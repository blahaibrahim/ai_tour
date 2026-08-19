import { AlertCircle, Info } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

import AppBackdrop from "@/components/AppBackdrop";

import { login, signup } from "./actions";
import styles from "./login.module.css";

type Mode = "login" | "signup";

/**
 * Sign-in and sign-up, on the duotone backdrop the app gives its first-run
 * screens — the one page with no content of its own to carry the brand.
 *
 * The mode is a URL parameter rather than component state, so the whole page
 * stays a Server Component and a failed submit can come back to the tab it was
 * sent from. The app's `AuthScreen` opens on sign-up for the same reason it
 * does here: almost everybody who reaches this page has no account yet.
 */
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ mode?: string; message?: string; notice?: string }>;
}) {
  const params = await searchParams;
  const mode: Mode = params.mode === "login" ? "login" : "signup";
  const isSignup = mode === "signup";

  return (
    <AppBackdrop variant="duotone">
      <main className={styles.page}>
        <section className={styles.card}>
          <header className={styles.header}>
            <Image src="/logo.png" alt="" width={56} height={56} className={styles.mark} priority />
            <h1 className={styles.title}>Massar</h1>
            <p className={styles.tagline}>
              Plan a route through Algeria, and follow it stop by stop.
            </p>
          </header>

          {/* A bounded track with the active side filled in — the web twin of
              the app's segmented control, for a choice that is two, fixed and
              exclusive. */}
          <nav className={styles.tabs} aria-label="Account">
            <Link
              href="/login?mode=signup"
              className={styles.tab}
              data-active={isSignup}
              aria-current={isSignup ? "page" : undefined}
            >
              Create account
            </Link>
            <Link
              href="/login?mode=login"
              className={styles.tab}
              data-active={!isSignup}
              aria-current={!isSignup ? "page" : undefined}
            >
              Sign in
            </Link>
          </nav>

          {params.message ? (
            <p className={`${styles.banner} ${styles.error}`} role="alert">
              <AlertCircle size={16} aria-hidden />
              {params.message}
            </p>
          ) : null}

          {params.notice ? (
            <p className={`${styles.banner} ${styles.notice}`}>
              <Info size={16} aria-hidden />
              {params.notice}
            </p>
          ) : null}

          <form className={styles.form}>
            <label className={styles.field}>
              <span className={styles.label}>Email</span>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                required
                className="input-field"
                placeholder="you@example.com"
              />
            </label>

            <label className={styles.field}>
              <span className={styles.label}>Password</span>
              <input
                id="password"
                name="password"
                type="password"
                required
                minLength={6}
                autoComplete={isSignup ? "new-password" : "current-password"}
                className="input-field"
                placeholder={isSignup ? "At least 6 characters" : "Your password"}
              />
            </label>

            <button
              type="submit"
              formAction={isSignup ? signup : login}
              className="btn btn-primary btn-block"
            >
              {isSignup ? "Create account" : "Sign in"}
            </button>
          </form>

          <p className={styles.footnote}>
            The account is the same one the Massar app uses — sign in here and your routes
            follow you between the two.
          </p>
        </section>
      </main>
    </AppBackdrop>
  );
}
