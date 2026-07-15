import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

import { buildApp } from '../src/app.js';
import { defaultAppConfig } from '../src/domain/app-config.js';
import { StaticTokenVerifier } from '../src/security/token-verifier.js';
import {
  SecretBrokerError,
  type CreateTranslationSecretInput,
  type SecretBroker,
  type TranslationSecret
} from '../src/services/openai-secret-broker.js';
import type { QuotaPolicy } from '../src/services/quota-service.js';
import type { SessionRepository } from '../src/services/session-repository.js';
import { InMemorySessionRepository } from '../src/storage/in-memory-session-repository.js';

const apps: FastifyInstance[] = [];
const appToken = 'test-prototype-app-token';
const idempotencyKey = '8f5d6754-c57a-4a44-9f0d-02da2172c11f';
const recreateIdempotencyKey = '6fd2aca3-1be3-462f-98ee-a297b3e4d7af';
const headers = {
  authorization: `Bearer ${appToken}`,
  'idempotency-key': idempotencyKey
};
const oneWayRequest = {
  mode: 'one_way_ru_to_en',
  sourceLocaleHint: 'ru-KZ',
  legs: [{ clientLegId: 'ru-to-en', targetLanguage: 'en' }],
  app: { version: '0.1.0', build: 42 },
  device: { osVersion: '26.0', modelClass: 'phone' }
};
const completionRequest = {
  result: 'user_stopped',
  durationSeconds: 32,
  activeAudioSeconds: 18,
  turns: 3,
  reconnects: 1,
  finalRouteType: 'bluetooth',
  errorCode: null
};

class RecordingBroker implements SecretBroker {
  readonly calls: CreateTranslationSecretInput[] = [];

  async createTranslationSecret(input: CreateTranslationSecretInput): Promise<TranslationSecret> {
    this.calls.push(input);
    return {
      value: `ek_mock_${input.targetLanguage}_${this.calls.length}_short_lived_secret`,
      expiresAt: new Date(input.targetLanguage === 'en' ? '2099-07-14T05:10:00Z' : '2099-07-14T05:09:30Z')
    };
  }
}

function makeApp(
  broker: SecretBroker,
  killSwitch = false,
  now: () => Date = () => new Date(),
  acceptedTokens: string[] = [appToken],
  quotaPolicy?: QuotaPolicy,
  sessionRepository?: SessionRepository
): FastifyInstance {
  let id = 0;
  const config = structuredClone(defaultAppConfig);
  config.killSwitch = killSwitch;
  config.killSwitchMessage = killSwitch ? 'Pilot is paused' : null;
  const app = buildApp({
    serviceVersion: '0.1.0-test',
    appConfig: config,
    tokenVerifier: new StaticTokenVerifier(
      acceptedTokens,
      'test-safety-identifier-secret-32-characters'
    ),
    secretBroker: broker,
    ...(quotaPolicy === undefined ? {} : { quotaPolicy }),
    ...(sessionRepository === undefined ? {} : { sessionRepository }),
    now,
    sessionIdFactory: (prefix) => `${prefix}_${String(++id).padStart(24, 'a')}`
  });
  apps.push(app);
  return app;
}

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
});

test('POST /v1/translation-sessions creates a contract-valid one-way session', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  assert.equal(response.statusCode, 201);
  const body = response.json();
  assert.match(body.sessionId, /^ts_[A-Za-z0-9]{20,40}$/);
  assert.match(body.traceId, /^tr_[A-Za-z0-9]{20,40}$/);
  assert.equal(body.expiresAt, '2099-07-14T05:10:00.000Z');
  assert.equal(body.legs[0].clientSecret, 'ek_mock_en_1_short_lived_secret');
  assert.equal(
    body.legs[0].callsUrl,
    'https://api.openai.com/v1/realtime/translations/calls'
  );
  assert.equal(broker.calls.length, 1);
  assert.equal(broker.calls[0]?.targetLanguage, 'en');
  assert.match(broker.calls[0]?.safetyIdentifier ?? '', /^inst_[0-9a-f]{32}$/);
  assert.equal(JSON.stringify(broker.calls).includes(appToken), false);
});

test('POST /v1/translation-sessions creates two dialogue legs and uses earliest expiry', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: {
      ...oneWayRequest,
      mode: 'dialogue',
      legs: [
        { clientLegId: 'ru-to-en', targetLanguage: 'en' },
        { clientLegId: 'en-to-ru', targetLanguage: 'ru' }
      ]
    }
  });

  assert.equal(response.statusCode, 201);
  assert.equal(response.json().legs.length, 2);
  assert.equal(response.json().expiresAt, '2099-07-14T05:09:30.000Z');
  assert.deepEqual(
    broker.calls.map((call) => call.targetLanguage),
    ['en', 'ru']
  );
});

