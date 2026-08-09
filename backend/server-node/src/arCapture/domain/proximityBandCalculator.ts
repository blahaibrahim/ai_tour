/**
 * Layer 3 — Proximity Band Calculator. Pure function, no dependencies.
 *
 * Mirrored line-for-line in Dart (`lib/ar/proximity.dart`, `ProximityBandCalculator`
 * and `rawBand`) — plan §5.3 and §11 both call this out by name: "Server and
 * client disagreeing about what 'hot' means is the most likely silent bug in
 * this module." `sql/../band-fixtures.json` is executed against both
 * implementations to prove they agree; see `test/arCaptureParity.ts` here and
 * `test/proximity_parity_test.dart` on the Flutter side.
 *
 * STATUS: implemented for real, unlike the rest of this module's Layer 3 —
 * the plan puts it first in the domain build order precisely because it has
 * no dependency on Data or an Adapter, and the parity requirement means it
 * has to exist before the fixture can be written.
 */
import { BandThresholds, DEFAULT_BAND_THRESHOLDS, PROXIMITY_BANDS, ProximityBand } from "../types";

function bandIndex(band: ProximityBand): number {
  return PROXIMITY_BANDS.indexOf(band);
}

/** The distance at which `band` gives way to the next-hotter one. FROZEN has
 * no inner edge, so it reports Infinity. */
export function boundaryOf(band: ProximityBand, thresholds: BandThresholds): number {
  switch (band) {
    case "frozen":
      return Infinity;
    case "cold":
      return thresholds.coldMeters;
    case "warm":
      return thresholds.warmMeters;
    case "hot":
      return thresholds.hotMeters;
    case "burning":
      return thresholds.burningMeters;
  }
}

/** The band `distanceMeters` falls into on its own, ignoring hysteresis. */
export function rawBand(distanceMeters: number, thresholds: BandThresholds = DEFAULT_BAND_THRESHOLDS): ProximityBand {
  if (distanceMeters <= thresholds.burningMeters) return "burning";
  if (distanceMeters <= thresholds.hotMeters) return "hot";
  if (distanceMeters <= thresholds.warmMeters) return "warm";
  if (distanceMeters <= thresholds.coldMeters) return "cold";
  return "frozen";
}

/**
 * Classifies a distance into a band, with the flap guard plan §5.3 specifies:
 * moving to a hotter band is immediate ("false hope is cheaper than false
 * despair"); moving to a colder one requires clearing the old boundary by a
 * margin (`max(8m, 15% of the boundary)`), so 8 m of GPS noise near an edge
 * doesn't buzz the hunter back and forth every few seconds.
 */
export function classify(
  distanceMeters: number,
  thresholds: BandThresholds = DEFAULT_BAND_THRESHOLDS,
  previousBand: ProximityBand = "frozen",
): ProximityBand {
  const raw = rawBand(distanceMeters, thresholds);
  if (bandIndex(raw) >= bandIndex(previousBand)) return raw;

  const margin = Math.max(8, 0.15 * boundaryOf(previousBand, thresholds));
  if (distanceMeters < boundaryOf(previousBand, thresholds) + margin) return previousBand;
  return raw;
}
