-- AR Capture Module — schema (docs/mascot_plan.md §7)
--
-- Transcribed from the plan. Builds on top of 001_route_generation.sql's
-- `pois` / `routes` tables — this file cannot be applied on its own.
--
-- One deviation from the plan, marked NOT IN SPEC: `mascot_spawns.route_id`
-- and `mascot_captures` are scoped to `routes`/`pois` exactly as written, but
-- `routes.user_id` is nullable in 001 while every request in this deployment
-- is already authenticated (see 001's own NOT IN SPEC note on RLS) — so
-- `session_id` columns are kept for schema fidelity with the plan but are
-- expected to stay null in practice, the same way 001 treats them.

-- ---------------------------------------------------------------------
-- MASCOTS — species catalog, city-agnostic
-- ---------------------------------------------------------------------
CREATE TYPE mascot_rarity AS ENUM ('common', 'uncommon', 'rare', 'legendary');

CREATE TABLE mascots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key             TEXT NOT NULL UNIQUE,          -- 'fennec', 'corsair-cat'
  name_fr         TEXT NOT NULL,
  name_ar         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  lore_fr         TEXT, lore_ar TEXT, lore_en TEXT,
  rarity          mascot_rarity NOT NULL DEFAULT 'common',
  model_glb_ref   TEXT NOT NULL,                 -- storage key, Android/web
  model_usdz_ref  TEXT NOT NULL,                 -- storage key, iOS
  model_checksum  TEXT NOT NULL,                 -- SHA-256, client cache validation
  scale_meters    NUMERIC(4,2) NOT NULL DEFAULT 0.60,
  thumbnail_ref   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- AR_CONTENTS — per-POI AR configuration. Closes the loop 001 left open
-- with `pois.ar_content_id UUID -- FK added once AR module owns its table`.
-- ---------------------------------------------------------------------
CREATE TABLE ar_contents (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poi_id                UUID NOT NULL REFERENCES pois(id),
  mascot_id             UUID NOT NULL REFERENCES mascots(id),
  spawn_zone            GEOGRAPHY(POLYGON, 4326) NOT NULL,  -- curated, plan §5.1
  spawn_radius_meters   INT  NOT NULL DEFAULT 60,           -- zone clip radius
  capture_radius_meters INT  NOT NULL DEFAULT 25,           -- BURNING boundary
  hot_radius_meters     INT  NOT NULL DEFAULT 60,           -- HOT boundary / geofence
  band_thresholds       JSONB NOT NULL DEFAULT '{}',        -- per-POI overrides
  presentation_distance_meters NUMERIC(3,1) NOT NULL DEFAULT 4.0,
  is_enabled            BOOLEAN NOT NULL DEFAULT true,
  zone_reviewed_by      TEXT,                               -- manual safety review
  zone_reviewed_at      TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (poi_id)
);
CREATE INDEX idx_ar_contents_zone ON ar_contents USING GIST (spawn_zone);

ALTER TABLE pois
  ADD CONSTRAINT fk_pois_ar_content
  FOREIGN KEY (ar_content_id) REFERENCES ar_contents(id);

-- ---------------------------------------------------------------------
-- MASCOT_SPAWNS — one instance per (route, POI). Immutable, like `routes`.
-- ---------------------------------------------------------------------
CREATE TYPE spawn_state AS ENUM ('active', 'captured', 'expired');

CREATE TABLE mascot_spawns (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id        UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  poi_id          UUID NOT NULL REFERENCES pois(id),
  ar_content_id   UUID NOT NULL REFERENCES ar_contents(id),
  mascot_id       UUID NOT NULL REFERENCES mascots(id),
  location        GEOGRAPHY(POINT, 4326) NOT NULL,   -- horizontal only, no altitude
  spawn_seed      TEXT NOT NULL,                     -- reproducibility / audit
  spawn_epoch     DATE NOT NULL,
  state           spawn_state NOT NULL DEFAULT 'active',
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (route_id, poi_id)
);
CREATE INDEX idx_mascot_spawns_route ON mascot_spawns (route_id) WHERE state = 'active';
CREATE INDEX idx_mascot_spawns_location ON mascot_spawns USING GIST (location);

-- ---------------------------------------------------------------------
-- MASCOT_CAPTURES — append-only, records rejected attempts too (audit trail)
-- ---------------------------------------------------------------------
CREATE TYPE capture_outcome AS ENUM (
  'accepted', 'too_far', 'low_accuracy', 'already_captured',
  'invalid_token', 'stale', 'rate_limited'
);
CREATE TYPE placement_quality AS ENUM (
  'plane_hit', 'plane_estimated', 'gyro_overlay', 'map_capture'
);

CREATE TABLE mascot_captures (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  spawn_id          UUID NOT NULL REFERENCES mascot_spawns(id) ON DELETE CASCADE,
  user_id           UUID REFERENCES auth.users(id),   -- always set in this deployment (001)
  session_id        UUID,                             -- schema fidelity only, see header
  client_nonce      TEXT NOT NULL,    -- idempotency
  outcome           capture_outcome NOT NULL,
  device_fix        GEOGRAPHY(POINT, 4326),
  fix_accuracy_m    NUMERIC(6,2),
  measured_distance_m NUMERIC(8,2),
  placement         placement_quality,
  ar_telemetry      JSONB NOT NULL DEFAULT '{}',  -- planeCount, trackingState, ttfPlaneMs
  flags             TEXT[] NOT NULL DEFAULT '{}', -- 'implausible_speed', ...
  client_ts         TIMESTAMPTZ NOT NULL,
  is_offline_replay BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (client_nonce)
);
CREATE INDEX idx_captures_spawn ON mascot_captures (spawn_id);
CREATE INDEX idx_captures_flagged ON mascot_captures (created_at)
  WHERE array_length(flags, 1) > 0;
CREATE UNIQUE INDEX uq_capture_accepted_per_spawn
  ON mascot_captures (spawn_id) WHERE outcome = 'accepted';

-- ---------------------------------------------------------------------
-- MASCOT_COLLECTION — the album / "dex"
-- ---------------------------------------------------------------------
CREATE TABLE mascot_collection (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID REFERENCES auth.users(id),
  session_id        UUID,
  mascot_id         UUID NOT NULL REFERENCES mascots(id),
  first_captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  capture_count     INT NOT NULL DEFAULT 1,
  UNIQUE (user_id, mascot_id)
);

-- ---------------------------------------------------------------------
-- PUSH TOKENS — server-originated events only (plan §5.6: never the
-- proximity-alert mechanism, which is client-side geofencing)
-- ---------------------------------------------------------------------
CREATE TYPE device_platform AS ENUM ('android', 'ios', 'web');
CREATE TABLE push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES auth.users(id),
  session_id    UUID,
  token         TEXT NOT NULL UNIQUE,
  platform      device_platform NOT NULL,
  ar_capability TEXT,                     -- 'full' | 'limited' | 'none' — telemetry
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- RLS — same shape as 001: public read for the catalog (mascots,
-- ar_contents), own-row read/write for anything keyed by user_id.
-- ---------------------------------------------------------------------
ALTER TABLE mascots            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ar_contents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE mascot_spawns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE mascot_captures    ENABLE ROW LEVEL SECURITY;
ALTER TABLE mascot_collection  ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens        ENABLE ROW LEVEL SECURITY;

CREATE POLICY mascots_public ON mascots FOR SELECT USING (true);
CREATE POLICY ar_contents_enabled ON ar_contents FOR SELECT USING (is_enabled);

-- A spawn is visible to whoever can see the route it belongs to — same rule
-- 001 applies to `progress`, so the hunt manifest never leaks another user's
-- spawn point.
CREATE POLICY mascot_spawns_own ON mascot_spawns FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM routes r
    WHERE r.id = mascot_spawns.route_id AND (r.user_id IS NULL OR r.user_id = auth.uid())
  ));

CREATE POLICY mascot_captures_own ON mascot_captures FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY mascot_collection_own ON mascot_collection FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY push_tokens_own ON push_tokens FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
