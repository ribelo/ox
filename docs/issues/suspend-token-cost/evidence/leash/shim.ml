(* Local experiment only: NOT Ox or Leash production implementations.
   Cdp.call is unlinked; protect/timeout exercise callback modes without masking
   cancellation or enforcing deadlines. sleep is backed by real Eio. *)
module Duration = struct
  type t = float
  let seconds n = float_of_int n
  let ms n = float_of_int n /. 1000.
end
module Cdp = struct
  type t = unit
  let call ~(io : Io.t @ yielding) (_ : t) ?session:_ ?deadline:_ _method
      (_params : Yojson.Safe.t) =
    io.suspend ();
    Error `Unlinked_cdp
  let error_of_reply (_ : Yojson.Safe.t) = None
  let result (reply : Yojson.Safe.t) = Some reply
end
let bind r (f : (_ -> _) @ local once yielding) =
  match r with Ok x -> f x | Error e -> Error e
let protect ~(finally : (unit -> unit) @ local once yielding)
    (f : (unit -> _) @ local once yielding) =
  (* A type-only shim: each once callback is invoked once on this path. *)
  let result = f () in
  finally ();
  result
let cancel_protect (f : (unit -> _) @ local once yielding) = f ()
let critical_section (f : (unit -> _) @ local once unyielding) = f ()
module Timeout = struct
  let timeout ~(io : Io.t @ yielding) ~clock:_ _duration
      (f : (unit -> _) @ local once yielding) =
    io.suspend ();
    f ()
end
let sleep ~(io : Io.t @ yielding) clock seconds =
  io.suspend ();
  Eio.Time.sleep clock seconds
