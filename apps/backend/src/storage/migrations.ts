import { readFile } from 'node:fs/promises';

import type { Pool } from 'pg';

const migrations = [
  {
    version: 1,
    name: 'installations',
    url: new URL('../../migrations/001_installations.sql', import.meta.url)
  },
  {
    version: 2,
    name: 'translation_sessions',
    url: new URL('../../migrations/002_translation_sessions.sql', import.meta.url)
  },
  {
    version: 3,
    name: 'translation_quotas',
    url: new URL('../../migrations/003_translation_quotas.sql', import.meta.url)
  },
  {
    version: 4,
    name: 'session_completion',
    url: new URL('../../migrations/004_session_completion.sql', import.meta.url)
  },
  {
    version: 5,
    name: 'session_feedback',
    url: new URL('../../migrations/005_session_feedback.sql', import.meta.url)
  },
  {
    version: 6,
    name: 'technical_telemetry',
    url: new URL('../../migrations/006_technical_telemetry.sql', import.meta.url)
  }
] as const;

export async function runMigrations(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT pg_advisory_xact_lock(hashtext('translator-schema-migrations'))");
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version integer PRIMARY KEY,
        name text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);

    for (const migration of migrations) {
      const existing = await client.query<{ exists: boolean }>(
        'SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1) AS exists',
        [migration.version]
      );
      if (existing.rows[0]?.exists === true) {
        continue;
      }

      const sql = await readFile(migration.url, 'utf8');
      await client.query(sql);
      await client.query(
        'INSERT INTO schema_migrations (version, name) VALUES ($1, $2)',
        [migration.version, migration.name]
      );
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
