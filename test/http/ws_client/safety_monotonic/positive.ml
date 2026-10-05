(* ^safe-p9cw ^safe-8peq ^safe-5a9k: compile and execute the public native seam. *)
let check () =
  Eio_mock.Backend.run_full (fun env ->
      Eio.Switch.run (fun sw ->
          let net = Eio_mock.Net.make "native-consumer" in
          let clock : _ Eio.Time.Mono.t = env#mono_clock in
          match Ox_http.Ws_client.connect ~sw ~net ~clock "not-a-url" with
          | Error (`Url _) -> ()
          | _ -> failwith "expected URL refusal, not success or an exception"))

let () = check ()
