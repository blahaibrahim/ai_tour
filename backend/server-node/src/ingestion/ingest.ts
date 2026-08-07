/**
 * Orchestrates the full ingestion pipeline for a tile (docs/backend/12):
 *
 *     Overpass fetch -> Wikidata match -> Wikipedia blurb -> photo -> score
 *     -> dedupe against existing locations -> persist
 *
 * `ensureTilesIngested` is the entry point routes/poi.ts and
 * data/locationsRepo.ts call before serving a radius query — it's a no-op
 * for any tile already fresh in `poi_tiles`, so a warm area costs nothing.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

import { createLimiter, sleep } from "../async";
import { embed } from "../llm";
import { getLogger } from "../logger";
import { unwrap, unwrapRows } from "../supabase";
import { HeritageStatus, OsmTags, Poi, WikidataItem } from "../types";
import * as describe from "./describe";
import * as overpass from "./overpass";
import * as photos from "./photos";
import * as scoring from "./scoring";
import * as wikidata from "./wikidata";
import * as wikipedia from "./wikipedia";
import { rewriteBlurb } from "./rewrite";
import { getAdminClient } from "./supabaseAdmin";
import { coveringTiles, tileBounds } from "./tiling";

const logger = getLogger("ingestion.ingest");

export const MIN_ACTIVE_SCORE = 25;
export const TILE_QUERY_RADIUS_KM = 1.5; // covers a ~3km tile from its center with margin
export const POLITE_DELAY_S = 1.0; // between external-API calls, see tiling.ts's note on the 429 hit while testing

function osmWikipediaTitle(tags: OsmTags): string | null {
  const raw = tags.wikipedia ?? "";
  if (raw.startsWith("en:")) {
    return raw.slice(3);
  }
  return null;
}

/**
 * Wikipedia extracts run long and are encyclopedic rather than editorial in
 * tone (docs/backend/12 flags this — an LLM rewrite pass would fix the tone
 * but costs a call per POI, deferred for now). This just keeps the stored
 * blurb card-sized, cutting at the last sentence boundary inside the limit
 * rather than mid-word.
 */
function truncateBlurb(text: string, maxChars = 280): string {
  if (text.length <= maxChars) return text;
  const truncated = text.slice(0, maxChars);
  const lastPeriod = truncated.lastIndexOf(". ");
  return lastPeriod > maxChars * 0.4
    ? truncated.slice(0, lastPeriod + 1)
    : `${truncated.replace(/\s+$/u, "")}…`;
}

/**
 * The city/region this tile sits in, as the most common `addr:*` value among
 * its POIs.
 *
 * `photos.ts`'s unanchored search tier needs a place name to verify against,
 * and only ~13% of POIs carry `addr:city` individually — but a tile is ~3km
 * across, so borrowing the modal value from its neighbours is both sound and
 * free, needing no extra geocoding request.
 */
function tilePlaceContext(pois: Poi[]): string | null {
  const counts = new Map<string, number>();
  for (const poi of pois) {
    const tags = poi.tags ?? {};
    for (const key of ["addr:city", "addr:suburb", "addr:province", "addr:state"]) {
      const value = tags[key];
      if (typeof value === "string" && value.trim()) {
        const trimmed = value.trim();
        counts.set(trimmed, (counts.get(trimmed) ?? 0) + 1);
        break; // count each POI once, at its most specific level
      }
    }
  }
  if (counts.size === 0) return null;
  // Python's `max(counts, key=counts.get)` keeps the first key on a tie, and
  // so does this, because Map iterates in insertion order.
  let best: string | null = null;
  let bestCount = -1;
  for (const [value, count] of counts) {
    if (count > bestCount) {
      best = value;
      bestCount = count;
    }
  }
  return best;
}

/**
 * A tile that's never been fetched simply won't appear in this result either,
 * so "not fresh" correctly covers both "missing" and "expired" without needing
 * to distinguish them.
 */
