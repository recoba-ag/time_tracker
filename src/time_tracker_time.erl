-module(time_tracker_time).

-export([period_start/1, to_seconds/1]).

period_start(week) ->
    {{Y, M, D}, _} = calendar:universal_time(),
    Date = {Y, M, D},
    DayOfWeek = calendar:day_of_the_week(Date),
    calendar:datetime_to_gregorian_seconds({Date, {0, 0, 0}}) - (DayOfWeek - 1) * 24 * 3600;
period_start(month) ->
    {{Y, M, _}, _} = calendar:universal_time(),
    calendar:datetime_to_gregorian_seconds({{Y, M, 1}, {0, 0, 0}});
period_start(year) ->
    {{Y, _, _}, _} = calendar:universal_time(),
    calendar:datetime_to_gregorian_seconds({{Y, 1, 1}, {0, 0, 0}});
period_start(all) ->
    0.

to_seconds({H, M, S}) ->
    H * 3600 + M * 60 + S.
