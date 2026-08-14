import { NextResponse } from "next/server";

import { createJob, listJobs } from "@/lib/jobs";
import {
  QUALITIES,
  SCENE_TYPES,
  STAGES,
  type Quality,
  type SceneType,
  type Stage,
} from "@/lib/pipeline";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({ jobs: listJobs() });
}

export async function POST(request: Request) {
  const body = (await request.json()) as Record<string, unknown>;

  const video = typeof body.video === "string" ? body.video : "";
  const sceneType = body.sceneType as SceneType;
  const quality = body.quality as Quality;
  const stage = body.stage as Stage;

  if (!video) {
    return NextResponse.json({ error: "video is required" }, { status: 400 });
  }
  if (!SCENE_TYPES.includes(sceneType) || !QUALITIES.includes(quality) || !STAGES.includes(stage)) {
    return NextResponse.json({ error: "unknown scene, quality or stage" }, { status: 400 });
  }

  try {
    const job = await createJob({
      video,
      sceneType,
      quality,
      stage,
      force: body.force === true,
      reupload: body.reupload === true,
    });
    return NextResponse.json({ job }, { status: 201 });
  } catch (err) {
    return NextResponse.json({ error: (err as Error).message }, { status: 409 });
  }
}
