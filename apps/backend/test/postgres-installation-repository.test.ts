import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Pool } from 'pg';

import { RepositoryTokenVerifier } from '../src/security/token-verifier.js';
import { InstallationService } from '../src/services/installation-service.js';
import { runMigrations } from '../src/storage/migrations.js';
import { PostgresInstallationRepository } from '../src/storage/postgres-installation-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;

test(
  'PostgreSQL persists installation identity and token rotation across repository instances',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query('TRUNCATE TABLE installations');

      const publicId = '24e967eb-3b2b-4728-89b9-b7f8c07bc3ed';
      const tokens = [
        'app_persistent_first_token_1234567890',
        'app_persistent_second_token_123456789'
      ];
      const firstRepository = new PostgresInstallationRepository(pool);
      const firstService = new InstallationService({
        repository: firstRepository,
        installationIdFactory: () => 'ins_abcdefghijklmnopqrstuvwxyz',
        tokenFactory: () => tokens.shift()!
      });
      const request = {
        installationPublicId: publicId,
        appVersion: '0.1.0',
        appBuild: 42,
        osVersion: '18.5',
        modelClass: 'phone' as const
      };
      const first = await firstService.register(request);

      const restartedRepository = new PostgresInstallationRepository(pool);
      const verifier = new RepositoryTokenVerifier(
        restartedRepository,
        'test-safety-identifier-secret-32-characters'
      );
      const firstIdentity = await verifier.authenticateAuthorizationHeader(
        `Bearer ${first.appToken}`
      );
      assert.match(firstIdentity?.safetyIdentifier ?? '', /^inst_[0-9a-f]{32}$/);

      const restartedService = new InstallationService({
        repository: restartedRepository,
        installationIdFactory: () => 'ins_shouldnotreplaceexistingid123',
        tokenFactory: () => tokens.shift()!
      });
      const second = await restartedService.register({ ...request, appBuild: 43 });

      assert.equal(second.statusCode, 200);
      assert.equal(second.installationId, first.installationId);
      assert.equal(
        await verifier.authenticateAuthorizationHeader(`Bearer ${first.appToken}`),
        null
      );
      assert.deepEqual(
        await verifier.authenticateAuthorizationHeader(`Bearer ${second.appToken}`),
        firstIdentity
      );

      const stored = await pool.query<{ hash_bytes: number; equals_raw_token: boolean }>(
        `
          SELECT
            octet_length(token_hash) AS hash_bytes,
            token_hash = convert_to($2, 'UTF8') AS equals_raw_token
          FROM installations
          WHERE installation_public_id = $1
        `,
        [publicId, second.appToken]
      );
      assert.equal(stored.rowCount, 1);
      assert.equal(stored.rows[0]?.hash_bytes, 32);
      assert.equal(stored.rows[0]?.equals_raw_token, false);
    } finally {
      await pool.end();
    }
  }
);
