CREATE TABLE IF NOT EXISTS technical_telemetry_events (
  owner_safety_identifier text NOT NULL
    CHECK (owner_safety_identifier ~ '^inst_[0-9a-f]{32}$'),
  event_id uuid NOT NULL,
  session_id text,
  leg_id text,
  event_type varchar(64) NOT NULL
    CHECK (event_type IN (
      'app_opened',
      'session_start_tapped',
      'session_create_requested',
      'session_secret_received',
      'webrtc_offer_created',
      'webrtc_connected',
      'mic_enabled_changed',
      'first_input_transcript',
      'first_output_transcript',
      'first_remote_audio',
      'network_degraded',
      'reconnect_attempt',
      'reconnect_result',
      'audio_route_changed',
      'session_completed',
      'feedback_submitted'
    )),
  monotonic_ms bigint NOT NULL CHECK (monotonic_ms >= 0),
  properties jsonb NOT NULL CHECK (jsonb_typeof(properties) = 'object'),
  payload_fingerprint bytea NOT NULL CHECK (octet_length(payload_fingerprint) = 32),
  client_sent_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL,
  PRIMARY KEY (owner_safety_identifier, event_id),
  CHECK (session_id IS NULL OR session_id ~ '^ts_[A-Za-z0-9]{20,40}$'),
  CHECK (leg_id IS NULL OR leg_id ~ '^leg_[A-Za-z0-9]{20,40}$'),
  CHECK (leg_id IS NULL OR session_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS technical_telemetry_owner_received_idx
  ON technical_telemetry_events (owner_safety_identifier, received_at DESC);

CREATE INDEX IF NOT EXISTS technical_telemetry_session_received_idx
  ON technical_telemetry_events (session_id, received_at DESC)
  WHERE session_id IS NOT NULL;
