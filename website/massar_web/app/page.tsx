import {
  ArrowRight,
  BadgeCheck,
  Camera,
  Compass,
  Download,
  Footprints,
  Gift,
  Languages,
  MapPinned,
  Route,
  ScanLine,
  Smartphone,
  Sparkles,
  WifiOff,
} from "lucide-react";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";

import AppBackdrop from "@/components/AppBackdrop";
import GlassSurface from "@/components/GlassSurface";
import { createClient } from "@/utils/supabase/server";

import styles from "./landing.module.css";

/**
 * The public front door: what Massar is, and the two ways into it.
 *
 * This is the one page a visitor with no account may see — see `isPublic` in
 * `proxy.ts` — which is why the signed-in home moved to `/home`. A landing page
 * behind a sign-in wall is a sign-in wall.
 *
 * It carries the brand on the duotone backdrop, the same ground the app gives
 * its first-run screens and the sign-in card, because like them it has no
 * content of its own to do the job.
 *
 * The copy is deliberately honest about the split between the two surfaces. A
 * browser cannot run the AR hunt, the quests or the camera, and a landing page
 * that implied otherwise would send people to the demo expecting the half of
 * the product it is missing.
 */

export const metadata: Metadata = {
  description:
    "An AI-guided tour companion for Algeria: routes built around your day, " +
    "a task at every stop, and 3D souvenirs that help rebuild the country's heritage.",
};

/**
 * Where "Download for Android" points.
 *
 * By default the release build itself, served from `public/`, so the button
 * hands over the APK rather than sending the visitor somewhere to look for it.
 * That file is gitignored — at 138 MB it is over GitHub's per-file limit — so a
 * deployment built from a clone needs either the file copied in alongside the
 * build or `NEXT_PUBLIC_APP_DOWNLOAD_URL` pointed at a hosted copy.
 */
const APK_URL = process.env.NEXT_PUBLIC_APP_DOWNLOAD_URL ?? "/app-release.apk";

/** Shown next to the button. Nobody on mobile data wants a 138 MB surprise. */
const APK_SIZE = "138 MB";

export default async function LandingPage() {
  // Not `requireSession`: that redirects, and this page exists precisely for
  // people who have nowhere to be redirected to. Somebody already signed in
  // should be sent onward to their routes rather than back through the form.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const webHref = user ? "/home" : "/login";
  const webLabel = user ? "Back to your routes" : "Continue in the browser";

  return (
    <AppBackdrop variant="duotone">
      <div className={styles.page}>
        <SiteHeader signedIn={Boolean(user)} />

        <main className={styles.main}>
          <Hero webHref={webHref} webLabel={webLabel} />
          <TheLoop />
          <Features />
          <Heritage />
          <TwoWaysIn webHref={webHref} webLabel={webLabel} signedIn={Boolean(user)} />
        </main>

        <SiteFooter />
      </div>
    </AppBackdrop>
  );
}

/* --- chrome --------------------------------------------------------------- */

function SiteHeader({ signedIn }: { signedIn: boolean }) {
  return (
    <header className={styles.siteHeader}>
      <span className={styles.wordmark}>
        <Image src="/logo.png" alt="" width={36} height={36} className={styles.mark} priority />
        <span className={styles.wordmarkText}>
          Massar
          {/* The Arabic reading of the name, not a translation of it. It sits
              beside the wordmark everywhere the brand does. */}
          <span className={styles.wordmarkArabic} lang="ar">
            مسار
          </span>
        </span>
      </span>
      <Link href={signedIn ? "/home" : "/login"} className={styles.headerLink}>
        {signedIn ? "Your routes" : "Sign in"}
        <ArrowRight size={15} aria-hidden />
      </Link>
    </header>
  );
}

function SiteFooter() {
  return (
    <footer className={styles.footer}>
      <p className={styles.footerLine}>
        Massar — an AI-guided tour companion for Algeria, and a way of rebuilding its
        heritage in 3D.
      </p>
      <p className={styles.footerMeta}>
        Submitted to AI Tour Algeria 2026 · Axis 01 — Dream · Ministry of Tourism and
        Handicrafts
      </p>
    </footer>
  );
}

