import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

export interface AppIdentity {
  safetyIdentifier: string;
}

export interface TokenVerifier {
  authenticateAuthorizationHeader(header: string | undefined): AppIdentity | null;
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

  authenticateAuthorizationHeader(header: string | undefined): AppIdentity | null {
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
