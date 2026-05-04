-module(time_tracker_attendance).

-export([
    parse_schedule/1,
    build_exclusion_secs/1,
    build_touch_secs/1,
    compute/5
]).

-define(EX_COME, <<"come later">>).
-define(EX_LEAVE, <<"leave earlier">>).
-define(EX_FULL, <<"full day">>).

-type stats_map() :: #{
    late_without_reason => non_neg_integer(),
    late_with_reason => non_neg_integer(),
    early_without_reason => non_neg_integer(),
    early_with_reason => non_neg_integer(),
    worked_days => non_neg_integer()
}.

-export_type([stats_map/0, work_schedule/0, touch_gsec/0, exclusion_gsec/0, exclusion_db_row/0, touch_db_row/0]).

-type work_schedule() ::
    {non_neg_integer(), non_neg_integer(), [1..7], false, binary()}
    | {0, 0, [], true}.

-type touch_gsec() :: {time_tracker_time:gregorian_sec(), in | out}.
-type exclusion_gsec() :: {binary(), non_neg_integer(), non_neg_integer()}.

-type exclusion_db_row() :: {binary(), term(), term()}.
-type touch_db_row() :: {binary(), term()}.

-spec parse_schedule(tuple()) -> {ok, work_schedule()} | {error, bad_schedule}.
parse_schedule({_StartBin, _EndBin, _DbDays, true}) ->
    {ok, {0, 0, [], true}};
parse_schedule({_StartBin, _EndBin, _DbDays, true, _Tz}) ->
    {ok, {0, 0, [], true}};
parse_schedule({StartBin, EndBin, WorkdaysDb, false}) when is_binary(StartBin) ->
    parse_schedule({StartBin, EndBin, WorkdaysDb, false, <<"UTC">>});
parse_schedule({StartBin, EndBin, WorkdaysDb, false, Tz0}) when is_binary(StartBin) ->
    Tz = time_tracker_schedule:coerce_schedule_timezone_binary(Tz0),
    case {time_tracker_time:parse_time(StartBin), time_tracker_time:parse_time(EndBin)} of
        {{ok, StartHms}, {ok, EndHms}} when StartHms < EndHms ->
            SecFromMidnightStart = time_tracker_time:to_seconds(StartHms),
            SecFromMidnightEnd = time_tracker_time:to_seconds(EndHms),
            WorkdayNumbers = normalize_days(WorkdaysDb),
            {ok, {SecFromMidnightStart, SecFromMidnightEnd, WorkdayNumbers, false, Tz}};
        _ ->
            {error, bad_schedule}
    end;
parse_schedule(_) ->
    {error, bad_schedule}.

normalize_days({array, DaysList}) when is_list(DaysList) ->
    normalize_days(DaysList);
normalize_days(WorkdayNumbers) when is_list(WorkdayNumbers) ->
    [Day || Day <- WorkdayNumbers, is_integer(Day), Day >= 1, Day =< 7];
normalize_days(WorkdayNumbers) when is_tuple(WorkdayNumbers) ->
    normalize_days(tuple_to_list(WorkdayNumbers));
normalize_days(_) -> [].

-spec build_exclusion_secs([exclusion_db_row()]) -> [exclusion_gsec()].
build_exclusion_secs(Rows) ->
    ExclRowToGsecTuple =
        fun({ExclType, StartDt, EndDt}) ->
            case
                {time_tracker_time:datetime_to_gregorian(StartDt), time_tracker_time:datetime_to_gregorian(EndDt)}
            of
                {{ok, StartGsec}, {ok, EndGsec}} when StartGsec =< EndGsec -> {true, {ExclType, StartGsec, EndGsec}};
                _ -> false
            end
        end,
    lists:filtermap(ExclRowToGsecTuple, Rows).

