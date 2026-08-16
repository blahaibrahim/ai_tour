import { NextResponse } from "next/server";

import { poiDetail } from "@/lib/atlas";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  if (!UUID.test(id)) {
    return NextResponse.json({ error: "bad poi id" }, { status: 400 });
  }
  return NextResponse.json(await poiDetail(id));
}
