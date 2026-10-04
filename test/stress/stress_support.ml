(* ^nstress-xn75: runner setup is explicit, never a module-load RNG side effect. *)
let seed ~(caps : < Ox_caps.Cap.env ; Ox_caps.Cap.stdout ; .. >) ~default () =
  let parse source value =
    match int_of_string_opt value with
    | Some seed -> seed
    | None -> invalid_arg (source ^ ": expected an integer, got " ^ value)
  in
  let rec argument i =
    if i >= Array.length Sys.argv then default
    else if Sys.argv.(i) = "--seed" then
      if i + 1 < Array.length Sys.argv then parse "--seed" Sys.argv.(i + 1)
      else invalid_arg "--seed: missing integer"
    else argument (i + 1)
  in
  let selected =
    match Ox_caps.Cap_sys.getenv_opt ~caps "OX_STRESS_SEED" with
    | Some value -> parse "OX_STRESS_SEED" value
    | None -> argument 1
  in
  Ox_caps.Cap_stdlib.printf ~caps "OX_STRESS_SEED=%d\n%!" selected;
  selected

let random ~(caps : < Ox_caps.Cap.env ; Ox_caps.Cap.stdout ; .. >) ~default () =
  Random.State.make [| seed ~caps ~default () |]
