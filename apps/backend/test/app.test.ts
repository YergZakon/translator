import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

import { buildApp } from '../src/app.js';
import { StaticTokenVerifier } from '../src/security/token-verifier.js';

const openApps: FastifyInstance[] = [];
const validHeaders = {
  authorization: 'Bearer test-prototype-app-token',
  'x-app-version': '0.1.0',
  'x-app-build': '42'
};

function makeApp(options: Parameters<typeof buildApp>[0] = {}): FastifyInstance {
  const app = buildApp({
    serviceVersion: '0.1.0-test',
    now: () => new Date('2026-07-14T05:00:00.000Z'),
    tokenVerifier: new StaticTokenVerifier(
      ['test-prototype-app-token'],
      'test-safety-identifier-secret-32-characters'
    ),
    ...options
  });
  openApps.push(app);
  return app;
}

afterEach(async () => {
  await Promise.all(openApps.splice(0).map((app) => app.close()));
});

test('GET /v1/health returns minimal ready status without authentication', async () => {
  const response = await makeApp().inject({ method: 'GET', url: '/v1/health' });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    status: 'ok',
    version: '0.1.0-test',
    time: '2026-07-14T05:00:00.000Z'
  });
});

test('GET /v1/health returns 503 when readiness is degraded', async () => {
  const response = await makeApp({ isReady: () => false }).inject({
    method: 'GET',
    url: '/v1/health'
  });
  assert.equal(response.statusCode, 503);
  assert.equal(response.json().status, 'degraded');
});

test('GET /v1/config rejects an invalid app token with the shared error envelope', async () => {
  const response = await makeApp().inject({
    method: 'GET',
    url: '/v1/config',
    headers: { ...validHeaders, authorization: 'Bearer invalid-token' }
  });
  assert.equal(response.statusCode, 401);
  const body = response.json();
  assert.equal(body.error.code, 'INVALID_APP_TOKEN');
  assert.equal(body.error.retryable, false);
  assert.match(body.error.traceId, /^tr_[0-9a-f]{32}$/);
});

test('GET /v1/config returns the accepted contract shape and ETag', async () => {
  const response = await makeApp().inject({
    method: 'GET',
    url: '/v1/config',
    headers: validHeaders
  });
  assert.equal(response.statusCode, 200);
  assert.match(response.headers.etag ?? '', /^"cfg-[0-9a-f]{16}"$/);
  assert.deepEqual(response.json(), {
    version: '2026-07-14.1',
    killSwitch: false,
    killSwitchMessage: null,
    modelAlias: 'gpt-realtime-translate',
    allowedModes: ['one_way_ru_to_en', 'dialogue'],
    allowedTargetLanguages: ['en', 'ru'],
    maxDurationSeconds: 1800,
    reconnectPolicy: {
      maxAttempts: 3,
      backoffMs: [500, 1500, 3000],
      disconnectedGraceMs: 2000
    },
    outputInterruption: { mode: 'duck_and_switch', delayMs: 300 },
    telemetrySampleRate: 1,
    experiments: {
      autoSideDetection: 'control',
      localTranscriptSave: 'disabled'
    }
  });
});

test('GET /v1/config returns 304 for the active ETag', async () => {
  const app = makeApp();
  const first = await app.inject({ method: 'GET', url: '/v1/config', headers: validHeaders });
  const response = await app.inject({
    method: 'GET',
    url: '/v1/config',
    headers: { ...validHeaders, 'if-none-match': first.headers.etag ?? '' }
  });
  assert.equal(response.statusCode, 304);
  assert.equal(response.body, '');
});

test('GET /v1/config maps invalid required headers to a sanitized error', async () => {
  const response = await makeApp().inject({
    method: 'GET',
    url: '/v1/config',
    headers: { ...validHeaders, 'x-app-build': 'not-a-build' }
  });
  assert.equal(response.statusCode, 400);
  const body = response.json();
  assert.equal(body.error.code, 'INVALID_REQUEST');
  assert.equal(body.error.message, 'Request validation failed');
});
