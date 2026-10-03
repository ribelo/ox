type io = { suspend : unit -> unit } [@@unboxed]
type t = io
let touch (io : t @ yielding) = io.suspend ()
