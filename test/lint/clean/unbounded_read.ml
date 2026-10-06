(* ^safe-sx2y ^safe-5ajg ^safe-qczi *)
module B = Eio.Buf_read

let bounded flow = B.parse_exn ~max_size:1024 B.take_all flow

let bounded_reader flow =
  let reader = B.of_flow ~max_size:256 flow in
  B.take_all reader

let parser = B.take_all
let alias flow = B.parse_exn ~max_size:128 parser flow

module Eio = struct
  module Flow = struct
    let read_all value = value
  end
end

let unrelated value = Eio.Flow.read_all value
