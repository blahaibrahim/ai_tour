"""Photo resolution — replaces the `picsum.photos` placeholders in
`lib/models/location.dart` with real, licensed photos of the actual place.

## Approaches evaluated

Tested empirically against real ingestion candidates before writing, not
assumed from documentation. The original four:

1. **Wikipedia REST summary thumbnail** (`wikipedia.fetch_summary`) — tested
   against the Casbah and Timgad, returned a correct, appropriately-sized
   thumbnail plus its full-resolution original for both, in the same call
   that already fetches the blurb text. Reliable, free, no extra request.
2. **Wikidata P18** — the per-tile SPARQL query already returns this
   alongside heritage status, so it's nearly free when present. Weaker
   coverage than (1): not every Wikidata item carries a P18 claim even when
   its corresponding Wikipedia article has a lead image.
3. **Wikipedia full-text search**, as a fallback for POIs with no direct
   Wikidata/Wikipedia link — tested with `srsearch=Aqueduc Romain
   Constantine Algeria`. Top (only) hit was "History of the Loiret", a
   French department article with zero relevance. Rejected *in that form*.
4. **Search-engine image discovery**, both general and Commons-restricted —
   general search returned exclusively paid stock-photo licensors (Alamy,
   Dreamstime, Shutterstock), unusable without per-image licensing and
   hotlink-blocked besides. Restricting to `commons.wikimedia.org` looked
   promising — top result literally titled "File:Aqueduc romain.JPG" — but
   that file depicts a bridge in Carrazeda de Ansiães, **Portugal**. A
   silent false positive from a match that looked strong. Rejected *in that
   form*.

## Why tiers 1–4 alone left two thirds of the catalogue with no photo

Measured against the live catalogue: 134 of 203 locations had no photo, and
**132 of those 134 had neither a `wikidata_qid` nor a `wikipedia_title`**.
Every structured tier is inapplicable by construction for that long tail —
it isn't that they were failing, it's that they never ran. Conversely, of
the rows that *did* carry a `wikipedia_title`, zero lacked a photo: tier 1
is ~100% effective whenever it applies.

So the gap is entirely POIs that OSM never linked to a knowledge base. Some
are genuinely unphotographed (an escape room, private embassy grounds, a
node literally named "Ne"); but the misses also included Ketchaoua Mosque,
the Casbah of Algiers, and the Museum of Modern Art — all extensively
photographed on Commons, just not reachable without an ID.

## What closes the gap: anchor on coordinates, then verify by name

The failure mode that sank approaches 3–4 was matching on *text similarity
alone*, which cannot distinguish an Algerian aqueduct from a Portuguese
one. Both new signals below constrain the search geographically first —
Commons and Wikipedia both expose `list=geosearch`, which returns only
items geotagged within a radius of a coordinate — so a Portugal/Algeria
mixup is not representable.

Geography alone is not sufficient either, and this was measured rather than
assumed. Accepting the *nearest* geotagged Commons file within 60m produced
15 matches, and inspection showed them to be mostly wrong subjects: the
well "Bir Jebah" got `Ourida Meddad.jpg` (a portrait of a person), "Beb El
Bhar" got `Voiture ancienne alger.jpg` (an old car), "Kilometre Zero" got a
map of Algiers' municipalities. Photos taken *near* a POI are routinely not
photos *of* it. Proximity-only acceptance is therefore rejected outright.

The rule that works is the conjunction: **within the radius AND sharing a
distinctive name token**. Name matching runs over every name variant OSM
carries (`name`, `name:en`, `name:fr`, `name:ar`, `alt_name`, …) because
Commons filenames for these subjects are frequently French or Arabic
("Mosquée du Dey (Alger)", "تمثال الامير عبد القادر") while the POI's
display name is English. Tokens naming the containing city are excluded
from counting as a match — "Museum of Modern Art of Algiers" matching
`Streets in Algiers 2024 06.jpg` on the token "algiers" alone is exactly
the false positive this guard exists to stop.

## Openverse, in place of scraping a search engine

The remaining tier is an image search engine, but a licensed one: Openverse
(the Creative Commons / WordPress index over Commons, Flickr, and others).
It is used instead of scraping DuckDuckGo/Qwant/Yahoo results — those were
tried and are both bot-blocked (403) and, more fundamentally, return images
with no license metadata, which this module may not store (see
`commons.resolve_commons_file`'s note). Openverse returns `creator`,
`license`, `license_version` and `foreign_landing_url` per result, so the
"never store a photo_url without knowing what it's licensed under" rule
still holds.

Openverse is matched on name tokens under the same guard, because
unguarded it is exactly as credulous as any other text search: querying it
for "Palace of the Dey" returns the Doge's Palace in **Venice** as the top
hit, and "Embassy of France" returns the French embassy in **Armenia**.

Below every tier, this module still returns `None`; the app already has a
placeholder treatment for that case, and a wrong photo is worse than none.
"""
from __future__ import annotations

