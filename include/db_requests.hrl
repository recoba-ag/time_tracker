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
  "INSERT INTO work_schedules(user_id, start_time, end_time, days, free_schedule, updated_at) "
  "VALUES ($1, $2::time, $3::time, $4::smallint[], $5, NOW()) "
  "ON CONFLICT(user_id) DO UPDATE SET "
  "start_time = EXCLUDED.start_time, "
  "end_time = EXCLUDED.end_time, "
  "days = EXCLUDED.days, "
  "free_schedule = EXCLUDED.free_schedule, "
  "updated_at = NOW()"
>>).

-define(GET_USER_WORK_TIME, <<
  "SELECT start_time::text, end_time::text, days, free_schedule "
  "FROM work_schedules WHERE user_id = $1"
>>).

-define(ADD_USER_EXCLUSION, <<
  "INSERT INTO work_exclusions(user_id, type_exclusion, start_datetime, end_datetime) "
  "VALUES ($1, $2, $3::timestamptz, $4::timestamptz)"
>>).

-define(GET_USER_EXCLUSION, <<
  "SELECT type_exclusion, start_datetime::text, end_datetime::text "
  "FROM work_exclusions "
  "WHERE user_id = $1 "
  "ORDER BY start_datetime DESC"
>>).

-define(GET_HISTORY_BY_USER, <<
  "SELECT card_uid, touched_at::text, event_type "
  "FROM touch_events "
  "WHERE user_id = $1 "
  "ORDER BY touched_at DESC"
>>).

-define(GET_HISTORY, <<
  "SELECT user_id, card_uid, touched_at::text, event_type "
  "FROM touch_events "
  "ORDER BY touched_at DESC "
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
  "SELECT user_id, start_time::text, end_time::text, days, free_schedule "
  "FROM work_schedules WHERE user_id = ANY($1::bigint[])"
>>).

-define(GET_NEXT_EVENT_TYPE_BY_USER, <<
  "SELECT event_type FROM touch_events "
  "WHERE user_id = $1 AND touched_at::date = CURRENT_DATE "
  "ORDER BY touched_at DESC LIMIT 1"
>>).
