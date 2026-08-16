import { NextResponse } from "next/server";

import { buildAnalytics } from "@/lib/analytics";
import { SUPABASE_HINT, supabaseConfigured } from "@/lib/supabase";

export const dynamic = "force-dynamic";

export async function GET() {
  const analytics = await buildAnalytics();
  return NextResponse.json({
    ...analytics,
    hint: supabaseConfigured() ? undefined : SUPABASE_HINT,
  });
}
