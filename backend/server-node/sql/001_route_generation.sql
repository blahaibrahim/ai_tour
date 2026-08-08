-- Route Generation Module — schema (Technical Design Spec §7)
--
-- Transcribed from the spec. Two additions are marked NOT IN SPEC and are
-- there because the schema as written cannot answer a question the endpoints
-- have to answer; each says what it is for. Everything else is verbatim.
--
-- This replaces the `locations` / `route_jobs` shape the old LLM+Overpass
-- itinerary route used. Those tables are NOT dropped here — the Flask server
-- still serves from them during the migration, and `/api/poi/ingest` still
-- writes to them. Dropping them is a separate, later migration.

CREATE EXTENSION IF NOT EXISTS postgis;

-- REGIONS — wilayas, administrative scaffold for phased rollout
CREATE TABLE regions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    name_ar TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CITIES — also holds per-city routing / rollout config
CREATE TYPE rollout_status AS ENUM ('planning', 'pilot', 'active');
CREATE TYPE routing_provider AS ENUM (
    'graphhopper', 'ors',
    'self_hosted_osrm', 'self_hosted_graphhopper', 'self_hosted_valhalla'
);

CREATE TABLE cities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id UUID REFERENCES regions(id),
    name TEXT NOT NULL,
    name_ar TEXT,
    name_fr TEXT,
    bounding_box GEOGRAPHY(POLYGON, 4326),
    cluster_radius_meters INT NOT NULL DEFAULT 500,
    active_routing_provider routing_provider NOT NULL DEFAULT 'graphhopper',
    rollout_status rollout_status NOT NULL DEFAULT 'planning',
    feature_flags JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

-- CATEGORIES — lookup table, carries display metadata
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL UNIQUE,
    label_fr TEXT NOT NULL,
    label_ar TEXT NOT NULL,
    label_en TEXT NOT NULL,
    icon_ref TEXT,
    color_hex TEXT
);

-- POIS
CREATE TYPE poi_source AS ENUM ('team_seeded', 'api_seeded', 'user_submitted', 'ministry_provided');
CREATE TYPE poi_status AS ENUM ('draft', 'verified', 'published');

CREATE TABLE pois (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id UUID NOT NULL REFERENCES cities(id),
    category_id UUID NOT NULL REFERENCES categories(id),
    name_fr TEXT, name_ar TEXT, name_en TEXT,
    description_fr TEXT, description_ar TEXT, description_en TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    opening_hours_raw TEXT,                       -- OSM opening_hours syntax, parseable
    avg_visit_duration_minutes INT NOT NULL DEFAULT 15,
    ar_content_id UUID,                           -- FK added once AR module owns its table
    stamp_id UUID,                                -- FK added once gamification module owns its table
    external_ref TEXT,                            -- e.g. 'osm:node/123456' — dedup / re-sync anchor
    source poi_source NOT NULL DEFAULT 'team_seeded',
    status poi_status NOT NULL DEFAULT 'draft',
    verified_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);
CREATE INDEX idx_pois_location ON pois USING GIST (location);
CREATE INDEX idx_pois_city_status_category ON pois (city_id, status, category_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_pois_external_ref ON pois (external_ref) WHERE external_ref IS NOT NULL;

-- NOT IN SPEC — the Response Assembler is specified to emit a per-POI
-- checkpoint radius, and §10 says it "is per-POI configurable, not global".
-- The spec's `pois` table has nowhere to put it, so it would have to be
-- hardcoded. Confirm the column name with the module owner before relying on
-- it; the repository stub reads it through one accessor so renaming is cheap.
ALTER TABLE pois ADD COLUMN checkpoint_radius_meters INT NOT NULL DEFAULT 40;

-- NOT IN SPEC — the app already displays a photo per stop and the existing
-- catalogue carries licence/attribution alongside every image (never a URL
-- without knowing what it is licensed under). Carried forward rather than
-- regressing that rule.
ALTER TABLE pois ADD COLUMN photo_url TEXT;
ALTER TABLE pois ADD COLUMN photo_attribution TEXT;
ALTER TABLE pois ADD COLUMN photo_license TEXT;
ALTER TABLE pois ADD COLUMN photo_source_url TEXT;

-- ROUTES — immutable once generated
CREATE TYPE transport_mode AS ENUM ('walking', 'driving', 'hybrid');

CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id UUID NOT NULL REFERENCES cities(id),
    session_id UUID,                              -- nullable: supports anonymous demo usage
    user_id UUID,                                 -- nullable until auth exists
    theme TEXT NOT NULL,
    time_budget_minutes INT NOT NULL,
    transport_mode transport_mode NOT NULL DEFAULT 'hybrid',
    segments JSONB NOT NULL,                      -- opaque per-leg geometry / mode / duration
    estimated_total_duration_minutes INT NOT NULL,
    day_count_flag INT NOT NULL DEFAULT 1,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ROUTE_STOPS — queryable, kept out of the segments JSON on purpose
CREATE TABLE route_stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    poi_id UUID NOT NULL REFERENCES pois(id),
    sequence_order INT NOT NULL,
    cluster_id INT NOT NULL
);
CREATE INDEX idx_route_stops_route ON route_stops (route_id);
CREATE INDEX idx_route_stops_poi ON route_stops (poi_id);  -- powers data-flywheel queries

-- PROGRESS — mutable, kept separate from the immutable route definition
CREATE TYPE progress_status AS ENUM ('in_progress', 'completed', 'abandoned');

CREATE TABLE progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id),
    status progress_status NOT NULL DEFAULT 'in_progress',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- PROGRESS_EVENTS — append-only checkpoint log
CREATE TABLE progress_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    progress_id UUID NOT NULL REFERENCES progress(id) ON DELETE CASCADE,
    poi_id UUID NOT NULL REFERENCES pois(id),
    arrived_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_progress_events_progress ON progress_events (progress_id);

-- NOT IN SPEC — `routes.user_id` is nullable per the spec, but this deployment
-- already authenticates every request, and without RLS any client could read
-- any route. Enable it here rather than discovering it in a security review.
-- Anonymous/demo rows (user_id IS NULL) stay readable, which is what the
-- spec's "supports anonymous demo usage" note asks for.
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY routes_own ON routes FOR SELECT
    USING (user_id IS NULL OR user_id = auth.uid());
CREATE POLICY progress_own ON progress FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM routes r
        WHERE r.id = progress.route_id AND (r.user_id IS NULL OR r.user_id = auth.uid())
    ));
CREATE POLICY progress_events_own ON progress_events FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM progress p
        JOIN routes r ON r.id = p.route_id
        WHERE p.id = progress_events.progress_id AND (r.user_id IS NULL OR r.user_id = auth.uid())
    ));

-- Published POIs and the city/category lookups are public read.
ALTER TABLE pois ENABLE ROW LEVEL SECURITY;
ALTER TABLE cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY pois_published ON pois FOR SELECT
    USING (status = 'published' AND deleted_at IS NULL);
CREATE POLICY cities_public ON cities FOR SELECT USING (deleted_at IS NULL);
CREATE POLICY categories_public ON categories FOR SELECT USING (true);
