# AI-Powered Travel Itinerary Generation — Architecture Plan

## 1. Objective

Build a travel itinerary system that accepts:

* User GPS coordinates
* Natural-language travel preferences
* Optional constraints such as trip duration, travel mode, and maximum distance

The system generates an optimized itinerary containing **8 verified real-world Points of Interest (POIs)**.

The system must prioritize:

1. **Real-world accuracy** — coordinates must come from verified geographic datasets.
2. **Semantic relevance** — locations must match nuanced user preferences.
3. **Broad coverage** — beaches, natural areas, trails, viewpoints, historical sites, and urban attractions must all be discoverable.
4. **Fast execution** — route generation should normally complete within a few seconds.
5. **Low operating cost** — rely primarily on open geographic data and self-hostable services.

---

# 2. Core Design Principle

Separate the system into four responsibilities:

```text
Geographic Data
      ↓
Verified POI Database
      ↓
Intent-Aware Candidate Retrieval
      ↓
AI Selection + Route Optimization
```

The LLM must never invent locations or coordinates.

All final locations must already exist in the verified POI database.

The LLM may:

* Interpret user intent
* Compare candidate locations
* Select suitable POI IDs
* Explain itinerary choices

The LLM may not:

* Generate new POIs
* Generate coordinates
* modify coordinates
* return locations outside the candidate set

---

# 3. High-Level Pipeline

```text
User GPS + Travel Prompt
              │
              ▼
      Intent Extraction
              │
              ▼
      Category Expansion
              │
              ▼
 Fast Geographic Candidate Search
              │
              ▼
 Hybrid Ranking and Diversification
              │
              ▼
      LLM Candidate Selection
              │
              ▼
     Travel-Time Calculation
              │
              ▼
 Route Optimization and Finalization
              │
              ▼
       8-Stop Itinerary
```

Target execution time:

| Stage                    |          Target |
| ------------------------ | --------------: |
| Intent extraction        |      200–700 ms |
| Geographic retrieval     |       50–200 ms |
| Hybrid ranking           |       50–150 ms |
| LLM candidate selection  |    500–1,500 ms |
| Route matrix calculation |      100–500 ms |
| Route optimization       |    Under 100 ms |
| **Total target**         | **1–3 seconds** |

The first request for a new region may take longer because of cache misses or external enrichment.

---

# 4. Geographic Data Layer

## 4.1 Primary Source: OpenStreetMap

OpenStreetMap is the authoritative geographic backbone.

Use it for:

* POI names
* GPS coordinates
* Geometry
* Geographic categories
* Natural features
* Historical sites
* Parks and protected areas
* Trails and viewpoints
* Local attractions

Important OSM tags should be retained rather than discarded.

Examples:

```text
natural=beach
natural=peak
natural=water
natural=cliff

tourism=viewpoint
tourism=attraction
tourism=museum

historic=ruins
historic=archaeological_site
historic=castle

leisure=park
leisure=nature_reserve

boundary=protected_area
```

Store the complete useful tag set in PostgreSQL as `JSONB`.

Do not require a Wikipedia or Wikidata link for a POI to be included.

---

## 4.2 Offline Regional Data

Do not query Overpass during every itinerary request.

Instead:

```text
OSM Regional Extract
        ↓
Offline Processing
        ↓
POI Normalization
        ↓
Semantic Enrichment
        ↓
PostGIS + pgvector
```

Use regional OSM extracts from Geofabrik.

Benefits:

* No Overpass request latency
* No public API rate limits
* Predictable performance
* Precomputed embeddings
* Faster geographic queries
* Better scalability

Overpass may remain available as an optional fallback for recent or missing data.

---

# 5. POI Data Model

Each POI should contain verified geographic data, structured semantic information, and generated travel context.

Example:

