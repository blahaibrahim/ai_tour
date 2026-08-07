"""Backfill `locations.photo_url` for rows ingested before the photo
fallback tiers existed.

Fixing `ingestion/photos.py` only affects POIs as they are ingested, and
`poi_tiles` keeps an already-fetched tile out of the pipeline until its
`expires_at` passes — so without this, existing rows keep their empty photo
for up to the full tile TTL.

Only touches rows where `photo_url is null`; a row that already has a photo
is never overwritten. Dry-run by default.

    python backfill_photos.py                # report what would change
    python backfill_photos.py --apply        # write them
    python backfill_photos.py --apply --limit 20
"""
from __future__ import annotations

import argparse
import logging
import struct
import sys
import time

from ingestion import photos
from ingestion.supabase_admin import get_admin_client

logger = logging.getLogger(__name__)

# The external APIs photos.py calls are rate-limited; this runs as a batch
# job, so there is no reason to be anything other than polite.
DELAY_S = 0.6


def _decode_point(wkb_hex: str) -> tuple[float, float]:
    """PostGIS returns geography as WKB hex; the payload after the 9-byte
    header is (lng, lat) as little-endian doubles."""
    raw = bytes.fromhex(wkb_hex)
    lng, lat = struct.unpack_from("<dd", raw, 9)
    return lat, lng


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write results (default is dry-run)")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--place", default=None,
                        help="place context for the unanchored search tier, e.g. 'Algiers'")
    args = parser.parse_args()

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    client = get_admin_client()

    query = (
        client.table("locations")
        .select("id,geog,osm_tags,wikidata_qid,wikipedia_title,"
                "location_translations(name,locale)")
        .is_("photo_url", "null")
    )
    if args.limit:
        query = query.limit(args.limit)
    rows = query.execute().data or []

    print(f"{len(rows)} location(s) without a photo"
          f"{'' if args.apply else '  (dry run — pass --apply to write)'}\n")

    resolved = 0
    for i, row in enumerate(rows, 1):
        translations = row.get("location_translations") or []
        name = next(
            (t["name"] for t in translations if t.get("locale") == "en"),
            next((t["name"] for t in translations), None),
        )
        lat, lng = _decode_point(row["geog"])
        tags = row.get("osm_tags") or {}

        photo = photos.resolve_photo(
            wikipedia_title=row.get("wikipedia_title"),
            wikidata_image_filename=None,
            osm_tags=tags,
            wikidata_qid=row.get("wikidata_qid"),
            name=name,
            lat=lat,
            lng=lng,
            place_context=args.place or tags.get("addr:city"),
        )

        if photo:
            resolved += 1
            print(f"{i:4}/{len(rows)}  HIT  {(name or row['id'])[:38]:38}  "
                  f"{photo['photo_license'][:16]:16}  {photo['photo_url'][:60]}")
            if args.apply:
                client.table("locations").update({
                    "photo_url": photo["photo_url"],
                    "photo_attribution": photo["photo_attribution"],
                    "photo_license": photo["photo_license"],
                    "photo_source_url": photo["photo_source_url"],
                }).eq("id", row["id"]).is_("photo_url", "null").execute()
        else:
            print(f"{i:4}/{len(rows)}   .   {(name or row['id'])[:38]:38}")

        sys.stdout.flush()
        time.sleep(DELAY_S)

    if not rows:
        print("\nnothing to do")
        return 0
    print(f"\nresolved {resolved}/{len(rows)} ({100 * resolved / len(rows):.1f}%)")
    if resolved and not args.apply:
        print("dry run — nothing written. Re-run with --apply to persist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
