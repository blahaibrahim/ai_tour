/**
 * The shapes that flow between modules.
 *
 * The Python passed these as bare `dict` / `list[dict]` through six modules,
 * which is how the osm-id-vs-uuid mismatch in `/api/itinerary/modify` and the
 * `stops.index()` misindexing both got in. Naming them is most of the value of
 * this port.
 */

/** OSM tag bag. Values are optional because Python read them with `.get()`. */
export interface OsmTags {
  [key: string]: string | undefined;
}

export interface Bounds {
  minlat: number;
  minlon: number;
  maxlat: number;
  maxlon: number;
}

/** One POI as `ingestion/overpass.ts` emits it. */
export interface Poi {
  osm_type: string;
  osm_id: number;
  name: string;
  category: string;
  lat: number;
  lng: number;
  /** `null` for nodes, which have no extent. */
  bounds: Bounds | null;
  tags: OsmTags;
  wikidata_qid?: string | null;
  /** The OSM `wikipedia` tag, in "en:Casbah of Algiers" form. */
  wikipedia?: string | null;
}

/** What `ingestion/photos.ts` resolves, and what a stop carries to the client. */
export interface PhotoFields {
  photo_url: string;
  photo_attribution: string;
  photo_license: string;
  photo_source_url: string;
  photo_is_stock?: boolean;
  photo_stock_note?: string;
}

/**
 * A ranked route candidate. The index signature is not laziness: `modify`
 * re-adopts client-supplied stops verbatim (`merged = dict(stop)`), so a
 * candidate genuinely can carry fields this server never wrote.
 */
export interface Candidate {
  id: string;
  name: string;
  category: string;
  lat: number;
  lng: number;
  bounds?: Bounds | null;
  tags: OsmTags;
  interest_score: number;
  distance_km: number;
  blurb: string;
  wikipedia?: string | null;
  wikidata_qid?: string | null;
  region?: string | null;
  photo_url?: string | null;
  photo_attribution?: string;
  photo_license?: string;
  photo_source_url?: string;
  photo_is_stock?: boolean;
  photo_stock_note?: string;
  reason?: string;
  [key: string]: unknown;
}

/** One `{location_id, reason, suggested_order}` pick from the model. */
export interface LlmPick {
  location_id: string;
  reason?: string;
  suggested_order?: number;
}

/** A row as `data/locationsRepo.ts` serves it, whatever answered. */
export interface LocationRow {
  id: string;
  name: string;
  region: string | null;
  category: string;
  blurb: string;
  task_type: string | null;
  task_label: string | null;
  lat: number;
  lng: number;
  distance_km: number;
  photo_url?: string | null;
}

/** The narrower shape `get_location` returns (no coordinates). */
export interface LocationDetail {
  id: string;
  name: string;
  region: string | null;
  category: string;
  blurb: string;
  [key: string]: unknown;
}

export interface WikidataItem {
  qid: string;
  name: string;
  lat: number | null;
  lng: number | null;
  is_unesco: boolean;
  has_heritage: boolean;
  image_filename: string | null;
  wikipedia_title: string | null;
  sitelinks: number;
}

export interface WikipediaSummary {
  /** The article's own canonical title, which is not necessarily the title
   * that was requested — the REST endpoint resolves redirects, so asking for
   * "Casbah" can come back as "Casbah of Algiers". Callers that go on to hit
   * the pageviews API must use this one: that endpoint does not follow
   * redirects and 404s on the alias. */
  title: string;
  extract: string;
  thumbnail_url: string | null;
  original_url: string | null;
}

/** The structured frame both description paths work from. */
export interface Facts {
  name: string;
  kind: string | null;
  embassy: string | null;
  qualifiers: string[];
  place: string | null;
  street: string | null;
  description: string | null;
  website: string | null;
}

export type HeritageStatus = "unesco_world_heritage" | "heritage_listed" | null;

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}
