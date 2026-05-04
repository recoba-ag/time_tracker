-module(time_tracker_time).

-export([
    period_start/1,
    to_seconds/1,
    parse_time/1,
    parse_iso8601/1,
    now_gregorian_sec/0,
    datetime_to_gregorian/1
]).

-export_type([period/0, hms/0, parse_error/0, gregorian_sec/0]).

-type period() :: week | month | year | all.
-type hms() :: {0..23, 0..59, 0..59}.
-type parse_error() :: error.
-type gregorian_sec() :: non_neg_integer().

-spec period_start(period()) -> gregorian_sec().

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

-spec to_seconds(hms()) -> non_neg_integer().
to_seconds({H, M, S}) ->
    H * 3600 + M * 60 + S.

-spec parse_time(binary()) -> {ok, hms()} | parse_error().
parse_time(Bin) when is_binary(Bin) ->
    Parts = binary:split(Bin, [<<":">>, <<".">>], [global]),
    case Parts of
        [HourB, MinB] ->
            case {to_int(HourB), to_int(MinB)} of
                {Hh, Mm} when
                    Hh >= 0, Hh < 24,
                    Mm >= 0, Mm < 60 ->
                    {ok, {Hh, Mm, 0}};
                _ ->
                    error
            end;
        [HourB, MinB, SecB | _] ->
            case {to_int(HourB), to_int(MinB), to_int(SecB)} of
                {Hh, Mm, Ss} when
                    Hh >= 0, Hh < 24,
                    Mm >= 0, Mm < 60,
                    Ss >= 0, Ss < 60 ->
                    {ok, {Hh, Mm, Ss}};
                _ ->
                    error
            end;
        _ ->
            error
    end;
parse_time(_) ->
    error.

-spec now_gregorian_sec() -> gregorian_sec().
now_gregorian_sec() ->
    calendar:datetime_to_gregorian_seconds(calendar:universal_time()).

-spec datetime_to_gregorian(calendar:datetime() | term()) -> {ok, gregorian_sec()} | parse_error().
datetime_to_gregorian({{Y, Mo, D}, {H, Mi, S}}) ->
    datetime_parts_to_gregorian(Y, Mo, D, H, Mi, S);
datetime_to_gregorian({{Y, Mo, D}, {H, Mi, S, _Us}}) ->
    datetime_parts_to_gregorian(Y, Mo, D, H, Mi, S);
datetime_to_gregorian(_) ->
    error.

datetime_parts_to_gregorian(Y, Mo, D, H, Mi, S) ->
    S2 =
        if
            is_float(S) -> trunc(S);
            is_integer(S) -> S;
            true -> 0
        end,
    try calendar:datetime_to_gregorian_seconds({{Y, Mo, D}, {H, Mi, S2}}) of
        Gs ->
            {ok, Gs}
    catch
        _:_ ->
            error
    end.

-spec parse_iso8601(binary()) -> {ok, calendar:datetime()} | parse_error().
parse_iso8601(Bin) when is_binary(Bin) ->
    case Bin of
        <<Y:4/binary, "-", Mo:2/binary, "-", D:2/binary,
            "T",
            H:2/binary, ":", Mi:2/binary, ":", S:2/binary,
            Sign, _:2/binary, ":", _:2/binary>> when Sign == $+; Sign == $- ->
            case parse_datetime(Y, Mo, D, H, Mi, S) of
                {ok, DT} -> {ok, DT};
                error -> error
            end;
        <<Y:4/binary, "-", Mo:2/binary, "-", D:2/binary,
            "T",
            H:2/binary, ":", Mi:2/binary, ":", S:2/binary,
            "Z">> ->
            case parse_datetime(Y, Mo, D, H, Mi, S) of
                {ok, DT} -> {ok, DT};
                error -> error
            end;
        _ ->
            error
    end;
parse_iso8601(_) ->
    error.

parse_datetime(Y, Mo, D, H, Mi, S) ->
    case {to_int(Y), to_int(Mo), to_int(D), to_int(H), to_int(Mi), to_int(S)} of
        {Yy, Mo1, Dd, Hh, Mm, Ss} when
            Yy > 0,
            Mo1 >= 1, Mo1 =< 12,
            Dd >= 1, Dd =< 31,
            Hh >= 0, Hh < 24,
            Mm >= 0, Mm < 60,
            Ss >= 0, Ss < 60 ->
            {ok, {{Yy, Mo1, Dd}, {Hh, Mm, Ss}}};
        _ ->
            error
    end.

to_int(B) ->
    case catch binary_to_integer(B) of
        I when is_integer(I) -> I;
        _ -> -1
    end.
