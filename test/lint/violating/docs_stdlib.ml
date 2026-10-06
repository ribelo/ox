(* ^nlintd-b362 ^nlintd-2tmh *)

let forged_format _ =
  Printf.sprintf
    (CamlinternalFormatBasics.Format
       (CamlinternalFormatBasics.Alpha CamlinternalFormatBasics.End_of_format, "%d"))
    (fun () () -> Eio.Fiber.yield (); "") ()

let fail _ = failwith "callback"
let result_map _ = ignore (Result.map fail (Ok 1))
let result_map_error _ = ignore (Result.map_error fail (Error 1))
let result_bind _ = ignore (Result.bind (Ok 1) fail)
let result_syntax _ = ignore (Result.Syntax.(let*) (Ok 1) fail)
let partial_map _ = let map = Result.map fail in ignore (map (Ok 1))
let option_map _ = ignore (Option.map fail (Some 1))
let option_bind _ = ignore (Option.bind (Some 1) fail)
let option_iter _ = Option.iter fail (Some 1)
let option_fold _ = ignore (Option.fold (Some 1) ~none:0 ~some:fail)
let option_equal _ = ignore (Option.equal (fun _ _ -> fail ()) (Some 1) (Some 1))
let option_compare _ = ignore (Option.compare (fun _ _ -> fail ()) (Some 1) (Some 1))
module Stdlib = struct
  let fst _ = failwith "shadow"
end
let shadowed _ = ignore (Stdlib.fst (1, 2))
let callback_yield _ = ignore (Result.map (fun _ -> Eio.Fiber.yield ()) (Ok 1))
let functional_equal _ (a : unit -> unit) (b : unit -> unit) = a = b
let functional_list_equal _ (a : (unit -> unit) list) b = a = b
let option_get _ option = Option.get option
let returned_callback _ pair = (fst pair) ()
