import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes
} from 'node:crypto';

import type { Pool, PoolClient } from 'pg';

import type { TranslationLegCredentials, TranslationSession } from '../services/session-service.js';
import {
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

interface EncryptedResponse {
  iv: Buffer;
  authTag: Buffer;
  ciphertext: Buffer;
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
