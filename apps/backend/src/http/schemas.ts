import { Type } from '@sinclair/typebox';

const reconnectPolicySchema = Type.Object(
  {
    maxAttempts: Type.Integer({ minimum: 0, maximum: 5 }),
    backoffMs: Type.Array(Type.Integer({ minimum: 0, maximum: 30000 }), {
      minItems: 0,
      maxItems: 5
    }),
    disconnectedGraceMs: Type.Integer({ minimum: 0, maximum: 30000 })
  },
  { additionalProperties: false }
);

const outputInterruptionSchema = Type.Object(
  {
    mode: Type.Union([
      Type.Literal('finish_current'),
      Type.Literal('duck_and_switch'),
      Type.Literal('hard_cut')
    ]),
    delayMs: Type.Integer({ minimum: 0, maximum: 5000 })
  },
  { additionalProperties: false }
);

export const appConfigSchema = Type.Object(
  {
    version: Type.String({ maxLength: 64 }),
    killSwitch: Type.Boolean(),
    killSwitchMessage: Type.Union([Type.String({ maxLength: 240 }), Type.Null()]),
    modelAlias: Type.String({ maxLength: 80 }),
    allowedModes: Type.Array(
      Type.Union([Type.Literal('one_way_ru_to_en'), Type.Literal('dialogue')]),
      {
        minItems: 1,
        uniqueItems: true
      }
    ),
    allowedTargetLanguages: Type.Array(Type.Union([Type.Literal('en'), Type.Literal('ru')]), {
      minItems: 1,
      uniqueItems: true
    }),
    maxDurationSeconds: Type.Integer({ minimum: 60, maximum: 3600 }),
    reconnectPolicy: reconnectPolicySchema,
    outputInterruption: outputInterruptionSchema,
    telemetrySampleRate: Type.Number({ minimum: 0, maximum: 1 }),
    experiments: Type.Record(Type.String(), Type.String({ maxLength: 64 }))
  },
  { additionalProperties: false }
);

export const healthResponseSchema = Type.Object(
  {
    status: Type.Union([Type.Literal('ok'), Type.Literal('degraded')]),
    version: Type.String({ maxLength: 64 }),
    time: Type.String({ format: 'date-time' })
  },
  { additionalProperties: false }
);

export const errorEnvelopeSchema = Type.Object(
  {
    error: Type.Object(
      {
        code: Type.Union([
          Type.Literal('INVALID_REQUEST'),
          Type.Literal('INVALID_APP_TOKEN'),
          Type.Literal('INSTALLATION_FORBIDDEN'),
          Type.Literal('RESOURCE_NOT_FOUND'),
          Type.Literal('IDEMPOTENCY_CONFLICT'),
          Type.Literal('PARALLEL_SESSION_LIMIT'),
          Type.Literal('UNSUPPORTED_CONFIGURATION'),
          Type.Literal('QUOTA_EXCEEDED'),
          Type.Literal('RATE_LIMITED'),
          Type.Literal('PAYLOAD_TOO_LARGE'),
          Type.Literal('UPSTREAM_SESSION_UNAVAILABLE'),
          Type.Literal('UPSTREAM_TIMEOUT'),
          Type.Literal('KILL_SWITCH_ACTIVE'),
          Type.Literal('SERVICE_UNAVAILABLE'),
          Type.Literal('INTERNAL_ERROR')
        ]),
        message: Type.String({ maxLength: 240 }),
        retryable: Type.Boolean(),
        retryAfterMs: Type.Optional(
          Type.Union([Type.Integer({ minimum: 0, maximum: 3600000 }), Type.Null()])
        ),
        traceId: Type.String({ pattern: '^tr_[A-Za-z0-9]{20,40}$' })
      },
      { additionalProperties: false }
    )
  },
  { additionalProperties: false }
);

export const configHeadersSchema = Type.Object(
  {
    'x-app-version': Type.String({ minLength: 1, maxLength: 32 }),
    'x-app-build': Type.String({ pattern: '^[1-9][0-9]*$' }),
    'if-none-match': Type.Optional(Type.String())
  },
  { additionalProperties: true }
);
