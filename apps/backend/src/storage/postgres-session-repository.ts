import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes
} from 'node:crypto';

import type { Pool, PoolClient } from 'pg';

import type {
  CompleteTranslationSessionResponse,
  TranslationLegCredentials,
  TranslationSession
} from '../services/session-service.js';
import type { QuotaReservation } from '../services/quota-service.js';
import {
  type CompleteSessionPersistenceInput,
  type CreateSessionPersistenceInput,
  type CreatedSessionPersistenceResult,
  type RecreateLegPersistenceInput,
  type SessionRepository,
  SessionRepositoryError,
  type StoredSession
} from '../services/session-repository.js';

type Operation = 'create_session' | 'recreate_leg';

interface IdempotencyRow {
  request_fingerprint: Buffer;
  response_iv: Buffer;
  response_auth_tag: Buffer;
  response_ciphertext: Buffer;
  expires_at: Date;
}

interface StoredSessionRow {
  owner_safety_identifier: string;
  active_until: Date;
  model: string;
  client_leg_id: string;
  leg_id: string;
  target_language: 'ru' | 'en';
}

interface CompletionRow {
  completed_at: Date | null;
}

interface EncryptedResponse {
  iv: Buffer;
  authTag: Buffer;
  ciphertext: Buffer;
}

interface ActiveLegQuotaRow {
  active_legs: number;
  earliest_active_until: Date | null;
}

interface DailyQuotaRow {
  reserved_leg_minutes: number;
}

interface MintEventRow {
  secret_mints: number;
  created_at: Date;
}

export class PostgresSessionRepository implements SessionRepository {
  readonly #pool: Pool;
  readonly #encryptionKey: Buffer;

  constructor(pool: Pool, serverSecret: string) {
    this.#pool = pool;
    this.#encryptionKey = createHmac('sha256', serverSecret)
      .update('translator/session-idempotency-response/v1', 'utf8')
      .digest();
  }

  async createSession(
    input: CreateSessionPersistenceInput,
    create: () => Promise<CreatedSessionPersistenceResult>
  ): Promise<TranslationSession> {
    const client = await this.#pool.connect();
    const operation: Operation = 'create_session';
    const scopeId = '';
    try {
      await client.query('BEGIN');
      await this.#pruneExpired(client, input.now);
      await this.#lockOperation(client, operation, input.safetyIdentifier, scopeId, input.idempotencyKey);

      const existing = await this.#findIdempotency(
        client,
        operation,
        input.safetyIdentifier,
        scopeId,
        input.idempotencyKey
      );
      if (existing !== null) {
        this.#assertFingerprint(existing.request_fingerprint, input.requestFingerprint);
        const session = this.#decrypt<TranslationSession>(existing, this.#aad(operation, input, scopeId));
        await client.query('COMMIT');
        return session;
      }

      await this.#lockQuotaOwner(client, input.safetyIdentifier);
      await this.#reserveQuota(client, operation, input.safetyIdentifier, input.now, input.quota);

      const created = await create();
      await client.query(
        `
          INSERT INTO translation_sessions (
            session_id,
            owner_safety_identifier,
            model,
            active_until,
            created_at
          ) VALUES ($1, $2, $3, $4, $5)
        `,
        [
          created.session.sessionId,
          input.safetyIdentifier,
          created.session.legs[0]!.model,
          created.activeUntil,
          input.now
        ]
      );
      for (const leg of created.session.legs) {
        await client.query(
          `
            INSERT INTO translation_session_legs (
              session_id,
              client_leg_id,
              leg_id,
              target_language,
              updated_at
            ) VALUES ($1, $2, $3, $4, $5)
          `,
          [created.session.sessionId, leg.clientLegId, leg.legId, leg.targetLanguage, input.now]
        );
      }
      await this.#storeIdempotency(
        client,
        operation,
        input,
        scopeId,
        created.session,
        new Date(created.session.expiresAt)
      );
      await client.query('COMMIT');
      return created.session;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async recreateLeg(
    input: RecreateLegPersistenceInput,
    create: (session: StoredSession) => Promise<TranslationLegCredentials>
  ): Promise<TranslationLegCredentials> {
    const client = await this.#pool.connect();
    const operation: Operation = 'recreate_leg';
    const scopeId = input.sessionId;
    try {
      await client.query('BEGIN');
      await this.#pruneExpired(client, input.now);
      await this.#lockOperation(client, operation, input.safetyIdentifier, scopeId, input.idempotencyKey);
      await this.#lockQuotaOwner(client, input.safetyIdentifier);

      const stored = await client.query<StoredSessionRow>(
        `
          SELECT
            s.owner_safety_identifier,
            s.active_until,
            s.model,
            l.client_leg_id,
            l.leg_id,
            l.target_language
          FROM translation_sessions AS s
          JOIN translation_session_legs AS l ON l.session_id = s.session_id
          WHERE s.session_id = $1
            AND s.owner_safety_identifier = $2
            AND s.active_until > $3
            AND s.completed_at IS NULL
            AND l.client_leg_id = $4
          FOR UPDATE OF s, l
        `,
        [input.sessionId, input.safetyIdentifier, input.now, input.clientLegId]
      );
      const storedRow = stored.rows[0];
      if (storedRow === undefined) {
        throw new SessionRepositoryError('RESOURCE_NOT_FOUND');
      }

      const existing = await this.#findIdempotency(
        client,
        operation,
        input.safetyIdentifier,
        scopeId,
        input.idempotencyKey
      );
      if (existing !== null) {
        this.#assertFingerprint(existing.request_fingerprint, input.requestFingerprint);
        const credentials = this.#decrypt<TranslationLegCredentials>(
          existing,
          this.#aad(operation, input, scopeId)
        );
        await client.query('COMMIT');
        return credentials;
      }

