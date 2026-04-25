-module(time_tracker_service).

-export([
    assign_card/2,
    delete_card/1,
    list_cards_by_user/1,
    delete_all_cards_by_user/1,
    touch_card/1,
    set_work_time/5,
    get_work_time/1,
    add_exclusion/4,
    get_exclusion/1,
    history_by_user/1,
    history/1,
    statistics_by_user/2,
    statistics/1
]).

assign_card(UserId, CardUid) ->
    InsertSql = <<"INSERT INTO cards(user_id, card_uid) VALUES ($1, $2)
                   ON CONFLICT(card_uid) DO NOTHING
                   RETURNING user_id, card_uid">>,
    case rows_result(time_tracker_db:query(InsertSql, [UserId, CardUid])) of
        {ok, [{DbUserId, DbCardUid}]} ->
            {ok, #{card_uid => DbCardUid, user_id => DbUserId}};
        {ok, []} ->
            ExistingSql = <<"SELECT user_id, card_uid FROM cards WHERE card_uid = $1">>,
            case rows_result(time_tracker_db:query(ExistingSql, [CardUid])) of
                {ok, [{UserId, DbCardUid}]} ->
                    {ok, #{card_uid => DbCardUid, user_id => UserId}};
                {ok, [{_ExistingUserId, _DbCardUid}]} ->
                    {error, card_already_assigned, <<"This card is already assigned to another user">>};
                {ok, []} ->
                    {error, internal_error, <<"Card assignment state changed unexpectedly">>};
                {ok, _} ->
                    {error, internal_error, <<"Unexpected DB result">>};
                {error, Reason1} ->
                    db_error(Reason1)
            end;
        {ok, _} ->
            {error, internal_error, <<"Unexpected DB result">>};
        {error, Reason2} ->
            db_error(Reason2)
    end.

delete_card(CardUid) ->
    Sql = <<"DELETE FROM cards WHERE card_uid = $1 RETURNING user_id, card_uid">>,
    case rows_result(time_tracker_db:query(Sql, [CardUid])) of
        {ok, [{UserId, DbCardUid}]} -> {ok, #{card_uid => DbCardUid, user_id => UserId}};
        {ok, []} -> {error, not_found, <<"Card not found">>};
        {error, Reason} -> db_error(Reason)
    end.

list_cards_by_user(UserId) ->
    Sql = <<"SELECT card_uid FROM cards WHERE user_id = $1 ORDER BY id ASC">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, Reason} ->
            db_error(Reason)
    end.

delete_all_cards_by_user(UserId) ->
    Sql = <<"DELETE FROM cards WHERE user_id = $1 RETURNING card_uid">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, Reason} ->
            db_error(Reason)
    end.

touch_card(CardUid) ->
    UserSql = <<"SELECT user_id FROM cards WHERE card_uid = $1">>,
    case rows_result(time_tracker_db:query(UserSql, [CardUid])) of
        {ok, [{UserId}]} ->
            EventType = next_event_type(UserId),
            InsertSql = <<"INSERT INTO touch_events(user_id, card_uid, event_type) VALUES ($1, $2, $3)">>,
            case exec_result(time_tracker_db:execute(InsertSql, [UserId, CardUid, EventType])) of
                ok -> {ok, #{card_uid => CardUid, user_id => UserId, event_type => EventType}};
                {error, Reason1} -> db_error(Reason1)
            end;
        {ok, []} -> {error, not_found, <<"Card is not assigned">>};
        {error, Reason2} -> db_error(Reason2)
    end.

set_work_time(UserId, StartTime, EndTime, Days, Free) ->
    Sql = <<"INSERT INTO work_schedules(user_id, start_time, end_time, days, free_schedule, updated_at)
             VALUES ($1, $2::time, $3::time, $4::smallint[], $5, NOW())
             ON CONFLICT(user_id) DO UPDATE SET
             start_time = EXCLUDED.start_time,
             end_time = EXCLUDED.end_time,
             days = EXCLUDED.days,
             free_schedule = EXCLUDED.free_schedule,
             updated_at = NOW()">>,
    case exec_result(time_tracker_db:execute(Sql, [UserId, StartTime, EndTime, Days, Free])) of
        ok -> {ok, #{user_id => UserId}};
        {error, Reason} -> db_error(Reason)
    end.

get_work_time(UserId) ->
    Sql = <<"SELECT start_time::text, end_time::text, days, free_schedule
             FROM work_schedules WHERE user_id = $1">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, [{StartTime, EndTime, Days, Free}]} ->
            {ok, #{
                user_id => UserId,
                start_time => StartTime,
                end_time => EndTime,
                days => Days,
                free_schedule => Free
            }};
        {ok, []} ->
            {error, not_found, <<"Schedule not found">>};
        {error, Reason} ->
            db_error(Reason)
    end.

add_exclusion(UserId, Type, StartDt, EndDt) ->
    Sql = <<"INSERT INTO work_exclusions(user_id, type_exclusion, start_datetime, end_datetime)
             VALUES ($1, $2, $3::timestamptz, $4::timestamptz)">>,
    case exec_result(time_tracker_db:execute(Sql, [UserId, Type, StartDt, EndDt])) of
        ok -> {ok, #{user_id => UserId}};
        {error, Reason} -> db_error(Reason)
    end.

get_exclusion(UserId) ->
    Sql = <<"SELECT type_exclusion, start_datetime::text, end_datetime::text
             FROM work_exclusions WHERE user_id = $1 ORDER BY start_datetime DESC">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, Rows} ->
            Ex = [#{type_exclusion => T, start_datetime => S, end_datetime => E} || {T, S, E} <- Rows],
            {ok, #{user_id => UserId, exclusions => Ex}};
        {error, Reason} ->
            db_error(Reason)
    end.

history_by_user(UserId) ->
    Sql = <<"SELECT card_uid, touched_at::text, event_type
             FROM touch_events WHERE user_id = $1 ORDER BY touched_at DESC">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, Rows} ->
            Hist = [#{card_uid => C, touched_at => T, event_type => E} || {C, T, E} <- Rows],
            {ok, #{user_id => UserId, history => Hist}};
        {error, Reason} ->
            db_error(Reason)
    end.

history(Limit) ->
    Sql = <<"SELECT user_id, card_uid, touched_at::text, event_type
             FROM touch_events ORDER BY touched_at DESC LIMIT $1">>,
    case rows_result(time_tracker_db:query(Sql, [Limit])) of
        {ok, Rows} ->
            GroupedHist = grouped_history_by_user(Rows),
            {ok, #{history => GroupedHist}};
        {error, Reason} ->
            db_error(Reason)
    end.

statistics_by_user(UserId, PeriodBin) ->
    StartSec = time_tracker_time:period_start(period_atom(PeriodBin)),
    StartDt = calendar:gregorian_seconds_to_datetime(StartSec),
    StartText = fmt_datetime(StartDt),
    Sql = <<"SELECT event_type, COUNT(*) FROM touch_events
             WHERE user_id = $1 AND touched_at >= $2::timestamptz
             GROUP BY event_type">>,
    case rows_result(time_tracker_db:query(Sql, [UserId, StartText])) of
        {ok, Rows} ->
            InCnt = count_event(<<"in">>, Rows),
            OutCnt = count_event(<<"out">>, Rows),
            Stats = #{
                user_id => UserId,
                period => PeriodBin,
                worked_days => erlang:min(InCnt, OutCnt),
                late_without_reason => 0,
                late_with_reason => 0,
                early_without_reason => 0,
                early_with_reason => 0
            },
            {ok, Stats};
        {error, Reason} ->
            db_error(Reason)
    end.

statistics(Limit) ->
    Sql = <<"SELECT user_id, COUNT(*) FROM touch_events GROUP BY user_id ORDER BY user_id ASC LIMIT $1">>,
    case rows_result(time_tracker_db:query(Sql, [Limit])) of
        {ok, Rows} ->
            Summary = [#{user_id => U, touches => Cnt} || {U, Cnt} <- Rows],
            {ok, #{summary => Summary}};
        {error, Reason} ->
            db_error(Reason)
    end.

grouped_history_by_user(Rows) ->
    Grouped = lists:foldl(
        fun({UserId, CardUid, TouchedAt, EventType}, Acc) ->
            Event = #{card_uid => CardUid, touched_at => TouchedAt, event_type => EventType},
            maps:update_with(UserId, fun(Events) -> [Event | Events] end, [Event], Acc)
        end,
        #{},
        Rows
    ),
    UserIds = lists:sort(maps:keys(Grouped)),
    [
        #{
            user_id => UserId,
            history => lists:reverse(maps:get(UserId, Grouped))
        }
     || UserId <- UserIds
    ].

period_atom(<<"week">>) -> week;
period_atom(<<"month">>) -> month;
period_atom(<<"year">>) -> year;
period_atom(<<"all">>) -> all;
period_atom(_) -> month.

count_event(Type, Rows) ->
    case lists:keyfind(Type, 1, Rows) of
        false -> 0;
        {_, Cnt} -> Cnt
    end.

next_event_type(UserId) ->
    Sql = <<"SELECT event_type FROM touch_events
             WHERE user_id = $1 AND touched_at::date = CURRENT_DATE
             ORDER BY touched_at DESC LIMIT 1">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, [{<<"in">>}]} -> <<"out">>;
        {ok, [{<<"out">>}]} -> <<"in">>;
        _ -> <<"in">>
    end.

fmt_datetime({Date, Time}) ->
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", tuple_to_list(Date) ++ tuple_to_list(Time))).

db_error(Reason) ->
    logger:error("Database error: ~p", [Reason]),
    {error, db_error, <<"Database operation failed">>}.

rows_result({ok, _Count, _Cols, Rows}) when is_list(Rows) ->
    {ok, Rows};
rows_result({ok, _Count, Rows}) when is_list(Rows) ->
    {ok, Rows};
rows_result({ok, _Count}) ->
    {ok, []};
rows_result({error, _} = Error) ->
    Error;
rows_result(Other) ->
    {error, {unexpected_db_result, Other}}.

exec_result({ok, _Count}) ->
    ok;
exec_result({ok, _Count, _Cols, _Rows}) ->
    ok;
exec_result({ok, _Count, _Rows}) ->
    ok;
exec_result({error, _} = Error) ->
    Error;
exec_result(Other) ->
    {error, {unexpected_db_result, Other}}.
