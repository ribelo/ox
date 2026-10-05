val clean : (unit -> unit) list -> unit
val effectful : int ref -> unit
val opaque : (unit -> (unit -> unit) list) -> unit
val functional : (unit -> unit) list -> (unit -> unit) list -> unit
val nonempty : unit -> unit
val custom :
  (int, Bigarray.int_elt, Bigarray.c_layout) Bigarray.Array1.t ->
  (int, Bigarray.int_elt, Bigarray.c_layout) Bigarray.Array1.t -> unit
type counterfeit = [] | ( :: ) of (unit -> unit) * counterfeit
val counterfeit : counterfeit -> unit