import logging
import re
import time
import unicodedata
from urllib.parse import unquote

import requests

from config import Config
from ingestion.commons import resolve_commons_file
from ingestion.wikipedia import fetch_summary

logger = logging.getLogger(__name__)

TIMEOUT_S = 15
RETRY_AFTER_FALLBACK_S = 2.0
MAX_RETRY_WAIT_S = 10.0

# Radii for the coordinate-anchored tiers. Deliberately generous for Commons
# files (a photographer standing back from a large building geotags where the
# camera was, not the subject) and tighter for Wikidata, where the coordinate
# is the subject's own and a mismatch means it's a different subject.
COMMONS_GEO_RADIUS_M = 400
WIKIPEDIA_GEO_RADIUS_M = 400
WIKIDATA_VERIFY_RADIUS_M = 250

# Words that carry no subject information, so a match on them alone is not
# evidence the image depicts this POI. Covers the EN/FR/AR generics that
# dominate this catalogue's names.
_GENERIC_TOKENS = {
    "the", "of", "de", "la", "le", "les", "du", "des", "el", "al", "and",
    "et", "in", "at", "sur", "ex", "site", "center", "centre", "parc",
    "park", "jardin", "garden", "plage", "beach", "musee", "museum",
    "statue", "place", "cite", "villa", "ancien", "ancienne", "old", "new",
    "grand", "grande", "petit", "petite", "public", "national", "unesco",
    "world", "heritage", "former", "location", "complexe", "hotel", "photo",
    "file", "image", "view", "vue",
    "حديقة", "شاطئ", "متحف", "قصر", "مسجد", "ساحة", "تمثال", "مقام", "دار",
    "باب", "بئر", "صورة",
}

_ARABIC_RANGE = ("؀", "ۿ")

# Streets are routinely named after the landmark they run past, so a caption
# naming a thoroughfare describes the street, not the landmark. Measured: the
# city gate "Bab Azzoun" matched `Publicité pour la marque de soda Crush en
# mosaïque, rue Bab Azzoun à Alger` — a photo of a soda advert — on a full
# name match, because the street carries the gate's name.
_THOROUGHFARE_TOKENS = {
    "rue", "street", "avenue", "boulevard", "route", "chemin", "impasse",
    "ruelle", "شارع", "نهج", "طريق", "زنقة",
}


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


def _get_json(url: str, params: dict, *, what: str) -> dict | None:
    """GET returning parsed JSON, or None on any failure.

    Retries once on 429/503 honouring `Retry-After`. Wikimedia rate-limits
    a burst of geosearch calls, and the previous code's blanket
    `except Exception: pass` turned that into a silent "no photo found" —
    indistinguishable from a genuine miss, which is how a throttled run can
    look like a broken one.
    """
    for attempt in (0, 1):
        try:
            resp = requests.get(
                url, params=params,
                headers={"User-Agent": _user_agent()},
                timeout=TIMEOUT_S,
            )
            if resp.status_code in (429, 503) and attempt == 0:
                delay = float(resp.headers.get("Retry-After") or RETRY_AFTER_FALLBACK_S)
                logger.info("%s throttled (%s), retrying in %.1fs", what, resp.status_code, delay)
                time.sleep(min(delay, MAX_RETRY_WAIT_S))
                continue
            resp.raise_for_status()
            return resp.json()
        except (requests.RequestException, ValueError) as e:
            logger.warning("%s failed: %s", what, e)
            return None
    return None


