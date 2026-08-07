"""Overpass client — Stage 1 (Fetch) of the route-generation funnel.

docs/backend/12 specifies the query shape: tourism/historic/natural POIs,
explicitly excluding accommodation, information boards, and gift shops,
which dominate an unfiltered feed and are never a stop on a tour.
"""
from __future__ import annotations

import concurrent.futures
import logging
import math
import re
import threading
import time
import unicodedata

import requests

from config import Config

logger = logging.getLogger(__name__)

# Note what `GET /api/status` reports for these three:
#
#   overpass-api.de      -> announced endpoint lambert.openstreetmap.de
#   z.overpass-api.de    -> announced endpoint gall.openstreetmap.de
#   lz4.overpass-api.de  -> announced endpoint lambert.openstreetmap.de
#
# Three hostnames, **two** actual servers — overpass-api.de and lz4 are the
# same machine. So the list buys less redundancy than it looks like, and a bad
# minute on lambert takes out two thirds of it at once.
OVERPASS_MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
]

# The same status endpoint reports `Rate limit: 2` — two concurrent queries
# per client IP across the whole service, not per host. Hedging three at once
# therefore *guarantees* the third is refused, and a burst of requests spends
# slots that then aren't there for the real one. Capping in-flight requests at
# the documented limit is the difference between hedging and self-inflicted
# 504s.
MAX_CONCURRENT_MIRRORS = 2

TIMEOUT_S = 30

# Mirrors are hedged rather than tried strictly in sequence: the next one is
# started if the previous hasn't answered within this window, and the first
# usable response wins. Overpass mirror latency is wildly bimodal — a loaded
# public instance can sit on a request for its full 25 s timeout before
# failing, which under the old sequential loop put a 50–75 s floor under a
# route request. Hedging bounds that at roughly one slow mirror's wait.
#
# Deliberately a delay rather than firing all three at once: three copies of
# every query is not fair use of a free shared service, and in the common case
# where the first mirror is healthy the others are never sent at all.
HEDGE_DELAY_S = 5.0

# One extra pass over the mirrors after a pause. A 504 from a public Overpass
# instance means "busy right now", not "no data here" — the same bbox that
# 504'd on one attempt answers in a few seconds on the next. Without this a
# momentary wobble is indistinguishable from an empty area, and the user gets
# an empty route (which is exactly what happened).
RETRY_PASSES = 2
RETRY_BACKOFF_S = 3.0

# How close two objects must be before a shared name or Wikidata id is read
# as "same place". Sized from the real misses: the two Martyrs Memorial
# objects sit 61 m apart, the two Parc de Bentalha ways 121 m, and the Sidi
# Fredj fort and its viewpoint 246 m. Beyond ~250 m a shared name starts
# meaning two genuinely different places (a street and the landmark it is
# named after).
DUPLICATE_RADIUS_M = 250

# Same bbox asked for twice in a row (a retry, a nudged radius, two people in
# the same city) reuses the answer instead of paying Overpass again. POI data
# does not move on this timescale.
_CACHE_TTL_S = 600

# Entries are kept long past their serving TTL so that a failed fetch can fall
# back on the last known-good answer for the area. Hours-old POI data is a far
# better answer than no route at all, and POIs do not move.
_CACHE_RETAIN_S = 24 * 3600

_CACHE_MAX = 64
_cache: dict[tuple, tuple[float, list[dict]]] = {}
_cache_lock = threading.Lock()

_EXCLUDED_TOURISM = {
    "hotel", "hostel", "guest_house", "apartment", "motel", "camp_site",
    "caravan_site", "chalet", "information", "picnic_site",
}

# The same exclusion, pushed down into the query instead of only being applied
# to the response. Accommodation and information boards are the bulk of
# `tourism=*` in any city, and every one of them was being matched, serialized,
# transferred and then dropped by `_category_from_tags`.
#
# This cannot lose a POI: the union's other clauses are unconditional, so a
# hotel that is also `historic=castle` still arrives via `node["historic"]`,
# and a `tourism=hotel` with nothing else was already discarded on arrival.
_TOURISM_FILTER = '["tourism"!~"^(' + "|".join(sorted(_EXCLUDED_TOURISM)) + ')$"]'

