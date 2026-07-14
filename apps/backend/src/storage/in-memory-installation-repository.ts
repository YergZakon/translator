import {
  type InstallationRecord,
  type InstallationRepository
} from '../services/installation-service.js';

function cloneRecord(record: InstallationRecord): InstallationRecord {
  return {
    ...record,
    tokenHash: Buffer.from(record.tokenHash),
    metadata: { ...record.metadata },
    createdAt: new Date(record.createdAt),
    updatedAt: new Date(record.updatedAt),
    lastSeenAt: new Date(record.lastSeenAt),
    tokenExpiresAt:
      record.tokenExpiresAt === null ? null : new Date(record.tokenExpiresAt)
  };
}

export class InMemoryInstallationRepository implements InstallationRepository {
  readonly #byPublicId = new Map<string, InstallationRecord>();

  async registerOrRotate(
    input: Parameters<InstallationRepository['registerOrRotate']>[0]
  ): Promise<{ record: InstallationRecord; created: boolean }> {
    const existing = this.#byPublicId.get(input.installationPublicId);
    if (existing !== undefined) {
      if (existing.status === 'active') {
        existing.tokenHash = Buffer.from(input.tokenHash);
        existing.tokenExpiresAt = input.tokenExpiresAt;
        existing.metadata = { ...input.metadata };
        existing.updatedAt = new Date(input.now);
        existing.lastSeenAt = new Date(input.now);
      }
      return { record: cloneRecord(existing), created: false };
    }

    const record: InstallationRecord = {
      installationId: input.installationId,
      installationPublicId: input.installationPublicId,
      tokenHash: Buffer.from(input.tokenHash),
      status: 'active',
      tokenExpiresAt: input.tokenExpiresAt,
      metadata: { ...input.metadata },
      createdAt: new Date(input.now),
      updatedAt: new Date(input.now),
      lastSeenAt: new Date(input.now)
    };
    this.#byPublicId.set(input.installationPublicId, record);
    return { record: cloneRecord(record), created: true };
  }

  async findActiveByTokenHash(tokenHash: Buffer, now: Date): Promise<InstallationRecord | null> {
    for (const record of this.#byPublicId.values()) {
      if (
        record.status === 'active' &&
        record.tokenHash.equals(tokenHash) &&
        (record.tokenExpiresAt === null || record.tokenExpiresAt > now)
      ) {
        record.lastSeenAt = new Date(now);
        return cloneRecord(record);
      }
    }
    return null;
  }

  forbid(installationPublicId: string): void {
    const record = this.#byPublicId.get(installationPublicId);
    if (record !== undefined) {
      record.status = 'forbidden';
    }
  }

  snapshot(installationPublicId: string): InstallationRecord | null {
    const record = this.#byPublicId.get(installationPublicId);
    return record === undefined ? null : cloneRecord(record);
  }
}
