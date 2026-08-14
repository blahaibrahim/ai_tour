import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);
  
  try {
    console.log('Resetting public schema...');
    await sql`DROP SCHEMA public CASCADE;`.execute(db);
    await sql`CREATE SCHEMA public;`.execute(db);
    console.log('Schema reset successful.');
  } catch (error) {
    console.error('Failed:', error);
  } finally {
    await db.destroy();
  }
}

main();
