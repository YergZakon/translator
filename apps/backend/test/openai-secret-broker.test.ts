import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  OpenAISecretBroker,
  SecretBrokerError
} from '../src/services/openai-secret-broker.js';

test('OpenAISecretBroker sends the documented translation secret request and parses provider expiry', async () => {
  let capturedUrl = '';
  let capturedInit: RequestInit | undefined;
  const broker = new OpenAISecretBroker({
    apiKey: 'test-server-api-key',
    fetchImpl: async (input, init) => {
      capturedUrl = String(input);
      capturedInit = init;
      return new Response(
        JSON.stringify({ value: 'ek_short_lived_client_secret', expires_at: 1784005800 }),
        { status: 200, headers: { 'content-type': 'application/json' } }
      );
    }
  });

  const result = await broker.createTranslationSecret({
    model: 'gpt-realtime-translate',
    targetLanguage: 'en',
    safetyIdentifier: 'inst_0123456789abcdef0123456789abcdef'
  });

  assert.equal(
    capturedUrl,
    'https://api.openai.com/v1/realtime/translations/client_secrets'
  );
  assert.equal(capturedInit?.method, 'POST');
  const headers = new Headers(capturedInit?.headers);
  assert.equal(headers.get('authorization'), 'Bearer test-server-api-key');
  assert.equal(
    headers.get('openai-safety-identifier'),
    'inst_0123456789abcdef0123456789abcdef'
  );
  assert.deepEqual(JSON.parse(String(capturedInit?.body)), {
    session: {
      model: 'gpt-realtime-translate',
      audio: { output: { language: 'en' } }
    }
  });
  assert.equal(result.value, 'ek_short_lived_client_secret');
  assert.equal(result.expiresAt.toISOString(), '2026-07-14T05:10:00.000Z');
  assert.equal(JSON.stringify(result).includes('test-server-api-key'), false);
});

test('OpenAISecretBroker maps 429 without exposing the upstream response body', async () => {
  const broker = new OpenAISecretBroker({
    apiKey: 'test-server-api-key',
    fetchImpl: async () =>
      new Response('provider details and secrets must not escape', {
        status: 429,
        headers: { 'retry-after': '1.5' }
      })
  });

  await assert.rejects(
    broker.createTranslationSecret({
      model: 'gpt-realtime-translate',
      targetLanguage: 'ru',
      safetyIdentifier: 'inst_0123456789abcdef0123456789abcdef'
    }),
    (error: unknown) => {
      assert.ok(error instanceof SecretBrokerError);
      assert.equal(error.code, 'RATE_LIMITED');
      assert.equal(error.httpStatus, 429);
      assert.equal(error.retryAfterMs, 1500);
      assert.equal(error.message.includes('provider details'), false);
      return true;
    }
  );
});

test('OpenAISecretBroker rejects malformed success payloads as sanitized upstream failures', async () => {
  const broker = new OpenAISecretBroker({
    apiKey: 'test-server-api-key',
    fetchImpl: async () => new Response(JSON.stringify({ value: 'missing-expiry' }), { status: 200 })
  });

  await assert.rejects(
    broker.createTranslationSecret({
      model: 'gpt-realtime-translate',
      targetLanguage: 'en',
      safetyIdentifier: 'inst_0123456789abcdef0123456789abcdef'
    }),
    (error: unknown) =>
      error instanceof SecretBrokerError && error.code === 'UPSTREAM_SESSION_UNAVAILABLE'
  );
});

test('OpenAISecretBroker maps request aborts to an upstream timeout', async () => {
  const broker = new OpenAISecretBroker({
    apiKey: 'test-server-api-key',
    requestTimeoutMs: 5,
    fetchImpl: async (_input, init) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          const error = new Error('aborted');
          error.name = 'AbortError';
          reject(error);
        });
      })
  });

  await assert.rejects(
    broker.createTranslationSecret({
      model: 'gpt-realtime-translate',
      targetLanguage: 'en',
      safetyIdentifier: 'inst_0123456789abcdef0123456789abcdef'
    }),
    (error: unknown) => error instanceof SecretBrokerError && error.code === 'UPSTREAM_TIMEOUT'
  );
});
