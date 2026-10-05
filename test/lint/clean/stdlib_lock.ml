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

(* ^nlintc-j03j ^nlintc-kdcl: cached transfers must replay the released lock set. *)
let repeated_instantiation mutex =
  let release target = Stdlib.Mutex.unlock target in
  Stdlib.Mutex.lock mutex;
  release mutex;
  Stdlib.Mutex.lock mutex;
  release mutex;
  Eio.Fiber.yield ()

(* ^nlintc-j03j ^nlintc-kdcl: an empty-held-state diamond must not expand exponentially. *)
let diamond_0 () = Eio.Fiber.yield ()

let diamond_1 () =
  diamond_0 ();
  diamond_0 ()

let diamond_2 () =
  diamond_1 ();
  diamond_1 ()

let diamond_3 () =
  diamond_2 ();
  diamond_2 ()

let diamond_4 () =
  diamond_3 ();
  diamond_3 ()

let diamond_5 () =
  diamond_4 ();
  diamond_4 ()

let diamond_6 () =
  diamond_5 ();
  diamond_5 ()

let diamond_7 () =
  diamond_6 ();
  diamond_6 ()

let diamond_8 () =
  diamond_7 ();
  diamond_7 ()

let diamond_9 () =
  diamond_8 ();
  diamond_8 ()

let diamond_10 () =
  diamond_9 ();
  diamond_9 ()

let diamond_11 () =
  diamond_10 ();
  diamond_10 ()

let diamond_12 () =
  diamond_11 ();
  diamond_11 ()

let diamond_13 () =
  diamond_12 ();
  diamond_12 ()

let diamond_14 () =
  diamond_13 ();
  diamond_13 ()

let diamond_15 () =
  diamond_14 ();
  diamond_14 ()

let diamond_16 () =
  diamond_15 ();
  diamond_15 ()

let diamond_17 () =
  diamond_16 ();
  diamond_16 ()

let diamond_18 () =
  diamond_17 ();
  diamond_17 ()

let diamond_19 () =
  diamond_18 ();
  diamond_18 ()

let diamond_20 () =
  diamond_19 ();
  diamond_19 ()

let diamond_21 () =
  diamond_20 ();
  diamond_20 ()

let diamond_22 () =
  diamond_21 ();
  diamond_21 ()

let diamond_23 () =
  diamond_22 ();
  diamond_22 ()

let diamond_24 () =
  diamond_23 ();
  diamond_23 ()
