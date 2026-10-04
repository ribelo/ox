(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

exception Error of string

module Nested : sig
  exception Failure
end
