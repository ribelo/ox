(* ^nlintc-kdcl: construction and synchronous lock scopes are correct. *)
[@@@warning "-32-34-37"]

let construct () = (Mutex.create (), Condition.create (), Semaphore.Counting.make 0)

let sync mutex table key =
  Mutex.lock mutex;
  Fun.protect
    ~finally:(fun () -> Mutex.unlock mutex)
    (fun () -> Hashtbl.find_opt table key)

let release_before_suspend mutex =
  Mutex.lock mutex;
  Mutex.unlock mutex;
  Eio.Fiber.yield ()

let deferred mutex =
  Mutex.lock mutex;
  let later () = Eio.Fiber.yield () in
  Mutex.unlock mutex;
  later

let via_alias mutex =
  let alias = mutex in
  Mutex.lock mutex;
  Mutex.unlock alias;
  Eio.Fiber.yield ()

let fiber () = Eio.Mutex.create ()

module Mutex = struct
  let lock () = ()
  let unlock () = ()
end

let local () =
  Mutex.lock ();
  Eio.Fiber.yield ();
  Mutex.unlock ()
