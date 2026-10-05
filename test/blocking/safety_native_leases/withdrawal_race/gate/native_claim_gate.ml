(* ^safe-sw86 ^safe-bt9f: this test-only import shadow leaves production source verbatim. *)
type t = {
  gate : Semaphore.Counting.t;
  submitted : unit Eio.Promise.t;
  submit : unit Eio.Promise.u;
  returned : unit Eio.Promise.t;
  return : unit Eio.Promise.u;
}

let next = ref None

let arm () =
  assert (match !next with None -> true | Some _ -> false);
  let submitted, submit = Eio.Promise.create () in
  let returned, return = Eio.Promise.create () in
  let t = { gate = Semaphore.Counting.make 0; submitted; submit; returned; return } in
  next := Some t;
  t

let await_submitted t = Eio.Promise.await t.submitted
let unblock t = Semaphore.Counting.release t.gate
let await_returned t = Eio.Promise.await t.returned

module Eio_unix = struct
  let run_in_systhread ?label fn =
    match !next with
    | None -> Eio_unix.run_in_systhread ?label fn
    | Some t ->
        next := None;
        Fun.protect
          ~finally:(fun () -> Eio.Promise.resolve t.return ())
          (fun () ->
            Eio_unix.run_in_systhread ?label (fun () ->
                Eio.Promise.resolve t.submit ();
                Semaphore.Counting.acquire t.gate;
                fn ()))
end
