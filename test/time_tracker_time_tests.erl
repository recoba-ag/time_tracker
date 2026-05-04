-module(time_tracker_time_tests).

-include_lib("eunit/include/eunit.hrl").

to_seconds_test() ->
    ?assertEqual(3661, time_tracker_time:to_seconds({1, 1, 1})).

period_start_all_test() ->
    ?assertEqual(0, time_tracker_time:period_start(all)).

period_start_order_test() ->
    Week = time_tracker_time:period_start(week),
    Month = time_tracker_time:period_start(month),
    Year = time_tracker_time:period_start(year),
    ?assert(Week >= Year),
    ?assert(Month >= Year).

parse_iso8601_offset_not_shifted_test() ->
    WallSame = <<"2026-05-01T08:30:05+07:00">>,
    {ok, W} = time_tracker_time:parse_iso8601(WallSame),
    Expected = {{2026, 5, 1}, {8, 30, 5}},
    ?assertEqual(Expected, W),
    {ok, FromZ} = time_tracker_time:parse_iso8601(<<"2026-05-01T08:30:05Z">>),
    ?assertEqual(Expected, FromZ),
    {ok, NegOff} = time_tracker_time:parse_iso8601(<<"2026-05-01T08:30:05-03:30">>),
    ?assertEqual(Expected, NegOff),
    error = time_tracker_time:parse_iso8601(<<"2026/05/01T08:30:05Z">>).
