CREATE TABLE IF NOT EXISTS translation_quota_daily_usage (
  owner_safety_identifier text NOT NULL
    CHECK (owner_safety_identifier ~ '^inst_[0-9a-f]{32}$'),
  quota_date date NOT NULL,
  reserved_leg_minutes integer NOT NULL DEFAULT 0
    CHECK (reserved_leg_minutes >= 0),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (owner_safety_identifier, quota_date)
);

CREATE TABLE IF NOT EXISTS translation_quota_mint_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_safety_identifier text NOT NULL
    CHECK (owner_safety_identifier ~ '^inst_[0-9a-f]{32}$'),
  operation varchar(16) NOT NULL
    CHECK (operation IN ('create_session', 'recreate_leg')),
  secret_mints integer NOT NULL
    CHECK (secret_mints > 0),
  created_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS translation_quota_mint_events_owner_time_idx
  ON translation_quota_mint_events (owner_safety_identifier, created_at);
