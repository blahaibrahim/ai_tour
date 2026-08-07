"""Human-readable descriptions for POIs that Wikipedia has never heard of.

## Why this exists

The blurb pipeline had exactly one good path — rewrite a Wikipedia extract —
and a throwaway `else` branch for everything else. Since only ~10 of 203
catalogue rows carry a `wikipedia_title`, that `else` branch produced almost
every blurb in the app, and it produced them by pasting raw OSM tag values
into a format string. The live catalogue is the evidence:

    "A attraction attraction."   x28     (tourism=attraction)
    "A park."                    x31     (nothing but the category)
    "A historic yes."            x3      (historic=yes, a tag meaning
                                          "this is historic", not a noun)
    "A artwork in the area."     x4      (no article agreement)

So: 190 of 203 blurbs were some flavour of broken. This module replaces that
branch with something that reads like English, and — when an LLM is reachable
— hands the same structured facts to it for a sentence with some life in it.

## Rules

Nothing here invents facts. Every clause traces to a tag that is actually
set, which is what keeps the deterministic path safe to ship unattended and
gives the LLM path a factual frame it is told not to depart from.
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

# OSM uses "yes" to mean "this key applies" — it is a flag, not a noun, and
# pasting it into prose is where "A historic yes." came from.
_NON_NOUNS = {"yes", "y", "true", "1", ""}

_VOWELS = "aeiou"

# Tag values whose OSM spelling is not what a person would call the thing.
_PRETTY = {
    "place_of_worship": "place of worship",
    "attraction": "visitor attraction",
    "artwork": "public artwork",
    "viewpoint": "viewpoint",
    "theme_park": "theme park",
    "nature_reserve": "nature reserve",
    "city_gate": "city gate",
    # historic=heritage marks a protected site; on its own "heritage" is not a
    # noun for a thing, which is where "A heritage in Algiers." came from.
    "heritage": "heritage site",
    "archaeological_site": "archaeological site",
    "water_tap": "public fountain",
    "powder_magazine": "powder magazine",
    "battlefield": "battlefield",
    "wood": "woodland",
    "water": "body of water",
    "bay": "bay",
    "ruins": "ruins",
    "manor": "manor house",
    "memorial": "memorial",
    "monument": "monument",
    "castle": "castle",
    "museum": "museum",
    "zoo": "zoo",
    "beach": "beach",
    "park": "park",
    "garden": "garden",
    "tomb": "tomb",
    "bridge": "bridge",
    "church": "church",
    "mosque": "mosque",
    "hotel": "hotel",
}

# ISO 3166-1 alpha-2 for the embassies that actually appear in this catalogue;
# anything else falls back to the raw code rather than guessing.
_COUNTRIES = {
    "FR": "France", "NL": "the Netherlands", "BR": "Brazil", "ES": "Spain",
    "IT": "Italy", "DE": "Germany", "GB": "the United Kingdom",
    "US": "the United States", "RU": "Russia", "CN": "China", "TR": "Türkiye",
    "PT": "Portugal", "BE": "Belgium", "TN": "Tunisia", "MA": "Morocco",
    "EG": "Egypt", "SA": "Saudi Arabia", "QA": "Qatar", "AE": "the UAE",
}


def _is_noun(value: object) -> bool:
    return isinstance(value, str) and value.strip().lower() not in _NON_NOUNS


def _pretty(value: str) -> str:
    key = value.strip().lower()
    return _PRETTY.get(key, key.replace("_", " ").strip())


def _sentence_case(text: str) -> str:
    """Upper-cases the first character only, leaving proper nouns intact."""
    return text[:1].upper() + text[1:] if text else text


def _article(phrase: str) -> str:
    """"a" / "an" by sound of the first letter. Cheap, but it is the whole
    reason the old output read as "A artwork" / "A attraction"."""
    return "an" if phrase[:1].lower() in _VOWELS else "a"


def _kind(category: str | None, tags: dict) -> str | None:
    """The noun this place *is*, chosen from the most specific tag that
    carries one. Order matters: `historic=castle` says more than
    `building=yes`, and the bare category is the last resort."""
    tags = tags or {}

    if _is_noun(tags.get("historic")):
        kind = _pretty(tags["historic"])
        castle_type = tags.get("castle_type")
        if kind == "castle" and _is_noun(castle_type):
            sub = _pretty(castle_type)
            # castle_type=palace/fortress/citadel name the building outright —
            # "a palace castle" is not a thing. Others qualify it ("a hill
            # castle"), so those keep the head noun.
            if sub in ("palace", "fortress", "citadel", "manor house", "stately"):
                return "palace" if sub == "stately" else sub
            return f"{sub} castle"
        return kind

    if _is_noun(tags.get("memorial")):
        return _pretty(tags["memorial"])

    for key in ("leisure", "natural", "tourism", "man_made", "amenity", "shop"):
        if _is_noun(tags.get(key)):
            return _pretty(tags[key])

    if _is_noun(tags.get("building")):
        return _pretty(tags["building"])

    if category and _is_noun(category):
        return _pretty(category)
    return None


def _qualifiers(tags: dict, heritage_status: str | None) -> list[str]:
    """Short factual clauses, each traceable to a set tag."""
    tags = tags or {}
    out: list[str] = []

    if heritage_status == "unesco_world_heritage":
        out.append("part of a UNESCO World Heritage site")
    elif heritage_status == "heritage_listed":
        out.append("heritage-listed")

    religion = tags.get("religion")
    denomination = tags.get("denomination")
    if _is_noun(religion) and tags.get("amenity") == "place_of_worship":
        label = _pretty(denomination) if _is_noun(denomination) else _pretty(religion)
        # Denominations are proper nouns — "sunni" reads as a typo.
        out.append(label.title())

    if _is_noun(tags.get("start_date")):
        out.append(f"dating from {tags['start_date']}")

    operator = tags.get("operator")
    if _is_noun(operator) and len(str(operator)) < 40:
        out.append(f"run by {operator}")

    access = tags.get("access")
    if isinstance(access, str) and access.lower() in ("private", "no"):
        out.append("not open to the public")

    return out


def _embassy_phrase(tags: dict) -> str | None:
    """Embassies are a big slice of this catalogue and read terribly through
    the generic path ("A park." — they are tagged as their grounds)."""
    tags = tags or {}
    if tags.get("office") != "diplomatic" and not _is_noun(tags.get("embassy")):
        return None
    code = tags.get("country")
    if isinstance(code, str) and code.strip():
        raw = code.strip()
        country = _COUNTRIES.get(raw.upper()) or raw.title()
        return f"the diplomatic mission of {country}"
    return "a diplomatic mission"


def collect_facts(
    *,
    name: str,
    category: str | None,
    tags: dict,
    heritage_status: str | None = None,
    place: str | None = None,
) -> dict:
    """The structured frame both description paths work from."""
    tags = tags or {}
    return {
        "name": name,
        "kind": _kind(category, tags),
        "embassy": _embassy_phrase(tags),
        "qualifiers": _qualifiers(tags, heritage_status),
        "place": place or tags.get("addr:city") or None,
        "street": tags.get("addr:street"),
        # An explicit description tag beats anything either path can compose.
        "description": tags.get("description:en") or tags.get("description"),
        "website": tags.get("website"),
    }


def compose(facts: dict) -> str:
    """Deterministic description. Always returns a readable sentence.

    This is the floor, not the ceiling — it runs when no LLM is reachable,
    and as the fallback when the LLM declines or misbehaves.
    """
    explicit = facts.get("description")
    if isinstance(explicit, str) and len(explicit.strip()) >= 20:
        text = explicit.strip()
        return text if text.endswith((".", "!", "?")) else text + "."

    place = facts.get("place")
    in_place = f" in {place}" if place else ""

    if facts.get("embassy"):
        # Not str.capitalize(): it lowercases everything after the first
        # character, which turned "…mission of France" into "…of france".
        return _sentence_case(f"{facts['embassy']}{in_place}") + "."

    kind = facts.get("kind")
    qualifiers = list(facts.get("qualifiers") or [])

    if not kind:
        # Nothing factual to say beyond where it is. Better an honest, plain
        # line than a confidently wrong one.
        return f"A point of interest{in_place}." if place else "A point of interest."

    # Fold a leading adjectival qualifier into the noun phrase so it reads as
    # "A heritage-listed mosque" rather than "A mosque, heritage-listed".
    lead = ""
    for candidate in list(qualifiers):
        if candidate in ("heritage-listed",) or " " not in candidate:
            lead = candidate + " "
            qualifiers.remove(candidate)
            break

    phrase = f"{lead}{kind}"
    sentence = f"{_article(phrase).capitalize()} {phrase}{in_place}"

    if qualifiers:
        sentence += ", " + ", ".join(qualifiers[:2])
    return sentence + "."


def is_worth_writing(facts: dict) -> bool:
    """Whether there is enough substance for a written sentence to beat the
    deterministic one.

    Measured, not assumed: asked to describe a POI whose only facts are
    "type: park, city: Algiers", the model returns "Explore this park located
    in Algiers." — strictly worse than "A park in Algiers.", because it pads
    the same information with filler. Told not to invent (as it must be), it
    has nothing else to work with. So the call is only made when the facts
    can actually carry a sentence.
    """
    if facts.get("description"):
        return True
    if facts.get("embassy"):
        return False  # the deterministic phrasing is already exact
    qualifiers = facts.get("qualifiers") or []
    if len(qualifiers) >= 2:
        return True
    return bool(facts.get("kind")) and len(qualifiers) >= 1


def describe(facts: dict, *, use_llm: bool = True) -> str:
    """LLM-written description when the facts justify it, deterministic
    otherwise.

    The LLM is given only the collected facts and told not to add any, which
    is what keeps this from inventing history for a POI whose entire record is
    three OSM tags. Any failure — unreachable, empty, wrong length, or an
    answer that smells like a refusal — falls back to `compose`.
    """
    baseline = compose(facts)
    if not use_llm or not is_worth_writing(facts):
        return baseline

    try:
        from ingestion.rewrite import describe_from_facts
        written = describe_from_facts(facts)
    except Exception as e:  # import or call failure — never fatal
        logger.warning("LLM description failed for %r: %s", facts.get("name"), e)
        return baseline

    return written or baseline