_QUERY_TEMPLATE = """
[out:json][timeout:25];
(
  node["tourism"]%(tourism_filter)s({lat_min},{lng_min},{lat_max},{lng_max});
  way ["tourism"]%(tourism_filter)s({lat_min},{lng_min},{lat_max},{lng_max});

  node["historic"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["historic"]({lat_min},{lng_min},{lat_max},{lng_max});

  node["natural"~"^(peak|cave_entrance|arch|spring|beach|bay|cape|cliff|glacier|volcano|water)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["natural"~"^(beach|bay|cape|cliff|glacier|volcano|water)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["waterway"="waterfall"]({lat_min},{lng_min},{lat_max},{lng_max});

  node["leisure"~"^(park|garden|water_park|beach_resort|stadium)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["leisure"~"^(park|garden|water_park|beach_resort|stadium)$"]({lat_min},{lng_min},{lat_max},{lng_max});

  node["shop"="mall"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["shop"="mall"]({lat_min},{lng_min},{lat_max},{lng_max});
  node["amenity"~"^(marketplace|theatre|cinema|arts_centre)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["amenity"~"^(marketplace|theatre|cinema|arts_centre)$"]({lat_min},{lng_min},{lat_max},{lng_max});
);
out tags bb;
""" % {"tourism_filter": _TOURISM_FILTER}
# `bb` rather than `center`: Overpass's "center" *is* the midpoint of the
# bounding box, so this loses nothing and gains each way's extent — which is
# what lets the route avoid spending three of its eight stops inside one
# archaeological park (see `_enclosing_index` in routes/itinerary.py). Costs
# about 20% more response bytes.


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


# Tag values that say a tag is *present* without saying what the thing is.
# `historic=yes` is the common one, and taken literally it produced the
# category "Yes" on the app's cards — two Algiers mosques shipped labelled
# "Yes" because that is what `historic` said about them.
_UNINFORMATIVE_VALUES = {"yes", "true", "1"}

# `historic` values that are real but still less descriptive of what the
# place *is* than another tag on the same object. "Ketchaoua Mosque —
# Heritage" is worse than "Ketchaoua Mosque — Mosque".
_WEAK_HISTORIC_VALUES = {"heritage", "building", "yes"}

_LEISURE_CATEGORIES = {
    "park": "Park",
    "garden": "Garden",
    "water_park": "Water park",
    "beach_resort": "Beach resort",
    "stadium": "Stadium",
}

_AMENITY_CATEGORIES = {
    "marketplace": "Market",
    "theatre": "Theatre",
    "cinema": "Cinema",
    "arts_centre": "Arts centre",
}

_WORSHIP_BY_RELIGION = {
    "muslim": "Mosque",
    "christian": "Church",
    "jewish": "Synagogue",
    "buddhist": "Temple",
    "hindu": "Temple",
}

# Places that carry a tourism/historic/leisure tag but that nobody can
# actually visit. Embassies are the case that forced this: they are tagged
# `office=diplomatic` *and* `leisure=park` (their walled gardens), which under
# the old rules scored them as parks — four of the top ten Algiers candidates
# were embassies, ahead of the Casbah's mosques.
_EXCLUDED_TAG_VALUES = {
    "office": {"diplomatic", "government", "administrative"},
    "amenity": {"embassy", "prison", "police", "fire_station", "hospital",
                "school", "college", "kindergarten", "fuel", "parking"},
    "diplomatic": None,        # any value at all
    "embassy": None,
    "landuse": {"industrial"},
    # `barrier` is deliberately absent as a blanket rule — historic city walls
    # carry it, and so does the Serkadji Prison museum. See
    # `_is_private_grounds` for the narrow case it does matter in.
}

