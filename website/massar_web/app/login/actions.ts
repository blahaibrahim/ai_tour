"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/utils/supabase/server";

/**
 * Sign-in and sign-up.
 *
 * Both end in a `redirect`, which throws a control-flow signal Next catches —
 * so neither may be wrapped in a `try`, and the error paths return by
 * redirecting back to the form with a message rather than by rethrowing.
 */

export async function login(formData: FormData) {
  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword({
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
  });

  if (error) {
    redirect(`/login?mode=login&message=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/", "layout");
  redirect("/");
}

export async function signup(formData: FormData) {
  const supabase = await createClient();

  const { data, error } = await supabase.auth.signUp({
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
  });

  if (error) {
    redirect(`/login?mode=signup&message=${encodeURIComponent(error.message)}`);
  }

  // With email confirmation on, `signUp` succeeds without a session: the
  // account exists but nobody is signed in yet. Saying so is the honest
  // outcome — redirecting to a home page that would bounce straight back here
  // reads as the sign-up having silently failed.
  if (!data.session) {
    redirect(
      `/login?mode=login&notice=${encodeURIComponent(
        "Check your inbox to confirm the address, then sign in.",
      )}`,
    );
  }

  revalidatePath("/", "layout");
  redirect("/");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/login");
}
