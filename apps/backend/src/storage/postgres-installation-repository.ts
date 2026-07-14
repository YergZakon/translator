import type { Pool } from 'pg';

import {
  type InstallationMetadata,
  type InstallationRecord,
  type InstallationRepository
} from '../services/installation-service.js';

interface InstallationRow {
  installation_id: string;
  installation_public_id: string;
  token_hash: Buffer;
  status: 'active' | 'forbidden';
  token_expires_at: Date | null;
  app_version: string;
  app_build: number;
  os_version: string;
  model_class: 'phone';
  created_at: Date;
  updated_at: Date;
  last_seen_at: Date;
  created?: boolean;
}

function mapRow(row: InstallationRow): InstallationRecord {
  const metadata: InstallationMetadata = {
    appVersion: row.app_version,
    appBuild: row.app_build,
    osVersion: row.os_version,
    modelClass: row.model_class
  };
  return {
    installationId: row.installation_id,
    installationPublicId: row.installation_public_id,
    tokenHash: row.token_hash,
    status: row.status,
    tokenExpiresAt: row.token_expires_at,
    metadata,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastSeenAt: row.last_seen_at
  };
}

export class PostgresInstallationRepository implements InstallationRepository {
  readonly #pool: Pool;

  constructor(pool: Pool) {
    this.#pool = pool;
  }

  async registerOrRotate(
    input: Parameters<InstallationRepository['registerOrRotate']>[0]
  ): Promise<{ record: InstallationRecord; created: boolean }> {
    const result = await this.#pool.query<InstallationRow>(
      `
        INSERT INTO installations (
          installation_id,
          installation_public_id,
          token_hash,
          token_expires_at,
          app_version,
          app_build,
          os_version,
          model_class,
          created_at,
          updated_at,
          last_seen_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9, $9)
        ON CONFLICT (installation_public_id) DO UPDATE SET
          token_hash = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.token_hash
            ELSE installations.token_hash
          END,
          token_expires_at = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.token_expires_at
            ELSE installations.token_expires_at
          END,
          app_version = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.app_version
            ELSE installations.app_version
          END,
          app_build = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.app_build
            ELSE installations.app_build
          END,
          os_version = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.os_version
            ELSE installations.os_version
          END,
          model_class = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.model_class
            ELSE installations.model_class
          END,
          updated_at = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.updated_at
            ELSE installations.updated_at
          END,
          last_seen_at = CASE
            WHEN installations.status = 'active' THEN EXCLUDED.last_seen_at
            ELSE installations.last_seen_at
          END
        RETURNING *, (xmax = 0) AS created
      `,
      [
        input.installationId,
        input.installationPublicId,
        input.tokenHash,
        input.tokenExpiresAt,
        input.metadata.appVersion,
        input.metadata.appBuild,
        input.metadata.osVersion,
        input.metadata.modelClass,
        input.now
      ]
    );
    const row = result.rows[0];
    if (row === undefined) {
      throw new Error('Installation upsert returned no row');
    }
    return { record: mapRow(row), created: row.created === true };
  }

  async findActiveByTokenHash(tokenHash: Buffer, now: Date): Promise<InstallationRecord | null> {
    const result = await this.#pool.query<InstallationRow>(
      `
        UPDATE installations
        SET last_seen_at = $2
        WHERE token_hash = $1
          AND status = 'active'
          AND (token_expires_at IS NULL OR token_expires_at > $2)
        RETURNING *
      `,
      [tokenHash, now]
    );
    const row = result.rows[0];
    return row === undefined ? null : mapRow(row);
  }
}
