import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);
  
  try {
    const res = await sql`
      SELECT tablename 
      FROM pg_tables 
      WHERE schemaname = 'public';
    `.execute(db);
    console.log('Tables:', res.rows.map((r: any) => r.tablename));
  } catch (error) {
    console.error('Failed:', error);
  } finally {
    await db.destroy();
  }
}

main();
