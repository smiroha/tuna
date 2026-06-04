-module(tuna_metrics).

-behaviour(gen_server).

-export([
	start_link/0,
	inc/2,
	add/3,
	set/3,
	to_prometheus/0
]).

-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2
]).

-define(TABLE, ?MODULE).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

inc(Name, Labels) ->
	add(Name, Labels, 1).

add(Name, Labels, Incr) when is_integer(Incr) ->
	Key = {counter, Name, normalize_labels(Labels)},
	_ = ets:update_counter(?TABLE, Key, {2, Incr}, {Key, 0}),
	ok.

set(Name, Labels, Value) when is_integer(Value) ->
	Key = {gauge, Name, normalize_labels(Labels)},
	true = ets:insert(?TABLE, {Key, Value}),
	ok.

to_prometheus() ->
	Rows = ets:tab2list(?TABLE),
	Lines = [format_row(Row) || Row <- Rows],
	iolist_to_binary(Lines).

init([]) ->
	_ = ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}, {write_concurrency, true}]),
	{ok, #{}}.

handle_call(_, _From, State) ->
	{reply, ok, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info(_, State) ->
	{noreply, State}.

terminate(_, _) ->
	ok.

format_row({{Type, Name, Labels}, Value}) ->
	Metric = metric_name(Type, Name),
	LabelText = format_labels(Labels),
	io_lib:format("~s~s ~B~n", [Metric, LabelText, Value]).

metric_name(counter, Name) ->
	"tuna_" ++ atom_to_list(Name);
metric_name(gauge, Name) ->
	"tuna_" ++ atom_to_list(Name).

normalize_labels(Labels) when is_list(Labels) ->
	lists:sort([{to_atom(K), to_bin(V)} || {K, V} <- [{run_id, tuna_config:metrics_run_id()} | Labels]]).

format_labels([]) ->
	"";
format_labels(Labels) ->
	Pairs = [io_lib:format("~s=\"~s\"", [atom_to_list(K), escape(V)]) || {K, V} <- Labels],
	[$\{, string:join([lists:flatten(P) || P <- Pairs], ","), $\}].

escape(Bin) ->
	Str = binary_to_list(Bin),
	lists:flatten(string:replace(Str, "\"", "\\\"", all)).

to_atom(Value) when is_atom(Value) -> Value;
to_atom(Value) when is_binary(Value) -> binary_to_atom(Value);
to_atom(Value) when is_list(Value) -> list_to_atom(Value).

to_bin(Value) when is_binary(Value) -> Value;
to_bin(Value) when is_atom(Value) -> atom_to_binary(Value);
to_bin(Value) when is_integer(Value) -> integer_to_binary(Value);
to_bin(Value) when is_list(Value) -> iolist_to_binary(Value).
