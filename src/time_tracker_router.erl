-module(time_tracker_router).

-export([handle_request/1]).

handle_request(Payload) ->
    case time_tracker_json:decode(Payload) of
        {ok, #{<<"method">> := Method, <<"params">> := Params}} when is_map(Params) ->
            time_tracker_service:handle(Method, Params);
        {ok, _} ->
            #{status => error, error => #{code => validation_error, message => <<"method and params required">>}};
        {error, invalid_json} ->
            #{status => error, error => #{code => invalid_json, message => <<"Invalid JSON payload">>}}
    end.
