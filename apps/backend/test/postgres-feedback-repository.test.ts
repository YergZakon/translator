import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Pool } from 'pg';

import { defaultAppConfig } from '../src/domain/app-config.js';
import {
  FeedbackService,
  FeedbackServiceError
} from '../src/services/feedback-service.js';
import type { SecretBroker } from '../src/services/openai-secret-broker.js';
import { SessionService } from '../src/services/session-service.js';
import { runMigrations } from '../src/storage/migrations.js';
import { PostgresSessionRepository } from '../src/storage/postgres-session-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const owner = 'inst_0123456789abcdef0123456789abcdef';
const otherOwner = 'inst_fedcba9876543210fedcba9876543210';
const serverSecret = 'feedback-postgres-server-secret-32chars';
const request = {
  mode: 'one_way_ru_to_en' as const,
  sourceLocaleHint: 'ru-KZ',
  legs: [{ clientLegId: 'ru-to-en', targetLanguage: 'en' as const }],
  app: { version: '0.1.0', build: 42 },
  device: { osVersion: '26.4', modelClass: 'phone' as const }
};

test(
  'PostgreSQL atomically persists one redacted feedback record across instances',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query(
        'TRUNCATE TABLE translation_session_feedback, translation_quota_mint_events, translation_quota_daily_usage, translation_session_idempotency, translation_session_legs, translation_sessions RESTART IDENTITY'
      );

      let sequence = 0;
      let current = new Date('2026-07-15T07:00:00.000Z');
      const broker: SecretBroker = {
        async createTranslationSecret() {
          return {
            value: 'ek_feedback_pg_short_lived_secret',
            expiresAt: new Date(current.getTime() + 10 * 60 * 1000)
          };
        }
      };
      const repository = () => new PostgresSessionRepository(pool, serverSecret);
      const sessions = new SessionService({
        broker,
        repository: repository(),
        now: () => current,
        idFactory: (prefix) => `${prefix}_${String(++sequence).padStart(24, 'a')}`
      });
      const session = await sessions.create(request, {
        idempotencyKey: '8f5d6754-c57a-4a44-9f0d-02da2172c11f',
        safetyIdentifier: owner,
        traceId: 'tr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        config: structuredClone(defaultAppConfig)
      });

      const firstService = new FeedbackService(repository(), () => current);
      const first = await firstService.upsert(
        {
          rating: 2,
          categories: ['critical_entity', 'connection'],
          comment:
            'Email person@example.com, phone +7 777 123 45 67, token sk-proj-secret12345678',
          consentFlags: { storeComment: true }
        },
        { sessionId: session.sessionId, safetyIdentifier: owner }
      );
      assert.equal(first.updatedAt, current.toISOString());

      const stored = await pool.query<{
        count: number;
        rating: number;
        categories: string[];
        store_comment: boolean;
        comment_redacted: string | null;
      }>(
        `
          SELECT count(*) OVER ()::integer AS count,
                 rating,
                 categories,
                 store_comment,
                 comment_redacted
          FROM translation_session_feedback
          WHERE session_id = $1
        `,
        [session.sessionId]
      );
      assert.equal(stored.rows[0]?.count, 1);
      assert.equal(stored.rows[0]?.rating, 2);
      assert.deepEqual(stored.rows[0]?.categories, ['critical_entity', 'connection']);
      assert.equal(stored.rows[0]?.store_comment, true);
      assert.equal(stored.rows[0]?.comment_redacted?.includes('person@example.com'), false);
      assert.equal(stored.rows[0]?.comment_redacted?.includes('777 123'), false);
      assert.equal(stored.rows[0]?.comment_redacted?.includes('sk-proj-secret'), false);

      current = new Date('2026-07-15T07:00:01.000Z');
      const twoWriters = [
        new FeedbackService(repository(), () => current).upsert(
          {
            rating: 4,
            categories: ['audio_quality'],
            comment: 'must not persist',
            consentFlags: { storeComment: false }
          },
          { sessionId: session.sessionId, safetyIdentifier: owner }
        ),
        new FeedbackService(repository(), () => current).upsert(
          {
            rating: 5,
            categories: ['other'],
            comment: null,
            consentFlags: { storeComment: true }
          },
          { sessionId: session.sessionId, safetyIdentifier: owner }
        )
      ];
      const updates = await Promise.all(twoWriters);
      assert.ok(updates.every((response) => response.sessionId === session.sessionId));

      const afterUpdate = await pool.query<{
        count: number;
        rating: number;
        store_comment: boolean;
        comment_redacted: string | null;
      }>(
        `
          SELECT count(*) OVER ()::integer AS count,
                 rating,
                 store_comment,
                 comment_redacted
          FROM translation_session_feedback
          WHERE session_id = $1
        `,
        [session.sessionId]
      );
      assert.equal(afterUpdate.rows[0]?.count, 1);
      assert.ok(afterUpdate.rows[0]?.rating === 4 || afterUpdate.rows[0]?.rating === 5);
      assert.equal(afterUpdate.rows[0]?.comment_redacted, null);

      await assert.rejects(
        new FeedbackService(repository(), () => current).upsert(
          {
            rating: 1,
            categories: ['other'],
            consentFlags: { storeComment: false }
          },
          { sessionId: session.sessionId, safetyIdentifier: otherOwner }
        ),
        (error: unknown) =>
          error instanceof FeedbackServiceError && error.code === 'RESOURCE_NOT_FOUND'
      );

      await sessions.complete(
        {
          result: 'completed',
          durationSeconds: 60,
          activeAudioSeconds: 45,
          turns: 3,
          reconnects: 0,
          finalRouteType: 'bluetooth',
          errorCode: null
        },
        { sessionId: session.sessionId, safetyIdentifier: owner }
      );
      current = new Date('2026-07-15T08:00:00.000Z');
      await sessions.create(request, {
        idempotencyKey: '1cc047eb-d17e-40e8-864d-989fd9090a2d',
        safetyIdentifier: owner,
        traceId: 'tr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        config: structuredClone(defaultAppConfig)
      });
      const retained = await pool.query<{ count: number }>(
        'SELECT count(*)::integer AS count FROM translation_session_feedback WHERE session_id = $1',
        [session.sessionId]
      );
      assert.equal(retained.rows[0]?.count, 1);
    } finally {
      await pool.end();
    }
  }
);
