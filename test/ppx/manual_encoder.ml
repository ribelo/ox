(* ^nderive-s2lt ^nderive-u3ux: an opaque constituent supplies no decoder. *)
type t = int

let make value = value
let yojson_of_t value : Yojson.Safe.t = `Int value
