-module(tuna_amqp).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("tuna.hrl").

-export([
	open/1,
	declare_exchange/1,
	consume/3
]).

open(Name) ->
	ConnProps = [{<<"connection_name">>, longstr, atom_to_binary(Name)}],
	Host = tuna_config:amqp_host(),
	Port = tuna_config:amqp_port(),
	AmqpParams = #amqp_params_network{host = Host, port = Port, client_properties = ConnProps},
	{ok, AMQPConn} = amqp_connection:start(AmqpParams),
	{ok, AMQPChan} = amqp_connection:open_channel(AMQPConn),
	{ok, #{
		conn => AMQPConn,
		chan => AMQPChan,
		conn_mref => erlang:monitor(process, AMQPConn),
		chan_mref => erlang:monitor(process, AMQPChan)
	}}.

declare_exchange(AMQPChan) ->
	Declare = #'exchange.declare'{exchange = ?EXCHANGE, type = <<"topic">>, durable = true},
	#'exchange.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	ok.

consume(AMQPChan, QueueType, Name) ->
	Queue = queue_name(QueueType, Name),
	Declare = #'queue.declare'{
		queue = Queue,
		auto_delete = false,
		exclusive = false,
		durable = true,
		arguments = queue_arguments(QueueType)
	},
	Bind = #'queue.bind'{queue = Queue, exchange = ?EXCHANGE},
	Qos = #'basic.qos'{prefetch_count = 250},
	Consume = #'basic.consume'{queue = Queue, no_ack = false},
	#'basic.qos_ok'{} = amqp_channel:call(AMQPChan, Qos),
	#'queue.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	#'queue.bind_ok'{} = amqp_channel:call(AMQPChan, Bind),
	#'basic.consume_ok'{} = amqp_channel:call(AMQPChan, Consume),
	ok.

queue_name(classic, Name) ->
	<<"rb_classic_queue_", (atom_to_binary(Name))/binary>>;
queue_name(quorum, Name) ->
	<<"rb_quorum_queue_", (atom_to_binary(Name))/binary>>.

queue_arguments(classic) ->
	[];
queue_arguments(quorum) ->
	[{<<"x-queue-type">>, longstr, <<"quorum">>}].

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

classic_queue_name_test() ->
	?assertEqual(<<"rb_classic_queue_tuna_classic_consumer_1">>,
		queue_name(classic, tuna_classic_consumer_1)).

quorum_queue_name_test() ->
	?assertEqual(<<"rb_quorum_queue_tuna_quorum_consumer_1">>,
		queue_name(quorum, tuna_quorum_consumer_1)).

classic_queue_arguments_test() ->
	?assertEqual([], queue_arguments(classic)).

quorum_queue_arguments_test() ->
	?assertEqual([{<<"x-queue-type">>, longstr, <<"quorum">>}], queue_arguments(quorum)).

-endif.
