-module(tuna_publisher).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("tuna.hrl").

-export([
	start_link/1,
	init/1,
	handle_continue/2,
	handle_info/2, handle_call/3, handle_cast/2,
	terminate/2
]).


start_link(Name) ->
	gen_server:start_link({local, Name}, ?MODULE, [Name], []).

init([Name]) ->
	_ = process_flag(trap_exit, true),
	State = #{
		name => Name,
		publish_interval_ms => tuna_config:publisher_interval(),
		publish_batch_size => tuna_config:publisher_size(),
		next_delivery_tag => 1,
		inflight => #{}
	},
	{ok, State, {continue, connect}}.

handle_continue(connect, State = #{name := Name}) ->
	case connect(State) of
		{ok, NewState} ->
			timer:send_after(10, publish_tick),
			{noreply, NewState};
		{error, Reason} ->
			logger:error("publisher:~p (re)connected failed, reason:~p", [Name, Reason]),
			{stop, connect_failed, State}
	end.

handle_call(_, _, State) ->
	{reply, ok, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info(publish_tick, State0 = #{publish_batch_size := BatchSize, publish_interval_ms := IntervalMs}) ->
	State1 = lists:foldl(fun(_, Acc) -> publish_one(Acc) end, State0, lists:seq(1, BatchSize)),
	timer:send_after(IntervalMs, publish_tick),
	{noreply, State1};
handle_info(#'basic.ack'{delivery_tag = DeliveryTag, multiple = Multiple}, State = #{name := Name, inflight := Inflight0}) ->
	{Acked, Inflight1} = tuna_confirm:settle(DeliveryTag, Multiple, Inflight0),
	tuna_metrics:add(publish_confirm_ack_total, [{publisher, Name}], Acked),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], maps:size(Inflight1)),
	{noreply, State#{inflight => Inflight1}};
handle_info(#'basic.nack'{delivery_tag = DeliveryTag, multiple = Multiple}, State = #{name := Name, inflight := Inflight0}) ->
	{Nacked, Inflight1} = tuna_confirm:settle(DeliveryTag, Multiple, Inflight0),
	tuna_metrics:add(publish_confirm_nack_total, [{publisher, Name}], Nacked),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], maps:size(Inflight1)),
	{noreply, State#{inflight => Inflight1}};
handle_info({#'basic.return'{}, _Msg}, State = #{name := Name}) ->
	tuna_metrics:inc(publish_return_total, [{publisher, Name}]),
	{noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) ->
	tuna_metrics:inc(amqp_down_total, lifecycle_labels(publisher, maps:get(name, State), conn)),
	{stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) ->
	tuna_metrics:inc(amqp_down_total, lifecycle_labels(publisher, maps:get(name, State), chan)),
	{stop, {died_chan, Reason}, State};
handle_info(_, State) ->
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("publisher:~p terminated by reason:~p", [Name, Reason]),
	timer:sleep(3000),
	ok.

%% @private
connect(State = #{name := Name}) ->
	{ok, #{conn := AMQPConn, chan := AMQPChan, conn_mref := AMQPConnMRef, chan_mref := AMQPChanMRef}} =
		tuna_amqp:open(Name),
	Confirm = #'confirm.select'{},
	ok = tuna_amqp:declare_exchange(AMQPChan),
	#'confirm.select_ok'{} = amqp_channel:call(AMQPChan, Confirm),
	tuna_metrics:inc(amqp_connect_total, lifecycle_labels(publisher, Name, conn)),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], 0),
	{ok, State#{
		amqp_conn => AMQPConn,
		amqp_chan => AMQPChan,
		channel => AMQPChan,
		amqp_conn_mref => AMQPConnMRef,
		amqp_chan_mref => AMQPChanMRef,
		next_delivery_tag => 1,
		inflight => #{}
	}}.

%% @private
publish_one(State0 = #{
	name := Name,
	channel := Chan,
	next_delivery_tag := Tag0,
	inflight := Inflight0
}) ->
	Seq = tuna_seq_srv:next_pub_seq(Name),
	Method = #'basic.publish'{exchange = ?EXCHANGE, routing_key = <<"bench">>, mandatory = true},
	Payload = term_to_binary(#{seq => Seq, from => Name}),
	Content = #amqp_msg{props = #'P_basic'{delivery_mode = 2}, payload = Payload},
	ok = amqp_channel:cast(Chan, Method, Content),
	tuna_metrics:inc(published_total, [{publisher, Name}]),
	Inflight1 = maps:put(Tag0, Seq, Inflight0),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], maps:size(Inflight1)),
	State0#{next_delivery_tag => Tag0 + 1, inflight => Inflight1}.

%% @private
lifecycle_labels(Role, Name, Target) ->
	[{role, Role}, {worker, Name}, {target, Target}].
