(* Trusted adaptation boundary for legacy Eio callback modes. The callbacks below
   are invoked synchronously; the representation cast is NOT a safe general API. *)
external legacy_callback :
  (unit -> 'a) @ local once yielding -> (unit -> 'a) = "%identity"
let cancel_protect (f : (unit -> 'a) @ local once yielding) =
  Eio.Cancel.protect (legacy_callback f)
let protect ~(finally : (unit -> unit) @ local once yielding)
    (f : (unit -> 'a) @ local once yielding) =
  match f () with
  | value -> finally (); value
  | exception error ->
      let backtrace = Printexc.get_raw_backtrace () in
      finally (); Printexc.raise_with_backtrace error backtrace
let mutex_lock ~(io : Io.t @ yielding) mutex =
  Io.touch io; Eio.Mutex.lock mutex
let mutex_use_ro ~(io : Io.t @ yielding) mutex
    (f : (unit -> 'a) @ local once unyielding) =
  Io.touch io; Eio.Mutex.use_ro mutex (legacy_callback f)
let condition_await ~(io : Io.t @ yielding) condition mutex =
  Io.touch io; Eio.Condition.await condition mutex
let yield ~(io : Io.t @ yielding) = Io.touch io; Eio.Fiber.yield ()
let bind r (f : ('a -> ('b, 'e) result) @ local once yielding) =
  match r with Ok value -> f value | Error error -> Error error
