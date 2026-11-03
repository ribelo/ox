(* ^ncrit-ihf2 ^ncrit-9sfw: branded guarded data over one Eio mutex.

   The callback is called directly in the caller's frame, never handed to
   Eio, so a [local once] callback needs no locality conversion and its
   captures stay rooted by this frame while it runs (once-forks,
   Implementation Decisions). The lock is released on return and on every
   exception, including cancellation inside a waiting section: Eio's
   [use_ro] behaviour, not [use_rw]'s poisoning. *)

type 'k t = { mu : Eio.Mutex.t }
type packed = P : 'k t -> packed

module Access = struct
  type 'k t = Token
end

let create () = P { mu = Eio.Mutex.create () }

let enter t (f @ local once) =
  Eio.Mutex.lock t.mu;
  match f Access.Token with
  | value ->
      Eio.Mutex.unlock t.mu;
      value
  | exception exn ->
      Eio.Mutex.unlock t.mu;
      raise exn

let with_access t (f @ local once unyielding) = enter t f [@nontail]

let with_access_waiting t (f @ local once) = enter t f [@nontail]