test('POST /v1/translation-sessions reuses an idempotent result without minting another secret', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const first = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const second = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  assert.equal(first.statusCode, 201);
  assert.equal(second.statusCode, 201);
  assert.deepEqual(second.json(), first.json());
  assert.equal(broker.calls.length, 1);
});

test('POST /v1/translation-sessions rejects reuse of a key for a different request', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const response = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: { ...oneWayRequest, sourceLocaleHint: 'ru-RU' }
  });

  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'IDEMPOTENCY_CONFLICT');
  assert.equal(broker.calls.length, 1);
});

test('POST /v1/translation-sessions enforces mode and leg semantics before the upstream call', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: {
      ...oneWayRequest,
      legs: [{ clientLegId: 'en-to-ru', targetLanguage: 'ru' }]
    }
  });

  assert.equal(response.statusCode, 422);
  assert.equal(response.json().error.code, 'UNSUPPORTED_CONFIGURATION');
  assert.equal(broker.calls.length, 0);
});

test('POST /v1/translation-sessions blocks new sessions when kill switch is active', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker, true).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  assert.equal(response.statusCode, 503);
  assert.equal(response.json().error.code, 'KILL_SWITCH_ACTIVE');
  assert.equal(response.json().error.message, 'Pilot is paused');
  assert.equal(broker.calls.length, 0);
});

test('POST /v1/translation-sessions maps sanitized upstream errors and retry policy', async () => {
  const broker: SecretBroker = {
    async createTranslationSecret() {
      throw new SecretBrokerError('RATE_LIMITED', 429, true, 1500);
    }
  };
  const response = await makeApp(broker).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  assert.equal(response.statusCode, 429);
  assert.deepEqual(
    {
      code: response.json().error.code,
      retryable: response.json().error.retryable,
      retryAfterMs: response.json().error.retryAfterMs
    },
    { code: 'RATE_LIMITED', retryable: true, retryAfterMs: 1500 }
  );
});

test('POST /v1/translation-sessions rejects invalid app tokens before minting secrets', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker).inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: { ...headers, authorization: 'Bearer invalid' },
    payload: oneWayRequest
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error.code, 'INVALID_APP_TOKEN');
  assert.equal(broker.calls.length, 0);
});

test('session quota rejects a parallel leg before broker mint and preserves idempotent replay', async () => {
  const broker = new RecordingBroker();
  const current = new Date('2026-07-15T05:00:00.000Z');
  const app = makeApp(broker, false, () => current, [appToken], {
    maxParallelLegs: 1,
    maxSecretMintsPerWindow: 10,
    secretMintWindowMs: 60_000,
    maxDailyLegMinutes: 120
  });
  const first = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const replay = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const limited = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: { ...headers, 'idempotency-key': '0a8eeaf5-c52e-47c4-96c6-8279573e0815' },
    payload: oneWayRequest
  });

  assert.equal(first.statusCode, 201);
  assert.deepEqual(replay.json(), first.json());
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.json().error.code, 'RATE_LIMITED');
  assert.equal(limited.json().error.retryable, true);
  assert.equal(limited.json().error.retryAfterMs, 1_800_000);
  assert.equal(broker.calls.length, 1);
});

test('daily leg-minute quota returns the UTC reset delay before broker mint', async () => {
  const broker = new RecordingBroker();
  let current = new Date('2026-07-15T05:00:00.000Z');
  const app = makeApp(broker, false, () => current, [appToken], {
    maxParallelLegs: 2,
    maxSecretMintsPerWindow: 10,
    secretMintWindowMs: 60_000,
    maxDailyLegMinutes: 30
  });
  await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  current = new Date('2026-07-15T05:30:01.000Z');
  const limited = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: { ...headers, 'idempotency-key': '49a0cb10-ad3a-4853-bec7-aefc8b1929d3' },
    payload: oneWayRequest
  });

  assert.equal(limited.statusCode, 429);
  assert.equal(limited.json().error.retryAfterMs, 3_600_000);
  assert.equal(broker.calls.length, 1);
});

