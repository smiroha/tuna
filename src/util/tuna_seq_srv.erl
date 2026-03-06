-module(tuna_seq_srv).

-behaviour(gen_server).

-export([
	start_link/0,
	next_pub_seq/1,
	observe/4,
	consumer_progress/2
]).

-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2
]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

next_pub_seq(Publisher) ->
	gen_server:call(?MODULE, {next_pub_seq, Publisher}).

observe(Consumer, QueueType, From, Seq) ->
	gen_server:call(?MODULE, {observe, Consumer, QueueType, From, Seq}).

consumer_progress(Consumer, QueueType) ->
	gen_server:call(?MODULE, {consumer_progress, Consumer, QueueType}).

init([]) ->
	{ok, #{pub_seq => #{}, consumer_expected => #{}}}.

handle_call({next_pub_seq, Publisher}, _From, State0 = #{pub_seq := PubSeq0}) ->
	Next = maps:get(Publisher, PubSeq0, 0) + 1,
	PubSeq1 = maps:put(Publisher, Next, PubSeq0),
	{reply, Next, State0#{pub_seq => PubSeq1}};
handle_call({observe, Consumer, QueueType, From, Seq}, _From, State0 = #{consumer_expected := Expected0}) ->
	Key = {Consumer, QueueType, From},
	ExpectedSeq = maps:get(Key, Expected0, 1),
	case Seq of
		ExpectedSeq ->
			Expected1 = maps:put(Key, ExpectedSeq + 1, Expected0),
			{reply, {in_order, 0}, State0#{consumer_expected => Expected1}};
		_ when Seq > ExpectedSeq ->
			Gap = Seq - ExpectedSeq,
			Expected1 = maps:put(Key, Seq + 1, Expected0),
			{reply, {gap, Gap}, State0#{consumer_expected => Expected1}};
		_ ->
			{reply, {duplicate, 0}, State0}
	end;
handle_call({consumer_progress, Consumer, QueueType}, _From, State = #{consumer_expected := Expected}) ->
	Rows = [
		{From, NextSeq}
		|| {{C, QT, From}, NextSeq} <- maps:to_list(Expected),
		   C =:= Consumer,
		   QT =:= QueueType
	],
	{reply, Rows, State};
handle_call(_, _From, State) ->
	{reply, ok, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info(_, State) ->
	{noreply, State}.

terminate(_, _) ->
	ok.