/* --- hero ----------------------------------------------------------------- */

function Hero({ webHref, webLabel }: { webHref: string; webLabel: string }) {
  return (
    <section className={styles.hero}>
      <p className="sectionLabel">AN AI-GUIDED TOUR COMPANION FOR ALGERIA</p>
      <h1 className={styles.heroTitle}>
        Plan a route through Algeria, and follow it stop by stop.
      </h1>
      <p className={styles.heroLede}>
        Say where you are going, what you are in the mood for, and how long you have.
        Massar builds an ordered route through real places, gives you something to do at
        every stop, and turns what you photograph there into a 3D record of the
        country&rsquo;s heritage.
      </p>

      {/* The two ways in, at the top, before any argument for either. The
          long-form version of this choice — with what each surface can and
          cannot do — is at the bottom, once the page has earned the detail. */}
      <div className={styles.heroActions}>
        {/* `download` rather than a plain link: the APK is same-origin by
            default, so this saves it instead of letting the browser decide
            what to do with an unfamiliar type. It is inert when
            NEXT_PUBLIC_APP_DOWNLOAD_URL points somewhere else, which is
            correct — a cross-origin host owns that decision. */}
        <a className={`btn btn-primary ${styles.heroCta}`} href={APK_URL} download>
          <Download size={18} aria-hidden />
          Download for Android
        </a>
        <Link className={`btn btn-outline ${styles.heroCtaAlt}`} href={webHref}>
          <Compass size={18} aria-hidden />
          {webLabel}
        </Link>
      </div>
      <p className={styles.heroFootnote}>
        Android APK, {APK_SIZE}. One account across both — plan a route in the browser,
        and it is waiting on your phone when you get there.
      </p>
    </section>
  );
}

/* --- the loop ------------------------------------------------------------- */

const STEPS = [
  {
    icon: <Compass size={20} aria-hidden />,
    title: "Say what you want",
    body: "A city, a theme, a sentence in your own words, and how many days and hours you have.",
  },
  {
    icon: <Route size={20} aria-hidden />,
    title: "Get a route",
    body: "Ordered stops, drive legs between clusters and walk legs inside them. Swipe away the ones you do not want.",
  },
  {
    icon: <Footprints size={20} aria-hidden />,
    title: "Walk it",
    body: "A small task waits at every stop — and it only scores in full if you are actually standing there.",
  },
  {
    icon: <Camera size={20} aria-hidden />,
    title: "Raise your camera",
    body: "Catch the fennec hiding near the stop, or scan something in front of you into a 3D souvenir.",
  },
  {
    icon: <Sparkles size={20} aria-hidden />,
    title: "Rebuild the place",
    body: "Your footage trains a reconstruction of the site itself — and you are told when yours is what built it.",
  },
] as const;

