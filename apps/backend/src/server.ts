import { buildApp } from './app.js';
import { loadRuntimeConfig } from './runtime-config.js';
import { StaticTokenVerifier } from './security/token-verifier.js';

const runtime = loadRuntimeConfig();
const app = buildApp({
  serviceVersion: runtime.serviceVersion,
  tokenVerifier: new StaticTokenVerifier(runtime.appTokens),
  logger: { level: runtime.logLevel }
});

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, 'Stopping backend');
  await app.close();
  process.exit(0);
}

process.once('SIGINT', () => void shutdown('SIGINT'));
process.once('SIGTERM', () => void shutdown('SIGTERM'));

try {
  await app.listen({ host: runtime.host, port: runtime.port });
} catch (error) {
  app.log.error({ errorName: error instanceof Error ? error.name : 'UnknownError' }, 'Startup failed');
  process.exit(1);
}