test('session completion is first-write-wins and releases the active-leg quota', async () => {
  const broker = new RecordingBroker();
  const current = new Date('2026-07-15T05:00:00Z');
  const app = makeApp(broker, false, () => current, [appToken], {
    maxParallelLegs: 1,
    maxSecretMintsPerWindow: 10,
    secretMintWindowMs: 60_000,
    maxDailyLegMinutes: 120
  });
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  assert.equal(created.statusCode, 201);
  const sessionId = created.json().sessionId as string;

  const blocked = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: { ...headers, 'idempotency-key': '16d0dd2e-d643-46c8-8231-522cc029fc95' },
    payload: oneWayRequest
  });
  assert.equal(blocked.statusCode, 429);

  const completed = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: headers.authorization },
    payload: completionRequest
  });
  assert.equal(completed.statusCode, 200);
  assert.deepEqual(completed.json(), {
    sessionId,
    status: 'completed',
    completedAt: current.toISOString()
  });

  current.setSeconds(current.getSeconds() + 1);
  const replay = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: headers.authorization },
    payload: { ...completionRequest, result: 'failed', errorCode: 'NETWORK' }
  });
  assert.equal(replay.statusCode, 200);
  assert.deepEqual(replay.json(), completed.json());

  const replacement = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: { ...headers, 'idempotency-key': '1cc047eb-d17e-40e8-864d-989fd9090a2d' },
    payload: oneWayRequest
  });
  assert.equal(replacement.statusCode, 201);
  assert.equal(broker.calls.length, 2);
});

test('session completion remains available under kill switch and hides foreign sessions', async () => {
  const broker = new RecordingBroker();
  const repository = new InMemorySessionRepository();
  const otherToken = 'other-owner-app-token';
  const activeApp = makeApp(
    broker,
    false,
    () => new Date('2026-07-15T05:00:00Z'),
    [appToken, otherToken],
    undefined,
    repository
  );
  const created = await activeApp.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const sessionId = created.json().sessionId as string;

  const foreign = await activeApp.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: `Bearer ${otherToken}` },
    payload: completionRequest
  });
  assert.equal(foreign.statusCode, 404);

  const pausedApp = makeApp(
    broker,
    true,
    () => new Date('2026-07-15T05:00:01Z'),
    [appToken],
    undefined,
    repository
  );
  const completed = await pausedApp.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: headers.authorization },
    payload: completionRequest
  });
  assert.equal(completed.statusCode, 200);
  assert.equal(broker.calls.length, 1);
});

