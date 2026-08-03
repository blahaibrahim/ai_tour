"""Location data access — Supabase-backed, with the curated set as a hard
fallback (docs/backend/12: "the curated 8 are the floor. Never show an empty
map."). Every function here degrades to `curated_locations` on *any* failure
(network error, misconfiguration, empty/unexpected result) rather than
raising, because a stale-but-correct answer beats a 500 for a travel app.

Callers (routes/*.py) see one stable shape regardless of which source
answered:
    {id, name, region, category, blurb, task_type, task_label, lat, lng, distance_km}
"""
from __future__ import annotations

import logging

from data import curated_locations as fallback
from data.supabase_client import get_client, is_configured

logger = logging.getLogger(__name__)


def _pick_locale(rows: list[dict], locale: str, key_field: str = "locale") -> dict | None:
    """From a list of {locale, ...} rows (a translations embed), pick the
    requested locale, falling back to English, falling back to whatever's
    first. Mirrors the SQL-side `coalesce(t.x, ten.x)` fallback in the
    `nearby_locations` RPC (docs/backend/02) so single-row lookups behave the
    same way as the radius query."""
    if not rows:
        return None
    by_locale = {r[key_field]: r for r in rows}
    return by_locale.get(locale) or by_locale.get("en") or rows[0]


def _first_task(location_tasks: list[dict], locale: str) -> tuple[str | None, str | None]:
    if not location_tasks:
        return None, None
    task = location_tasks[0]
    translations = task.get("location_task_translations") or []
    label_row = _pick_locale(translations, locale)
    return task.get("type"), (label_row or {}).get("label")


def _region_name(regions: dict | None, locale: str) -> str | None:
    if not regions:
        return None
    translations = regions.get("region_translations") or []
    name_row = _pick_locale(translations, locale)
    return (name_row or {}).get("name")


def locations_within_radius(
    lat: float,
    lng: float,
    radius_km: float,
    *,
    locale: str = "en",
    prompt_embedding: list[float] | None = None,
    categories: list[str] | None = None,
    limit: int | None = None,
) -> list[dict]:
    if not is_configured():
        return fallback.locations_within_radius(lat, lng, radius_km, limit=limit)

    try:
        client = get_client()
        rpc_args = {"p_lat": lat, "p_lng": lng, "p_radius_km": radius_km, "p_locale": locale}
        if prompt_embedding is not None:
            rpc_args["p_prompt_embedding"] = prompt_embedding
        if categories:
            rpc_args["p_categories"] = categories
        if limit is not None:
            rpc_args["p_limit"] = limit
            
        rpc_rows = (
            client.rpc(
                "nearby_locations",
                rpc_args,
            )
            .execute()
            .data
        )

        if not rpc_rows:
            # Same "never an empty map" behaviour as the curated fallback:
            # widen the search rather than returning nothing.
            rpc_rows = sorted(
                client.rpc(
                    "nearby_locations",
                    {"p_lat": lat, "p_lng": lng, "p_radius_km": 20000, "p_limit": 5, "p_locale": locale},
                )
                .execute()
                .data,
                key=lambda r: r["distance_km"],
            )

        if not rpc_rows:
            raise ValueError("Supabase catalogue returned no locations at all")

        ids = [r["id"] for r in rpc_rows]
        extra_by_id = {
            row["id"]: row
            for row in client.table("locations")
            .select(
                "id,photo_url,"
                "regions(region_translations(name,locale)),"
                "location_tasks(type,location_task_translations(label,locale))"
            )
            .in_("id", ids)
            .execute()
            .data
        }

        results = []
        for r in rpc_rows:
            extra = extra_by_id.get(r["id"], {})
            task_type, task_label = _first_task(extra.get("location_tasks") or [], locale)
            results.append(
                {
                    "id": r["id"],
                    "name": r["name"],
                    "region": _region_name(extra.get("regions"), locale),
                    "category": r["category"],
                    "blurb": r["blurb"],
                    "task_type": task_type,
                    "task_label": task_label,
                    "lat": r["lat"],
                    "lng": r["lng"],
                    "distance_km": round(r["distance_km"], 1),
                    "photo_url": extra.get("photo_url"),
                }
            )
        return results

    except Exception:
        logger.exception("Supabase locations_within_radius failed, falling back to curated set")
        return fallback.locations_within_radius(lat, lng, radius_km)


def get_location(location_id: str, *, locale: str = "en") -> dict | None:
    if not is_configured():
        return fallback.get_location(location_id)

    try:
        client = get_client()
        rows = (
            client.table("locations")
            .select(
                "id,category,"
                "location_translations(name,blurb,locale),"
                "regions(region_translations(name,locale))"
            )
            .eq("id", location_id)
            .eq("is_active", True)
            .limit(1)
            .execute()
            .data
        )
        if not rows:
            # A miss is a real answer (unknown id), not a failure — don't
            # mask it by falling back to a curated id that happens to exist.
            return None

        row = rows[0]
        translation = _pick_locale(row.get("location_translations") or [], locale)
        if translation is None:
            return None

        return {
            "id": row["id"],
            "name": translation["name"],
            "region": _region_name(row.get("regions"), locale),
            "category": row["category"],
            "blurb": translation["blurb"],
        }

    except Exception:
        logger.exception("Supabase get_location failed, falling back to curated set")
        return fallback.get_location(location_id)
