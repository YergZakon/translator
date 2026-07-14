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

const apps: FastifyInstance[] = [];
const appToken = 'test-prototype-app-token';
const idempotencyKey = '8f5d6754-c57a-4a44-9f0d-02da2172c11f';
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

class RecordingBroker implements SecretBroker {
  readonly calls: CreateTranslationSecretInput[] = [];

  async createTranslationSecret(input: CreateTranslationSecretInput): Promise<TranslationSecret> {
    this.calls.push(input);
    return {
      value: `ek_mock_${input.targetLanguage}_short_lived_secret`,
      expiresAt: new Date(input.targetLanguage === 'en' ? '2099-07-14T05:10:00Z' : '2099-07-14T05:09:30Z')
    };
  }
}

function makeApp(broker: SecretBroker, killSwitch = false): FastifyInstance {
  let id = 0;
  const config = structuredClone(defaultAppConfig);
  config.killSwitch = killSwitch;
  config.killSwitchMessage = killSwitch ? 'Pilot is paused' : null;
  const app = buildApp({
    serviceVersion: '0.1.0-test',
    appConfig: config,
    tokenVerifier: new StaticTokenVerifier(
      [appToken],
      'test-safety-identifier-secret-32-characters'
    ),
    secretBroker: broker,
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
  assert.equal(body.legs[0].clientSecret, 'ek_mock_en_short_lived_secret');
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
