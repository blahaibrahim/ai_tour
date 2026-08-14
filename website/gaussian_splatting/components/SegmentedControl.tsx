"use client";

import styles from "./SegmentedControl.module.css";

export interface SegmentOption<T extends string> {
  value: T;
  label: string;
  /** Shown under the label — "7k iters" says more than "draft" does alone. */
  hint?: string;
}

interface Props<T extends string> {
  label: string;
  options: SegmentOption<T>[];
  value: T;
  onChange: (value: T) => void;
  disabled?: boolean;
}

/**
 * Single choice out of a few fixed, ordered options — the same control the app
 * uses for "how many days" and "how are you getting around", and the right
 * shape for scene type, quality and stage.
 */
export function SegmentedControl<T extends string>({
  label,
  options,
  value,
  onChange,
  disabled,
}: Props<T>) {
  const index = Math.max(
    0,
    options.findIndex((option) => option.value === value),
  );

  return (
    <div className={styles.field}>
      <span className={styles.label}>{label}</span>
      <div
        className={styles.track}
        role="radiogroup"
        aria-label={label}
        style={{ opacity: disabled ? 0.5 : 1 }}
      >
        <div
          className={styles.indicator}
          style={{
            width: `calc((100% - 8px) / ${options.length})`,
            transform: `translateX(${index * 100}%)`,
          }}
        />
        {options.map((option) => {
          const selected = option.value === value;
          return (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={selected}
              disabled={disabled}
              className={`${styles.segment} ${selected ? styles.selected : ""}`}
              onClick={() => !selected && onChange(option.value)}
            >
              <span className={styles.text}>{option.label}</span>
              {option.hint ? (
                <span className={styles.hint}>{option.hint}</span>
              ) : null}
            </button>
          );
        })}
      </div>
    </div>
  );
}
