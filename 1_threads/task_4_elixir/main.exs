defmodule AnagramSearch do

  def main do
    IO.puts("=== Задача 1.4: Параллельный поиск групп анаграмм (Elixir) ===\n")

    words = read_words()
    IO.puts("Всего слов в словаре: #{length(words)}\n")

    # Последовательный поиск
    IO.puts("--- Последовательный поиск ---")
    {seq_time, seq_groups} = :timer.tc(fn -> find_sequential(words) end)
    print_results(seq_groups, seq_time)

    # Параллельный поиск
    IO.puts("\n--- Параллельный поиск (4 воркера + коллектор) ---")
    {par_time, par_groups} = :timer.tc(fn -> find_parallel(words, 4) end)
    print_results(par_groups, par_time)

    # Проверка результатов
    normalize = fn groups ->
      groups
      |> Enum.map(fn {key, group} -> {key, Enum.sort(group)} end)
      |> Enum.sort()
    end

    IO.puts(
      "\nРезультаты совпадают: #{normalize.(seq_groups) == normalize.(par_groups)}"
    )
  end

  defp read_words do
    case File.read("input.txt") do
      {:ok, content} ->
        IO.puts("Словарь прочитан из input.txt")
        String.split(content, ~r/\R/, trim: true)

      {:error, reason} ->
        IO.puts("Ошибка чтения input.txt: #{reason}")
        System.halt(1)
    end
  end

  defp sort_string(str) do
    str
    |> String.graphemes()
    |> Enum.sort()
    |> Enum.join()
  end

  defp find_sequential(words) do
    words
    |> Enum.group_by(&sort_string/1)
    |> Enum.filter(fn {_key, group} -> length(group) >= 2 end)
  end

  defp find_parallel([], _num_workers), do: []

  defp find_parallel(words, num_workers) when num_workers > 0 do
    chunk_size = ceil(length(words) / num_workers)
    chunks = Enum.chunk_every(words, chunk_size)

    collector_pid =
      spawn(__MODULE__, :collector_loop, [self(), length(chunks), %{}])

    Enum.each(chunks, fn chunk ->
      spawn_monitor(fn ->
        partial = Enum.group_by(chunk, &sort_string/1)
        send(collector_pid, {:partial, partial})
      end)
    end)

    receive do
      {:final_result, groups} ->
        groups
    end
  end

  # Коллектор
  def collector_loop(main_pid, 0, acc) do
    result =
      Enum.filter(acc, fn {_key, group} -> length(group) >= 2 end)

    send(main_pid, {:final_result, result})
  end

  def collector_loop(main_pid, remaining, acc) do
    receive do
      {:partial, partial_map} ->
        merged =
          Map.merge(acc, partial_map, fn _key, list1, list2 ->
            list1 ++ list2
          end)

        collector_loop(main_pid, remaining - 1, merged)

      {:DOWN, _ref, :process, _pid, reason} when reason != :normal ->
        collector_loop(main_pid, remaining - 1, acc)

      {:DOWN, _ref, :process, _pid, :normal} ->
        collector_loop(main_pid, remaining, acc)
    end
  end

  # Вывод результатов
  defp print_results(groups, time_us) do
    time_ms = time_us / 1000

    IO.puts("Найдено групп анаграмм (размер >= 2): #{length(groups)}")

    top5 =
      groups
      |> Enum.sort_by(fn {_key, group} -> length(group) end, :desc)
      |> Enum.take(5)

    IO.puts("\nТоп-5 самых больших групп:")

    Enum.each(top5, fn {key, group} ->
      sample = Enum.take(group, 3) |> Enum.join(", ")
      IO.puts("  Ключ '#{key}' (#{length(group)} слов): #{sample}...")
    end)

    IO.puts("\nВремя выполнения: #{:io_lib.format("~.2f", [time_ms])} мс")
  end
end

AnagramSearch.main()
