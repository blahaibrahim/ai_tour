import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);
  
  try {
    const res = await sql`
      SELECT schemaname, tablename 
      FROM pg_tables 
    `.execute(db);
    console.log('All Tables:');
    console.table(res.rows);
  } catch (error) {
    console.error('Failed:', error);
  } finally {
    await db.destroy();
  }
}

main();
