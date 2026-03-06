-module(tuna_metrics_pusher).

-behaviour(gen_server).

-export([
	start_link/0,
	init/1,
	handle_info/2,
	handle_call/3,
	handle_cast/2,
	terminate/2
]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
	ok = tuna_metrics:init(),
	{ok, _} = application:ensure_all_started(inets),
	IntervalMs = application:get_env(tuna, metrics_push_interval_ms, 5000),
	PushUrl = application:get_env(tuna, pushgateway_url, default_push_url()),
	timer:send_after(1000, push),
	{ok, #{interval_ms => IntervalMs, push_url => PushUrl}}.

handle_call(_, _, State) ->
	{reply, ok, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info(push, State = #{interval_ms := IntervalMs, push_url := PushUrl}) ->
	Body = tuna_metrics:to_prometheus(),
	Req = {PushUrl, [], "text/plain", Body},
	case httpc:request(put, Req, [{timeout, 5000}], []) of
		{ok, _} -> ok;
		{error, Reason} ->
			logger:warning("metrics push failed url:~p reason:~p", [PushUrl, Reason])
	end,
	timer:send_after(IntervalMs, push),
	{noreply, State};
handle_info(_, State) ->
	{noreply, State}.

terminate(_, _) ->
	ok.

default_push_url() ->
	Instance = atom_to_list(node()),
	"http://localhost:9091/metrics/job/tuna/instance/" ++ Instance.