def _has_arabic(word: str) -> bool:
    return any(_ARABIC_RANGE[0] <= c <= _ARABIC_RANGE[1] for c in word)


def _normalize(text: str) -> str:
    """Fold to a comparable form: strip Latin accents, apply the standard
    Arabic orthographic normalizations (alef/teh-marbuta/alef-maksura
    variants, tatweel), lowercase, and reduce punctuation to spaces.

    The Arabic folding is not cosmetic — OSM and Commons routinely disagree
    on أ vs ا in the same name, which would otherwise defeat token matching
    on the 64 catalogue rows that carry a `name:ar`.
    """
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower()
    text = re.sub("[أإآٱ]", "ا", text)
    text = text.replace("ة", "ه").replace("ى", "ي").replace("ـ", "")
    return "".join(c if c.isalnum() else " " for c in text)


def _tokens(text: str, extra_stop: frozenset[str] = frozenset()) -> set[str]:
    """Distinctive tokens only — generics, caller-supplied place words, and
    short fragments are dropped. Arabic words are kept at 3+ characters
    (Arabic roots are short and dropping them loses real signal); Latin
    words need 4+, which is what keeps "de"/"la"/"ex" style noise out.
    """
    out = set()
    for word in _normalize(text).split():
        if word in _GENERIC_TOKENS or word in extra_stop:
            continue
        if len(word) < 3:
            continue
        out.add(word)
    return out


def _name_variants(name: str | None, osm_tags: dict) -> list[str]:
    """Every name OSM knows this POI by. Commons filenames for these
    subjects are as often French or Arabic as English, so matching only on
    the display name throws away most of the available signal."""
    variants: list[str] = []
    if name:
        variants.append(name)
    for key, value in (osm_tags or {}).items():
        if not value or not isinstance(value, str):
            continue
        if key == "name" or key.startswith("name:") or key in (
            "alt_name", "official_name", "short_name", "int_name",
        ):
            variants.append(value)
    # Dedupe, preserving order so the display name stays the primary query.
    seen: set[str] = set()
    return [v for v in variants if not (v in seen or seen.add(v))]


def _place_stopwords(osm_tags: dict, place_context: str | None) -> frozenset[str]:
    """Tokens naming the containing city/region, which must not count as a
    subject match on their own (the "Streets in Algiers" false positive)."""
    parts = [place_context or ""]
    for key in ("addr:city", "addr:province", "addr:state", "addr:country", "is_in"):
        value = (osm_tags or {}).get(key)
        if isinstance(value, str):
            parts.append(value)
    stop: set[str] = set()
    for part in parts:
        stop |= {w for w in _normalize(part).split() if len(w) >= 3}
    return frozenset(stop)


def _matches_subject(
    candidate: str,
    variant_tokens: list[set[str]],
    place_stop: frozenset[str],
) -> bool:
    """True when the candidate text contains *every* distinctive token of at
    least one of the POI's name variants.

    Requiring full coverage of a variant rather than any single shared token
    is what separates a real match from a coincidence, and this was measured:
    the any-token rule accepted `Mausolée de Sidi Abderrahmane ben Mohamed
    ben Makhlouf` for "Sidi Mohamed Sharif Mosque" (overlapping on the
    honorific "sidi" and the given name "mohamed" — two tokens, still the
    wrong building) and `Streets in Algiers 2024 06.jpg` for "Museum of
    Modern Art of Algiers". Under full coverage both are rejected, because
    "sharif" and "modern" are absent, while "Ketchaoua Mosque architecture –
    Algiers 8.jpg" still matches "Ketchaoua Mosque" exactly.
    """
    candidate_tokens = _tokens(candidate, place_stop)
    if not candidate_tokens:
        return False
    if not any(tokens and tokens <= candidate_tokens for tokens in variant_tokens):
        return False

    # A caption naming a street is about the street. Only reject when the POI
    # itself isn't a thoroughfare, so an actual named street still matches.
    candidate_words = set(_normalize(candidate).split())
    if candidate_words & _THOROUGHFARE_TOKENS:
        own_words: set[str] = set()
        for tokens in variant_tokens:
            own_words |= tokens
        if not (own_words & _THOROUGHFARE_TOKENS):
            return False
    return True


