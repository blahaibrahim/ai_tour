import { NextResponse } from "next/server";

import { cancelJob, getJob } from "@/lib/jobs";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const job = getJob((await params).id);
  if (!job) return NextResponse.json({ error: "no such job" }, { status: 404 });
  return NextResponse.json({ job });
}

/** Cancel. Only meaningful while a job is queued or running. */
export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const canceled = cancelJob((await params).id);
  if (!canceled) {
    return NextResponse.json(
      { error: "job is not running" },
      { status: 409 },
    );
  }
  return NextResponse.json({ ok: true });
}
