%%%-------------------------------------------------------------------
%% @doc time_tracker top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(time_tracker_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
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

%% internal functions
