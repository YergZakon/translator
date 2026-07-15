import { createHash, randomUUID } from 'node:crypto';

import type { AppConfig } from '../domain/app-config.js';
import { InMemorySessionRepository } from '../storage/in-memory-session-repository.js';
import type { SecretBroker, TargetLanguage } from './openai-secret-broker.js';
import { QuotaService, type QuotaPolicy } from './quota-service.js';
import {
  type SessionRepository,
  SessionRepositoryError,
  type StoredSession
} from './session-repository.js';

export type TranslationMode = 'one_way_ru_to_en' | 'dialogue';

export interface CreateSessionRequest {
  mode: TranslationMode;
  sourceLocaleHint?: string | null;
  legs: Array<{
    clientLegId: string;
    targetLanguage: TargetLanguage;
  }>;
  app: { version: string; build: number };
  device: { osVersion: string; modelClass: 'phone' };
}

export interface TranslationLegCredentials {
  legId: string;
  clientLegId: string;
  targetLanguage: TargetLanguage;
  provider: 'openai';
  model: string;
  clientSecret: string;
  expiresAt: string;
  callsUrl: string;
}

export interface TranslationSession {
  sessionId: string;
  traceId: string;
  expiresAt: string;
  maxDurationSeconds: number;
  legs: TranslationLegCredentials[];
  policy: {
    maxReconnectAttempts: number;
    reconnectBackoffMs: number[];
    outputInterruption: 'finish_current' | 'duck_and_switch' | 'hard_cut';
    outputInterruptionDelayMs: number;
    telemetrySampleRate: number;
  };
}

export class SessionServiceError extends Error {
  constructor(
    readonly code:
      | 'IDEMPOTENCY_CONFLICT'
      | 'RESOURCE_NOT_FOUND'
      | 'UNSUPPORTED_CONFIGURATION'
      | 'RATE_LIMITED',
    readonly httpStatus: 404 | 409 | 422 | 429,
    readonly message: string,
    readonly retryable = false,
    readonly retryAfterMs?: number
  ) {
    super(message);
    this.name = 'SessionServiceError';
  }
}

export interface CreateSessionContext {
  idempotencyKey: string;
  safetyIdentifier: string;
  traceId: string;
  config: AppConfig;
}

export type RecreateLegReason =
  | 'connection_failed'
  | 'disconnected_timeout'
  | 'secret_expired'
  | 'manual_retry';

export interface RecreateLegRequest {
  clientLegId: string;
  reason: RecreateLegReason;
}

export interface RecreateLegContext {
  sessionId: string;
  idempotencyKey: string;
  safetyIdentifier: string;
}

function stableFingerprint(request: CreateSessionRequest): string {
  const normalized = {
    mode: request.mode,
    sourceLocaleHint: request.sourceLocaleHint ?? null,
    legs: request.legs.map((leg) => ({
      clientLegId: leg.clientLegId,
      targetLanguage: leg.targetLanguage
    })),
    app: { version: request.app.version, build: request.app.build },
    device: { osVersion: request.device.osVersion, modelClass: request.device.modelClass }
  };
  return createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
}

function validateRequest(request: CreateSessionRequest, config: AppConfig): void {
  if (!config.allowedModes.includes(request.mode)) {
    throw new SessionServiceError('UNSUPPORTED_CONFIGURATION', 422, 'Mode is disabled by config');
  }

  const ids = new Set(request.legs.map((leg) => leg.clientLegId));
  if (ids.size !== request.legs.length) {
    throw new SessionServiceError('UNSUPPORTED_CONFIGURATION', 422, 'Client leg IDs must be unique');
  }

  if (request.legs.some((leg) => !config.allowedTargetLanguages.includes(leg.targetLanguage))) {
    throw new SessionServiceError('UNSUPPORTED_CONFIGURATION', 422, 'Target language is disabled by config');
  }

  if (
    request.mode === 'one_way_ru_to_en' &&
    (request.legs.length !== 1 || request.legs[0]?.targetLanguage !== 'en')
  ) {
    throw new SessionServiceError(
      'UNSUPPORTED_CONFIGURATION',
      422,
      'One-way RU to EN mode requires exactly one English target leg'
    );
  }

  const targets = new Set(request.legs.map((leg) => leg.targetLanguage));
  if (
    request.mode === 'dialogue' &&
    (request.legs.length !== 2 || !targets.has('ru') || !targets.has('en'))
  ) {
    throw new SessionServiceError(
      'UNSUPPORTED_CONFIGURATION',
      422,
      'Dialogue mode requires one Russian and one English target leg'
    );
  }
}

export interface SessionServiceOptions {
  broker: SecretBroker;
  repository?: SessionRepository;
  callsUrl?: string;
  idFactory?: (prefix: 'ts' | 'leg') => string;
  now?: () => Date;
  quotaPolicy?: QuotaPolicy;
}

export class SessionService {
  readonly #broker: SecretBroker;
  readonly #callsUrl: string;
  readonly #idFactory: (prefix: 'ts' | 'leg') => string;
  readonly #now: () => Date;
  readonly #repository: SessionRepository;
  readonly #quotaService: QuotaService;