function TheLoop() {
  return (
    <section className={styles.section}>
      <SectionHead
        label="HOW A DAY ON MASSAR GOES"
        title="Five steps, and the last one is the point"
      />
      <ol className={styles.steps}>
        {STEPS.map((step, index) => (
          <li key={step.title} className={styles.step}>
            {/* Numbered the way a stop on the route map is numbered — the
                sequence is the content here, not decoration on it. */}
            <span className={styles.stepBadge} aria-hidden>
              {index + 1}
            </span>
            <span className={styles.stepIcon} aria-hidden>
              {step.icon}
            </span>
            <h3 className={styles.stepTitle}>{step.title}</h3>
            <p className={styles.stepBody}>{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}

/* --- features ------------------------------------------------------------- */

/**
 * `tint` follows the app's onboarding: the planning half is the compass blue,
 * and everything you do with a camera in your hand is the warm amber.
 */
const FEATURES = [
  {
    icon: <Route size={20} aria-hidden />,
    tint: "cool",
    title: "Routes that fit the day",
    body: "One to four days, two to twelve hours each, on foot, by car, or both. Nobody plans a trip in minutes.",
  },
  {
    icon: <Sparkles size={20} aria-hidden />,
    tint: "cool",
    title: "Ask in your own words",
    body: "“Somewhere quiet with Ottoman architecture, not too much walking” becomes a route, not a page of search results.",
  },
  {
    icon: <BadgeCheck size={20} aria-hidden />,
    tint: "cool",
    title: "A task at every stop",
    body: "Photo, video or a fennec hunt, worth 30 points — checked against the stop's own checkpoint, so a catalogue of real places cannot be farmed from a sofa.",
  },
  {
    icon: <MapPinned size={20} aria-hidden />,
    tint: "warm",
    title: "An AR fennec at every stop",
    body: "Massar's mascot hides near each place. Distance is worked out on the device, so the hunt keeps running where there is no signal.",
  },
  {
    icon: <ScanLine size={20} aria-hidden />,
    tint: "warm",
    title: "Scan a souvenir into 3D",
    body: "Point the camera at something real and get a model back, filed in a folder you keep. The frame is checked before it costs any GPU time.",
  },
  {
    icon: <Gift size={20} aria-hidden />,
    tint: "warm",
    title: "Points worth spending",
    body: "What you earn on the route is spent on rewards from the places along it — and spending it never costs you your standing.",
  },
] as const;

const FACTS = [
  {
    icon: <Languages size={15} aria-hidden />,
    label: "English · Français · العربية, RTL throughout",
  },
  { icon: <WifiOff size={15} aria-hidden />, label: "Keeps working where there is no signal" },
  {
    icon: <Smartphone size={15} aria-hidden />,
    label: "Android and iOS, mid-range devices included",
  },
] as const;

function Features() {
  return (
    <section className={styles.section}>
      <SectionHead label="WHAT IT DOES" title="A guide, a game and a scanner in one pocket" />
      <div className={styles.featureGrid}>
        {FEATURES.map((feature) => (
          <GlassSurface key={feature.title} className={styles.feature}>
            <span className={styles.featureIcon} data-tint={feature.tint} aria-hidden>
              {feature.icon}
            </span>
            <h3 className={styles.featureTitle}>{feature.title}</h3>
            <p className={styles.featureBody}>{feature.body}</p>
          </GlassSurface>
        ))}
      </div>
      <ul className={styles.facts}>
        {FACTS.map((fact) => (
          <li key={fact.label} className={styles.fact}>
            <span className={styles.factIcon} aria-hidden>
              {fact.icon}
            </span>
            {fact.label}
          </li>
        ))}
      </ul>
    </section>
  );
}

/* --- heritage ------------------------------------------------------------- */

const PIPELINE = ["your video", "frames", "COLMAP SfM", "3D Gaussian splat"] as const;

function Heritage() {
  return (
    <section className={styles.section}>
      <div className={`${styles.heritage} onDark`}>
        <div className={styles.heritageCopy}>
          <p className="sectionLabel sectionLabel-onDark">WHY THE CAMERA MATTERS</p>
          <h2 className={styles.heritageTitle}>
            The tour and the heritage archive are the same product
          </h2>
          <p className={styles.heritageBody}>
            Everyone who films a slow pan at Djemila is contributing frames toward a
            photogrammetric reconstruction of Djemila. When that reconstruction is
            finished, Massar tells the traveller whose footage built it — with a link to
            the thing itself, turning in a browser.
          </p>
          <p className={styles.heritageBody}>
            That is the loop that makes Massar more than an itinerary app: the country
            gets a 3D record of its sites, built by the people who went to see them.
          </p>
        </div>
        <ol className={styles.pipeline} aria-label="Reconstruction pipeline">
          {PIPELINE.map((stage) => (
            <li key={stage} className={styles.pipelineStage}>
              <span className={styles.pipelineDot} aria-hidden />
              {stage}
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

/* --- the choice, in full -------------------------------------------------- */

const APP_HAS = [
  { has: true, label: "Route planning and the full itinerary" },
  { has: true, label: "A task at every stop, and the points for it" },
  { has: true, label: "The AR fennec hunt" },
  { has: true, label: "The camera, and 3D souvenirs from it" },
  { has: true, label: "Rewards, and everything that spends points" },
] as const;

const WEB_HAS = [
  { has: true, label: "Route planning, against the same engine" },
  { has: true, label: "The itinerary, its map and every stop on it" },
  { has: true, label: "Every route you have generated, on any device" },
  { has: false, label: "No quests or points — they are scored where you stand" },
  { has: false, label: "No AR hunt and no camera — those need a phone in a place" },
] as const;

function TwoWaysIn({
  webHref,
  webLabel,
  signedIn,
}: {
  webHref: string;
  webLabel: string;
  signedIn: boolean;
}) {
  return (
    <section className={styles.section} id="get-massar">
      <SectionHead label="TWO WAYS IN" title="Take the app, or try it here first" />
      <div className={styles.ways}>
        {/* The filled card is the app, not because the demo is an afterthought
            but because it is the whole product — the browser has the planning
            half by design, and saying so is more use than implying parity. */}
        <div className={`${styles.way} ${styles.wayApp} onDark`}>
          <span className={styles.wayIcon} aria-hidden>
            <Smartphone size={20} />
          </span>
          <h3 className={styles.wayTitle}>The Android app</h3>
          <p className={styles.wayLede}>
            The whole thing, for the traveller who is actually there.
          </p>
          <WayList items={APP_HAS} onDark />
          <a
            className={`btn btn-onDark btn-block ${styles.wayCta}`}
            href={APK_URL}
            download
          >
            <Download size={18} aria-hidden />
            Download for Android
          </a>
          <p className={`${styles.wayFootnote} ${styles.wayFootnoteOnDark}`}>
            APK, {APK_SIZE}. Android 7 and up — you may need to allow installs from
            your browser.
          </p>
        </div>

        <GlassSurface className={styles.way}>
          <span className={`${styles.wayIcon} ${styles.wayIconWeb}`} aria-hidden>
            <Compass size={20} />
          </span>
          <h3 className={styles.wayTitle}>This browser demo</h3>
          <p className={styles.wayLede}>
            The planning half, with nothing to install — for before the trip, and for
            anyone who wants to see it work first.
          </p>
          <WayList items={WEB_HAS} />
          <Link className={`btn btn-primary btn-block ${styles.wayCta}`} href={webHref}>
            {webLabel}
            <ArrowRight size={18} aria-hidden />
          </Link>
          <p className={styles.wayFootnote}>
            {signedIn
              ? "You are already signed in — this goes straight to your routes."
              : "Takes an email and a password. The same account signs you into the app."}
          </p>
        </GlassSurface>
      </div>
    </section>
  );
}

function WayList({
  items,
  onDark = false,
}: {
  items: readonly { has: boolean; label: string }[];
  onDark?: boolean;
}) {
  return (
    <ul className={styles.wayList}>
      {items.map((item) => (
        <li key={item.label} className={styles.wayItem} data-has={item.has}>
          {/* A dash rather than a cross: what the browser leaves out is a
              deliberate boundary, not a fault in it. */}
          <span className={styles.wayBullet} aria-hidden>
            {item.has ? <BadgeCheck size={16} /> : "—"}
          </span>
          <span className={onDark ? styles.wayLabelOnDark : styles.wayLabel}>
            {item.label}
          </span>
        </li>
      ))}
    </ul>
  );
}

/* --- shared --------------------------------------------------------------- */

function SectionHead({ label, title }: { label: string; title: ReactNode }) {
  return (
    <div className={styles.sectionHead}>
      <p className="sectionLabel">{label}</p>
      <h2 className={styles.sectionTitle}>{title}</h2>
    </div>
  );
}
