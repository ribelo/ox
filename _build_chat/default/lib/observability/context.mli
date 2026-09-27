(** Fiber-local fields every record logged in their dynamic extent inherits.

    Fields are attached with {!with_fields} and stored in an Eio fiber-local key, so a
    fiber forked inside the extent of [with_fields] inherits them — Eio copies bindings
    into forked fibers — and a fiber outside it does not. This is what lets a service log
    the identity of the work (service handle, tab, owner, command) without threading it
    through every call.

    Values are plain strings. A secret becomes a context value only through
    {!Redact.to_string}, which renders ["<redacted>"], so a redacted value can be
    inherited like any other.

    Cancellation and finalizers: [with_fields] runs [f] in the current fiber and does
    nothing else. It installs the binding for the duration of the call and restores the
    previous one when [f] returns, raises or is cancelled; it forks no fiber, performs no
    I/O, blocks on nothing and registers no finalizer.

    Outside an Eio fiber there is no binding storage: {!current} is {!empty}, and
    {!with_fields} raises Eio's unhandled-effect exception. *)

type t
(** A set of fields attached to the current fiber. Order is the order the fields were
    attached in; rendering sorts by name. *)

val empty : t
(** The set with no fields. *)

val with_fields : (string * string) list -> (unit -> 'a) -> 'a
(** [with_fields fields f] runs [f ()] with [fields] attached to the current fiber, and
    restores the previous set afterwards whatever [f] does. A name already attached is
    replaced where it was; a new name is appended in the order given. Fibers forked by [f]
    inherit the merged set. *)

val current : unit -> t
(** [current ()] is the set attached to the current fiber, [empty] when nothing is
    attached. *)

val fields : t -> (string * string) list
(** [fields t] is the attached fields in attachment order. *)
