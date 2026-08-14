import { NextResponse } from "next/server";

import { sceneStatus } from "@/lib/volume";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ scene: string }> },
) {
  const { scene } = await params;
  if (!/^[a-z0-9_-]+$/.test(scene)) {
    return NextResponse.json({ error: "bad scene name" }, { status: 400 });
  }
  return NextResponse.json(await sceneStatus(scene));
}
