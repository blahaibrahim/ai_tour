import fs from "node:fs/promises";

import { NextResponse } from "next/server";

import { DEFAULT_TARGET_POINTS, decimatePly } from "@/lib/mobileSplat";
import { NOTIFY_HINT, notifyConfigured, notifyContributor, uploadSplat } from "@/lib/publish";
import { cachedSplatPath } from "@/lib/volume";

export const dynamic = "force-dynamic";

/**
 * Publish a trained splat to the app, and tell the contributor it exists.
 *
 * One endpoint rather than two, because half of it is not a state anybody wants
 * to be in: an uploaded scene nobody was told about is invisible, and a
 * notification pointing at an object that was never uploaded is a dead end. So
 * the upload happens first and the notification only if it succeeded.
 *
 * It is deliberately *not* idempotent-by-accident. The storage key is derived
 * from the scene and the point cloud, so publishing the same scene twice
 * overwrites the object; the backend dedupes the notification on that same key,
 * so the second press re-uploads a better decimation without filing a second
 * copy of the news. Pressing the button again is how you fix a bad upload.
 */
export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const str = (key: string) =>
    typeof body[key] === "string" ? (body[key] as string).trim() : "";

  const scene = str("scene");
  const ply = str("ply");
  const email = str("email").toLowerCase();
  const sceneTitle = str("sceneTitle") || scene;
  const poiId = str("poiId") || null;

  // The same patterns the splat routes validate against — these two become a
  // filesystem path below, and a storage key after that.
  if (!/^[a-z0-9_-]+$/.test(scene)) {
    return NextResponse.json({ error: "bad scene name" }, { status: 400 });
  }
  if (!/^[a-z0-9_.-]+\.ply$/i.test(ply) || ply.includes("..")) {
    return NextResponse.json({ error: "bad ply name" }, { status: 400 });
  }
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return NextResponse.json(
      { error: "a contributor email is required" },
      { status: 400 },
    );
  }
  // Checked before the decimation rather than after, because decimating 468 MB
  // takes long enough that finding out the secret is missing at the end of it
  // would be a genuinely annoying way to learn.
  if (!notifyConfigured()) {
    return NextResponse.json({ error: NOTIFY_HINT }, { status: 503 });
  }

  const local = cachedSplatPath(scene, ply);
  try {
    await fs.stat(local);
  } catch {
    return NextResponse.json(
      { error: `${ply} is not fetched yet — fetch it before publishing` },
      { status: 409 },
    );
  }

  try {
    const decimated = await decimatePly(local, DEFAULT_TARGET_POINTS);
    // `.splatb` beside the `.ply`'s own name, so the object says which export it
    // came from — a scene retrained to 30k steps publishes as a different file
    // and reads as a different notification.
    const splatPath = await uploadSplat(
      `${scene}/${ply.replace(/\.ply$/i, "")}.splatb`,
      decimated.bytes,
    );

    const notified = await notifyContributor({
      email,
      scene,
      sceneTitle,
      splatPath,
      gaussians: decimated.count,
      poiId,
    });

    return NextResponse.json({
      splatPath,
      gaussians: decimated.count,
      source: decimated.source,
      bytes: decimated.bytes.length,
      ...notified,
    });
  } catch (err) {
    const message = (err as Error).message;
    // A mistyped contributor is the operator's own input, not a bad gateway.
    // Everything else that reaches here really is the far end failing — the
    // Volume, Storage, or the backend.
    const status = message.startsWith("no_such_user") ? 404 : 502;
    return NextResponse.json({ error: message }, { status });
  }
}
