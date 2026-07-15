import type {
  TargetLanguage
} from './openai-secret-broker.js';
import type {
  TranslationLegCredentials,
  TranslationSession
} from './session-service.js';
import type { QuotaReservation } from './quota-service.js';

export interface StoredSessionLeg {
  clientLegId: string;
  legId: string;
  targetLanguage: TargetLanguage;
}

export interface StoredSession {
  safetyIdentifier: string;
  activeUntil: Date;
  model: string;
  leg: StoredSessionLeg;
}

export interface CreateSessionPersistenceInput {
  safetyIdentifier: string;
  idempotencyKey: string;
  requestFingerprint: string;
  now: Date;
  quota: QuotaReservation;
}

export interface CreatedSessionPersistenceResult {
  session: TranslationSession;
  activeUntil: Date;
}

export interface RecreateLegPersistenceInput extends CreateSessionPersistenceInput {
  sessionId: string;
  clientLegId: string;
}

export class SessionRepositoryError extends Error {
  constructor(
    readonly code: 'IDEMPOTENCY_CONFLICT' | 'RESOURCE_NOT_FOUND' | 'RATE_LIMITED',
    readonly retryAfterMs?: number
  ) {
    super(code);
    this.name = 'SessionRepositoryError';
  }
}

export interface SessionRepository {
  createSession(
    input: CreateSessionPersistenceInput,
    create: () => Promise<CreatedSessionPersistenceResult>
  ): Promise<TranslationSession>;

  recreateLeg(
    input: RecreateLegPersistenceInput,
    create: (session: StoredSession) => Promise<TranslationLegCredentials>
  ): Promise<TranslationLegCredentials>;
}
