-module(time_tracker_rpc_server).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([start_link/0]).
-export([init/1, handle_info/2, terminate/2, handle_call/3, handle_cast/2, handle_continue/2]).

-record(state, {
    conn = undefined,
    chan = undefined,
    queue = <<"time_tracker_rpc">>,
    consumer_tag = undefined,
    backoff_ms = 2000
}).

-define(RECONNECT, reconnect).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    process_flag(trap_exit, true),
    Queue = list_to_binary(rpc_queue()),
    Backoff = reconnect_backoff_ms(),
    {ok, #state{queue = Queue, backoff_ms = Backoff}, {continue, connect}}.

handle_continue(connect, State) ->
    {noreply, maybe_connect(State)}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', _Pid, Reason}, State) ->
    logger:error("Rabbit process exited: ~p", [Reason]),
    schedule_reconnect(State),
    {noreply, State#state{conn = undefined, chan = undefined, consumer_tag = undefined}};
handle_info({#'basic.deliver'{delivery_tag = Tag, routing_key = RoutingKey},
             #amqp_msg{props = #'P_basic'{content_type = ContentType, reply_to = ReplyTo, correlation_id = CorrId}, payload = Payload}},
            #state{chan = Chan} = State) when ContentType =:= <<"application/json">> ->
    log_incoming_request(Payload, ContentType, RoutingKey, ReplyTo, CorrId),
    RespMap = safe_handle(Payload),
    Resp = time_tracker_decoder:encode(RespMap),
    publish_response(Chan, ReplyTo, CorrId, Resp),
    amqp_channel:cast(Chan, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};
handle_info({#'basic.deliver'{delivery_tag = Tag, routing_key = RoutingKey},
             #amqp_msg{props = #'P_basic'{content_type = ContentType, reply_to = ReplyTo, correlation_id = CorrId}, payload = Payload}},
            #state{chan = Chan} = State) ->
    log_incoming_request(Payload, ContentType, RoutingKey, ReplyTo, CorrId),
    RespErr = time_tracker_decoder:encode(#{
        status => error,
        error => #{code => validation_error, message => <<"Content-Type must be application/json">>}
    }),
    publish_response(Chan, ReplyTo, CorrId, RespErr),
    amqp_channel:cast(Chan, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};
handle_info(?RECONNECT, State) ->
    {noreply, maybe_connect(State)};
handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, #state{chan = Chan, conn = Conn}) ->
    catch amqp_channel:close(Chan),
    catch amqp_connection:close(Conn),
    ok.

safe_handle(Payload) ->
    try
        time_tracker_router:handle_request(Payload)
    catch
        Class:Reason:Stack ->
            logger:error("Unhandled request error ~p:~p ~p", [Class, Reason, Stack]),
            #{status => error, error => #{code => internal_error, message => <<"Internal error">>}}
    end.

publish_response(_Chan, undefined, _CorrId, _Resp) ->
    ok;
publish_response(Chan, ReplyTo, CorrId, Resp) ->
    Props = #'P_basic'{
        content_type = <<"application/json">>,
        correlation_id = CorrId
    },
    amqp_channel:cast(
        Chan,
        #'basic.publish'{exchange = <<>>, routing_key = ReplyTo},
        #amqp_msg{props = Props, payload = Resp}
    ),
    logger:info(
        "Outgoing RPC response payload=~ts content_type=application/json reply_to=~ts correlation_id=~ts",
        [to_printable(Resp), to_printable(ReplyTo), to_printable(CorrId)]
    ).

maybe_connect(State) ->
    Rc = rabbit_config(),
    Params = #amqp_params_network{
        host = maps:get(host, Rc),
        port = maps:get(port, Rc),
        username = to_binary(maps:get(username, Rc)),
        password = to_binary(maps:get(password, Rc)),
        virtual_host = to_binary(maps:get(vhost, Rc))
    },
    case catch amqp_connection:start(Params) of
        {ok, Conn} ->
            case catch open_channel_and_subscribe(Conn, State) of
                {ok, NewState} ->
                    NewState;
                {'EXIT', Reason1} ->
                    logger:error("Failed to initialize RabbitMQ channel: ~p", [Reason1]),
                    catch amqp_connection:close(Conn),
                    schedule_reconnect(State),
                    State
            end;
        {error, Reason2} ->
            logger:error("Failed to connect RabbitMQ: ~p", [Reason2]),
            schedule_reconnect(State),
            State;
        {'EXIT', Reason3} ->
            logger:error("RabbitMQ connection crashed: ~p", [Reason3]),
            schedule_reconnect(State),
            State
    end.

schedule_reconnect(#state{backoff_ms = Backoff}) ->
    erlang:send_after(Backoff, self(), ?RECONNECT),
    ok.

rabbit_config() ->
    Default = app_cfg(rabbitmq, #{
        host => "rabbitmq",
        port => 5672,
        username => "guest",
        password => "guest",
        vhost => "/"
    }),
    #{
        host => env_or_default("RABBIT_HOST", maps:get(host, Default)),
        port => env_or_default_int("RABBIT_PORT", maps:get(port, Default)),
        username => env_or_default("RABBIT_USER", maps:get(username, Default)),
        password => env_or_default("RABBIT_PASSWORD", maps:get(password, Default)),
        vhost => env_or_default("RABBIT_VHOST", maps:get(vhost, Default))
    }.

rpc_queue() ->
    env_or_default("RPC_QUEUE", app_cfg(rpc_queue, "time_tracker_rpc")).

reconnect_backoff_ms() ->
    Default = app_cfg(reconnect_backoff_ms, 2000),
    env_or_default_int("RECONNECT_BACKOFF_MS", Default).

app_cfg(Key, Default) ->
    case application:get_env(time_tracker, Key) of
        {ok, Value} -> Value;
        undefined -> Default
    end.

env_or_default(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Value -> Value
    end.

env_or_default_int(Name, Default) ->
    case os:getenv(Name) of
        false ->
            Default;
        Value ->
            try list_to_integer(Value) of
                Int -> Int
            catch
                _:_ -> Default
            end
    end.

open_channel_and_subscribe(Conn, State) ->
    link(Conn),
    {ok, Chan} = amqp_connection:open_channel(Conn),
    link(Chan),
    Queue = State#state.queue,
    _ = amqp_channel:call(Chan, #'queue.declare'{queue = Queue, durable = true}),
    #'basic.consume_ok'{consumer_tag = Tag} =
        amqp_channel:subscribe(Chan, #'basic.consume'{queue = Queue}, self()),
    logger:info("RabbitMQ RPC consumer started on queue ~p", [Queue]),
    {ok, State#state{conn = Conn, chan = Chan, consumer_tag = Tag}}.

log_incoming_request(Payload, ContentType, RoutingKey, ReplyTo, CorrId) ->
    logger:info(
        "Incoming RPC request payload=~ts content_type=~ts routing_key=~ts reply_to=~ts correlation_id=~ts",
        [to_printable(Payload), to_printable(ContentType), to_printable(RoutingKey), to_printable(ReplyTo), to_printable(CorrId)]
    ).

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value);
to_binary(Value) ->
    unicode:characters_to_binary(io_lib:format("~p", [Value])).

to_printable(undefined) ->
    "-";
to_printable(Value) when is_binary(Value) ->
    binary_to_list(Value);
to_printable(Value) when is_list(Value) ->
    Value;
to_printable(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).
