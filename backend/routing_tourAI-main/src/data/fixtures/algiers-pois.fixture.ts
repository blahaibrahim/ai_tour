import type { Poi } from '../../domain/models/poi.model.js';
import type { CityConfig } from '../../domain/models/city-config.model.js';

// ---------------------------------------------------------------------------
// IDs — deterministic UUIDs so tests and the driver can reference them stably.
// ---------------------------------------------------------------------------

export const ALGIERS_REGION_ID = '00000000-0000-4000-a000-000000000001';
export const ALGIERS_CITY_ID = '00000000-0000-4000-a000-000000000010';

export const CATEGORY_IDS = {
  historical_monument: '00000000-0000-4000-b000-000000000001',
  museum: '00000000-0000-4000-b000-000000000002',
  park_garden: '00000000-0000-4000-b000-000000000003',
  religious_site: '00000000-0000-4000-b000-000000000004',
  viewpoint: '00000000-0000-4000-b000-000000000005',
  cultural_venue: '00000000-0000-4000-b000-000000000006',
  beach: '00000000-0000-4000-b000-000000000007',
} as const;

// ---------------------------------------------------------------------------
// Algiers city config — pilot city, active, GraphHopper primary provider.
// ---------------------------------------------------------------------------

export const ALGIERS_CITY_CONFIG: CityConfig = {
  id: ALGIERS_CITY_ID,
  name: 'Algiers',
  nameAr: 'الجزائر',
  nameFr: 'Alger',
  clusterRadiusMeters: 500,
  activeRoutingProvider: 'graphhopper',
  rolloutStatus: 'pilot',
  featureFlags: {},
};

// ---------------------------------------------------------------------------
// 15 hand-authored fixture POIs spread across Algiers — real coordinates,
// realistic dwell times. All status = 'published' per the PoiRepository
// contract.
// ---------------------------------------------------------------------------