test('completed sessions cannot recreate legs and invalid completion payloads are rejected', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const sessionId = created.json().sessionId as string;

  const invalid = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: headers.authorization },
    payload: { ...completionRequest, activeAudioSeconds: -1 }
  });
  assert.equal(invalid.statusCode, 400);

  const completed = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/complete`,
    headers: { authorization: headers.authorization },
    payload: completionRequest
  });
  assert.equal(completed.statusCode, 200);

  const recreated = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'manual_retry' }
  });
  assert.equal(recreated.statusCode, 404);
  assert.equal(broker.calls.length, 1);
});

test('rolling mint quota applies to recreate and a broker failure rolls its reservation back', async () => {
  let calls = 0;
  const broker: SecretBroker = {
    async createTranslationSecret(input) {
      calls += 1;
      if (calls === 1) {
        throw new SecretBrokerError('SERVICE_UNAVAILABLE', 503, true, 500);
      }
      return {
        value: `ek_quota_${input.targetLanguage}_${calls}_short_lived_secret`,
        expiresAt: new Date('2099-07-15T06:00:00.000Z')
      };
    }
  };
  const current = new Date('2026-07-15T05:00:00.000Z');
  const app = makeApp(broker, false, () => current, [appToken], {
    maxParallelLegs: 2,
    maxSecretMintsPerWindow: 1,
    secretMintWindowMs: 60_000,
    maxDailyLegMinutes: 120
  });
  const firstAttempt = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const limited = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'connection_failed' }
  });

  assert.equal(firstAttempt.statusCode, 503);
  assert.equal(created.statusCode, 201);
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.json().error.retryAfterMs, 60_000);
  assert.equal(calls, 2);
});

test('POST /v1/translation-sessions/{id}/legs creates fresh credentials for the original target', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const originalLeg = created.json().legs[0];

  const response = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'connection_failed' }
  });

  assert.equal(response.statusCode, 201);
  assert.equal(response.json().clientLegId, 'ru-to-en');
  assert.equal(response.json().targetLanguage, 'en');
  assert.notEqual(response.json().legId, originalLeg.legId);
  assert.notEqual(response.json().clientSecret, originalLeg.clientSecret);
  assert.equal(broker.calls.length, 2);
  assert.equal(broker.calls[1]?.targetLanguage, 'en');
  assert.equal(broker.calls[1]?.safetyIdentifier, broker.calls[0]?.safetyIdentifier);
});

test('POST /v1/translation-sessions/{id}/legs blocks recreation when kill switch is active', async () => {
  const broker = new RecordingBroker();
  const response = await makeApp(broker, true).inject({
    method: 'POST',
    url: '/v1/translation-sessions/ts_aaaaaaaaaaaaaaaaaaaaaaaa/legs',
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'connection_failed' }
  });

  assert.equal(response.statusCode, 503);
  assert.equal(response.json().error.code, 'KILL_SWITCH_ACTIVE');
  assert.equal(response.json().error.message, 'Pilot is paused');
  assert.equal(broker.calls.length, 0);
});

test('leg recreation coalesces an idempotent retry without minting another secret', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const request = {
    method: 'POST' as const,
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'disconnected_timeout' }
  };

  const [first, second] = await Promise.all([app.inject(request), app.inject(request)]);

  assert.equal(first.statusCode, 201);
  assert.deepEqual(second.json(), first.json());
  assert.equal(broker.calls.length, 2);
});

test('leg recreation rejects conflicting reuse of an idempotency key', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const url = `/v1/translation-sessions/${created.json().sessionId}/legs`;
  const recreateHeaders = { ...headers, 'idempotency-key': recreateIdempotencyKey };
  await app.inject({
    method: 'POST',
    url,
    headers: recreateHeaders,
    payload: { clientLegId: 'ru-to-en', reason: 'connection_failed' }
  });

  const response = await app.inject({
    method: 'POST',
    url,
    headers: recreateHeaders,
    payload: { clientLegId: 'ru-to-en', reason: 'manual_retry' }
  });

  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'IDEMPOTENCY_CONFLICT');
  assert.equal(broker.calls.length, 2);
});

test('leg recreation hides sessions owned by another installation', async () => {
  const broker = new RecordingBroker();
  const otherToken = 'another-valid-app-token';
  const app = makeApp(broker, false, () => new Date(), [appToken, otherToken]);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  const response = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: {
      authorization: `Bearer ${otherToken}`,
      'idempotency-key': recreateIdempotencyKey
    },
    payload: { clientLegId: 'ru-to-en', reason: 'manual_retry' }
  });

  assert.equal(response.statusCode, 404);
  assert.equal(response.json().error.code, 'RESOURCE_NOT_FOUND');
  assert.equal(broker.calls.length, 1);
});

test('leg recreation rejects an expired app session without minting a secret', async () => {
  const broker = new RecordingBroker();
  let current = new Date('2026-07-14T05:00:00Z');
  const app = makeApp(broker, false, () => current);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  current = new Date('2026-07-14T05:30:01Z');

  const response = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'secret_expired' }
  });

  assert.equal(response.statusCode, 404);
  assert.equal(response.json().error.code, 'RESOURCE_NOT_FOUND');
  assert.equal(broker.calls.length, 1);
});

test('leg recreation rejects an invalid app token before minting a replacement secret', async () => {
  const broker = new RecordingBroker();
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });

  const response = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: {
      authorization: 'Bearer invalid',
      'idempotency-key': recreateIdempotencyKey
    },
    payload: { clientLegId: 'ru-to-en', reason: 'manual_retry' }
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error.code, 'INVALID_APP_TOKEN');
  assert.equal(broker.calls.length, 1);
});

test('leg recreation maps sanitized upstream errors and allows retrying a failed key', async () => {
  let calls = 0;
  const broker: SecretBroker = {
    async createTranslationSecret(input) {
      calls += 1;
      if (calls === 2) {
        throw new SecretBrokerError('RATE_LIMITED', 429, true, 1500);
      }
      return {
        value: `ek_mock_${input.targetLanguage}_${calls}_short_lived_secret`,
        expiresAt: new Date('2099-07-14T05:10:00Z')
      };
    }
  };
  const app = makeApp(broker);
  const created = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers,
    payload: oneWayRequest
  });
  const request = {
    method: 'POST' as const,
    url: `/v1/translation-sessions/${created.json().sessionId}/legs`,
    headers: { ...headers, 'idempotency-key': recreateIdempotencyKey },
    payload: { clientLegId: 'ru-to-en', reason: 'connection_failed' }
  };

  const limited = await app.inject(request);
  const retried = await app.inject(request);

  assert.equal(limited.statusCode, 429);
  assert.deepEqual(
    {
      code: limited.json().error.code,
      retryable: limited.json().error.retryable,
      retryAfterMs: limited.json().error.retryAfterMs
    },
    { code: 'RATE_LIMITED', retryable: true, retryAfterMs: 1500 }
  );
  assert.equal(retried.statusCode, 201);
  assert.equal(calls, 3);
});
