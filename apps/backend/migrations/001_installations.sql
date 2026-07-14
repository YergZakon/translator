CREATE TABLE IF NOT EXISTS installations (
  installation_id text PRIMARY KEY
    CHECK (installation_id ~ '^ins_[A-Za-z0-9]{20,40}$'),
  installation_public_id uuid NOT NULL UNIQUE,
  token_hash bytea NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'forbidden')),
  token_expires_at timestamptz NULL,
  app_version varchar(32) NOT NULL,
  app_build integer NOT NULL CHECK (app_build >= 1),
  os_version varchar(32) NOT NULL,
  model_class varchar(16) NOT NULL CHECK (model_class = 'phone'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS installations_active_token_hash_idx
  ON installations (token_hash)
  WHERE status = 'active';