export const ALGIERS_POIS: Poi[] = [
  // ── Casbah / Old Town cluster ──────────────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000001',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.historical_monument,
    nameFr: 'Casbah d\'Alger',
    nameAr: 'قصبة الجزائر',
    nameEn: 'Casbah of Algiers',
    location: { lat: 36.7853, lng: 3.0588 },
    openingHoursRaw: 'Mo-Su 08:00-18:00',
    avgVisitDurationMinutes: 45,
    checkpointRadiusMeters: 40,
  },
  {
    id: '00000000-0000-4000-c000-000000000008',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.historical_monument,
    nameFr: 'Palais des Raïs',
    nameAr: 'قصر الرياس',
    nameEn: 'Bastion 23',
    location: { lat: 36.7870, lng: 3.0560 },
    openingHoursRaw: 'Mo-Su 09:00-16:30',
    avgVisitDurationMinutes: 25,
    checkpointRadiusMeters: 30,
  },
  {
    id: '00000000-0000-4000-c000-000000000009',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.religious_site,
    nameFr: 'Mosquée Ketchaoua',
    nameAr: 'مسجد كتشاوة',
    nameEn: 'Ketchaoua Mosque',
    location: { lat: 36.7862, lng: 3.0607 },
    openingHoursRaw: 'Mo-Su 08:00-20:00',
    avgVisitDurationMinutes: 20,
    checkpointRadiusMeters: 30,
  },
  {
    id: '00000000-0000-4000-c000-000000000010',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.historical_monument,
    nameFr: 'Place des Martyrs',
    nameAr: 'ساحة الشهداء',
    nameEn: 'Place des Martyrs',
    location: { lat: 36.7846, lng: 3.0603 },
    openingHoursRaw: null,
    avgVisitDurationMinutes: 15,
    checkpointRadiusMeters: 35,
  },

  // ── Hamma / El Madania cluster ─────────────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000002',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.historical_monument,
    nameFr: 'Maqam Echahid',
    nameAr: 'مقام الشهيد',
    nameEn: 'Martyrs\' Memorial',
    location: { lat: 36.7470, lng: 3.0710 },
    openingHoursRaw: 'Mo-Su 09:00-17:00',
    avgVisitDurationMinutes: 30,
    checkpointRadiusMeters: 50,
  },
  {
    id: '00000000-0000-4000-c000-000000000003',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.park_garden,
    nameFr: 'Jardin d\'Essai du Hamma',
    nameAr: 'حديقة التجارب',
    nameEn: 'Jardin d\'Essai du Hamma',
    location: { lat: 36.7475, lng: 3.0760 },
    openingHoursRaw: 'Mo-Su 09:00-17:00',
    avgVisitDurationMinutes: 40,
    checkpointRadiusMeters: 35,
  },
  {
    id: '00000000-0000-4000-c000-000000000006',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.museum,
    nameFr: 'Musée National des Beaux-Arts',
    nameAr: 'المتحف الوطني للفنون الجميلة',
    nameEn: 'National Museum of Fine Arts',
    location: { lat: 36.7485, lng: 3.0715 },
    openingHoursRaw: 'Tu-Su 10:00-17:00',
    avgVisitDurationMinutes: 30,
    checkpointRadiusMeters: 25,
  },

  // ── Mohammadia / Grande Mosquée ────────────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000004',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.religious_site,
    nameFr: 'Grande Mosquée d\'Alger',
    nameAr: 'جامع الجزائر الأعظم',
    nameEn: 'Great Mosque of Algiers (Djamaa el Djazaïr)',
    location: { lat: 36.7605, lng: 3.0830 },
    openingHoursRaw: 'Mo-Su 08:00-20:00',
    avgVisitDurationMinutes: 30,
    checkpointRadiusMeters: 60,
  },

  // ── Bab El Oued / Bardo ────────────────────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000005',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.museum,
    nameFr: 'Musée National du Bardo',
    nameAr: 'المتحف الوطني للباردو',
    nameEn: 'Bardo National Museum',
    location: { lat: 36.7660, lng: 3.0510 },
    openingHoursRaw: 'Tu-Su 10:00-17:00',
    avgVisitDurationMinutes: 35,
    checkpointRadiusMeters: 25,
  },

  // ── Bouzaréah / Notre-Dame d'Afrique ───────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000007',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.viewpoint,
    nameFr: 'Notre-Dame d\'Afrique',
    nameAr: 'سيدة أفريقيا',
    nameEn: 'Notre Dame d\'Afrique',
    location: { lat: 36.7890, lng: 3.0420 },
    openingHoursRaw: 'Mo-Su 08:00-18:00',
    avgVisitDurationMinutes: 25,
    checkpointRadiusMeters: 30,
  },

  // ── Additional POIs (Phase 2 expansion) ────────────────────────────
  {
    id: '00000000-0000-4000-c000-000000000011',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.historical_monument,
    nameFr: 'Monument aux Morts',
    nameAr: 'نصب الأموات',
    nameEn: 'Monument of the Dead (Pavois)',
    location: { lat: 36.7590, lng: 3.0505 },
    openingHoursRaw: null,
    avgVisitDurationMinutes: 10,
    checkpointRadiusMeters: 25,
  },
  {
    id: '00000000-0000-4000-c000-000000000012',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.museum,
    nameFr: 'Musée d\'Art Moderne d\'Alger (MAMA)',
    nameAr: 'متحف الفن الحديث والمعاصر',
    nameEn: 'Museum of Modern Art (MAMA)',
    location: { lat: 36.7738, lng: 3.0590 },
    openingHoursRaw: 'Tu-Su 10:00-18:00',
    avgVisitDurationMinutes: 30,
    checkpointRadiusMeters: 25,
  },
  {
    id: '00000000-0000-4000-c000-000000000013',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.park_garden,
    nameFr: 'Parc de la Liberté',
    nameAr: 'حديقة الحرية',
    nameEn: 'Parc de la Liberté',
    location: { lat: 36.7560, lng: 3.0540 },
    openingHoursRaw: 'Mo-Su 07:00-19:00',
    avgVisitDurationMinutes: 20,
    checkpointRadiusMeters: 30,
  },
  {
    id: '00000000-0000-4000-c000-000000000014',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.religious_site,
    nameFr: 'Grande Mosquée d\'Alger (Ancienne)',
    nameAr: 'الجامع الكبير',
    nameEn: 'Great Mosque of Algiers (Historic, Djamaa el Kebir)',
    location: { lat: 36.7842, lng: 3.0621 },
    openingHoursRaw: 'Mo-Su 06:00-21:00',
    avgVisitDurationMinutes: 20,
    checkpointRadiusMeters: 25,
  },
  {
    id: '00000000-0000-4000-c000-000000000015',
    cityId: ALGIERS_CITY_ID,
    categoryId: CATEGORY_IDS.viewpoint,
    nameFr: 'Balcon Saint-Raphaël',
    nameAr: 'شرفة سان رفائيل',
    nameEn: 'Balcon Saint-Raphaël Viewpoint',
    location: { lat: 36.7750, lng: 3.0480 },
    openingHoursRaw: null,
    avgVisitDurationMinutes: 15,
    checkpointRadiusMeters: 20,
  },
];

/**
 * Theme → category mapping. POI Selector uses this to decide which
 * categories are eligible for a given theme string. Shared across all
 * cities — the mapping is theme logic, not city-specific.
 */
export const THEME_CATEGORY_MAP: Record<string, string[]> = {
  heritage: [
    CATEGORY_IDS.historical_monument,
    CATEGORY_IDS.museum,
    CATEGORY_IDS.religious_site,
  ],
  nature: [CATEGORY_IDS.park_garden, CATEGORY_IDS.viewpoint, CATEGORY_IDS.beach],
  culture: [CATEGORY_IDS.museum, CATEGORY_IDS.cultural_venue],
  all: Object.values(CATEGORY_IDS),
};

// Keep the old export name for backward compatibility with existing tests.
export const FIXTURE_POIS = ALGIERS_POIS;