# Active military installations aren't visitable, but a great many *visitable*
# forts and citadels are tagged `military=*` too (`historic=fort` +
# `military=bunker` is standard). So military tags only exclude when nothing
# else says the object is a heritage site.
_MILITARY_KEYS = {"military": None, "landuse": {"military"}}


def _is_excluded(tags: dict) -> bool:
    """Whether this object is something a traveller cannot visit, regardless
    of what other tags it happens to carry.

    Only unambiguous cases belong here, because this drops a POI outright. A
    walled compound tagged `leisure=park` is *usually* a private residence but
    sometimes a real monument with poor tagging, so it is penalized in
    `ingestion/scoring.py` rather than excluded — see the note there.
    """
    for key, blocked in _EXCLUDED_TAG_VALUES.items():
        value = tags.get(key)
        if value is None:
            continue
        if blocked is None or value in blocked:
            return True

    historic = tags.get("historic")
    if historic and historic not in _UNINFORMATIVE_VALUES:
        return False
    for key, blocked in _MILITARY_KEYS.items():
        value = tags.get(key)
        if value is not None and (blocked is None or value in blocked):
            return True
    return False


def _clean(value: str) -> str:
    return value.replace("_", " ").capitalize()


def _category_from_tags(tags: dict) -> str | None:
    """Normalizes the several OSM tagging schemes this query touches into one
    display category.

    `historic` still leads — heritage sites are this app's subject — but only
    when it actually says something. A `historic` of `yes`/`heritage`/
    `building` describes the object's status, not its kind, so those fall
    through to whatever tag does describe it (`amenity=place_of_worship`,
    `tourism`, `natural`, …) and are used only as a last resort.
    """
    if _is_excluded(tags):
        return None

    historic = tags.get("historic")
    if historic and historic not in _WEAK_HISTORIC_VALUES:
        return _clean(historic)

    if tags.get("amenity") == "place_of_worship":
        religion = tags.get("religion", "")
        if religion in _WORSHIP_BY_RELIGION:
            return _WORSHIP_BY_RELIGION[religion]
        building = tags.get("building", "")
        if building in ("mosque", "church", "synagogue", "temple", "cathedral", "chapel"):
            return _clean(building)
        return "Place of worship"

    tourism = tags.get("tourism")
    if tourism and tourism not in _EXCLUDED_TOURISM and tourism not in _UNINFORMATIVE_VALUES:
        return _clean(tourism)

    if "natural" in tags:
        return {"peak": "Peak", "cave_entrance": "Cave", "arch": "Natural arch", "spring": "Spring", "beach": "Beach", "bay": "Bay", "cape": "Cape", "cliff": "Cliff", "glacier": "Glacier", "volcano": "Volcano", "water": "Water"}.get(
            tags["natural"], _clean(tags["natural"])
        )
    if tags.get("waterway") == "waterfall":
        return "Waterfall"

    leisure = tags.get("leisure")
    if leisure in _LEISURE_CATEGORIES:
        return _LEISURE_CATEGORIES[leisure]

    # Destination retail and performing arts. Deliberately narrow: `shop=mall`
    # and `amenity=marketplace` are places people set out to visit, whereas
    # `shop=*` in general is every corner store in the city. A route request
    # that says "shopping malls" had nothing to select before this — the
    # Bab Ezzouar mall (`shop=mall`, and it has a Wikidata id) was not merely
    # ranked low, it was never fetched.
    if tags.get("shop") == "mall":
        return "Shopping mall"
    amenity = tags.get("amenity")
    if amenity in _AMENITY_CATEGORIES:
        return _AMENITY_CATEGORIES[amenity]

    # Nothing said what it is, but `historic=heritage` at least says it
    # matters. `historic=yes` says nothing at all and is not a category.
    if historic and historic not in _UNINFORMATIVE_VALUES:
        return _clean(historic)
    if historic:
        return "Historic site"
    return None


_NAME_KEYS = ("name", "alt_name", "int_name", "official_name", "short_name", "reg_name")

