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
        'TRUNCATE TABLE translation_session_feedback, translation_quota_mint_events, translation_quota_daily_usage, translation_session_idempotency, translation_session_legs, translation_sessions RESTART IDENTITY'
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

test(
  'PostgreSQL atomically enforces parallel, rate, and daily quota before broker mint',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query(
        'TRUNCATE TABLE translation_session_feedback, translation_quota_mint_events, translation_quota_daily_usage, translation_session_idempotency, translation_session_legs, translation_sessions RESTART IDENTITY'
      );

      let sequence = 0;
      let current = new Date('2026-07-15T05:00:00.000Z');
      const broker = new (class implements SecretBroker {
        readonly calls: CreateTranslationSecretInput[] = [];
        failNext = false;

        async createTranslationSecret(
          input: CreateTranslationSecretInput
        ): Promise<TranslationSecret> {
          this.calls.push(input);
          if (this.failNext) {
            this.failNext = false;
            throw new Error('synthetic broker failure');
          }
          return {
            value: `ek_quota_pg_${String(this.calls.length).padStart(2, '0')}_short_lived_secret`,
            expiresAt: new Date(current.getTime() + 10 * 60 * 1000)
          };
        }
      })();
      const service = (safetyIdentifier: string, policy: {
        maxParallelLegs: number;
        maxSecretMintsPerWindow: number;
        secretMintWindowMs: number;
        maxDailyLegMinutes: number;
      }) =>
        new SessionService({
          broker,
          repository: new PostgresSessionRepository(pool, encryptionSecret),
          now: () => current,
          quotaPolicy: policy,
          idFactory: (prefix) => `${prefix}_${String(++sequence).padStart(24, 'q')}`
        });
      const context = (safetyIdentifier: string, key: string) => ({
        idempotencyKey: key,
        safetyIdentifier,
        traceId: 'tr_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
        config: structuredClone(defaultAppConfig)
      });
      const parallelOwner = 'inst_11111111111111111111111111111111';
      const parallelPolicy = {
        maxParallelLegs: 1,
        maxSecretMintsPerWindow: 10,
        secretMintWindowMs: 60_000,
        maxDailyLegMinutes: 120
      };
      const firstKey = '11111111-1111-4111-8111-111111111111';
      const secondKey = '22222222-2222-4222-8222-222222222222';
      const concurrent = await Promise.allSettled([
        service(parallelOwner, parallelPolicy).create(request, context(parallelOwner, firstKey)),
        service(parallelOwner, parallelPolicy).create(request, context(parallelOwner, secondKey))
      ]);
      assert.equal(concurrent.filter((result) => result.status === 'fulfilled').length, 1);
      const parallelFailure = concurrent.find((result) => result.status === 'rejected');
      assert.ok(parallelFailure?.status === 'rejected');
      assert.ok(parallelFailure.reason instanceof SessionServiceError);
      assert.equal(parallelFailure.reason.code, 'RATE_LIMITED');
      assert.equal(parallelFailure.reason.retryAfterMs, 1_800_000);
      assert.equal(broker.calls.length, 1);

      const acceptedKey = concurrent[0]?.status === 'fulfilled' ? firstKey : secondKey;
      const accepted = concurrent.find((result) => result.status === 'fulfilled');
      assert.ok(accepted?.status === 'fulfilled');
      assert.deepEqual(
        await service(parallelOwner, parallelPolicy).create(
          request,
          context(parallelOwner, acceptedKey)
        ),
        accepted.value
      );
      assert.equal(broker.calls.length, 1);

      const rateOwner = 'inst_22222222222222222222222222222222';
      const ratePolicy = {
        maxParallelLegs: 2,
        maxSecretMintsPerWindow: 1,
        secretMintWindowMs: 60_000,
        maxDailyLegMinutes: 120
      };
      const rateSession = await service(rateOwner, ratePolicy).create(
        request,
        context(rateOwner, '33333333-3333-4333-8333-333333333333')
      );
      await assert.rejects(
        service(rateOwner, ratePolicy).recreateLeg(
          { clientLegId: 'ru-to-en', reason: 'connection_failed' },
          {
            sessionId: rateSession.sessionId,
            idempotencyKey: '44444444-4444-4444-8444-444444444444',
            safetyIdentifier: rateOwner
          }
        ),
        (error: unknown) =>
          error instanceof SessionServiceError &&
          error.code === 'RATE_LIMITED' &&
          error.retryAfterMs === 60_000
      );

      const dailyOwner = 'inst_33333333333333333333333333333333';
      const dailyPolicy = {
        maxParallelLegs: 2,
        maxSecretMintsPerWindow: 10,
        secretMintWindowMs: 60_000,
        maxDailyLegMinutes: 30
      };
      await service(dailyOwner, dailyPolicy).create(
        request,
        context(dailyOwner, '55555555-5555-4555-8555-555555555555')
      );
      current = new Date('2026-07-15T05:30:01.000Z');
      await assert.rejects(
        service(dailyOwner, dailyPolicy).create(
          request,
          context(dailyOwner, '66666666-6666-4666-8666-666666666666')
        ),
        (error: unknown) =>
          error instanceof SessionServiceError &&
          error.code === 'RATE_LIMITED' &&
          error.retryAfterMs === 3_600_000
      );

      const rollbackOwner = 'inst_44444444444444444444444444444444';
      const rollbackPolicy = {
        maxParallelLegs: 1,
        maxSecretMintsPerWindow: 1,
        secretMintWindowMs: 60_000,
        maxDailyLegMinutes: 30
      };
      broker.failNext = true;
      const rollbackContext = context(
        rollbackOwner,
        '77777777-7777-4777-8777-777777777777'
      );
      await assert.rejects(service(rollbackOwner, rollbackPolicy).create(request, rollbackContext));
      await service(rollbackOwner, rollbackPolicy).create(request, rollbackContext);

      const usage = await pool.query<{
        daily_rows: number;
        mint_total: number;
      }>(
        `
          SELECT
            (SELECT count(*)::integer FROM translation_quota_daily_usage
              WHERE owner_safety_identifier = $1) AS daily_rows,
            (SELECT coalesce(sum(secret_mints), 0)::integer FROM translation_quota_mint_events
              WHERE owner_safety_identifier = $1) AS mint_total
        `,
        [rollbackOwner]
      );
      assert.deepEqual(usage.rows[0], { daily_rows: 1, mint_total: 1 });
    } finally {
      await pool.end();
    }
  }
);

