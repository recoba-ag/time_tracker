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

-type user_id() :: pos_integer().
-type card_uid() :: binary().
-type period_bin() :: binary().

-type service_error() :: {error, atom(), binary() | map()} | {error, term(), term()}.

-type card_map() :: #{card_uid => card_uid(), user_id => user_id()}.
-type work_time_map() :: #{
    user_id => user_id(),
    start_time => term(),
    end_time => term(),
    days => term(),
    free_schedule => term()
}.
-type exclusion_item() :: #{
    type_exclusion => binary(),
    start_datetime => term(),
    end_datetime => term()
}.
-type history_event() :: #{
    user_id := user_id(),
    card_uid := binary(),
    touched_at := term(),
    event_type := binary()
}.
-type history_group() :: #{user_id := user_id(), events := [history_event()]}.
-type stats_by_user() :: #{
    user_id => user_id(),
    period => period_bin(),
    late_without_reason => non_neg_integer(),
    late_with_reason => non_neg_integer(),
    early_without_reason => non_neg_integer(),
    early_with_reason => non_neg_integer(),
    worked_days => number()
}.

-spec assign_card(user_id(), card_uid()) -> {ok, card_map()} | service_error().
assign_card(UserId, CardUid) ->
    AssignRes = time_tracker_db:query(?ASSIGN_CARD, [UserId, CardUid]),
    case AssignRes of
        {ok, [{DbUserId, DbCardUid}]} ->
            {ok, #{card_uid => DbCardUid, user_id => DbUserId}};
        {ok, []} ->
            CheckRes = time_tracker_db:query(?CHECK_ASSIGNED_CARD, [CardUid]),
            case CheckRes of
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

-spec delete_card(card_uid()) -> {ok, card_map()} | service_error().
delete_card(CardUid) ->
    DeleteRes = time_tracker_db:query(?DELETE_CARD, [CardUid]),
    case DeleteRes of
        {ok, [{UserId, DbCardUid}]} ->
            {ok, #{card_uid => DbCardUid, user_id => UserId}};
        {ok, []} ->
            {error, not_found, <<"Card not found">>};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec list_cards_by_user(user_id()) -> {ok, #{user_id => user_id(), cards => [card_uid()]}} | service_error().
list_cards_by_user(UserId) ->
    GetRes = time_tracker_db:query(?GET_CARDS_BY_USER, [UserId]),
    case GetRes of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec delete_all_cards_by_user(user_id()) -> {ok, #{user_id => user_id(), cards => [card_uid()]}} | service_error().
delete_all_cards_by_user(UserId) ->
    DeleteRes = time_tracker_db:query(?DELETE_ALL_USER_CARDS, [UserId]),
    case DeleteRes of
        {ok, Rows} ->
            Cards = [CardUid || {CardUid} <- Rows],
            {ok, #{user_id => UserId, cards => Cards}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec touch_card(card_uid()) -> {ok, #{card_uid => card_uid(), user_id => user_id(), event_type => binary()}} | service_error().
touch_card(CardUid) ->
    GetUserRes = time_tracker_db:query(?GET_USER_BY_CARD, [CardUid]),
    case GetUserRes of
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

-spec set_work_time(user_id(), term(), term(), term(), term()) -> {ok, #{user_id => user_id()}} | service_error().
set_work_time(UserId, StartTime, EndTime, Days, Free) ->
    SetWorkTimeRes = time_tracker_db:execute(?SET_USER_WORK_TIME, [UserId, StartTime, EndTime, Days, Free]),
    case SetWorkTimeRes of
        ok ->
            {ok, #{user_id => UserId}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec get_work_time(user_id()) -> {ok, work_time_map()} | service_error().
get_work_time(UserId) ->
    UserWorkTime = time_tracker_db:query(?GET_USER_WORK_TIME, [UserId]),
    case UserWorkTime of
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

-spec add_exclusion(user_id(), binary(), term(), term()) -> {ok, #{user_id => user_id()}} | service_error().
add_exclusion(UserId, Type, StartDt, EndDt) ->
    AddRes = time_tracker_db:execute(?ADD_USER_EXCLUSION, [UserId, Type, StartDt, EndDt]),
    case AddRes of
        ok ->
            {ok, #{user_id => UserId}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec get_exclusion(user_id()) -> {ok, #{user_id => user_id(), exclusions => [exclusion_item()]}} | service_error().
get_exclusion(UserId) ->
    GetExclusionRes = time_tracker_db:query(?GET_USER_EXCLUSION, [UserId]),
    case GetExclusionRes of
        {ok, Rows} ->
            Ex = [
                #{type_exclusion => ExclType, start_datetime => StartDt, end_datetime => EndDt}
             || {ExclType, StartDt, EndDt} <- Rows
            ],
            {ok, #{user_id => UserId, exclusions => Ex}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec history_by_user(user_id()) -> {ok, #{user_id := user_id(), events := [history_event()]}} | service_error().
history_by_user(UserId) ->
    GetHistoryRes = time_tracker_db:query(?GET_HISTORY_BY_USER, [UserId]),
    case GetHistoryRes of
        {ok, Rows} ->
            Events = [
                #{user_id => UserId, card_uid => C, touched_at => T, event_type => E}
             || {C, T, E} <- Rows
            ],
            {ok, #{user_id => UserId, events => Events}};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec history(pos_integer()) -> {ok, [history_group()]} | service_error().
history(Limit) ->
    GetHistoryRes = time_tracker_db:query(?GET_HISTORY, [Limit]),
    case GetHistoryRes of
        {ok, Rows} ->
            {ok, grouped_history_by_user(Rows)};
        {error, _Code, _Reason} = Error ->
            Error
    end.

-spec statistics_by_user(user_id(), period_bin()) -> {ok, stats_by_user()} | service_error().
statistics_by_user(UserId, PeriodBin) ->
    NowGsec = time_tracker_time:now_gregorian_sec(),
    WindowStartGsec = period_t_start(period_atom(PeriodBin), UserId, NowGsec),
    WindowStartDt = calendar:gregorian_seconds_to_datetime(WindowStartGsec),
    WindowEndDt = calendar:gregorian_seconds_to_datetime(NowGsec),
    GetWorkTimeRes = time_tracker_db:query(?GET_USER_WORK_TIME, [UserId]),
    case GetWorkTimeRes of
        {ok, [Row]} ->
            Schedule = time_tracker_attendance:parse_schedule(Row),
            case Schedule of
                {ok, Sch} ->
                    GetUserExclusionsRes = time_tracker_db:query(?GET_EXCLUSIONS_FOR_USER_IN_RANGE, [UserId, WindowStartDt, WindowEndDt]),
                    GetUserTouchesRes = time_tracker_db:query(?GET_TOUCHES_FOR_USER_IN_RANGE, [UserId, WindowStartDt, WindowEndDt]),
                    case {GetUserExclusionsRes, GetUserTouchesRes} of
                        {{ok, ExRows}, {ok, TRows}} when WindowStartGsec =< NowGsec ->
                            Stats = time_tracker_attendance:compute(
                                Sch,
                                time_tracker_attendance:build_exclusion_secs(ExRows),
                                time_tracker_attendance:build_touch_secs(TRows),
                                WindowStartGsec,
                                NowGsec
                            ),
                            {ok, Stats#{user_id => UserId, period => PeriodBin}};
                        {{error, _C, _M} = E, _} ->
                            E;
                        {_, {error, _C, _M} = E} ->
                            E;
                        _ when WindowStartGsec > NowGsec ->
                            {ok, empty_stats_map(UserId, PeriodBin, 0)};
                        _ ->
                            {ok, empty_stats_map(UserId, PeriodBin, 0)}
                    end;
                {error, _} ->
                    {ok, empty_stats_map(UserId, PeriodBin, 0)}
            end;
        {ok, []} ->
            {ok, empty_stats_map(UserId, PeriodBin, 0)};
        {error, _C, _M} = E ->
            E
    end.

-spec statistics(pos_integer()) -> {ok, #{users => [map()]}} | service_error().
statistics(Limit) ->
    GetHistoryRes = time_tracker_db:query(?GET_HISTORY_EPOCH, [Limit]),
    case GetHistoryRes of
        {ok, []} ->
            {ok, #{users => []}};
        {ok, HRows} ->
            TouchedGsecs = [ts_to_gsec(T) || {_, _, T} <- HRows, is_number(T)],
            EarliestTouchedGsec = lists:min(TouchedGsecs),
            LatestTouchedGsec = lists:max(TouchedGsecs),
            UserIds0 = [UserId || {UserId, _, _} <- HRows],
            UserIds = ordsets:from_list(UserIds0),
            WindowStartGsec = EarliestTouchedGsec,
            WindowEndGsec = LatestTouchedGsec,
            WindowStartDt = calendar:gregorian_seconds_to_datetime(WindowStartGsec),
            WindowEndDt = calendar:gregorian_seconds_to_datetime(WindowEndGsec),
            UserIdList = ordsets:to_list(UserIds),
            GetWorkSchedulesRes = time_tracker_db:query(?GET_WORK_SCHEDULES_FOR_USERS, [UserIdList]),
            case GetWorkSchedulesRes of
                {ok, SchRows} ->
                    SchedulesByUser = schedule_map(SchRows),
                    GetExclusionsRes = time_tracker_db:query(?GET_EXCLUSIONS_FOR_USERS_IN_RANGE, [UserIdList, WindowStartDt, WindowEndDt]),
                    GetTouchesRes = time_tracker_db:query(?GET_TOUCHES_FOR_USERS_IN_RANGE, [UserIdList, WindowStartDt, WindowEndDt]),
                    case {GetExclusionsRes, GetTouchesRes} of
                        {{ok, ExclRowsAll}, {ok, TouchRowsAll}} when WindowStartGsec =< WindowEndGsec ->
                            ExclusionsByUser = exclusions_by_user(ExclRowsAll),
                            TouchesByUser = touches_by_user(TouchRowsAll),
                            Users = [
                                (time_tracker_attendance:compute(
                                    maps:get(UserId, SchedulesByUser, undefined),
                                    time_tracker_attendance:build_exclusion_secs(maps:get(UserId, ExclusionsByUser, [])),
                                    maps:get(UserId, TouchesByUser, []),
                                    WindowStartGsec,
                                    WindowEndGsec
                                )) #{user_id => UserId}
                                || UserId <- UserIdList
                            ],
                            {ok, #{users => Users}};
                        {{error, _C, _M} = E, _} ->
                            E;
                        {_, {error, _C, _M} = E} ->
                            E
                    end;
                {error, _C, _M} = E ->
                    E
            end;
        {error, _C, _M} = E ->
            E
    end.

empty_stats_map(UserId, PeriodBin, W) ->
    #{
        user_id => UserId,
        period => PeriodBin,
        late_without_reason => 0,
        late_with_reason => 0,
        early_without_reason => 0,
        early_with_reason => 0,
        worked_days => W
    }.

period_t_start(all, UserId, NowGsec) ->
    GetTouchesRes = time_tracker_db:query(?GET_MIN_TOUCHED_AT_FOR_USER, [UserId]),
    case GetTouchesRes of
        {ok, [{MinTouchedAt}]} when MinTouchedAt =/= null ->
            Time = time_tracker_time:datetime_to_gregorian(MinTouchedAt),
            case Time of
                {ok, FirstEventGsec} -> FirstEventGsec;
                _ -> NowGsec
            end;
        _ ->
            NowGsec
    end;
period_t_start(week, _UserId, _NowGsec) ->
    max(time_tracker_time:period_start(week), 0);
period_t_start(Period, _UserId, _NowGsec) ->
    time_tracker_time:period_start(Period).

ts_to_gsec(T) when is_float(T) ->
    epoch_to_gregorian(erlang:round(T));
ts_to_gsec(T) when is_integer(T) ->
    epoch_to_gregorian(T).

epoch_to_gregorian(EpochSec) ->
    EpochStart = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
    EpochStart + EpochSec.

schedule_map(Rows) ->
    AddUserScheduleToMap =
        fun({Uid, S, E, D, F}, M) when is_integer(Uid) ->
            case time_tracker_attendance:parse_schedule({S, E, D, F}) of
                {ok, P} -> M#{Uid => P};
                {error, _} -> M#{Uid => undefined}
            end
        end,
    lists:foldl(AddUserScheduleToMap, #{}, Rows).

exclusions_by_user(Rows) ->
    PrependExclusionToUser =
        fun({UserId, ExclType, StartDt, EndDt}, ByUser) ->
            maps:update_with(UserId, fun(Rows0) -> [{ExclType, StartDt, EndDt} | Rows0] end, [{ExclType, StartDt, EndDt}], ByUser)
        end,
    lists:foldl(PrependExclusionToUser, #{}, Rows).

touches_by_user(Rows) ->
    PrependTouchToUser =
        fun({UserId, EventType, TouchedAt}, ByUser) ->
            maps:update_with(
                UserId, fun(Events) -> [{EventType, TouchedAt} | Events] end, [{EventType, TouchedAt}], ByUser
            )
        end,
    ByUserRaw = lists:foldl(PrependTouchToUser, #{}, Rows),
    BuildSortedTouchGsecPairsForUser =
        fun(_UserId, Unsorted) ->
            Sorted = lists:sort(
                fun({_, TouchedA}, {_, TouchedB}) -> TouchedA =< TouchedB end, Unsorted
            ),
            time_tracker_attendance:build_touch_secs(Sorted)
        end,
    maps:map(BuildSortedTouchGsecPairsForUser, ByUserRaw).

grouped_history_by_user(Rows) ->
    AppendEventToUserHistory =
        fun({UserId, CardUid, TouchedAt, EventType}, Acc) ->
            Event = #{card_uid => CardUid, touched_at => TouchedAt, event_type => EventType},
            maps:update_with(UserId, fun(Events) -> [Event | Events] end, [Event], Acc)
        end,
    Grouped = lists:foldl(AppendEventToUserHistory, #{}, Rows),
    UserIds = lists:sort(maps:keys(Grouped)),
    [#{user_id => UserId, events => lists:reverse(maps:get(UserId, Grouped))} || UserId <- UserIds].

period_atom(<<"week">>) -> week;
period_atom(<<"month">>) -> month;
period_atom(<<"year">>) -> year;
period_atom(<<"all">>) -> all;
period_atom(_) -> month.

next_event_type(UserId) ->
    GetRes = time_tracker_db:query(?GET_NEXT_EVENT_TYPE_BY_USER, [UserId]),
    case GetRes of
        {ok, [{<<"in">>}]} -> <<"out">>;
        {ok, [{<<"out">>}]} -> <<"in">>;
        _ -> <<"in">>
    end.
