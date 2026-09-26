type t = int
exception Stop of t
let next = Atomic.make 0
let create () = Atomic.fetch_and_add next 1
let equal = Int.equal
let compare = Int.compare
let pp fmt id = Format.fprintf fmt "eta-stop-%d" id
let to_string id = Format.asprintf "%a" pp id
let stop id = Stop id
let of_exn = function Stop id -> Some id | _ -> None
