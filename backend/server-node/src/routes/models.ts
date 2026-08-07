import { Router } from "express";

import { ConfigurationError, requireModalKeys } from "../config";
import { getUserClient } from "../data/supabaseClient";
import { parseJson, request } from "../http";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { bearerToken } from "../rateLimit";
import { unwrap, unwrapRows } from "../supabase";
import { asyncHandler } from "./asyncHandler";

export const modelsRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHA256_RE = /^[a-f0-9]{64}$/;

modelsRouter.post(
  "/api/models/generate",
  asyncHandler(async (req, res) => {
    const jwt = bearerToken(req);
    if (jwt === null) {
      return res.status(401).json({ error: "unauthorized" });
    }

    const userClient = getUserClient(jwt);

    let user;
    try {
      const { data, error } = await userClient.auth.getUser(jwt);
      if (error) throw error;
      user = data.user;
    } catch {
      return res.status(401).json({ error: "unauthorized" });
    }

    if (!user) {
      return res.status(401).json({ error: "unauthorized" });
    }

    const data = (req.body ?? {}) as Record<string, unknown>;
    const artifactId = data.artifact_id;
    const imagePath = typeof data.image_path === "string" ? data.image_path : "";
    const imageSha256 = typeof data.image_sha256 === "string" ? data.image_sha256 : "";

    if (!imagePath || !imagePath.startsWith(`captures/${user.id}/`)) {
      return res.status(403).json({ error: "forbidden_path" });
    }

    if (!imageSha256 || !SHA256_RE.test(imageSha256)) {
      return res.status(400).json({ error: "bad_request" });
    }

    // artifact_id lands in model_jobs.artifact_id, a uuid column with a foreign
    // key to artifacts.id. Validating it here turns what was an opaque 500 (the
    // insert below failing on a malformed id, after a credit had already been
    // consumed) into a clear 400.
    if (!artifactId || !UUID_RE.test(String(artifactId).toLowerCase())) {
      return res.status(400).json({ error: "bad_artifact_id" });
    }

    const admin = getAdminClient();
    const refund = (): Promise<unknown> =>
      unwrap(admin.rpc("refund_model_credit", { p_user: user.id })).catch(() => null);

    // --- check rate limit ---
    const allowed = await unwrap(
      admin.rpc("check_rate_limit", {
        p_user: user.id,
        p_action: "generate_3d",
        p_max: 20,
        p_window: "1 day",
      }),
    );
    if (!allowed) {
      return res.status(429).json({ error: "rate_limit_exceeded" });
    }

    // --- quota (atomic) ---
    const consumed = await unwrap(admin.rpc("consume_model_credit", { p_user: user.id }));
    if (!consumed) {
      return res.status(429).json({ error: "quota_exceeded" });
    }

    // --- dedupe ---
    const hit = await unwrapRows<{ output_path: string }>(
      admin
        .from("model_jobs")
        .select("output_path")
        .eq("input_sha256", imageSha256)
        .eq("status", "succeeded")
        .limit(1),
    );
    if (hit.length > 0) {
      await refund();
      const cachedOutput = hit[0].output_path;
      await unwrap(
        admin.from("artifacts").update({ model_path: cachedOutput }).eq("id", artifactId),
      );
      return res.status(200).json({ cached: true, output_path: cachedOutput });
    }

    // --- create the job ---
    // The client inserts its own artifacts row (RLS "own artifacts") before
    // calling this, so a missing row means the two got out of sync rather than
    // a transient fault — report it instead of failing the FK insert blind.
    const owner = await unwrapRows<{ id: string }>(
      admin.from("artifacts").select("id").eq("id", artifactId).eq("user_id", user.id).limit(1),
    );
    if (owner.length === 0) {
      await refund();
      return res.status(404).json({ error: "artifact_not_found" });
    }

    // `.select()` is required here: supabase-js returns no rows from an insert
    // without it, where supabase-py returned them by default.
    let jobRows: Array<{ id: string }>;
    try {
      jobRows = await unwrapRows<{ id: string }>(
        admin
          .from("model_jobs")
          .insert({
            user_id: user.id,
            artifact_id: artifactId,
            input_path: imagePath,
            input_sha256: imageSha256,
            status: "queued",
          })
          .select("id"),
      );
    } catch {
      await refund();
      return res.status(500).json({ error: "internal_error" });
    }

    if (jobRows.length === 0) {
      await refund();
      return res.status(500).json({ error: "internal_error" });
    }

    const jobId = jobRows[0].id;

    // --- hand off to Modal ---
    const storagePath = imagePath.replace("captures/", "");

    let signedUrl: string | undefined;
    try {
      const { data: signed, error } = await admin.storage
        .from("captures")
        .createSignedUrl(storagePath, 600);
      if (error) throw error;
      signedUrl = signed?.signedUrl;
    } catch {
      await refund();
      return res.status(400).json({ error: "image_not_found" });
    }

    if (!signedUrl) {
      await refund();
      await unwrap(
        admin
          .from("model_jobs")
          .update({ status: "failed", error_code: "sign_failed" })
          .eq("id", jobId),
      );
      return res.status(503).json({ error: "upstream_unavailable" });
    }

    let modalKey: string;
    let modalSecret: string;
    let modalSubmitUrl: string;
    try {
      [modalKey, modalSecret, modalSubmitUrl] = requireModalKeys();
    } catch (error) {
      if (!(error instanceof ConfigurationError)) throw error;
      // Misconfiguration, not the user's fault — fail the job explicitly and
      // give the credit back rather than raising an opaque 500 with a row
      // left in `queued` for the reconcile cron to time out 20 minutes later.
      await unwrap(
        admin.from("model_jobs").update({ status: "failed", error_code: "internal" }).eq("id", jobId),
      );
      await refund();
      return res.status(503).json({ error: "not_configured" });
    }

    let modalResponse: Response;
    try {
      modalResponse = await request(modalSubmitUrl, {
        method: "POST",
        json: { job_id: jobId, image_url: signedUrl, input_path: imagePath },
        headers: {
          Authorization: `Bearer ${modalSecret}`,
          "Modal-Key": modalKey,
          "Modal-Secret": modalSecret,
        },
        timeoutMs: 10_000,
      });
    } catch {
      await unwrap(
        admin.from("model_jobs").update({ status: "failed", error_code: "internal" }).eq("id", jobId),
      );
      await refund();
      return res.status(503).json({ error: "upstream_unavailable" });
    }

    if (!modalResponse.ok) {
      // error_code is surfaced to the client, which only has copy for the
      // four codes in modelFailureMessages — the HTTP status stays in the
      // response body for debugging rather than in the job row.
      const details = await modalResponse.text().catch(() => "");
      await unwrap(
        admin.from("model_jobs").update({ status: "failed", error_code: "internal" }).eq("id", jobId),
      );
      await refund();
      return res.status(modalResponse.status).json({ error: "upstream_error", details });
    }

    let callId: string | null = null;
    try {
      const parsed = await parseJson<{ call_id?: string }>(modalResponse, modalSubmitUrl);
      callId = parsed.call_id ?? null;
    } catch {
      callId = null;
    }

    // Only advance `queued -> processing`. The Modal worker sets `processing`
    // itself and may already have finished by the time this line runs (a warm
    // container with a cached mesh is fast); an unguarded write would drag a
    // succeeded job back to processing and strand it there.
    await unwrap(
      admin
        .from("model_jobs")
        .update({ modal_call_id: callId, status: "processing" })
        .eq("id", jobId)
        .eq("status", "queued"),
    );

    return res.status(200).json({ job_id: jobId });
  }),
);
