-module(time_tracker_service).

-include("db_requests.hrl").

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
    case time_tracker_db:query(?ASSIGN_CARD, [UserId, CardUid]) of
        {ok, [{DbUserId, DbCardUid}]} ->
            {ok, #{card_uid => DbCardUid, user_id => DbUserId}};
        {ok, []} ->
            case time_tracker_db:query(?CHECK_ASSIGNED_CARD, [CardUid]) of
                {ok, [{UserId, DbCardUid}]} ->
                    {ok, #{card_uid => DbCardUid, user_id => UserId}};
                {ok, [{_ExistingUserId, _DbCardUid}]} ->
                    {error, card_already_assigned, <<"This card is already assigned to another user">>};
                {ok, []} ->
                    {error, internal_error, <<"Card assignment state changed unexpectedly">>};
                {ok, _} ->
                    {error, internal_error, <<"Unexpected DB result">>};
                {error, _Code, _Reason} = Error ->
                    Error
            end;
        {ok, _} ->
            {error, internal_error, <<"Unexpected DB result">>};
        {error, _Code, _Reason} = Error ->
            Error
    end.

delete_card(CardUid) ->
    case time_tracker_db:query(?DELETE_CARD, [CardUid]) of
        {ok, [{UserId, DbCardUid}]} ->
            {ok, #{card_uid => DbCardUid, user_id => UserId}};
        {ok, []} ->
            {error, not_found, <<"Card not found">>};
        {error, _Code, _Reason} = Error ->
            Error
    end.

list_cards_by_user(UserId) ->
    case time_tracker_db:query(?GET_CARDS_BY_USER, [UserId]) of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

delete_all_cards_by_user(UserId) ->
    case time_tracker_db:query(?DELETE_ALL_USER_CARDS, [UserId]) of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

touch_card(CardUid) ->
    case time_tracker_db:query(?GET_USER_BY_CARD, [CardUid]) of
        {ok, [{UserId}]} ->
            EventType = next_event_type(UserId),
            case time_tracker_db:execute(?TOUCH_CARD, [UserId, CardUid, EventType]) of
                ok ->
                    {ok, #{card_uid => CardUid, user_id => UserId, event_type => EventType}};
                {error, _Code, _Reason} = Error ->
                    Error
            end;
        {ok, []} ->
            {error, not_found, <<"Card is not assigned">>};
        {error, _Code, _Reason} = Error ->
            Error
    end.

set_work_time(UserId, StartTime, EndTime, Days, Free) ->
    case time_tracker_db:execute(?SET_USER_WORK_TIME, [UserId, StartTime, EndTime, Days, Free]) of
        ok ->
            {ok, #{user_id => UserId}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

get_work_time(UserId) ->
    case time_tracker_db:query(?GET_USER_WORK_TIME, [UserId]) of
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
        {error, _Code, _Reason} = Error ->
            Error
    end.

add_exclusion(UserId, Type, StartDt, EndDt) ->
    case time_tracker_db:execute(?ADD_USER_EXCLUSION, [UserId, Type, StartDt, EndDt]) of
        ok ->
            {ok, #{user_id => UserId}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

get_exclusion(UserId) ->
    case time_tracker_db:query(?GET_USER_EXCLUSION, [UserId]) of
        {ok, Rows} ->
            Ex = [#{type_exclusion => T, start_datetime => S, end_datetime => E} || {T, S, E} <- Rows],
            {ok, #{user_id => UserId, exclusions => Ex}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

history_by_user(UserId) ->
    case time_tracker_db:query(?GET_HISTORY_BY_USER, [UserId]) of
        {ok, Rows} ->
            Hist = [#{card_uid => C, touched_at => T, event_type => E} || {C, T, E} <- Rows],
            {ok, #{user_id => UserId, history => Hist}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

history(Limit) ->
    case time_tracker_db:query(?GET_HISTORY, [Limit]) of
        {ok, Rows} ->
            GroupedHist = grouped_history_by_user(Rows),
            {ok, #{history => GroupedHist}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

statistics_by_user(UserId, PeriodBin) ->
    StartSec = time_tracker_time:period_start(period_atom(PeriodBin)),
    StartDt = calendar:gregorian_seconds_to_datetime(StartSec),
    StartText = fmt_datetime(StartDt),
    case time_tracker_db:query(?GET_STATISTICS_BY_USER, [UserId, StartText]) of
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
        {error, _Code, _Reason} = Error ->
            Error
    end.

statistics(Limit) ->
    case time_tracker_db:query(?GET_STATISTICS, [Limit]) of
        {ok, Rows} ->
            Summary = [#{user_id => U, touches => Cnt} || {U, Cnt} <- Rows],
            {ok, #{summary => Summary}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

grouped_history_by_user(Rows) ->
    GroupFun =
        fun({UserId, CardUid, TouchedAt, EventType}, Acc) ->
            Event = #{card_uid => CardUid, touched_at => TouchedAt, event_type => EventType},
            maps:update_with(UserId, fun(Events) -> [Event | Events] end, [Event], Acc)
        end,
    Grouped = lists:foldl(GroupFun, #{}, Rows),
    UserIds = lists:sort(maps:keys(Grouped)),
    [#{user_id => UserId, history => lists:reverse(maps:get(UserId, Grouped))} || UserId <- UserIds].

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
    case time_tracker_db:query(?GET_NEXT_EVENT_TYPE_BY_USER, [UserId]) of
        {ok, [{<<"in">>}]} -> <<"out">>;
        {ok, [{<<"out">>}]} -> <<"in">>;
        _ -> <<"in">>
    end.

fmt_datetime({Date, Time}) ->
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", tuple_to_list(Date) ++ tuple_to_list(Time))).
