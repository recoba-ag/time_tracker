-define(ASSIGN_CARD, <<
    "INSERT INTO cards(user_id, card_uid) VALUES ($1, $2) "
    "ON CONFLICT(card_uid) DO NOTHING "
    "RETURNING user_id, card_uid"
>>).

-define(CHECK_ASSIGNED_CARD, <<
    "SELECT user_id, card_uid "
    "FROM cards "
    "WHERE card_uid = $1"
>>).

-define(DELETE_CARD, <<
    "DELETE FROM cards "
    "WHERE card_uid = $1 "
    "RETURNING user_id, card_uid"
>>).

-define(GET_CARDS_BY_USER, <<
    "SELECT card_uid FROM cards "
    "WHERE user_id = $1 "
    "ORDER BY id ASC"
>>).

-define(DELETE_ALL_USER_CARDS, <<
    "DELETE FROM cards "
    "WHERE user_id = $1 "
    "RETURNING card_uid"
>>).

-define(GET_USER_BY_CARD, <<
    "SELECT user_id FROM cards "
    "WHERE card_uid = $1"
>>).

-define(TOUCH_CARD, <<
    "INSERT INTO touch_events(user_id, card_uid, event_type) VALUES ($1, $2, $3)"
>>).

-define(SET_USER_WORK_TIME, <<
    "INSERT INTO work_schedules(user_id, start_time, end_time, days, free_schedule, schedule_timezone, updated_at) "
    "VALUES ($1, $2::time, $3::time, $4::smallint[], $5, $6, NOW()) "
    "ON CONFLICT(user_id) DO UPDATE SET "
    "start_time = EXCLUDED.start_time, "
    "end_time = EXCLUDED.end_time, "
    "days = EXCLUDED.days, "
    "free_schedule = EXCLUDED.free_schedule, "
    "schedule_timezone = EXCLUDED.schedule_timezone, "
    "updated_at = NOW()"
>>).

-define(GET_USER_WORK_TIME, <<
    "SELECT start_time::text, end_time::text, days, free_schedule, schedule_timezone "
    "FROM work_schedules WHERE user_id = $1"
>>).

-define(ADD_USER_EXCLUSION, <<
    "INSERT INTO work_exclusions(user_id, type_exclusion, start_datetime, end_datetime) "
    "VALUES ($1, $2, $3::timestamptz, $4::timestamptz)"
>>).

-define(GET_USER_EXCLUSION, <<
    "SELECT e.type_exclusion, "
    "to_char(timezone(COALESCE(w.schedule_timezone, 'UTC'), e.start_datetime), 'YYYY-MM-DD\"T\"HH24:MI:SS'), "
    "to_char(timezone(COALESCE(w.schedule_timezone, 'UTC'), e.end_datetime), 'YYYY-MM-DD\"T\"HH24:MI:SS'), "
    "COALESCE(w.schedule_timezone, 'UTC') "
    "FROM work_exclusions e "
    "LEFT JOIN work_schedules w ON w.user_id = e.user_id "
    "WHERE e.user_id = $1 "
    "ORDER BY e.start_datetime DESC"
>>).

-define(GET_HISTORY_BY_USER, <<
    "SELECT t.card_uid, "
    "to_char(timezone(COALESCE(w.schedule_timezone, 'UTC'), t.touched_at), 'YYYY-MM-DD\"T\"HH24:MI:SS'), "
    "t.event_type "
    "FROM touch_events t "
    "LEFT JOIN work_schedules w ON w.user_id = t.user_id "
    "WHERE t.user_id = $1 "
    "ORDER BY t.touched_at DESC"
>>).

-define(GET_HISTORY, <<
    "SELECT t.user_id, t.card_uid, "
    "to_char(timezone(COALESCE(w.schedule_timezone, 'UTC'), t.touched_at), 'YYYY-MM-DD\"T\"HH24:MI:SS'), "
    "t.event_type "
    "FROM touch_events t "
    "LEFT JOIN work_schedules w ON w.user_id = t.user_id "
    "ORDER BY t.touched_at DESC "
    "LIMIT $1"
>>).