```json
{
  "id": "osm_way_123456",
  "name": "Example Beach",

  "latitude": 35.8123,
  "longitude": -0.6345,
  "geometry": "POLYGON(...)",

  "source": "openstreetmap",
  "source_id": "way/123456",

  "categories": [
    "beach",
    "coastal_nature"
  ],

  "features": [
    "sandy",
    "coastal",
    "public"
  ],

  "activities": [
    "swimming",
    "walking",
    "photography"
  ],

  "osm_tags": {
    "natural": "beach",
    "surface": "sand",
    "access": "public"
  },

  "semantic_description": "A public sandy beach suitable for swimming, coastal walks, and photography.",

  "metadata_quality": 0.78,
  "coordinate_confidence": 0.99
}
```

The coordinate fields must always come directly from a geographic source.

Generated descriptions must be stored separately from source data.

---

# 6. Multi-Source Enrichment

Use additional sources only to improve context.

Priority:

```text
Official tourism data
        ↓
Wikipedia
        ↓
Wikidata
        ↓
OSM tags
        ↓
Generated factual description
```

Possible enrichment:

* Historical periods
* Official descriptions
* Landmark types
* Images
* Geographic relationships
* Nearby cities and regions
* Cultural significance

If no external description exists, generate a concise description from verified OSM data.

Example input:

```json
{
  "name": "Example Beach",
  "tags": {
    "natural": "beach",
    "surface": "sand"
  },
  "nearby_features": [
    "coastline",
    "cliffs"
  ]
}
```

Generated output:

```text
A sandy coastal beach near scenic cliffs, suitable for swimming,
coastal walks, and photography.
```

The generation prompt must explicitly prohibit unsupported claims.

Do not invent:

* Facilities
* Opening hours
* Safety conditions
* Accessibility
* Historical information
* Popularity
* Activities not supported by source data

---

# 7. Semantic POI Cards

Every POI should receive a normalized semantic card.

Example:

```text
Name:
Example Beach

Type:
Beach and coastal natural attraction

Scenery:
Sandy coastline with nearby cliffs

Activities:
Swimming, walking, photography

Travel Themes:
Beach, nature, scenic coastline

Location:
Near Example City

Description:
A public sandy beach on a scenic coastline.
```

Generate embeddings from this normalized representation.

This ensures that a beach without Wikipedia can still match prompts such as:

* “Beautiful beaches”
* “Quiet coastal scenery”
* “Nature near the sea”
* “Good places for landscape photography”

---

# 8. User Intent Extraction

Use a small, fast LLM to convert the prompt into structured intent.

Input:

```text
I want to see beautiful beaches, nature, and maybe some historic ruins.
```

Output:

```json
{
  "themes": [
    {
      "name": "beach",
      "weight": 1.0
    },
    {
      "name": "nature",
      "weight": 0.85
    },
    {
      "name": "historic_ruins",
      "weight": 0.55
    }
  ],

  "activities": [
    "sightseeing",
    "walking",
    "photography"
  ],

  "required_categories": [
    "beach"
  ],

  "preferred_categories": [
    "natural_area",
    "historic_site"
  ],

  "excluded_categories": [],

  "number_of_stops": 8
}
```

Use structured JSON output with schema validation.

Cache repeated or similar intent interpretations when possible.

---

# 9. Category Expansion

Map user concepts to controlled geographic categories.

Example:

```text
Beach
↓
natural=beach
leisure=beach_resort
coastal_nature
```

```text
Nature
↓
natural=wood
natural=water
natural=peak
natural=cliff
natural=bay
waterway=waterfall
leisure=nature_reserve
boundary=protected_area
tourism=viewpoint
```

```text
Historic ruins
↓
historic=ruins
historic=archaeological_site
historic=castle
historic=fort
ruins=*
```

This structured expansion must happen before semantic search.

Do not rely on vector similarity to discover all geographic categories.

---

# 10. Fast Geographic Retrieval

Use PostGIS to retrieve candidates near the user.

Example:

```sql
SELECT *
FROM pois
WHERE ST_DWithin(
    geography,
    ST_SetSRID(
        ST_MakePoint(:longitude, :latitude),
        4326
    )::geography,
    :search_radius_meters
);
```

Create a spatial index:

```sql
CREATE INDEX pois_geography_index
ON pois
USING GIST (geography);
```

Retrieve separate candidate pools:

```text
Beach candidates:       100
Nature candidates:      100
Historical candidates:   50
Urban candidates:        50
```

