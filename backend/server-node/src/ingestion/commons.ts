/**
 * Wikimedia Commons file resolution — license and attribution metadata for
 * a Commons filename, used by `photos.ts`.
 */
import { getJson } from "../http";
import { getLogger } from "../logger";

const logger = getLogger("ingestion.commons");

export const TIMEOUT_S = 15;
const TAG_RE = /<[^>]+>/g;

/**
 * Commons' extmetadata fields (Artist, Credit) come back as HTML fragments
 * (`<a href=...>Name</a>`) — the app displays these as plain text, so this is
 * stripped once here rather than at every call site.
 */
function stripHtml(value: string | null | undefined): string | null {
  if (!value) return null;
  return value.replace(TAG_RE, "").trim() || null;
}

export interface CommonsFile {
  url: string;
  attribution: string;
  license: string;
  source_url: string;
}

interface ImageInfo {
  url: string;
  thumburl?: string;
  descriptionurl?: string;
  extmetadata?: Record<string, { value?: string } | undefined>;
}

interface CommonsResponse {
  query?: { pages?: Record<string, { imageinfo?: ImageInfo[] }> };
}

/**
 * Given a bare Commons filename (no `File:` prefix required), returns
 * {url, attribution, license, source_url} or null if the file doesn't exist or
 * has no usable license metadata. Every field here is exactly what
 * docs/backend/05's storage plan and docs/backend/11's checklist require to
 * display attribution alongside the image — never store a photo_url without
 * also storing where it came from.
 */
export async function resolveCommonsFile(filename: string): Promise<CommonsFile | null> {
  let pages: Record<string, { imageinfo?: ImageInfo[] }>;
  try {
    const data = await getJson<CommonsResponse>("https://commons.wikimedia.org/w/api.php", {
      params: {
        action: "query",
        titles: `File:${filename}`,
        prop: "imageinfo",
        iiprop: "url|extmetadata",
        iiurlwidth: "800",
        format: "json",
      },
      timeoutMs: TIMEOUT_S * 1000,
    });
    // The Python indexed `["query"]["pages"]` and let a KeyError join the
    // same `except` clause as a network failure — a missing key is a miss.
    if (!data.query?.pages) throw new Error("no query.pages in Commons response");
    pages = data.query.pages;
  } catch (error) {
    logger.warning(
      `Commons imageinfo lookup failed for ${JSON.stringify(filename)}: ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return null;
  }

  const page = Object.values(pages)[0] ?? {};
  const imageinfo = page.imageinfo;
  if (!imageinfo || imageinfo.length === 0) {
    return null;
  }

  const info = imageinfo[0];
  const meta = info.extmetadata ?? {};
  const artist = stripHtml(meta.Artist?.value);
  const credit = stripHtml(meta.Credit?.value);
  const licenseName = meta.LicenseShortName?.value;

  const attribution = artist || credit;
  if (!attribution || !licenseName) {
    // No usable attribution/license metadata — treat as unusable rather
    // than publishing an image we can't credit. Matches the "never
    // display a photo without its attribution" rule this module exists
    // to enforce.
    return null;
  }

  return {
    url: info.thumburl ?? info.url,
    attribution,
    license: licenseName,
    source_url: info.descriptionurl ?? info.url,
  };
}
