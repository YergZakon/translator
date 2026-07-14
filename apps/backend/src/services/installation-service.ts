import { createHash, randomBytes, randomUUID } from 'node:crypto';

export interface InstallationMetadata {
  appVersion: string;
  appBuild: number;
  osVersion: string;
  modelClass: 'phone';
}

export interface RegisterInstallationInput extends InstallationMetadata {
  installationPublicId: string;
}

export interface InstallationRegistration {
  statusCode: 200 | 201;
  installationId: string;
  tokenType: 'Bearer';
  appToken: string;
  expiresAt: string | null;
}

export interface InstallationRecord {
  installationId: string;
  installationPublicId: string;
  tokenHash: Buffer;
  status: 'active' | 'forbidden';
  tokenExpiresAt: Date | null;
  metadata: InstallationMetadata;
  createdAt: Date;
  updatedAt: Date;
  lastSeenAt: Date;
}

export interface InstallationRepository {
  registerOrRotate(input: {
    installationPublicId: string;
    installationId: string;
    tokenHash: Buffer;
    tokenExpiresAt: Date | null;
    metadata: InstallationMetadata;
    now: Date;
  }): Promise<{ record: InstallationRecord; created: boolean }>;

  findActiveByTokenHash(tokenHash: Buffer, now: Date): Promise<InstallationRecord | null>;
}

export class InstallationServiceError extends Error {
  constructor(
    readonly code: 'INSTALLATION_FORBIDDEN',
    readonly httpStatus: 403,
    readonly safeMessage: string
  ) {
    super(safeMessage);
    this.name = 'InstallationServiceError';
  }
}

export interface InstallationServiceOptions {
  repository: InstallationRepository;
  now?: () => Date;
  installationIdFactory?: () => string;
  tokenFactory?: () => string;
}

export function hashAppToken(token: string): Buffer {
  return createHash('sha256').update(token, 'utf8').digest();
}

export class InstallationService {
  readonly #repository: InstallationRepository;
  readonly #now: () => Date;
  readonly #installationIdFactory: () => string;
  readonly #tokenFactory: () => string;

  constructor(options: InstallationServiceOptions) {
    this.#repository = options.repository;
    this.#now = options.now ?? (() => new Date());
    this.#installationIdFactory =
      options.installationIdFactory ??
      (() => `ins_${randomUUID().replaceAll('-', '')}`);
    this.#tokenFactory =
      options.tokenFactory ??
      (() => `app_${randomBytes(32).toString('base64url')}`);
  }

  async register(input: RegisterInstallationInput): Promise<InstallationRegistration> {
    const appToken = this.#tokenFactory();
    const now = this.#now();
    const result = await this.#repository.registerOrRotate({
      installationPublicId: input.installationPublicId,
      installationId: this.#installationIdFactory(),
      tokenHash: hashAppToken(appToken),
      tokenExpiresAt: null,
      metadata: {
        appVersion: input.appVersion,
        appBuild: input.appBuild,
        osVersion: input.osVersion,
        modelClass: input.modelClass
      },
      now
    });

    if (result.record.status === 'forbidden') {
      throw new InstallationServiceError(
        'INSTALLATION_FORBIDDEN',
        403,
        'Installation is forbidden'
      );
    }

    return {
      statusCode: result.created ? 201 : 200,
      installationId: result.record.installationId,
      tokenType: 'Bearer',
      appToken,
      expiresAt: result.record.tokenExpiresAt?.toISOString() ?? null
    };
  }
}
