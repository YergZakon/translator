import type { TranslationLegCredentials, TranslationSession } from '../services/session-service.js';
import {
  type CreateSessionPersistenceInput,
  type CreatedSessionPersistenceResult,
  type RecreateLegPersistenceInput,
  type SessionRepository,
  SessionRepositoryError,
  type StoredSession,
  type StoredSessionLeg
} from '../services/session-repository.js';

interface IdempotencyEntry<T> {
  fingerprint: string;
  expiresAt: Date;
  result: Promise<T>;
}

interface SessionRecord {
  safetyIdentifier: string;
  activeUntil: Date;
  model: string;
  legs: Map<string, StoredSessionLeg>;
}

export class InMemorySessionRepository implements SessionRepository {
  readonly #createIdempotency = new Map<string, IdempotencyEntry<TranslationSession>>();
  readonly #recreateIdempotency = new Map<
    string,
    IdempotencyEntry<TranslationLegCredentials>
  >();
  readonly #sessions = new Map<string, SessionRecord>();

  createSession(
    input: CreateSessionPersistenceInput,
    create: () => Promise<CreatedSessionPersistenceResult>
  ): Promise<TranslationSession> {
    const key = `${input.safetyIdentifier}:${input.idempotencyKey}`;
    const existing = this.#createIdempotency.get(key);
    if (existing !== undefined && existing.expiresAt.getTime() > input.now.getTime()) {
      this.#assertFingerprint(existing.fingerprint, input.requestFingerprint);
      return existing.result;
    }
    if (existing !== undefined) {
      this.#createIdempotency.delete(key);
    }

    let expiresAt = new Date(0);
    const result = create().then((created) => {
      expiresAt = new Date(created.session.expiresAt);
      this.#sessions.set(created.session.sessionId, {
        safetyIdentifier: input.safetyIdentifier,
        activeUntil: created.activeUntil,
        model: created.session.legs[0]!.model,
        legs: new Map(
          created.session.legs.map((leg) => [
            leg.clientLegId,
            {
              clientLegId: leg.clientLegId,
              legId: leg.legId,
              targetLanguage: leg.targetLanguage
            }
          ])
        )
      });
      const current = this.#createIdempotency.get(key);
      if (current?.result === result) {
        current.expiresAt = expiresAt;
      }
      return created.session;
    });
    this.#createIdempotency.set(key, {
      fingerprint: input.requestFingerprint,
      expiresAt: new Date(8_640_000_000_000_000),
      result
    });
    void result.catch(() => {
      const current = this.#createIdempotency.get(key);
      if (current?.result === result) {
        this.#createIdempotency.delete(key);
      }
    });
    return result;
  }

  recreateLeg(
    input: RecreateLegPersistenceInput,
    create: (session: StoredSession) => Promise<TranslationLegCredentials>
  ): Promise<TranslationLegCredentials> {
    const session = this.#sessions.get(input.sessionId);
    if (
      session === undefined ||
      session.safetyIdentifier !== input.safetyIdentifier ||
      session.activeUntil.getTime() <= input.now.getTime()
    ) {
      if (session !== undefined && session.activeUntil.getTime() <= input.now.getTime()) {
        this.#sessions.delete(input.sessionId);
      }
      throw new SessionRepositoryError('RESOURCE_NOT_FOUND');
    }
    const leg = session.legs.get(input.clientLegId);
    if (leg === undefined) {
      throw new SessionRepositoryError('RESOURCE_NOT_FOUND');
    }

    const key = `${input.safetyIdentifier}:${input.sessionId}:${input.idempotencyKey}`;
    const existing = this.#recreateIdempotency.get(key);
    if (existing !== undefined && existing.expiresAt.getTime() > input.now.getTime()) {
      this.#assertFingerprint(existing.fingerprint, input.requestFingerprint);
      return existing.result;
    }
    if (existing !== undefined) {
      this.#recreateIdempotency.delete(key);
    }

    const result = create({
      safetyIdentifier: session.safetyIdentifier,
      activeUntil: session.activeUntil,
      model: session.model,
      leg
    }).then((credentials) => {
      session.legs.set(input.clientLegId, {
        clientLegId: input.clientLegId,
        legId: credentials.legId,
        targetLanguage: credentials.targetLanguage
      });
      return credentials;
    });
    this.#recreateIdempotency.set(key, {
      fingerprint: input.requestFingerprint,
      expiresAt: session.activeUntil,
      result
    });
    void result.catch(() => {
      const current = this.#recreateIdempotency.get(key);
      if (current?.result === result) {
        this.#recreateIdempotency.delete(key);
      }
    });
    return result;
  }

  #assertFingerprint(stored: string, requested: string): void {
    if (stored !== requested) {
      throw new SessionRepositoryError('IDEMPOTENCY_CONFLICT');
    }
  }
}
