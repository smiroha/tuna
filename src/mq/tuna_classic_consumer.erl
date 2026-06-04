-module(tuna_classic_consumer).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("tuna.hrl").

-export([start_link/1]).
-export([init/1, handle_continue/2, handle_info/2, handle_call/3, handle_cast/2, terminate/2]).


start_link(Name) ->
	gen_server:start_link({local, Name}, ?MODULE, [Name], []).

init([Name]) ->
	_ = process_flag(trap_exit, true),
	{ok, #{name => Name}, {continue, connect}}.

handle_continue(connect, OldState = #{name := Name}) ->
	{ok, State} = connect(OldState),
	logger:info("consumer:~p (re)connected", [Name]),
	{noreply, State}.

handle_call(_, _, State) -> {reply, ok, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info({#'basic.deliver'{delivery_tag = DeliveryTag, redelivered = Redelivered},
			{amqp_msg, #'P_basic'{}, Content}},
			State0 = #{name := Name, channel := Chan}) ->
	#{from := From, seq := Seq} = binary_to_term(Content),
	tuna_metrics:inc(consumer_received_total, [{queue_type, QueueType = classic}, {consumer, Name}]),
	case Redelivered of
		true -> tuna_metrics:inc(consumer_redelivered_total, [{queue_type, QueueType}, {consumer, Name}]);
		false -> ok
	end,
	case tuna_seq_srv:observe(Name, QueueType, From, Seq) of
		{in_order, _} ->
			ok;
		{gap, Gap} ->
			tuna_metrics:add(consumer_gap_total, [{queue_type, QueueType}, {consumer, Name}], Gap),
			logger:error("consumer:~p type:~p from:~p seq gap detected got:~p gap:~p", [Name, QueueType, From, Seq, Gap]);
		{duplicate, _} ->
			tuna_metrics:inc(consumer_duplicate_total, [{queue_type, QueueType}, {consumer, Name}]),
			logger:warning("consumer:~p type:~p from:~p duplicate/out-of-order got:~p", [Name, QueueType, From, Seq])
	end,
	ok = amqp_channel:cast(Chan, #'basic.ack'{delivery_tag = DeliveryTag, multiple = false}),
	tuna_metrics:inc(consumer_ack_total, [{queue_type, QueueType}, {consumer, Name}]),
	if Seq rem 1000 =:= 0 -> logger:info("consumer:~p type:~p from:~p reached seq:~p", [Name, QueueType, From, Seq]); true -> ok end,
	{noreply, State0};
handle_info(#'basic.consume_ok'{}, State) -> {noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{name := Name, amqp_conn_mref := MRef}) ->
	tuna_metrics:inc(amqp_down_total, lifecycle_labels(Name, conn)),
	{stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{name := Name, amqp_chan_mref := MRef}) ->
	tuna_metrics:inc(amqp_down_total, lifecycle_labels(Name, chan)),
	{stop, {died_chan, Reason}, State};
handle_info(Msg, State = #{name := Name}) ->
	logger:warning("consumer:~p handle unexpected msg:~p", [Name, Msg]),
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("consumer:~p terminated by reason:~p", [Name, Reason]),
	timer:sleep(3000),
	ok.


%% @private
connect(State = #{name := Name}) ->
	{ok, #{chan := AMQPChan, conn_mref := AMQPConnMRef, chan_mref := AMQPChanMRef}} = tuna_amqp:open(Name),
	ok = tuna_amqp:consume(AMQPChan, classic, Name),
	tuna_metrics:inc(amqp_connect_total, lifecycle_labels(Name, conn)),
	{ok, State#{channel => AMQPChan, amqp_conn_mref => AMQPConnMRef, amqp_chan_mref => AMQPChanMRef}}.

%% @private
lifecycle_labels(Name, Target) ->
	[{role, classic_consumer}, {worker, Name}, {target, Target}].
