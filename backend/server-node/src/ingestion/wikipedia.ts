/**
 * Wikipedia summary + pageviews — docs/backend/12's real blurb source and
 * its best free popularity signal.
 */
import { parseJson, raiseForStatus, request } from "../http";
import { getLogger } from "../logger";
import { WikipediaSummary } from "../types";

const logger = getLogger("ingestion.wikipedia");

export const TIMEOUT_S = 15;

interface SummaryResponse {
  title?: string;
  extract?: string;
  thumbnail?: { source?: string };
  originalimage?: { source?: string };
}

/**
 * Returns {extract, thumbnail_url, original_url} (the latter two `null` if the
 * article has no lead image) or null if the article doesn't exist / the request
 * fails. A missing summary is not fatal to ingestion — the POI still gets an
 * OSM-derived blurb.
 *
 * Both a thumbnail and the original are returned because they serve
 * different purposes: `thumbnail_url` is what gets stored and displayed
 * (a few hundred KB, this app's use case doesn't need more); `original_url`
 * is only used to recover the underlying Commons filename in `photos.ts`,
 * since the thumbnail URL's `/330px-` size prefix makes that extraction
 * more fragile than it needs to be.
 */
export async function fetchSummary(
  title: string,
  lang = "en",
): Promise<WikipediaSummary | null> {
  // `requests` percent-encoded the title as part of building the URL; the
  // explicit encode is the equivalent, and is what keeps a title with a space
  // or an accent from producing a malformed request.
  const url = `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`;

  let data: SummaryResponse;
  try {
    const response = await request(url, { timeoutMs: TIMEOUT_S * 1000 });
    if (response.status === 404) {
      return null;
    }
    await raiseForStatus(response, url);
    data = await parseJson<SummaryResponse>(response, url);
  } catch (error) {
    logger.warning(
      `Wikipedia summary fetch failed for ${JSON.stringify(title)}: ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return null;
  }

  const extract = data.extract;
  if (!extract) {
    return null;
  }

  return {
    // The endpoint always returns a title alongside an extract; the fallback
    // only keeps the type honest.
    title: data.title ?? title,
    extract,
    thumbnail_url: data.thumbnail?.source ?? null,
    original_url: data.originalimage?.source ?? null,
  };
}

function yyyymmdd(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}${month}${day}`;
}

/**
 * Total pageviews over the trailing 30 days, ending yesterday (today is
 * still accumulating and often isn't fully aggregated yet).
 *
 * Originally tried `monthly` granularity with the two dates set to the
 * first-of-month boundaries — that turned out to be a real bug, not a
 * style choice: it 400'd against the live API during ingestion testing
 * (`.../monthly/20260701/20260701`). Rather than guess at the exact
 * monthly-endpoint boundary convention against a rate-limited API, this
 * switched to `daily` granularity summed over the window — unambiguous,
 * and a more literal match for what "30d" in the field name actually means.
 */
export async function fetchPageviews30d(title: string, lang = "en"): Promise<number | null> {
  const DAY_MS = 24 * 60 * 60 * 1000;
  const yesterday = new Date(Date.now() - DAY_MS);
  const windowStart = new Date(yesterday.getTime() - 29 * DAY_MS); // 30 days inclusive

  const start = yyyymmdd(windowStart);
  const end = yyyymmdd(yesterday);

  const url =
    "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/" +
    `${lang}.wikipedia/all-access/user/${encodeURIComponent(title)}/daily/${start}/${end}`;

  let items: Array<{ views?: number }>;
  try {
    const response = await request(url, { timeoutMs: TIMEOUT_S * 1000 });
    if (response.status === 404) {
      return null;
    }
    await raiseForStatus(response, url);
    const data = await parseJson<{ items?: Array<{ views?: number }> }>(response, url);
    items = data.items ?? [];
  } catch (error) {
    logger.warning(
      `Wikipedia pageviews fetch failed for ${JSON.stringify(title)}: ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return null;
  }

  if (items.length === 0) {
    return null;
  }
  return items.reduce((sum, item) => sum + (item.views ?? 0), 0);
}
