(* ^safe-9ved ^safe-r5ye: authentic domain wait is illegal only in the Eio owner. *)
let owner semaphore () = Eio_main.run (fun _ -> Semaphore.Counting.acquire semaphore)
let worker ~pool semaphore () = Eio_main.run (fun _ -> ignore (Ox_blocking.run ~pool (fun () -> Semaphore.Counting.acquire semaphore)))
module Counting = Semaphore.Counting
let acquire = Counting.acquire
let alias_owner semaphore () = Eio_main.run (fun _ -> acquire semaphore)
let alias_worker ~pool semaphore () = Eio_main.run (fun _ -> ignore (Ox_blocking.run ~pool (fun () -> acquire semaphore)))
let outside semaphore () = Counting.acquire semaphore
let cooperative semaphore () = Eio_main.run (fun _ -> Eio.Semaphore.acquire semaphore)
