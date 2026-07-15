import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Pool } from 'pg';

import {
  fingerprintTelemetryEvent,
  type TelemetryEvent
} from '../src/services/telemetry-service.js';
import { runMigrations } from '../src/storage/migrations.js';
import { PostgresTelemetryRepository } from '../src/storage/postgres-telemetry-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const owner = 'inst_0123456789abcdef0123456789abcdef';
const otherOwner = 'inst_fedcba9876543210fedcba9876543210';
const ownerSession = 'ts_0123456789abcdefghijklmn';
const ownerLeg = 'leg_0123456789abcdefghijklmn';
const foreignSession = 'ts_zyxwvutsrqponmlkjihgfedc';
const foreignLeg = 'leg_zyxwvutsrqponmlkjihgfedc';
const sentAt = new Date('2026-07-15T10:00:00.000Z');
const receivedAt = new Date('2026-07-15T10:00:01.000Z');

function persistable(event: TelemetryEvent) {
  return { ...event, payloadFingerprint: fingerprintTelemetryEvent(event) };
}

test(
  'PostgreSQL telemetry ingestion is owner-scoped, durable and replay-safe',
  { skip: databaseUrl === undefined ? 'TEST_DATABASE_URL is not configured' : false },
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await runMigrations(pool);
      await pool.query(
        'TRUNCATE TABLE technical_telemetry_events, translation_session_feedback, translation_quota_mint_events, translation_quota_daily_usage, translation_session_idempotency, translation_session_legs, translation_sessions RESTART IDENTITY'
      );
      await pool.query(
        `
          INSERT INTO translation_sessions (
            session_id, owner_safety_identifier, model, active_until, created_at
          ) VALUES
            ($1, $2, 'gpt-realtime', $3, $4),
            ($5, $6, 'gpt-realtime', $3, $4)
        `,
        [
          ownerSession,
          owner,
          new Date('2026-07-15T11:00:00.000Z'),
          new Date('2026-07-15T09:00:00.000Z'),
          foreignSession,
          otherOwner
        ]
      );
      await pool.query(
        `
          INSERT INTO translation_session_legs (
            session_id, client_leg_id, leg_id, target_language, updated_at
          ) VALUES
            ($1, 'owner-leg', $2, 'en', $5),
            ($3, 'foreign-leg', $4, 'en', $5)
        `,
        [ownerSession, ownerLeg, foreignSession, foreignLeg, receivedAt]
      );

      const appOpened: TelemetryEvent = {
        eventId: '3f1b26b5-86ab-43a2-bf0c-82d83701ef77',
        sessionId: null,
        legId: null,
        type: 'app_opened',
        monotonicMs: 120,
        properties: { app_version: '0.1.0', build: 42, os_major: 26 }
      };
      const connected: TelemetryEvent = {
        eventId: 'bc2cac9c-a488-4d02-8600-cf20c3890cb2',
        sessionId: ownerSession,
        legId: ownerLeg,
        type: 'webrtc_connected',
        monotonicMs: 900,
        properties: { setup_ms: 500, measurement_quality: 'exact' }
      };
      const foreign: TelemetryEvent = {
        ...connected,
        eventId: '7f0207bb-3a2d-4c73-95a3-4906f530f22a',
        sessionId: foreignSession,
        legId: foreignLeg
      };
      const unknownLeg: TelemetryEvent = {
        ...connected,
        eventId: '8c1fe2ad-424c-40a1-b899-f97636fe69ca',
        legId: 'leg_unknownunknownunknownunknown'
      };
      const events = [appOpened, connected, foreign, unknownLeg].map(persistable);

      const first = await new PostgresTelemetryRepository(pool).ingest({
        safetyIdentifier: owner,
        sentAt,
        receivedAt,
        events
      });
      assert.deepEqual(first, {
        accepted: 2,
        rejected: 2,
        rejectedEventIds: [foreign.eventId, unknownLeg.eventId]
      });

      const replay = await new PostgresTelemetryRepository(pool).ingest({
        safetyIdentifier: owner,
        sentAt,
        receivedAt,
        events: events.slice(0, 2)
      });
      assert.deepEqual(replay, { accepted: 2, rejected: 0, rejectedEventIds: [] });

      const conflicting = { ...appOpened, properties: { ...appOpened.properties, build: 43 } };
      const conflict = await new PostgresTelemetryRepository(pool).ingest({
        safetyIdentifier: owner,
        sentAt,
        receivedAt,
        events: [persistable(conflicting)]
      });
      assert.deepEqual(conflict, {
        accepted: 0,
        rejected: 1,
        rejectedEventIds: [appOpened.eventId]
      });

      const concurrentEvent: TelemetryEvent = {
        ...appOpened,
        eventId: 'bf8b0888-0be5-4d67-9b45-0fd8916c29a7',
        monotonicMs: 240
      };
      const concurrentInput = {
        safetyIdentifier: owner,
        sentAt,
        receivedAt,
        events: [persistable(concurrentEvent)]
      };
      const concurrent = await Promise.all([
        new PostgresTelemetryRepository(pool).ingest(concurrentInput),
        new PostgresTelemetryRepository(pool).ingest(concurrentInput)
      ]);
      assert.deepEqual(concurrent, [
        { accepted: 1, rejected: 0, rejectedEventIds: [] },
        { accepted: 1, rejected: 0, rejectedEventIds: [] }
      ]);

      const stored = await pool.query<{
        count: number;
        owners: string[];
        properties: Array<Record<string, unknown>>;
      }>(
        `
          SELECT
            count(*)::integer AS count,
            array_agg(DISTINCT owner_safety_identifier) AS owners,
            array_agg(properties ORDER BY event_id) AS properties
          FROM technical_telemetry_events
        `
      );
      assert.equal(stored.rows[0]!.count, 3);
      assert.deepEqual(stored.rows[0]!.owners, [owner]);
      assert.equal(JSON.stringify(stored.rows[0]!.properties).includes('transcript'), false);
    } finally {
      await pool.end();
    }
  }
);
