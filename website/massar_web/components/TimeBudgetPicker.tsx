"use client";

import { useCallback, useEffect, useRef } from "react";

import { formatMinutes } from "@/lib/format";

import styles from "./TimeBudgetPicker.module.css";

/** The wheels' stops, exactly as `AppState.tripDayOptions` / `hoursPerDayOptions`. */
export const TRIP_DAY_OPTIONS = [1, 2, 3, 4];
export const HOURS_PER_DAY_OPTIONS = [2, 4, 6, 8, 10, 12];

/** One row of a wheel, in px. The wheel shows a value either side of the
 *  selection, which is what sets the track height at 3.4 rows. */
const ROW = 34;

/**
 * How much time the traveller actually has, set the way an alarm is set.
 *
 * The route module plans against this budget — how many stops fit, and whether
 * the answer needs more than one day — so it is not a cosmetic filter.
 *
 * Two wheels rather than one, because they answer questions people know the
 * answers to separately: how long the trip is, and how much of each day is
 * spent walking around. The minutes on the wire stay derived from both, so
 * there is no third number to disagree.
 *
 * One selection band runs behind both wheels rather than each having its own,
 * which is what makes the pair read as a single setting — the same reason a
 * clock's hours and minutes sit under one highlight.
 */
export default function TimeBudgetPicker({
  tripDays,
  hoursPerDay,
  onTripDaysChange,
  onHoursPerDayChange,
}: {
  tripDays: number;
  hoursPerDay: number;
  onTripDaysChange: (value: number) => void;
  onHoursPerDayChange: (value: number) => void;
}) {
  const totalMinutes = tripDays * hoursPerDay * 60;

  return (
    <div className={styles.picker}>
      <div className={styles.head}>
        <span className="sectionLabel">HOW MUCH TIME DO YOU HAVE?</span>
        {/* The derived total, shown because it is what the server is actually
            asked for — seeing the product makes "2 days × 4h" legible as eight
            hours of touring rather than something to work out. */}
        <span className={styles.total}>{formatMinutes(totalMinutes)}</span>
      </div>

      <div className={styles.track}>
        {/* The band sits under both wheels and belongs to neither, so the two
            columns cannot drift out of alignment with it. */}
        <div className={styles.band} aria-hidden />
        <Wheel
          values={TRIP_DAY_OPTIONS}
          selected={tripDays}
          unit={(v) => (v === 1 ? "day" : "days")}
          label="Trip length in days"
          onChange={onTripDaysChange}
        />
        <Wheel
          values={HOURS_PER_DAY_OPTIONS}
          selected={hoursPerDay}
          unit={() => "hours"}
          label="Touring hours per day"
          onChange={onHoursPerDayChange}
        />
      </div>

      {/* What each wheel is counting. "8 hours" alone is genuinely ambiguous —
          eight hours in total, or eight on each of the days beside it? */}
      <div className={styles.captions}>
        <span>for the whole trip</span>
        <span>on each of those days</span>
      </div>
    </div>
  );
}

/**
 * One scrolling column of numbers, with its unit standing still beside it.
 *
 * The unit does not scroll with the number: on an alarm picker the label is
 * part of the frame, not part of the list, and scrolling it would make the
 * wheel look like it holds twelve different words rather than twelve values of
 * one thing.
 */
function Wheel({
  values,
  selected,
  unit,
  label,
  onChange,
}: {
  values: number[];
  selected: number;
  unit: (value: number) => string;
  label: string;
  onChange: (value: number) => void;
}) {
  const listRef = useRef<HTMLDivElement>(null);
  const settleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const scrollToSelected = useCallback(
    (behavior: ScrollBehavior) => {
      const list = listRef.current;
      if (!list) return;
      list.scrollTo({ top: nearestIndex(values, selected) * ROW, behavior });
    },
    [selected, values],
  );

  // The value can also change from outside the wheel — a reset, or the other
  // wheel being restored. Follow it, but only when it is not already there, or
  // this fights the settling scroll that produced the change.
  useEffect(() => {
    const list = listRef.current;
    if (!list) return;
    const target = nearestIndex(values, selected) * ROW;
    if (Math.abs(list.scrollTop - target) < ROW / 2) return;
    scrollToSelected("smooth");
  }, [scrollToSelected, selected, values]);

  // The first paint has to land on the current value without animating.
  useEffect(() => {
    scrollToSelected("auto");
    // Deliberately once, on mount: afterwards the effect above owns the scroll
    // position, and re-running this would yank the wheel mid-drag.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /**
   * Reports the value the wheel came to rest on.
   *
   * Debounced rather than fired per scroll event: a flick emits dozens of
   * frames, and calling back on each would re-render the whole planner sixty
   * times a second and re-enter the effect above on every one of them.
   */
  const onScroll = () => {
    if (settleTimer.current) clearTimeout(settleTimer.current);
    settleTimer.current = setTimeout(() => {
      const list = listRef.current;
      if (!list) return;
      const index = Math.max(0, Math.min(values.length - 1, Math.round(list.scrollTop / ROW)));
      if (values[index] !== selected) onChange(values[index]);
    }, 120);
  };

  useEffect(() => () => {
    if (settleTimer.current) clearTimeout(settleTimer.current);
  }, []);

  return (
    <div className={styles.wheel}>
      <div
        ref={listRef}
        className={styles.list}
        onScroll={onScroll}
        role="listbox"
        aria-label={label}
        tabIndex={0}
        onKeyDown={(event) => {
          const index = nearestIndex(values, selected);
          if (event.key === "ArrowDown" && index < values.length - 1) {
            event.preventDefault();
            onChange(values[index + 1]);
          } else if (event.key === "ArrowUp" && index > 0) {
            event.preventDefault();
            onChange(values[index - 1]);
          }
        }}
      >
        {values.map((value) => (
          <div
            key={value}
            role="option"
            aria-selected={value === selected}
            className={styles.row}
            data-selected={value === selected}
            onClick={() => onChange(value)}
          >
            {value}
          </div>
        ))}
      </div>
      <span className={styles.unit}>{unit(selected)}</span>
    </div>
  );
}

/**
 * The index of `value` in `values`, or the nearest one to it.
 *
 * A restored budget can carry a value the picker no longer offers — the
 * options are a fixed list and a saved plan is not. Snapping to the nearest is
 * the honest reading; `indexOf`'s -1 would scroll the wheel off its own top.
 */
function nearestIndex(values: number[], value: number): number {
  if (values.length === 0) return 0;
  const exact = values.indexOf(value);
  if (exact !== -1) return exact;

  let best = 0;
  for (let i = 1; i < values.length; i += 1) {
    if (Math.abs(values[i] - value) < Math.abs(values[best] - value)) best = i;
  }
  return best;
}
