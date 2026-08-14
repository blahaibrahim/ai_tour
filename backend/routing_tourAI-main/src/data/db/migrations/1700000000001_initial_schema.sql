-- Up
-- 001_initial_schema.sql
-- Route Generation Module — initial database schema (Section 7)
-- PostgreSQL 15+ with PostGIS extension required.

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
    opening_hours_raw TEXT,                    -- OSM opening_hours syntax, parseable
    avg_visit_duration_minutes INT NOT NULL DEFAULT 15,
    checkpoint_radius_meters INT NOT NULL DEFAULT 30,  -- per-POI AR checkpoint radius (Section 8/10)
    ar_content_id UUID,                        -- FK added once AR module owns its table
    stamp_id UUID,                             -- FK added once gamification module owns its table
    external_ref TEXT,                         -- e.g. 'osm:node/123456' — dedup / re-sync anchor
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

-- ROUTES — immutable once generated
CREATE TYPE transport_mode AS ENUM ('walking', 'driving', 'hybrid');

CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id UUID NOT NULL REFERENCES cities(id),
    session_id UUID,                           -- nullable: supports anonymous demo usage
    user_id UUID,                              -- nullable until auth exists
    theme TEXT NOT NULL,
    time_budget_minutes INT NOT NULL,
    transport_mode transport_mode NOT NULL DEFAULT 'hybrid',
    segments JSONB NOT NULL,                   -- opaque per-leg geometry / mode / duration
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
CREATE INDEX idx_route_stops_poi ON route_stops (poi_id);   -- powers data-flywheel queries

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

-- Down
DROP TABLE progress_events;
DROP TABLE progress;
DROP TYPE progress_status;

DROP TABLE route_stops;
DROP TABLE routes;
DROP TYPE transport_mode;

DROP TABLE pois;
DROP TYPE poi_status;
DROP TYPE poi_source;

DROP TABLE categories;

DROP TABLE cities;
DROP TYPE routing_provider;
DROP TYPE rollout_status;

DROP TABLE regions;
