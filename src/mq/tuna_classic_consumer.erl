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
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) -> {stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) -> {stop, {died_chan, Reason}, State};
handle_info(Msg, State = #{name := Name}) ->
	logger:warning("consumer:~p handle unexpected msg:~p", [Name, Msg]),
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("consumer:~p terminated by reason:~p", [Name, Reason]),
	timer:sleep(3000),
	ok.


%% @private
connect(State = #{name := Name}) ->
	ConnProps = [{<<"connection_name">>, longstr, atom_to_binary(Name)}],
	Host = application:get_env(?APP, amqp_host, "localhost"),
	Port = application:get_env(?APP, amqp_port, 5672),
	AmqpParams = #amqp_params_network{host = Host, port = Port, client_properties = ConnProps},
	{ok, AMQPConn} = amqp_connection:start(AmqpParams),
	{ok, AMQPChan} = amqp_connection:open_channel(AMQPConn),
	AMQPConnMRef = erlang:monitor(process, AMQPConn),
	AMQPChanMRef = erlang:monitor(process, AMQPChan),
	Queue = <<"rb_classic_queue_", (atom_to_binary(Name))/binary>>,
	Declare = #'queue.declare'{queue = Queue, durable = true},
	Bind = #'queue.bind'{queue = Queue, exchange = ?EXCHANGE},
	Qos = #'basic.qos'{prefetch_count = 250},
	Consume = #'basic.consume'{queue = Queue, no_ack = false},
	#'basic.qos_ok'{} = amqp_channel:call(AMQPChan, Qos),
	#'queue.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	#'queue.bind_ok'{} = amqp_channel:call(AMQPChan, Bind),
	#'basic.consume_ok'{} = amqp_channel:call(AMQPChan, Consume),
	{ok, State#{channel => AMQPChan, amqp_conn_mref => AMQPConnMRef, amqp_chan_mref => AMQPChanMRef}}.