def _is_tag_dump(text: str) -> bool:
    """Whether a title is a bag of hashtags rather than a caption.

    These defeat name matching by brute force: a title carrying twenty tags
    will contain almost any name's tokens by coincidence. Measured — the
    Flickr title `#algiers #alger #algeria #casbah #oldcity
    #darmustaphapacha ... #palais #palace #dey` fully covers "Palace of the
    Dey" and names the city, passing every other guard, while actually
    depicting Dar Mustapha Pacha, a different building entirely.
    """
    return text.count("#") >= 5


def _mentions_place(candidate: str, place_stop: frozenset[str]) -> bool:
    """Whether the candidate names the POI's city/region.

    Required only by the Openverse tier, which is the one tier with no
    geographic anchor of its own. Full name coverage is not sufficient
    there because a candidate can contain the whole name and still add a
    qualifier that moves it elsewhere: "Embassy of France in Armenia"
    contains every token of "Embassy of France". Demanding the place name
    substitutes for the coordinate filter the other tiers get for free.
    """
    if not place_stop:
        return False
    return bool(place_stop & set(_normalize(candidate).split()))


def _commons_from_url(url: str) -> str | None:
    if not url:
        return None
    # ".../commons/d/d4/AlgerCasbah.jpg" -> "AlgerCasbah.jpg". Deliberately
    # uses `original_url`, not `thumbnail_url` — the latter's "/330px-"
    # size-prefixed final segment would need extra handling to strip.
    # unquote handles accented/spaced filenames the same way wikidata.py
    # does, for the same reason: avoid double-encoding on the next request.
    return unquote(url.rsplit("/", 1)[-1]) or None


def _from_commons_file(filename: str) -> dict | None:
    resolved = resolve_commons_file(filename)
    if not resolved:
        return None
    return {
        "photo_url": resolved["url"],
        "photo_attribution": resolved["attribution"],
        "photo_license": resolved["license"],
        "photo_source_url": resolved["source_url"],
    }


def _from_wikipedia_summary(summary: dict) -> dict | None:
    """A lead image is only usable once its Commons license is known, so this
    always round-trips through `resolve_commons_file` rather than storing the
    REST thumbnail URL on its own."""
    if not summary or not summary.get("thumbnail_url"):
        return None
    filename = _commons_from_url(summary.get("original_url") or "")
    if not filename:
        return None
    resolved = resolve_commons_file(filename)
    if not resolved:
        return None
    return {
        "photo_url": summary["thumbnail_url"],
        "photo_attribution": resolved["attribution"],
        "photo_license": resolved["license"],
        "photo_source_url": resolved["source_url"],
    }


def _commons_geosearch(
    lat: float, lng: float, limit: int = 30, radius_m: int = COMMONS_GEO_RADIUS_M
) -> list[tuple[str, float]]:
    """Commons files geotagged within `radius_m` of the point, nearest first.
    Returns (filename, metres)."""
    data = _get_json(
        "https://commons.wikimedia.org/w/api.php",
        {
            "action": "query",
            "format": "json",
            "list": "geosearch",
            "gscoord": f"{lat}|{lng}",
            "gsradius": radius_m,
            "gslimit": limit,
            "gsnamespace": 6,
        },
        what=f"Commons geosearch {lat},{lng}",
    )
    results = (data or {}).get("query", {}).get("geosearch", [])
    return [(r["title"].removeprefix("File:"), r.get("dist", 0.0)) for r in results]


def _wikipedia_geosearch(lat: float, lng: float, lang: str, limit: int = 15) -> list[str]:
    data = _get_json(
        f"https://{lang}.wikipedia.org/w/api.php",
        {
            "action": "query",
            "format": "json",
            "list": "geosearch",
            "gscoord": f"{lat}|{lng}",
            "gsradius": WIKIPEDIA_GEO_RADIUS_M,
            "gslimit": limit,
        },
        what=f"Wikipedia ({lang}) geosearch {lat},{lng}",
    )
    return [r["title"] for r in (data or {}).get("query", {}).get("geosearch", [])]


