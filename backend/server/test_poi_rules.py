"""Regression checks for POI categorization, exclusion, scoring and dedupe.

    python test_poi_rules.py

No network and no pytest (the project has neither a backend suite nor that
dependency) — every case below is a real tag set taken from live Overpass
output for Algiers, kept as a fixture so the rules that produced today's
candidate list can't silently regress.

Each case names the failure it exists to prevent.
"""
from __future__ import annotations

import sys

from ingestion.overpass import (
    DUPLICATE_RADIUS_M,
    _category_from_tags,
    _deduplicate,
    _distance_m,
    _is_real_name,
    _name_variants,
)
from ingestion.scoring import compute_score

failures: list[str] = []


def check(label: str, got, expected):
    if got != expected:
        failures.append(f"{label}\n      expected {expected!r}\n      got      {got!r}")


def poi(osm_id, name, tags, lat, lng, osm_type="way"):
    return {
        "osm_type": osm_type, "osm_id": osm_id, "name": name, "category": _category_from_tags(tags) or "Attraction",
        "lat": lat, "lng": lng, "tags": tags,
        "wikidata_qid": tags.get("wikidata"), "wikipedia": tags.get("wikipedia"),
    }


# --- categorization --------------------------------------------------------
# `historic=yes` shipped two Algiers mosques to the app labelled "Yes".
check(
    "historic=yes place_of_worship -> Mosque, never 'Yes'",
    _category_from_tags({"historic": "yes", "amenity": "place_of_worship", "religion": "muslim"}),
    "Mosque",
)
check(
    "historic=heritage on a mosque prefers the mosque",
    _category_from_tags({"historic": "heritage", "amenity": "place_of_worship",
                         "religion": "muslim", "building": "mosque"}),
    "Mosque",
)
check(
    "a specific historic value still wins",
    _category_from_tags({"historic": "castle", "castle_type": "palace"}),
    "Castle",
)
check(
    "historic=yes with nothing else is not a category called 'Yes'",
    _category_from_tags({"historic": "yes"}),
    "Historic site",
)

# --- exclusions ------------------------------------------------------------
# Embassies are tagged leisure=park and took four of the top ten candidates.
check(
    "embassy compound is not a park",
    _category_from_tags({"office": "diplomatic", "diplomatic": "embassy",
                         "embassy": "yes", "leisure": "park", "barrier": "wall"}),
    None,
)
check(
    "a historic fort on military land is still visitable",
    _category_from_tags({"historic": "fort", "military": "bunker"}),
    "Fort",
)
check(
    "an active military site with no heritage value is not",
    _category_from_tags({"military": "barracks", "tourism": "attraction"}),
    None,
)
check(
    "Serkadji Prison (barrier=wall) is a museum, not a compound",
    _category_from_tags({"barrier": "wall", "tourism": "museum", "wikidata": "Q3403985"}),
    "Museum",
)

# --- names -----------------------------------------------------------------
# Heritage-register ids get tagged as names: 214145, 937605, 116pa466551.
check("register id is not a name", _is_real_name("214145"), False)
check("mostly-digit id is not a name", _is_real_name("116pa466551"), False)
check("two-letter name is not a name", _is_real_name("Ne"), False)
check("a real name with a number survives", _is_real_name("ilot 661"), True)
check("an Arabic name survives", _is_real_name("مقام الشهيد"), True)

# --- scoring ---------------------------------------------------------------
def score(name, tags):
    return compute_score(category=_category_from_tags(tags) or "Attraction", name=name,
                         osm_tags=tags, wikidata_match=None, wikipedia_found=False,
                         pageviews_30d=None, has_photo=False)[0]

walled = {"barrier": "wall", "leisure": "park"}
check("walled private grounds are penalized below a real park",
      score("Villa Montfeld", walled) < score("Hamma Park", {"leisure": "park", "access": "yes"}), True)
check("...but survive as a candidate rather than being deleted",
      score("Dar Aziza", walled) >= 0, True)
check("a state residence is rejected outright",
      score("Djenane El Mithak (Résidence d'Etat)", {"leisure": "park"}) < 0, True)
check("an embassy named but untagged is rejected too",
      score("Ambassade du Brésil", {"leisure": "park"}) < 0, True)
check("a walled park with a wikidata link is not penalized",
      score("Jardin d'Essai", {**walled, "wikidata": "Q123"}) > 0, True)

