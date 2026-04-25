-module(time_tracker_json).

-export([decode/1, encode/1]).

decode(Bin) when is_binary(Bin) ->
    try
        {ok, jsx:decode(Bin, [return_maps])}
    catch
        _:_ -> {error, invalid_json}
    end.

encode(Data) ->
    jsx:encode(Data).
