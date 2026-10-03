type t = { cc : Eio.Cancel.t; reason : exn }
let with_ f = Eio.Cancel.sub (fun cc -> f {cc; reason = Failure "explicit source"})
let cancel t = Eio.Cancel.cancel t.cc t.reason
let receive ~cancel channel =
  try match Channel_base.receive channel with
  | Ok x -> Ok x
  | Error `Done -> Error `Done
  | Error (`Error e) -> Error (`Error e)
  with Eio.Cancel.Cancelled reason when reason == cancel.reason -> Error `Canceled
