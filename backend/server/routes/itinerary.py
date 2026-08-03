"""Stage 3 of the route-generation funnel (docs/backend/08, docs/backend/12):

    1. Fetch    maps API -> raw POIs                    (ingestion/overpass.py + wikidata.py)
    2. Score    deterministic interest ranking           (ingestion/scoring.py)
    3. Select   LLM picks + orders from vetted candidates (this file)

Stage 1+2 run via `POST /api/poi/ingest` (routes/poi.py), which populates
Supabase's `locations` table — this file and `locations_repo.py` never call
the ingestion pipeline directly, they just query whatever's already there
via the `nearby_locations` RPC. Ingestion is a deliberately separate,
explicitly-triggered step rather than an automatic part of every itinerary
request: a cold tile can take tens of seconds to ingest (several external
API calls per POI, with rate-limit-driven delays between them), which is a
bad trade to pay inline on a user's request. See routes/poi.py's docstring.
An area that's never been ingested still works here — it just only offers
the 8 `is_curated` seed locations until someone calls `/api/poi/ingest` for
it. If Supabase is unreachable entirely, `locations_repo` degrades further,
to the same 8 locations from a hardcoded fallback — this endpoint never
returns an empty candidate set either way.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from data.geo import haversine_km, get_travel_time_matrix
from data.locations_repo import locations_within_radius
from json_utils import extract_json
from llm import chat, embed, extract_intent, LLMError
from rate_limit import authenticate_and_rate_limit
from ingestion.supabase_admin import get_admin_client
from ingestion.overpass import fetch_pois
from ingestion.scoring import compute_score
from ingestion.photos import resolve_photo
import threading
import math

itinerary_bp = Blueprint("itinerary", __name__)

MAX_RADIUS_KM = 500
MAX_WANTED_VISITS = 20


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
        remaining.remove(nxt)
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
        
    # Greedy nearest-neighbor using travel time instead of straight line
    remaining = list(stops)
    ordered = []
    cur_idx = 0  # 0 is the start point
    
    while remaining:
        best_time = float("inf")
        best_stop = None
        best_stop_idx = -1
        
        for stop in remaining:
            stop_idx = stops.index(stop) + 1
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
        remaining.remove(best_stop)
        cur_idx = best_stop_idx
        
    return ordered


def _select_with_llm(candidates: list[dict], prompt: str, wanted_visits: int | None, existing_stops: list[dict] = None) -> list[dict]:
    """Returns a list of {location_id, reason, suggested_order} dicts, already
    validated against `candidates`. Never returns an id the model invented."""
    candidate_lines = "\n".join(
        f"- id={c['id']} | {c['name']} | {c['category']} | {c.get('region', 'Algeria')} | "
        f"{c.get('distance_km', 0):.1f} km away | {c.get('blurb', '')}"
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

    raw = chat(messages, json_mode=True, max_tokens=900, temperature=0.6)
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

def _expand_categories(intent: dict) -> list[str]:
    """Map extracted themes to OSM categories."""
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
        try:
            radius_km = min(float(body.get("radius_km", 20)), MAX_RADIUS_KM)
            admin.table("route_jobs").update({"status": "processing"}).eq("id", job_id).execute()
            
            import concurrent.futures
            
            # Step 2: Route Generation
            prompt = str(body.get("prompt") or "").strip()[:500]
            wanted_visits = body.get("wanted_visits")
            if wanted_visits is not None:
                try:
                    wanted_visits = min(int(wanted_visits), MAX_WANTED_VISITS)
                except (TypeError, ValueError):
                    wanted_visits = None
            
            prompt_embedding = None
            extracted_intent = {}
            target_categories = []
            
            # Calculate simple bounding box from radius
            lat_delta = radius_km / 111.0
            lng_delta = radius_km / (111.0 * math.cos(math.radians(lat)))
            lat_min, lat_max = lat - lat_delta, lat + lat_delta
            lng_min, lng_max = lng - lng_delta, lng + lng_delta
            
            # Direct fast overpass search
            try:
                raw_pois = fetch_pois(lat_min, lng_min, lat_max, lng_max)
            except Exception as e:
                admin.table("route_jobs").update({"status": "failed", "error_message": f"Overpass error: {str(e)}"}).eq("id", job_id).execute()
                return

            candidates = []
            for poi in raw_pois:
                score, _ = compute_score(
                    category=poi["category"], name=poi["name"], osm_tags=poi["tags"],
                    wikidata_match=None, wikipedia_found=False, pageviews_30d=None, has_photo=False
                )
                if score >= 0:  # keep all matched overpass results
                    candidates.append({
                        "id": f"osm-{poi['osm_type']}-{poi['osm_id']}",
                        "name": poi["name"],
                        "category": poi["category"],
                        "lat": poi["lat"],
                        "lng": poi["lng"],
                        "tags": poi["tags"],
                        "interest_score": score,
                        "wikipedia": poi.get("wikipedia"),
                        "wikidata_qid": poi.get("wikidata_qid"),
                        "distance_km": haversine_km(lat, lng, poi["lat"], poi["lng"]),
                        "blurb": poi.get("tags", {}).get("description", f"A {poi['category'].lower()} point of interest.")
                    })
            
            # Basic distance sorting + hybrid score
            candidates.sort(key=lambda x: (x.get("interest_score", 0) - (x.get("distance_km", 0) * 2)), reverse=True)
            candidates = candidates[:50]
            
            rejected_ids = body.get("rejected_ids")
            if not isinstance(rejected_ids, list):
                rejected_ids = []
            accepted_ids = body.get("accepted_ids")
            if not isinstance(accepted_ids, list):
                accepted_ids = []
                
            skip_ids = set(rejected_ids) | set(accepted_ids)
            if skip_ids:
                candidates = [c for c in candidates if c["id"] not in skip_ids]

            existing_stops = body.get("existing_stops")
            if existing_stops and not isinstance(existing_stops, list):
                existing_stops = []
                
            if not prompt and not existing_stops:
                selected = candidates[:min(8, len(candidates))]
                stops_out = [
                    {**c, "reason": "One of the closer highlights to your starting point."}
                    for c in _order_travel_time(lat, lng, selected)
                ]
            else:
                try:
                    picked = _select_with_llm(candidates, prompt, wanted_visits, existing_stops)
                    if not picked:
                        stops_out = []
                    else:
                        by_id = {c["id"]: c for c in candidates}
                        hydrated = [
                            {**by_id[s["location_id"]], "reason": s.get("reason", "")}
                            for s in picked
                            if s["location_id"] in by_id
                        ]
                        # Rapidly fetch photos for the final selection only
                        import concurrent.futures
                        def _fetch_photo(s):
                            try:
                                photo = resolve_photo(
                                    wikipedia_title=s.get("wikipedia"),
                                    wikidata_image_filename=None,
                                    osm_tags=s.get("tags", {})
                                )
                                if photo:
                                    s.update(photo)
                            except Exception:
                                pass
                        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
                            executor.map(_fetch_photo, hydrated)
                            
                        stops_out = _order_travel_time(lat, lng, hydrated)
                except Exception as e:
                    import logging
                    logging.exception(f"LLM generation failed: {e}")
                    raise Exception(f"llm_error: {e}")

            if not stops_out and candidates:
                stops_out = []
                
            admin.table("route_jobs").update({
                "status": "succeeded",
                "result_data": {"stops": stops_out}
            }).eq("id", job_id).execute()

        except Exception as e:
            admin.table("route_jobs").update({
                "status": "failed",
                "error_message": str(e)
            }).eq("id", job_id).execute()

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
    nearby_locations candidate set the original itinerary was built from — the LLM
    cannot promote a location it invented or that scores below the floor.

    Body:
      lat, lng          (float, required) — user's original departure point
      radius_km         (float, optional, default 20) — search radius
      existing_stops    (list[{id, name, ...}], required) — the current route
      change_request    (str, required) — e.g. "add something with Roman ruins"
    """
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

    # Embed the change request for semantic candidate ranking (optional, degrade gracefully)
    prompt_embedding = None
    try:
        prompt_embedding = embed(change_request)
    except Exception:
        pass

    candidates = locations_within_radius(lat, lng, radius_km, prompt_embedding=prompt_embedding, limit=30)

    # Build a modify-specific prompt that names existing stops explicitly
    existing_names = [s.get("name", "Unknown") for s in existing_stops]
    candidate_lines = "\n".join(
        f"- id={c['id']} | {c['name']} | {c['category']} | {c.get('region', 'Algeria')} | "
        f"{c.get('distance_km', 0):.1f} km away | {c.get('blurb', '')}"
        for c in candidates
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
        raw = chat(messages, json_mode=True, max_tokens=900, temperature=0.6)
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

    # Enforce: only ids from the verified candidate set survive
    candidate_ids = {c["id"] for c in candidates}
    valid_picks = [
        s for s in stops
        if isinstance(s, dict) and s.get("location_id") in candidate_ids
    ]

    if not valid_picks:
        return jsonify({"error": "no_matches", "message": "No candidates matched that change request"}), 200

    by_id = {c["id"]: c for c in candidates}
    hydrated = [
        {**by_id[s["location_id"]], "reason": s.get("reason", "")}
        for s in valid_picks
        if s["location_id"] in by_id
    ]
    ordered = _order_travel_time(lat, lng, hydrated)

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
