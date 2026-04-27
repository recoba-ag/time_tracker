%% Unit tests for attendance / statistics rules (NFC: identify employee; in/out
%% twice per day is reflected as first in / last out per calendar day).
-module(time_tracker_attendance_tests).

-include_lib("eunit/include/eunit.hrl").

%% Fixed past dates so "today" logic never flips; universal-time calendar.
-define(D_WED, {2020, 6, 10}).
-define(D_SAT, {2020, 6, 13}).

day_base(D) -> calendar:datetime_to_gregorian_seconds({D, {0, 0, 0}}).

at(D, H, M, S) -> day_base(D) + H * 3600 + M * 60 + S.

%% Mon–Fri 09:00–18:00, office days 1..5
schedule_9_18() -> {9 * 3600, 18 * 3600, [1, 2, 3, 4, 5], false}.

%% Single calendar day D only (avoids scoring neighbour days in the same range).
window_single_day(D) ->
    B = day_base(D),
    {B, B + 86400 - 1}.

excl(Type, D, H1, M1, S1, H2, M2, S2) ->
    {Type, {D, {H1, M1, S1}}, {D, {H2, M2, S2}}}.

%% --- parse_schedule / free ---

parse_free_schedule_test() ->
    {ok, {0, 0, [], true}} = time_tracker_attendance:parse_schedule({any, any, any, true}).

parse_bad_schedule_test() ->
    {error, bad_schedule} = time_tracker_attendance:parse_schedule({}),

    {error, bad_schedule} =
        time_tracker_attendance:parse_schedule(
            {<<"20:00">>, <<"08:00">>, [1, 2, 3, 4, 5], false}
        ).

%% --- undefined schedule ---

no_schedule_test() ->
    {WS, WE} = window_single_day(?D_WED),
    M = time_tracker_attendance:compute(undefined, [], [], WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

%% --- free schedule: only worked_days = min(in, out) in window ---

free_schedule_pairing_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = {0, 0, [], true},
    T = [
        {at(?D_WED, 10, 0, 0), in},
        {at(?D_WED, 11, 0, 0), out},
        {at(?D_WED, 12, 0, 0), in}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(1, maps:get(worked_days, M)).

%% --- one perfect workday: on time, full shift ---

perfect_day_worked_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    T = [
        {at(?D_WED, 8, 55, 0), in},
        {at(?D_WED, 18, 5, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(late_with_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(early_with_reason, M)),
    ?assertEqual(1, maps:get(worked_days, M)).

late_without_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    T = [
        {at(?D_WED, 9, 30, 0), in},
        {at(?D_WED, 18, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(1, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(late_with_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

late_with_come_later_exclusion_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    Ex = [excl(<<"come later">>, ?D_WED, 9, 0, 0, 10, 0, 0)],
    ExSecs = time_tracker_attendance:build_exclusion_secs(Ex),
    T = [
        {at(?D_WED, 9, 30, 0), in},
        {at(?D_WED, 18, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, ExSecs, T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(1, maps:get(late_with_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(1, maps:get(worked_days, M)).

early_without_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    T = [
        {at(?D_WED, 9, 0, 0), in},
        {at(?D_WED, 16, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(1, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(early_with_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

early_with_leave_earlier_exclusion_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    Ex = [excl(<<"leave earlier">>, ?D_WED, 16, 0, 0, 18, 0, 0)],
    ExSecs = time_tracker_attendance:build_exclusion_secs(Ex),
    T = [
        {at(?D_WED, 9, 0, 0), in},
        {at(?D_WED, 16, 30, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, ExSecs, T, WS, WE),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(1, maps:get(early_with_reason, M)),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(1, maps:get(worked_days, M)).

%% Full "day off" / vacation style: full shift covered -> day not scored
full_day_exclusion_skips_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    Ex = [{<<"full day">>, {?D_WED, {9, 0, 0}}, {?D_WED, {18, 0, 0}}}],
    ExSecs = time_tracker_attendance:build_exclusion_secs(Ex),
    T = [
        {at(?D_WED, 9, 0, 0), in},
        {at(?D_WED, 18, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, ExSecs, T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

%% Saturday: not a scheduled workday -> no contribution
saturday_not_in_schedule_test() ->
    {WS, WE} = window_single_day(?D_SAT),
    Sch = schedule_9_18(),
    T = [
        {at(?D_SAT, 9, 0, 0), in},
        {at(?D_SAT, 18, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(0, maps:get(worked_days, M)),
    ?assertEqual(0, maps:get(late_without_reason, M)).

%% No show: no in/out
absent_late_bucket_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    M = time_tracker_attendance:compute(Sch, [], [], WS, WE),
    ?assertEqual(1, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

%% Checked in, never out (past day) -> early leave without
in_no_out_past_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    T = [{at(?D_WED, 9, 0, 0), in}],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(1, maps:get(early_without_reason, M)),
    ?assertEqual(0, maps:get(worked_days, M)).

%% Multiple in/out: first in and last out only
first_in_last_out_test() ->
    {WS, WE} = window_single_day(?D_WED),
    Sch = schedule_9_18(),
    T = [
        {at(?D_WED, 8, 0, 0), in},
        {at(?D_WED, 9, 5, 0), in},
        {at(?D_WED, 12, 0, 0), out},
        {at(?D_WED, 18, 0, 0), out}
    ],
    M = time_tracker_attendance:compute(Sch, [], T, WS, WE),
    %% Effective first in 8:00 -> on time; last out 18:00
    ?assertEqual(0, maps:get(late_without_reason, M)),
    ?assertEqual(0, maps:get(early_without_reason, M)),
    ?assertEqual(1, maps:get(worked_days, M)).

build_touch_secs_parses_db_rows_test() ->
    TouchedIn = {{2020, 6, 10}, {9, 0, 0}},
    TouchedOut = {{2020, 6, 10}, {18, 0, 0}},
    R = time_tracker_attendance:build_touch_secs([{<<"in">>, TouchedIn}, {<<"out">>, TouchedOut}]),
    ?assertEqual(2, length(R)),
    [A, B] = lists:sort(R),
    {Gi, in} = A,
    {Go, out} = B,
    ?assert(Gi < Go).
