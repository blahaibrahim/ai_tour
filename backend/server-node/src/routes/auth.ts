import { Router } from "express";

import { getUserClient } from "../data/supabaseClient";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { bearerToken } from "../rateLimit";
import { asyncHandler } from "./asyncHandler";

export const authRouter = Router();

authRouter.post(
  "/api/auth/delete-account",
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

    const admin = getAdminClient();

    try {
      // Delete the user's storage objects inside captures/ and models/.
      // `list()` is not fully recursive, but the path structure is strictly
      // {uid}/{id}.jpg so one level is all there is.
      for (const bucket of ["captures", "models", "thumbnails"]) {
        const { data: files, error } = await admin.storage.from(bucket).list(user.id);
        if (error) throw error;
        if (files && files.length > 0) {
          const filePaths = files
            .filter((f) => f.name !== ".emptyFolderPlaceholder")
            .map((f) => `${user.id}/${f.name}`);
          if (filePaths.length > 0) {
            await admin.storage.from(bucket).remove(filePaths);
          }
        }
      }
    } catch (error) {
      console.error(`Failed to delete storage objects for user ${user.id}: ${error}`);
      // Proceed with account deletion even if storage fails;
      // the orphan purge cron will catch them.
    }

    try {
      // Deleting the user cascades to public.profiles and related user-scoped tables
      const { error } = await admin.auth.admin.deleteUser(user.id);
      if (error) throw error;
    } catch (error) {
      console.error(`Failed to delete auth user ${user.id}: ${error}`);
      return res.status(500).json({ error: "deletion_failed" });
    }

    // Flask returned `jsonify({}), 204`; a 204 carries no body either way.
    return res.status(204).end();
  }),
);
