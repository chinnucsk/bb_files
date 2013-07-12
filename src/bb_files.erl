-module(bb_files).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).
-export([start_link/1, stop/0, next_file/1, find_file/1]).
-export([keygen/2, valgen/1]).
-include_lib("kernel/include/file.hrl").

-record(state, {next, map=dict:new()}).

start_link(Dir) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Dir, []).

next_file(Id) ->
    gen_server:call(?MODULE, {next_file, Id}).

read_file(Id) ->
    gen_server:call(?MODULE, {read_file, Id}).

stop() ->
    gen_server:call(?MODULE, stop).

init(Dir) ->
    F = fun() -> find_file(Dir) end,
    {ok, #state{next=F}}.

handle_call({next_file, Id}, _From, S=#state{}) ->
    case (S#state.next)() of
        {continue, Path, Next} ->
            Map = dict:store(Id, Path, S#state.map),
            {reply, {ok, filename:basename(Path)}, S#state{next=Next, map=Map}};
        done ->
            {reply, done, S}
    end;

handle_call({read_file, Id}, _From, S=#state{}) ->
    Path = dict:fetch(Id, S#state.map),
    {reply, file:read_file(Path), S};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

keygen(Id, Dir) ->
    case whereis(?MODULE) of
        undefined -> start_link(Dir);
        _ -> ok
    end,
    fun() ->
        case next_file(Id) of
            {ok, File} -> File;
            done -> throw({stop, complete})
        end
    end.

valgen(Id) ->
    fun() ->
        {ok, Bin} = read_file(Id),
        Bin
    end.

find_file(Dir) ->
    find_file(Dir, queue:new()).

find_file(Name, Q) ->
    {ok, F=#file_info{}} = file:read_file_info(Name),
    case F#file_info.type of
        directory -> handle_directory(Name, Q);
        regular -> handle_regular_file(Name, Q);
        _ -> dequeue_and_run(Q)
    end.

handle_directory(Dir, Q) ->
    case file:list_dir(Dir) of
        {ok, []} ->
            dequeue_and_run(Q);
        {ok, Files} ->
            dequeue_and_run(enqueue_many(Dir, Files, Q));
        {error, _} ->
            dequeue_and_run(Q)
    end.

dequeue_and_run(Q) ->
    case queue:out(Q) of
        {empty, _} -> done;
        {{value, File}, NewQ} -> find_file(File, NewQ)
    end.

enqueue_many(Dir, Files, Queue) ->
    F = fun(File, Q) -> queue:in(filename:join(Dir, File), Q) end,
    lists:foldl(F, Queue, Files).

handle_regular_file(Name, Q) ->
    {continue, Name, fun() -> dequeue_and_run(Q) end}.