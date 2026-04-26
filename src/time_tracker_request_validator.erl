-module(time_tracker_request_validator).

-include_lib("liver/include/liver.hrl").

-export([validate/1]).

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
      validate_work_time_times(Args);
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
    <<"start_datetime">> => [required, {iso_date, #{format => datetime}}],
    <<"end_datetime">> => [required, {iso_date, #{format => datetime}}]
  },
  liver:validate(Schema, Params, #{return => map});

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

validate_work_time_times(Args) ->
  StartTime = maps:get(<<"start_time">>, Args),
  EndTime = maps:get(<<"end_time">>, Args),
  case {parse_time(StartTime), parse_time(EndTime)} of
    {{ok, StartNorm}, {ok, EndNorm}} ->
      {ok, Args#{<<"start_time">> => StartNorm, <<"end_time">> => EndNorm}};
    {error, _} ->
      {error, #{<<"start_time">> => <<"INVALID_TIME">>}};
    {_, error} ->
      {error, #{<<"end_time">> => <<"INVALID_TIME">>}}
  end.

parse_time(<<H:2/binary, ":", M:2/binary, ":", S:2/binary>>) ->
  case {to_int(H), to_int(M), to_int(S)} of
    {Hh, Mm, Ss} when
      Hh >= 0, Hh < 24,
      Mm >= 0, Mm < 60,
      Ss >= 0, Ss < 60 ->
      {ok, {Hh, Mm, Ss}};
    _ ->
      error
  end;
parse_time(<<H:2/binary, ":", M:2/binary>>) ->
  case {to_int(H), to_int(M)} of
    {Hh, Mm} when
      Hh >= 0, Hh < 24,
      Mm >= 0, Mm < 60 ->
      {ok, {Hh, Mm, 0}};
    _ ->
      error
  end;
parse_time(_) ->
  error.

to_int(B) ->
  case catch binary_to_integer(B) of
    I when is_integer(I) -> I;
    _ -> -1
  end.
