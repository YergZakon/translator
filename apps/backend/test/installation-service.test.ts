import assert from 'node:assert/strict';
import { test } from 'node:test';

import { RepositoryTokenVerifier } from '../src/security/token-verifier.js';
import {
  InstallationService,
  InstallationServiceError
} from '../src/services/installation-service.js';
import { InMemoryInstallationRepository } from '../src/storage/in-memory-installation-repository.js';

const publicId = '45bbdc50-594a-4c35-8b46-5d72c2dfed1a';
const metadata = {
  installationPublicId: publicId,
  appVersion: '0.1.0',
  appBuild: 42,
  osVersion: '18.5',
  modelClass: 'phone' as const
};

test('registration stores only a token hash and authenticates the returned token', async () => {
  const repository = new InMemoryInstallationRepository();
  const token = 'app_first_high_entropy_token_1234567890';
  const service = new InstallationService({
    repository,
    now: () => new Date('2026-07-14T08:00:00Z'),
    installationIdFactory: () => 'ins_012345678901234567890123',
    tokenFactory: () => token
  });

  const registration = await service.register(metadata);

  assert.equal(registration.statusCode, 201);
  assert.equal(registration.appToken, token);
  assert.equal(registration.expiresAt, null);
  const stored = repository.snapshot(publicId);
  assert.ok(stored);
  assert.notEqual(stored.tokenHash.toString('utf8'), token);
  assert.equal(JSON.stringify(stored).includes(token), false);

  const verifier = new RepositoryTokenVerifier(
    repository,
    'test-safety-identifier-secret-32-characters',
    () => new Date('2026-07-14T08:00:01Z')
  );
  const identity = await verifier.authenticateAuthorizationHeader(`Bearer ${token}`);
  assert.match(identity?.safetyIdentifier ?? '', /^inst_[0-9a-f]{32}$/);
});

test('recovery rotates the token, rejects the old token, and preserves identity', async () => {
  const repository = new InMemoryInstallationRepository();
  const tokens = [
    'app_first_high_entropy_token_1234567890',
    'app_second_high_entropy_token_123456789'
  ];
  const service = new InstallationService({
    repository,
    installationIdFactory: () => 'ins_012345678901234567890123',
    tokenFactory: () => tokens.shift()!
  });
  const verifier = new RepositoryTokenVerifier(
    repository,
    'test-safety-identifier-secret-32-characters'
  );

  const first = await service.register(metadata);
  const firstIdentity = await verifier.authenticateAuthorizationHeader(
    `Bearer ${first.appToken}`
  );
  const second = await service.register({ ...metadata, appBuild: 43 });
  const oldIdentity = await verifier.authenticateAuthorizationHeader(
    `Bearer ${first.appToken}`
  );
  const secondIdentity = await verifier.authenticateAuthorizationHeader(
    `Bearer ${second.appToken}`
  );

  assert.equal(first.statusCode, 201);
  assert.equal(second.statusCode, 200);
  assert.equal(second.installationId, first.installationId);
  assert.equal(oldIdentity, null);
  assert.deepEqual(secondIdentity, firstIdentity);
  assert.equal(repository.snapshot(publicId)?.metadata.appBuild, 43);
});

test('forbidden installation cannot rotate or authenticate', async () => {
  const repository = new InMemoryInstallationRepository();
  const service = new InstallationService({
    repository,
    installationIdFactory: () => 'ins_012345678901234567890123',
    tokenFactory: () => 'app_forbidden_high_entropy_token_123456'
  });
  const first = await service.register(metadata);
  repository.forbid(publicId);

  await assert.rejects(
    service.register(metadata),
    (error: unknown) =>
      error instanceof InstallationServiceError &&
      error.code === 'INSTALLATION_FORBIDDEN'
  );

  const verifier = new RepositoryTokenVerifier(
    repository,
    'test-safety-identifier-secret-32-characters'
  );
  assert.equal(
    await verifier.authenticateAuthorizationHeader(`Bearer ${first.appToken}`),
    null
  );
});
