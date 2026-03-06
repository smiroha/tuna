-module(tuna_super_sup).

-behaviour(supervisor).

-define(CHILD(Id, M, F, A),
	#{id => Id, start => {M, F, A}, restart => permanent, shutdown => 5000, type => worker}
).

-define(DEF_P_CNT, 3).
-define(DEF_Q_CON_CNT, 5).
-define(DEF_C_CNT, 5).

-export([
	start_link/0,
	init/1
]).


start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).


init([]) ->
	SeqSpec = ?CHILD(tuna_seq_srv, tuna_seq_srv, start_link, []),
	MetricsSpec = ?CHILD(tuna_metrics_pusher, tuna_metrics_pusher, start_link, []),
	PubSpecs     = [make_spec(tuna_publisher,        I) || I <- lists:seq(1, ?DEF_P_CNT)],
	QuorumSpecs  = [make_spec(tuna_quorum_consumer,  I) || I <- lists:seq(1, ?DEF_Q_CON_CNT)],
	ClassicSpecs = [make_spec(tuna_classic_consumer, I) || I <- lists:seq(1, ?DEF_C_CNT)],
	{ok, {{one_for_one, 10, 30}, [SeqSpec, MetricsSpec | PubSpecs ++ QuorumSpecs ++ ClassicSpecs]}}.


%% @private
make_spec(Module, Index) ->
	Name = binary_to_atom(<<(atom_to_binary(Module))/binary, "_", (integer_to_binary(Index))/binary>>),
	?CHILD(Name, Module, start_link, [Name]).
