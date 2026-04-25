-module(time_tracker_db_schema).

-export([ensure/1]).

ensure(Conn) ->
    Statements = load_schema_statements(),
    lists:foreach(
        fun(Sql) ->
            case epgsql:squery(Conn, Sql) of
                {ok, _, _} -> ok;
                {ok, _} -> ok;
                Other -> error({schema_error, Other})
            end
        end,
        Statements
    ),
    ok.

load_schema_statements() ->
    Paths = schema_paths(),
    case read_first_existing(Paths) of
        {ok, Bin} ->
            [unicode:characters_to_binary(string:trim(S))
             || S <- string:split(binary_to_list(Bin), ";", all),
                string:trim(S) =/= []];
        {error, Reason} ->
            error({schema_file_error, Paths, Reason})
    end.

schema_paths() ->
    PrivPath =
        case code:priv_dir(time_tracker) of
            {error, bad_name} -> undefined;
            Dir -> filename:join(Dir, "db/schema.sql")
        end,
    LocalPath = filename:join(["include", "db", "schema.sql"]),
    [P || P <- [PrivPath, LocalPath], P =/= undefined].

read_first_existing([]) ->
    {error, enoent};
read_first_existing([Path | Rest]) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            {ok, Bin};
        {error, enoent} ->
            read_first_existing(Rest);
        {error, Reason} ->
            {error, {Path, Reason}}
    end.