Merge and deduplicate the pools before ranking.

This prevents locations with richer descriptions from dominating all results.

---

# 11. Hybrid Candidate Ranking

Do not use embeddings as the only ranking mechanism.

Calculate:

```text
Final Candidate Score =
    Semantic Similarity
  + Category Match
  + Feature Match
  + Activity Match
  + Geographic Relevance
  + Metadata Quality
  + Prominence
```

Initial weights:

```python
final_score = (
    0.30 * semantic_similarity
    + 0.25 * category_match
    + 0.15 * feature_match
    + 0.10 * activity_match
    + 0.10 * geographic_relevance
    + 0.05 * metadata_quality
    + 0.05 * prominence
)
```

Category matching should strongly boost exact matches.

For example:

```text
Prompt:
“Beautiful beaches”

POI:
category = beach

Result:
High structured relevance,
even if the POI has no Wikipedia article.
```

---

# 12. Candidate Diversification

Do not select the eight highest individual scores.

Use a diversity-aware reranking stage.

For the example prompt:

```text
Target itinerary:

2–4 beach locations
2–4 nature locations
0–2 historic locations
```

Avoid:

```text
Beach A
Beach B
Beach C
Beach D
Beach E
Beach F
Beach G
Beach H
```

unless the user explicitly requests only beaches.

Penalize:

* Duplicate experiences
* Nearby POIs with nearly identical characteristics
* Multiple stops representing the same attraction
* Excessive travel distance

Return approximately 30–50 diverse candidates to the final selection stage.

---

# 13. LLM Candidate Selection

The LLM receives structured candidate cards.

Example:

```json
{
  "id": "osm_way_123",
  "name": "Example Beach",

  "categories": [
    "beach",
    "coastal_nature"
  ],

  "features": [
    "sandy",
    "coastal"
  ],

  "activities": [
    "swimming",
    "walking",
    "photography"
  ],

  "description": "A sandy beach on a scenic coastline.",

  "distance_from_user_km": 12.4,

  "quality_score": 0.84
}
```

The LLM must return only candidate IDs:

```json
{
  "selected_ids": [
    "osm_way_123",
    "osm_node_456",
    "osm_relation_789"
  ]
}
```

The backend resolves all names and coordinates from the database.

The LLM must not return coordinates.

---

# 14. Route Generation

The LLM selects approximately 12–20 strong candidates.

The routing system then determines:

* Which 8 candidates to include
* The optimal visit order
* Total travel time
* Route geometry

Use a routing engine such as:

* OSRM
* Valhalla
* GraphHopper

Use actual road or walking travel times rather than straight-line distance.

Pipeline:

```text
12–20 Selected Candidates
             ↓
Travel-Time Matrix
             ↓
Route Optimization
             ↓
Best 8 Stops
             ↓
Optimal Stop Order
```

Use:

* Nearest-neighbor + 2-opt for the MVP
* OR-Tools for advanced route constraints

The optimizer should minimize:

```text
Travel Time
+ Route Distance
+ Duplicate Experiences
+ Low-Relevance Stops
```

while maximizing:

```text
User Intent Match
+ Theme Diversity
+ POI Quality
+ Geographic Coherence
```

---

# 15. Speed Optimization

## Precompute Offline

Precompute:

* POI categories
* Semantic cards
* Embeddings
* Metadata quality
* Geographic context
* Nearby feature relationships
* Prominence scores

Do not generate descriptions or embeddings during route requests.

---

## Cache Frequently Used Data

Cache:

* Parsed intent
* Nearby POI results
* Candidate rankings
* Travel-time matrices
* Popular routes

Suggested cache keys:

```text
intent:{normalized_prompt}

nearby:{geohash}:{radius}

route_matrix:{candidate_hash}:{travel_mode}
```

Use Redis for short-lived request caching.

---

## Use Two-Stage Retrieval

Stage 1: fast filtering

```text
PostGIS geographic filter
+
Category filter
↓
500–2,000 candidates
```

Stage 2: accurate ranking

```text
pgvector similarity
+
Structured scoring
↓
30–50 candidates
```

This avoids performing expensive semantic operations over the full POI database.

