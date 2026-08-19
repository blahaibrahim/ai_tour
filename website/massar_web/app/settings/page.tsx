import { ChevronLeft, LogOut, Mail, Star } from "lucide-react";
import Link from "next/link";

import AppBackdrop from "@/components/AppBackdrop";
import { requireSession } from "@/lib/api";
import { createClient } from "@/utils/supabase/server";

import { signOut } from "../login/actions";
import LeaveTourRow from "./LeaveTourRow";
import styles from "./settings.module.css";

/**
 * Who the traveller is, what they have scored, and the way out.
 *
 * Every row here does something. The app's settings screen used to carry four
 * that did not — Offline Maps, Language, Help Center, Privacy Policy, each with
 * an empty tap handler — and a settings page where half the rows are inert
 * teaches people that none of them are worth pressing, which costs more than
 * the placeholders were worth. Each goes back at the point it does something.
 */
export default async function SettingsPage() {
  const session = await requireSession();
  const points = await fetchLifetimePoints();

  return (
    <AppBackdrop>
      <main className={styles.page}>
        <header className={styles.header}>
          <Link href="/home" className={styles.back} aria-label="Back">
            <ChevronLeft size={20} aria-hidden />
          </Link>
          <h1 className={styles.title}>Settings</h1>
        </header>

        <section className={styles.section}>
          <h2 className="sectionLabel">ACCOUNT</h2>
          <div className={styles.group}>
            <div className={styles.row}>
              <Mail size={20} aria-hidden className={styles.rowIcon} />
              <div className={styles.rowCopy}>
                <p className={styles.rowTitle}>{session.email ?? "Signed in"}</p>
                <p className={styles.rowSubtitle}>
                  Your routes and points follow this account
                </p>
              </div>
            </div>

            <div className={styles.row}>
              <Star size={20} aria-hidden className={styles.rowIcon} />
              <div className={styles.rowCopy}>
                <p className={styles.rowTitle}>Total points</p>
                <p className={styles.rowSubtitle}>
                  {/* Null is "not synced yet", which is not the same fact as
                      zero — hence the dash rather than a 0. */}
                  {points === null
                    ? "Syncing…"
                    : "Earned across every tour, in the app"}
                </p>
              </div>
              <span className={styles.rowValue}>{points ?? "—"}</span>
            </div>

            <form action={signOut}>
              <button type="submit" className={`${styles.row} ${styles.rowButton}`}>
                <LogOut size={20} aria-hidden className={styles.rowIcon} />
                <span className={styles.rowTitle}>Sign out</span>
              </button>
            </form>
          </div>
        </section>

        <section className={styles.section}>
          <h2 className="sectionLabel">THIS BROWSER</h2>
          <div className={styles.group}>
            <LeaveTourRow />
          </div>
        </section>

        <section className={styles.section}>
          <h2 className="sectionLabel">ABOUT</h2>
          <div className={styles.group}>
            <div className={styles.row}>
              <div className={styles.rowCopy}>
                <p className={styles.rowTitle}>What this is</p>
                <p className={styles.rowSubtitle}>
                  The web half of Massar: plan a route and follow it. Quests, the
                  camera and the 3D captures live in the phone app.
                </p>
              </div>
            </div>
          </div>
        </section>

        <p className={styles.version}>Massar Web v1.0.0</p>
      </main>
    </AppBackdrop>
  );
}

/** The lifetime score from `profiles`, the same figure the app's account
 *  section shows. Null on any failure — see the dash above. */
async function fetchLifetimePoints(): Promise<number | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("profiles").select("total_points").maybeSingle();
  const total = (data as { total_points?: number } | null)?.total_points;
  return typeof total === "number" ? total : null;
}
