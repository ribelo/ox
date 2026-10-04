(* ^nlintc-7be1 ^nlintc-kdcl *)
exception Error of string

module Nested : sig
  exception Failure
end