---

## Keep LLM Context Small

Do not send hundreds of POIs to the LLM.

Send only:

```text
30–50 candidates
```

Each candidate should be represented by a compact semantic card.

Use a smaller model for intent extraction and a larger model only when necessary for final itinerary reasoning.

---

# 16. Accuracy and Validation

Every final stop must pass:

```text
✓ Exists in the POI database

✓ Has valid coordinates

✓ Coordinates originate from a trusted geographic source

✓ Matches at least one requested theme

✓ Is geographically reachable

✓ Is not a duplicate

✓ Has sufficient metadata

✓ Fits the route constraints
```

Reject candidates when:

* Coordinates are missing
* Coordinates are invalid
* The POI is too far from the route
* The POI is a duplicate
* The location has extremely low metadata confidence
* The location conflicts with explicit user preferences

---

# 17. Recommended Technology Stack

```text
Mobile Application
└── Flutter

Backend
└── FastAPI

Database
└── Supabase PostgreSQL
    ├── PostGIS
    └── pgvector

Cache
└── Redis

Geographic Data
└── OpenStreetMap regional extracts

Entity Enrichment
├── Wikidata
├── Wikipedia
├── Wikimedia Commons
└── Official tourism datasets

Embeddings
└── BGE-M3 or multilingual E5

Intent Extraction
└── Small fast LLM

Itinerary Reasoning
└── Llama 3

Routing
└── OSRM or Valhalla

Route Optimization
└── Google OR-Tools
```

---

# 18. Implementation Phases

## Phase 1 — Core Accuracy

1. Keep OSM coordinates as the geographic source of truth.
2. Remove the Wikipedia requirement.
3. Store OSM tags as structured JSONB.
4. Add PostGIS spatial indexing.
5. Build deterministic semantic descriptions.
6. Generate multilingual embeddings.

Result:

```text
Verified coordinates
+
Broad natural-feature coverage
+
Fast local candidate retrieval
```

---

## Phase 2 — Better Relevance

1. Add LLM intent extraction.
2. Create category expansion rules.
3. Implement hybrid ranking.
4. Add category-specific candidate pools.
5. Add diversity-aware reranking.

Result:

```text
Better matching
+
Fewer irrelevant attractions
+
Balanced itineraries
```

---

## Phase 3 — Route Quality

1. Add OSRM or Valhalla.
2. Calculate travel-time matrices.
3. Select 8 stops from 12–20 candidates.
4. Optimize route order.
5. Add travel-time constraints.

Result:

```text
Relevant locations
+
Physically practical routes
+
Reduced unnecessary travel
```

---

## Phase 4 — Production Performance

1. Move from live Overpass queries to offline OSM extracts.
2. Precompute all semantic cards and embeddings.
3. Add Redis caching.
4. Add asynchronous enrichment workers.
5. Add incremental OSM updates.
6. Monitor latency and route quality.

Result:

```text
Typical route generation:
1–3 seconds

No dependency on live Overpass requests

Predictable performance at scale
```

---

# 19. Final Architecture

```text
User GPS + Prompt
        │
        ▼
Fast Intent Extraction
        │
        ▼
Category Expansion
        │
        ▼
PostGIS Geographic Retrieval
        │
        ▼
Hybrid Ranking
Vector + Categories + Features
        │
        ▼
Diversity-Aware Candidate Set
        │
        ▼
LLM Selects Verified POI IDs
        │
        ▼
Routing Engine
        │
        ▼
Route Optimizer
        │
        ▼
Verified 8-Stop Itinerary
```

## Final Principle

The system should use:

> **OSM and PostGIS for geographic truth, structured metadata for reliable matching, generated semantic cards for broad coverage, vector search for nuanced language, LLMs for intent and itinerary reasoning, and routing algorithms for physically valid routes.**

This design avoids the two major failure modes:

```text
Sparse Wikipedia data
→ solved by structured OSM enrichment

LLM-generated fake locations
→ prevented by candidate-ID-only selection
```

The expected result is a route generator that is faster, more geographically accurate, more robust for natural attractions, and substantially less dependent on expensive commercial location APIs.
