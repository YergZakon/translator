import { Pool } from 'pg';

import { buildApp } from './app.js';
import { loadRuntimeConfig } from './runtime-config.js';
import { OpenAISecretBroker } from './services/openai-secret-broker.js';
import { runMigrations } from './storage/migrations.js';
import { PostgresInstallationRepository } from './storage/postgres-installation-repository.js';

async function main(): Promise<void> {
  const runtime = loadRuntimeConfig();
  const pool = new Pool({
    connectionString: runtime.databaseUrl,
    max: runtime.databasePoolMax
  });

  try {
    await runMigrations(pool);
    const installationRepository = new PostgresInstallationRepository(pool);
    const app = buildApp({
      serviceVersion: runtime.serviceVersion,
      installationRepository,
      safetyIdentifierSecret: runtime.safetyIdentifierSecret,
      secretBroker: new OpenAISecretBroker({
        apiKey: runtime.openAIAPIKey,
        requestTimeoutMs: runtime.openAIRequestTimeoutMs
      }),
      logger: { level: runtime.logLevel }
    });

    let shuttingDown = false;
    const shutdown = async (signal: string): Promise<void> => {
      if (shuttingDown) return;
      shuttingDown = true;
      app.log.info({ signal }, 'Stopping backend');
      await app.close();
      await pool.end();
      process.exit(0);
    };

    process.once('SIGINT', () => void shutdown('SIGINT'));
    process.once('SIGTERM', () => void shutdown('SIGTERM'));
    await app.listen({ host: runtime.host, port: runtime.port });
  } catch (error) {
    const errorName = error instanceof Error ? error.name : 'UnknownError';
    process.stderr.write(`Backend startup failed (${errorName})\n`);
    await pool.end();
    process.exitCode = 1;
  }
}

await main();
