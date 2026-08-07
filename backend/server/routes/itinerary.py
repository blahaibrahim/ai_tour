"""Stage 3 of the route-generation funnel (docs/backend/08, docs/backend/12):

    1. Fetch    maps API -> raw POIs                    (ingestion/overpass.py)
    2. Score    deterministic interest ranking           (ingestion/scoring.py)
    3. Select   LLM picks + orders from vetted candidates (this file)

## Where candidates come from

Both routes here build candidates by calling Overpass live, through the one
shared `_build_candidates`. They do **not** read the `locations` catalogue.

That is a change from the original design, in which stages 1+2 ran only via
`POST /api/poi/ingest` (routes/poi.py) into Supabase's `locations` table and
this file queried it through the `nearby_locations` RPC. Live Overpass is now
fast enough for the request path (`ingestion/overpass.py` hedges mirrors and
caches by bbox), and it removes a hard dependency on someone having ingested
an area first — a cold city returned only the 8 curated seed rows.

`/api/itinerary` had already moved to live Overpass; `/api/itinerary/modify`
had not, and the mismatch was silently destructive. Generate returned
`osm-{type}-{id}` ids, modify validated the client's `existing_stops` against
uuid-keyed catalogue rows, so no current stop was ever a valid pick and every
modify replaced the whole route instead of adjusting it. One builder, one id
space, is what fixes that.

The catalogue still exists and `/api/poi/ingest` still populates it — it is
what `data/locations_repo.py` serves, what semantic search runs over, and the
**fallback** when Overpass is unreachable (`_catalogue_candidates`). Overpass
is a free shared service that really does return 504 on all three mirrors at
once; when it does, a stale-but-real candidate list is the difference between
a usable route and an empty screen.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from data.geo import haversine_km, get_travel_time_matrix
from data.locations_repo import locations_within_radius
from json_utils import extract_json
from llm import chat, LLMError
from rate_limit import authenticate_and_rate_limit
from ingestion.supabase_admin import get_admin_client
from ingestion.overpass import fetch_pois
from ingestion.scoring import compute_score
from ingestion.photos import resolve_photo, resolve_nearby_photo
from ingestion.wikipedia import fetch_summary
from ingestion.describe import collect_facts, describe
import concurrent.futures
import logging
import math
import re
import threading
import time

itinerary_bp = Blueprint("itinerary", __name__)

MAX_RADIUS_KM = 500
MAX_WANTED_VISITS = 20

# How many of the ranked candidates get their photo fetched. Photo resolution
# is several HTTP round trips per POI, and it used to run *after* the LLM had
# picked — pure added latency at the end of the request. Fetching the top of
# the ranked list while the model is still choosing makes it nearly free,
# since the picks come from that top slice. A few extra fetches for candidates
# that don't get picked cost nothing on the critical path.
PHOTO_PREFETCH = 16

# How many ranked candidates are kept at all.
CANDIDATE_LIMIT = 50

# Ranked candidates offered to the model. 50 lines of blurb is a large prompt
# for a choice that is effectively made in the top half of the list.
LLM_CANDIDATE_LIMIT = 30

# Blurbs are context for the pick, not content — the full text goes to the
# client from the candidate record either way.
BLURB_CHARS_FOR_LLM = 140

# Ceiling on how long the finished route waits for outstanding photo and
# description lookups. A missing thumbnail is a placeholder in the UI; a route
# that never arrives is a broken feature. Raised from 8 s once the nearby-photo
# fallback was added: the extra Commons round trips were pushing the *most*
# interesting stops past the deadline, so the mall with a Wikipedia article
# came back with no image at all while its neighbours got one.
PHOTO_WAIT_S = 14.0

# Card-sized. Long enough for a real opening paragraph, short enough that the
# card stays a card.
BLURB_MAX_CHARS = 320


def _order_nearest_neighbor(start_lat: float, start_lng: float, stops: list[dict]) -> list[dict]:
    """Greedy nearest-neighbor ordering from the user's position. This is the
    "geometry chooses the order" half of docs/backend/08's Feature 1 — the
    LLM is never asked to do this."""
    remaining = list(stops)
    ordered = []
    cur_lat, cur_lng = start_lat, start_lng
    while remaining:
        nxt = min(
            remaining,
            key=lambda s: haversine_km(cur_lat, cur_lng, s["lat"], s["lng"]),
        )
        ordered.append(nxt)
        # Identity, not equality: `remove` drops the first *equal* dict, which
        # for two stops with the same fields is not necessarily this one.
        remaining = [s for s in remaining if s is not nxt]
        cur_lat, cur_lng = nxt["lat"], nxt["lng"]
    return ordered


def _order_travel_time(start_lat: float, start_lng: float, stops: list[dict]) -> list[dict]:
    """Order stops using real road travel times. Falls back to nearest-neighbor
    haversine if the OSRM routing engine fails or returns invalid data."""
    if not stops:
        return []

    coords = [(start_lat, start_lng)] + [(s["lat"], s["lng"]) for s in stops]
    matrix = get_travel_time_matrix(coords)

    if matrix is None:
        return _order_nearest_neighbor(start_lat, start_lng, stops)

    # Greedy nearest-neighbor using travel time instead of straight line.
    # Positions are captured up front by identity: the old `stops.index(stop)`
    # both rescanned the list on every comparison and returned the *first*
    # equal dict, which silently mis-indexed the matrix whenever two stops
    # compared equal.
    matrix_index = {id(s): i + 1 for i, s in enumerate(stops)}
    remaining = list(stops)
    ordered = []
    cur_idx = 0  # 0 is the start point

    while remaining:
        best_time = float("inf")
        best_stop = None
        best_stop_idx = -1

        for stop in remaining:
            stop_idx = matrix_index[id(stop)]
            # duration from cur_idx to stop_idx
            time_s = matrix[cur_idx][stop_idx]
            if time_s is not None and time_s < best_time:
                best_time = time_s
                best_stop = stop
                best_stop_idx = stop_idx

        if best_stop is None:
            # Should only happen if matrix has nulls (unroutable). 
            # Fall back to appending remaining by haversine distance.
            ordered.extend(_order_nearest_neighbor(
                coords[cur_idx][0], coords[cur_idx][1], remaining
            ))
            break
            
        ordered.append(best_stop)
        remaining = [s for s in remaining if s is not best_stop]
        cur_idx = best_stop_idx

    return ordered


def _select_with_llm(candidates: list[dict], prompt: str, wanted_visits: int | None, existing_stops: list[dict] = None) -> list[dict]:
    """Returns a list of {location_id, reason, suggested_order} dicts, already
    validated against `candidates`. Never returns an id the model invented."""
    candidate_lines = "\n".join(
        f"- id={c['id']} | {c['name']} | {c['category']} | {c.get('region', 'Algeria')} | "
        f"{c.get('distance_km', 0):.1f} km away | {(c.get('blurb') or '')[:BLURB_CHARS_FOR_LLM]}"
        for c in candidates
    )
    visits_line = (
        f"You MUST select exactly 8 stops (or all of them if there are fewer than 8 candidates). They eventually want to reach {wanted_visits} stops."
        if wanted_visits
        else "You MUST select exactly 8 stops (or all of them if there are fewer than 8 candidates)."
    )

    messages = [
        {
            "role": "system",
            "content": (
                "You are planning a walking/driving tour in Algeria. Every "
                "candidate location has already been verified to exist and to "
                "be worth visiting — your job is fit to the traveller's "
                "request, not quality. Choose ONLY from the given candidates "
                "and never invent a location. Reply with a single JSON object "
                'shaped exactly like: {"stops": [{"location_id": "...", '
                '"reason": "one sentence, addressed to the traveller", '
                '"suggested_order": 0}]}. No prose outside the JSON.'
            ),
        },
        {
            "role": "user",
            "content": (
                f'Traveller\'s request: "{prompt}"\n'
                f"{visits_line}\n\n"
                + (f"Currently they have these stops: {', '.join(s.get('name', 'Unknown') for s in existing_stops)}\n" if existing_stops else "") +
                f"Candidates:\n{candidate_lines}"
            ),
        },
    ]

    # This call is the whole route's critical path — the user is on the
    # thinking screen for exactly as long as it takes. Picking 8 ids out of a
    # pre-vetted list is a selection task, not a reasoning one: every
    # candidate has already been verified and scored before it gets here, and
    # anything the model invents is rejected below regardless. So it asks for
    # the fast provider and minimal thinking; both fall back exactly as
    # before if that path is unavailable. Measured on this prompt: ~1.6s here
    # against ~16s for the previous gemini/'medium' default, same 8 stops.
    raw = chat(
        messages,
        json_mode=True,
        max_tokens=1024,
        temperature=0.6,
        thinking_level="minimal",
        prefer="groq",
    )
    try:
        parsed = extract_json(raw)
        stops = parsed.get("stops")
        if not isinstance(stops, list):
            stops = []
    except Exception as e:
        import logging
        logging.error(f"Failed to extract JSON from LLM: {raw}")
        raise ValueError("Could not parse LLM output") from e

    candidate_ids = {c["id"] for c in candidates}
    valid = []
    for s in stops:
        if isinstance(s, dict) and s.get("location_id") in candidate_ids:
            # Safely capture the reason
            s["reason"] = s.get("reason", "")
            valid.append(s)
            
    # If the LLM somehow didn't select enough, pad with top available candidates
    if len(valid) < (wanted_visits or 8):
        valid_ids = {s["location_id"] for s in valid}
        for c in candidates:
            if c["id"] not in valid_ids:
                valid.append({"location_id": c["id"], "reason": "A great addition to your route."})
                valid_ids.add(c["id"])
            if len(valid) >= (wanted_visits or 8):
                break
                
    return valid[:(wanted_visits or 8)]

def _build_candidates(
    lat: float,
    lng: float,
    radius_km: float,
    *,
    skip_ids: set[str] | frozenset[str] = frozenset(),
    limit: int = CANDIDATE_LIMIT,
    prompt: str = "",
) -> list[dict]:
    """Ranked POI candidates around a point, from Overpass.

    The single source of candidates for both `/api/itinerary` and
    `/api/itinerary/modify`. They used to disagree, and not harmlessly:
    generate built `osm-{type}-{id}` candidates from Overpass, while modify
    queried the `locations` table for uuid-keyed rows. So the ids the client
    sent back in `existing_stops` — all `osm-*`, since that is what generate
    returned — never appeared in modify's candidate set, `candidate_ids`
    rejected every one of them, and "keep the stops you already have" was
    unrepresentable. Every modify silently replaced the whole route with
    catalogue rows, and once the catalogue was empty, with the curated 8.

    Rejected/accepted ids are filtered before the trim rather than after, so
    a swiped-away stop no longer consumes one of the `limit` slots.
    """
    search_radius = max(radius_km, 15.0)
    lat_delta = search_radius / 111.0
    lng_delta = search_radius / (111.0 * math.cos(math.radians(lat)))

    try:
        raw_pois = fetch_pois(
            lat - lat_delta, lng - lng_delta, lat + lat_delta, lng + lng_delta
        )
    except Exception:
        # Overpass is a free shared service and it does go down. It has
        # already retried and already tried its own stale cache by this point,
        # so this is the last line before the user gets nothing — and getting
        # nothing is what a Tipaza request got when all three mirrors returned
        # 504 at the same moment. The catalogue is a worse answer than live
        # OSM but an incomparably better one than an empty route.
        logging.exception("Overpass unavailable for (%s, %s) — falling back to catalogue", lat, lng)
        return _catalogue_candidates(lat, lng, radius_km, skip_ids=skip_ids, limit=limit)

    candidates = []
    for poi in raw_pois:
        candidate_id = f"osm-{poi['osm_type']}-{poi['osm_id']}"
        if candidate_id in skip_ids:
            continue
        score, _ = compute_score(
            category=poi["category"], name=poi["name"], osm_tags=poi["tags"],
            wikidata_match=None, wikipedia_found=False, pageviews_30d=None,
            has_photo=False,
        )
        if score < 0:
            continue
        candidates.append({
            "id": candidate_id,
            "name": poi["name"],
            "category": poi["category"],
            "lat": poi["lat"],
            "lng": poi["lng"],
            "bounds": poi.get("bounds"),
            "tags": poi["tags"],
            "interest_score": score,
            "wikipedia": poi.get("wikipedia"),
            "wikidata_qid": poi.get("wikidata_qid"),
            "distance_km": haversine_km(lat, lng, poi["lat"], poi["lng"]),
            # `ingestion/describe.py` exists precisely to replace the
            # "A {category} point of interest." template that used to be here,
            # and this path never called it — so every generated stop carried
            # a blurb like "A park point of interest." or "A ruins point of
            # interest.", which is what made the descriptions read as generic.
            # `use_llm=False` keeps it deterministic and free: this runs for
            # every candidate on the request path, where 50 LLM calls is not
            # a trade worth making.
            "blurb": describe(
                collect_facts(
                    name=poi["name"],
                    category=poi["category"],
                    tags=poi["tags"],
                    place=poi["tags"].get("addr:city"),
                ),
                use_llm=False,
            ),
        })

    return _merge_by_relevance(candidates, search_radius, prompt, limit)


def _merge_by_relevance(
    candidates: list[dict], search_radius_km: float, prompt: str, limit: int
) -> list[dict]:
    """Rank, reserving room for what the traveller asked for.

    A single ranked sort with a relevance bonus does not work here, and the
    measurement is unambiguous: "shopping malls" in Bab Ezzouar filled all 50
    candidate slots with malls and markets, so the model's only possible
    answer was eight shopping centres in a row. Too small a bonus and the
    requested category never survives the trim at all — which is the bug this
    started as.

    Neither is a ranking problem, so it isn't solved with a weight. The
    requested category gets a guaranteed *share* of the list and the rest is
    filled on merit, so asking for malls returns the malls plus the city's
    actual landmarks, and the model chooses the mix.
    """
    terms = _prompt_terms(prompt)
    ranked = sorted(
        candidates, key=lambda x: _rank(x, search_radius_km), reverse=True
    )
    if not terms:
        return ranked[:limit]

    matched = [c for c in ranked if _matches_prompt(c, terms)]
    others = [c for c in ranked if not _matches_prompt(c, terms)]

    reserved = min(len(matched), max(1, int(limit * PROMPT_RESERVED_SHARE)))
    out = matched[:reserved]
    seen = {id(c) for c in out}
    for candidate in others + matched[reserved:]:
        if len(out) >= limit:
            break
        if id(candidate) not in seen:
            out.append(candidate)
            seen.add(id(candidate))
    return out


# What a stop at the very edge of the search radius gives up against one on
# the doorstep. Roughly the gap between a wikidata-linked landmark and an
# unremarkable park, so a real landmark across town still outranks filler
# next door, but two comparable places sort near-first.
DISTANCE_PENALTY_AT_EDGE = 8.0


# The share of the candidate list guaranteed to what the traveller asked for.
# 40% of 50 leaves 30 slots for the area's actual landmarks, so a request for
# malls yields malls *and* the Casbah rather than one or the other.
PROMPT_RESERVED_SHARE = 0.4


def _prompt_terms(prompt: str) -> set[str]:
    """Distinctive words from the request, for matching against candidates."""
    if not prompt:
        return set()
    words = {w for w in re.split(r"[^\w]+", prompt.lower()) if len(w) >= 4}
    return words - _PROMPT_STOPWORDS


# Words that say nothing about *what* to visit and would match everything.
_PROMPT_STOPWORDS = {
    "want", "would", "like", "some", "something", "please", "with", "near",
    "nearby", "around", "visit", "visiting", "show", "find", "give", "take",
    "there", "that", "this", "then", "from", "into", "about", "have", "need",
    "really", "maybe", "just", "also", "more", "most", "very", "good", "nice",
    "place", "places", "area", "areas", "trip", "tour", "route", "stop",
    "stops", "day", "days", "time", "kind", "type", "thing", "things",
}

# Synonyms, so the traveller's word reaches the OSM category it means.
_PROMPT_SYNONYMS = {
    "mall": {"shopping mall"},
    "malls": {"shopping mall"},
    "shopping": {"shopping mall", "market"},
    "shop": {"shopping mall", "market"},
    "shops": {"shopping mall", "market"},
    "souk": {"market"},
    "market": {"market"},
    "markets": {"market"},
    "beach": {"beach", "beach resort"},
    "beaches": {"beach", "beach resort"},
    "museum": {"museum"},
    "museums": {"museum"},
    "mosque": {"mosque"},
    "mosques": {"mosque"},
    "church": {"church"},
    "ruins": {"ruins", "archaeological site"},
    "roman": {"ruins", "archaeological site"},
    "history": {"heritage", "monument", "memorial", "castle", "fort", "ruins"},
    "historic": {"heritage", "monument", "memorial", "castle", "fort", "ruins"},
    "historical": {"heritage", "monument", "memorial", "castle", "fort", "ruins"},
    "park": {"park", "garden"},
    "parks": {"park", "garden"},
    "garden": {"garden", "park"},
    "gardens": {"garden", "park"},
    "nature": {"park", "garden", "peak", "beach", "cave"},
    "view": {"viewpoint", "peak"},
    "views": {"viewpoint", "peak"},
    "viewpoint": {"viewpoint", "peak"},
    "theatre": {"theatre"},
    "theater": {"theatre"},
    "cinema": {"cinema"},
    "art": {"arts centre", "artwork", "gallery", "museum"},
    "food": {"market"},
    "eat": {"market"},
}


def _matches_prompt(candidate: dict, terms: set[str]) -> bool:
    """Whether the traveller asked for this kind of place, by category or name."""
    if not terms:
        return False
    category = (candidate.get("category") or "").lower()
    name = (candidate.get("name") or "").lower()
    for term in terms:
        if term in category or term in name:
            return True
        if category in _PROMPT_SYNONYMS.get(term, ()):
            return True
    return False


def _rank(candidate: dict, search_radius_km: float) -> float:
    """Interest, discounted by how far out of the way it is.

    The distance penalty is a fraction of the radius the user actually asked
    for, not a flat 2 points per km. The flat version silently made the radius
    setting meaningless: at 2/km, anything past ~5 km was outscored by
    whatever park happened to be nearest, so asking for 50 km returned the
    same handful of doorstep POIs as asking for 5.

    Relevance to the traveller's request is deliberately *not* folded in here
    — see `_merge_by_relevance`, which reserves list slots instead. A bonus
    large enough to guarantee a requested category survives the trim is also
    large enough to let it take every slot.
    """
    distance = candidate.get("distance_km", 0.0)
    reach = max(search_radius_km, 1.0)
    penalty = DISTANCE_PENALTY_AT_EDGE * min(distance / reach, 1.5)
    return candidate.get("interest_score", 0) - penalty


def _catalogue_candidates(
    lat: float,
    lng: float,
    radius_km: float,
    *,
    skip_ids: set[str] | frozenset[str] = frozenset(),
    limit: int = CANDIDATE_LIMIT,
) -> list[dict]:
    """Candidates from the `locations` catalogue, shaped like Overpass ones.

    Only used when live Overpass is unreachable. `locations_repo` degrades
    further on its own — to the curated seed set — so this returns a non-empty
    list even against an empty catalogue, which is the whole point of it.
    """
    rows = locations_within_radius(lat, lng, radius_km, limit=limit)
    candidates = []
    for row in rows:
        if row["id"] in skip_ids:
            continue
        candidates.append({
            "id": row["id"],
            "name": row.get("name") or "",
            "category": row.get("category") or "Attraction",
            "lat": row["lat"],
            "lng": row["lng"],
            "tags": {},
            # Catalogue rows are pre-vetted at ingestion time, so they enter
            # at a flat baseline rather than being re-scored from tags they
            # no longer carry.
            "interest_score": 20,
            "wikipedia": None,
            "wikidata_qid": None,
            "region": row.get("region"),
            "distance_km": row.get("distance_km")
                or haversine_km(lat, lng, row["lat"], row["lng"]),
            "blurb": row.get("blurb") or "",
            "photo_url": row.get("photo_url"),
        })
    return candidates[:limit]


def _encloses(outer: dict, inner: dict) -> bool:
    """Whether `inner`'s position falls inside `outer`'s footprint.

    Only ways carry a footprint; a node has no extent, so it can contain
    nothing. `outer is inner` is excluded so a stop never encloses itself.
    """
    if outer is inner:
        return False
    bounds = outer.get("bounds")
    if not bounds:
        return False
    return (
        bounds["minlat"] <= inner["lat"] <= bounds["maxlat"]
        and bounds["minlon"] <= inner["lng"] <= bounds["maxlon"]
    )


def _drop_enclosed(stops: list[dict], candidates: list[dict], wanted: int) -> list[dict]:
    """Keep at most one stop per enclosing site, then backfill.

    This is the "three cards for one place" fix. Tipaza's archaeological park
    is a single 951 m way that contains the Roman theatre, the amphitheatre,
    the Villa des Fresques, the nymphaeum and the site museum as separate OSM
    ways. Each is a legitimately distinct object with its own Wikidata id, so
    no name- or id-based rule treats them as duplicates — but a route that
    spends three of its eight stops inside one park, on one ticket, reads as
    duplicated to the person holding the phone, which is exactly how it was
    reported.

    Note this is deliberately a *route* rule and not a catalogue rule. The
    candidates all survive; only the itinerary is thinned. Size thresholds
    were tried first and don't separate the cases — Tipaza's park is 951 m
    across and the Casbah of Algiers is 1387 m, but the Casbah's contents
    (Ketchaoua Mosque, Serkadji Prison) are independently worth their own
    stop while Tipaza's are features of one visit. Capping at one stop per
    enclosure gets both right without having to tell them apart.

    The enclosing site is the one kept: it is what you navigate to, and it
    carries the name and the photograph.
    """
    kept: list[dict] = []
    for stop in stops:
        if any(_encloses(other, stop) for other in stops if other is not stop):
            continue  # a larger selected stop already covers this one
        kept.append(stop)

    if len(kept) >= len(stops):
        return kept

    # Backfill so a thinned route still offers a full day out.
    chosen_ids = {s["id"] for s in kept}
    for candidate in candidates:
        if len(kept) >= wanted:
            break
        if candidate["id"] in chosen_ids:
            continue
        if any(_encloses(k, candidate) or _encloses(candidate, k) for k in kept):
            continue
        kept.append({**candidate, "reason": "Added to round out your route."})
        chosen_ids.add(candidate["id"])
    return kept


def _photo_for(candidate: dict) -> dict | None:
    """The photo fields for one candidate, or None. Never raises — a route
    without a photo is fine, a route that failed because of one is not.

    Coordinates and name variants are passed, which turns on the
    coordinate-anchored discovery tiers in `ingestion/photos.py` (geotagged
    Commons files, nearby Wikipedia articles, then Openverse). Without them
    only the structured tiers ran, so a POI that OSM never linked to Wikidata
    or Wikipedia could never get a photo at all — and that is most of them:
    4 of 12 Tipaza candidates resolved an image, the other 8 showed the
    placeholder.

    Those tiers are several more HTTP round trips, which is affordable only
    because this now runs prefetched underneath the LLM call rather than
    after it, under `PHOTO_WAIT_S`.
    """
    try:
        wiki = candidate.get("wikipedia")
        if wiki and ":" in wiki:
            wiki = wiki.split(":", 1)[1]
        tags = candidate.get("tags") or {}
        exact = resolve_photo(
            wikipedia_title=wiki,
            wikidata_image_filename=None,
            osm_tags={"name": candidate.get("name", ""), **tags},
            wikidata_qid=candidate.get("wikidata_qid"),
            name=candidate.get("name"),
            lat=candidate.get("lat"),
            lng=candidate.get("lng"),
            # The containing city, which the Openverse tier needs to tell this
            # place from a same-named one on another continent, and which the
            # other tiers use to stop a city name alone counting as a match.
            place_context=(
                tags.get("addr:city")
                or tags.get("addr:province")
                or candidate.get("region")
            ),
        )
        if exact:
            return {**exact, "photo_is_stock": False}

        # Nothing depicting this place exists that we can verify. Rather than
        # the empty placeholder, offer a real photograph of the surroundings
        # and mark it — see `resolve_nearby_photo`, and note the client shows
        # a "Nearby photo" chip so this is never passed off as the subject.
        if candidate.get("lat") is not None and candidate.get("lng") is not None:
            return resolve_nearby_photo(lat=candidate["lat"], lng=candidate["lng"])
        return None
    except Exception:
        return None


def _wikipedia_blurb(candidate: dict) -> str | None:
    """The opening of this place's own Wikipedia article, if it has one.

    The OSM-derived description is honest but thin — "A mall.", "A
    marketplace." — because it may only state what the tags state. Where a
    Wikipedia article exists, its first sentences are real, sourced prose
    about this specific place, which is what the cards were missing.
    """
    wiki = candidate.get("wikipedia")
    if not wiki:
        return None
    tags = candidate.get("tags") or {}
    lang, _, title = wiki.partition(":") if ":" in wiki else ("en", "", wiki)
    lang = lang or "en"
    title = title or wiki

    # English first, whatever language OSM happened to tag. The `wikipedia`
    # tag on Algerian POIs is as often `fr:` or `ar:` as `en:`, and taking it
    # at face value put a French paragraph on the Bab Ezzouar mall card and an
    # Arabic one on Riadh El Feth — correct, sourced, and unreadable to
    # someone using the app in English.
    attempts: list[tuple[str, str]] = []
    english_tag = tags.get("wikipedia:en")
    if english_tag:
        attempts.append(("en", english_tag.partition(":")[2] or english_tag))
    if lang == "en":
        attempts.append(("en", title))
    else:
        english_name = tags.get("name:en")
        if english_name:
            attempts.append(("en", english_name))
        # The tagged article last: real prose in the wrong language still
        # beats "A marketplace."
        attempts.append((lang, title))

    extract = None
    for attempt_lang, attempt_title in attempts:
        try:
            summary = fetch_summary(attempt_title, lang=attempt_lang)
        except Exception:
            continue
        extract = (summary or {}).get("extract")
        if extract:
            break
    if not extract:
        return None
    extract = " ".join(extract.split())
    if len(extract) <= BLURB_MAX_CHARS:
        return extract
    # Cut on a sentence boundary so the card never ends mid-clause.
    cut = extract[:BLURB_MAX_CHARS]
    stop = max(cut.rfind(". "), cut.rfind("! "), cut.rfind("? "))
    return (cut[: stop + 1] if stop > 80 else cut.rstrip() + "…")


def _finalize_stops(
    start_lat: float,
    start_lng: float,
    stops: list[dict],
    photo_futures: dict,
    photo_pool,
) -> list[dict]:
    """Attach photos and order the route.

    The two are independent — ordering reads only coordinates — so the OSRM
    round trip runs concurrently with whatever photo lookups are still in
    flight instead of after them. Photo waiting is bounded: a slow Commons or
    Openverse tier delays a thumbnail, and must not delay the route.
    """
    if not stops:
        return []

    # Its own executor, not `photo_pool`: submitted there it would queue
    # behind up to PHOTO_PREFETCH photo tasks and lose the overlap entirely.
    order_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
    try:
        order_future = order_pool.submit(_order_travel_time, start_lat, start_lng, stops)

        # Only the chosen stops get a Wikipedia lookup — eight requests, in
        # parallel, for the eight cards the traveller will actually read.
        blurb_futures = {
            s["id"]: photo_pool.submit(_wikipedia_blurb, s)
            for s in stops
            if s.get("wikipedia")
        }

        for stop in stops:
            # A stop carried over from an existing route already has its
            # photo; re-resolving it would spend the same round trips to
            # arrive at the same URL, or worse, at None.
            if stop.get("photo_url") or stop["id"] in photo_futures:
                continue
            # Picked from outside the prefetched slice — fetch it now.
            photo_futures[stop["id"]] = photo_pool.submit(_photo_for, stop)

        photos: dict[str, dict | None] = {}
        deadline = time.monotonic() + PHOTO_WAIT_S
        for stop in stops:
            future = photo_futures.get(stop["id"])
            if future is None:
                continue
            try:
                photos[stop["id"]] = future.result(
                    timeout=max(0.0, deadline - time.monotonic())
                )
            except Exception:
                photos[stop["id"]] = None

        ordered = order_future.result()
    finally:
        order_pool.shutdown(wait=False)

    for stop in ordered:
        photo = photos.get(stop["id"])
        if photo:
            stop.update(photo)
        stop.setdefault("photo_is_stock", False)

        future = blurb_futures.get(stop["id"])
        if future is not None:
            try:
                better = future.result(timeout=max(0.0, deadline - time.monotonic()))
            except Exception:
                better = None
            if better:
                stop["blurb"] = better
    return ordered


def _expand_categories(intent: dict) -> list[str]:
    """Map extracted themes (`llm.extract_intent`) to OSM categories.

    Not currently called: category filtering was designed for the catalogue's
    `nearby_locations(p_categories => ...)` argument, and candidates now come
    from Overpass. Kept because it is the ready-made half of theme-aware
    filtering over `_build_candidates` — wire it in there when the ranking
    needs it, rather than rewriting the mapping.
    """
    rules = {
        "nature": ["Beach", "Peak", "Park", "Waterfall", "Bay", "Cape", "Cliff", "Spring", "Glacier", "Volcano"],
        "history": ["Historic", "Ruins", "Monument", "Castle", "Fort", "Archaeological"],
        "culture": ["Museum", "Art Gallery", "Theatre", "Mosque", "Church", "Library", "Artwork"],
        "food": ["Market", "Restaurant", "Cafe", "Street food", "Bakery"],
        "attraction": ["Attraction", "Theme park", "Zoo", "Aquarium", "Viewpoint"]
    }
    
    categories = set()
    categories.update(intent.get("required_categories", []))
    categories.update(intent.get("preferred_categories", []))
    
    for theme in intent.get("themes", []):
        name = theme.get("name", "").lower()
        for k, v in rules.items():
            if k in name or name in k:
                categories.update(v)
                
    return list(categories)



@itinerary_bp.post("/api/itinerary")
def generate_itinerary():
    user, err = authenticate_and_rate_limit("generate_itinerary", max_requests=30, window="1 hour")
    if err:
        return err

    body = request.get_json(silent=True) or {}

    try:
        lat = float(body["lat"])
        lng = float(body["lng"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "bad_request", "message": "lat and lng are required numbers"}), 400

    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return jsonify({"error": "bad_request", "message": "lat/lng out of range"}), 400

    admin = get_admin_client()
    try:
        job_res = admin.table("route_jobs").insert({
            "user_id": user.id,
            "request_params": body,
            "status": "queued"
        }).execute()
        if not job_res.data:
            return jsonify({"error": "server_error", "message": "Could not create job"}), 500
        job_id = job_res.data[0]["id"]
    except Exception as e:
        return jsonify({"error": "server_error", "message": str(e)}), 500

    def process_job(job_id: str, body: dict):
        photo_pool = None
        try:
            radius_km = min(float(body.get("radius_km", 20)), MAX_RADIUS_KM)
            admin.table("route_jobs").update({"status": "processing"}).eq("id", job_id).execute()

            # Step 2: Route Generation
            prompt = str(body.get("prompt") or "").strip()[:500]
            wanted_visits = body.get("wanted_visits")
            if wanted_visits is not None:
                try:
                    wanted_visits = min(int(wanted_visits), MAX_WANTED_VISITS)
                except (TypeError, ValueError):
                    wanted_visits = None

            rejected_ids = body.get("rejected_ids")
            if not isinstance(rejected_ids, list):
                rejected_ids = []
            accepted_ids = body.get("accepted_ids")
            if not isinstance(accepted_ids, list):
                accepted_ids = []

            try:
                candidates = _build_candidates(
                    lat, lng, radius_km,
                    skip_ids=set(rejected_ids) | set(accepted_ids),
                    prompt=prompt,
                )
            except Exception as e:
                admin.table("route_jobs").update({"status": "failed", "error_message": f"Overpass error: {str(e)}"}).eq("id", job_id).execute()
                return

            existing_stops = body.get("existing_stops")
            if existing_stops and not isinstance(existing_stops, list):
                existing_stops = []

            # Start photo lookups now, against the ranked list, so they run
            # underneath the LLM call instead of after it. The picks come out
            # of the top of this same list, so by the time selection returns
            # most of what's needed is already resolved.
            photo_pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)
            photo_futures = {
                c["id"]: photo_pool.submit(_photo_for, c)
                for c in candidates[:PHOTO_PREFETCH]
            }

            if not prompt and not existing_stops:
                hydrated = [
                    {**c, "reason": "One of the closer highlights to your starting point."}
                    for c in candidates[:min(8, len(candidates))]
                ]
            else:
                try:
                    picked = _select_with_llm(
                        candidates[:LLM_CANDIDATE_LIMIT], prompt, 8, existing_stops
                    )
                    by_id = {c["id"]: c for c in candidates}
                    hydrated = [
                        {**by_id[s["location_id"]], "reason": s.get("reason", "")}
                        for s in picked
                        if s["location_id"] in by_id
                    ]
                except Exception as e:
                    import logging
                    logging.exception(f"LLM generation failed: {e}")
                    raise Exception(f"llm_error: {e}")

            hydrated = _drop_enclosed(hydrated, candidates, wanted=8)
            stops_out = _finalize_stops(lat, lng, hydrated, photo_futures, photo_pool)

            admin.table("route_jobs").update({
                "status": "succeeded",
                "result_data": {"stops": stops_out}
            }).eq("id", job_id).execute()

        except Exception as e:
            admin.table("route_jobs").update({
                "status": "failed",
                "error_message": str(e)
            }).eq("id", job_id).execute()
        finally:
            if photo_pool is not None:
                # Never wait on prefetches for candidates that weren't picked.
                photo_pool.shutdown(wait=False)

    threading.Thread(target=process_job, args=(job_id, body)).start()

    return jsonify({"job_id": job_id})


@itinerary_bp.get("/api/itinerary/job/<job_id>")
def get_itinerary_job(job_id):
    user, err = authenticate_and_rate_limit("get_job", max_requests=1000, window="1 hour")
    if err:
        return err

    admin = get_admin_client()
    import time
    for _ in range(3):
        try:
            res = admin.table("route_jobs").select("*").eq("id", job_id).eq("user_id", user.id).execute()
            if not res.data:
                return jsonify({"error": "not_found"}), 404
            return jsonify(res.data[0])
        except Exception as e:
            if "10035" in str(e) or "ReadError" in str(e) or "timeout" in str(e).lower():
                time.sleep(1)
                continue
            return jsonify({"error": "server_error", "message": str(e)}), 500
            
    return jsonify({"error": "server_error", "message": "Database query timed out"}), 500


@itinerary_bp.get("/api/itinerary/job/latest")
def get_latest_itinerary_job():
    user, err = authenticate_and_rate_limit("get_job", max_requests=1000, window="1 hour")
    if err:
        return err

    admin = get_admin_client()
    res = admin.table("route_jobs").select("*").eq("user_id", user.id).order("created_at", desc=True).limit(1).execute()
    if not res.data:
        return jsonify({"job": None})
        
    return jsonify({"job": res.data[0]})


@itinerary_bp.post("/api/itinerary/modify")
def modify_itinerary():
    """Modify an existing itinerary based on a user's change request (SendAIChangeEvent).

    The key invariant: every location_id in the response must come from the same
    candidate set the original itinerary was built from — the LLM cannot
    promote a location it invented or that scores below the floor. That is why
    this now calls `_build_candidates`, exactly as `/api/itinerary` does,
    instead of the `locations` catalogue: "the same candidate set" was the
    stated invariant but not the implemented one.

    Body:
      lat, lng          (float, required) — user's original departure point
      radius_km         (float, optional, default 20) — search radius
      existing_stops    (list[{id, name, lat, lng, ...}], required) — the current route
      change_request    (str, required) — e.g. "add something with Roman ruins"
    """
    user, err = authenticate_and_rate_limit("modify_itinerary", max_requests=60, window="1 hour")
    if err:
        return err

    body = request.get_json(silent=True) or {}

    try:
        lat = float(body["lat"])
        lng = float(body["lng"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "bad_request", "message": "lat and lng are required numbers"}), 400

    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return jsonify({"error": "bad_request", "message": "lat/lng out of range"}), 400

    existing_stops = body.get("existing_stops")
    if not isinstance(existing_stops, list) or not existing_stops:
        return jsonify({"error": "bad_request", "message": "existing_stops must be a non-empty list"}), 400

    change_request = str(body.get("change_request") or "").strip()[:500]
    if not change_request:
        return jsonify({"error": "bad_request", "message": "change_request is required"}), 400

    radius_km = min(float(body.get("radius_km", 20)), MAX_RADIUS_KM)
    wanted_visits = body.get("wanted_visits")
    if wanted_visits is not None:
        try:
            wanted_visits = min(int(wanted_visits), MAX_WANTED_VISITS)
        except (TypeError, ValueError):
            wanted_visits = None

    # No `embed()` call here any more: its only consumer was the
    # `nearby_locations` RPC's semantic ranking, so with the catalogue out of
    # this path it was a Gemini round trip whose result was discarded — pure
    # latency on a request the user is watching.
    try:
        candidates = _build_candidates(lat, lng, radius_km, prompt=change_request)
    except Exception as e:
        return jsonify({"error": "upstream_unavailable", "message": str(e)}), 503

    # The current stops must themselves be selectable, or "keep the ones I
    # have" cannot be expressed: the model can only answer with ids, and a
    # stop absent from the candidate list has no id to name it by. Overpass
    # normally returns them (they came from it), but a stop just outside a
    # narrowed radius would otherwise be silently undroppable-or-keepable.
    by_id = {c["id"]: c for c in candidates}
    readopted = []
    for stop in existing_stops:
        stop_id = stop.get("id")
        if not stop_id:
            continue
        if stop_id in by_id:
            # Already a candidate. Carry over the photo the client is
            # currently displaying, so a stop the user chose to keep doesn't
            # silently change its image — and so `_finalize_stops` doesn't
            # spend a lookup rediscovering it.
            if stop.get("photo_url") and not by_id[stop_id].get("photo_url"):
                by_id[stop_id]["photo_url"] = stop["photo_url"]
            continue
        if stop.get("lat") is None or stop.get("lng") is None:
            # Pre-existing clients sent only {id, name}; without coordinates
            # it cannot be ordered, so it can't be offered as a candidate.
            continue
        merged = dict(stop)
        merged.setdefault("category", "Attraction")
        merged.setdefault("blurb", "")
        merged.setdefault(
            "distance_km", haversine_km(lat, lng, stop["lat"], stop["lng"])
        )
        by_id[stop_id] = merged
        readopted.append(merged)

    # Current stops go at the head of the offered list, never into the tail
    # that the LLM_CANDIDATE_LIMIT trim discards — otherwise re-adding them as
    # candidates would be undone by the trim for exactly the routes that
    # needed it.
    offered = readopted + candidates[:LLM_CANDIDATE_LIMIT]

    # Build a modify-specific prompt that names existing stops explicitly
    existing_names = [s.get("name", "Unknown") for s in existing_stops]
    candidate_lines = "\n".join(
        f"- id={c['id']} | {c['name']} | {c['category']} | {c.get('region', 'Algeria')} | "
        f"{c.get('distance_km', 0):.1f} km away | {(c.get('blurb') or '')[:BLURB_CHARS_FOR_LLM]}"
        for c in offered
    )
    visits_line = (
        f"The new route should have about {wanted_visits} stops."
        if wanted_visits
        else f"Keep a similar number of stops ({len(existing_stops)}) unless the request says otherwise."
    )

    messages = [
        {
            "role": "system",
            "content": (
                "You are adjusting a walking/driving tour in Algeria. "
                "The traveller has an existing route and wants to change it. "
                "Choose ONLY from the provided candidate locations — never invent a place. "
                'Reply with a single JSON object shaped exactly like: {"stops": [{"location_id": "...", '
                '"reason": "one sentence, addressed to the traveller", '
                '"suggested_order": 0}]}. No prose outside the JSON.'
            ),
        },
        {
            "role": "user",
            "content": (
                f"Current route: {', '.join(existing_names)}\n"
                f"Change request: \"{change_request}\"\n"
                f"{visits_line}\n\n"
                f"Available candidates (include current stops if you keep them):\n{candidate_lines}"
            ),
        },
    ]

    try:
        # Same shape of task as the initial selection, and just as much on the
        # user's waiting path — the AI prompt bar blocks on this response.
        raw = chat(
            messages,
            json_mode=True,
            max_tokens=1024,
            temperature=0.6,
            thinking_level="minimal",
            prefer="groq",
        )
    except LLMError as e:
        return jsonify({"error": "llm_unavailable", "message": str(e)}), 503

    from json_utils import extract_json
    try:
        parsed = extract_json(raw)
        stops = parsed.get("stops")
        if not isinstance(stops, list):
            raise ValueError("LLM response had no 'stops' array")
    except (ValueError, Exception) as e:
        return jsonify({"error": "llm_bad_output", "message": str(e)}), 502

    # Enforce: only ids from the verified candidate set survive. `by_id` is
    # the set actually offered plus the re-adopted current stops, so keeping
    # an existing stop is now a valid answer.
    valid_picks = [
        s for s in stops
        if isinstance(s, dict) and s.get("location_id") in by_id
    ]

    if not valid_picks:
        return jsonify({"error": "no_matches", "message": "No candidates matched that change request"}), 200

    hydrated = [
        {**by_id[s["location_id"]], "reason": s.get("reason", "")}
        for s in valid_picks
    ]

    # Photos and ordering on the same concurrent path the generate route uses.
    # Stops carried over from the current route already have their photo_url
    # and keep it — `_finalize_stops` only overwrites on a positive lookup.
    photo_pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)
    try:
        photo_futures = {
            s["id"]: photo_pool.submit(_photo_for, s)
            for s in hydrated
            if not s.get("photo_url")
        }
        ordered = _finalize_stops(lat, lng, hydrated, photo_futures, photo_pool)
    finally:
        photo_pool.shutdown(wait=False)

    return jsonify({"stops": ordered})


@itinerary_bp.post("/api/itinerary/accept")
def accept_itinerary():
    user, err = authenticate_and_rate_limit("accept_itinerary", max_requests=100, window="1 hour")
    if err:
        return err

    body = request.get_json(silent=True) or {}
    job_id = body.get("job_id")
    accepted_stops = body.get("accepted_stops")
    if not job_id or not isinstance(accepted_stops, list):
        return jsonify({"error": "bad_request"}), 400

    admin = get_admin_client()
    try:
        admin.table("route_jobs").update({
            "status": "accepted",
            "result_data": {"stops": accepted_stops}
        }).eq("id", job_id).eq("user_id", user.id).execute()
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": "server_error", "message": str(e)}), 500