-spec build_touch_secs([touch_db_row()]) -> [touch_gsec()].
build_touch_secs(Rows) ->
    TouchRowToGsecPair =
        fun({EventType, TouchedDt}) ->
            case time_tracker_time:datetime_to_gregorian(TouchedDt) of
                {ok, TouchGsec} when EventType =:= <<"in">> -> {true, {TouchGsec, in}};
                {ok, TouchGsec} when EventType =:= <<"out">> -> {true, {TouchGsec, out}};
                _ -> false
            end
        end,
    lists:sort(lists:filtermap(TouchRowToGsecPair, Rows)).

-spec compute(
    work_schedule() | undefined,
    [exclusion_gsec()],
    [touch_gsec()],
    time_tracker_time:gregorian_sec(),
    time_tracker_time:gregorian_sec()
) -> stats_map().
compute(undefined, _ExclSecs, _Touches, _WindowStart, _WindowEnd) ->
    empty(0);
compute({0, 0, _, true}, _ExclSecs, Touches, WindowStart, WindowEnd) ->
    empty(free_count(Touches, WindowStart, WindowEnd));
compute({SecFromMidnightStart, SecFromMidnightEnd, WorkdayNumbers, false, TzBin},
    ExclSecs, Touches, WindowStart, WindowEnd) when SecFromMidnightStart < SecFromMidnightEnd,
    WindowStart =< WindowEnd ->
    case time_tracker_schedule:tz_equals_utc(TzBin) of
        true ->
            compute_fixed_utc(
                SecFromMidnightStart, SecFromMidnightEnd,
                WorkdayNumbers, ExclSecs, Touches, WindowStart, WindowEnd
            );
        false ->
            compute_fixed_non_utc_tz(
                SecFromMidnightStart, SecFromMidnightEnd,
                WorkdayNumbers, ExclSecs, Touches,
                WindowStart, WindowEnd, TzBin
            )
    end;
compute({SecFromMidnightStart, SecFromMidnightEnd, WorkdayNumbers, false},
    ExclSecs, Touches, WindowStart, WindowEnd) when SecFromMidnightStart < SecFromMidnightEnd,
    WindowStart =< WindowEnd ->
    compute(
        {SecFromMidnightStart, SecFromMidnightEnd, WorkdayNumbers, false, <<"UTC">>},
        ExclSecs,
        Touches,
        WindowStart,
        WindowEnd
    );
compute(_Schedule, _ExclSecs, _Touches, _WindowStart, _WindowEnd) -> empty(0).

compute_fixed_utc(SecMidStart, SecMidEnd, WorkdayNumbers, ExclSecs, Touches, WindowStart, WindowEnd) ->
    NowGsec = time_tracker_time:now_gregorian_sec(),
    TouchesByWorkday = touches_by_workday(Touches, WindowStart, WindowEnd),
    {FirstDateInWindow, LastDateInWindow} = {date_ceil(WindowStart), date_floor(WindowEnd)},
    TodayDate = date_of_greg(NowGsec),
    Step =
        fun(WorkdayDate, Accum) ->
            step_via_local_midnight_utc_calendar(
                WorkdayDate,
                SecMidStart,
                SecMidEnd,
                WorkdayNumbers,
                ExclSecs,
                TouchesByWorkday,
                WindowStart,
                WindowEnd,
                NowGsec,
                TodayDate,
                Accum
            )
        end,
    lists:foldl(
        Step, empty(0), date_range(FirstDateInWindow, LastDateInWindow)
    ).

