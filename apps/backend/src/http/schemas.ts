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

export const registerInstallationHeadersSchema = Type.Object(
  {
    'x-app-attestation': Type.Optional(Type.String({ maxLength: 8192 }))
  },
  { additionalProperties: true }
);

export const registerInstallationRequestSchema = Type.Object(
  {
    installationPublicId: Type.String({ format: 'uuid' }),
    app: Type.Object(
      {
        version: Type.String({ maxLength: 32 }),
        build: Type.Integer({ minimum: 1 })
      },
      { additionalProperties: false }
    ),
    device: Type.Object(
      {
        osVersion: Type.String({ maxLength: 32 }),
        modelClass: Type.Literal('phone')
      },
      { additionalProperties: false }
    )
  },
  { additionalProperties: false }
);

export const registerInstallationResponseSchema = Type.Object(
  {
    installationId: Type.String({ pattern: '^ins_[A-Za-z0-9]{20,40}$' }),
    tokenType: Type.Literal('Bearer'),
    appToken: Type.String({ minLength: 24, maxLength: 2048 }),
    expiresAt: Type.Union([Type.String({ format: 'date-time' }), Type.Null()])
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

const translationModeSchema = Type.Union([
  Type.Literal('one_way_ru_to_en'),
  Type.Literal('dialogue')
]);

const targetLanguageSchema = Type.Union([Type.Literal('ru'), Type.Literal('en')]);

export const createSessionHeadersSchema = Type.Object(
  {
    'idempotency-key': Type.String({ format: 'uuid' })
  },
  { additionalProperties: true }
);

export const createSessionRequestSchema = Type.Object(
  {
    mode: translationModeSchema,
    sourceLocaleHint: Type.Optional(
      Type.Union([
        Type.String({ pattern: '^[a-z]{2}(-[A-Z]{2})?$' }),
        Type.Null()
      ])
    ),
    legs: Type.Array(
      Type.Object(
        {
          clientLegId: Type.String({ pattern: '^[a-z0-9][a-z0-9-]{1,39}$' }),
          targetLanguage: targetLanguageSchema
        },
        { additionalProperties: false }
      ),
      { minItems: 1, maxItems: 2 }
    ),
    app: Type.Object(
      {
        version: Type.String({ maxLength: 32 }),
        build: Type.Integer({ minimum: 1 })
      },
      { additionalProperties: false }
    ),
    device: Type.Object(
      {
        osVersion: Type.String({ maxLength: 32 }),
        modelClass: Type.Literal('phone')
      },
      { additionalProperties: false }
    )
  },
  { additionalProperties: false }
);

const sessionPolicySchema = Type.Object(
  {
    maxReconnectAttempts: Type.Integer({ minimum: 0, maximum: 5 }),
    reconnectBackoffMs: Type.Array(Type.Integer({ minimum: 0, maximum: 30000 }), {
      maxItems: 5
    }),
    outputInterruption: Type.Union([
      Type.Literal('finish_current'),
      Type.Literal('duck_and_switch'),
      Type.Literal('hard_cut')
    ]),
    outputInterruptionDelayMs: Type.Integer({ minimum: 0, maximum: 5000 }),
    telemetrySampleRate: Type.Number({ minimum: 0, maximum: 1 })
  },
  { additionalProperties: false }
);

export const translationLegCredentialsSchema = Type.Object(
  {
    legId: Type.String({ pattern: '^leg_[A-Za-z0-9]{20,40}$' }),
    clientLegId: Type.String({ pattern: '^[a-z0-9][a-z0-9-]{1,39}$' }),
    targetLanguage: targetLanguageSchema,
    provider: Type.Literal('openai'),
    model: Type.String({ maxLength: 80 }),
    clientSecret: Type.String({ minLength: 8, maxLength: 2048 }),
    expiresAt: Type.String({ format: 'date-time' }),
    callsUrl: Type.String({ format: 'uri' })
  },
  { additionalProperties: false }
);

export const translationSessionSchema = Type.Object(
  {
    sessionId: Type.String({ pattern: '^ts_[A-Za-z0-9]{20,40}$' }),
    traceId: Type.String({ pattern: '^tr_[A-Za-z0-9]{20,40}$' }),
    expiresAt: Type.String({ format: 'date-time' }),
    maxDurationSeconds: Type.Integer({ minimum: 60, maximum: 3600 }),
    legs: Type.Array(translationLegCredentialsSchema, { minItems: 1, maxItems: 2 }),
    policy: sessionPolicySchema
  },
  { additionalProperties: false }
);

export const recreateTranslationLegParamsSchema = Type.Object(
  {
    sessionId: Type.String({ pattern: '^ts_[A-Za-z0-9]{20,40}$' })
  },
  { additionalProperties: false }
);

export const recreateTranslationLegRequestSchema = Type.Object(
  {
    clientLegId: Type.String({ pattern: '^[a-z0-9][a-z0-9-]{1,39}$' }),
    reason: Type.Union([
      Type.Literal('connection_failed'),
      Type.Literal('disconnected_timeout'),
      Type.Literal('secret_expired'),
      Type.Literal('manual_retry')
    ])
  },
  { additionalProperties: false }
);

export const completeTranslationSessionRequestSchema = Type.Object(
  {
    result: Type.Union([
      Type.Literal('completed'),
      Type.Literal('user_stopped'),
      Type.Literal('failed'),
      Type.Literal('killed_by_config')
    ]),
    durationSeconds: Type.Integer({ minimum: 0, maximum: 7200 }),
    activeAudioSeconds: Type.Integer({ minimum: 0, maximum: 7200 }),
    turns: Type.Integer({ minimum: 0 }),
    reconnects: Type.Integer({ minimum: 0 }),
    finalRouteType: Type.Optional(
      Type.Union([
        Type.Literal('built_in'),
        Type.Literal('speaker'),
        Type.Literal('bluetooth'),
        Type.Literal('wired'),
        Type.Literal('usb'),
        Type.Literal('unknown'),
        Type.Null()
      ])
    ),
    errorCode: Type.Optional(Type.Union([Type.String({ maxLength: 80 }), Type.Null()]))
  },
  { additionalProperties: false }
);

export const completeTranslationSessionResponseSchema = Type.Object(
  {
    sessionId: Type.String({ pattern: '^ts_[A-Za-z0-9]{20,40}$' }),
    status: Type.Literal('completed'),
    completedAt: Type.String({ format: 'date-time' })
  },
  { additionalProperties: false }
);

const feedbackCategorySchema = Type.Union([
  Type.Literal('wrong_meaning'),
  Type.Literal('missing_content'),
  Type.Literal('critical_entity'),
  Type.Literal('latency'),
  Type.Literal('audio_quality'),
  Type.Literal('echo_loop'),
  Type.Literal('connection'),
  Type.Literal('ui'),
  Type.Literal('other')
]);

export const feedbackRequestSchema = Type.Object(
  {
    rating: Type.Integer({ minimum: 1, maximum: 5 }),
    categories: Type.Array(feedbackCategorySchema, {
      maxItems: 8,
      uniqueItems: true
    }),
    comment: Type.Optional(Type.Union([Type.String({ maxLength: 500 }), Type.Null()])),
    consentFlags: Type.Object(
      {
        storeComment: Type.Boolean()
      },
      { additionalProperties: false }
    )
  },
  { additionalProperties: false }
);

export const feedbackResponseSchema = Type.Object(
  {
    sessionId: Type.String({ pattern: '^ts_[A-Za-z0-9]{20,40}$' }),
    updatedAt: Type.String({ format: 'date-time' })
  },
  { additionalProperties: false }
);

export const telemetryBatchResponseSchema = Type.Object(
  {
    accepted: Type.Integer({ minimum: 0 }),
    rejected: Type.Integer({ minimum: 0 }),
    rejectedEventIds: Type.Array(Type.String({ format: 'uuid' }), { maxItems: 100 })
  },
  { additionalProperties: false }
);