def _wikidata_p18(qid: str) -> str | None:
    data = _get_json(
        "https://www.wikidata.org/w/api.php",
        {
            "action": "wbgetclaims",
            "entity": qid,
            "property": "P18",
            "format": "json",
        },
        what=f"Wikidata P18 {qid}",
    )
    claims = (data or {}).get("claims", {}).get("P18", [])
    if not claims:
        return None
    try:
        # Commons filenames use underscores where Wikidata stores spaces.
        return claims[0]["mainsnak"]["datavalue"]["value"].replace(" ", "_")
    except (KeyError, TypeError):
        return None


def _openverse_search(query: str, limit: int = 8) -> list[dict]:
    data = _get_json(
        "https://api.openverse.org/v1/images/",
        {"q": query, "page_size": limit, "license_type": "all-cc"},
        what=f"Openverse search {query!r}",
    )
    return (data or {}).get("results", []) or []


def _from_openverse(result: dict) -> dict | None:
    """Wikimedia-sourced Openverse hits are routed back through
    `resolve_commons_file` — that yields the 800px thumbnail and the same
    attribution string as every other Commons tier, rather than Openverse's
    link to the multi-megabyte original. Non-Commons sources (Flickr et al.)
    are stored as-is, with Openverse's own license metadata."""
    url = result.get("url") or ""
    if result.get("source") == "wikimedia" and "/commons/" in url:
        filename = _commons_from_url(url)
        if filename:
            resolved = _from_commons_file(filename)
            if resolved:
                return resolved

    license_code = result.get("license")
    creator = result.get("creator")
    if not url or not license_code or not creator:
        # Same rule as commons.py: no attribution, no photo.
        return None

    version = result.get("license_version")
    license_name = f"CC {license_code.upper()}" + (f" {version}" if version else "")
    return {
        "photo_url": url,
        "photo_attribution": f"{creator} (via Openverse)",
        "photo_license": license_name,
        "photo_source_url": result.get("foreign_landing_url") or url,
    }


# How far out to look for a representative photograph when nothing depicting
# the subject itself could be found. Wide enough to reach the nearest
# photographed thing in a town, tight enough that the picture is still of
# somewhere the traveller is standing.
NEARBY_FALLBACK_RADIUS_M = 2000

# Commons holds a great deal that is not a photograph of a place — locator
# maps, coats of arms, flags, plans, scanned documents. They are exactly what
# a proximity-only search surfaces first, and they look broken on a card.
_NON_PHOTO_HINTS = (
    "map", "locator", "carte", "plan", "flag", "drapeau", "coat of arms",
    "blason", "logo", "seal", "diagram", "chart", "schema", "timeline",
    "svg", "icon", "banner", "signature", "document", "scan",
)
_PHOTO_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff")


def _looks_like_a_photograph(filename: str) -> bool:
    lowered = filename.lower()
    if not lowered.endswith(_PHOTO_EXTENSIONS):
        return False
    return not any(hint in lowered for hint in _NON_PHOTO_HINTS)


def resolve_nearby_photo(
    *, lat: float, lng: float, radius_m: int = NEARBY_FALLBACK_RADIUS_M
) -> dict | None:
    """A real, licensed photograph taken *near* this point — not of it.

    This deliberately breaks the rule the rest of this module is built on.
    Every tier above requires a name match precisely because proximity alone
    picks the wrong subject: the module docstring records "Bir Jebah" getting
    a portrait of a person and "Kilometre Zero" getting a map. That reasoning
    still stands, and this function does not overturn it.

    What changed is the alternative. Most POIs match no tier at all and showed
    an empty placeholder, and a photograph of the surrounding place — clearly
    labelled as not being of the subject — is more use to a traveller than
    nothing. The caller **must** surface `photo_is_stock`; an unlabelled
    nearby photo would be exactly the silent false positive the strict tiers
    exist to prevent.

    Obvious non-photographs are filtered out, since a locator map is what a
    proximity search offers first and it reads as a broken image on a card.
    """
    for filename, distance in _commons_geosearch(lat, lng, limit=25, radius_m=radius_m):
        if not _looks_like_a_photograph(filename):
            continue
        resolved = _from_commons_file(filename)
        if resolved:
            return {
                **resolved,
                "photo_is_stock": True,
                "photo_stock_note": "Nearby photo, not of this place",
            }
    return None


