# Backend Handoff

The backend services for AI Tour have been successfully implemented following the design documents. This file serves as a summary of the completed work, current state, and remaining gaps for the next developer.

## Completed Work

### 1. 3D Model Generation Pipeline (Docs 06, 07)
- Rewrote the `hunyuan2.1` Modal backend to use `modal.enter` for async GPU inference, improving generation throughput by keeping the model weights in VRAM across requests.
- Created the `/api/models/generate` Flask endpoint which implements:
  - **Auth validation:** Verifies Supabase JWTs natively.
  - **Rate Limiting:** Enforces rate limits using the Supabase `check_rate_limit` RPC.
  - **Quotas:** Deducts from the user's `model_credits` balance via `consume_model_credit` RPC.
  - **Caching:** Automatically skips generation and re-uses outputs if the input `image_sha256` matches a prior succeeded job.
  - **Security:** Securely proxies the generation request to Modal, hiding all secrets from the client.
  - **Storage:** The Modal worker directly streams output `.glb` meshes to the Supabase Storage `models` bucket securely using the Service Role Key.

### 2. LLM Failover & Itinerary Routes (Doc 08)
- Updated `backend/server/llm.py` to use `google-genai` (Gemini Flash) as the primary generation model.
- Kept `groq` as an automated failback if Gemini fails.
- Modified `/api/itinerary` to accept an `existing_stops` parameter, allowing the LLM to context-aware rewrite itineraries in "modify mode" rather than just replacing them entirely.

### 3. POI Ingestion (Doc 12)
- Added rate-limiting to the POI ingestion endpoint (`/api/poi/ingest`) via Supabase RPCs.
- Ensured external API calls to Overpass have proper `User-Agent` (`OVERPASS_CONTACT`) headers set.

### 4. Semantic Search (Doc 08)
- Created the migration `20260801120004_semantic_search.sql` which enables `pgvector`.
- Updated the `locations` schema to include an `embedding vector(384)` column.
- Updated the `nearby_locations` RPC to automatically order POIs by cosine similarity (ascending) if an embedding prompt is provided.
- Updated `ingest.py` to generate semantic embeddings for new POIs using Gemini `text-embedding-004`.
- Updated `/api/itinerary` to calculate vector embeddings for user prompts, allowing highly contextualized POI selection.

## Remaining Gaps

1. **Flutter App Integration:** The Flutter UI (`lib/`) needs to be wired to the new backend endpoints.
2. **Content Safety:** Implementation of NSFW filtering and face detection as outlined in layer 4 of Doc 07.
3. **Database Schema:** Full test coverage for RLS policies, trips, artifacts, and swipe decisions schema.
4. **Route Generation Overhaul:** The itinerary generation architecture is being overhauled to use offline geographic data, semantic POI cards, LLM intent extraction, and OSRM routing. See [13-route-generation-architecture.md](docs/backend/13-route-generation-architecture.md) for the new pipeline.

## Run Instructions

To run the backend:
```bash
cd backend/server
# Create venv and install requirements if needed
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

# Start the Flask API
flask run --port 8000
```
