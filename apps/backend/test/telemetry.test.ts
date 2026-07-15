import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { afterEach, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

import { buildApp } from '../src/app.js';
import type { TokenVerifier } from '../src/security/token-verifier.js';
import { InMemoryTelemetryRepository } from '../src/storage/in-memory-telemetry-repository.js';

const fixturePath = new URL('../../../contracts/examples/telemetry-batch.request.json', import.meta.url);
const owner = 'inst_0123456789abcdef0123456789abcdef';
const authorization = { authorization: 'Bearer telemetry-test-token-1234567890' };
const openApps: FastifyInstance[] = [];

const tokenVerifier: TokenVerifier = {
  async authenticateAuthorizationHeader(header) {
    return header === authorization.authorization ? { safetyIdentifier: owner } : null;
  }
};

async function fixture(): Promise<Record<string, unknown>> {
  return JSON.parse(await readFile(fixturePath, 'utf8')) as Record<string, unknown>;
}

function makeApp(repository = new InMemoryTelemetryRepository()): FastifyInstance {
  const app = buildApp({
    tokenVerifier,
    telemetryRepository: repository,
    now: () => new Date('2026-07-15T11:00:00.000Z')
  });
  openApps.push(app);
  return app;
}

afterEach(async () => {
  await Promise.all(openApps.splice(0).map((app) => app.close()));
});

test('POST telemetry authenticates and returns accepted/rejected event counts', async () => {
  const body = await fixture();
  const events = body.events as Array<Record<string, unknown>>;
  const scoped = events[1]!;
  const repository = new InMemoryTelemetryRepository([
    {
      safetyIdentifier: owner,
      sessionId: String(scoped.sessionId),
      legIds: [String(scoped.legId)]
    }
  ]);
  const app = makeApp(repository);

  const unauthorized = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    payload: body
  });
  assert.equal(unauthorized.statusCode, 401);
  assert.equal(unauthorized.json().error.code, 'INVALID_APP_TOKEN');

  const first = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: authorization,
    payload: body
  });
  assert.equal(first.statusCode, 202);
  assert.deepEqual(first.json(), { accepted: 2, rejected: 0, rejectedEventIds: [] });

  const replay = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: authorization,
    payload: body
  });
  assert.equal(replay.statusCode, 202);
  assert.deepEqual(replay.json(), { accepted: 2, rejected: 0, rejectedEventIds: [] });

  const conflicting = structuredClone(body);
  const conflictingEvents = conflicting.events as Array<Record<string, unknown>>;
  conflictingEvents[0]!.properties = {
    ...(conflictingEvents[0]!.properties as Record<string, unknown>),
    build: 43
  };
  const conflict = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: authorization,
    payload: conflicting
  });
  assert.equal(conflict.statusCode, 202);
  assert.deepEqual(conflict.json(), {
    accepted: 1,
    rejected: 1,
    rejectedEventIds: [conflictingEvents[0]!.eventId]
  });
});

test('POST telemetry rejects foreign scopes per event without exposing ownership', async () => {
  const body = await fixture();
  const events = body.events as Array<Record<string, unknown>>;
  const app = makeApp();

  const response = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: authorization,
    payload: body
  });
  assert.equal(response.statusCode, 202);
  assert.deepEqual(response.json(), {
    accepted: 1,
    rejected: 1,
    rejectedEventIds: [events[1]!.eventId]
  });
});

test('POST telemetry rejects forbidden content before storage and enforces body limit', async () => {
  const body = await fixture();
  const events = body.events as Array<Record<string, unknown>>;
  const forbidden = structuredClone(body);
  const forbiddenEvents = forbidden.events as Array<Record<string, unknown>>;
  forbiddenEvents[0]!.properties = {
    ...(forbiddenEvents[0]!.properties as Record<string, unknown>),
    transcript: 'must not be accepted'
  };
  const app = makeApp();

  const invalid = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: authorization,
    payload: forbidden
  });
  assert.equal(invalid.statusCode, 400);
  assert.equal(invalid.json().error.code, 'INVALID_REQUEST');

  const oversized = await app.inject({
    method: 'POST',
    url: '/v1/telemetry/batch',
    headers: { ...authorization, 'content-type': 'application/json' },
    payload: JSON.stringify({ ...body, ignored: 'x'.repeat(300_000) })
  });
  assert.equal(oversized.statusCode, 413);
  assert.equal(oversized.json().error.code, 'PAYLOAD_TOO_LARGE');
  assert.equal(events.length, 2);
});
