export interface RuntimeConfig {
  host: string;
  port: number;
  logLevel: string;
  serviceVersion: string;
  databaseUrl: string;
  databasePoolMax: number;
  safetyIdentifierSecret: string;
  openAIAPIKey: string;
  openAIRequestTimeoutMs: number;
}

function positiveInteger(
  name: string,
  value: string | undefined,
  fallback: number,
  maximum: number
): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }
  return parsed;
}

export function loadRuntimeConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const databaseUrl = env.DATABASE_URL ?? '';
  if (databaseUrl.length === 0) {
    throw new Error('DATABASE_URL is required');
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
    port: positiveInteger('PORT', env.PORT, 3000, 65535),
    logLevel: env.LOG_LEVEL ?? 'info',
    serviceVersion: env.SERVICE_VERSION ?? 'dev',
    databaseUrl,
    databasePoolMax: positiveInteger('DATABASE_POOL_MAX', env.DATABASE_POOL_MAX, 10, 100),
    safetyIdentifierSecret,
    openAIAPIKey,
    openAIRequestTimeoutMs
  };
}
