import { NextResponse } from "next/server";

import { assign, readAssignments } from "@/lib/assignments";
import { resolveVideo } from "@/lib/videos";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET() {
  return NextResponse.json(await readAssignments());
}

/**
 * Attach a clip or an app capture to a POI, or detach it with `poiId: null`.
 *
 * The only write this dashboard does, and it writes to a local JSON file, not
 * to Supabase — see `lib/assignments.ts` for why the link isn't a column yet.
 */
export async function POST(request: Request) {
  const body = (await request.json()) as Record<string, unknown>;

  const kind = body.kind === "artifacts" ? "artifacts" : "clips";
  const key = typeof body.key === "string" ? body.key : "";
  const poiId = typeof body.poiId === "string" ? body.poiId : null;

  if (!key) {
    return NextResponse.json({ error: "key is required" }, { status: 400 });
  }
  if (poiId && !UUID.test(poiId)) {
    return NextResponse.json({ error: "poiId must be a uuid" }, { status: 400 });
  }
  // A clip key is a filename that later becomes a Volume path and a CLI
  // argument, so it is checked against the actual listing rather than a
  // pattern — the same membership test `lib/videos.ts` uses.
  if (kind === "clips" && !(await resolveVideo(key))) {
    return NextResponse.json({ error: `no such clip: ${key}` }, { status: 400 });
  }
  if (kind === "artifacts" && !UUID.test(key)) {
    return NextResponse.json(
      { error: "artifact key must be a uuid" },
      { status: 400 },
    );
  }

  try {
    return NextResponse.json(await assign(kind, key, poiId));
  } catch (err) {
    return NextResponse.json({ error: (err as Error).message }, { status: 500 });
  }
}
