(** Structured concurrent operations; the coordinator is attached to [sw]
    and its workers live on a child switch. Losers are cancelled with private
    identities and awaited before return.
    External cancellation and defects propagate to the enclosing [Scope.run]. *)
val race : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list -> ('a, [> `Concurrent of 'e Cause.t]) result
(** The first success wins. If all fail, the error payload is
    [Cause.Concurrent] in input order, including defects as [Cause.Die]. An
    empty list returns [Error (`Concurrent (Cause.Concurrent []))]. *)
val par : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) -> (unit -> ('b, 'e) result) -> ('a * 'b, 'e) result
val all : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list -> ('a list, 'e) result
(** First failure stops siblings, which are awaited; typed errors return
    unchanged and defects/cancellation propagate after cleanup. *)
val with_background : sw:Eio.Switch.t -> (unit -> (unit, 'e) result) -> (unit -> ('a, 'e) result) -> ('a, 'e) result
(** Fail-fast in both directions: the first terminal failure of background
    stops body and wins, while body completion stops background and wins.
    Background normal completion does not stop body. Eta's own stop does not
    overwrite the winner; both fibers and their finalizers are awaited. *)