compute_fixed_non_utc_tz(
    SecMidStart, SecMidEnd, WorkdayNumbers, ExclSecs, Touches,
    WindowStart, WindowEnd, TzBin
) ->
    NowGsec = time_tracker_time:now_gregorian_sec(),
    case time_tracker_schedule:window_local_dates(WindowStart, WindowEnd, TzBin) of
        {ok, {FirstLocal, LastLocal}} ->
            case time_tracker_schedule:shift_bounds_epoch_map(
                FirstLocal, LastLocal, SecMidStart, SecMidEnd, TzBin
            ) of
                {ok, BoundsMap} ->
                    case time_tracker_schedule:touches_by_local_workday_map(
                        WindowStart, WindowEnd, Touches, TzBin
                    ) of
                        {ok, TouchesByLocalDay} ->
                            case time_tracker_schedule:local_date_from_gregorian_sec(NowGsec, TzBin) of
                                {ok, TodayLocal} ->
                                    Step =
                                        fun(WorkdayDate, Accum) ->
                                            case maps:get(WorkdayDate, BoundsMap, undefined) of
                                                undefined ->
                                                    Accum;
                                                {ShiftStartGsec, ShiftEndGsec} ->
                                                    evaluate_workday(
                                                        WorkdayDate,
                                                        ShiftStartGsec,
                                                        ShiftEndGsec,
                                                        WorkdayNumbers,
                                                        ExclSecs,
                                                        TouchesByLocalDay,
                                                        WindowStart,
                                                        WindowEnd,
                                                        NowGsec,
                                                        TodayLocal,
                                                        Accum
                                                    )
                                            end
                                        end,
                                    lists:foldl(
                                        Step,
                                        empty(0),
                                        date_range(FirstLocal, LastLocal)
                                    );
                                {error, _, _} ->
                                    empty(0)
                            end;
                        {error, _, _} ->
                            empty(0)
                    end;
                {error, _, _} ->
                    empty(0)
            end;
        {error, _, _} ->
            empty(0)
    end.

step_via_local_midnight_utc_calendar(
    WorkdayDate,
    SecFromMidnightStart,
    SecFromMidnightEnd,
    WorkdayNumbers,
    ExclSecs,
    TouchesByWorkday,
    WindowStart,
    WindowEnd,
    NowGsec,
    TodayDate,
    Accum
) ->
    ShiftStartGsec = day_midnight_greg(WorkdayDate) + SecFromMidnightStart,
    ShiftEndGsec = day_midnight_greg(WorkdayDate) + SecFromMidnightEnd,
    evaluate_workday(
        WorkdayDate,
        ShiftStartGsec,
        ShiftEndGsec,
        WorkdayNumbers,
        ExclSecs,
        TouchesByWorkday,
        WindowStart,
        WindowEnd,
        NowGsec,
        TodayDate,
        Accum
    ).

empty(WorkedDaysInit) ->
    #{
        late_without_reason => 0,
        late_with_reason => 0,
        early_without_reason => 0,
        early_with_reason => 0,
        worked_days => WorkedDaysInit
    }.

free_count(Touches, WindowStart, WindowEnd) ->
    CountInOrOutInWindow =
        fun
            ({TouchGsec, in}, {InAcc, OutAcc}) when
                TouchGsec >= WindowStart, TouchGsec =< WindowEnd
                ->
                {InAcc + 1, OutAcc};
            ({TouchGsec, out}, {InAcc, OutAcc}) when
                TouchGsec >= WindowStart, TouchGsec =< WindowEnd
                ->
                {InAcc, OutAcc + 1};
            (_, Counts) -> Counts
        end,
    {InCount, OutCount} = lists:foldl(CountInOrOutInWindow, {0, 0}, Touches),
    erlang:min(InCount, OutCount).

