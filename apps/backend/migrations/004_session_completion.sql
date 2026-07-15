ALTER TABLE translation_sessions
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS completion_result varchar(32),
  ADD COLUMN IF NOT EXISTS duration_seconds integer,
  ADD COLUMN IF NOT EXISTS active_audio_seconds integer,
  ADD COLUMN IF NOT EXISTS turns integer,
  ADD COLUMN IF NOT EXISTS reconnects integer,
  ADD COLUMN IF NOT EXISTS final_route_type varchar(16),
  ADD COLUMN IF NOT EXISTS completion_error_code varchar(80);

ALTER TABLE translation_sessions
  ADD CONSTRAINT translation_sessions_completion_result_check
    CHECK (completion_result IS NULL OR completion_result IN (
      'completed', 'user_stopped', 'failed', 'killed_by_config'
    )),
  ADD CONSTRAINT translation_sessions_duration_check
    CHECK (duration_seconds IS NULL OR duration_seconds BETWEEN 0 AND 7200),
  ADD CONSTRAINT translation_sessions_active_audio_check
    CHECK (active_audio_seconds IS NULL OR active_audio_seconds BETWEEN 0 AND 7200),
  ADD CONSTRAINT translation_sessions_turns_check
    CHECK (turns IS NULL OR turns >= 0),
  ADD CONSTRAINT translation_sessions_reconnects_check
    CHECK (reconnects IS NULL OR reconnects >= 0),
  ADD CONSTRAINT translation_sessions_final_route_check
    CHECK (final_route_type IS NULL OR final_route_type IN (
      'built_in', 'speaker', 'bluetooth', 'wired', 'usb', 'unknown'
    )),
  ADD CONSTRAINT translation_sessions_completion_error_code_check
    CHECK (completion_error_code IS NULL OR length(completion_error_code) <= 80),
  ADD CONSTRAINT translation_sessions_completion_shape_check
    CHECK (
      (
        completed_at IS NULL
        AND completion_result IS NULL
        AND duration_seconds IS NULL
        AND active_audio_seconds IS NULL
        AND turns IS NULL
        AND reconnects IS NULL
        AND final_route_type IS NULL
        AND completion_error_code IS NULL
      ) OR (
        completed_at IS NOT NULL
        AND completed_at >= created_at
        AND completion_result IS NOT NULL
        AND duration_seconds IS NOT NULL
        AND active_audio_seconds IS NOT NULL
        AND turns IS NOT NULL
        AND reconnects IS NOT NULL
      )
    );

CREATE INDEX IF NOT EXISTS translation_sessions_owner_uncompleted_idx
  ON translation_sessions (owner_safety_identifier, active_until)
  WHERE completed_at IS NULL;