# A trailing "2" / "no 2" / "n 3" — a mapper's disambiguation suffix, not part
# of the name. Anchored to the end so "Route 66" or "Place du 1er Novembre"
# (where the number carries meaning mid-name) are untouched.
_TRAILING_INDEX_RE = re.compile(r"\s+(?:no|n|nr|num|numero)?\s*\d{1,2}$")


def _is_real_name(name: str) -> bool:
    """Whether a `name` value names the place or is a catalogue reference.

    Heritage-register ids get tagged as names surprisingly often — Algiers
    alone returns artworks named `214145`, `937605` and `116pa466551`. They
    are unusable on a card and meaningless to the LLM, and they defeat
    deduplication because two references never match.
    """
    letters = sum(1 for c in name if c.isalpha())
    digits = sum(1 for c in name if c.isdigit())
    return letters >= 3 and letters > digits


def _name_from_tags(tags: dict) -> str | None:
    # English-first since only 'en' translations are populated today
    # (docs/backend/09 covers multilingual content; not wired up yet).
    for value in (tags.get("name:en"), tags.get("int_name"), tags.get("name")):
        if value and _is_real_name(value):
            return value
    return None


def _name_variants(tags: dict) -> set[str]:
    """Every name this object is known by, normalized for comparison.

    All languages, deliberately: the duplicate that shows up as two cards is
    usually the *same* subject carrying different display names — a way named
    "Martyrs Memorial" and a node named "مقام الشهداء" whose `name:en` is also
    "martyrs memorial". Comparing display names alone would never catch it.
    """
    out: set[str] = set()
    for key, value in tags.items():
        if not isinstance(value, str):
            continue
        if key not in _NAME_KEYS and not key.startswith("name:"):
            continue
        # OSM packs multiple values into one tag with semicolons
        # ("Dar Aziza;Palais de la Djenina"), and a merged duplicate's name is
        # appended to `alt_name` the same way below.
        for part in value.split(";"):
            part = part.strip()
            if not _is_real_name(part):
                continue
            normalized = " ".join(_normalize_name(part).split())
            if not normalized:
                continue
            out.add(normalized)
            # Mappers disambiguate a second object for one subject by
            # suffixing a number — "Martyrs Memorial" the monument and
            # "Martyrs Memorial 2" the viewpoint node 94 m away. Comparing
            # the de-numbered form too catches those without merging places
            # that merely sit near each other.
            base = _TRAILING_INDEX_RE.sub("", normalized).strip()
            if base and base != normalized and len(base) >= 4:
                out.add(base)
    return out


def _normalize_name(text: str) -> str:
    """Fold to a comparable form: strip Latin accents, apply the standard
    Arabic orthographic normalizations, lowercase, punctuation to spaces.

    Same folding as `ingestion/photos.py` uses, and for the same reason — OSM
    disagrees with itself about أ vs ا and about accents ("ilot 661" vs
    "ÎLOT 661", 7 m apart, two cards for one artwork).
    """
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower()
    text = re.sub("[أإآٱ]", "ا", text)
    text = text.replace("ة", "ه").replace("ى", "ي").replace("ـ", "")
    return "".join(c if c.isalnum() else " " for c in text)


def _split_multi(value: str | None) -> list[str]:
    """OSM's semicolon-separated multi-value convention."""
    return [part.strip() for part in (value or "").split(";") if part.strip()]


def _richness(poi: dict) -> tuple:
    """Sort key for "which of these duplicates should survive". Prefers a
    knowledge-base link, then a specific category, then raw tag count."""
    tags = poi["tags"]
    return (
        1 if (tags.get("wikidata") or tags.get("wikipedia")) else 0,
        1 if tags.get("wikimedia_commons") else 0,
        0 if poi["category"] in ("Attraction", "Historic site", "Place of worship") else 1,
        len(tags),
    )


