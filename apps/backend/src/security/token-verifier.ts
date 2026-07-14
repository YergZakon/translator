import { createHash, timingSafeEqual } from 'node:crypto';

export interface TokenVerifier {
  verifyAuthorizationHeader(header: string | undefined): boolean;
}

function digest(token: string): Buffer {
  return createHash('sha256').update(token, 'utf8').digest();
}

export class StaticTokenVerifier implements TokenVerifier {
  readonly #tokenHashes: Buffer[];

  constructor(tokens: string[]) {
    this.#tokenHashes = tokens.filter(Boolean).map(digest);
  }

  verifyAuthorizationHeader(header: string | undefined): boolean {
    if (header === undefined || !header.startsWith('Bearer ')) {
      return false;
    }

    const token = header.slice('Bearer '.length);
    if (token.length === 0) {
      return false;
    }

    const candidate = digest(token);
    return this.#tokenHashes.some((expected) => timingSafeEqual(candidate, expected));
  }
}
