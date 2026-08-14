import { createDbClient } from '../src/data/db/client.js';
import { loadEnv } from '../src/config/env.js';
import { sql } from 'kysely';
import fs from 'fs';

async function main() {
  const env = loadEnv();
  const db = createDbClient(env.DATABASE_URL);
  
  try {
    console.log('Reading SQL file...');
    const query = fs.readFileSync('src/data/db/migrations/1700000000001_initial_schema.sql', 'utf8');
    
    // Split by semicolons for multiple execution
    const statements = query.split(';').filter(q => q.trim().length > 0);
    
    console.log(`Executing ${statements.length} SQL statements directly...`);
    for (let i = 0; i < statements.length; i++) {
        const stmt = statements[i].trim();
        // Skip purely comment statements or empty down migrations
        if (stmt.startsWith('-- Down') || stmt === '') continue;
        console.log(`Executing statement ${i + 1}...`);
        await sql.raw(stmt).execute(db);
    }
    
    console.log('SQL executed successfully!');
  } catch (error) {
    console.error('Failed to execute SQL:', error);
  } finally {
    await db.destroy();
  }
}

main();
