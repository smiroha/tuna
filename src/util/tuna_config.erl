-module(tuna_config).

-include("tuna.hrl").

-export([
	amqp_host/0,
	amqp_port/0,
	publisher_interval/0,
	publisher_size/0,
	metrics_interval/0,
	metrics_url/0,
	publisher_count/0,
	classic_consumer_count/0,
	quorum_consumer_count/0,
	metrics_run_id/0
]).

amqp_host() ->
	path([amqp, host], "localhost").

amqp_port() ->
	path([amqp, port], 5672).

publisher_interval() ->
	path([amqp, publisher, interval], 25).

publisher_size() ->
	path([amqp, publisher, size], 1).

metrics_interval() ->
	path([metrics, interval], 5000).

metrics_url() ->
	path([metrics, url], default_push_url()).

publisher_count() ->
	path([process_counts, publishers], 3).

classic_consumer_count() ->
	path([process_counts, classic_consumers], 5).

quorum_consumer_count() ->
	path([process_counts, quorum_consumers], 5).

metrics_run_id() ->
	path([metrics, run_id], "local").

path(Keys, Default) ->
	Env = application:get_all_env(?APP),
	lookup(Keys, Env, Default).

lookup([], Value, _Default) ->
	Value;
lookup([Key | Rest], Context, Default) when is_list(Context) ->
	case proplists:get_value(Key, Context, undefined) of
		undefined -> Default;
		Value -> lookup(Rest, Value, Default)
	end;
lookup(_Keys, _Context, Default) ->
	Default.

default_push_url() ->
	Instance = atom_to_list(node()),
	"http://localhost:9091/metrics/job/tuna/instance/" ++ Instance.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

process_count_defaults_test() ->
	clear_tuna_env(),
	?assertEqual(3, publisher_count()),
	?assertEqual(5, classic_consumer_count()),
	?assertEqual(5, quorum_consumer_count()).

process_count_configured_values_test() ->
	clear_tuna_env(),
	application:set_env(?APP, process_counts, [
		{publishers, 7},
		{classic_consumers, 8},
		{quorum_consumers, 9}
	]),
	?assertEqual(7, publisher_count()),
	?assertEqual(8, classic_consumer_count()),
	?assertEqual(9, quorum_consumer_count()),
	clear_tuna_env().

metrics_run_id_default_and_configured_test() ->
	clear_tuna_env(),
	?assertEqual("local", metrics_run_id()),
	application:set_env(?APP, metrics, [{run_id, "test-run"}]),
	?assertEqual("test-run", metrics_run_id()),
	clear_tuna_env().

clear_tuna_env() ->
	[application:unset_env(?APP, Key) || {Key, _Value} <- application:get_all_env(?APP)],
	ok.

-endif.
