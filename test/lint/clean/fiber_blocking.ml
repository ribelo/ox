(* ^safe-9ved ^safe-r5ye: explicit clocks and pools replace scheduler blocking. *)
let timer () = Eio_main.run (fun env -> Eio.Time.sleep (Eio.Stdenv.clock env) 0.001)

let native ~pool () =
  Eio_main.run (fun _ ->
      (* Best effort: this lint fixture exercises placement, not pool shutdown errors. *)
      let _best_effort = Ox_blocking.run ~pool (fun () -> Unix.sleepf 0.001) in
      ())

let harmless () = Eio_main.run (fun _ -> ignore (Unix.getpid ()))
let non_eio () = Thread.delay 0.001

let counting_native ~pool semaphore () =
  Eio_main.run (fun _ ->
      (* Best effort: this lint fixture exercises placement, not pool shutdown errors. *)
      let _best_effort =
        Ox_blocking.run ~pool (fun () -> Semaphore.Counting.acquire semaphore)
      in
      ())

let counting_outside semaphore () = Semaphore.Counting.acquire semaphore
let counting_owner semaphore () = Eio_main.run (fun _ -> Eio.Semaphore.acquire semaphore)
