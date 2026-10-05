(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)
[@@@warning "-32-34-37"]

let yield mutex =
  Mutex.lock mutex;
  Eio.Fiber.yield ();
  Mutex.unlock mutex

let await mutex promise =
  Mutex.lock mutex;
  ignore (Eio.Promise.await promise);
  Mutex.unlock mutex

module M = Mutex

let protected mutex =
  M.lock mutex;
  Fun.protect ~finally:(fun () -> M.unlock mutex) (fun () -> Eio.Fiber.yield ())

let via_helper mutex =
  let suspend () = Eio.Fiber.yield () in
  Mutex.lock mutex;
  suspend ();
  Mutex.unlock mutex

let via_alias mutex =
  let alias = mutex in
  Mutex.lock alias;
  Eio.Fiber.yield ();
  Mutex.unlock mutex

let branch mutex choose =
  if choose then Mutex.lock mutex;
  Eio.Fiber.yield ();
  if choose then Mutex.unlock mutex

(* ^nlintc-j03j ^nlintc-kdcl: identical closure, distinct lock substitutions. *)
let different_instantiations mutex other =
  let release_then_yield target =
    Mutex.unlock target;
    Eio.Fiber.yield ()
  in
  Mutex.lock mutex;
  release_then_yield mutex;
  Mutex.lock mutex;
  release_then_yield other;
  Mutex.unlock mutex
