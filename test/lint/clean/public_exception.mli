(* ^nlintc-7be1 ^nlintc-kdcl *)
val call : unit -> (unit, [ `Failure of string ]) result

module type BACKEND = sig
  type error

  exception Error of error

  module Nested : sig
    exception Defect
  end
end

module Make (Backend : BACKEND) : sig
  val run : unit -> (unit, Backend.error) result
end
