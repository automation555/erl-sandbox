
-module(test).

-compile(export_all).

test() ->
    XX = 10,
    A = fun(YY) ->
		XX + YY
	end,
    A().

test2(Param) ->
    A = Param,
    case Param of
	true ->
	    foo;
	false ->
	    bar
    end.