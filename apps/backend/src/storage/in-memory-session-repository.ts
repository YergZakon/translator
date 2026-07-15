import type {
  CompleteTranslationSessionResponse,
  TranslationLegCredentials,
  TranslationSession
} from '../services/session-service.js';
import {
  type CompleteSessionPersistenceInput,
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
  completion?: CompleteTranslationSessionResponse;
}

interface MintEvent {
  createdAt: Date;
  secretMints: number;
}

interface QuotaRollback {
  apply(): void;
}

export class InMemorySessionRepository implements SessionRepository {
  readonly #createIdempotency = new Map<string, IdempotencyEntry<TranslationSession>>();
  readonly #recreateIdempotency = new Map<
    string,
    IdempotencyEntry<TranslationLegCredentials>
  >();
  readonly #sessions = new Map<string, SessionRecord>();
  readonly #dailyUsage = new Map<string, number>();
  readonly #mintEvents = new Map<string, MintEvent[]>();
  readonly #pendingActiveLegs = new Map<string, number>();

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

    const quotaRollback = this.#reserveQuota(input);
    let expiresAt = new Date(0);
    const result = Promise.resolve().then(create).then((created) => {
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
      this.#decrementPendingLegs(input.safetyIdentifier, input.quota.additionalActiveLegs);
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
      quotaRollback.apply();
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
      session.activeUntil.getTime() <= input.now.getTime() ||
      session.completion !== undefined
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

    const quotaRollback = this.#reserveQuota(input);
    const result = Promise.resolve().then(() =>
      create({
        safetyIdentifier: session.safetyIdentifier,
        activeUntil: session.activeUntil,
        model: session.model,
        leg
      })
    );
    const quotaResult = result.then((credentials) => {
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
      result: quotaResult
    });
    void quotaResult.catch(() => {
      quotaRollback.apply();
      const current = this.#recreateIdempotency.get(key);
      if (current?.result === quotaResult) {
        this.#recreateIdempotency.delete(key);
      }
    });
    return quotaResult;
  }

  completeSession(input: CompleteSessionPersistenceInput): Promise<CompleteTranslationSessionResponse> {
    const session = this.#sessions.get(input.sessionId);
    if (session === undefined || session.safetyIdentifier !== input.safetyIdentifier) {
      throw new SessionRepositoryError('RESOURCE_NOT_FOUND');
    }
    if (session.completion !== undefined) {
      return Promise.resolve(session.completion);
    }
    const completion: CompleteTranslationSessionResponse = {
      sessionId: input.sessionId,
      status: 'completed',
      completedAt: input.now.toISOString()
    };
    session.completion = completion;
    return Promise.resolve(completion);
  }

  #reserveQuota(input: CreateSessionPersistenceInput): QuotaRollback {
    this.#pruneExpiredSessions(input.now);
    const owner = input.safetyIdentifier;
    const reservation = input.quota;
    const activeSessions = [...this.#sessions.values()].filter(
      (session) =>
        session.safetyIdentifier === owner &&
        session.completion === undefined &&
        session.activeUntil.getTime() > input.now.getTime()
    );
    const activeLegs = activeSessions.reduce((sum, session) => sum + session.legs.size, 0);
    const pendingLegs = this.#pendingActiveLegs.get(owner) ?? 0;
    if (
      activeLegs + pendingLegs + reservation.additionalActiveLegs >
      reservation.policy.maxParallelLegs
    ) {
      const earliest = activeSessions.reduce<number | null>(
        (value, session) =>
          value === null ? session.activeUntil.getTime() : Math.min(value, session.activeUntil.getTime()),
        null
      );
      throw new SessionRepositoryError(
        'RATE_LIMITED',
        earliest === null
          ? reservation.policy.secretMintWindowMs
          : Math.max(1, earliest - input.now.getTime())
      );
    }

    const quotaDate = input.now.toISOString().slice(0, 10);
    const dailyKey = `${owner}:${quotaDate}`;
    const dailyUsed = this.#dailyUsage.get(dailyKey) ?? 0;
    if (dailyUsed + reservation.dailyLegMinutes > reservation.policy.maxDailyLegMinutes) {
      const nextUtcDay = Date.UTC(
        input.now.getUTCFullYear(),
        input.now.getUTCMonth(),
        input.now.getUTCDate() + 1
      );
      throw new SessionRepositoryError(
        'RATE_LIMITED',
        Math.min(3_600_000, Math.max(1, nextUtcDay - input.now.getTime()))
      );
    }

    const windowStart = input.now.getTime() - reservation.policy.secretMintWindowMs;
    const events = (this.#mintEvents.get(owner) ?? []).filter(
      (event) => event.createdAt.getTime() > windowStart
    );
    this.#mintEvents.set(owner, events);
    let usedMints = events.reduce((sum, event) => sum + event.secretMints, 0);
    if (usedMints + reservation.secretMints > reservation.policy.maxSecretMintsPerWindow) {
      let retryAfterMs = reservation.policy.secretMintWindowMs;
      for (const event of events) {
        usedMints -= event.secretMints;
        retryAfterMs = Math.max(
          1,
          event.createdAt.getTime() + reservation.policy.secretMintWindowMs - input.now.getTime()
        );
        if (usedMints + reservation.secretMints <= reservation.policy.maxSecretMintsPerWindow) {
          break;
        }
      }
      throw new SessionRepositoryError('RATE_LIMITED', retryAfterMs);
    }

    const event = { createdAt: input.now, secretMints: reservation.secretMints };
    events.push(event);
    this.#dailyUsage.set(dailyKey, dailyUsed + reservation.dailyLegMinutes);
    this.#pendingActiveLegs.set(owner, pendingLegs + reservation.additionalActiveLegs);
    let active = true;
    return {
      apply: () => {
        if (!active) return;
        active = false;
        const currentEvents = this.#mintEvents.get(owner);
        if (currentEvents !== undefined) {
          const index = currentEvents.indexOf(event);
          if (index >= 0) currentEvents.splice(index, 1);
        }
        const remainingDaily = Math.max(
          0,
          (this.#dailyUsage.get(dailyKey) ?? 0) - reservation.dailyLegMinutes
        );
        if (remainingDaily === 0) this.#dailyUsage.delete(dailyKey);
        else this.#dailyUsage.set(dailyKey, remainingDaily);
        this.#decrementPendingLegs(owner, reservation.additionalActiveLegs);
      }
    };
  }

  #decrementPendingLegs(owner: string, count: number): void {
    const remaining = Math.max(0, (this.#pendingActiveLegs.get(owner) ?? 0) - count);
    if (remaining === 0) this.#pendingActiveLegs.delete(owner);
    else this.#pendingActiveLegs.set(owner, remaining);
  }

  #pruneExpiredSessions(now: Date): void {
    for (const [sessionId, session] of this.#sessions) {
      if (session.activeUntil.getTime() <= now.getTime()) this.#sessions.delete(sessionId);
    }
  }

  #assertFingerprint(stored: string, requested: string): void {
    if (stored !== requested) {
      throw new SessionRepositoryError('IDEMPOTENCY_CONFLICT');
    }
  }
}
