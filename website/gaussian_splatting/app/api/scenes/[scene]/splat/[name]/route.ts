import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import { Readable } from "node:stream";

import { NextResponse } from "next/server";

import { cachedSplatPath, fetchSplat } from "@/lib/volume";

export const dynamic = "force-dynamic";

const SCENE = /^[a-z0-9_-]+$/;
// The trainer's own naming: point_cloud_<step>.ply. Anything else is not
// something this route should be pulling out of the Volume.
const PLY = /^[a-z0-9_.-]+\.ply$/i;

function validate(scene: string, name: string): string | null {
  if (!SCENE.test(scene)) return "bad scene name";
  if (!PLY.test(name) || name.includes("..")) return "bad ply name";
  return null;
}

/** Serve a `.ply` that has already been fetched, for the viewer to load. */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ scene: string; name: string }> },
) {
  const { scene, name } = await params;
  const bad = validate(scene, name);
  if (bad) return NextResponse.json({ error: bad }, { status: 400 });

  const local = cachedSplatPath(scene, name);
  let size: number;
  try {
    size = (await fs.stat(local)).size;
  } catch {
    return NextResponse.json(
      { error: "not fetched yet — POST to this URL first" },
      { status: 404 },
    );
  }

  const stream = Readable.toWeb(
    createReadStream(local),
  ) as unknown as ReadableStream;

  return new Response(stream, {
    headers: {
      "content-type": "application/octet-stream",
      "content-length": String(size),
      // The file is immutable once written: the trainer names each export
      // after the step it came from, so a given name never changes content.
      "cache-control": "private, max-age=31536000, immutable",
    },
  });
}

/**
 * Pull the `.ply` down from the Modal Volume.
 *
 * Separate from the GET on purpose — this one can take minutes and costs
 * bandwidth, so it happens when the operator asks for it, not when a card
 * renders.
 */
export async function POST(
  _request: Request,
  { params }: { params: Promise<{ scene: string; name: string }> },
) {
  const { scene, name } = await params;
  const bad = validate(scene, name);
  if (bad) return NextResponse.json({ error: bad }, { status: 400 });

  try {
    const local = await fetchSplat(scene, name);
    const { size } = await fs.stat(local);
    return NextResponse.json({ ok: true, bytes: size });
  } catch (err) {
    return NextResponse.json({ error: (err as Error).message }, { status: 502 });
  }
}
