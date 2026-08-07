/**
 * Wikidata SPARQL enrichment — the strongest free "is this worth visiting?"
 * signal available (docs/backend/12). One query per tile returns everything
 * scoring needs: heritage designation, a Commons image, and the English
 * Wikipedia article, all in a single round trip rather than one lookup per POI.
 */
import { getJson } from "../http";
import { getLogger } from "../logger";
import { unquote } from "../text";
import { WikidataItem } from "../types";
import { haversineKm } from "../data/geo";

const logger = getLogger("ingestion.wikidata");

export const SPARQL_URL = "https://query.wikidata.org/sparql";
export const TIMEOUT_S = 25;

export const UNESCO_QID = "Q9259";

function buildQuery(lat: number, lng: number, radiusKm: number): string {
  return `
SELECT ?item ?itemLabel ?location ?heritage ?image ?article ?sitelinks WHERE {
  SERVICE wikibase:around {
    ?item wdt:P625 ?location .
    bd:serviceParam wikibase:center "Point(${lng} ${lat})"^^geo:wktLiteral .
    bd:serviceParam wikibase:radius "${radiusKm}" .
  }
  ?item wikibase:sitelinks ?sitelinks .
  OPTIONAL { ?item wdt:P1435 ?heritage . }
  OPTIONAL { ?item wdt:P18   ?image . }
  OPTIONAL {
    ?article schema:about ?item ;
             schema:isPartOf <https://en.wikipedia.org/> .
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
`;
}

const QID_RE = /Q\d+$/;
const POINT_RE = /^Point\(([-\d.]+) ([-\d.]+)\)/;

function qidFromUri(uri: string): string | null {
  const match = QID_RE.exec(uri);
  return match ? match[0] : null;
}

function parsePoint(wkt: string): [number, number] | null {
  const match = POINT_RE.exec(wkt);
  if (!match) return null;
  const lng = Number.parseFloat(match[1]);
  const lat = Number.parseFloat(match[2]);
  return [lat, lng];
}

type Binding = Record<string, { value: string } | undefined>;

/**
 * Wikidata items near a point, one row per item with duplicate
 * heritage/image/article bindings collapsed. Returns `[]` on failure —
 * ingestion proceeds with OSM-only signals rather than blocking on this.
 */
export async function fetchWikidataItems(
  lat: number,
  lng: number,
  radiusKm: number,
): Promise<WikidataItem[]> {
  const query = buildQuery(lat, lng, Math.max(radiusKm, 0.1));

  let bindings: Binding[];
  try {
    const data = await getJson<{ results?: { bindings?: Binding[] } }>(SPARQL_URL, {
      params: { query, format: "json" },
      headers: { Accept: "application/sparql-results+json" },
      timeoutMs: TIMEOUT_S * 1000,
    });
    if (!data.results?.bindings) {
      logger.warning(`Wikidata SPARQL returned unexpected shape for (${lat}, ${lng})`);
      return [];
    }
    bindings = data.results.bindings;
  } catch (error) {
    logger.warning(
      `Wikidata SPARQL request failed for (${lat}, ${lng}): ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return [];
  }

  const byQid = new Map<string, WikidataItem>();
  for (const row of bindings) {
    const itemUri = row.item?.value ?? "";
    const qid = qidFromUri(itemUri);
    if (!qid) continue;

    let entry = byQid.get(qid);
    if (!entry) {
      entry = {
        qid,
        name: row.itemLabel?.value || qid,
        lat: null,
        lng: null,
        is_unesco: false,
        has_heritage: false,
        image_filename: null,
        wikipedia_title: null,
        sitelinks: Number.parseInt(row.sitelinks?.value ?? "0", 10) || 0,
      };
      byQid.set(qid, entry);
    }

    if (entry.lat === null && row.location) {
      const point = parsePoint(row.location.value);
      if (point) {
        entry.lat = point[0];
        entry.lng = point[1];
      }
    }

    const heritageUri = row.heritage?.value;
    if (heritageUri) {
      entry.has_heritage = true;
      if (qidFromUri(heritageUri) === UNESCO_QID) {
        entry.is_unesco = true;
      }
    }

    if (entry.image_filename === null && row.image) {
      // Commons file URIs look like .../Special:FilePath/<name>, with
      // accented/spaced filenames percent-encoded — decode now so a
      // later request doesn't double-encode it into a 404.
      entry.image_filename = unquote(row.image.value.split("/").pop() ?? "");
    }

    if (entry.wikipedia_title === null && row.article) {
      // e.g. https://en.wikipedia.org/wiki/Casbah_of_Algiers
      entry.wikipedia_title = unquote(row.article.value.split("/").pop() ?? "");
    }
  }

  return [...byQid.values()].filter((entry) => entry.lat !== null);
}

/**
 * Nearest Wikidata item to an OSM point, within `maxDistanceM`. Called only
 * when the OSM element has no explicit `wikidata=*` tag — proximity is a
 * weaker signal than an explicit tag, so the radius here is deliberately tight
 * to avoid pairing a POI with the wrong nearby item.
 */
export function matchNearest(
  poiLat: number,
  poiLng: number,
  items: WikidataItem[],
  maxDistanceM = 75,
): WikidataItem | null {
  let best: WikidataItem | null = null;
  let bestDist = maxDistanceM / 1000.0;
  for (const item of items) {
    if (item.lat === null || item.lng === null) continue;
    const distKm = haversineKm(poiLat, poiLng, item.lat, item.lng);
    if (distKm <= bestDist) {
      best = item;
      bestDist = distKm;
    }
  }
  return best;
}
