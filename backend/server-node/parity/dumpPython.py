"""Emit the *Python* implementation's answers for a shared corpus, as JSON.

Half of the differential parity check between backend/server (Flask) and
backend/server-node (this port). Run from `backend/server`:

    ./venv/Scripts/python.exe ../server-node/parity/dumpPython.py /tmp/py.json

See parity/README.md for the full three-command sequence.

Only pure functions are exercised — no network, no Supabase — because those are
exactly the ones where a Unicode or rounding difference between the two
languages would degrade behaviour silently instead of raising.
"""
import json
import sys
import os

# Import the Flask server's modules, wherever this file is invoked from.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "server"))

from ingestion.overpass import (
    _category_from_tags, _is_real_name, _name_variants, _normalize_name, _is_excluded, _clean,
)
from ingestion.photos import _tokens, _matches_subject, _place_stopwords, _normalize, _is_tag_dump, _name_variants as p_name_variants
from ingestion.scoring import compute_score
from ingestion.describe import collect_facts, compose, _kind, _qualifiers
from routes.itinerary import _prompt_terms, _matches_prompt, _rank
from ingestion.tiling import covering_tiles, tile_id_for, tile_bounds
from data.geo import haversine_km

STRINGS = [
    "ÎLOT 661", "ilot 661", "Sidi M'Cid", "مقام الشهيد", "أحمد", "قلعة", "Café Malakoff",
    "Mémorial du martyr", "Djenane El Mithak (Résidence d'Etat)", "Bab Azzoun", "114pa466551",
    "Ne", "214145", "Route 66", "Place du 1er Novembre", "Martyrs Memorial 2", "Dar Aziza;Palais",
    "Ketchaoua Mosque architecture – Algiers 8.jpg", "Streets in Algiers 2024 06.jpg",
    "Mosquée du Dey (Alger)", "تمثال الامير عبد القادر", "  spaced   out  ", "",
    "Timgad", "Tassili n'Ajjer", "Yemma Gouraya", "Ambassade du Brésil", "ÉCOLE", "ЖУРНАЛ",
    "no 2", "Parc 12", "Parc n 3", "Beb El Bhar", "Bir Jebah", "Kilometre Zero", "９９",
]

TAGSETS = [
    {"historic": "yes", "amenity": "place_of_worship", "religion": "muslim"},
    {"historic": "heritage", "amenity": "place_of_worship", "religion": "muslim", "building": "mosque"},
    {"historic": "castle", "castle_type": "palace"},
    {"historic": "castle", "castle_type": "hill"},
    {"historic": "castle", "castle_type": "stately"},
    {"historic": "yes"},
    {"historic": "building"},
    {"office": "diplomatic", "diplomatic": "embassy", "embassy": "yes", "leisure": "park", "barrier": "wall"},
    {"historic": "fort", "military": "bunker"},
    {"military": "barracks", "tourism": "attraction"},
    {"barrier": "wall", "tourism": "museum", "wikidata": "Q3403985"},
    {"leisure": "park"}, {"leisure": "garden"}, {"leisure": "water_park"}, {"leisure": "stadium"},
    {"natural": "peak"}, {"natural": "cave_entrance"}, {"natural": "arch"}, {"natural": "fjord"},
    {"waterway": "waterfall"}, {"shop": "mall"}, {"amenity": "marketplace"}, {"amenity": "cinema"},
    {"amenity": "place_of_worship"}, {"amenity": "place_of_worship", "building": "cathedral"},
    {"amenity": "place_of_worship", "religion": "zoroastrian"},
    {"tourism": "attraction"}, {"tourism": "hotel"}, {"tourism": "yes"}, {"tourism": "artwork"},
    {"landuse": "industrial"}, {"landuse": "military"}, {"amenity": "parking"},
    {"barrier": "wall", "leisure": "park"},
    {"barrier": "fence", "leisure": "park", "access": "permissive"},
    {"barrier": "wall", "leisure": "park", "wikidata": "Q123"},
    {"man_made": "lighthouse"}, {"building": "yes"}, {"memorial": "statue"},
    {"historic": "memorial", "name": "Martyrs Memorial", "name:fr": "Mémorial", "name:ar": "مقام الشهيد", "wikidata": "Q3056085"},
    {"tourism": "viewpoint", "name": "مقام الشهيد", "name:en": "Martyrs Memorial"},
    {"amenity": "place_of_worship", "religion": "muslim", "denomination": "sunni", "start_date": "1612", "operator": "Ministry"},
    {"office": "diplomatic", "country": "fr"}, {"office": "diplomatic", "country": "zz"},
    {"office": "diplomatic"}, {"access": "private", "leisure": "park"},
    {"website": "x", "opening_hours": "y", "description": "z", "image": "w", "leisure": "park"},
    {"description:en": "A genuinely explicit description of this place, long enough."},
    {"description": "short"},
]

NAMES_FOR_SCORE = [
    "Villa Montfeld", "Hamma Park", "Dar Aziza", "Djenane El Mithak (Résidence d'Etat)",
    "Ambassade du Brésil", "Jardin d'Essai", "Parking Centre", "Public Toilets",
    "Consulate General", "Chancellerie", "Snack Bar", "Ticket Office", "Casbah of Algiers",
    "Résidence d'Etat", "RESIDENCE D ETAT", "gift shop", "Giftshop",
]

PROMPTS = [
    "shopping malls", "I would like to visit some Roman ruins near Algiers",
    "musées et jardins", "شواطئ", "beaches and viewpoints", "history", "", "art",
    "show me nice places", "théâtre", "café", "old town walking tour",
]