  constructor(options: SessionServiceOptions) {
    this.#broker = options.broker;
    this.#repository = options.repository ?? new InMemorySessionRepository();
    this.#callsUrl = options.callsUrl ?? 'https://api.openai.com/v1/realtime/translations/calls';
    this.#idFactory =
      options.idFactory ?? ((prefix) => `${prefix}_${randomUUID().replaceAll('-', '')}`);
    this.#now = options.now ?? (() => new Date());
    this.#quotaService = new QuotaService(options.quotaPolicy);
  }

  async create(
    request: CreateSessionRequest,
    context: CreateSessionContext
  ): Promise<TranslationSession> {
    validateRequest(request, context.config);
    const now = this.#now();
    try {
      return await this.#repository.createSession(
        {
          safetyIdentifier: context.safetyIdentifier,
          idempotencyKey: context.idempotencyKey,
          requestFingerprint: stableFingerprint(request),
          now,
          quota: this.#quotaService.createSessionReservation(
            request.legs.length,
            context.config.maxDurationSeconds
          )
        },
        () => this.#createNew(request, context, now)
      );
    } catch (error) {
      throw this.#mapRepositoryError(error);
    }
  }

  async recreateLeg(
    request: RecreateLegRequest,
    context: RecreateLegContext
  ): Promise<TranslationLegCredentials> {
    const now = this.#now();
    try {
      return await this.#repository.recreateLeg(
        {
          safetyIdentifier: context.safetyIdentifier,
          sessionId: context.sessionId,
          clientLegId: request.clientLegId,
          idempotencyKey: context.idempotencyKey,
          requestFingerprint: createHash('sha256')
            .update(JSON.stringify(request))
            .digest('hex'),
          now,
          quota: this.#quotaService.recreateLegReservation()
        },
        (session) => this.#createReplacementLeg(request.clientLegId, session)
      );
    } catch (error) {
      throw this.#mapRepositoryError(error);
    }
  }

  async #createNew(
    request: CreateSessionRequest,
    context: CreateSessionContext,
    now: Date
  ): Promise<{ session: TranslationSession; activeUntil: Date }> {
    const credentials = await Promise.all(
      request.legs.map(async (requestedLeg) => {
        const secret = await this.#broker.createTranslationSecret({
          model: context.config.modelAlias,
          targetLanguage: requestedLeg.targetLanguage,
          safetyIdentifier: context.safetyIdentifier
        });
        return {
          legId: this.#idFactory('leg'),
          clientLegId: requestedLeg.clientLegId,
          targetLanguage: requestedLeg.targetLanguage,
          provider: 'openai' as const,
          model: context.config.modelAlias,
          clientSecret: secret.value,
          expiresAt: secret.expiresAt.toISOString(),
          callsUrl: this.#callsUrl
        };
      })
    );

    const sessionExpiry = credentials.reduce(
      (earliest, leg) => (leg.expiresAt < earliest ? leg.expiresAt : earliest),
      credentials[0]!.expiresAt
    );

    const session: TranslationSession = {
      sessionId: this.#idFactory('ts'),
      traceId: context.traceId,
      expiresAt: sessionExpiry,
      maxDurationSeconds: context.config.maxDurationSeconds,
      legs: credentials,
      policy: {
        maxReconnectAttempts: context.config.reconnectPolicy.maxAttempts,
        reconnectBackoffMs: [...context.config.reconnectPolicy.backoffMs],
        outputInterruption: context.config.outputInterruption.mode,
        outputInterruptionDelayMs: context.config.outputInterruption.delayMs,
        telemetrySampleRate: context.config.telemetrySampleRate
      }
    };
    return {
      session,
      activeUntil: new Date(now.getTime() + session.maxDurationSeconds * 1000)
    };
  }

  async #createReplacementLeg(
    clientLegId: string,
    session: StoredSession
  ): Promise<TranslationLegCredentials> {
    const secret = await this.#broker.createTranslationSecret({
      model: session.model,
      targetLanguage: session.leg.targetLanguage,
      safetyIdentifier: session.safetyIdentifier
    });
    const credentials = {
      legId: this.#idFactory('leg'),
      clientLegId,
      targetLanguage: session.leg.targetLanguage,
      provider: 'openai' as const,
      model: session.model,
      clientSecret: secret.value,
      expiresAt: secret.expiresAt.toISOString(),
      callsUrl: this.#callsUrl
    };
    return credentials;
  }

  #mapRepositoryError(error: unknown): unknown {
    if (!(error instanceof SessionRepositoryError)) {
      return error;
    }
    if (error.code === 'IDEMPOTENCY_CONFLICT') {
      return new SessionServiceError(
        'IDEMPOTENCY_CONFLICT',
        409,
        'Idempotency key was already used for a different request'
      );
    }
    if (error.code === 'RATE_LIMITED') {
      return new SessionServiceError(
        'RATE_LIMITED',
        429,
        'Translation quota is temporarily exceeded',
        true,
        error.retryAfterMs
      );
    }
    return new SessionServiceError('RESOURCE_NOT_FOUND', 404, 'Translation session was not found');
  }
}
