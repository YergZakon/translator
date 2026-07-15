import { randomUUID } from 'node:crypto';

import Fastify, {
  type FastifyReply,
  type FastifyRequest,
  type FastifyServerOptions
} from 'fastify';

import { defaultAppConfig, type AppConfig } from './domain/app-config.js';
import {
  appConfigSchema,
  completeTranslationSessionRequestSchema,
  completeTranslationSessionResponseSchema,
  configHeadersSchema,
  createSessionHeadersSchema,
  createSessionRequestSchema,
  errorEnvelopeSchema,
  feedbackRequestSchema,
  feedbackResponseSchema,
  healthResponseSchema,
  recreateTranslationLegParamsSchema,
  recreateTranslationLegRequestSchema,
  registerInstallationHeadersSchema,
  registerInstallationRequestSchema,
  registerInstallationResponseSchema,
  translationLegCredentialsSchema,
  translationSessionSchema
} from './http/schemas.js';
import { RepositoryTokenVerifier, type TokenVerifier } from './security/token-verifier.js';
import { ConfigService } from './services/config-service.js';
import {
  FeedbackService,
  FeedbackServiceError,
  type FeedbackRequest
} from './services/feedback-service.js';
import {
  InstallationService,
  InstallationServiceError,
  type InstallationRepository
} from './services/installation-service.js';
import {
  SecretBrokerError,
  type SecretBroker,
  UnavailableSecretBroker
} from './services/openai-secret-broker.js';
import {
  type CompleteTranslationSessionRequest,
  type CreateSessionRequest,
  type RecreateLegRequest,
  SessionService,
  SessionServiceError
} from './services/session-service.js';
import type { SessionRepository } from './services/session-repository.js';
import type { QuotaPolicy } from './services/quota-service.js';
import { InMemoryInstallationRepository } from './storage/in-memory-installation-repository.js';
import { InMemorySessionRepository } from './storage/in-memory-session-repository.js';

interface RegisterInstallationHeaders {
  'x-app-attestation'?: string;
}

interface RegisterInstallationRequest {
  installationPublicId: string;
  app: { version: string; build: number };
  device: { osVersion: string; modelClass: 'phone' };
}

interface ConfigHeaders {
  authorization?: string;
  'x-app-version': string;
  'x-app-build': string;
  'if-none-match'?: string;
}

interface CreateSessionHeaders {
  authorization?: string;
  'idempotency-key': string;
}

interface AuthorizationHeaders {
  authorization?: string;
}

interface RecreateTranslationLegParams {
  sessionId: string;
}

export interface BuildAppOptions {
  serviceVersion?: string;
  now?: () => Date;
  isReady?: () => boolean;
  tokenVerifier?: TokenVerifier;
  installationRepository?: InstallationRepository;
  safetyIdentifierSecret?: string;
  installationIdFactory?: () => string;
  appTokenFactory?: () => string;
  appConfig?: AppConfig;
  secretBroker?: SecretBroker;
  sessionRepository?: SessionRepository;
  translationCallsUrl?: string;
  sessionIdFactory?: (prefix: 'ts' | 'leg') => string;
  quotaPolicy?: QuotaPolicy;
  logger?: FastifyServerOptions['logger'];
}

function traceId(request: FastifyRequest): string {
  return String(request.id);
}

function sendError(
  request: FastifyRequest,
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
  retryable = false,
  retryAfterMs?: number
): FastifyReply {
  return reply.code(statusCode).send({
    error: {
      code,
      message,
      retryable,
      ...(retryAfterMs === undefined ? {} : { retryAfterMs }),
      traceId: traceId(request)
    }
  });
}

