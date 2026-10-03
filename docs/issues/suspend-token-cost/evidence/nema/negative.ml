let rejected ~(io : Io.t @ yielding) gate =
  Gate.with_write ~io
    ~on_waiting:(fun () -> Shim.yield ~io; Ok ())
    gate (fun () -> Ok ()) [@nontail]
