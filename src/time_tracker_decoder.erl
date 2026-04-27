-module(time_tracker_decoder).

-export([decode/1, encode/1]).

-type decode_error() :: invalid_json.

-spec decode(binary()) -> {ok, term()} | {error, decode_error()}.
decode(Bin) when is_binary(Bin) ->
    try
        {ok, jsx:decode(Bin, [return_maps])}
    catch
        _:_ -> {error, invalid_json}
    end.

-spec encode(term()) -> binary().
encode(Data) ->
    jsx:encode(Data).
