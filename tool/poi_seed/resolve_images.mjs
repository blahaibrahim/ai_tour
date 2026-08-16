/**
 * Resolves a freely-licensed photo for every POI in the catalogue, and emits the
 * seed SQL.
 *
 * "All locations must have images" is a hard constraint, not a best effort, so
 * this script is the gate: a POI that comes out the other side without a photo
 * URL that actually returned an image is *dropped* and listed in the report,
 * rather than inserted with a null photo for the app to render a grey box for.
 *
 * The lookup cascade, cheapest and most trustworthy first:
 *
 *   1. The lead image of the POI's Wikipedia article (en, then fr, then ar).
 *      This is the picture an editor chose to represent the subject, so it is
 *      almost always the establishing shot a traveller expects.
 *   2. A Commons file search scoped to the POI's Commons category, which is
 *      curated per-subject and so still on-topic.
 *   3. A plain Commons file search on the POI's name — the loosest step, and the
 *      only one that can drift, which is why it runs last.
 *
 * Whatever step wins, the file is then resolved *on Commons* for licence,
 * author and description page, because those are the fields the attribution
 * line in the app is built from and the Wikipedia mirror of them is lossy.
 *
 * Coordinates come from Wikipedia when the article carries them: a hand-typed
 * lat/lng in the catalogue is a guess, the article's is maintained. The
 * catalogue value stays as the fallback, and as the sanity check — a Wikipedia
 * coordinate more than DRIFT_KM from it is treated as the wrong article and
 * discarded.
 *
 * Usage:
 *   node tool/poi_seed/resolve_images.mjs            # writes seed + report
 *   node tool/poi_seed/resolve_images.mjs --limit 5  # smoke test
 */

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { CATALOGUE, CITY_IDS, CATEGORY_IDS } from './catalogue.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

/** Commons rejects unidentified clients; be a good citizen and say who we are. */
const UA = 'ai-tour-poi-seeder/1.0 (https://github.com/ai_tour; contact via repo)';

/** Width to request thumbnails at. Big enough for a full-bleed phone hero. */
const THUMB_WIDTH = 1280;

/** How far a Wikipedia coordinate may sit from the catalogue one before we
 *  conclude we matched the wrong article. */
const DRIFT_KM = 12;

/** Licences we will not ship. Anything non-commercial or no-derivatives is a
 *  liability in a product, however convenient the photo. */
const LICENCE_DENY = [/\bNC\b/i, /\bND\b/i, /non-?commercial/i, /no-?deriv/i, /fair use/i];

const args = process.argv.slice(2);
const limitArg = args.indexOf('--limit');
const LIMIT = limitArg >= 0 ? Number(args[limitArg + 1]) : Infinity;

// -----------------------------------------------------------------------------
// HTTP
// -----------------------------------------------------------------------------

async function getJson(url, tries = 3) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) return null;
      return await res.json();
    } catch (err) {
      if (attempt === tries) return null;
      await sleep(400 * attempt);
    }
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Confirms a URL really serves an image.
 *
 * The whole point of this script is that the app never renders a broken tile,
 * and a Commons API response describing a file is not the same claim as that
 * file being fetchable — renames, deletions and thumbnailer failures all
 * produce a healthy-looking API record pointing at a 404.
 *
 * The retry loop is not defensive padding. Verifying every candidate hammers
 * upload.wikimedia.org with a burst of requests, and once it starts shedding
 * load a single non-ok response is indistinguishable from a dead file — the
 * first run of this script "lost" eight POIs that way, all of them clustered at
 * the end, all of them fine on a second look. A photo is only declared missing
 * after the CDN has been given several chances to say so.
 */
async function verifyImage(url, tries = 4) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    for (const method of ['HEAD', 'GET']) {
      try {
        const res = await fetch(url, { method, headers: { 'User-Agent': UA } });
        if (res.ok) {
          const type = res.headers.get('content-type') ?? '';
          if (method === 'GET') res.body?.cancel?.();
          if (type.startsWith('image/')) return true;
          break; // Served something that isn't an image — retrying won't help.
        }
        // 404/410 are verdicts; everything else is the CDN having a moment.
        if (res.status === 404 || res.status === 410) return false;
      } catch {
        /* transport blip — fall through to the backoff */
      }
    }
    if (attempt < tries) await sleep(600 * attempt);
  }
  return false;
}

// -----------------------------------------------------------------------------
// Wikipedia / Commons
// -----------------------------------------------------------------------------

