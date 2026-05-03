-module(time_tracker_request_validator).

-include_lib("liver/include/liver.hrl").

-export([validate/1]).

-type method_bin() :: binary().

-spec validate(map()) -> {ok, method_bin(), map()} | {error, term()}.
validate(#{<<"method">> := Method, <<"params">> := Params})
    when is_binary(Method), is_map(Params) ->
    case validate(Method, Params) of
        {ok, Args} ->
            {ok, Method, Args};
        {error, _Reason} = Error ->
            Error
    end;
validate(_) ->
    {error, <<"method and params required">>}.

validate(<<"/card/touch">>, Params) ->
    Schema = #{
        <<"card_uid">> => [required, string]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/card/assign">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"card_uid">> => [required, string]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/card/delete">>, Params) ->
    Schema = #{
        <<"card_uid">> => [required, string]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/card/list_by_user">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/card/delete_all_by_user">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/set">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"start_time">> => [required, string],
        <<"end_time">> => [required, string],
        <<"days">> => [required, not_empty_list, {list_of, [{number_between, [1, 7]}]}],
        <<"free_schedule">> => [required, to_boolean]
    },
    case liver:validate(Schema, Params, #{return => map}) of
        {ok, Args} ->
            validate_work_time(Args);
        {error, _} = Error ->
            Error
    end;

validate(<<"/work_time/get">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/add_exclusion">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"type_exclusion">> => [required, {one_of, [[<<"come later">>, <<"leave earlier">>, <<"full day">>]]}],
        <<"start_datetime">> => [required, string],
        <<"end_datetime">> => [required, string]
    },
    case liver:validate(Schema, Params, #{return => map}) of
        {ok, Args} ->
            validate_exclusion_dt(Args);
        {error, _} = Error ->
            Error
    end;

validate(<<"/work_time/get_exclusion">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/history_by_user">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/history">>, Params) ->
    Schema = #{
        <<"limit">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/statistics_by_user">>, Params) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"period">> => [{one_of, [[<<"week">>, <<"month">>, <<"year">>, <<"all">>]]}, {default, <<"month">>}]
    },
    liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/statistics">>, Params) ->
    Schema = #{
        <<"limit">> => [required, positive_integer]
    },
    liver:validate(Schema, Params, #{return => map});

validate(_, _) ->
    {error, <<"invalid method">>}.

validate_work_time(Args) ->
    StartTime = maps:get(<<"start_time">>, Args),
    EndTime = maps:get(<<"end_time">>, Args),
    case {time_tracker_time:parse_time(StartTime), time_tracker_time:parse_time(EndTime)} of
        {{ok, StartNorm}, {ok, EndNorm}} ->
            {ok, Args#{<<"start_time">> => StartNorm, <<"end_time">> => EndNorm}};
        {error, _} ->
            {error, #{<<"start_time">> => <<"INVALID_TIME">>}};
        {_, error} ->
            {error, #{<<"end_time">> => <<"INVALID_TIME">>}}
    end.

validate_exclusion_dt(Args) ->
    StartBin = maps:get(<<"start_datetime">>, Args),
    EndBin = maps:get(<<"end_datetime">>, Args),
    case {time_tracker_time:parse_iso8601(StartBin), time_tracker_time:parse_iso8601(EndBin)} of
        {{ok, StartDT}, {ok, EndDT}} ->
            case StartDT =< EndDT of
                true ->
                    {ok, Args#{
                        <<"start_datetime">> => StartDT,
                        <<"end_datetime">> => EndDT
                    }};
                false ->
                    {error, #{<<"range">> => <<"END_BEFORE_START">>}}
            end;
        {error, _} ->
            {error, #{<<"start_datetime">> => <<"INVALID_ISO8601">>}};
        {_, error} ->
            {error, #{<<"end_datetime">> => <<"INVALID_ISO8601">>}}
    end.
