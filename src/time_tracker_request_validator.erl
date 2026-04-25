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
    <<"days">> => [required, positive_integer],
    <<"free_schedule">> => [{one_of, [[<<"true">>, <<"false">>]]}]
  },
  liver:validate(Schema, Params, #{return => map});

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
    <<"period">> => [{one_of, [[<<"weak">>, <<"month">>, <<"year">>, <<"all">>]]}, {default, <<"month">>}]
  },
  liver:validate(Schema, Params, #{return => map});

validate(<<"/work_time/statistics">>, Params) ->
  Schema = #{
    <<"limit">> => [required, positive_integer]
  },
  liver:validate(Schema, Params, #{return => map});

validate(_, _) ->
  {error, <<"invalid method">>}.
