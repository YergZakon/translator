CREATE OR REPLACE FUNCTION translator_text_array_is_unique(values_to_check text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT count(*) = count(DISTINCT value)
  FROM unnest(values_to_check) AS value
$$;

CREATE TABLE IF NOT EXISTS translation_session_feedback (
  session_id text PRIMARY KEY
    REFERENCES translation_sessions (session_id) ON DELETE CASCADE,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  categories text[] NOT NULL
    CHECK (cardinality(categories) <= 8)
    CHECK (translator_text_array_is_unique(categories))
    CHECK (categories <@ ARRAY[
      'wrong_meaning',
      'missing_content',
      'critical_entity',
      'latency',
      'audio_quality',
      'echo_loop',
      'connection',
      'ui',
      'other'
    ]::text[]),
  store_comment boolean NOT NULL,
  comment_redacted varchar(500),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  CHECK (store_comment OR comment_redacted IS NULL),
  CHECK (updated_at >= created_at)
);

CREATE INDEX IF NOT EXISTS translation_session_feedback_updated_idx
  ON translation_session_feedback (updated_at);
