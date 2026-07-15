import { readFileSync } from 'node:fs';

export const telemetryBatchRequestSchema = JSON.parse(
  readFileSync(
    new URL('../../../../contracts/telemetry.schema.json', import.meta.url),
    'utf8'
  )
) as Record<string, unknown>;