-define(GET_HISTORY_EPOCH, <<
    "SELECT user_id, event_type, (EXTRACT(EPOCH FROM touched_at))::float8 AS ts "
    "FROM touch_events "
    "ORDER BY touched_at DESC "
    "LIMIT $1"
>>).

-define(GET_MIN_TOUCHED_AT_FOR_USER, <<
    "SELECT MIN(touched_at) FROM touch_events WHERE user_id = $1"
>>).

-define(GET_MIN_TOUCHED_AT_FOR_USERS, <<
    "SELECT user_id, MIN(touched_at) FROM touch_events "
    "WHERE user_id = ANY($1::bigint[]) GROUP BY user_id"
>>).

-define(GET_TOUCHES_FOR_USER_IN_RANGE, <<
    "SELECT event_type, touched_at FROM touch_events "
    "WHERE user_id = $1 AND touched_at >= $2::timestamptz AND touched_at <= $3::timestamptz "
    "ORDER BY touched_at ASC"
>>).

-define(GET_TOUCHES_FOR_USERS_IN_RANGE, <<
    "SELECT user_id, event_type, touched_at FROM touch_events "
    "WHERE user_id = ANY($1::bigint[]) AND touched_at >= $2::timestamptz AND touched_at <= $3::timestamptz "
    "ORDER BY user_id, touched_at ASC"
>>).

-define(GET_EXCLUSIONS_FOR_USER_IN_RANGE, <<
    "SELECT type_exclusion, start_datetime, end_datetime "
    "FROM work_exclusions "
    "WHERE user_id = $1 AND end_datetime >= $2::timestamptz AND start_datetime <= $3::timestamptz"
>>).

-define(GET_EXCLUSIONS_FOR_USERS_IN_RANGE, <<
    "SELECT user_id, type_exclusion, start_datetime, end_datetime "
    "FROM work_exclusions "
    "WHERE user_id = ANY($1::bigint[]) AND end_datetime >= $2::timestamptz AND start_datetime <= $3::timestamptz"
>>).

-define(GET_WORK_SCHEDULES_FOR_USERS, <<
    "SELECT user_id, start_time::text, end_time::text, days, free_schedule, schedule_timezone "
    "FROM work_schedules WHERE user_id = ANY($1::bigint[])"
>>).

-define(PG_TIMEZONE_EXISTS, <<
    "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = $1::text)"
>>).

-define(WINDOW_LOCAL_DATES_FROM_UNIX, <<
    "SELECT timezone($3::text, to_timestamp($1::double precision))::date AS d0, "
    "timezone($3::text, to_timestamp($2::double precision))::date AS d1"
>>).

-define(SHIFT_BOUNDS_LOCAL_SERIES, <<
    "SELECT wd::date, "
    "extract(epoch FROM ((wd::date)::timestamp + ($3::bigint * interval '1 second')) AT TIME ZONE $4::text)::double precision AS ss, "
    "extract(epoch FROM ((wd::date)::timestamp + ($5::bigint * interval '1 second')) AT TIME ZONE $4::text)::double precision AS se "
    "FROM generate_series($1::date, $2::date, interval '1 day') AS wd"
>>).

-define(TOUCH_EVENTS_LOCAL_DATES, <<
    "SELECT timezone($2::text, to_timestamp(epoch))::date "
    "FROM unnest($1::double precision[]) AS epoch"
>>).

-define(LOCAL_DATE_AT_UNIX, <<
    "SELECT timezone($2::text, to_timestamp($1::double precision))::date"
>>).

-define(WALL_PAIR_TO_TIMESTAMPTZ, <<
    "SELECT "
    "(make_timestamp($1::int, $2::int, $3::int, $4::int, $5::int, $6::float8)::timestamp AT TIME ZONE $13::text) AS ts0, "
    "(make_timestamp($7::int, $8::int, $9::int, $10::int, $11::int, $12::float8)::timestamp AT TIME ZONE $13::text) AS ts1"
>>).

-define(GET_NEXT_EVENT_TYPE_BY_USER, <<
    "SELECT event_type FROM touch_events "
    "WHERE user_id = $1 AND touched_at::date = CURRENT_DATE "
    "ORDER BY touched_at DESC LIMIT 1"
>>).
