CREATE TABLE IF NOT EXISTS translation_sessions (
  session_id text PRIMARY KEY
    CHECK (session_id ~ '^ts_[A-Za-z0-9]{20,40}$'),
  owner_safety_identifier text NOT NULL
    CHECK (owner_safety_identifier ~ '^inst_[0-9a-f]{32}$'),
  model varchar(128) NOT NULL CHECK (length(model) > 0),
  active_until timestamptz NOT NULL,
  created_at timestamptz NOT NULL,
  CHECK (active_until > created_at)
);

CREATE INDEX IF NOT EXISTS translation_sessions_owner_active_idx
  ON translation_sessions (owner_safety_identifier, active_until);

CREATE TABLE IF NOT EXISTS translation_session_legs (
  session_id text NOT NULL
    REFERENCES translation_sessions (session_id) ON DELETE CASCADE,
  client_leg_id varchar(40) NOT NULL
    CHECK (client_leg_id ~ '^[a-z0-9][a-z0-9-]{1,39}$'),
  leg_id text NOT NULL
    CHECK (leg_id ~ '^leg_[A-Za-z0-9]{20,40}$'),
  target_language varchar(2) NOT NULL
    CHECK (target_language IN ('ru', 'en')),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (session_id, client_leg_id)
);

CREATE TABLE IF NOT EXISTS translation_session_idempotency (
  operation varchar(16) NOT NULL
    CHECK (operation IN ('create_session', 'recreate_leg')),
  owner_safety_identifier text NOT NULL
    CHECK (owner_safety_identifier ~ '^inst_[0-9a-f]{32}$'),
  scope_id text NOT NULL,
  idempotency_key uuid NOT NULL,
  request_fingerprint bytea NOT NULL
    CHECK (octet_length(request_fingerprint) = 32),
  response_iv bytea NOT NULL
    CHECK (octet_length(response_iv) = 12),
  response_auth_tag bytea NOT NULL
    CHECK (octet_length(response_auth_tag) = 16),
  response_ciphertext bytea NOT NULL
    CHECK (octet_length(response_ciphertext) > 0),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (operation, owner_safety_identifier, scope_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS translation_session_idempotency_expiry_idx
  ON translation_session_idempotency (expires_at);
