-module(time_tracker_schedule).

-include("db_requests.hrl").

-export([
    validate_timezone_name/1,
    coerce_schedule_timezone_binary/1,
    tz_equals_utc/1,
    window_local_dates/3,
    shift_bounds_epoch_map/5,
    touches_by_local_workday_map/4,
    local_date_from_gregorian_sec/2,
    wall_pair_to_timestamptz/3
]).

-define(EPOCH_GREGORIAN, calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})).

-spec gregorian_to_unix_float(calendar:gregorian_seconds()) -> float().
gregorian_to_unix_float(Gsec) ->
    float(Gsec - ?EPOCH_GREGORIAN).

-spec epoch_seconds_to_gregorian(number()) -> calendar:gregorian_seconds().
epoch_seconds_to_gregorian(Sec) ->
    ?EPOCH_GREGORIAN + erlang:round(Sec).

-spec coerce_schedule_timezone_binary(term()) -> binary().
coerce_schedule_timezone_binary(Tz)
    when Tz == undefined; Tz == null ->
    <<"UTC">>;
coerce_schedule_timezone_binary(Tz) when is_binary(Tz) ->
    Trimmed = trim_bin(Tz),
    case Trimmed of
        <<>> ->
            <<"UTC">>;
        _ ->
            Trimmed
    end;
coerce_schedule_timezone_binary(Tz) when is_list(Tz) ->
    coerce_schedule_timezone_binary(unicode:characters_to_binary(Tz)).

-spec tz_equals_utc(term()) -> boolean().
tz_equals_utc(Tz0) ->
    Tz = coerce_schedule_timezone_binary(Tz0),
    case string:casefold(binary_to_list(Tz)) of
        "utc" -> true;
        "gmt" -> true;
        "etc/utc" -> true;
        "etc/gmt" -> true;
        _ -> false
    end.

-spec validate_timezone_name(term()) -> ok | {error, invalid_timezone, binary()} | {error, term(), term()}.
validate_timezone_name(TzRaw) ->
    Bin0 =
        case TzRaw of
            B when is_binary(B) -> trim_bin(B);
            L when is_list(L) -> trim_bin(unicode:characters_to_binary(L));
            _ ->
                <<>>
        end,
    case Bin0 of
        <<>> ->
            {error, invalid_timezone, <<"Empty schedule_timezone">>};
        Bin ->
            case time_tracker_db:query(?PG_TIMEZONE_EXISTS, [Bin]) of
                {ok, [{true}]} -> ok;
                {ok, [{false}]} -> {error, invalid_timezone, <<"Unknown schedule_timezone">>};
                {error, _, _} = E -> E
            end
    end.

-spec trim_bin(binary()) -> binary().
trim_bin(Bin) ->
    binary_ltrim(binary_rtrim(Bin)).

-spec binary_rtrim(binary()) -> binary().
binary_rtrim(B) ->
    binary_rtrim(B, byte_size(B)).

-spec binary_rtrim(binary(), non_neg_integer()) -> binary().
binary_rtrim(B, Len) ->
    case Len of
        0 ->
            B;
        _ ->
            Idx = Len - 1,
            <<Prefix:Idx/binary, Ch:8>> = B,
            case space_char(Ch) of
                true -> binary_rtrim(Prefix, Idx);
                false -> B
            end
    end.

-spec binary_ltrim(binary()) -> binary().
binary_ltrim(B) ->
    {_L, B2} = split_ws(B),
    B2.

-spec split_ws(binary()) -> {non_neg_integer(), binary()}.
split_ws(Bin) ->
    split_ws(Bin, 0).

-spec split_ws(binary(), non_neg_integer()) -> {non_neg_integer(), binary()}.
split_ws(<<>>, C) ->
    {C, <<>>};
split_ws(<<Ch:8, Rest/bitstring>>, C) ->
    case space_char(Ch) of
        true -> split_ws(Rest, C + 1);
        false -> {C, <<Ch:8, Rest/bitstring>>}
    end.

-spec space_char(byte()) -> boolean().
space_char($\s) -> true;
space_char($\t) -> true;
space_char($\n) -> true;
space_char($\r) -> true;
space_char(_) -> false.

-spec window_local_dates(
    calendar:gregorian_seconds(), calendar:gregorian_seconds(), binary()
) ->
    {ok, {calendar:date(), calendar:date()}} | {error, term(), term()}.
window_local_dates(WindowStartGsec, WindowEndGsec, TzBin) ->
    U0 = gregorian_to_unix_float(WindowStartGsec),
    U1 = gregorian_to_unix_float(WindowEndGsec),
    case time_tracker_db:query(?WINDOW_LOCAL_DATES_FROM_UNIX, [U0, U1, TzBin]) of
        {ok, [{D0, D1}]} ->
            MinD = calendar_sub(D0),
            MaxD = calendar_sub(D1),
            {ok, {erlang:min(MinD, MaxD), erlang:max(MinD, MaxD)}};
        {error, _, _} = E ->
            E
    end.