async function tilesNeedingRefresh(
  client: SupabaseClient,
  tileIds: string[],
): Promise<string[]> {
  if (tileIds.length === 0) return [];

  try {
    const nowIso = new Date().toISOString();
    const rows = await unwrapRows<{ tile_id: string }>(
      client
        .from("poi_tiles")
        .select("tile_id")
        .in("tile_id", tileIds)
        .gte("expires_at", nowIso)
        .eq("fetch_status", "ok"),
    );
    const freshTiles = new Set(rows.map((r) => r.tile_id));
    return tileIds.filter((t) => !freshTiles.has(t));
  } catch (error) {
    logger.warning(
      `Failed to check poi_tiles cache, forcing refresh: ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return tileIds;
  }
}

async function ingestOneTile(client: SupabaseClient, tileId: string): Promise<void> {
  const [latMin, latMax, lngMin, lngMax] = tileBounds(tileId);
  const centerLat = (latMin + latMax) / 2;
  const centerLng = (lngMin + lngMax) / 2;

  // Add a tiny margin to the tile boundaries for the Overpass query
  const margin = 0.005; // Roughly 500m
  const pois = await overpass.fetchPois(
    latMin - margin,
    lngMin - margin,
    latMax + margin,
    lngMax + margin,
  );
  await sleep(POLITE_DELAY_S * 1000);
  const wikidataItems = await wikidata.fetchWikidataItems(
    centerLat,
    centerLng,
    TILE_QUERY_RADIUS_KM,
  );
  await sleep(POLITE_DELAY_S * 1000);

  const wikidataByQid = new Map<string, WikidataItem>(
    wikidataItems.map((item) => [item.qid, item]),
  );
  const placeContext = tilePlaceContext(pois);
  let processed = 0;

  const processPoi = async (poi: Poi): Promise<boolean> => {
    let wdMatch: WikidataItem | null = null;
    if (poi.wikidata_qid) {
      wdMatch = wikidataByQid.get(poi.wikidata_qid) ?? null;
    }
    if (wdMatch === null) {
      wdMatch = wikidata.matchNearest(poi.lat, poi.lng, wikidataItems);
    }

    const wikipediaTitle = wdMatch?.wikipedia_title ?? osmWikipediaTitle(poi.tags);

    let summary = null;
    let pageviews: number | null = null;
    if (wikipediaTitle) {
      summary = await wikipedia.fetchSummary(wikipediaTitle);
      if (summary) {
        pageviews = await wikipedia.fetchPageviews30d(wikipediaTitle);
      }
    }

    const photo = await photos.resolvePhoto({
      wikipediaTitle,
      wikidataImageFilename: wdMatch?.image_filename ?? null,
      osmTags: poi.tags,
      // Was previously omitted, which left the P18-by-QID tier and every
      // coordinate-anchored tier below it unreachable in the real
      // pipeline — they only ever ran in isolated tests.
      wikidataQid: wdMatch?.qid ?? null,
      name: poi.name,
      lat: poi.lat,
      lng: poi.lng,
      placeContext,
    });

    const [score, breakdown] = scoring.computeScore({
      category: poi.category,
      name: poi.name,
      osmTags: poi.tags,
      wikidataMatch: wdMatch,
      wikipediaFound: summary !== null,
      pageviews30d: pageviews,
      hasPhoto: photo !== null,
    });

    const heritageStatus: HeritageStatus = wdMatch?.is_unesco
      ? "unesco_world_heritage"
      : wdMatch?.has_heritage
        ? "heritage_listed"
        : null;

    let rawBlurb: string;
    if (summary?.extract) {
      rawBlurb = truncateBlurb(summary.extract);
    } else {
      // No Wikipedia article — compose from the OSM tags instead. This is
      // the path almost every POI takes (only ~10 of 203 catalogue rows
      // have a wikipedia_title), so it is worth doing properly; see
      // describe.ts for what the previous format-string version produced.
      rawBlurb = describe.compose(
        describe.collectFacts({
          name: poi.name,
          category: poi.category,
          tags: poi.tags,
          heritageStatus,
          place: placeContext,
        }),
      );
    }

    // LLM pass. Both branches degrade silently to rawBlurb on failure.
    let blurb: string;
    if (summary?.extract) {
      // Condense text that already exists.
      const rewritten = await rewriteBlurb(summary.extract, poi.name, poi.category);
      blurb = rewritten ?? rawBlurb;
    } else {
      // Previously the LLM was skipped entirely here, which meant the
      // ~95% of POIs with no Wikipedia article never got a written
      // description at all. There is no source text to condense, so the
      // model is instead given the same structured facts and forbidden
      // from adding to them (see rewrite.describeFromFacts).
      blurb = await describe.describe(
        describe.collectFacts({
          name: poi.name,
          category: poi.category,
          tags: poi.tags,
          heritageStatus,
          place: placeContext,
        }),
      );
    }

    // QID match first — a definitive signal (docs/backend/12's dedup
    // tier 1) — before falling back to the weaker proximity+name RPC.
    // This isn't theoretical: live testing found the curated seed
    // coordinate for Ahmed Bey Palace is 432m from OSM's mapped point,
    // and OSM's name for it ("Palais du Bey") doesn't trigram-match
    // "Ahmed Bey Palace" — both comfortably clear of the proximity+name
    // RPC's thresholds, which produced a real duplicate row before this
    // check existed. Both records agreed on the same Wikidata QID
    // (Q12232975) even though neither weaker signal did.
    let matchedId: string | null = null;
    const wdQid = wdMatch?.qid;
    if (wdQid) {
      const qidHit = await unwrapRows<{ id: string }>(
        client.from("locations").select("id").eq("wikidata_qid", wdQid).limit(1),
      );
      if (qidHit.length > 0) {
        matchedId = qidHit[0].id;
      }
    }

    if (matchedId === null) {
      matchedId = (await unwrap<string>(
        client.rpc("find_location_match", {
          p_lat: poi.lat,
          p_lng: poi.lng,
          p_name: poi.name,
        }),
      )) as string | null;
    }

    const targetId = matchedId || `osm-${poi.osm_type}-${poi.osm_id}`;

    // Generate semantic embedding
    const embeddingText = `${poi.name}. ${blurb}`;
    let emb: number[] | null = null;
    try {
      emb = await embed(embeddingText);
    } catch (error) {
      logger.warning(
        `Embedding failed for ${targetId}: ${error instanceof Error ? error.message : error}`,
      );
    }

    await unwrap(
      client.rpc("upsert_ingested_location", {
        p_id: targetId,
        p_lat: poi.lat,
        p_lng: poi.lng,
        p_category: poi.category,
        p_name: poi.name,
        p_blurb: blurb,
        p_interest_score: score,
        p_score_breakdown: breakdown,
        p_wikidata_qid: wdMatch?.qid ?? null,
        p_wikipedia_title: wikipediaTitle,
        p_pageviews_30d: pageviews,
        p_heritage_status: heritageStatus,
        p_photo_url: photo?.photo_url ?? null,
        p_photo_attribution: photo?.photo_attribution ?? null,
        p_photo_license: photo?.photo_license ?? null,
        p_photo_source_url: photo?.photo_source_url ?? null,
        p_is_active: score >= MIN_ACTIVE_SCORE,
        p_embedding: emb,
        p_osm_tags: poi.tags,
      }),
    );

    await unwrap(
      client.from("poi_source_links").upsert(
        {
          location_id: targetId,
          source: "osm",
          source_ref: `${poi.osm_type}/${poi.osm_id}`,
          raw: JSON.parse(JSON.stringify(poi)),
        },
        { onConflict: "source,source_ref" },
      ),
    );

    return true;
  };

  const limit = createLimiter(10);
  const results = await Promise.allSettled(pois.map((poi) => limit(() => processPoi(poi))));
  for (const result of results) {
    if (result.status === "fulfilled") {
      if (result.value) processed += 1;
    } else {
      logger.error(
        `Failed processing a POI: ` +
          `${result.reason instanceof Error ? result.reason.message : result.reason}`,
      );
    }
  }

  // Translations are disabled for now to save LLM quota. When they come back,
  // `rewrite.translateBlurbs(blurb, poi.name)` feeds a
  // `location_translations` upsert on conflict "location_id,locale".

  await unwrap(
    client.rpc("upsert_poi_tile", {
      p_tile_id: tileId,
      p_lat_min: latMin,
      p_lat_max: latMax,
      p_lng_min: lngMin,
      p_lng_max: lngMax,
      p_source: "overpass+wikidata",
      p_poi_count: processed,
      p_fetch_status: "ok",
    }),
  );
}

export interface IngestSummary {
  tiles_considered: number;
  tiles_refreshed: number;
}

/**
 * Ingests whatever tiles covering (lat, lng, radiusKm) aren't already fresh in
 * the cache. Returns a summary for logging/debugging — this is meant to be
 * called before `nearby_locations`, not to replace it.
 */
export async function ensureTilesIngested(
  lat: number,
  lng: number,
  radiusKm: number,
  maxTiles: number | null = null,
): Promise<IngestSummary> {
  const client = getAdminClient();
  const tiles = coveringTiles(lat, lng, radiusKm);
  let stale = await tilesNeedingRefresh(client, tiles);

  if (maxTiles !== null && stale.length > maxTiles) {
    logger.info(
      `Truncating stale tiles from ${stale.length} to ${maxTiles} to avoid blocking too long`,
    );
    // Always prioritize the tile the user is currently standing in (the center)
    // by sorting tiles by distance to center.
    const distanceToCenter = (t: string): number => {
      const [tileLatMin, , tileLngMin] = tileBounds(t);
      return Math.abs(lat - tileLatMin) + Math.abs(lng - tileLngMin);
    };
    stale = [...stale].sort((a, b) => distanceToCenter(a) - distanceToCenter(b)).slice(0, maxTiles);
  }

  for (const tileId of stale) {
    try {
      await ingestOneTile(client, tileId);
    } catch (error) {
      logger.exception(`Ingestion failed for tile ${tileId}`, error);
      const [latMin, latMax, lngMin, lngMax] = tileBounds(tileId);
      try {
        await unwrap(
          client.rpc("upsert_poi_tile", {
            p_tile_id: tileId,
            p_lat_min: latMin,
            p_lat_max: latMax,
            p_lng_min: lngMin,
            p_lng_max: lngMax,
            p_source: "overpass+wikidata",
            p_poi_count: 0,
            p_fetch_status: "failed",
            p_ttl_days: 1,
          }),
        );
      } catch (inner) {
        logger.exception(`Could not even record tile ${tileId} as failed`, inner);
      }
    }
  }

  return { tiles_considered: tiles.length, tiles_refreshed: stale.length };
}
