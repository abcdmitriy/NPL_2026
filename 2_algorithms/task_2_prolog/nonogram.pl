
% Чтение входных данных из файла
read_input(File, N, M, RowClues, ColClues) :-
    open(File, read, Stream),
    read_lines(Stream, Lines),
    close(Stream),
    include(non_empty_string, Lines, NonEmptyLines),
    maplist(string_to_ints, NonEmptyLines, IntLines),
    [[N, M]|Rest] = IntLines,
    length(RowClues, N),
    length(ColClues, M),
    append(RowClues, ColClues, Rest).

read_lines(Stream, []) :-
    at_end_of_stream(Stream), !.
read_lines(Stream, [Line|Rest]) :-
    read_line_to_string(Stream, Line),
    read_lines(Stream, Rest).

non_empty_string(Str) :-
    string_length(Str, L),
    L > 0.

string_to_ints(Str, Ints) :-
    split_string(Str, " ", " ", Parts),
    maplist(number_string, Ints, Parts).

% Решение нонограммы с возвратом
solve_nonogram(N, M, RowClues, ColClues, Grid) :-
    length(RowClues, N),
    length(ColClues, M),
    solve_rows(RowClues, ColClues, N, M, [], Grid),
    transpose(Grid, ColGrid),
    maplist(line_value, ColGrid, ColClues).

% Последовательное построение строк
solve_rows([], _, _, _, Acc, Grid) :-
    reverse(Acc, Grid).

solve_rows([Clue|Clues], ColClues, N, M, Acc, Grid) :-
    length(Row, M),
    maplist(between(0, 1), Row),
    line_value(Row, Clue),
    NewAcc = [Row|Acc],
    reverse(NewAcc, Rows),
    partial_columns_compatible(Rows, ColClues, N),
    solve_rows(Clues, ColClues, N, M, NewAcc, Grid).

% Проверка частично заполненных столбцов
partial_columns_compatible(Rows, ColClues, N) :-
    transpose(Rows, Columns),
    maplist(column_prefix_compatible(N), Columns, ColClues).

% Проверка возможности завершения столбца
column_prefix_compatible(N, Prefix, Clue) :-
    length(Full, N),
    line_value(Full, Clue),
    append(Prefix, _, Full), !.

% Проверка соответствия строки подсказке (DCG)
line_value(Line, Clue) :-
    phrase(block_pattern(Clue), Line).

block_pattern([]) -->
    zeros.

block_pattern([N|Ns]) -->
    zeros,
    ones(N),
    ( {Ns == []} -> zeros
    ; [0], block_pattern(Ns)
    ).

zeros --> [] | [0], zeros.

ones(0) --> [].
ones(N) -->
    { N > 0, N1 is N - 1 },
    [1],
    ones(N1).

% Транспонирование матрицы
transpose([], []).
transpose([[]|_], []) :- !.
transpose(Matrix, [Col|Cols]) :-
    maplist(head_tail, Matrix, Col, RestMatrix),
    transpose(RestMatrix, Cols).

head_tail([H|T], H, T).

% Вывод сетки
print_grid([]).
print_grid([Row|Rows]) :-
    maplist(print_cell, Row),
    nl,
    print_grid(Rows).

print_cell(0) :- write('.').
print_cell(1) :- write('#').

% Главный предикат
main :-
    File = 'input.txt',
    (   exists_file(File)
    ->  read_input(File, N, M, RowClues, ColClues),
        format('Nonogram size: ~d x ~d~n', [N, M]),
        format('Row clues: ~w~n', [RowClues]),
        format('Col clues: ~w~n~n', [ColClues]),

        findall(Grid,
                solve_nonogram(N, M, RowClues, ColClues, Grid),
                Solutions),

        length(Solutions, Count),
        format('Solutions found: ~d~n', [Count]),

        (   Count > 0
        ->  format('~nFirst solution:~n', []),
            nth0(0, Solutions, FirstSolution),
            print_grid(FirstSolution)
        ;   format('~nNo solutions found (contradictory nonogram).~n', [])
        )
    ;   format('Error: file ~w not found.~n', [File])
    ).
