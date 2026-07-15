import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadRuntimeConfig } from '../src/runtime-config.js';

const validEnvironment = {
  DATABASE_URL: 'postgres://translator:password@127.0.0.1:5432/translator',
  DATABASE_POOL_MAX: '12',
  SAFETY_IDENTIFIER_SECRET: 'test-safety-identifier-secret-32-characters',
  OPENAI_API_KEY: 'test-placeholder-key'
};

test('runtime config requires PostgreSQL and no longer accepts prototype token bootstrap', () => {
  assert.throws(
    () => loadRuntimeConfig({ ...validEnvironment, DATABASE_URL: '', APP_TOKENS: 'legacy' }),
    /DATABASE_URL is required/
  );
});

test('runtime config parses database pool settings without exposing credentials', () => {
  const config = loadRuntimeConfig(validEnvironment);

  assert.equal(config.databaseUrl, validEnvironment.DATABASE_URL);
  assert.equal(config.databasePoolMax, 12);
  assert.equal(config.quotaMaxParallelLegs, 2);
  assert.equal(config.quotaSecretMintsPerMinute, 8);
  assert.equal(config.quotaDailyLegMinutes, 120);
  assert.equal('appTokens' in config, false);
});

test('runtime config validates explicit quota policy settings', () => {
  const config = loadRuntimeConfig({
    ...validEnvironment,
    QUOTA_MAX_PARALLEL_LEGS: '4',
    QUOTA_SECRET_MINTS_PER_MINUTE: '12',
    QUOTA_DAILY_LEG_MINUTES: '240'
  });

  assert.equal(config.quotaMaxParallelLegs, 4);
  assert.equal(config.quotaSecretMintsPerMinute, 12);
  assert.equal(config.quotaDailyLegMinutes, 240);
  assert.throws(
    () => loadRuntimeConfig({ ...validEnvironment, QUOTA_MAX_PARALLEL_LEGS: '0' }),
    /QUOTA_MAX_PARALLEL_LEGS/
  );
});
