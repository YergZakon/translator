import type { Pool, PoolClient } from 'pg';

import {
  type IngestTelemetryInput,
  type PersistableTelemetryEvent,
  type TelemetryBatchResponse,
  type TelemetryRepository
} from '../services/telemetry-service.js';

interface OwnedScopeRow {
  session_id: string;
  leg_id: string | null;
}

export class PostgresTelemetryRepository implements TelemetryRepository {
  readonly #pool: Pool;

  constructor(pool: Pool) {
    this.#pool = pool;
  }

  async ingest(input: IngestTelemetryInput): Promise<TelemetryBatchResponse> {
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      const scopes = await this.#loadOwnedScopes(client, input);
      const rejectedEventIds: string[] = [];
      let accepted = 0;

      for (const event of input.events) {
        if (!this.#ownsScope(scopes.sessions, scopes.legs, event)) {
          rejectedEventIds.push(event.eventId);
          continue;
        }

        const result = await client.query<{ event_id: string }>(
          `
            INSERT INTO technical_telemetry_events (
              owner_safety_identifier,
              event_id,
              session_id,
              leg_id,
              event_type,
              monotonic_ms,
              properties,
              payload_fingerprint,
              client_sent_at,
              received_at
            )
            VALUES ($1, $2::uuid, $3, $4, $5, $6, $7::jsonb, $8, $9, $10)
            ON CONFLICT (owner_safety_identifier, event_id) DO UPDATE
              SET event_id = EXCLUDED.event_id
              WHERE technical_telemetry_events.payload_fingerprint = EXCLUDED.payload_fingerprint
            RETURNING event_id::text
          `,
          [
            input.safetyIdentifier,
            event.eventId,
            event.sessionId ?? null,
            event.legId ?? null,
            event.type,
            event.monotonicMs,
            JSON.stringify(event.properties),
            event.payloadFingerprint,
            input.sentAt,
            input.receivedAt
          ]
        );

        if (result.rowCount === 1) {
          accepted += 1;
        } else {
          rejectedEventIds.push(event.eventId);
        }
      }

      await client.query('COMMIT');
      return {
        accepted,
        rejected: rejectedEventIds.length,
        rejectedEventIds
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async #loadOwnedScopes(
    client: PoolClient,
    input: IngestTelemetryInput
  ): Promise<{ sessions: Set<string>; legs: Set<string> }> {
    const sessionIds = [
      ...new Set(
        input.events
          .map((event) => event.sessionId)
          .filter((sessionId): sessionId is string => sessionId != null)
      )
    ];
    if (sessionIds.length === 0) {
      return { sessions: new Set(), legs: new Set() };
    }

    const result = await client.query<OwnedScopeRow>(
      `
        SELECT sessions.session_id, legs.leg_id
        FROM translation_sessions AS sessions
        LEFT JOIN translation_session_legs AS legs
          ON legs.session_id = sessions.session_id
        WHERE sessions.owner_safety_identifier = $1
          AND sessions.session_id = ANY($2::text[])
      `,
      [input.safetyIdentifier, sessionIds]
    );

    const sessions = new Set<string>();
    const legs = new Set<string>();
    for (const row of result.rows) {
      sessions.add(row.session_id);
      if (row.leg_id !== null) {
        legs.add(`${row.session_id}:${row.leg_id}`);
      }
    }
    return { sessions, legs };
  }

  #ownsScope(
    sessions: Set<string>,
    legs: Set<string>,
    event: PersistableTelemetryEvent
  ): boolean {
    if (event.sessionId == null) {
      return event.legId == null;
    }
    if (!sessions.has(event.sessionId)) {
      return false;
    }
    return event.legId == null || legs.has(`${event.sessionId}:${event.legId}`);
  }
}
