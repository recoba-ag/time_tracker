-module(time_tracker_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 5
    },
    ChildSpecs = [
        #{
            id => time_tracker_db,
            start => {time_tracker_db, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [time_tracker_db]
        },
        #{
            id => time_tracker_rpc_server,
            start => {time_tracker_rpc_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [time_tracker_rpc_server]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
