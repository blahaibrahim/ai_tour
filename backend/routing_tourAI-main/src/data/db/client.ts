import { Kysely, PostgresDialect } from 'kysely';
import pkg from 'pg';
import type { DB } from './types.js';

const { Pool } = pkg;

export function createDbClient(connectionString: string): Kysely<DB> {
  const dialect = new PostgresDialect({
    pool: new Pool({
      connectionString,
      max: 10,
    }),
  });

  return new Kysely<DB>({
    dialect,
  });
}
