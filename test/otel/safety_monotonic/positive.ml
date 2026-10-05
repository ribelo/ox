(* ^safe-p9cw ^safe-8peq ^safe-5a9k: directly compile both strong clock types. *)
let check ~caps () =
  Eio_mock.Backend.run_full (fun env ->
      Eio.Switch.run (fun sw ->
          let net = Eio_mock.Net.make "native-consumer" in
          let clock : _ Eio.Time.clock = env#clock in
          let mono_clock : _ Eio.Time.Mono.t = env#mono_clock in
          let http_client = Ox_http.Client.create ~sw ~net ~clock () in
          match
            Ox_otel.create ~caps ~sw ~clock ~mono_clock ~http_client
              ~endpoint:"http://localhost" ~service_name:"native-control"
              ~ending_budget:Ox.Duration.zero ()
          with
          | Error (`Invalid_config _) -> ()
          | _ -> failwith "expected configuration refusal, not success or an exception"))

let () = check ~caps:(Ox_test.powerbox () :> < Ox_caps.Cap.random >) ()
