type t = (string * string) list

let empty = []

let key : t Eio.Fiber.key = Eio.Fiber.create_key ()

(* [Fiber.get] performs Eio's [Get_context] effect, which has no handler outside
   an Eio fiber. A logger is a side channel: it reports "no fields attached"
   there instead of aborting the process it was asked to describe. *)
let current () =
  match Eio.Fiber.get key with
  | Some fields -> fields
  | None -> empty
  | exception Effect.Unhandled _ -> empty

(* A name already attached keeps its position and takes the new value; a new
   name is appended in the order given. *)
let merge attached fields =
  List.fold_left
    (fun merged (name, value) ->
      if List.mem_assoc name merged then
        List.map
          (fun (attached_name, attached_value) ->
            if String.equal attached_name name then (attached_name, value)
            else (attached_name, attached_value))
          merged
      else merged @ [ (name, value) ])
    attached fields

let with_fields fields f =
  Eio.Fiber.with_binding key (merge (current ()) fields) f

let fields t = t
