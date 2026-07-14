export interface RuntimeConfig {
  host: string;
  port: number;
  logLevel: string;
  serviceVersion: string;
  appTokens: string[];
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

  return {
    host: env.HOST ?? '127.0.0.1',
    port: positiveInteger(env.PORT, 3000),
    logLevel: env.LOG_LEVEL ?? 'info',
    serviceVersion: env.SERVICE_VERSION ?? 'dev',
    appTokens
  };
}
