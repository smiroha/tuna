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
	{Acked, Inflight1} = settle_confirms(DeliveryTag, Multiple, Inflight0),
	tuna_metrics:add(publish_confirm_ack_total, [{publisher, Name}], Acked),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], maps:size(Inflight1)),
	{noreply, State#{inflight => Inflight1}};
handle_info(#'basic.nack'{delivery_tag = DeliveryTag, multiple = Multiple}, State = #{name := Name, inflight := Inflight0}) ->
	{Nacked, Inflight1} = settle_confirms(DeliveryTag, Multiple, Inflight0),
	tuna_metrics:add(publish_confirm_nack_total, [{publisher, Name}], Nacked),
	tuna_metrics:set(publisher_inflight, [{publisher, Name}], maps:size(Inflight1)),
	{noreply, State#{inflight => Inflight1}};
handle_info({#'basic.return'{}, _Msg}, State = #{name := Name}) ->
	tuna_metrics:inc(publish_return_total, [{publisher, Name}]),
	{noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) ->
	{stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) ->
	{stop, {died_chan, Reason}, State};
handle_info(_, State) ->
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("publisher:~p terminated by reason:~p", [Name, Reason]),
	timer:sleep(3000),
	ok.

%% @private
connect(State = #{name := Name}) ->
	ConnProps = [{<<"connection_name">>, longstr, atom_to_binary(Name)}],
	Host = tuna_config:amqp_host(),
	Port = tuna_config:amqp_port(),
	AmqpParams = #amqp_params_network{host = Host, port = Port, client_properties = ConnProps},
	{ok, AMQPConn} = amqp_connection:start(AmqpParams),
	{ok, AMQPChan} = amqp_connection:open_channel(AMQPConn),
	AMQPConnMRef = erlang:monitor(process, AMQPConn),
	AMQPChanMRef = erlang:monitor(process, AMQPChan),
	Declare = #'exchange.declare'{exchange = ?EXCHANGE, type = <<"topic">>, durable = true},
	Confirm = #'confirm.select'{},
	#'exchange.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	#'confirm.select_ok'{} = amqp_channel:call(AMQPChan, Confirm),
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
settle_confirms(DeliveryTag, true, Inflight0) ->
	maps:fold(
		fun(Tag, _Seq, {Cnt, Acc}) when Tag =< DeliveryTag ->
			{Cnt + 1, Acc};
		   (Tag, Seq, {Cnt, Acc}) ->
			{Cnt, maps:put(Tag, Seq, Acc)}
		end,
		{0, #{}},
		Inflight0
	);
settle_confirms(DeliveryTag, false, Inflight0) ->
	case maps:take(DeliveryTag, Inflight0) of
		{_Seq, Inflight1} -> {1, Inflight1};
		error -> {0, Inflight0}
	end.