def _deduplicate(pois: list[dict]) -> list[dict]:
    """Collapse POIs that are the same real-world subject.

    OSM routinely holds one place several times — a way for the building and
    a node for the viewpoint on top of it, or two ways digitized by different
    mappers — each with its own name in its own language. Untouched, they
    become separate cards in the same route: Algiers returned "Martyrs
    Memorial" (way), "Martyrs Memorial" (node, tagged as a viewpoint) and
    "MaQam echahid" (node) — three cards, 61 m apart, all the same monument.

    Two objects are the same subject when they are **close together** and
    either share a Wikidata id or share a name variant. Both halves are
    required. Proximity alone is wrong (a café next to a mosque is not the
    mosque) and identity alone is wrong too — `Ben Aknoun Zoo` and `Ben Aknoun
    Amusement Park` carry the same Wikidata id 1.8 km apart and are genuinely
    two places.

    The survivor is the richest record, and it inherits the others' tags, so
    name variants and any `wikidata`/`wikipedia` link from a dropped duplicate
    still reach photo resolution.
    """
    ordered = sorted(pois, key=_richness, reverse=True)
    kept: list[dict] = []
    kept_variants: list[set[str]] = []

    for poi in ordered:
        variants = _name_variants(poi["tags"])
        qid = poi["tags"].get("wikidata")

        merged_into = None
        for existing, existing_variants in zip(kept, kept_variants):
            if _distance_m(poi, existing) > DUPLICATE_RADIUS_M:
                continue
            existing_qid = existing["tags"].get("wikidata")
            if (qid and qid == existing_qid) or (variants & existing_variants):
                merged_into = (existing, existing_variants)
                break

        if merged_into is None:
            kept.append(poi)
            kept_variants.append(variants)
            continue

        survivor, survivor_variants = merged_into
        # The survivor's own values win; the duplicate only fills gaps.
        for key, value in poi["tags"].items():
            survivor["tags"].setdefault(key, value)

        # `setdefault` cannot carry over the duplicate's *display* name — the
        # survivor always has a `name` of its own — so it is appended to
        # `alt_name` instead. That name is often the only one in a given
        # language ("MaQam echahid" for the memorial whose `name` is English),
        # and photo resolution matches Commons filenames against exactly these
        # variants, so dropping it would cost real matches.
        dropped_name = poi["tags"].get("name")
        if dropped_name and dropped_name not in _split_multi(survivor["tags"].get("alt_name")):
            if dropped_name != survivor["tags"].get("name"):
                existing_alt = survivor["tags"].get("alt_name")
                survivor["tags"]["alt_name"] = (
                    f"{existing_alt};{dropped_name}" if existing_alt else dropped_name
                )

        survivor_variants |= variants
        survivor["wikidata_qid"] = survivor["wikidata_qid"] or poi.get("wikidata_qid")
        survivor["wikipedia"] = survivor["wikipedia"] or poi.get("wikipedia")

    return kept


def _distance_m(a: dict, b: dict) -> float:
    """Metres between two POIs. Equirectangular rather than haversine — this
    runs O(kept) times per POI and is only ever compared against a 250 m
    threshold, where the two agree to well under a metre."""
    mean_lat = math.radians((a["lat"] + b["lat"]) / 2)
    dx = math.radians(a["lng"] - b["lng"]) * math.cos(mean_lat)
    dy = math.radians(a["lat"] - b["lat"])
    return math.hypot(dx, dy) * 6371000.0


class OverpassError(RuntimeError):
    """Raised when Overpass can't be reached or returns something unusable.

    Deliberately **not** swallowed into an empty list here — that was the
    original design and it produced a real bug during live testing: a 504
    from Overpass (hit for real, mid-ingestion, on a shared public instance)
    resulted in `_ingest_one_tile` finishing with zero POIs and the tile
    getting cached as `fetch_status='ok', poi_count=0` for the normal 60-day
    TTL. That's indistinguishable from "this tile genuinely has nothing in
    it" and silently poisons the cache for two months over a transient
    timeout. Raising here lets `ingestion/ingest.py`'s existing tile-level
    exception handling do the right thing instead — mark the tile `failed`
    with a 1-day retry TTL, which is what already happens for every other
    exception in that path; Overpass failures just weren't reaching it.
    """