const api = (host, params) =>
  `https://${host}/w/api.php?${new URLSearchParams({ format: 'json', formatversion: '2', origin: '*', ...params })}`;

/** The lead image filename and coordinates of a Wikipedia article. */
async function wikipediaArticle(lang, title) {
  const data = await getJson(
    api(`${lang}.wikipedia.org`, {
      action: 'query',
      prop: 'pageimages|coordinates',
      piprop: 'name',
      pilicense: 'free',
      redirects: '1',
      titles: title,
    }),
  );
  const page = data?.query?.pages?.[0];
  if (!page || page.missing) return null;
  return {
    file: page.pageimage ? `File:${page.pageimage}` : null,
    lat: page.coordinates?.[0]?.lat ?? null,
    lng: page.coordinates?.[0]?.lon ?? null,
  };
}

/**
 * Full Commons record for a file: thumbnail, author, licence, description page.
 *
 * `extmetadata` carries the author as an HTML fragment (usually a link to the
 * uploader's user page), which is why it gets stripped rather than used raw —
 * the app renders attribution as plain text.
 */
async function commonsFile(fileTitle) {
  const data = await getJson(
    api('commons.wikimedia.org', {
      action: 'query',
      prop: 'imageinfo',
      iiprop: 'url|extmetadata|mime|size',
      iiurlwidth: String(THUMB_WIDTH),
      titles: fileTitle,
    }),
  );
  const page = data?.query?.pages?.[0];
  const info = page?.imageinfo?.[0];
  if (!info) return null;
  return describeFile(page.title, info);
}

function describeFile(title, info) {
  if (info.mime && !info.mime.startsWith('image/')) return null;
  const meta = info.extmetadata ?? {};
  const licence = plain(meta.LicenseShortName?.value) || plain(meta.License?.value) || 'Unknown';
  if (LICENCE_DENY.some((re) => re.test(licence))) return null;

  return {
    title,
    // The scaled thumbnail, not the original: originals on Commons are
    // routinely 8–20 MB, which is a hostile thing to put behind a list view on
    // a phone. `thumburl` is absent only for files the thumbnailer can't
    // handle, and those we'd rather skip anyway.
    //
    // The query string is Wikimedia's own campaign tracking, added because we
    // asked their API rather than because the CDN needs it. Storing it would
    // bake an analytics tag for a third party into every row of our catalogue
    // and defeat CDN caching between clients, so it goes.
    url: stripQuery(info.thumburl ?? info.url),
    width: info.thumbwidth ?? info.width,
    height: info.thumbheight ?? info.height,
    attribution: plain(meta.Artist?.value) || 'Wikimedia Commons contributor',
    licence,
    sourceUrl: info.descriptionurl ?? `https://commons.wikimedia.org/wiki/${encodeURIComponent(title)}`,
  };
}

const stripQuery = (url) => (url ? url.split('?')[0] : url);

/** Strips the HTML Commons wraps author names in, and collapses whitespace. */
function plain(html) {
  if (!html) return '';
  return html
    .replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 200);
}

/**
 * Candidate files from a Commons search, best first.
 *
 * `filetype:bitmap` keeps out SVG coats-of-arms and PDFs of scanned documents,
 * which otherwise dominate the results for historical subjects.
 */
async function commonsSearch(query) {
  return candidates(
    api('commons.wikimedia.org', {
      action: 'query',
      generator: 'search',
      gsrsearch: `${query} filetype:bitmap`,
      gsrnamespace: '6',
      gsrlimit: '12',
      prop: 'imageinfo',
      iiprop: 'url|extmetadata|mime|size',
      iiurlwidth: String(THUMB_WIDTH),
    }),
  );
}

/**
 * Files belonging to a Commons category.
 *
 * Deliberately `categorymembers` rather than an `incategory:` search: category
 * membership is a fact in the database, whereas `incategory:` asks the search
 * index about it and answers nothing at all for the many Algerian subject
 * categories that were never indexed under that name.
 */
async function commonsCategoryFiles(category) {
  const title = category.startsWith('Category:') ? category : `Category:${category}`;
  return candidates(
    api('commons.wikimedia.org', {
      action: 'query',
      generator: 'categorymembers',
      gcmtitle: title,
      gcmtype: 'file',
      gcmlimit: '20',
      prop: 'imageinfo',
      iiprop: 'url|extmetadata|mime|size',
      iiurlwidth: String(THUMB_WIDTH),
    }),
  );
}

