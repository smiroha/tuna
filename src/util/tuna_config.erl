-module(tuna_config).

-include("tuna.hrl").

-export([
	amqp_host/0,
	amqp_port/0,
	publisher_interval/0,
	publisher_size/0,
	metrics_interval/0,
	metrics_url/0
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