touches_by_workday(Touches, WindowStart, WindowEnd) ->
    AddTouchToWorkdayMap =
        fun
            ({TouchGsec, InOrOut}, ByWorkday) when
                TouchGsec >= WindowStart, TouchGsec =< WindowEnd
                ->
                Workday = date_of_greg(TouchGsec),
                maps:update_with(Workday, fun(List) -> [{TouchGsec, InOrOut} | List] end, [{TouchGsec, InOrOut}], ByWorkday);
            (_, ByWorkday) -> ByWorkday
        end,
    lists:foldl(AddTouchToWorkdayMap, #{}, Touches).

date_of_greg(GregSec) -> element(1, calendar:gregorian_seconds_to_datetime(GregSec)).
date_ceil(G) -> date_of_greg(G).
date_floor(G) -> date_of_greg(G).

date_range(RangeStart, RangeEnd) when RangeStart =< RangeEnd -> date_range_i(RangeStart, RangeEnd, []);
date_range(_RangeStart, _RangeEnd) -> [].

date_range_i(WorkdayDate, LastDate, AccRev) when WorkdayDate =< LastDate ->
    date_range_i(date_add_one_day(WorkdayDate), LastDate, [WorkdayDate | AccRev]);
date_range_i(_WorkdayDate, _LastDate, AccRev) ->
    lists:reverse(AccRev).

date_add_one_day({Year, Mon, Day}) ->
    N = calendar:date_to_gregorian_days({Year, Mon, Day}) + 1,
    calendar:gregorian_days_to_date(N).

day_midnight_greg(WorkdayDate) -> calendar:datetime_to_gregorian_seconds({WorkdayDate, {0, 0, 0}}).

evaluate_workday(
    WorkdayDate,
    ShiftStartGsec,
    ShiftEndGsec,
    WorkdayNumbers,
    ExclSecs,
    TouchesByWorkday,
    WindowStart,
    WindowEnd,
    NowGsec,
    TodayDate,
    Acc
) ->
    case lists:member(calendar:day_of_the_week(WorkdayDate), WorkdayNumbers) of
        false ->
            Acc;
        true ->
            if
                ShiftStartGsec > WindowEnd; ShiftEndGsec < WindowStart; ShiftStartGsec >= ShiftEndGsec -> Acc;
                true ->
                    case full_covers_work(ShiftStartGsec, ShiftEndGsec, ExclSecs) of
                        true ->
                            Acc;
                        false ->
                            case should_score_day(TodayDate, NowGsec, WorkdayDate, ShiftStartGsec, ShiftEndGsec) of
                                false ->
                                    Acc;
                                true ->
                                    DayTouches = lists:sort(maps:get(WorkdayDate, TouchesByWorkday, [])),
                                    FirstInGsec = first_in_gsec(DayTouches),
                                    LastOutGsec = last_out_gsec(DayTouches),
                                    {LateWithout, LateWith, EarlyWithout, EarlyWith, Worked} = score_workday(
                                        WorkdayDate,
                                        TodayDate,
                                        NowGsec,
                                        FirstInGsec,
                                        LastOutGsec,
                                        ShiftStartGsec,
                                        ShiftEndGsec,
                                        ExclSecs
                                    ),
                                    Acc#{
                                        late_without_reason => maps:get(late_without_reason, Acc) + LateWithout,
                                        late_with_reason => maps:get(late_with_reason, Acc) + LateWith,
                                        early_without_reason => maps:get(early_without_reason, Acc) + EarlyWithout,
                                        early_with_reason => maps:get(early_with_reason, Acc) + EarlyWith,
                                        worked_days => maps:get(worked_days, Acc) + Worked
                                    }
                            end
                    end
            end
    end.


should_score_day(TodayDate, _NowGsec, WorkdayDate, _ShiftStartGsec, _ShiftEndGsec) when
    WorkdayDate < TodayDate ->
    true;
should_score_day(TodayDate, NowGsec, WorkdayDate, ShiftStartGsec, _ShiftEndGsec) when
    WorkdayDate =:= TodayDate, NowGsec >= ShiftStartGsec ->
    true;
should_score_day(_TodayDate, _NowGsec, _WorkdayDate, _ShiftStartGsec, _ShiftEndGsec) ->
    false.

score_workday(WorkdayDate, TodayDate, NowGsec, FirstInGsec, LastOutGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs) when
    WorkdayDate =:= TodayDate, NowGsec < ShiftEndGsec, LastOutGsec =:= undefined ->
    classify_late_only(FirstInGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs);
score_workday(_WorkdayDate, _TodayDate, _NowGsec, FirstInGsec, LastOutGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs) ->
    classify(FirstInGsec, LastOutGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs).

classify_late_only(undefined, _ShiftStartGsec, _ShiftEndGsec, _ExclSecs) ->
    {1, 0, 0, 0, 0};