def _cache_key(lat_min: float, lng_min: float, lat_max: float, lng_max: float) -> tuple:
    # ~100 m of rounding: finer than that and the cache never hits, because
    # the bbox is derived from a GPS fix that jitters on every request.
    return tuple(round(v, 3) for v in (lat_min, lng_min, lat_max, lng_max))


def _cache_get(key: tuple, *, max_age_s: float = _CACHE_TTL_S) -> list[dict] | None:
    """Cached POIs for a bbox. `max_age_s` is widened by the failure path to
    accept a stale entry rather than return nothing."""
    with _cache_lock:
        entry = _cache.get(key)
        if entry is None:
            return None
        stored_at, pois = entry
        age = time.time() - stored_at
        if age > max_age_s:
            if age > _CACHE_RETAIN_S:
                _cache.pop(key, None)
            return None
        return pois


def _cache_put(key: tuple, pois: list[dict]) -> None:
    with _cache_lock:
        if len(_cache) >= _CACHE_MAX:
            oldest = min(_cache, key=lambda k: _cache[k][0])
            _cache.pop(oldest, None)
        _cache[key] = (time.time(), pois)


def _query_mirror(url: str, query: str) -> list[dict]:
    """One mirror's raw `elements`. Raises on anything unusable."""
    resp = requests.post(
        url,
        data={"data": query},
        headers={"User-Agent": _user_agent()},
        timeout=TIMEOUT_S,
    )
    if resp.status_code == 429:
        raise OverpassError(f"429 Too Many Requests from {url}")
    resp.raise_for_status()
    return resp.json().get("elements", [])


def _fetch_elements(query: str) -> list[dict]:
    """First usable response from any mirror, hedged and then retried.

    A single pass over the mirrors is not enough on a free shared service:
    all three can be busy at the same moment and all three return 504, which
    is a temporary state, not an answer about the area.
    """
    last_error: Exception | None = None
    for attempt in range(RETRY_PASSES):
        if attempt:
            time.sleep(RETRY_BACKOFF_S * attempt)
            logger.info("Overpass retry pass %d/%d", attempt + 1, RETRY_PASSES)
        try:
            return _fetch_elements_once(query)
        except OverpassError as e:
            last_error = e
    raise last_error if last_error else OverpassError("Overpass failed with no error recorded")


