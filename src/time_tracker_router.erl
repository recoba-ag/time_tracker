-module(time_tracker_router).

-export([handle_request/1]).

handle_request(Payload) ->
    case time_tracker_json:decode(Payload) of
        {ok, #{<<"method">> := Method, <<"params">> := Params}} when is_map(Params) ->
            route(Method, Params);
        {ok, _} ->
            err_json(validation_error, <<"method and params required">>);
        {error, invalid_json} ->
            err_json(invalid_json, <<"Invalid JSON payload">>)
    end.

route(<<"/card/assign">>, Req) ->
    with_required([<<"user_id">>, <<"card_uid">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        CardUid = maps:get(<<"card_uid">>, Req),
        to_json_response(time_tracker_service:assign_card(UserId, CardUid))
    end);
route(<<"/card/delete">>, Req) ->
    with_required([<<"card_uid">>], Req, fun() ->
        CardUid = maps:get(<<"card_uid">>, Req),
        to_json_response(time_tracker_service:delete_card(CardUid))
    end);
route(<<"/card/list_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        to_json_response(time_tracker_service:list_cards_by_user(UserId))
    end);
route(<<"/card/delete_all_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        to_json_response(time_tracker_service:delete_all_cards_by_user(UserId))
    end);
route(<<"/card/touch">>, Req) ->
    with_required([<<"card_uid">>], Req, fun() ->
        CardUid = maps:get(<<"card_uid">>, Req),
        to_json_response(time_tracker_service:touch_card(CardUid))
    end);
route(<<"/work_time/set">>, Req) ->
    with_required([<<"user_id">>, <<"start_time">>, <<"end_time">>, <<"days">>, <<"free_schedule">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        StartTime = maps:get(<<"start_time">>, Req),
        EndTime = maps:get(<<"end_time">>, Req),
        Days = maps:get(<<"days">>, Req),
        Free = maps:get(<<"free_schedule">>, Req),
        to_json_response(time_tracker_service:set_work_time(UserId, StartTime, EndTime, Days, Free))
    end);
route(<<"/work_time/get">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        to_json_response(time_tracker_service:get_work_time(UserId))
    end);
route(<<"/work_time/add_exclusion">>, Req) ->
    with_required([<<"user_id">>, <<"type_exclusion">>, <<"start_datetime">>, <<"end_datetime">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Type = maps:get(<<"type_exclusion">>, Req),
        StartDt = maps:get(<<"start_datetime">>, Req),
        EndDt = maps:get(<<"end_datetime">>, Req),
        to_json_response(time_tracker_service:add_exclusion(UserId, Type, StartDt, EndDt))
    end);
route(<<"/work_time/get_exclusion">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        to_json_response(time_tracker_service:get_exclusion(UserId))
    end);
route(<<"/work_time/history_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        to_json_response(time_tracker_service:history_by_user(UserId))
    end);
route(<<"/work_time/history">>, Req) ->
    with_required([<<"limit">>], Req, fun() ->
        Limit = maps:get(<<"limit">>, Req),
        to_json_response(time_tracker_service:history(Limit))
    end);
route(<<"/work_time/statistics_by_user">>, Req) ->
    with_required([<<"user_id">>], Req, fun() ->
        UserId = maps:get(<<"user_id">>, Req),
        Period = maps:get(<<"period">>, Req, <<"month">>),
        to_json_response(time_tracker_service:statistics_by_user(UserId, Period))
    end);
route(<<"/work_time/statistics">>, Req) ->
    with_required([<<"limit">>], Req, fun() ->
        Limit = maps:get(<<"limit">>, Req),
        to_json_response(time_tracker_service:statistics(Limit))
    end);
route(_, _) ->
    err_json(not_found, <<"Unknown method">>).

to_json_response({ok, Data}) ->
    ok_json(Data);
to_json_response({error, Code, Message}) ->
    err_json(Code, Message).

with_required(Keys, Req, Fun) ->
    Missing = [K || K <- Keys, not maps:is_key(K, Req)],
    case Missing of
        [] -> Fun();
        _ -> err_json(validation_error, <<"Missing required fields">>)
    end.

ok_json(Data) ->
    #{status => ok, data => Data}.

err_json(Code, Message) ->
    #{status => error, error => #{code => Code, message => Message}}.
