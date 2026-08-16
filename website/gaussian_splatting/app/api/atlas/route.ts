import { NextResponse } from "next/server";

import { buildAtlas } from "@/lib/atlas";
import { SUPABASE_HINT, supabaseConfigured } from "@/lib/supabase";

export const dynamic = "force-dynamic";

export async function GET() {
  const atlas = await buildAtlas();
  return NextResponse.json({
    ...atlas,
    hint: supabaseConfigured() ? undefined : SUPABASE_HINT,
  });
}
