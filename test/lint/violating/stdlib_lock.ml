(* ^nlintc-kdcl: stdlib_lock violating evidence. *)
[@@@warning "-32-34-37"]

let mutex () = Mutex.create ()
let condition () = Condition.create ()
let semaphore () = Semaphore.Counting.make 0

module M = Mutex

let alias () = M.create ()

let opened () =
  let open Condition in
  create ()
