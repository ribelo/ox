(** Structured failures. Construction and rendering do not suspend, observe
    cancellation, or register finalizers. *)
type 'e t =
  | Fail of 'e
  | Die of exn * Printexc.raw_backtrace
  | Interrupt of Interrupt_id.t option
  | Finalizer of 'e t
  | Suppressed of { primary : 'e t; finalizer : 'e t }
  | Concurrent of 'e t list
val pp : (Format.formatter -> 'e -> unit) -> Format.formatter -> 'e t -> unit
val pp_compact : (Format.formatter -> 'e -> unit) -> Format.formatter -> 'e t -> unit
(** One-line rendering; typed payloads use the supplied printer. *)
val is_interrupt_only : 'e t -> bool
