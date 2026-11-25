CREATE TABLE IF NOT EXISTS device_shares (
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'controller')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (device_id, user_id)
);

CREATE INDEX IF NOT EXISTS device_shares_user_id_idx
    ON device_shares (user_id, device_id);
