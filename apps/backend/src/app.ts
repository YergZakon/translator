import { randomUUID } from 'node:crypto';

import Fastify, {
  type FastifyReply,
  type FastifyRequest,
  type FastifyServerOptions
} from 'fastify';

import { defaultAppConfig, type AppConfig } from './domain/app-config.js';
import {
  appConfigSchema,
  configHeadersSchema,
  errorEnvelopeSchema,
  healthResponseSchema
} from './http/schemas.js';
import { StaticTokenVerifier, type TokenVerifier } from './security/token-verifier.js';
import { ConfigService } from './services/config-service.js';

interface ConfigHeaders {
  authorization?: string;
  'x-app-version': string;
  'x-app-build': string;
  'if-none-match'?: string;
}

export interface BuildAppOptions {
  serviceVersion?: string;
  now?: () => Date;
  isReady?: () => boolean;
  tokenVerifier?: TokenVerifier;
  appConfig?: AppConfig;
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
  retryable = false
): void {
  reply.code(statusCode).send({
    error: {
      code,
      message,
      retryable,
      traceId: traceId(request)
    }
  });
}

export function buildApp(options: BuildAppOptions = {}) {
  const now = options.now ?? (() => new Date());
  const isReady = options.isReady ?? (() => true);
  const tokenVerifier = options.tokenVerifier ?? new StaticTokenVerifier([]);
  const configService = new ConfigService(options.appConfig ?? defaultAppConfig);

  const app = Fastify({
    logger: options.logger ?? false,
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
        if (!tokenVerifier.verifyAuthorizationHeader(request.headers.authorization)) {
          sendError(request, reply, 401, 'INVALID_APP_TOKEN', 'App token is invalid');
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

  return app;
}