CANDIDATES_FOR_PROMPT = [
    {"category": "Shopping mall", "name": "Bab Ezzouar Mall"},
    {"category": "Market", "name": "Souk El Fellah"},
    {"category": "Ruins", "name": "Tipaza"},
    {"category": "Museum", "name": "Musée National"},
    {"category": "Beach", "name": "Chenoua Plage"},
    {"category": "Park", "name": "Jardin d'Essai"},
    {"category": "Theatre", "name": "Théâtre National"},
    {"category": "Mosque", "name": "Ketchaoua"},
]

PHOTO_CASES = [
    ("Ketchaoua Mosque architecture – Algiers 8.jpg", ["Ketchaoua Mosque"], {"addr:city": "Algiers"}, "Algiers"),
    ("Streets in Algiers 2024 06.jpg", ["Museum of Modern Art of Algiers"], {"addr:city": "Algiers"}, "Algiers"),
    ("Mausolée de Sidi Abderrahmane ben Mohamed ben Makhlouf.jpg", ["Sidi Mohamed Sharif Mosque"], {}, "Algiers"),
    ("Publicité pour la marque de soda Crush, rue Bab Azzoun à Alger.jpg", ["Bab Azzoun"], {}, "Alger"),
    ("Rue Bab Azzoun.jpg", ["Rue Bab Azzoun"], {}, "Alger"),
    ("Mosquée du Dey (Alger).jpg", ["Palace of the Dey", "Mosquée du Dey"], {}, "Alger"),
    ("تمثال الامير عبد القادر.jpg", ["تمثال الأمير عبد القادر"], {}, "الجزائر"),
    ("#algiers #alger #algeria #casbah #oldcity #palais #palace #dey", ["Palace of the Dey"], {}, "Algiers"),
    ("Voiture ancienne alger.jpg", ["Beb El Bhar"], {}, "Alger"),
    ("Timgad Trajan Arch.jpg", ["Timgad"], {"addr:city": "Batna"}, "Batna"),
]

out = {}

out["normalize"] = {s: _normalize_name(s) for s in STRINGS}
out["photos_normalize"] = {s: _normalize(s) for s in STRINGS}
out["is_real_name"] = {s: _is_real_name(s) for s in STRINGS}
out["clean"] = {s: _clean(s) for s in ["cave_entrance", "yes", "RUINS", "city_gate", "a", ""] if s}
out["category"] = [_category_from_tags(t) for t in TAGSETS]
out["excluded"] = [_is_excluded(t) for t in TAGSETS]
out["name_variants"] = [sorted(_name_variants(t)) for t in TAGSETS]

out["score"] = []
for name in NAMES_FOR_SCORE:
    for tags in TAGSETS[:20]:
        total, bd = compute_score(category=_category_from_tags(tags) or "Attraction", name=name,
                                  osm_tags=tags, wikidata_match=None, wikipedia_found=False,
                                  pageviews_30d=None, has_photo=False)
        out["score"].append([round(total, 6), {k: round(v, 6) for k, v in bd.items()}])

out["score_pageviews"] = []
for pv in [1, 30, 300, 3000, 30000, 300000, 3000000]:
    total, bd = compute_score(category="Museum", name="X", osm_tags={"historic": "castle"},
                              wikidata_match={"is_unesco": False, "has_heritage": True, "sitelinks": 5},
                              wikipedia_found=True, pageviews_30d=pv, has_photo=True)
    out["score_pageviews"].append([round(total, 6), {k: round(v, 6) for k, v in bd.items()}])

out["compose"] = []
for tags in TAGSETS:
    for hs in [None, "unesco_world_heritage", "heritage_listed"]:
        facts = collect_facts(name="Test Place", category=_category_from_tags(tags) or "Attraction",
                              tags=tags, heritage_status=hs, place="Algiers")
        out["compose"].append([facts["kind"], facts["embassy"], facts["qualifiers"], compose(facts)])

out["prompt_terms"] = {p: sorted(_prompt_terms(p)) for p in PROMPTS}
out["matches_prompt"] = []
for p in PROMPTS:
    terms = _prompt_terms(p)
    out["matches_prompt"].append([_matches_prompt(c, terms) for c in CANDIDATES_FOR_PROMPT])

out["rank"] = [round(_rank({"distance_km": d, "interest_score": s}, r), 9)
               for d in [0, 1, 5, 20, 100, 1000] for s in [0, 25, 60] for r in [1, 15, 50, 500]]

out["photo_tokens"] = []
out["photo_matches"] = []
for candidate, names, tags, place in PHOTO_CASES:
    stop = _place_stopwords(tags, place)
    vt = [t for t in (_tokens(n, stop) for n in names) if t]
    out["photo_tokens"].append([sorted(stop), [sorted(t) for t in vt], sorted(_tokens(candidate, stop))])
    out["photo_matches"].append(_matches_subject(candidate, vt, stop) if vt else None)

out["tag_dump"] = [_is_tag_dump(c) for c, _, _, _ in PHOTO_CASES]
out["photos_name_variants"] = [p_name_variants(n[0], t) for _, n, t, _ in PHOTO_CASES]

out["tiles"] = []
for lat, lng, r in [(36.75, 3.06, 5), (36.75, 3.06, 20), (24.55, 9.48, 1), (-33.9, 151.2, 50), (0, 0, 3)]:
    out["tiles"].append([tile_id_for(lat, lng), covering_tiles(lat, lng, r),
                         [round(v, 9) for v in tile_bounds(tile_id_for(lat, lng))]])

out["haversine"] = [round(haversine_km(a, b, c, d), 9) for a, b, c, d in
                    [(36.75, 3.06, 36.76, 3.07), (0, 0, 0, 1), (36.7457, 3.06973, 36.7462, 3.0694),
                     (-33.9, 151.2, 51.5, -0.12), (24.55, 9.48, 35.48, 6.46)]]

with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(out, ensure_ascii=False, sort_keys=True))
