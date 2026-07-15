import type { TargetLanguage } from './openai-secret-broker.js';
import type {
  CompleteTranslationSessionRequest,
  CompleteTranslationSessionResponse,
  TranslationLegCredentials,
  TranslationSession
} from './session-service.js';
import type { QuotaReservation } from './quota-service.js';
import type { FeedbackCategory, FeedbackResponse } from './feedback-service.js';

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

export interface CompleteSessionPersistenceInput {
  safetyIdentifier: string;
  sessionId: string;
  now: Date;
  completion: CompleteTranslationSessionRequest;
}

export interface UpsertFeedbackPersistenceInput {
  safetyIdentifier: string;
  sessionId: string;
  rating: number;
  categories: FeedbackCategory[];
  storeComment: boolean;
  comment: string | null;
  now: Date;
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

  completeSession(
    input: CompleteSessionPersistenceInput
  ): Promise<CompleteTranslationSessionResponse>;

  upsertFeedback(input: UpsertFeedbackPersistenceInput): Promise<FeedbackResponse>;
}
