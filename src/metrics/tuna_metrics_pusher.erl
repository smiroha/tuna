-module(tuna_metrics_pusher).

-include("tuna.hrl").

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
	IntervalMs = tuna_config:metrics_interval(),
	PushUrl = tuna_config:metrics_url(),
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
