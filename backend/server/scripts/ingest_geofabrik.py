"""Offline ingestion of OSM PBF files from Geofabrik.

This bypasses Overpass and fetches a regional extract, parses it, extracts POIs,
computes semantic descriptions, and loads them into Supabase.
"""
import os
import sys

# Ensure backend/server is in PYTHONPATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
import osmium
from ingestion.scoring import compute_score
from llm import embed
from ingestion.supabase_admin import get_admin_client

GEOFABRIK_URL = "https://download.geofabrik.de/africa/algeria-latest.osm.pbf"
PBF_PATH = "algeria-latest.osm.pbf"

class POIHandler(osmium.SimpleHandler):
    def __init__(self):
        super(POIHandler, self).__init__()
        self.pois = []
        
    def _process_tags(self, tags, location, osm_id, osm_type):
        tags_dict = {t.k: t.v for t in tags}
        if "name" not in tags_dict:
            return
            
        category = None
        if "historic" in tags_dict:
            category = tags_dict["historic"].replace("_", " ").capitalize()
        elif "tourism" in tags_dict and tags_dict["tourism"] not in {"hotel", "information", "guest_house"}:
            category = tags_dict["tourism"].replace("_", " ").capitalize()
        elif "natural" in tags_dict:
            category = tags_dict["natural"].replace("_", " ").capitalize()
        elif tags_dict.get("leisure") == "park":
            category = "Park"
            
        if not category:
            return
            
        self.pois.append({
            "osm_id": osm_id,
            "osm_type": osm_type,
            "name": tags_dict["name"],
            "category": category,
            "lat": location.lat,
            "lng": location.lon,
            "tags": tags_dict
        })

    def node(self, n):
        self._process_tags(n.tags, n.location, n.id, "node")

def run():
    print(f"Downloading {GEOFABRIK_URL}...")
    if not os.path.exists(PBF_PATH):
        r = requests.get(GEOFABRIK_URL, stream=True)
        r.raise_for_status()
        with open(PBF_PATH, 'wb') as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
    print("Download complete. Parsing PBF...")
    
    handler = POIHandler()
    handler.apply_file(PBF_PATH)
    
    print(f"Found {len(handler.pois)} POIs. Upserting to Supabase...")
    admin = get_admin_client()
    
    for i, poi in enumerate(handler.pois):
        if i % 100 == 0:
            print(f"Processed {i}/{len(handler.pois)} POIs...")
            
        # 1. Semantic fallback description
        t = poi["tags"]
        desc_parts = []
        if t.get("natural"):
            desc_parts.append(f"A natural {t['natural']}")
        elif t.get("historic"):
            desc_parts.append(f"A historic {t['historic']}")
        elif t.get("tourism"):
            desc_parts.append(f"A {t['tourism']} attraction")
        else:
            desc_parts.append(f"A {poi['category'].lower()}")
            
        extras = []
        if t.get("surface"):
            extras.append(f"with a {t['surface']} surface")
            
        raw_blurb = " ".join(desc_parts + extras).strip() + "."
        raw_blurb = raw_blurb[0].upper() + raw_blurb[1:] if raw_blurb else "A point of interest."
        
        # 2. Score
        score, breakdown = compute_score(
            category=poi["category"],
            name=poi["name"],
            osm_tags=poi["tags"],
            wikidata_match=None,
            wikipedia_found=False,
            pageviews_30d=None,
            has_photo=False,
        )
        
        if score < 15:
            continue
            
        # 3. Embedding
        try:
            emb = embed(raw_blurb)
        except Exception:
            continue
            
        # 4. Upsert
        loc_id = f"osm_{poi['osm_type']}_{poi['osm_id']}"
        try:
            admin.rpc(
                "upsert_ingested_location",
                {
                    "p_id": loc_id,
                    "p_lat": poi["lat"],
                    "p_lng": poi["lng"],
                    "p_category": poi["category"],
                    "p_name": poi["name"],
                    "p_blurb": raw_blurb,
                    "p_interest_score": score,
                    "p_score_breakdown": breakdown,
                    "p_is_active": score >= 25,
                    "p_embedding": emb,
                    "p_osm_tags": poi["tags"],
                },
            ).execute()
        except Exception as e:
            print(f"Error upserting {loc_id}: {e}")

if __name__ == "__main__":
    run()