-spec calendar_sub(tuple()) -> calendar:date().
calendar_sub({{Y, M, D}}) -> {Y, M, D};
calendar_sub({Y, M, D}) -> {Y, M, D}.

-spec shift_bounds_epoch_map(
    calendar:date(), calendar:date(), non_neg_integer(), non_neg_integer(), binary()
) ->
    {ok, #{calendar:date() => {calendar:gregorian_seconds(), calendar:gregorian_seconds()}}}
    | {error, term(), term()}.
shift_bounds_epoch_map(FromDate, ToDate, SecStart, SecEnd, TzBin) ->
    case
        time_tracker_db:query(?SHIFT_BOUNDS_LOCAL_SERIES, [FromDate, ToDate, SecStart, TzBin, SecEnd])
    of
        {ok, Rows} ->
            Mp = lists:foldl(
                fun({WdRaw, SS, SE}, M) ->
                    Wd = calendar_sub(WdRaw),
                    M#{
                        Wd => {
                            epoch_seconds_to_gregorian(SS),
                            epoch_seconds_to_gregorian(SE)
                        }
                    }
                end,
                #{},
                Rows
            ),
            {ok, Mp};
        {error, _, _} = E ->
            E
    end.

-spec touches_by_local_workday_map(
    calendar:gregorian_seconds(),
    calendar:gregorian_seconds(),
    [{calendar:gregorian_seconds(), in | out}],
    binary()
) ->
    {ok, #{calendar:date() => [{calendar:gregorian_seconds(), in | out}]}}
    | {error, term(), term()}.
touches_by_local_workday_map(WindowStartGsec, WindowEndGsec, Touches0, TzBin) ->
    Windowed =
        [
            Pair
         || {_Gsec, _} = Pair <- Touches0,
            element(1, Pair) >= WindowStartGsec,
            element(1, Pair) =< WindowEndGsec
        ],
    case Windowed of
        [] ->
            {ok, #{}};
        _ ->
            Epochs = [gregorian_to_unix_float(Gsec) || {Gsec, _} <- Windowed],
            case time_tracker_db:query(?TOUCH_EVENTS_LOCAL_DATES, [Epochs, TzBin]) of
                {ok, Rows} when length(Rows) =:= length(Windowed) ->
                    Dates = [calendar_sub(pg_unwrap_singleton(Row)) || Row <- Rows],
                    Zipped = lists:zip(Dates, Windowed),
                    ByDay =
                        lists:foldl(
                            fun({Date, {_Gsec, _} = TouchPair}, Map) ->
                                maps:update_with(
                                    Date,
                                    fun(List) -> [TouchPair | List] end,
                                    [TouchPair],
                                    Map
                                )
                            end,
                            #{},
                            Zipped
                    ),
                    {ok, ByDay};
                {ok, R} ->
                    {error, internal_error,
                        unicode:characters_to_binary(
                            io_lib:format("touch local date mismatch: rows=~w touches=~w", [
                                length(R), length(Windowed)
                            ])
                        )};
                {error, _, _} = E ->
                    E
            end
    end.

-spec local_date_from_gregorian_sec(calendar:gregorian_seconds(), binary()) ->
    {ok, calendar:date()} | {error, term(), term()}.
local_date_from_gregorian_sec(Gsec, TzBin) ->
    U = gregorian_to_unix_float(Gsec),
    case time_tracker_db:query(?LOCAL_DATE_AT_UNIX, [U, TzBin]) of
        {ok, [Row]} -> {ok, calendar_sub(pg_unwrap_singleton(Row))};
        {error, _, _} = E -> E;
        Ok -> {error, internal_error, unicode:characters_to_binary(io_lib:format("~p", [Ok]))}
    end.

-spec wall_pair_to_timestamptz(
    calendar:datetime(), calendar:datetime(), binary()
) ->
    {ok, {calendar:datetime(), calendar:datetime()}} | {error, term(), term()}.
wall_pair_to_timestamptz(
    {{Ys, Ms, Ds}, {Hs, Mis, Ss}},
    {{Ye, Me, De}, {He, Mie, Se}},
    TzBin
) ->
    Ssf = float_maybe(Ss),
    Sef = float_maybe(Se),
    Params =
        [
            Ys, Ms, Ds, Hs, Mis, Ssf,
            Ye, Me, De, He, Mie, Sef,
            TzBin
        ],
    case time_tracker_db:query(?WALL_PAIR_TO_TIMESTAMPTZ, Params) of
        {ok, [{Ts0, Ts1}]} ->
            {ok, {Ts0, Ts1}};
        {error, _, _} = E ->
            E
    end.

-spec float_maybe(number()) -> float().
float_maybe(S) when is_integer(S) -> float(S);
float_maybe(S) when is_float(S) -> S.

-spec pg_unwrap_singleton(tuple()) -> term().
pg_unwrap_singleton(T) ->
    case T of
        {One} ->
            One;
        Other ->
            Other
    end.