# --- deduplication ---------------------------------------------------------
# The reported bug: one monument, three cards, in French/English/Arabic.
martyrs = [
    poi(370342095, "Martyrs Memorial",
        {"historic": "memorial", "name": "Martyrs Memorial", "name:fr": "Mémorial du martyr",
         "name:ar": "مقام الشهيد", "wikidata": "Q3056085"}, 36.74570, 3.06973),
    poi(2700208215, "Martyrs Memorial",
        {"tourism": "viewpoint", "name": "مقام الشهيد", "name:en": "Martyrs Memorial"},
        36.74620, 3.06940, osm_type="node"),
    poi(7023985185, "MaQam echahid",
        {"historic": "monument", "name": "MaQam echahid", "name:ar": "مقام الشهيد"},
        36.74571, 3.06974, osm_type="node"),
    poi(2545150691, "Martyrs Memorial 2",
        {"tourism": "viewpoint", "name": "Martyrs Memorial 2"}, 36.74646, 3.06926, osm_type="node"),
]
deduped = _deduplicate(list(martyrs))
check("one monument in three languages collapses to one card", len(deduped), 1)
check("the survivor is the wikidata-linked record", deduped[0]["osm_id"], 370342095)
check("the survivor inherits the duplicates' name variants",
      "martyrs memorial 2" in _name_variants(deduped[0]["tags"]), True)

# Same subject, same id, but genuinely two places 1.8 km apart.
ben_aknoun = [
    poi(248872093, "Ben Aknoun Amusement Park",
        {"tourism": "theme_park", "name": "Ben Aknoun Amusement Park", "wikidata": "Q2896344"},
        36.76300, 3.02100),
    poi(248872080, "Ben Aknoun Zoo",
        {"tourism": "zoo", "name": "Ben Aknoun Zoo", "wikidata": "Q2896344"},
        36.77900, 3.02900),
]
check("a shared wikidata id across 1.8 km does NOT merge", len(_deduplicate(list(ben_aknoun))), 2)

# Same name, different cities — must stay separate.
squares = [
    poi(31242440, "Place des Martyrs", {"leisure": "park", "name": "Place des Martyrs"}, 36.66782, 3.09464),
    poi(475312883, "Place des Martyrs", {"leisure": "park", "name": "Place des Martyrs"}, 36.60500, 3.08849),
]
check("same name 7 km apart does NOT merge", len(_deduplicate(list(squares))), 2)

# Accents and case: "ilot 661" vs "ÎLOT 661", 7 m apart.
ilot = [
    poi(6127222785, "ilot 661", {"tourism": "artwork", "name": "ilot 661"}, 36.7700, 3.0600, "node"),
    poi(6062724102, "ÎLOT 661", {"tourism": "artwork", "name": "ÎLOT 661"}, 36.77005, 3.06005, "node"),
]
check("accent/case variants of one name merge", len(_deduplicate(list(ilot))), 1)

# A café next to a mosque is not the mosque.
neighbours = [
    poi(1, "Ketchaoua Mosque", {"historic": "heritage", "amenity": "place_of_worship",
                                "religion": "muslim", "name": "Ketchaoua Mosque"}, 36.7839, 3.0606),
    poi(2, "Café Malakoff", {"tourism": "attraction", "name": "Café Malakoff"}, 36.78392, 3.06062),
]
check("adjacent but differently-named places do NOT merge", len(_deduplicate(list(neighbours))), 2)

# --- enclosure (route diversity) -------------------------------------------
# Reported as duplicates: the Tipaza park plus two of its own ruins.
from routes.itinerary import _drop_enclosed, _encloses  # noqa: E402

TIPAZA_SITE_BOUNDS = {"minlat": 36.5905, "minlon": 2.4380, "maxlat": 36.5990, "maxlon": 2.4490}


def stop(sid, name, lat, lng, bounds=None):
    return {"id": sid, "name": name, "lat": lat, "lng": lng, "bounds": bounds,
            "category": "Ruins", "tags": {}, "interest_score": 25, "distance_km": 2.0}


site = stop("site", "Roman Ruins of Tipaza", 36.59463, 2.44224, TIPAZA_SITE_BOUNDS)
theatre = stop("theatre", "Roman Theatre", 36.59265, 2.44165)
amphi = stop("amphi", "Amphithéâtre Romain", 36.59315, 2.44542)
beach = stop("beach", "Chenoua Plage", 36.5750, 2.4000)

check("the park encloses its own theatre", _encloses(site, theatre), True)
check("a stop never encloses itself", _encloses(site, site), False)
check("a node (no bounds) encloses nothing", _encloses(theatre, amphi), False)
check("a beach outside the park is not enclosed", _encloses(site, beach), False)

thinned = _drop_enclosed([site, theatre, amphi, beach], [site, theatre, amphi, beach], wanted=4)
check("three cards for one park collapse to the park",
      sorted(s["id"] for s in thinned), ["beach", "site"])

# The Casbah's landmarks are peers, not sub-features: nothing selected
# encloses anything else, so an all-node selection must survive intact.
casbah = [stop(f"m{i}", f"Mosque {i}", 36.7839 + i * 0.001, 3.0606) for i in range(4)]
check("peer landmarks are never thinned", len(_drop_enclosed(casbah, casbah, wanted=8)), 4)

check("distance helper agrees with the dedupe radius",
      round(_distance_m({"lat": 36.74570, "lng": 3.06973}, {"lat": 36.74620, "lng": 3.06940})) < DUPLICATE_RADIUS_M,
      True)


if failures:
    print(f"FAILED ({len(failures)}):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("all POI rule checks passed")
