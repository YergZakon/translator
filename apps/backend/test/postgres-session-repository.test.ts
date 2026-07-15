import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Pool } from 'pg';

import { defaultAppConfig } from '../src/domain/app-config.js';
import type {
  CreateTranslationSecretInput,
  SecretBroker,
  TranslationSecret
} from '../src/services/openai-secret-broker.js';
import { SessionService, SessionServiceError } from '../src/services/session-service.js';
import { runMigrations } from '../src/storage/migrations.js';
import { PostgresSessionRepository } from '../src/storage/postgres-session-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const now = new Date('2026-07-15T04:30:00.000Z');
const owner = 'inst_0123456789abcdef0123456789abcdef';
const otherOwner = 'inst_fedcba9876543210fedcba9876543210';
const createKey = '8f5d6754-c57a-4a44-9f0d-02da2172c11f';
const recreateKey = '6fd2aca3-1be3-462f-98ee-a297b3e4d7af';
const encryptionSecret = 'test-session-encryption-root-secret-32chars';
const request = {
  mode: 'one_way_ru_to_en' as const,
  sourceLocaleHint: 'ru-KZ',
  legs: [{ clientLegId: 'ru-to-en', targetLanguage: 'en' as const }],
  app: { version: '0.1.0', build: 42 },
  device: { osVersion: '26.4', modelClass: 'phone' as const }
};

class RecordingBroker implements SecretBroker {
  readonly calls: CreateTranslationSecretInput[] = [];
  failNext = false;

  async createTranslationSecret(input: CreateTranslationSecretInput): Promise<TranslationSecret> {
    this.calls.push(input);
    if (this.failNext) {
      this.failNext = false;
      throw new Error('synthetic broker failure');
    }
    return {
      value: `ek_pg_${String(this.calls.length).padStart(2, '0')}_short_lived_secret`,
      expiresAt: new Date(now.getTime() + 10 * 60 * 1000)
    };
  }
}

test(
  'PostgreSQL persists session ownership and encrypted idempotency across instances',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query(
        'TRUNCATE TABLE translation_session_idempotency, translation_session_legs, translation_sessions'
      );

      const broker = new RecordingBroker();
      let sequence = 0;
      const service = () =>
        new SessionService({
          broker,
          repository: new PostgresSessionRepository(pool, encryptionSecret),
          now: () => now,
          idFactory: (prefix) => `${prefix}_${String(++sequence).padStart(24, 'a')}`
        });
      const context = {
        idempotencyKey: createKey,
        safetyIdentifier: owner,
        traceId: 'tr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        config: structuredClone(defaultAppConfig)
      };

      const firstService = service();
      const restartedService = service();
      const [first, concurrentReplay] = await Promise.all([
        firstService.create(request, context),
        restartedService.create(request, context)
      ]);

      assert.deepEqual(concurrentReplay, first);
      assert.equal(broker.calls.length, 1);
      assert.equal(
        (await pool.query('SELECT count(*)::integer AS count FROM translation_sessions')).rows[0]
          ?.count,
        1
      );
      assert.equal(
        (await pool.query('SELECT count(*)::integer AS count FROM translation_session_legs')).rows[0]
          ?.count,
        1
      );

      const replayAfterRestart = await service().create(request, context);
      assert.deepEqual(replayAfterRestart, first);
      assert.equal(broker.calls.length, 1);

      await assert.rejects(
        service().create(
          { ...request, sourceLocaleHint: 'ru-RU' },
          context
        ),
        (error: unknown) =>
          error instanceof SessionServiceError && error.code === 'IDEMPOTENCY_CONFLICT'
      );
      assert.equal(broker.calls.length, 1);

      const originalLeg = first.legs[0]!;
      const recreateContext = {
        sessionId: first.sessionId,
        idempotencyKey: recreateKey,
        safetyIdentifier: owner
      };
      const recreateRequest = {
        clientLegId: 'ru-to-en',
        reason: 'disconnected_timeout' as const
      };
      const [replacement, concurrentReplacementReplay] = await Promise.all([
        service().recreateLeg(recreateRequest, recreateContext),
        service().recreateLeg(recreateRequest, recreateContext)
      ]);

      assert.deepEqual(concurrentReplacementReplay, replacement);
      assert.notEqual(replacement.legId, originalLeg.legId);
      assert.equal(replacement.targetLanguage, originalLeg.targetLanguage);
      assert.equal(broker.calls.length, 2);
      assert.deepEqual(await service().recreateLeg(recreateRequest, recreateContext), replacement);
      assert.equal(broker.calls.length, 2);

      await assert.rejects(
        service().recreateLeg(recreateRequest, {
          ...recreateContext,
          safetyIdentifier: otherOwner
        }),
        (error: unknown) =>
          error instanceof SessionServiceError && error.code === 'RESOURCE_NOT_FOUND'
      );
      assert.equal(broker.calls.length, 2);

      broker.failNext = true;
      const retryableContext = {
        ...recreateContext,
        idempotencyKey: '725df706-ed3b-4ec8-bae1-cf82df302a71'
      };
      await assert.rejects(service().recreateLeg(recreateRequest, retryableContext));
      const afterFailure = await service().recreateLeg(recreateRequest, retryableContext);
      assert.match(afterFailure.clientSecret, /^ek_pg_04_/);
      assert.equal(broker.calls.length, 4);

      const encryptedRows = await pool.query<{
        iv_bytes: number;
        tag_bytes: number;
        secret_position: number;
      }>(
        `
          SELECT
            octet_length(response_iv) AS iv_bytes,
            octet_length(response_auth_tag) AS tag_bytes,
            position(convert_to($1, 'UTF8') in response_ciphertext) AS secret_position
          FROM translation_session_idempotency
        `,
        [first.legs[0]!.clientSecret]
      );
      assert.ok(encryptedRows.rows.length >= 3);
      assert.ok(
        encryptedRows.rows.every(
          (row) => row.iv_bytes === 12 && row.tag_bytes === 16 && row.secret_position === 0
        )
      );

      const secretColumns = await pool.query<{ count: number }>(
        `
          SELECT count(*)::integer AS count
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name IN (
              'translation_sessions',
              'translation_session_legs',
              'translation_session_idempotency'
            )
            AND column_name LIKE '%secret%'
        `
      );
      assert.equal(secretColumns.rows[0]?.count, 0);
    } finally {
      await pool.end();
    }
  }
);
