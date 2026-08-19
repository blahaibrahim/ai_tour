"use client";

import { ChevronLeft, ChevronUp, MousePointerClick, Search, X } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

import AppBackdrop from "@/components/AppBackdrop";
import CompassSpinner from "@/components/CompassSpinner";
import GlassSurface from "@/components/GlassSurface";
import Notice from "@/components/Notice";
import TimeBudgetPicker, {
  HOURS_PER_DAY_OPTIONS,
  TRIP_DAY_OPTIONS,
} from "@/components/TimeBudgetPicker";
import WilayaMap from "@/components/WilayaMap";
import { formatMinutes, messageForCode } from "@/lib/format";
import type { City, GeneratedRoute, PromptInterpretation, RouteTheme } from "@/lib/types";
import { ApiError, apiFetch } from "@/utils/apiFetch";

import styles from "./generate.module.css";

/** The app's own defaults, from `AppState`. */
const DEFAULT_TRIP_DAYS = TRIP_DAY_OPTIONS[0];
const DEFAULT_HOURS_PER_DAY = HOURS_PER_DAY_OPTIONS[2];

/** Bounds the interpreter's cost, and matches the server's own validation. */
const MAX_PROMPT_LENGTH = 280;

/**
 * The route request builder, docked over the map.
 *
 * The panel is collapsed by default and deliberately short, because the
 * decision it exists to serve — *which part of the country* — is made on the
 * map behind it, and a sheet tall enough to hold every control covers the thing
 * the traveller is being asked to point at.
 *
 * Time budget and prompt live one click away rather than being cut. Both have
 * working defaults, so somebody who does not care never opens the drawer; the
 * collapsed state summarises them ("2 days · 4h · quiet Roman ruins") so what
 * is hidden is never a mystery.
 */
