export interface RuntimeConfig {
  host: string;
  port: number;
  logLevel: string;
  serviceVersion: string;
  appTokens: string[];
  safetyIdentifierSecret: string;
  openAIAPIKey: string;
  openAIRequestTimeoutMs: number;
}

function positiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535');
  }
  return parsed;
}

export function loadRuntimeConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const appTokens = (env.APP_TOKENS ?? '')
    .split(',')
    .map((token) => token.trim())
    .filter(Boolean);

  if (appTokens.length === 0) {
    throw new Error('APP_TOKENS must contain at least one prototype app token');
  }

  const safetyIdentifierSecret = env.SAFETY_IDENTIFIER_SECRET ?? '';
  if (safetyIdentifierSecret.length < 32) {
    throw new Error('SAFETY_IDENTIFIER_SECRET must contain at least 32 characters');
  }

  const openAIAPIKey = env.OPENAI_API_KEY ?? '';
  if (openAIAPIKey.length === 0) {
    throw new Error('OPENAI_API_KEY is required');
  }

  const openAIRequestTimeoutMs = Number(env.OPENAI_REQUEST_TIMEOUT_MS ?? 8000);
  if (!Number.isInteger(openAIRequestTimeoutMs) || openAIRequestTimeoutMs < 1000 || openAIRequestTimeoutMs > 30000) {
    throw new Error('OPENAI_REQUEST_TIMEOUT_MS must be an integer between 1000 and 30000');
  }

  return {
    host: env.HOST ?? '127.0.0.1',
    port: positiveInteger(env.PORT, 3000),
    logLevel: env.LOG_LEVEL ?? 'info',
    serviceVersion: env.SERVICE_VERSION ?? 'dev',
    appTokens,
    safetyIdentifierSecret,
    openAIAPIKey,
    openAIRequestTimeoutMs
  };
}
