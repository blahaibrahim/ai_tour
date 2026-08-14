import { NextResponse } from "next/server";

import { VOLUME_NAME } from "@/lib/config";
import { overview } from "@/lib/volume";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({ volume: VOLUME_NAME, ...(await overview()) });
}