classify_late_only(FirstInGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs) when is_integer(FirstInGsec) ->
    LateDl = late_arrival_deadline_sec(ShiftStartGsec, ShiftEndGsec, ExclSecs),
    LateWithout =
        if
            FirstInGsec > LateDl -> 1;
            true -> 0
        end,
    LateWith =
        if
            (FirstInGsec > ShiftStartGsec) andalso (FirstInGsec =< LateDl) -> 1;
            true -> 0
        end,
    {LateWithout, LateWith, 0, 0, 0}.

full_covers_work(ShiftStartGsec, ShiftEndGsec, ExclSecs) ->
    FullExclSpansEntireShift =
        fun
            ({?EX_FULL, SpanStart, SpanEnd})
                when SpanStart =< ShiftStartGsec, SpanEnd >= ShiftEndGsec ->
                true;
            (_) ->
                false
        end,
    lists:any(FullExclSpansEntireShift, ExclSecs).

first_in_gsec(Sorted) ->
    case [Gsec || {Gsec, in} <- Sorted] of
        [] ->
            undefined;
        InList ->
            lists:min(InList)
    end.

last_out_gsec(Sorted) ->
    case [Gsec || {Gsec, out} <- Sorted] of
        [] ->
            undefined;
        OutList ->
            lists:max(OutList)
    end.

late_arrival_deadline_sec(ShiftStartGsec, ShiftEndGsec, ExclSecs) ->
    lists:foldl(
        fun
            ({?EX_COME, Es, Ee}, Acc) when Es =< Ee ->
                case intervals_overlap_gsec(Es, Ee, ShiftStartGsec, ShiftEndGsec) of
                    true ->
                        erlang:max(Acc, Ee);
                    false ->
                        Acc
                end;
            (_, Acc) ->
                Acc
        end,
        ShiftStartGsec,
        ExclSecs
    ).

intervals_overlap_gsec(A1, A2, B1, B2) when A1 =< A2, B1 =< B2 ->
    not (A2 < B1 orelse B2 < A1).

leave_covered(LastOutGsec, ShiftEndGsec, ExclSecs) when is_integer(LastOutGsec) ->
    LeaveExclContainsLastOut =
        fun
            ({?EX_LEAVE, ExclStart, ExclEnd}) when ExclStart =< LastOutGsec, LastOutGsec =< ExclEnd ->
                true;
            (_) ->
                false
        end,
    (LastOutGsec >= ShiftEndGsec) orelse lists:any(LeaveExclContainsLastOut, ExclSecs).

classify(undefined, _LastOutGsec, _ShiftStartGsec, _ShiftEndGsec, _ExclSecs) ->
    {1, 0, 0, 0, 0};
classify(_FirstInGsec, undefined, _ShiftStartGsec, _ShiftEndGsec, _ExclSecs) when is_integer(_FirstInGsec) ->
    {0, 0, 1, 0, 0};
classify(FirstInGsec, LastOutGsec, ShiftStartGsec, ShiftEndGsec, ExclSecs) when
    is_integer(FirstInGsec), is_integer(LastOutGsec) ->
    LateDl = late_arrival_deadline_sec(ShiftStartGsec, ShiftEndGsec, ExclSecs),
    HasLeaveExclusion = leave_covered(LastOutGsec, ShiftEndGsec, ExclSecs),
    LateWithout =
        if
            FirstInGsec > LateDl -> 1;
            true -> 0
        end,
    LateWith =
        if
            (FirstInGsec > ShiftStartGsec) andalso (FirstInGsec =< LateDl) -> 1;
            true -> 0
        end,
    EarlyWithout =
        if
            (LastOutGsec < ShiftEndGsec) andalso (not HasLeaveExclusion) -> 1;
            true -> 0
        end,
    EarlyWith =
        if
            (LastOutGsec < ShiftEndGsec) andalso HasLeaveExclusion -> 1;
            true -> 0
        end,
    Worked =
        case {LateWithout, EarlyWithout, FirstInGsec, LastOutGsec} of
            {0, 0, _, _} when LastOutGsec >= FirstInGsec -> 1;
            _ -> 0
        end,
    {LateWithout, LateWith, EarlyWithout, EarlyWith, Worked}.