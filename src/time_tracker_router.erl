-module(time_tracker_router).

-export([handle_request/1]).

handle_request(Payload) ->
    logger:info("handle_request"),
    case time_tracker_json:decode(Payload) of
        {ok, Data} ->
            Result =
                case time_tracker_request_validator:validate(Data) of
                    {ok, Method, Args} ->
                        handle(Method, Args);
                    {error, Reason} ->
                        {error, validation_error, Reason}
                end,
            to_json_response(Result);
        {error, invalid_json} ->
            to_json_response({error, invalid_json, <<"Invalid JSON payload">>})
    end.

handle(<<"/card/touch">>, Args) ->
    CardUid = maps:get(<<"card_uid">>, Args),
    time_tracker_service:touch_card(CardUid);
handle(<<"/card/assign">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    CardUid = maps:get(<<"card_uid">>, Args),
    time_tracker_service:assign_card(UserId, CardUid);
handle(<<"/card/delete">>, Args) ->
    CardUid = maps:get(<<"card_uid">>, Args),
    time_tracker_service:delete_card(CardUid);
handle(<<"/card/list_by_user">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    time_tracker_service:list_cards_by_user(UserId);
handle(<<"/card/delete_all_by_user">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    time_tracker_service:delete_all_cards_by_user(UserId);
handle(<<"/work_time/set">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    StartTime = maps:get(<<"start_time">>, Args),
    EndTime = maps:get(<<"end_time">>, Args),
    Days = maps:get(<<"days">>, Args),
    Free = maps:get(<<"free_schedule">>, Args),
    time_tracker_service:set_work_time(UserId, StartTime, EndTime, Days, Free);
handle(<<"/work_time/get">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    time_tracker_service:get_work_time(UserId);
handle(<<"/work_time/add_exclusion">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    Type = maps:get(<<"type_exclusion">>, Args),
    StartDt = maps:get(<<"start_datetime">>, Args),
    EndDt = maps:get(<<"end_datetime">>, Args),
    time_tracker_service:add_exclusion(UserId, Type, StartDt, EndDt);
handle(<<"/work_time/get_exclusion">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    time_tracker_service:get_exclusion(UserId);
handle(<<"/work_time/history_by_user">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    time_tracker_service:history_by_user(UserId);
handle(<<"/work_time/history">>, Args) ->
    Limit = maps:get(<<"limit">>, Args),
    time_tracker_service:history(Limit);
handle(<<"/work_time/statistics_by_user">>, Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    Period = maps:get(<<"period">>, Args),
    time_tracker_service:statistics_by_user(UserId, Period);
handle(<<"/work_time/statistics">>, Args) ->
    Limit = maps:get(<<"limit">>, Args),
    time_tracker_service:statistics(Limit).

to_json_response({ok, Data}) ->
    ok_json(Data);
to_json_response({error, Reason}) ->
    err_json(internal_error, Reason);
to_json_response({error, Code, Message}) ->
    err_json(Code, Message).

ok_json(Data) ->
    #{status => ok, data => Data}.

err_json(Code, Message) ->
    #{status => error, error => #{code => Code, message => Message}}.
