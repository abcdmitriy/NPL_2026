-module(timer_server).
-export([start/0]).

% Запуск сервера на порту 4000
start() ->
    case gen_tcp:listen(4000, [
        binary,
        {packet, line},
        {active, false},
        {reuseaddr, true}
    ]) of
        {ok, Listen} ->
            io:format("Server listening on port 4000...~n"),
            accept(Listen);
        {error, Reason} ->
            io:format("Server error: ~p~n", [Reason]),
            {error, Reason}
    end.

% Ожидание новых подключений
accept(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} ->
            ClientPid = spawn(fun() ->
                receive
                    start -> client_loop(Socket, #{})
                end
            end),

            case gen_tcp:controlling_process(Socket, ClientPid) of
                ok ->
                    ClientPid ! start;
                {error, _Reason} ->
                    gen_tcp:close(Socket),
                    exit(ClientPid, kill)
            end,

            accept(Listen);

        {error, Reason} ->
            io:format("Accept error: ~p~n", [Reason]),
            ok
    end.

% Цикл обработки сообщений клиента и таймеров
client_loop(Socket, Timers) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            receive
                {tcp, Socket, Bin} ->
                    Tokens = string:tokens(
                        binary_to_list(Bin),
                        " \t\r\n"
                    ),

                    case handle_cmd(Tokens, Socket, Timers) of
                        {continue, NewTimers} ->
                            client_loop(Socket, NewTimers);
                        quit ->
                            stop_all(Timers),
                            gen_tcp:close(Socket)
                    end;

                {tcp_closed, Socket} ->
                    stop_all(Timers);

                {tcp_error, Socket, _Reason} ->
                    stop_all(Timers),
                    gen_tcp:close(Socket);

                {expired, Name, TimerPid} ->
                    case maps:find(Name, Timers) of
                        {ok, {TimerPid, _Deadline}} ->
                            gen_tcp:send(
                                Socket,
                                io_lib:format(
                                    "EXPIRED ~s~n",
                                    [Name]
                                )
                            ),
                            NewTimers = maps:remove(Name, Timers),
                            client_loop(Socket, NewTimers);

                        _ ->
                            client_loop(Socket, Timers)
                    end;

                _ ->
                    client_loop(Socket, Timers)
            end;

        {error, _Reason} ->
            stop_all(Timers),
            gen_tcp:close(Socket)
    end.

% Обработка команды START
handle_cmd(["START", Name, SecStr], Socket, Timers) ->
    case parse_seconds(SecStr) of
        {ok, Sec} ->
            case maps:is_key(Name, Timers) of
                true ->
                    gen_tcp:send(
                        Socket,
                        io_lib:format(
                            "Error: timer '~s' already exists~n",
                            [Name]
                        )
                    ),
                    {continue, Timers};

                false ->
                    ClientPid = self(),

                    TimerPid = spawn_link(fun() ->
                        timer_wait(Name, Sec, ClientPid)
                    end),

                    Deadline = now_ms() + Sec * 1000,

                    gen_tcp:send(
                        Socket,
                        io_lib:format(
                            "Timer '~s' started (~p sec)~n",
                            [Name, Sec]
                        )
                    ),

                    {continue, maps:put(
                        Name,
                        {TimerPid, Deadline},
                        Timers
                    )}
            end;

        error ->
            gen_tcp:send(
                Socket,
                "Error: seconds must be a non-negative integer\n"
            ),
            {continue, Timers}
    end;

% Обработка команды STOP
handle_cmd(["STOP", Name], Socket, Timers) ->
    case maps:find(Name, Timers) of
        {ok, {Pid, _Deadline}} ->
            Pid ! stop,

            gen_tcp:send(
                Socket,
                io_lib:format(
                    "Timer '~s' stopped~n",
                    [Name]
                )
            ),

            {continue, maps:remove(Name, Timers)};

        error ->
            gen_tcp:send(
                Socket,
                io_lib:format(
                    "Error: timer '~s' not found~n",
                    [Name]
                )
            ),
            {continue, Timers}
    end;

% Обработка команды LIST
handle_cmd(["LIST"], Socket, Timers) ->
    case map_size(Timers) of
        0 ->
            gen_tcp:send(Socket, "No active timers\n");

        _ ->
            Now = now_ms(),

            lists:foreach(fun({Name, {_Pid, Deadline}}) ->
                LeftMs = erlang:max(0, Deadline - Now),
                LeftSec = (LeftMs + 999) div 1000,

                gen_tcp:send(
                    Socket,
                    io_lib:format(
                        "~s: ~p sec left~n",
                        [Name, LeftSec]
                    )
                )
            end, maps:to_list(Timers))
    end,

    {continue, Timers};

% Обработка команды QUIT
handle_cmd(["QUIT"], _Socket, _Timers) ->
    quit;

% Неизвестная или некорректная команда
handle_cmd(_, Socket, Timers) ->
    gen_tcp:send(
        Socket,
        "Error: unknown or invalid command\n"
    ),
    {continue, Timers}.

% Проверка количества секунд
parse_seconds(Str) ->
    try list_to_integer(Str) of
        Sec when Sec >= 0 ->
            {ok, Sec};
        _ ->
            error
    catch
        error:badarg ->
            error
    end.

% Процесс таймера
timer_wait(Name, Sec, ClientPid) ->
    receive
        stop ->
            ok
    after Sec * 1000 ->
        ClientPid ! {expired, Name, self()}
    end.

% Остановка всех таймеров клиента
stop_all(Timers) ->
    maps:fold(
        fun(_Name, {Pid, _Deadline}, Acc) ->
            Pid ! stop,
            Acc
        end,
        ok,
        Timers
    ).

% Текущее время в миллисекундах (для старых версий Erlang)
now_ms() ->
    {MegaSecs, Secs, MicroSecs} = erlang:now(),
    ((MegaSecs * 1000000 + Secs) * 1000) +
    (MicroSecs div 1000).