test(
  'PostgreSQL persists first session completion and releases its active-leg slot',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query(
        'TRUNCATE TABLE translation_session_feedback, translation_quota_mint_events, translation_quota_daily_usage, translation_session_idempotency, translation_session_legs, translation_sessions RESTART IDENTITY'
      );

      const broker = new RecordingBroker();
      let sequence = 0;
      const policy = {
        maxParallelLegs: 1,
        maxSecretMintsPerWindow: 10,
        secretMintWindowMs: 60_000,
        maxDailyLegMinutes: 120
      };
      const service = () =>
        new SessionService({
          broker,
          repository: new PostgresSessionRepository(pool, encryptionSecret),
          now: () => now,
          quotaPolicy: policy,
          idFactory: (prefix) => `${prefix}_${String(++sequence).padStart(24, 'c')}`
        });
      const createContext = (key: string) => ({
        idempotencyKey: key,
        safetyIdentifier: owner,
        traceId: 'tr_cccccccccccccccccccccccccccccccc',
        config: structuredClone(defaultAppConfig)
      });
      const session = await service().create(request, createContext(createKey));
      await service().recreateLeg(
        { clientLegId: 'ru-to-en', reason: 'manual_retry' },
        {
          sessionId: session.sessionId,
          idempotencyKey: recreateKey,
          safetyIdentifier: owner
        }
      );
      const completionContext = { sessionId: session.sessionId, safetyIdentifier: owner };
      const completionA = {
        result: 'user_stopped' as const,
        durationSeconds: 45,
        activeAudioSeconds: 21,
        turns: 4,
        reconnects: 1,
        finalRouteType: 'bluetooth' as const,
        errorCode: null
      };
      const completionB = {
        ...completionA,
        result: 'failed' as const,
        errorCode: 'NETWORK'
      };

      const [first, concurrent] = await Promise.all([
        service().complete(completionA, completionContext),
        service().complete(completionB, completionContext)
      ]);
      assert.deepEqual(concurrent, first);
      assert.deepEqual(await service().complete(completionB, completionContext), first);

      await assert.rejects(
        service().complete(completionA, { ...completionContext, safetyIdentifier: otherOwner }),
        (error: unknown) =>
          error instanceof SessionServiceError && error.code === 'RESOURCE_NOT_FOUND'
      );
      await assert.rejects(
        service().recreateLeg(
          { clientLegId: 'ru-to-en', reason: 'manual_retry' },
          {
            sessionId: session.sessionId,
            idempotencyKey: recreateKey,
            safetyIdentifier: owner
          }
        ),
        (error: unknown) =>
          error instanceof SessionServiceError && error.code === 'RESOURCE_NOT_FOUND'
      );
      assert.equal(broker.calls.length, 2);

      const next = await service().create(
        request,
        createContext('99999999-9999-4999-8999-999999999999')
      );
      assert.notEqual(next.sessionId, session.sessionId);
      assert.equal(broker.calls.length, 3);

      const stored = await pool.query<{
        completed_at: Date;
        completion_result: string;
        duration_seconds: number;
        active_audio_seconds: number;
        turns: number;
        reconnects: number;
        final_route_type: string;
        completion_error_code: string | null;
      }>(
        `
          SELECT completed_at, completion_result, duration_seconds, active_audio_seconds,
                 turns, reconnects, final_route_type, completion_error_code
          FROM translation_sessions
          WHERE session_id = $1
        `,
        [session.sessionId]
      );
      const row = stored.rows[0]!;
      assert.equal(row.completed_at.toISOString(), first.completedAt);
      assert.ok(row.completion_result === 'user_stopped' || row.completion_result === 'failed');
      assert.equal(row.duration_seconds, 45);
      assert.equal(row.active_audio_seconds, 21);
      assert.equal(row.turns, 4);
      assert.equal(row.reconnects, 1);
      assert.equal(row.final_route_type, 'bluetooth');
      assert.ok(row.completion_error_code === null || row.completion_error_code === 'NETWORK');
    } finally {
      await pool.end();
    }
  }
);
