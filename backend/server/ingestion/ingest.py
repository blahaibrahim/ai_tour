"""Orchestrates the full ingestion pipeline for a tile (docs/backend/12):

    Overpass fetch -> Wikidata match -> Wikipedia blurb -> photo -> score
    -> dedupe against existing locations -> persist

`ensure_tiles_ingested` is the entry point routes/poi.py and
data/locations_repo.py call before serving a radius query — it's a no-op
for any tile already fresh in `poi_tiles`, so a warm area costs nothing.
"""
from __future__ import annotations

import concurrent.futures
import json
import logging
import time

from data.geo import haversine_km
from ingestion import describe, overpass, photos, scoring, wikidata, wikipedia
from ingestion.rewrite import rewrite_blurb, translate_blurbs
from ingestion.supabase_admin import get_admin_client
from ingestion.tiling import covering_tiles, tile_bounds
from llm import embed

logger = logging.getLogger(__name__)

MIN_ACTIVE_SCORE = 25
TILE_QUERY_RADIUS_KM = 1.5  # covers a ~3km tile from its center with margin
POLITE_DELAY_S = 1.0  # between external-API calls, see tiling.py's note on the 429 hit while testing


def _osm_wikipedia_title(tags: dict) -> str | None:
    raw = tags.get("wikipedia", "")
    if raw.startswith("en:"):
        return raw[3:]
    return None


def _truncate_blurb(text: str, max_chars: int = 280) -> str:
    """Wikipedia extracts run long and are encyclopedic rather than
    editorial in tone (docs/backend/12 flags this — an LLM rewrite pass
    would fix the tone but costs a call per POI, deferred for now). This
    just keeps the stored blurb card-sized, cutting at the last sentence
    boundary inside the limit rather than mid-word."""
    if len(text) <= max_chars:
        return text
    truncated = text[:max_chars]
    last_period = truncated.rfind(". ")
    return truncated[: last_period + 1] if last_period > max_chars * 0.4 else truncated.rstrip() + "…"


def _tile_place_context(pois: list[dict]) -> str | None:
    """The city/region this tile sits in, as the most common `addr:*` value
    among its POIs.

    `photos.py`'s unanchored search tier needs a place name to verify
    against, and only ~13% of POIs carry `addr:city` individually — but a
    tile is ~3km across, so borrowing the modal value from its neighbours is
    both sound and free, needing no extra geocoding request.
    """
    counts: dict[str, int] = {}
    for poi in pois:
        tags = poi.get("tags") or {}
        for key in ("addr:city", "addr:suburb", "addr:province", "addr:state"):
            value = tags.get(key)
            if isinstance(value, str) and value.strip():
                counts[value.strip()] = counts.get(value.strip(), 0) + 1
                break  # count each POI once, at its most specific level
    if not counts:
        return None
    return max(counts, key=counts.get)


def _tiles_needing_refresh(client, tile_ids: list[str]) -> list[str]:
    """A tile that's never been fetched simply won't appear in this result
    either, so "not fresh" correctly covers both "missing" and "expired"
    without needing to distinguish them.
    """
    if not tile_ids:
        return []
        
    try:
        from datetime import datetime, timezone
        now_iso = datetime.now(timezone.utc).isoformat()
        res = (
            client.table("poi_tiles")
            .select("tile_id")
            .in_("tile_id", tile_ids)
            .gte("expires_at", now_iso)
            .eq("fetch_status", "ok")
            .execute()
        )
        fresh_tiles = {r["tile_id"] for r in res.data} if res.data else set()
        return [t for t in tile_ids if t not in fresh_tiles]
    except Exception as e:
        logger.warning(f"Failed to check poi_tiles cache, forcing refresh: {e}")
        return tile_ids


