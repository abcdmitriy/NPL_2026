
let read_input filename =
  let ic = open_in filename in
  try
    let first_line = input_line ic in
    let n, m = Scanf.sscanf first_line "%d %d" (fun n m -> n, m) in

    if n < 0 || m < 0 then
      failwith "Invalid graph dimensions";

    let rec read_edges acc =
      try
        let line = input_line ic in
        if String.trim line = "" then
          read_edges acc
        else begin
          let u, v = Scanf.sscanf line "%d %d" (fun u v -> u, v) in

          if u < 1 || u > n then
            failwith "Invalid left vertex";
          if v < 1 || v > m then
            failwith "Invalid right vertex";

          read_edges ((u, v) :: acc)
        end
      with End_of_file ->
        List.rev acc
    in

    let edges = read_edges [] in
    close_in ic;
    n, m, edges
  with exn ->
    close_in_noerr ic;
    raise exn

let build_graph n edges =
  let adj = Array.make (n + 1) [] in
  List.iter (fun (u, v) -> adj.(u) <- v :: adj.(u)) edges;
  adj

let kuhn n m adj =
  let match_right = Array.make (m + 1) 0 in
  let used = Array.make (n + 1) false in

  let rec dfs u =
    if used.(u) then false
    else begin
      used.(u) <- true;

      let rec try_neighbors = function
        | [] -> false
        | v :: rest ->
            if match_right.(v) = 0 || dfs match_right.(v) then begin
              match_right.(v) <- u;
              true
            end
            else
              try_neighbors rest
      in

      try_neighbors adj.(u)
    end
  in

  let matching_size = ref 0 in

  for u = 1 to n do
    Array.fill used 1 n false;
    if dfs u then incr matching_size
  done;

  !matching_size, match_right

let () =
  try
    let n, m, edges = read_input "input.txt" in
    let adj = build_graph n edges in
    let size, match_right = kuhn n m adj in

    Printf.printf "Maximum matching size: %d\n\n" size;

    Printf.printf "Pairs (Left -> Right):\n";
    if size > 0 then begin
      for v = 1 to m do
        if match_right.(v) <> 0 then
          Printf.printf "%d -> %d\n" match_right.(v) v
      done
    end
    else
      Printf.printf "None\n";

    let matched_left = Array.make (n + 1) false in

    for v = 1 to m do
      if match_right.(v) <> 0 then
        matched_left.(match_right.(v)) <- true
    done;

    Printf.printf "\nUnmatched left vertices:\n";

    let has_unmatched_left = ref false in

    for u = 1 to n do
      if not matched_left.(u) then begin
        Printf.printf "%d " u;
        has_unmatched_left := true
      end
    done;

    if not !has_unmatched_left then
      Printf.printf "None";

    Printf.printf "\n";

    Printf.printf "\nUnmatched right vertices:\n";

    let has_unmatched_right = ref false in

    for v = 1 to m do
      if match_right.(v) = 0 then begin
        Printf.printf "%d " v;
        has_unmatched_right := true
      end
    done;

    if not !has_unmatched_right then
      Printf.printf "None";

    Printf.printf "\n";

    (* Проверка корректности паросочетания *)
    let used_left = Array.make (n + 1) false in
    let used_right = Array.make (m + 1) false in
    let is_valid = ref true in
    let verified_size = ref 0 in

    for v = 1 to m do
      let u = match_right.(v) in

      if u <> 0 then begin
        incr verified_size;

        if u < 1 || u > n then
          is_valid := false
        else begin
          if used_left.(u) then
            is_valid := false;

          used_left.(u) <- true;

          if not (List.mem v adj.(u)) then
            is_valid := false
        end;

        if used_right.(v) then
          is_valid := false;

        used_right.(v) <- true
      end
    done;

    if !verified_size <> size then
      is_valid := false;

    if !is_valid then
      Printf.printf "\nVerification: PASSED (all pairs are valid and no vertex is used twice)\n"
    else
      Printf.printf "\nVerification: FAILED\n"

  with
  | Sys_error msg ->
      Printf.eprintf "File error: %s\n" msg
  | Failure msg ->
      Printf.eprintf "Input error: %s\n" msg
  | _ ->
      Printf.eprintf "Error: invalid input format\n"
