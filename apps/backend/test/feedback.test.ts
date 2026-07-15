import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

import { buildApp } from '../src/app.js';
import { defaultAppConfig } from '../src/domain/app-config.js';
import { StaticTokenVerifier } from '../src/security/token-verifier.js';
import { redactFeedbackComment } from '../src/services/feedback-service.js';
import type { SecretBroker } from '../src/services/openai-secret-broker.js';
import { InMemorySessionRepository } from '../src/storage/in-memory-session-repository.js';

const apps: FastifyInstance[] = [];
const appToken = 'feedback-owner-app-token';
const otherToken = 'feedback-other-owner-token';
const authorization = { authorization: `Bearer ${appToken}` };
const createHeaders = {
  ...authorization,
  'idempotency-key': '8f5d6754-c57a-4a44-9f0d-02da2172c11f'
};
const createRequest = {
  mode: 'one_way_ru_to_en',
  sourceLocaleHint: 'ru-KZ',
  legs: [{ clientLegId: 'ru-to-en', targetLanguage: 'en' }],
  app: { version: '0.1.0', build: 42 },
  device: { osVersion: '26.4', modelClass: 'phone' }
};
const feedbackRequest = {
  rating: 3,
  categories: ['wrong_meaning', 'latency'],
  comment: 'Contact person@example.com or +7 777 123 45 67; token sk_test_secret_12345678',
  consentFlags: { storeComment: true }
};

const broker: SecretBroker = {
  async createTranslationSecret() {
    return {
      value: 'ek_feedback_short_lived_secret',
      expiresAt: new Date('2099-07-15T06:00:00.000Z')
    };
  }
};

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
});

function makeApp(
  repository: InMemorySessionRepository,
  now: () => Date,
  killSwitch = false
): FastifyInstance {
  let sequence = 0;
  const config = structuredClone(defaultAppConfig);
  config.killSwitch = killSwitch;
  const app = buildApp({
    tokenVerifier: new StaticTokenVerifier(
      [appToken, otherToken],
      'feedback-test-safety-secret-32-characters'
    ),
    appConfig: config,
    secretBroker: broker,
    sessionRepository: repository,
    now,
    sessionIdFactory: (prefix) => `${prefix}_${String(++sequence).padStart(24, 'a')}`
  });
  apps.push(app);
  return app;
}

async function createSession(app: FastifyInstance): Promise<string> {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/translation-sessions',
    headers: createHeaders,
    payload: createRequest
  });
  assert.equal(response.statusCode, 201);
  return response.json().sessionId as string;
}

test('feedback comment redaction removes direct identifiers and secret-shaped values', () => {
  const redacted = redactFeedbackComment(
    'person@example.com\u0000 +7 777 123 45 67 sk-proj-secret12345678 https://example.com/private'
  );
  assert.equal(redacted.includes('person@example.com'), false);
  assert.equal(redacted.includes('777 123'), false);
  assert.equal(redacted.includes('sk-proj-secret'), false);
  assert.equal(redacted.includes('example.com/private'), false);
  assert.equal(redacted.includes('\u0000'), false);
  assert.match(redacted, /\[email\].*\[phone\].*\[token\].*\[url\]/);
});

test('POST feedback creates and replaces one owner-scoped record under kill switch', async () => {
  const repository = new InMemorySessionRepository();
  let current = new Date('2026-07-15T07:00:00.000Z');
  const activeApp = makeApp(repository, () => current);
  const sessionId = await createSession(activeApp);

  const first = await activeApp.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/feedback`,
    headers: authorization,
    payload: feedbackRequest
  });
  assert.equal(first.statusCode, 200);
  assert.deepEqual(first.json(), {
    sessionId,
    updatedAt: current.toISOString()
  });

  current = new Date('2026-07-15T07:00:01.000Z');
  const pausedApp = makeApp(repository, () => current, true);
  const replaced = await pausedApp.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/feedback`,
    headers: authorization,
    payload: {
      rating: 5,
      categories: [],
      comment: feedbackRequest.comment,
      consentFlags: { storeComment: false }
    }
  });
  assert.equal(replaced.statusCode, 200);
  assert.deepEqual(replaced.json(), {
    sessionId,
    updatedAt: current.toISOString()
  });
});

test('POST feedback hides foreign and unknown sessions behind the same 404', async () => {
  const repository = new InMemorySessionRepository();
  const app = makeApp(repository, () => new Date('2026-07-15T07:00:00.000Z'));
  const sessionId = await createSession(app);

  for (const [target, token] of [
    [sessionId, otherToken],
    ['ts_zzzzzzzzzzzzzzzzzzzzzzzz', appToken]
  ] as const) {
    const response = await app.inject({
      method: 'POST',
      url: `/v1/translation-sessions/${target}/feedback`,
      headers: { authorization: `Bearer ${token}` },
      payload: feedbackRequest
    });
    assert.equal(response.statusCode, 404);
    assert.equal(response.json().error.code, 'RESOURCE_NOT_FOUND');
  }
});

test('POST feedback enforces auth and the accepted closed request schema', async () => {
  const repository = new InMemorySessionRepository();
  const app = makeApp(repository, () => new Date('2026-07-15T07:00:00.000Z'));
  const sessionId = await createSession(app);

  const invalidToken = await app.inject({
    method: 'POST',
    url: `/v1/translation-sessions/${sessionId}/feedback`,
    headers: { authorization: 'Bearer invalid' },
    payload: feedbackRequest
  });
  assert.equal(invalidToken.statusCode, 401);

  for (const payload of [
    { ...feedbackRequest, rating: 0 },
    { ...feedbackRequest, categories: ['latency', 'latency'] },
    { ...feedbackRequest, categories: ['wrong_name'] },
    { ...feedbackRequest, unexpected: true }
  ]) {
    const response = await app.inject({
      method: 'POST',
      url: `/v1/translation-sessions/${sessionId}/feedback`,
      headers: authorization,
      payload
    });
    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error.code, 'INVALID_REQUEST');
  }
});
