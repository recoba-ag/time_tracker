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
