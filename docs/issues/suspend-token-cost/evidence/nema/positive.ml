let run ~(io : Io.t @ yielding) gate =
  let r = Ok () in
  Shim.bind r (fun () ->
      Gate.with_read ~io gate (fun () -> Shim.yield ~io) [@nontail];
      Gate.with_write ~io ~on_waiting:(fun () -> Ok ()) gate
        (fun () -> Shim.yield ~io; Ok 42) [@nontail]) [@nontail]
let () =
  Eio_main.run (fun _ ->
      let io : Io.t = { suspend = (fun () -> ()) } in
      match run ~io (Gate.create ()) with
      | Ok 42 -> print_endline "positive: reader/writer suspension and explicit bind passed"
      | _ -> assert false)
