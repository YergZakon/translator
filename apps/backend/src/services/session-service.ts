import { createHash, randomUUID } from 'node:crypto';

import type { AppConfig } from '../domain/app-config.js';
import type { SecretBroker, TargetLanguage } from './openai-secret-broker.js';

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

export interface TranslationSession {
  sessionId: string;
  traceId: string;
  expiresAt: string;
  maxDurationSeconds: number;
  legs: Array<{
    legId: string;
    clientLegId: string;
    targetLanguage: TargetLanguage;
    provider: 'openai';
    model: string;
    clientSecret: string;
    expiresAt: string;
    callsUrl: string;
  }>;
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
    readonly code: 'IDEMPOTENCY_CONFLICT' | 'UNSUPPORTED_CONFIGURATION',
    readonly httpStatus: 409 | 422,
    readonly message: string
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

interface IdempotencyEntry {
  fingerprint: string;
  result: Promise<TranslationSession>;
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
  callsUrl?: string;
  idFactory?: (prefix: 'ts' | 'leg') => string;
}

export class SessionService {
  readonly #broker: SecretBroker;
  readonly #callsUrl: string;
  readonly #idFactory: (prefix: 'ts' | 'leg') => string;
  readonly #idempotency = new Map<string, IdempotencyEntry>();

  constructor(options: SessionServiceOptions) {
    this.#broker = options.broker;
    this.#callsUrl = options.callsUrl ?? 'https://api.openai.com/v1/realtime/translations/calls';
    this.#idFactory =
      options.idFactory ?? ((prefix) => `${prefix}_${randomUUID().replaceAll('-', '')}`);
  }

  create(request: CreateSessionRequest, context: CreateSessionContext): Promise<TranslationSession> {
    validateRequest(request, context.config);

    const key = `${context.safetyIdentifier}:${context.idempotencyKey}`;
    const fingerprint = stableFingerprint(request);
    const existing = this.#idempotency.get(key);
    if (existing !== undefined) {
      if (existing.fingerprint !== fingerprint) {
        throw new SessionServiceError(
          'IDEMPOTENCY_CONFLICT',
          409,
          'Idempotency key was already used for a different request'
        );
      }
      return existing.result;
    }

    const result = this.#createNew(request, context);
    this.#idempotency.set(key, { fingerprint, result });
    void result.then(
      (session) => {
        const delay = Math.max(Date.parse(session.expiresAt) - Date.now(), 0);
        const expiryTimer = setTimeout(() => {
          const current = this.#idempotency.get(key);
          if (current?.result === result) {
            this.#idempotency.delete(key);
          }
        }, Math.min(delay, 2_147_483_647));
        expiryTimer.unref();
      },
      () => undefined
    );
    void result.catch(() => {
      const current = this.#idempotency.get(key);
      if (current?.result === result) {
        this.#idempotency.delete(key);
      }
    });
    return result;
  }

  async #createNew(
    request: CreateSessionRequest,
    context: CreateSessionContext
  ): Promise<TranslationSession> {
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

    return {
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
  }
}
