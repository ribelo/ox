(* ^nlintd-7x5n ^nlintd-b362 ^nlintd-2tmh *)
let scalar_format _ year month day stamp =
  Printf.sprintf "%04d-%02d-%02d:%012Ld" year month day stamp

let function_list_empty _ (fs : (unit -> unit) list) = fs = []
let polymorphic_list_empty _ xs = xs = []

let totals _ (pair : int * int) (option : int option) (result : (int, string) result)
    (xs : int list) =
  ignore (fst pair);
  ignore (snd pair);
  ignore (Fun.id pair);
  ignore (List.length xs);
  ignore (Option.some 1);
  ignore (Option.value option ~default:0);
  ignore (Option.join (Some option));
  ignore (Option.is_none option);
  ignore (Option.is_some option);
  ignore (Result.is_ok (Option.to_result option ~none:"none"));
  ignore (Option.to_list option);
  ignore (Result.is_ok (Result.ok 1));
  ignore (Result.is_ok (Result.error "error"));
  ignore (Result.value result ~default:0);
  ignore (Result.is_ok (Result.join (Ok result)));
  ignore (Result.is_ok result);
  ignore (Result.is_error result);
  ignore (Result.to_option result);
  ignore (xs = []);
  ignore ([] <> xs);
  ignore (1 = 2)

module R = Result

let project = fst

let aliases _ result =
  ignore (Result.is_ok (R.map project (Result.map (fun n -> (n, n)) result)));
  let map = R.map (fun n -> n + 1) in
  ignore (Result.is_ok (map result))

let stored_function _ callback =
  ignore (Fun.id callback);
  ignore (Option.some callback);
  ignore (Option.value (Some callback) ~default:callback)

let callbacks _ (result : (int, string) result) (option : int option) =
  ignore (Result.is_ok (Result.map Fun.id result));
  ignore (Result.is_ok (Result.map_error Fun.id result));
  ignore (Result.is_ok (Result.bind result Result.ok));
  ignore (Result.is_ok (Result.Syntax.( let* ) result Result.ok));
  ignore (Option.map Fun.id option);
  ignore (Option.bind option Option.some);
  ignore (Option.fold option ~none:0 ~some:Fun.id);
  Option.iter ignore option;
  ignore (Option.equal (fun a b -> a = b) option option);
  ignore (Option.compare (fun a b -> a - b) option option)

let unused_partial _ =
  let callback = Result.map (fun _ -> failwith "not invoked") in
  ignore callback

let caught_callback _ result =
  try ignore (Result.is_ok (Result.map (fun _ -> failwith "caught") result))
  with Failure _ -> ()
