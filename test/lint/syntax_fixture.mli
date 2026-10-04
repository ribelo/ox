module Root = Eio
(** ^nlint-yf56 ^nlint-rv8u: attached docs remain on interface values. *)

module Fiber = Root.Fiber
open Fiber

val value : unit
(** A future rule can read this attached documentation without losing its span. *)
