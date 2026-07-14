export type TargetLanguage = 'ru' | 'en';

export interface CreateTranslationSecretInput {
  model: string;
  targetLanguage: TargetLanguage;
  safetyIdentifier: string;
}

export interface TranslationSecret {
  value: string;
  expiresAt: Date;
}

export interface SecretBroker {
  createTranslationSecret(input: CreateTranslationSecretInput): Promise<TranslationSecret>;
}

export type SecretBrokerErrorCode =
  | 'RATE_LIMITED'
  | 'UPSTREAM_SESSION_UNAVAILABLE'
  | 'UPSTREAM_TIMEOUT'
  | 'SERVICE_UNAVAILABLE';

export class SecretBrokerError extends Error {
  constructor(
    readonly code: SecretBrokerErrorCode,
    readonly httpStatus: 429 | 502 | 503 | 504,
    readonly retryable: boolean,
    readonly retryAfterMs?: number
  ) {
    super(code);
    this.name = 'SecretBrokerError';
  }
}

type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export interface OpenAISecretBrokerOptions {
  apiKey: string;
  fetchImpl?: FetchLike;
  requestTimeoutMs?: number;
  baseUrl?: string;
}

function retryAfterMs(response: Response): number | undefined {
  const value = response.headers.get('retry-after');
  if (value === null) {
    return undefined;
  }

  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(Math.round(seconds * 1000), 3_600_000);
  }

  const date = Date.parse(value);
  if (Number.isNaN(date)) {
    return undefined;
  }
  return Math.min(Math.max(date - Date.now(), 0), 3_600_000);
}

function readSecret(payload: unknown): TranslationSecret | null {
  if (typeof payload !== 'object' || payload === null) {
    return null;
  }

  const record = payload as Record<string, unknown>;
  if (
    typeof record.value !== 'string' ||
    record.value.length < 8 ||
    typeof record.expires_at !== 'number' ||
    !Number.isFinite(record.expires_at)
  ) {
    return null;
  }

  const expiresAt = new Date(record.expires_at * 1000);
  if (Number.isNaN(expiresAt.getTime())) {
    return null;
  }
  return { value: record.value, expiresAt };
}

export class OpenAISecretBroker implements SecretBroker {
  readonly #apiKey: string;
  readonly #fetch: FetchLike;
  readonly #requestTimeoutMs: number;
  readonly #endpoint: string;

  constructor(options: OpenAISecretBrokerOptions) {
    this.#apiKey = options.apiKey;
    this.#fetch = options.fetchImpl ?? fetch;
    this.#requestTimeoutMs = options.requestTimeoutMs ?? 8000;
    this.#endpoint = new URL(
      '/v1/realtime/translations/client_secrets',
      options.baseUrl ?? 'https://api.openai.com'
    ).toString();
  }

  async createTranslationSecret(input: CreateTranslationSecretInput): Promise<TranslationSecret> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#requestTimeoutMs);

    try {
      const response = await this.#fetch(this.#endpoint, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${this.#apiKey}`,
          'content-type': 'application/json',
          'openai-safety-identifier': input.safetyIdentifier
        },
        body: JSON.stringify({
          session: {
            model: input.model,
            audio: {
              output: { language: input.targetLanguage }
            }
          }
        }),
        signal: controller.signal
      });

      if (!response.ok) {
        if (response.status === 429) {
          throw new SecretBrokerError('RATE_LIMITED', 429, true, retryAfterMs(response));
        }
        if (response.status === 504) {
          throw new SecretBrokerError('UPSTREAM_TIMEOUT', 504, true);
        }
        if (response.status >= 500) {
          throw new SecretBrokerError('UPSTREAM_SESSION_UNAVAILABLE', 502, true);
        }
        throw new SecretBrokerError('SERVICE_UNAVAILABLE', 503, false);
      }

      const secret = readSecret(await response.json());
      if (secret === null) {
        throw new SecretBrokerError('UPSTREAM_SESSION_UNAVAILABLE', 502, true);
      }
      return secret;
    } catch (error) {
      if (error instanceof SecretBrokerError) {
        throw error;
      }
      if (error instanceof Error && error.name === 'AbortError') {
        throw new SecretBrokerError('UPSTREAM_TIMEOUT', 504, true);
      }
      throw new SecretBrokerError('UPSTREAM_SESSION_UNAVAILABLE', 502, true);
    } finally {
      clearTimeout(timeout);
    }
  }
}

export class UnavailableSecretBroker implements SecretBroker {
  async createTranslationSecret(): Promise<TranslationSecret> {
    throw new SecretBrokerError('SERVICE_UNAVAILABLE', 503, false);
  }
}
