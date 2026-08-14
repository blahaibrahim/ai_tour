import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';
import fs from 'fs';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);
  
  try {
    console.log('Resetting schema...');
    await sql`DROP SCHEMA public CASCADE;`.execute(db);
    await sql`CREATE SCHEMA public;`.execute(db);
    
    console.log('Reading SQL file...');
    const query = fs.readFileSync('src/data/db/migrations/1700000000001_initial_schema.sql', 'utf8');
    
    console.log('Executing SQL file directly...');
    await sql.raw(query).execute(db);
    
    console.log('SQL executed successfully!');
  } catch (error) {
    console.error('Failed to execute SQL:', error);
  } finally {
    await db.destroy();
  }
}

main();
