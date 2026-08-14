import type { CityConfig } from '../../domain/models/city-config.model.js';
import type { Poi } from '../../domain/models/poi.model.js';

export {
  ALGIERS_REGION_ID,
  ALGIERS_CITY_ID,
  ALGIERS_CITY_CONFIG,
  ALGIERS_POIS,
  FIXTURE_POIS,
  CATEGORY_IDS,
  THEME_CATEGORY_MAP,
} from './algiers-pois.fixture.js';

export {
  ORAN_REGION_ID,
  ORAN_CITY_ID,
  ORAN_CITY_CONFIG,
  ORAN_POIS,
} from './oran-pois.fixture.js';

export {
  CONSTANTINE_REGION_ID,
  CONSTANTINE_CITY_ID,
  CONSTANTINE_CITY_CONFIG,
  CONSTANTINE_POIS,
} from './constantine-pois.fixture.js';

// ---------------------------------------------------------------------------
// Aggregated data — used by the composition root and driver script to
// load all cities and POIs in one shot.
// ---------------------------------------------------------------------------

import { ALGIERS_REGION_ID, ALGIERS_CITY_CONFIG, ALGIERS_POIS } from './algiers-pois.fixture.js';
import { ORAN_REGION_ID, ORAN_CITY_CONFIG, ORAN_POIS } from './oran-pois.fixture.js';
import { CONSTANTINE_REGION_ID, CONSTANTINE_CITY_CONFIG, CONSTANTINE_POIS } from './constantine-pois.fixture.js';

export const ALL_CITY_CONFIGS: CityConfig[] = [
  ALGIERS_CITY_CONFIG,
  ORAN_CITY_CONFIG,
  CONSTANTINE_CITY_CONFIG,
];

export const ALL_FIXTURE_POIS: Poi[] = [
  ...ALGIERS_POIS,
  ...ORAN_POIS,
  ...CONSTANTINE_POIS,
];
