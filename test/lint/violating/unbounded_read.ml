(* ^safe-sx2y ^safe-5ajg ^safe-qczi *)
let read flow = Eio.Flow.read_all flow
let capture mgr = Eio.Process.parse_out mgr Eio.Buf_read.take_all [ "probe" ]
let unbounded flow = Eio.Buf_read.of_flow ~max_size:max_int flow
module Flow = Eio.Flow
let all = Flow.read_all
let alias flow = all flow
