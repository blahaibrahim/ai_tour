import { NextResponse } from "next/server";

import { VIDEO_DIR } from "@/lib/config";
import { listVideos } from "@/lib/videos";

export const dynamic = "force-dynamic";

export async function GET() {
  const videos = await listVideos();
  return NextResponse.json({ videos, videoDir: VIDEO_DIR });
}
