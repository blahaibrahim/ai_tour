import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';
import { ALL_CITY_CONFIGS, ALL_FIXTURE_POIS, CATEGORY_IDS, ALGIERS_REGION_ID, ORAN_REGION_ID, CONSTANTINE_REGION_ID } from '../src/data/fixtures/index.js';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);

  console.log('Connecting to database:', env.DATABASE_URL);

  try {
    console.log('Cleaning existing data...');
    // Delete in correct order to respect FK constraints
    await db.deleteFrom('route_stops').execute();
    await db.deleteFrom('routes').execute();
    await db.deleteFrom('pois').execute();
    await db.deleteFrom('categories').execute();
    await db.deleteFrom('cities').execute();
    await db.deleteFrom('regions').execute();

    console.log('Seeding regions...');
    await db.insertInto('regions').values([
      { id: ALGIERS_REGION_ID, name: 'Algiers Region' },
      { id: ORAN_REGION_ID, name: 'Oran Region' },
      { id: CONSTANTINE_REGION_ID, name: 'Constantine Region' },
    ]).execute();

    console.log(`Seeding ${ALL_CITY_CONFIGS.length} cities...`);
    for (const city of ALL_CITY_CONFIGS) {
      let regionId = ALGIERS_REGION_ID;
      if (city.name === 'Oran') regionId = ORAN_REGION_ID;
      if (city.name === 'Constantine') regionId = CONSTANTINE_REGION_ID;

      await db.insertInto('cities').values({
        id: city.id,
        region_id: regionId,
        name: city.name,
        name_ar: city.nameAr,
        name_fr: city.nameFr,
        cluster_radius_meters: city.clusterRadiusMeters,
        active_routing_provider: city.activeRoutingProvider as any,
        rollout_status: city.rolloutStatus,
        feature_flags: JSON.stringify(city.featureFlags),
      }).execute();
    }

    console.log(`Seeding categories...`);
    const categoryValues = Object.entries(CATEGORY_IDS).map(([key, id]) => ({
      id,
      key,
      label_fr: key,
      label_ar: key,
      label_en: key,
    }));
    await db.insertInto('categories').values(categoryValues).execute();

    console.log(`Seeding ${ALL_FIXTURE_POIS.length} POIs...`);
    for (const poi of ALL_FIXTURE_POIS) {
      await db.insertInto('pois').values({
        id: poi.id,
        city_id: poi.cityId,
        category_id: poi.categoryId,
        name_fr: poi.nameFr,
        name_ar: poi.nameAr,
        name_en: poi.nameEn,
        location: sql`ST_MakePoint(${poi.location.lng}, ${poi.location.lat})`,
        opening_hours_raw: poi.openingHoursRaw,
        avg_visit_duration_minutes: poi.avgVisitDurationMinutes,
        checkpoint_radius_meters: poi.checkpointRadiusMeters,
        status: 'published',
      }).execute();
    }

    console.log('Seed completed successfully! ✅');

  } catch (error) {
    console.error('Seed failed:', error);
    process.exit(1);
  } finally {
    await db.destroy();
  }
}

main();