def _fetch_elements_once(query: str) -> list[dict]:
    """One hedged pass over the mirrors (see HEDGE_DELAY_S)."""
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=len(OVERPASS_MIRRORS))
    try:
        pending: list[concurrent.futures.Future] = []
        settled: set[concurrent.futures.Future] = set()
        last_err: str | None = None

        for index, url in enumerate(OVERPASS_MIRRORS):
            # Never exceed the service's concurrent-query limit: wait for a
            # slot to free up before hedging onto the next mirror.
            while len([f for f in pending if f not in settled]) >= MAX_CONCURRENT_MIRRORS:
                done, _ = concurrent.futures.wait(
                    [f for f in pending if f not in settled], timeout=TIMEOUT_S,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                if not done:
                    break
                for future in done:
                    settled.add(future)
                    try:
                        return future.result()
                    except Exception as e:
                        last_err = str(e)

            pending.append(pool.submit(_query_mirror, url, query))
            is_last = index == len(OVERPASS_MIRRORS) - 1
            # After the last mirror there is nothing left to hedge with, so
            # wait out the full timeout rather than the hedge window.
            window_ends = time.monotonic() + (TIMEOUT_S if is_last else HEDGE_DELAY_S)

            while True:
                # Only ever wait on mirrors that haven't answered yet.
                # Including settled ones would make `wait` return instantly
                # forever after the first failure, and the last iteration
                # would then declare total failure while two mirrors were
                # still in flight.
                outstanding = [f for f in pending if f not in settled]
                remaining = window_ends - time.monotonic()
                if not outstanding or remaining <= 0:
                    break

                done, _ = concurrent.futures.wait(
                    outstanding, timeout=remaining,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                if not done:
                    break  # nothing yet — hedge with the next mirror

                for future in done:
                    settled.add(future)
                    try:
                        return future.result()
                    except Exception as e:
                        last_err = str(e)
                        logger.info("Overpass mirror failed: %s", e)

        raise OverpassError(f"All Overpass mirrors failed. Last error: {last_err}")
    finally:
        # Don't block the caller on mirrors that are still thinking — a
        # hedged request we no longer need must not add its latency to a
        # request we already have an answer for.
        pool.shutdown(wait=False)


def fetch_pois(lat_min: float, lng_min: float, lat_max: float, lng_max: float) -> list[dict]:
    """Raw POIs from Overpass, already filtered to named + categorized and
    deduplicated — the noise Overpass returns alongside real POIs (unnamed
    benches, `tourism=information` signs, embassy compounds tagged as parks,
    heritage-register ids masquerading as names, and the same monument held
    two or three times over) is dropped here rather than passed on to scoring.

    Deduplication lives at this layer on purpose. It is a property of the
    source — OSM genuinely stores one place as several objects — not of any
    one consumer, so both the itinerary path and `ingestion/ingest.py` get it
    without either having to know.

    Raises `OverpassError` on failure — see that class's docstring for why
    this isn't a quiet `[]` return.
    """
    key = _cache_key(lat_min, lng_min, lat_max, lng_max)
    cached = _cache_get(key)
    if cached is not None:
        logger.info("Overpass cache hit for %s (%d POIs)", key, len(cached))
        return cached

    query = _QUERY_TEMPLATE.format(lat_min=lat_min, lng_min=lng_min, lat_max=lat_max, lng_max=lng_max)
    try:
        elements = _fetch_elements(query)
    except OverpassError:
        # Last resort before giving up: the last good answer for this bbox,
        # however old. POIs do not move, and a day-old candidate list beats
        # the empty route a transient 504 would otherwise produce.
        stale = _cache_get(key, max_age_s=_CACHE_RETAIN_S)
        if stale is not None:
            logger.warning("Overpass failed for %s — serving %d stale POIs", key, len(stale))
            return stale
        raise

    pois = []
    for el in elements:
        tags = el.get("tags", {})
        name = _name_from_tags(tags)
        category = _category_from_tags(tags)
        if not name or not category:
            continue

        bounds = None
        if el["type"] == "node":
            poi_lat, poi_lng = el.get("lat"), el.get("lon")
        else:
            bounds = el.get("bounds") or None
            if bounds:
                # Overpass's `center` is defined as the bounding box midpoint,
                # so deriving it here is identical to what `out center` returned.
                poi_lat = (bounds["minlat"] + bounds["maxlat"]) / 2
                poi_lng = (bounds["minlon"] + bounds["maxlon"]) / 2
            else:
                center = el.get("center") or {}
                poi_lat, poi_lng = center.get("lat"), center.get("lon")
        if poi_lat is None or poi_lng is None:
            continue

        pois.append(
            {
                "osm_type": el["type"],
                "osm_id": el["id"],
                "name": name,
                "category": category,
                "lat": poi_lat,
                "lng": poi_lng,
                # None for nodes, which have no extent — an enclosure test
                # against a node is meaningless and is skipped.
                "bounds": bounds,
                "tags": tags,
                "wikidata_qid": tags.get("wikidata"),
                "wikipedia": tags.get("wikipedia"),  # "en:Casbah of Algiers" form
            }
        )

    deduped = _deduplicate(pois)
    if len(deduped) != len(pois):
        logger.info(
            "Overpass %s: %d POIs -> %d after dedupe", key, len(pois), len(deduped)
        )

    _cache_put(key, deduped)
    return deduped