def _ingest_one_tile(client, tile_id: str) -> None:
    lat_min, lat_max, lng_min, lng_max = tile_bounds(tile_id)
    center_lat = (lat_min + lat_max) / 2
    center_lng = (lng_min + lng_max) / 2

    # Add a tiny margin to the tile boundaries for Overpass query
    margin = 0.005 # Roughly 500m
    pois = overpass.fetch_pois(lat_min - margin, lng_min - margin, lat_max + margin, lng_max + margin)
    time.sleep(POLITE_DELAY_S)
    wikidata_items = wikidata.fetch_wikidata_items(center_lat, center_lng, TILE_QUERY_RADIUS_KM)
    time.sleep(POLITE_DELAY_S)

    wikidata_by_qid = {item["qid"]: item for item in wikidata_items}
    place_context = _tile_place_context(pois)
    processed = 0

    def process_poi(poi):
        wd_match = None
        if poi["wikidata_qid"]:
            wd_match = wikidata_by_qid.get(poi["wikidata_qid"])
        if wd_match is None:
            wd_match = wikidata.match_nearest(poi["lat"], poi["lng"], wikidata_items)

        wikipedia_title = (wd_match or {}).get("wikipedia_title") or _osm_wikipedia_title(poi["tags"])

        summary = None
        pageviews = None
        if wikipedia_title:
            summary = wikipedia.fetch_summary(wikipedia_title)
            if summary:
                pageviews = wikipedia.fetch_pageviews_30d(wikipedia_title)

        photo = photos.resolve_photo(
            wikipedia_title=wikipedia_title,
            wikidata_image_filename=(wd_match or {}).get("image_filename"),
            osm_tags=poi["tags"],
            # Was previously omitted, which left the P18-by-QID tier and every
            # coordinate-anchored tier below it unreachable in the real
            # pipeline — they only ever ran in isolated tests.
            wikidata_qid=(wd_match or {}).get("qid"),
            name=poi["name"],
            lat=poi["lat"],
            lng=poi["lng"],
            place_context=place_context,
        )

        score, breakdown = scoring.compute_score(
            category=poi["category"],
            name=poi["name"],
            osm_tags=poi["tags"],
            wikidata_match=wd_match,
            wikipedia_found=summary is not None,
            pageviews_30d=pageviews,
            has_photo=photo is not None,
        )

        heritage_status = (
            "unesco_world_heritage" if (wd_match or {}).get("is_unesco")
            else "heritage_listed" if (wd_match or {}).get("has_heritage")
            else None
        )

        if summary and summary.get("extract"):
            raw_blurb = _truncate_blurb(summary["extract"])
        else:
            # No Wikipedia article — compose from the OSM tags instead. This is
            # the path almost every POI takes (only ~10 of 203 catalogue rows
            # have a wikipedia_title), so it is worth doing properly; see
            # describe.py for what the previous format-string version produced.
            raw_blurb = describe.compose(describe.collect_facts(
                name=poi["name"],
                category=poi["category"],
                tags=poi["tags"],
                heritage_status=heritage_status,
                place=place_context,
            ))

        # LLM pass. Both branches degrade silently to raw_blurb on failure.
        if summary and summary.get("extract"):
            # Condense text that already exists.
            rewritten = rewrite_blurb(summary["extract"], poi["name"], poi["category"])
            blurb = rewritten if rewritten else raw_blurb
        else:
            # Previously the LLM was skipped entirely here, which meant the
            # ~95% of POIs with no Wikipedia article never got a written
            # description at all. There is no source text to condense, so the
            # model is instead given the same structured facts and forbidden
            # from adding to them (see rewrite.describe_from_facts).
            blurb = describe.describe(describe.collect_facts(
                name=poi["name"],
                category=poi["category"],
                tags=poi["tags"],
                heritage_status=heritage_status,
                place=place_context,
            ))

        # QID match first — a definitive signal (docs/backend/12's dedup
        # tier 1) — before falling back to the weaker proximity+name RPC.
        # This isn't theoretical: live testing found the curated seed
        # coordinate for Ahmed Bey Palace is 432m from OSM's mapped point,
        # and OSM's name for it ("Palais du Bey") doesn't trigram-match
        # "Ahmed Bey Palace" — both comfortably clear of the proximity+name
        # RPC's thresholds, which produced a real duplicate row before this
        # check existed. Both records agreed on the same Wikidata QID
        # (Q12232975) even though neither weaker signal did.
        matched_id = None
        wd_qid = (wd_match or {}).get("qid")
        if wd_qid:
            qid_hit = (
                client.table("locations")
                .select("id")
                .eq("wikidata_qid", wd_qid)
                .limit(1)
                .execute()
                .data
            )
            if qid_hit:
                matched_id = qid_hit[0]["id"]

        if matched_id is None:
            matched_id = client.rpc(
                "find_location_match",
                {"p_lat": poi["lat"], "p_lng": poi["lng"], "p_name": poi["name"]},
            ).execute().data

        target_id = matched_id or f"osm-{poi['osm_type']}-{poi['osm_id']}"

        # Generate semantic embedding
        embedding_text = f"{poi['name']}. {blurb}"
        emb = None
        try:
            emb = embed(embedding_text)
        except Exception as e:
            logger.warning("Embedding failed for %s: %s", target_id, e)

        client.rpc(
            "upsert_ingested_location",
            {
                "p_id": target_id,
                "p_lat": poi["lat"],
                "p_lng": poi["lng"],
                "p_category": poi["category"],
                "p_name": poi["name"],
                "p_blurb": blurb,
                "p_interest_score": score,
                "p_score_breakdown": breakdown,
                "p_wikidata_qid": (wd_match or {}).get("qid"),
                "p_wikipedia_title": wikipedia_title,
                "p_pageviews_30d": pageviews,
                "p_heritage_status": heritage_status,
                "p_photo_url": (photo or {}).get("photo_url"),
                "p_photo_attribution": (photo or {}).get("photo_attribution"),
                "p_photo_license": (photo or {}).get("photo_license"),
                "p_photo_source_url": (photo or {}).get("photo_source_url"),
                "p_is_active": score >= MIN_ACTIVE_SCORE,
                "p_embedding": emb,
                "p_osm_tags": poi["tags"],
            },
        ).execute()

        client.table("poi_source_links").upsert(
            {
                "location_id": target_id,
                "source": "osm",
                "source_ref": f"{poi['osm_type']}/{poi['osm_id']}",
                "raw": json.loads(json.dumps(poi, default=str)),
            },
            on_conflict="source,source_ref",
        ).execute()

        return True

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(process_poi, poi) for poi in pois]
        for future in concurrent.futures.as_completed(futures):
            try:
                if future.result():
                    processed += 1
            except Exception as e:
                logger.error("Failed processing a POI: %s", e)

        # Disable translations for now to save LLM quota
        # translations = translate_blurbs(blurb, poi["name"])
        # for locale_code, translated_blurb in translations.items():
        #     try:
        #         client.table("location_translations").upsert(
        #             {
        #                 "location_id": target_id,
        #                 "locale": locale_code,
        #                 "name": poi["name"],
        #                 "blurb": translated_blurb,
        #             },
        #             on_conflict="location_id,locale",
        #         ).execute()
        #     except Exception as e:
        #         logger.warning("Could not persist %s translation for %s: %s", locale_code, target_id, e)

    client.rpc(
        "upsert_poi_tile",
        {
            "p_tile_id": tile_id,
            "p_lat_min": lat_min,
            "p_lat_max": lat_max,
            "p_lng_min": lng_min,
            "p_lng_max": lng_max,
            "p_source": "overpass+wikidata",
            "p_poi_count": processed,
            "p_fetch_status": "ok",
        },
    ).execute()