export default function GeneratePlanner({
  cities,
  themes,
}: {
  cities: City[];
  themes: RouteTheme[];
}) {
  const router = useRouter();

  const [cityId, setCityId] = useState<string | null>(null);
  // Narrowed theme lists, kept per city. A cache rather than a single slot, so
  // going back to a city already looked at does not spend a round trip
  // re-learning the same answer.
  const [narrowed, setNarrowed] = useState<Record<string, RouteTheme[]>>({});
  const [tripDays, setTripDays] = useState(DEFAULT_TRIP_DAYS);
  const [hoursPerDay, setHoursPerDay] = useState(DEFAULT_HOURS_PER_DAY);
  const [prompt, setPrompt] = useState("");
  const [expanded, setExpanded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Cancelling has to actually cancel. Dropping the waiting screen while the
  // request stayed in flight would land the traveller back on the map and then
  // navigate them away from it seconds later, which is worse than no cancel
  // button at all.
  const inFlight = useRef<AbortController | null>(null);

  const city = useMemo(() => cities.find((c) => c.id === cityId) ?? null, [cities, cityId]);

  /**
   * The themes this city can actually answer.
   *
   * A theme whose categories hold no published POI there is not offered, rather
   * than offered and then refused with a 422 — which matters more here than it
   * looks, because the planner has no theme picker: the first entry in this
   * list is the request's fallback when the prompt says nothing useful.
   *
   * Derived, not stored. Until a city is chosen — and while its narrowed list
   * is still on the wire — the union across every city is the right answer, so
   * it is the fallback rather than something an effect has to put back.
   */
  const cityThemes = cityId ? (narrowed[cityId] ?? themes) : themes;

  useEffect(() => {
    if (!cityId || narrowed[cityId]) return;

    let live = true;
    void apiFetch<{ themes: RouteTheme[] }>(`/api/categories?city_id=${cityId}`)
      .then((data) => {
        if (live) setNarrowed((cache) => ({ ...cache, [cityId]: data.themes ?? [] }));
      })
      .catch(() => {
        // Leave the union in place: a narrower list is an improvement, not a
        // precondition, and the server validates the theme anyway.
      });
    return () => {
      live = false;
    };
  }, [cityId, narrowed]);

  const canGenerate = city !== null && cityThemes.length > 0 && !busy;

  async function generate() {
    if (!city || cityThemes.length === 0) return;

    const controller = new AbortController();
    inFlight.current = controller;
    setBusy(true);
    setError(null);

    try {
      let theme = cityThemes[0].key;
      let preferredCategoryKeys: string[] = [];

      // Reading the description is part of pressing the button, not a separate
      // step to remember. There is no submit affordance on the field itself, so
      // an uninterpreted prompt would otherwise be silently discarded and the
      // route built from the fallback theme.
      const typed = prompt.trim();
      if (typed.length > 0) {
        const interpretation = await apiFetch<PromptInterpretation>("/api/routes/interpret", {
          method: "POST",
          signal: controller.signal,
          body: JSON.stringify({ prompt: typed, city_id: city.id, theme, locale: "en" }),
        }).catch((caught) => {
          if (caught instanceof DOMException && caught.name === "AbortError") throw caught;
          // Every other failure is the same answer as an unreadable prompt:
          // the route still generates, just from the fallback theme.
          return null;
        });

        if (interpretation?.understood) {
          // A theme the interpreter did not match is left alone rather than
          // cleared: an unrecognised sentence should not narrow the trip to
          // nothing.
          if (interpretation.theme) theme = interpretation.theme;
          preferredCategoryKeys = interpretation.category_keys ?? [];
        }
      }

      const route = await apiFetch<GeneratedRoute>("/api/routes", {
        method: "POST",
        signal: controller.signal,
        body: JSON.stringify({
          city_id: city.id,
          theme,
          time_budget_minutes: tripDays * hoursPerDay * 60,
          transport_mode: "hybrid",
          // A ranking preference, never a filter — see `RouteRequest` on the
          // server for why these are not `category_keys`.
          ...(preferredCategoryKeys.length > 0
            ? { preferred_category_keys: preferredCategoryKeys }
            : {}),
          locale: "en",
        }),
      });

      router.push(`/routes/${route.id}`);
    } catch (caught) {
      // A cancelled request already put the planner back on screen; saying
      // "couldn't build that route" about a route nobody is waiting for any
      // more would be reporting the traveller's own decision as a failure.
      if (caught instanceof DOMException && caught.name === "AbortError") return;

      setBusy(false);
      setError(
        caught instanceof ApiError
          ? messageForCode(caught.code, caught.message)
          : messageForCode("network_error"),
      );
    } finally {
      inFlight.current = null;
    }
  }

  function cancel() {
    inFlight.current?.abort();
    setBusy(false);
  }

  if (busy) return <Thinking onCancel={cancel} />;

  return (
    <div className={styles.stage}>
      <div className={styles.mapLayer}>
        <WilayaMap cities={cities} cityId={cityId} onSelect={setCityId} />
      </div>

      <Link href="/" className={styles.back}>
        <ChevronLeft size={18} aria-hidden />
        Back
      </Link>

      <GlassSurface className={styles.panel} as="section">
        <div className={styles.panelInner}>
          <CityPicker cities={cities} cityId={cityId} onSelect={setCityId} />

          <SelectedCity city={city} />

          {error ? (
            <Notice tone="error" title="Couldn't build that route">
              {error}
            </Notice>
          ) : null}

          {/* The drawer, animated open rather than swapped, so it reads as the
              panel growing from the bottom edge instead of the map being
              replaced. */}
          <div className={styles.drawer} data-open={expanded} aria-hidden={!expanded}>
            <div className={styles.drawerInner}>
              <TimeBudgetPicker
                tripDays={tripDays}
                hoursPerDay={hoursPerDay}
                onTripDaysChange={setTripDays}
                onHoursPerDayChange={setHoursPerDay}
              />

              <div className={styles.promptField}>
                <label className="sectionLabel" htmlFor="prompt">
                  TELL THE AI WHAT YOU&apos;RE AFTER
                </label>
                <input
                  id="prompt"
                  className="input-field"
                  maxLength={MAX_PROMPT_LENGTH}
                  value={prompt}
                  placeholder="quiet Roman ruins, coastal viewpoints…"
                  onChange={(event) => setPrompt(event.target.value)}
                  tabIndex={expanded ? undefined : -1}
                />
              </div>
            </div>
          </div>

          <button
            type="button"
            className={styles.drawerToggle}
            onClick={() => setExpanded((open) => !open)}
            aria-expanded={expanded}
          >
            <span className={styles.drawerSummary}>
              {/* Collapsed, this row has to say what is behind it; expanded, the
                  controls say it themselves and repeating it would just be a
                  second, staler copy. */}
              {expanded
                ? "Hide trip options"
                : summarise(tripDays, hoursPerDay, prompt)}
            </span>
            <ChevronUp size={20} aria-hidden data-open={expanded} className={styles.drawerChevron} />
          </button>

          <button
            type="button"
            className="btn btn-primary btn-block"
            disabled={!canGenerate}
            onClick={generate}
          >
            Generate my route
          </button>
        </div>
      </GlassSurface>
    </div>
  );
}

/** One line standing in for everything the collapsed panel hides. */
function summarise(tripDays: number, hoursPerDay: number, prompt: string): string {
  const parts = [
    `${tripDays} ${tripDays === 1 ? "day" : "days"}`,
    formatMinutes(hoursPerDay * 60),
  ];
  const typed = prompt.trim();
  if (typed.length > 0) parts.push(typed);
  return parts.join(" · ");
}

/**
 * Search across the routable cities.
 *
 * The map is the primary way to choose, but it asks the traveller to already
 * know where Tlemcen is. This is the same choice by name, and it is the only
 * control on the panel that can reach a city whose wilaya outline failed to
 * load.
 */
function CityPicker({
  cities,
  cityId,
  onSelect,
}: {
  cities: City[];
  cityId: string | null;
  onSelect: (id: string) => void;
}) {
  const [query, setQuery] = useState("");
  const trimmed = query.trim().toLowerCase();

  const matches =
    trimmed.length === 0
      ? []
      : cities.filter((city) => city.name.toLowerCase().includes(trimmed)).slice(0, 6);

  return (
    <div className={styles.search}>
      <Search size={16} aria-hidden className={styles.searchIcon} />
      <input
        className={styles.searchInput}
        value={query}
        placeholder="Search for a city"
        aria-label="Search for a city"
        onChange={(event) => setQuery(event.target.value)}
      />
      {query.length > 0 ? (
        <button
          type="button"
          className={styles.searchClear}
          onClick={() => setQuery("")}
          aria-label="Clear search"
        >
          <X size={14} aria-hidden />
        </button>
      ) : null}

      {matches.length > 0 ? (
        <ul className={styles.results}>
          {matches.map((city) => (
            <li key={city.id}>
              <button
                type="button"
                className={styles.result}
                data-selected={city.id === cityId}
                onClick={() => {
                  onSelect(city.id);
                  setQuery("");
                }}
              >
                {city.name}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

/**
 * Which one city the trip is being planned in.
 *
 * Singular throughout, matching what the module can actually route. There is no
 * count badge, because a count that only ever reads 0 or 1 is noise, and no
 * plural copy, because it would advertise a multi-select the map refuses to
 * perform.
 */
function SelectedCity({ city }: { city: City | null }) {
  if (!city) {
    return (
      <p className={styles.hint}>
        <MousePointerClick size={15} aria-hidden />
        Click a highlighted wilaya to pick where you are going
      </p>
    );
  }

  return (
    <p className={styles.selected}>
      <span className={styles.selectedChip}>{city.name}</span>
      {/* Says how to change it: that clicking a second wilaya swaps out the
          first is the one thing about single-select you cannot guess by
          looking. */}
      <span className={styles.selectedHint}>Click another to switch</span>
    </p>
  );
}

/**
 * Shown while the route is being built.
 *
 * It can be left. Generation is a single network call rather than a job to poll,
 * but it is still a call — and "I changed my mind" needs an answer sooner than
 * the client's own timeout gives one.
 */
function Thinking({ onCancel }: { onCancel: () => void }) {
  return (
    <AppBackdrop variant="deep">
      <div className={styles.thinking}>
        <button type="button" className={`btn btn-onDark btn-compact ${styles.cancel}`} onClick={onCancel}>
          <X size={16} aria-hidden />
          Cancel
        </button>

        <div className={styles.thinkingBody}>
          <CompassSpinner size={96} />
          <p className={styles.thinkingTitle}>Almost there…</p>
          <p className={styles.thinkingCopy}>
            Reading your time budget, picking the stops, and working out the order.
          </p>
        </div>
      </div>
    </AppBackdrop>
  );
}
