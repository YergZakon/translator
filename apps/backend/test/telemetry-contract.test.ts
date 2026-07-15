import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import Fastify from 'fastify';

const schemaPath = new URL('../../../contracts/telemetry.schema.json', import.meta.url);
const fixturePath = new URL('../../../contracts/examples/telemetry-batch.request.json', import.meta.url);
const openAPIPath = new URL('../../../contracts/openapi.yaml', import.meta.url);

const acceptedFeedbackCategories = [
  'wrong_meaning',
  'missing_content',
  'critical_entity',
  'latency',
  'audio_quality',
  'echo_loop',
  'connection',
  'ui',
  'other'
] as const;

async function makeValidator() {
  const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
  const app = Fastify({ ajv: { customOptions: { removeAdditional: false } } });
  app.post('/validate', { schema: { body: schema } }, async (_request, reply) => {
    await reply.code(204).send();
  });
  return app;
}

test('TEL-01 fixture satisfies the closed telemetry v1 schema', async () => {
  const app = await makeValidator();
  const fixture = JSON.parse(await readFile(fixturePath, 'utf8'));

  try {
    const response = await app.inject({ method: 'POST', url: '/validate', payload: fixture });
    assert.equal(response.statusCode, 204);
  } finally {
    await app.close();
  }
});

test('TEL-01 rejects content, identifiers and unknown fields outside the allowlist', async () => {
  const app = await makeValidator();
  const base = JSON.parse(await readFile(fixturePath, 'utf8'));
  const event = base.events[1];

  const forbiddenPayloads = [
    { ...base, events: [{ ...event, transcript: 'forbidden' }] },
    { ...base, events: [{ ...event, properties: { ...event.properties, transcript: 'forbidden' } }] },
    { ...base, events: [{ ...event, properties: { ...event.properties, audio: 'forbidden' } }] },
    { ...base, events: [{ ...event, properties: { ...event.properties, sdp: 'forbidden' } }] },
    { ...base, events: [{ ...event, properties: { ...event.properties, authorization: 'forbidden' } }] },
    { ...base, events: [{ ...event, properties: { ...event.properties, installation_id_hash: 'forbidden' } }] },
    {
      ...base,
      events: [{ ...event, sessionId: null }]
    },
    {
      ...base,
      events: [
        {
          ...event,
          properties: { ms_from_speech_start: 940 }
        }
      ]
    }
  ];

  try {
    for (const payload of forbiddenPayloads) {
      const response = await app.inject({ method: 'POST', url: '/validate', payload });
      assert.equal(response.statusCode, 400);
    }
  } finally {
    await app.close();
  }
});

test('TEL-01 enforces event-specific enums, ranges and batch bounds', async () => {
  const app = await makeValidator();
  const base = JSON.parse(await readFile(fixturePath, 'utf8'));

  const invalidPayloads = [
    { ...base, schemaVersion: '2.0' },
    { ...base, events: [] },
    { ...base, events: Array.from({ length: 101 }, () => base.events[0]) },
    {
      ...base,
      events: [
        {
          eventId: 'not-a-uuid',
          sessionId: null,
          legId: null,
          type: 'app_opened',
          monotonicMs: -1,
          properties: { app_version: '0.1.0', build: 0, os_major: 26 }
        }
      ]
    },
    {
      ...base,
      events: [
        {
          eventId: 'd2719cc5-ad3c-4f26-9307-108d0b591482',
          sessionId: 'ts_0123456789abcdefghijklmn',
          legId: null,
          type: 'feedback_submitted',
          monotonicMs: 9000,
          properties: { rating: 6, categories: ['latency', 'latency'] }
        }
      ]
    }
  ];

  try {
    for (const payload of invalidPayloads) {
      const response = await app.inject({ method: 'POST', url: '/validate', payload });
      assert.equal(response.statusCode, 400);
    }
  } finally {
    await app.close();
  }
});

test('TEL-02 feedback telemetry categories exactly match the accepted Feedback API taxonomy', async () => {
  const app = await makeValidator();
  const openAPI = await readFile(openAPIPath, 'utf8');
  const feedbackRequest = openAPI.match(/    FeedbackRequest:\r?\n([\s\S]*?)        comment:/)?.[1];
  assert.ok(feedbackRequest, 'FeedbackRequest category block must remain discoverable');

  const openAPICategories = [...feedbackRequest.matchAll(/^              - ([a-z_]+)$/gm)].map(
    ([, category]) => category
  );
  assert.deepEqual(openAPICategories, acceptedFeedbackCategories);

  const baseEvent = {
    eventId: 'd2719cc5-ad3c-4f26-9307-108d0b591482',
    sessionId: 'ts_0123456789abcdefghijklmn',
    legId: null,
    type: 'feedback_submitted',
    monotonicMs: 9000
  };
  const baseBatch = {
    schemaVersion: '1.0',
    sentAt: '2026-07-15T09:50:00Z'
  };

  try {
    for (const category of acceptedFeedbackCategories) {
      const response = await app.inject({
        method: 'POST',
        url: '/validate',
        payload: {
          ...baseBatch,
          events: [{ ...baseEvent, properties: { rating: 5, categories: [category] } }]
        }
      });
      assert.equal(response.statusCode, 204, `accepted Feedback API category ${category}`);
    }

    for (const category of ['wrong_number', 'wrong_name', 'omission', 'echo']) {
      const response = await app.inject({
        method: 'POST',
        url: '/validate',
        payload: {
          ...baseBatch,
          events: [{ ...baseEvent, properties: { rating: 2, categories: [category] } }]
        }
      });
      assert.equal(response.statusCode, 400, `obsolete telemetry-only category ${category}`);
    }
  } finally {
    await app.close();
  }
});