def resolve_photo(
    *,
    wikipedia_title: str | None,
    wikidata_image_filename: str | None,
    osm_tags: dict,
    wikidata_qid: str | None = None,
    name: str | None = None,
    lat: float | None = None,
    lng: float | None = None,
    place_context: str | None = None,
) -> dict | None:
    """Returns {"photo_url", "photo_attribution", "photo_license",
    "photo_source_url"} from the first tier that resolves, or None.

    Structured tiers run first and unconditionally: Wikipedia lead image,
    Wikidata P18 (from the tile SPARQL result, then by QID lookup), then an
    explicit `wikimedia_commons=File:*` OSM tag. Every one of them goes
    through `resolve_commons_file` for license/attribution — a URL is never
    stored without knowing what it's licensed under.

    The discovery tiers below them only run when `lat`/`lng` are supplied,
    and only accept a candidate that is both geographically anchored and a
    name match. See the module docstring for why either condition alone was
    measured to be insufficient.
    """
    if wikipedia_title:
        resolved = _from_wikipedia_summary(fetch_summary(wikipedia_title))
        if resolved:
            return resolved

    if wikidata_image_filename:
        resolved = _from_commons_file(wikidata_image_filename)
        if resolved:
            return resolved

    if wikidata_qid:
        filename = _wikidata_p18(wikidata_qid)
        if filename:
            resolved = _from_commons_file(filename)
            if resolved:
                return resolved

    commons_tag = (osm_tags or {}).get("wikimedia_commons", "")
    if isinstance(commons_tag, str) and commons_tag.startswith("File:"):
        resolved = _from_commons_file(commons_tag.removeprefix("File:"))
        if resolved:
            return resolved

    names = _name_variants(name or (osm_tags or {}).get("name"), osm_tags)
    if not names or lat is None or lng is None:
        return None

    place_stop = _place_stopwords(osm_tags, place_context)
    variant_tokens = [t for t in (_tokens(v, place_stop) for v in names) if t]
    if not variant_tokens:
        # Nothing distinctive left to verify against (e.g. a POI named just
        # "Parc", or the node literally named "Ne"). Guessing here is
        # precisely what produces wrong photos.
        return None

    # Tier: geotagged Commons file whose filename names this subject.
    for filename, _distance in _commons_geosearch(lat, lng):
        if _matches_subject(filename, variant_tokens, place_stop):
            resolved = _from_commons_file(filename)
            if resolved:
                return resolved

    # Tier: nearby Wikipedia article whose title names this subject — its
    # lead image is the same well-licensed path as tier 1, just reached
    # without an OSM link.
    for lang in ("en", "fr", "ar"):
        for title in _wikipedia_geosearch(lat, lng, lang):
            if _matches_subject(title, variant_tokens, place_stop):
                resolved = _from_wikipedia_summary(fetch_summary(title, lang=lang))
                if resolved:
                    return resolved

    # Tier: Openverse (CC-licensed image search). Query is qualified with the
    # place so the index has some chance of disambiguating, and the result is
    # still name-verified — unguarded it happily returns Venice for "Palace
    # of the Dey".
    # Without a place to corroborate against there is no way to tell a
    # correct hit from a same-named subject on another continent, so the
    # tier is skipped entirely rather than run unguarded.
    if not place_stop:
        return None

    qualifier = f" {place_context}" if place_context else ""
    for variant in names[:2]:
        for result in _openverse_search(f"{variant}{qualifier}"):
            title = result.get("title") or ""
            if _is_tag_dump(title):
                continue
            if _matches_subject(title, variant_tokens, place_stop) and _mentions_place(title, place_stop):
                resolved = _from_openverse(result)
                if resolved:
                    return resolved

    return None
