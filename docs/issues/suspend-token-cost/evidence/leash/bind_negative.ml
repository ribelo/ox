let ( let* ) = Result.bind
let rejected ~(io : Io.t @ yielding) clock =
  let* () = Ok () in
  Shim.sleep ~io clock 0.01;
  Ok ()
