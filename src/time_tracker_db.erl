-module(time_tracker_db).

-dialyzer({nowarn_function, [rows_result/1, exec_result/1]}).

-behaviour(gen_server).

-export([
    start_link/0,
    query/2,
    query/3,
    execute/2,
    execute/3
]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    handle_continue/2
]).

-record(state, {
    conn = undefined,
    cfg = #{},
    backoff_ms = 2000
}).

-define(SERVER, ?MODULE).
-define(RECONNECT, reconnect).

-type sql() :: iodata().
-type query_error() :: {error, internal_error, binary()}.
-type rows_ok() :: {ok, [tuple()]}.
-type query_result() :: rows_ok() | query_error() | {error, term()}.
-type exec_result() :: ok | query_error() | {error, term()}.

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec query(sql(), [term()]) -> query_result().
query(Sql, Params) ->
    query(Sql, Params, 5000).

-spec query(sql(), [term()], timeout()) -> query_result().
query(Sql, Params, Timeout) ->
    gen_server:call(?SERVER, {query, Sql, Params}, Timeout).

-spec execute(sql(), [term()]) -> exec_result().
execute(Sql, Params) ->
    execute(Sql, Params, 5000).

-spec execute(sql(), [term()], timeout()) -> exec_result().
execute(Sql, Params, Timeout) ->
    gen_server:call(?SERVER, {execute, Sql, Params}, Timeout).

init([]) ->
    process_flag(trap_exit, true),
    Cfg = pg_config(),
    Backoff = reconnect_backoff_ms(),
    {ok, #state{cfg = Cfg, backoff_ms = Backoff}, {continue, connect}}.

handle_call(_Req, _From, #state{conn = undefined} = State) ->
    {reply, {error, db_unavailable}, State};
handle_call({query, Sql, Params}, _From, State) ->
    {RawReply, NewState} =
        with_reconnect(fun(Conn) -> epgsql:equery(Conn, Sql, Params) end, State),
    Reply =
        case RawReply of
            {error, Reason} -> db_error(Reason);
            _ -> rows_result(RawReply)
        end,
    {reply, Reply, NewState};
handle_call({execute, Sql, Params}, _From, State) ->
    {RawReply, NewState} =
        with_reconnect(fun(Conn) -> epgsql:equery(Conn, Sql, Params) end, State),
    Reply =
        case RawReply of
            {error, Reason} -> db_error(Reason);
            _ -> exec_result(RawReply)
        end,
    {reply, Reply, NewState};
handle_call(_, _, State) ->
    {reply, {error, db_error, <<"Bad request">>}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Conn, Reason}, #state{conn = Conn} = State) ->
    logger:error("PostgreSQL connection lost: ~p", [Reason]),
    schedule_reconnect(State),
    {noreply, State#state{conn = undefined}};
handle_info(?RECONNECT, State) ->
    {noreply, maybe_connect(State)};
handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, #state{conn = undefined}) ->
    ok;
terminate(_Reason, #state{conn = Conn}) ->
    catch epgsql:close(Conn),
    ok.

handle_continue(connect, State) ->
    {noreply, maybe_connect(State)}.

maybe_connect(#state{cfg = Cfg} = State) ->
    Opts = [
        {host, maps:get(host, Cfg)},
        {port, maps:get(port, Cfg)},
        {username, maps:get(username, Cfg)},
        {password, maps:get(password, Cfg)},
        {database, maps:get(database, Cfg)},
        {timeout, 5000}
    ],
    case epgsql:connect(Opts) of
        {ok, Conn} ->
            link(Conn),
            case catch time_tracker_db_schema:ensure(Conn) of
                ok ->
                    logger:info("Connected to PostgreSQL"),
                    State#state{conn = Conn};
                {'EXIT', Reason} ->
                    logger:error("Schema initialization failed: ~p", [Reason]),
                    catch epgsql:close(Conn),
                    schedule_reconnect(State),
                    State#state{conn = undefined}
            end;
        {error, Reason} ->
            logger:error("Failed to connect PostgreSQL: ~p", [Reason]),
            schedule_reconnect(State),
            State#state{conn = undefined}
    end.

with_reconnect(WithConnection, #state{conn = Conn} = State) when Conn =/= undefined ->
    try
        {WithConnection(Conn), State}
    catch
        exit:Reason ->
            logger:error("DB query failed, dropping connection: ~p", [Reason]),
            schedule_reconnect(State),
            {{error, db_unavailable}, State#state{conn = undefined}}
    end.

schedule_reconnect(#state{backoff_ms = Backoff}) ->
    erlang:send_after(Backoff, self(), ?RECONNECT),
    ok.

pg_config() ->
    Default = app_cfg(pg, #{
        host => "postgres",
        port => 5432,
        username => "postgres",
        password => "postgres",
        database => "time_tracker"
    }),
    #{
        host => env_or_default("PG_HOST", maps:get(host, Default)),
        port => env_or_default_int("PG_PORT", maps:get(port, Default)),
        username => env_or_default("PG_USER", maps:get(username, Default)),
        password => env_or_default("PG_PASSWORD", maps:get(password, Default)),
        database => env_or_default("PG_DATABASE", maps:get(database, Default))
    }.

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

db_error(Reason) ->
    logger:error("Database error: ~p", [Reason]),
    {error, internal_error, <<"Database operation failed">>}.

rows_result({ok, _Count, _Cols, Rows}) when is_list(Rows) ->
    {ok, Rows};
rows_result({ok, _Count, Rows}) when is_list(Rows) ->
    {ok, Rows};
rows_result({ok, _Count}) ->
    {ok, []};
rows_result({error, _} = Error) ->
    Error;
rows_result(Other) ->
    {error, {unexpected_db_result, Other}}.

exec_result({ok, _Count, _Cols, _Rows}) ->
    ok;
exec_result({ok, _Count, _Rows}) ->
    ok;
exec_result({ok, _Count}) ->
    ok;
exec_result({error, _} = Error) ->
    Error;
exec_result(Other) ->
    {error, {unexpected_db_result, Other}}.
