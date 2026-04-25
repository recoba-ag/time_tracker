CREATE TABLE IF NOT EXISTS cards (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    card_uid TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS work_schedules (
    user_id BIGINT PRIMARY KEY,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    days SMALLINT[] NOT NULL,
    free_schedule BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS work_exclusions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    type_exclusion TEXT NOT NULL,
    start_datetime TIMESTAMPTZ NOT NULL,
    end_datetime TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS touch_events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    card_uid TEXT NOT NULL,
    touched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type TEXT NOT NULL
);