def ensure_tiles_ingested(lat: float, lng: float, radius_km: float, max_tiles: int = None) -> dict:
    """Ingests whatever tiles covering (lat, lng, radius_km) aren't already
    fresh in the cache. Returns a summary dict for logging/debugging — this
    is meant to be called before `nearby_locations`, not to replace it."""
    client = get_admin_client()
    tiles = covering_tiles(lat, lng, radius_km)
    stale = _tiles_needing_refresh(client, tiles)
    
    if max_tiles is not None and len(stale) > max_tiles:
        logger.info("Truncating stale tiles from %d to %d to avoid blocking too long", len(stale), max_tiles)
        # Always prioritize the tile the user is currently standing in (the center)
        # By sorting tiles by distance to center
        stale = sorted(stale, key=lambda t: abs(lat - tile_bounds(t)[0]) + abs(lng - tile_bounds(t)[2]))[:max_tiles]

    for tile_id in stale:
        try:
            _ingest_one_tile(client, tile_id)
        except Exception:
            logger.exception("Ingestion failed for tile %s", tile_id)
            lat_min, lat_max, lng_min, lng_max = tile_bounds(tile_id)
            try:
                client.rpc(
                    "upsert_poi_tile",
                    {
                        "p_tile_id": tile_id, "p_lat_min": lat_min, "p_lat_max": lat_max,
                        "p_lng_min": lng_min, "p_lng_max": lng_max, "p_source": "overpass+wikidata",
                        "p_poi_count": 0, "p_fetch_status": "failed", "p_ttl_days": 1,
                    },
                ).execute()
            except Exception:
                logger.exception("Could not even record tile %s as failed", tile_id)

    return {"tiles_considered": len(tiles), "tiles_refreshed": len(stale)}