export function buildApp(options: BuildAppOptions = {}) {
  const now = options.now ?? (() => new Date());
  const isReady = options.isReady ?? (() => true);
  const installationRepository =
    options.installationRepository ?? new InMemoryInstallationRepository();
  const installationService = new InstallationService({
    repository: installationRepository,
    now,
    ...(options.installationIdFactory === undefined
      ? {}
      : { installationIdFactory: options.installationIdFactory }),
    ...(options.appTokenFactory === undefined ? {} : { tokenFactory: options.appTokenFactory })
  });
  const tokenVerifier =
    options.tokenVerifier ??
    new RepositoryTokenVerifier(
      installationRepository,
      options.safetyIdentifierSecret ?? 'build-app-default-safety-secret-32chars',
      now
    );
  const configService = new ConfigService(options.appConfig ?? defaultAppConfig);
  const sessionRepository = options.sessionRepository ?? new InMemorySessionRepository();
  const sessionService = new SessionService({
    broker: options.secretBroker ?? new UnavailableSecretBroker(),
    repository: sessionRepository,
    ...(options.translationCallsUrl === undefined
      ? {}
      : { callsUrl: options.translationCallsUrl }),
    ...(options.sessionIdFactory === undefined ? {} : { idFactory: options.sessionIdFactory }),
    ...(options.quotaPolicy === undefined ? {} : { quotaPolicy: options.quotaPolicy }),
    now
  });
  const feedbackService = new FeedbackService(sessionRepository, now);

  const app = Fastify({
    logger: options.logger ?? false,
    ajv: {
      customOptions: {
        removeAdditional: false
      }
    },
    genReqId: () => `tr_${randomUUID().replaceAll('-', '')}`
  });

  app.setErrorHandler((error, request, reply) => {
    if (typeof error === 'object' && error !== null && 'validation' in error) {
      sendError(request, reply, 400, 'INVALID_REQUEST', 'Request validation failed');
      return;
    }

    const errorName = error instanceof Error ? error.name : 'UnknownError';
    const errorCode =
      typeof error === 'object' && error !== null && 'code' in error
        ? String(error.code)
        : undefined;
    request.log.error(
      { errorName, errorCode },
      'Unhandled request error'
    );
    sendError(request, reply, 500, 'INTERNAL_ERROR', 'Internal server error');
  });

  app.get(
    '/v1/health',
    {
      schema: {
        response: {
          200: healthResponseSchema,
          503: healthResponseSchema
        }
      }
    },
    async (_request, reply) => {
      const ready = isReady();
      return reply.code(ready ? 200 : 503).send({
        status: ready ? 'ok' : 'degraded',
        version: options.serviceVersion ?? 'dev',
        time: now().toISOString()
      });
    }
  );

  app.post<{ Headers: RegisterInstallationHeaders; Body: RegisterInstallationRequest }>(
    '/v1/installations',
    {
      schema: {
        headers: registerInstallationHeadersSchema,
        body: registerInstallationRequestSchema,
        response: {
          200: registerInstallationResponseSchema,
          201: registerInstallationResponseSchema,
          400: errorEnvelopeSchema,
          403: errorEnvelopeSchema,
          429: errorEnvelopeSchema
        }
      }
    },
    async (request, reply) => {
      try {
        const registration = await installationService.register({
          installationPublicId: request.body.installationPublicId,
          appVersion: request.body.app.version,
          appBuild: request.body.app.build,
          osVersion: request.body.device.osVersion,
          modelClass: request.body.device.modelClass
        });
        return reply.code(registration.statusCode).send({
          installationId: registration.installationId,
          tokenType: registration.tokenType,
          appToken: registration.appToken,
          expiresAt: registration.expiresAt
        });
      } catch (error) {
        if (error instanceof InstallationServiceError) {
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            error.safeMessage
          );
        }
        throw error;
      }
    }
  );

  app.get<{ Headers: ConfigHeaders }>(
    '/v1/config',
    {
      schema: {
        headers: configHeadersSchema,
        response: {
          200: appConfigSchema,
          400: errorEnvelopeSchema,
          401: errorEnvelopeSchema
        }
      },
      preHandler: async (request, reply) => {
        if (
          (await tokenVerifier.authenticateAuthorizationHeader(request.headers.authorization)) ===
          null
        ) {
          return sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
        }
      }
    },
    async (request, reply) => {
      const active = configService.getActiveConfig({
        appVersion: request.headers['x-app-version'],
        appBuild: Number(request.headers['x-app-build'])
      });

      reply.headers({
        etag: active.etag,
        'cache-control': 'private, max-age=0, must-revalidate',
        vary: 'Authorization, X-App-Version, X-App-Build'
      });

      if (request.headers['if-none-match'] === active.etag) {
        return reply.code(304).send();
      }

      return reply.code(200).send(active.config);
    }
  );

  app.post<{ Headers: CreateSessionHeaders; Body: CreateSessionRequest }>(
    '/v1/translation-sessions',
    {
      schema: {
        headers: createSessionHeadersSchema,
        body: createSessionRequestSchema,
        response: {
          201: translationSessionSchema,
          400: errorEnvelopeSchema,
          401: errorEnvelopeSchema,
          409: errorEnvelopeSchema,
          422: errorEnvelopeSchema,
          429: errorEnvelopeSchema,
          502: errorEnvelopeSchema,
          503: errorEnvelopeSchema,
          504: errorEnvelopeSchema
        }
      }
    },
    async (request, reply) => {
      const identity = await tokenVerifier.authenticateAuthorizationHeader(
        request.headers.authorization
      );
      if (identity === null) {
        return sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
      }

      const active = configService.getActiveConfig({
        appVersion: request.body.app.version,
        appBuild: request.body.app.build
      });
      if (active.config.killSwitch) {
        return sendError(
          request,
          reply,
          503,
          'KILL_SWITCH_ACTIVE',
          active.config.killSwitchMessage ?? 'Translation service is temporarily disabled'
        );
      }

      try {
        const session = await sessionService.create(request.body, {
          idempotencyKey: request.headers['idempotency-key'],
          safetyIdentifier: identity.safetyIdentifier,
          traceId: traceId(request),
          config: active.config
        });
        return reply.code(201).send(session);
      } catch (error) {
        if (error instanceof SessionServiceError) {
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            error.message,
            error.retryable,
            error.retryAfterMs
          );
        }
        if (error instanceof SecretBrokerError) {
          const messages = {
            RATE_LIMITED: 'Translation session creation is rate limited',
            UPSTREAM_SESSION_UNAVAILABLE: 'Translation session is temporarily unavailable',
            UPSTREAM_TIMEOUT: 'Translation provider timed out',
            SERVICE_UNAVAILABLE: 'Translation service is unavailable'
          } as const;
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            messages[error.code],
            error.retryable,
            error.retryAfterMs
          );
        }
        throw error;
      }
    }
  );

  app.post<{
    Params: RecreateTranslationLegParams;
    Headers: CreateSessionHeaders;
    Body: RecreateLegRequest;
  }>(
    '/v1/translation-sessions/:sessionId/legs',
    {
      schema: {
        params: recreateTranslationLegParamsSchema,
        headers: createSessionHeadersSchema,
        body: recreateTranslationLegRequestSchema,
        response: {
          201: translationLegCredentialsSchema,
          400: errorEnvelopeSchema,
          401: errorEnvelopeSchema,
          404: errorEnvelopeSchema,
          409: errorEnvelopeSchema,
          429: errorEnvelopeSchema,
          502: errorEnvelopeSchema,
          503: errorEnvelopeSchema,
          504: errorEnvelopeSchema
        }
      }
    },
    async (request, reply) => {
      const identity = await tokenVerifier.authenticateAuthorizationHeader(
        request.headers.authorization
      );
      if (identity === null) {
        return sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
      }

      const active = configService.getGlobalActiveConfig();
      if (active.config.killSwitch) {
        return sendError(
          request,
          reply,
          503,
          'KILL_SWITCH_ACTIVE',
          active.config.killSwitchMessage ?? 'Translation service is temporarily disabled'
        );
      }

      try {
        const credentials = await sessionService.recreateLeg(request.body, {
          sessionId: request.params.sessionId,
          idempotencyKey: request.headers['idempotency-key'],
          safetyIdentifier: identity.safetyIdentifier
        });
        return reply.code(201).send(credentials);
      } catch (error) {
        if (error instanceof SessionServiceError) {
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            error.message,
            error.retryable,
            error.retryAfterMs
          );
        }
        if (error instanceof SecretBrokerError) {
          const messages = {
            RATE_LIMITED: 'Translation leg recreation is rate limited',
            UPSTREAM_SESSION_UNAVAILABLE: 'Translation leg is temporarily unavailable',
            UPSTREAM_TIMEOUT: 'Translation provider timed out',
            SERVICE_UNAVAILABLE: 'Translation service is unavailable'
          } as const;
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            messages[error.code],
            error.retryable,
            error.retryAfterMs
          );
        }
        throw error;
      }
    }
  );

  app.post<{
    Params: RecreateTranslationLegParams;
    Headers: AuthorizationHeaders;
    Body: CompleteTranslationSessionRequest;
  }>(
    '/v1/translation-sessions/:sessionId/complete',
    {
      schema: {
        params: recreateTranslationLegParamsSchema,
        body: completeTranslationSessionRequestSchema,
        response: {
          200: completeTranslationSessionResponseSchema,
          400: errorEnvelopeSchema,
          401: errorEnvelopeSchema,
          404: errorEnvelopeSchema
        }
      }
    },
    async (request, reply) => {
      const identity = await tokenVerifier.authenticateAuthorizationHeader(
        request.headers.authorization
      );
      if (identity === null) {
        return sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
      }

      try {
        const completion = await sessionService.complete(request.body, {
          sessionId: request.params.sessionId,
          safetyIdentifier: identity.safetyIdentifier
        });
        return reply.code(200).send(completion);
      } catch (error) {
        if (error instanceof SessionServiceError) {
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            error.message,
            error.retryable,
            error.retryAfterMs
          );
        }
        throw error;
      }
    }
  );

  app.post<{
    Params: RecreateTranslationLegParams;
    Headers: AuthorizationHeaders;
    Body: FeedbackRequest;
  }>(
    '/v1/translation-sessions/:sessionId/feedback',
    {
      schema: {
        params: recreateTranslationLegParamsSchema,
        body: feedbackRequestSchema,
        response: {
          200: feedbackResponseSchema,
          400: errorEnvelopeSchema,
          401: errorEnvelopeSchema,
          404: errorEnvelopeSchema
        }
      }
    },
    async (request, reply) => {
      const identity = await tokenVerifier.authenticateAuthorizationHeader(
        request.headers.authorization
      );
      if (identity === null) {
        return sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
      }

      try {
        const feedback = await feedbackService.upsert(request.body, {
          sessionId: request.params.sessionId,
          safetyIdentifier: identity.safetyIdentifier
        });
        return reply.code(200).send(feedback);
      } catch (error) {
        if (error instanceof FeedbackServiceError) {
          return sendError(
            request,
            reply,
            error.httpStatus,
            error.code,
            error.message
          );
        }
        throw error;
      }
    }
  );

  return app;
}