      await this.#reserveQuota(client, operation, input.safetyIdentifier, input.now, input.quota);

      const credentials = await create({
        safetyIdentifier: storedRow.owner_safety_identifier,
        activeUntil: storedRow.active_until,
        model: storedRow.model,
        leg: {
          clientLegId: storedRow.client_leg_id,
          legId: storedRow.leg_id,
          targetLanguage: storedRow.target_language
        }
      });
      await client.query(
        `
          UPDATE translation_session_legs
          SET leg_id = $3, updated_at = $4
          WHERE session_id = $1 AND client_leg_id = $2
        `,
        [input.sessionId, input.clientLegId, credentials.legId, input.now]
      );
      await this.#storeIdempotency(
        client,
        operation,
        input,
        scopeId,
        credentials,
        storedRow.active_until
      );
      await client.query('COMMIT');
      return credentials;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async completeSession(
    input: CompleteSessionPersistenceInput
  ): Promise<CompleteTranslationSessionResponse> {
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      await this.#lockQuotaOwner(client, input.safetyIdentifier);
      const existing = await client.query<CompletionRow>(
        `
          SELECT completed_at
          FROM translation_sessions
          WHERE session_id = $1 AND owner_safety_identifier = $2
          FOR UPDATE
        `,
        [input.sessionId, input.safetyIdentifier]
      );
      const row = existing.rows[0];
      if (row === undefined) {
        throw new SessionRepositoryError('RESOURCE_NOT_FOUND');
      }
      const completedAt = row.completed_at ?? input.now;
      if (row.completed_at === null) {
        await client.query(
          `
            UPDATE translation_sessions
            SET completed_at = $3,
                completion_result = $4,
                duration_seconds = $5,
                active_audio_seconds = $6,
                turns = $7,
                reconnects = $8,
                final_route_type = $9,
                completion_error_code = $10
            WHERE session_id = $1 AND owner_safety_identifier = $2
          `,
          [
            input.sessionId,
            input.safetyIdentifier,
            completedAt,
            input.completion.result,
            input.completion.durationSeconds,
            input.completion.activeAudioSeconds,
            input.completion.turns,
            input.completion.reconnects,
            input.completion.finalRouteType ?? null,
            input.completion.errorCode ?? null
          ]
        );
      }
      await client.query('COMMIT');
      return {
        sessionId: input.sessionId,
        status: 'completed',
        completedAt: completedAt.toISOString()
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async #lockOperation(
    client: PoolClient,
    operation: Operation,
    owner: string,
    scopeId: string,
    idempotencyKey: string
  ): Promise<void> {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
      `${operation}:${owner}:${scopeId}:${idempotencyKey}`
    ]);
  }

  async #lockQuotaOwner(client: PoolClient, owner: string): Promise<void> {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
      `translation-quota:${owner}`
    ]);
  }

  async #reserveQuota(
    client: PoolClient,
    operation: Operation,
    owner: string,
    now: Date,
    reservation: QuotaReservation
  ): Promise<void> {
    await this.#assertParallelLimit(client, owner, now, reservation);
    await this.#assertDailyLimit(client, owner, now, reservation);
    await this.#assertRateLimit(client, operation, owner, now, reservation);
  }

  async #assertParallelLimit(
    client: PoolClient,
    owner: string,
    now: Date,
    reservation: QuotaReservation
  ): Promise<void> {
    if (reservation.additionalActiveLegs === 0) return;
    const result = await client.query<ActiveLegQuotaRow>(
      `
        SELECT
          count(l.leg_id)::integer AS active_legs,
          min(s.active_until) AS earliest_active_until
        FROM translation_sessions AS s
        JOIN translation_session_legs AS l ON l.session_id = s.session_id
        WHERE s.owner_safety_identifier = $1
          AND s.active_until > $2
          AND s.completed_at IS NULL
      `,
      [owner, now]
    );
    const activeLegs = result.rows[0]?.active_legs ?? 0;
    if (activeLegs + reservation.additionalActiveLegs <= reservation.policy.maxParallelLegs) {
      return;
    }
    const retryAt = result.rows[0]?.earliest_active_until;
    throw new SessionRepositoryError(
      'RATE_LIMITED',
      retryAt === null || retryAt === undefined
        ? reservation.policy.secretMintWindowMs
        : Math.max(1, retryAt.getTime() - now.getTime())
    );
  }

  async #assertDailyLimit(
    client: PoolClient,
    owner: string,
    now: Date,
    reservation: QuotaReservation
  ): Promise<void> {
    if (reservation.dailyLegMinutes === 0) return;
    const quotaDate = now.toISOString().slice(0, 10);
    const result = await client.query<DailyQuotaRow>(
      `
        SELECT reserved_leg_minutes
        FROM translation_quota_daily_usage
        WHERE owner_safety_identifier = $1 AND quota_date = $2
        FOR UPDATE
      `,
      [owner, quotaDate]
    );
    const used = result.rows[0]?.reserved_leg_minutes ?? 0;
    if (used + reservation.dailyLegMinutes > reservation.policy.maxDailyLegMinutes) {
      const nextUtcDay = Date.UTC(
        now.getUTCFullYear(),
        now.getUTCMonth(),
        now.getUTCDate() + 1
      );
      throw new SessionRepositoryError(
        'RATE_LIMITED',
        Math.min(3_600_000, Math.max(1, nextUtcDay - now.getTime()))
      );
    }
    await client.query(
      `
        INSERT INTO translation_quota_daily_usage (
          owner_safety_identifier,
          quota_date,
          reserved_leg_minutes,
          updated_at
        ) VALUES ($1, $2, $3, $4)
        ON CONFLICT (owner_safety_identifier, quota_date) DO UPDATE
        SET reserved_leg_minutes = translation_quota_daily_usage.reserved_leg_minutes
            + EXCLUDED.reserved_leg_minutes,
            updated_at = EXCLUDED.updated_at
      `,
      [owner, quotaDate, reservation.dailyLegMinutes, now]
    );
  }

  async #assertRateLimit(
    client: PoolClient,
    operation: Operation,
    owner: string,
    now: Date,
    reservation: QuotaReservation
  ): Promise<void> {
    const windowStart = new Date(now.getTime() - reservation.policy.secretMintWindowMs);
    await client.query(
      `
        DELETE FROM translation_quota_mint_events
        WHERE owner_safety_identifier = $1 AND created_at <= $2
      `,
      [owner, windowStart]
    );
    const result = await client.query<MintEventRow>(
      `
        SELECT secret_mints, created_at
        FROM translation_quota_mint_events
        WHERE owner_safety_identifier = $1 AND created_at > $2
        ORDER BY created_at, event_id
      `,
      [owner, windowStart]
    );
    let used = result.rows.reduce((sum, event) => sum + event.secret_mints, 0);
    if (used + reservation.secretMints > reservation.policy.maxSecretMintsPerWindow) {
      let retryAfterMs = reservation.policy.secretMintWindowMs;
      for (const event of result.rows) {
        used -= event.secret_mints;
        retryAfterMs = Math.max(
          1,
          event.created_at.getTime() + reservation.policy.secretMintWindowMs - now.getTime()
        );
        if (used + reservation.secretMints <= reservation.policy.maxSecretMintsPerWindow) break;
      }
      throw new SessionRepositoryError('RATE_LIMITED', retryAfterMs);
    }
    await client.query(
      `
        INSERT INTO translation_quota_mint_events (
          owner_safety_identifier,
          operation,
          secret_mints,
          created_at
        ) VALUES ($1, $2, $3, $4)
      `,
      [owner, operation, reservation.secretMints, now]
    );
  }

  async #pruneExpired(client: PoolClient, now: Date): Promise<void> {
    await client.query(
      `
        DELETE FROM translation_session_idempotency
        WHERE expires_at <= $1
      `,
      [now]
    );
    await client.query(
      `
        DELETE FROM translation_sessions
        WHERE active_until <= $1
      `,
      [now]
    );
  }

  async #findIdempotency(
    client: PoolClient,
    operation: Operation,
    owner: string,
    scopeId: string,
    idempotencyKey: string
  ): Promise<IdempotencyRow | null> {
    const result = await client.query<IdempotencyRow>(
      `
        SELECT
          request_fingerprint,
          response_iv,
          response_auth_tag,
          response_ciphertext,
          expires_at
        FROM translation_session_idempotency
        WHERE operation = $1
          AND owner_safety_identifier = $2
          AND scope_id = $3
          AND idempotency_key = $4
      `,
      [operation, owner, scopeId, idempotencyKey]
    );
    return result.rows[0] ?? null;
  }

  async #storeIdempotency<T>(
    client: PoolClient,
    operation: Operation,
    input: CreateSessionPersistenceInput,
    scopeId: string,
    response: T,
    expiresAt: Date
  ): Promise<void> {
    const aad = this.#aad(operation, input, scopeId);
    const encrypted = this.#encrypt(response, aad);
    await client.query(
      `
        INSERT INTO translation_session_idempotency (
          operation,
          owner_safety_identifier,
          scope_id,
          idempotency_key,
          request_fingerprint,
          response_iv,
          response_auth_tag,
          response_ciphertext,
          expires_at,
          created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      `,
      [
        operation,
        input.safetyIdentifier,
        scopeId,
        input.idempotencyKey,
        Buffer.from(input.requestFingerprint, 'hex'),
        encrypted.iv,
        encrypted.authTag,
        encrypted.ciphertext,
        expiresAt,
        input.now
      ]
    );
  }

  #assertFingerprint(stored: Buffer, requested: string): void {
    if (!stored.equals(Buffer.from(requested, 'hex'))) {
      throw new SessionRepositoryError('IDEMPOTENCY_CONFLICT');
    }
  }

  #aad(
    operation: Operation,
    input: CreateSessionPersistenceInput,
    scopeId: string
  ): Buffer {
    return Buffer.from(
      [
        operation,
        input.safetyIdentifier,
        scopeId,
        input.idempotencyKey,
        input.requestFingerprint
      ].join('\n'),
      'utf8'
    );
  }

  #encrypt<T>(response: T, aad: Buffer): EncryptedResponse {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.#encryptionKey, iv);
    cipher.setAAD(aad);
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(response), 'utf8'),
      cipher.final()
    ]);
    return { iv, authTag: cipher.getAuthTag(), ciphertext };
  }

  #decrypt<T>(encrypted: IdempotencyRow, aad: Buffer): T {
    const decipher = createDecipheriv('aes-256-gcm', this.#encryptionKey, encrypted.response_iv);
    decipher.setAAD(aad);
    decipher.setAuthTag(encrypted.response_auth_tag);
    const plaintext = Buffer.concat([
      decipher.update(encrypted.response_ciphertext),
      decipher.final()
    ]);
    return JSON.parse(plaintext.toString('utf8')) as T;
  }
}
