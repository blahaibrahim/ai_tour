# Route Generation Service

AR Tourism Platform — Route Generation module (Layers 2–5), built against `Route_Generation_Module_Technical_Design_Spec.docx`.

## Status

- [x] **Step 1 — Contracts.** POI, Cluster, Segment, Route, City Config models.
- [x] **Step 2 — Adapter layer.** `GraphHopperAdapter` with burst-limit protection (1.5s delay), and `RedisCacheAdapter`.
- [x] **Step 3 — Data layer.** PostgreSQL schema with PostGIS extension. Migrations and Kysely Repositories.
- [x] **Step 4 — Domain layer.** Advanced clustering (K-Means/DBSCAN fallback), TSP ordering, segment estimation.
- [x] **Step 5 — Orchestration.** `RouteGenerationOrchestrator` bringing caching and domains together.
- [x] **Step 6 & 7 — API & Deployment.** Fastify Server, rate-limiting, graceful degradation, and Dockerized infrastructure.

---

## 🚀 Frontend Integration Guide

The Route Generation Service exposes a single, powerful endpoint for generating tourism routes. It handles all clustering, pathfinding, caching, and database lookups in the background.

### `POST /api/v1/routes/generate`

Generates an optimized route for a specific city and theme within a given time budget.

**Headers:**
- `Content-Type: application/json`

**Request Body:**
```json
{
  "cityId": "00000000-0000-4000-a000-000000000010", // UUID of the City (Algiers: ...010, Oran: ...020, Constantine: ...030)
  "theme": "nature",                                // String: "nature", "history", "culture", etc.
  "timeBudgetMinutes": 180                          // Integer: How much time the user has to spend
}
```

**Response (Success - 200 OK):**
```json
{
  "id": "9776db94-0d12-439e-9567-74dc56b746d1",       // The saved Route UUID (Frontend should store this)
  "cityId": "00000000-0000-4000-a000-000000000020",
  "theme": "nature",
  "timeBudgetMinutes": 180,
  "transportMode": "driving",
  "segments": [
    {
      "mode": "driving",
      "from": { "lat": 35.699, "lng": -0.629 },
      "to": { "lat": 35.7055, "lng": -0.6555 },
      "durationMinutes": 5,
      "distanceMeters": 1200,
      "geometry": [ /* Array of lat/lng pairs to draw the Polyline on your map */ ]
    }
  ],
  "waypoints": [
    {
      "poiId": "00000000-0000-4000-d000-000000000010",
      "sequenceOrder": 0,
      "clusterId": 0,
      "location": { "lat": 35.699, "lng": -0.629 },
      "checkpointRadiusMeters": 30
    }
  ],
  "estimatedTotalDurationMinutes": 145,
  "dayCountFlag": 1,
  "generatedAt": "2026-08-13T18:22:04.489Z"
}
```

### Map Drawing Tips for Frontend:
1. **Markers:** Iterate over the `waypoints` array. You can hit your own POI endpoint with `poiId` to get the image/title, and plot the `location` coordinates on your map.
2. **Polylines:** Iterate over the `segments` array and concatenate the `geometry` array points to draw the actual path the user will take between clusters.

---

## 🛠️ Setting up on a New Machine

To deploy this service on a new server or another developer's machine, follow these steps exactly:

### 1. Prerequisites
- **Node.js:** v22.0.0 or higher.
- **Docker & Docker Compose:** Installed and running.
- **GraphHopper API Key:** Needed for route calculation.

### 2. Environment Configuration
Clone the repository, then copy the environment variables:
```bash
git clone <repository_url>
cd route-generation-service
cp .env.example .env
```
Edit `.env` and add your real GraphHopper API Key:
```env
ROUTING_PROVIDER_GRAPHHOPPER_API_KEY="your_real_key_here"
```

### 3. Start Infrastructure
Start the PostgreSQL (with PostGIS) and Redis containers.
```bash
sudo docker compose up -d postgres redis
```
*(Wait 5-10 seconds for PostgreSQL to initialize).*

### 4. Database Setup & Seeding
Install dependencies, run the schema migrations, and inject the seed data (which includes Algiers, Oran, and Constantine fixtures):
```bash
npm install
npm run migrate:up
npm run seed
```

### 5. Start the API
Start the Fastify API server:
```bash
# For development
npm run dev:api

# For production
npm run build
npm start
```
The API will be available at `http://localhost:3000`.

### ⚠️ Important Note on Rate Limiting
Because this project utilizes the free tier of the GraphHopper API, the adapter enforces a **1.5-second delay** between external requests to prevent your key from being banned. 

The *very first time* you generate a route for a new city/theme combination, it might take 15-30 seconds to respond as it calculates the matrix and fetches the polylines. 

However, all subsequent requests for that same route/matrix are **cached in Redis**, and will return in `< 10ms`.