async function candidates(url) {
  const data = await getJson(url);
  const pages = data?.query?.pages ?? [];
  return pages
    .map((p) => (p.imageinfo?.[0] ? describeFile(p.title, p.imageinfo[0]) : null))
    .filter(Boolean)
    // A 200px-wide file is a logo or a map legend, not a photo of a place.
    .filter((f) => (f.width ?? 0) >= 640);
}

// -----------------------------------------------------------------------------
// Resolution
// -----------------------------------------------------------------------------

function haversineKm(a, b) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const la1 = (a.lat * Math.PI) / 180;
  const la2 = (b.lat * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

async function resolve(poi) {
  const trace = [];
  let coords = null;

  // 0. A curator's override, when the automatic cascade is known to be wrong.
  //
  // The cascade is good but not infallible: a Wikipedia article's lead image
  // can be an adjacent landmark rather than the subject (the Fine Arts museum
  // led with a fountain in the garden next door), and a Commons text search for
  // a place with a French name can land on a French oil painting. Where that
  // has been caught by eye, `commonsFile` pins the right file so the mistake
  // does not come back on the next run — which is the only thing that makes
  // re-running this script safe.
  //
  // Pinning also pins the coordinates to the catalogue's. The two failures go
  // together: an article whose lead image is the wrong subject is usually an
  // article about the wrong subject, so its coordinates are not to be trusted
  // either — Constantine's casbah was being placed nine kilometres out by the
  // city article it matched.
  if (poi.commonsFile) {
    const file = await commonsFile(poi.commonsFile);
    if (file && (await verifyImage(file.url))) {
      return { photo: file, via: 'pinned', coords: null, trace };
    }
    // A pin that has stopped resolving is a bug in the catalogue, not a reason
    // to quietly fall back to a picture nobody chose.
    trace.push(`pinned ${poi.commonsFile} → unusable, catalogue needs updating`);
    return { photo: null, via: null, coords: null, trace };
  }

  // 1. Wikipedia lead images, in the catalogue's order of preference.
  for (const hint of poi.wiki ?? []) {
    const [lang, ...rest] = hint.split(':');
    const title = rest.join(':');
    const article = await wikipediaArticle(lang, title);
    if (!article) {
      trace.push(`${lang}:${title} → no article`);
      continue;
    }

    if (article.lat != null && coords == null) {
      const drift = haversineKm({ lat: poi.lat, lng: poi.lng }, { lat: article.lat, lng: article.lng });
      if (drift <= DRIFT_KM) {
        coords = { lat: article.lat, lng: article.lng, drift };
      } else {
        trace.push(`${lang}:${title} → coord drift ${drift.toFixed(1)}km, ignored`);
      }
    }

    if (!article.file) {
      trace.push(`${lang}:${title} → article has no free lead image`);
      continue;
    }
    const file = await commonsFile(article.file);
    if (file && (await verifyImage(file.url))) {
      return { photo: file, via: `wikipedia:${lang}`, coords, trace };
    }
    trace.push(`${lang}:${title} → lead image ${article.file} unusable`);
  }

  // 2. The POI's own Commons category.
  if (poi.commonsCategory) {
    for (const file of await commonsCategoryFiles(poi.commonsCategory)) {
      if (await verifyImage(file.url)) {
        return { photo: file, via: `commons-category:${poi.commonsCategory}`, coords, trace };
      }
    }
    trace.push(`commons category "${poi.commonsCategory}" → nothing usable`);
  }

  // 3. Free-text Commons search.
  for (const query of poi.commonsSearch ?? [poi.en]) {
    for (const file of await commonsSearch(query)) {
      if (await verifyImage(file.url)) {
        return { photo: file, via: `commons-search:${query}`, coords, trace };
      }
    }
    trace.push(`commons search "${query}" → nothing usable`);
  }

  return { photo: null, via: null, coords, trace };
}

// -----------------------------------------------------------------------------
// SQL
// -----------------------------------------------------------------------------

const q = (v) => (v == null || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`);

function toSql(rows) {
  const values = rows
    .map(
      (r) => `  (
    ${q(r.cityId)}::uuid, ${q(r.categoryId)}::uuid,
    ${q(r.en)}, ${q(r.fr)}, ${q(r.ar)},
    ${q(r.dEn)}, ${q(r.dFr)}, ${q(r.dAr)},
    st_setsrid(st_makepoint(${r.lng}, ${r.lat}), 4326)::geography,
    ${q(r.hours)}, ${r.min}, ${r.radius},
    ${q(r.key)},
    ${q(r.photo.url)}, ${q(r.photo.attribution)}, ${q(r.photo.licence)}, ${q(r.photo.sourceUrl)}
  )`,
    )
    .join(',\n');

  return `-- Curated POI catalogue for the pilot cities, regenerated by
-- tool/poi_seed/resolve_images.mjs on ${new Date().toISOString().slice(0, 10)}.
--
-- Every row carries a photo: the resolver drops any POI whose image could not be
-- fetched and verified, so "photo_url is not null" is an invariant of this file
-- rather than a property that happens to hold today. Coordinates are taken from
-- the subject's Wikipedia article where it has them.
--
-- Do not hand-edit. Change tool/poi_seed/catalogue.mjs and re-run the resolver.

begin;

-- Generated routes reference POIs by id, so they cannot outlive a catalogue
-- swap: a stop pointing at a deleted POI is a broken itinerary, and one
-- pointing at a *replacement* POI at the same id would be worse. Both go, and
-- with them the per-user progress and mascot spawns hung off those routes —
-- there is nothing left for them to be progress through.
--
-- Ordered by dependency, deepest first, because these are all NO ACTION FKs.
delete from public.progress;
delete from public.mascot_spawns;
delete from public.route_stops;
delete from public.routes;
delete from public.progress_events;
delete from public.pois;

insert into public.pois (
  city_id, category_id,
  name_en, name_fr, name_ar,
  description_en, description_fr, description_ar,
  location,
  opening_hours_raw, avg_visit_duration_minutes, checkpoint_radius_meters,
  external_ref,
  photo_url, photo_attribution, photo_license, photo_source_url
) values
${values};

update public.pois set source = 'team_seeded', status = 'published', verified_by = 'poi_seed_tool';

commit;
`;
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

async function main() {
  const catalogue = CATALOGUE.slice(0, LIMIT);
  const resolved = [];
  const dropped = [];

  for (const [i, poi] of catalogue.entries()) {
    // Paced rather than parallel. Wikimedia asks unauthenticated clients to keep
    // to a serial request stream, and going wide here was what pushed the CDN
    // into shedding our verification requests in the first place.
    if (i > 0) await sleep(250);
    process.stdout.write(`[${i + 1}/${catalogue.length}] ${poi.en} … `);
    const { photo, via, coords, trace } = await resolve(poi);

    if (!photo) {
      console.log('NO IMAGE');
      dropped.push({ ...poi, trace });
      continue;
    }

    const lat = coords?.lat ?? poi.lat;
    const lng = coords?.lng ?? poi.lng;
    console.log(`${photo.licence} via ${via}`);

    resolved.push({
      ...poi,
      lat,
      lng,
      coordSource: coords ? 'wikipedia' : 'catalogue',
      cityId: CITY_IDS[poi.city],
      categoryId: CATEGORY_IDS[poi.cat],
      photo,
      via,
    });
  }

  writeFileSync(join(HERE, 'seed_pois.sql'), toSql(resolved), 'utf8');
  writeFileSync(
    join(HERE, 'report.json'),
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        resolved: resolved.length,
        dropped: dropped.length,
        byCity: countBy(resolved, (r) => r.city),
        byCategory: countBy(resolved, (r) => r.cat),
        byLicence: countBy(resolved, (r) => r.photo.licence),
        bySource: countBy(resolved, (r) => r.via.split(':')[0]),
        coordsFromWikipedia: resolved.filter((r) => r.coordSource === 'wikipedia').length,
        droppedPois: dropped.map((d) => ({ key: d.key, name: d.en, trace: d.trace })),
        pois: resolved.map((r) => ({
          key: r.key,
          name: r.en,
          city: r.city,
          category: r.cat,
          lat: r.lat,
          lng: r.lng,
          coordSource: r.coordSource,
          photo: r.photo.url,
          licence: r.photo.licence,
          attribution: r.photo.attribution,
          via: r.via,
        })),
      },
      null,
      2,
    ),
    'utf8',
  );

  console.log(`\nResolved ${resolved.length}/${catalogue.length}. Dropped ${dropped.length}.`);
  for (const d of dropped) console.log(`  DROPPED ${d.key}: ${d.trace.join(' | ')}`);
  console.log(`\nWrote seed_pois.sql and report.json to ${HERE}`);
}

function countBy(rows, fn) {
  return rows.reduce((acc, r) => ((acc[fn(r)] = (acc[fn(r)] ?? 0) + 1), acc), {});
}

main();
