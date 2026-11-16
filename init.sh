#!/bin/bash

git checkout main

tasks=(
  "1_task_1_ada|1_threads/task_1_ada"
  "1_task_2_kotlin|1_threads/task_2_kotlin"
  "1_task_3_rust|1_threads/task_3_rust"
  "1_task_4_elixir|1_threads/task_4_elixir"
  "2_task_1_haskell|2_algorithms/task_1_haskell"
  "2_task_2_prolog|2_algorithms/task_2_prolog"
  "2_task_3_ocaml|2_algorithms/task_3_ocaml"
  "2_task_4_scheme|2_algorithms/task_4_scheme"
  "3_task_1_perl|3_io/task_1_perl"
  "3_task_2_nim|3_io/task_2_nim"
  "3_task_3_objc|3_io/task_3_objc"
  "3_task_4_zig|3_io/task_4_zig"
  "4_task_1_erlang|4_client_server/task_1_erlang"
  "4_task_2_julia|4_client_server/task_2_julia"
  "4_task_3_scala|4_client_server/task_3_scala"
  "4_task_4_d|4_client_server/task_4_d"
  "5_task_1_clojure|5_convert/task_1_clojure"
  "5_task_2_fsharp|5_convert/task_2_fsharp"
  "5_task_3_swift|5_convert/task_3_swift"
  "5_task_4_groovy|5_convert/task_4_groovy"
)

for task in "${tasks[@]}"; do
  IFS='|' read -r branch folder <<< "$task"

  echo "=> Создаю ветку $branch и папку $folder"

  git checkout -q -B "$branch" main

  mkdir -p "$folder"
  touch "$folder/.gitkeep"

  echo "# $branch" > "$folder/README.md"
  echo "Исходный код будет здесь." >> "$folder/README.md"

  git add .
  git commit -m "Init structure for $branch" -q || true
  git push -q -f origin "$branch"
done

git checkout main

echo "Готово: созданы 20 веток и папок."