-module(time_tracker_service).

-export([handle/2]).

handle(<<"/card/assign">>, Req) ->
    with_required([<<"user_id">>, <<"card_uid">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        CardUid = maps:get(<<"card_uid">>, Req),
        Sql = <<"INSERT INTO cards(user_id, card_uid) VALUES ($1, $2)
                 ON CONFLICT(card_uid) DO UPDATE SET user_id = EXCLUDED.user_id
                 RETURNING user_id, card_uid">>,
        case rows_result(time_tracker_db:query(Sql, [UserId, CardUid])) of
            {ok, [{DbUserId, DbCardUid}]} -> ok_json(#{card_uid => DbCardUid, user_id => DbUserId});
            {ok, _} -> err_json(internal_error, <<"Unexpected DB result">>);
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/card/delete">>, Req) ->
    with_required([<<"card_uid">>], Req, fun() ->
        CardUid = maps:get(<<"card_uid">>, Req),
        Sql = <<"DELETE FROM cards WHERE card_uid = $1 RETURNING user_id, card_uid">>,
        case rows_result(time_tracker_db:query(Sql, [CardUid])) of
            {ok, [{UserId, DbCardUid}]} -> ok_json(#{card_uid => DbCardUid, user_id => UserId});
            {ok, []} -> err_json(not_found, <<"Card not found">>);
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/card/list_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Sql = <<"SELECT card_uid FROM cards WHERE user_id = $1 ORDER BY id ASC">>,
        case rows_result(time_tracker_db:query(Sql, [UserId])) of
            {ok, Rows} ->
                Cards = [CardUid || {CardUid} <- Rows],
                ok_json(#{user_id => UserId, cards => Cards});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/card/delete_all_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Sql = <<"DELETE FROM cards WHERE user_id = $1 RETURNING card_uid">>,
        case rows_result(time_tracker_db:query(Sql, [UserId])) of
            {ok, Rows} ->
                Cards = [CardUid || {CardUid} <- Rows],
                ok_json(#{user_id => UserId, cards => Cards});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/card/touch">>, Req) ->
    with_required([<<"card_uid">>], Req, fun() ->
        CardUid = maps:get(<<"card_uid">>, Req),
        UserSql = <<"SELECT user_id FROM cards WHERE card_uid = $1">>,
        case rows_result(time_tracker_db:query(UserSql, [CardUid])) of
            {ok, [{UserId}]} ->
                EventType = next_event_type(UserId),
                InsertSql = <<"INSERT INTO touch_events(user_id, card_uid, event_type) VALUES ($1, $2, $3)">>,
                case exec_result(time_tracker_db:execute(InsertSql, [UserId, CardUid, EventType])) of
                    ok -> ok_json(#{card_uid => CardUid, user_id => UserId, event_type => EventType});
                    {error, Reason1} -> db_error(Reason1)
                end;
            {ok, []} -> err_json(not_found, <<"Card is not assigned">>);
            {error, Reason2} -> db_error(Reason2)
        end
    end);
handle(<<"/work_time/set">>, Req) ->
    with_required([<<"user_id">>, <<"start_time">>, <<"end_time">>, <<"days">>, <<"free_schedule">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        StartTime = maps:get(<<"start_time">>, Req),
        EndTime = maps:get(<<"end_time">>, Req),
        Days = maps:get(<<"days">>, Req),
        Free = maps:get(<<"free_schedule">>, Req),
        Sql = <<"INSERT INTO work_schedules(user_id, start_time, end_time, days, free_schedule, updated_at)
                 VALUES ($1, $2::time, $3::time, $4::smallint[], $5, NOW())
                 ON CONFLICT(user_id) DO UPDATE SET
                 start_time = EXCLUDED.start_time,
                 end_time = EXCLUDED.end_time,
                 days = EXCLUDED.days,
                 free_schedule = EXCLUDED.free_schedule,
                 updated_at = NOW()">>,
        case exec_result(time_tracker_db:execute(Sql, [UserId, StartTime, EndTime, Days, Free])) of
            ok -> ok_json(#{user_id => UserId});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/work_time/get">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Sql = <<"SELECT start_time::text, end_time::text, days, free_schedule
                 FROM work_schedules WHERE user_id = $1">>,
        case rows_result(time_tracker_db:query(Sql, [UserId])) of
            {ok, [{StartTime, EndTime, Days, Free}]} ->
                ok_json(#{
                    user_id => UserId,
                    start_time => StartTime,
                    end_time => EndTime,
                    days => Days,
                    free_schedule => Free
                });
            {ok, []} -> err_json(not_found, <<"Schedule not found">>);
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/work_time/add_exclusion">>, Req) ->
    with_required([<<"user_id">>, <<"type_exclusion">>, <<"start_datetime">>, <<"end_datetime">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Type = maps:get(<<"type_exclusion">>, Req),
        StartDt = maps:get(<<"start_datetime">>, Req),
        EndDt = maps:get(<<"end_datetime">>, Req),
        Sql = <<"INSERT INTO work_exclusions(user_id, type_exclusion, start_datetime, end_datetime)
                 VALUES ($1, $2, $3::timestamptz, $4::timestamptz)">>,
        case exec_result(time_tracker_db:execute(Sql, [UserId, Type, StartDt, EndDt])) of
            ok -> ok_json(#{user_id => UserId});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/work_time/get_exclusion">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Sql = <<"SELECT type_exclusion, start_datetime::text, end_datetime::text
                 FROM work_exclusions WHERE user_id = $1 ORDER BY start_datetime DESC">>,
        case rows_result(time_tracker_db:query(Sql, [UserId])) of
            {ok, Rows} ->
                Ex = [#{type_exclusion => T, start_datetime => S, end_datetime => E} || {T, S, E} <- Rows],
                ok_json(#{user_id => UserId, exclusions => Ex});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/work_time/history_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        history_for_user(UserId)
    end);
handle(<<"/work_time/history">>, Req) ->
    with_required([<<"limit">>], Req, fun() ->
        Limit = maps:get(<<"limit">>, Req),
        Sql = <<"SELECT user_id, card_uid, touched_at::text, event_type
                 FROM touch_events ORDER BY touched_at DESC LIMIT $1">>,
        case rows_result(time_tracker_db:query(Sql, [Limit])) of
            {ok, Rows} ->
                Hist = [#{user_id => U, card_uid => C, touched_at => T, event_type => E} || {U, C, T, E} <- Rows],
                ok_json(#{history => Hist});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(<<"/work_time/statistics_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Period = maps:get(<<"period">>, Req, <<"month">>),
        statistics_for_user(UserId, Period)
    end);
handle(<<"/work_time/statistics">>, Req) ->
    with_required([<<"limit">>], Req, fun() ->
        Limit = maps:get(<<"limit">>, Req),
        Sql = <<"SELECT user_id, COUNT(*) FROM touch_events GROUP BY user_id ORDER BY user_id ASC LIMIT $1">>,
        case rows_result(time_tracker_db:query(Sql, [Limit])) of
            {ok, Rows} ->
                Summary = [#{user_id => U, touches => Cnt} || {U, Cnt} <- Rows],
                ok_json(#{summary => Summary});
            {error, Reason} -> db_error(Reason)
        end
    end);
handle(_, _) ->
    err_json(not_found, <<"Unknown method">>).

history_for_user(UserId) ->
    Sql = <<"SELECT card_uid, touched_at::text, event_type
             FROM touch_events WHERE user_id = $1 ORDER BY touched_at DESC">>,
    case rows_result(time_tracker_db:query(Sql, [UserId])) of
        {ok, Rows} ->
            Hist = [#{card_uid => C, touched_at => T, event_type => E} || {C, T, E} <- Rows],
            ok_json(#{user_id => UserId, history => Hist});
        {error, Reason} -> db_error(Reason)
    end.

statistics_for_user(UserId, PeriodBin) ->
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
            % Простий прод-стабільний baseline, який легко розширюється.
            Stats = #{
                user_id => UserId,
                period => PeriodBin,
                worked_days => erlang:min(InCnt, OutCnt),
                late_without_reason => 0,
                late_with_reason => 0,
                early_without_reason => 0,
                early_with_reason => 0
            },
            ok_json(Stats);
        {error, Reason} ->
            db_error(Reason)
    end.

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

with_required(Keys, Req, Fun) ->
    Missing = [K || K <- Keys, not maps:is_key(K, Req)],
    case Missing of
        [] -> Fun();
        _ -> err_json(validation_error, <<"Missing required fields">>)
    end.

ok_json(Data) ->
    #{status => ok, data => Data}.

err_json(Code, Message) ->
    #{status => error, error => #{code => Code, message => Message}}.

db_error(Reason) ->
    logger:error("Database error: ~p", [Reason]),
    err_json(internal_error, <<"Database operation failed">>).

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
