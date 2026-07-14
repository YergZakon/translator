import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

import {
  hashAppToken,
  type InstallationRepository
} from '../services/installation-service.js';

export interface AppIdentity {
  safetyIdentifier: string;
}

export interface TokenVerifier {
  authenticateAuthorizationHeader(header: string | undefined): Promise<AppIdentity | null>;
}

function digest(token: string): Buffer {
  return createHash('sha256').update(token, 'utf8').digest();
}

export class StaticTokenVerifier implements TokenVerifier {
  readonly #entries: Array<{ tokenHash: Buffer; identity: AppIdentity }>;

  constructor(tokens: string[], safetyIdentifierSecret: string) {
    this.#entries = tokens.filter(Boolean).map((token) => ({
      tokenHash: digest(token),
      identity: {
        safetyIdentifier: `inst_${createHmac('sha256', safetyIdentifierSecret)
          .update(token, 'utf8')
          .digest('hex')
          .slice(0, 32)}`
      }
    }));
  }

  async authenticateAuthorizationHeader(header: string | undefined): Promise<AppIdentity | null> {
    if (header === undefined || !header.startsWith('Bearer ')) {
      return null;
    }

    const token = header.slice('Bearer '.length);
    if (token.length === 0) {
      return null;
    }

    const candidate = digest(token);
    const match = this.#entries.find((entry) => timingSafeEqual(candidate, entry.tokenHash));
    return match?.identity ?? null;
  }
}

export class RepositoryTokenVerifier implements TokenVerifier {
  readonly #repository: InstallationRepository;
  readonly #safetyIdentifierSecret: string;
  readonly #now: () => Date;

  constructor(
    repository: InstallationRepository,
    safetyIdentifierSecret: string,
    now: () => Date = () => new Date()
  ) {
    this.#repository = repository;
    this.#safetyIdentifierSecret = safetyIdentifierSecret;
    this.#now = now;
  }

  async authenticateAuthorizationHeader(header: string | undefined): Promise<AppIdentity | null> {
    if (header === undefined || !header.startsWith('Bearer ')) {
      return null;
    }

    const token = header.slice('Bearer '.length);
    if (token.length < 24 || token.length > 2048 || token.includes(' ')) {
      return null;
    }

    const installation = await this.#repository.findActiveByTokenHash(
      hashAppToken(token),
      this.#now()
    );
    if (installation === null) {
      return null;
    }

    return {
      safetyIdentifier: `inst_${createHmac('sha256', this.#safetyIdentifierSecret)
        .update(installation.installationId, 'utf8')
        .digest('hex')
        .slice(0, 32)}`
    };
  }
}
