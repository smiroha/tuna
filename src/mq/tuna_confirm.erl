-module(tuna_confirm).

-export([settle/3]).

settle(DeliveryTag, true, Inflight0) ->
	maps:fold(
		fun(Tag, _Seq, {Cnt, Acc}) when Tag =< DeliveryTag ->
			{Cnt + 1, Acc};
		   (Tag, Seq, {Cnt, Acc}) ->
			{Cnt, maps:put(Tag, Seq, Acc)}
		end,
		{0, #{}},
		Inflight0
	);
settle(DeliveryTag, false, Inflight0) ->
	case maps:take(DeliveryTag, Inflight0) of
		{_Seq, Inflight1} -> {1, Inflight1};
		error -> {0, Inflight0}
	end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

settle_single_confirm_test() ->
	Inflight = #{1 => 101, 2 => 102},
	?assertEqual({1, #{1 => 101}}, settle(2, false, Inflight)).

settle_missing_single_confirm_test() ->
	Inflight = #{1 => 101},
	?assertEqual({0, Inflight}, settle(2, false, Inflight)).

settle_multiple_confirm_test() ->
	Inflight = #{1 => 101, 2 => 102, 3 => 103},
	?assertEqual({2, #{3 => 103}}, settle(2, true, Inflight)).

settle_empty_multiple_confirm_test() ->
	?assertEqual({0, #{}}, settle(2, true, #{})).

-endif.
