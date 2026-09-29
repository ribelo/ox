(* nmodes-78o3: exercise a complete request/reply round-trip, not a mocked call. *)
type message = { id : int option; payload : int }

let iterations = 10_000

let () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let replies = Eio.Stream.create 64 in
          let correlator =
            Ox_rpc.Correlator.create ~sw ~clock:env#clock
              ~read:(fun () -> Some (Eio.Stream.take replies))
              ~write:(fun reply -> Eio.Stream.add replies reply)
              ~id:(fun message -> message.id)
              ~set_id:(fun message id -> { message with id = Some id })
              ()
          in
          let request = { id = None; payload = 42 } in
          ignore (Ox_rpc.Correlator.call correlator request);
          Gc.full_major ();
          let before = Gc.quick_stat () in
          for _ = 1 to iterations do
            match Ox_rpc.Correlator.call correlator request with
            | Ok reply when reply.payload = 42 -> ()
            | _ -> failwith "correlator reply mismatch"
          done;
          let after = Gc.quick_stat () in
          Printf.printf "correlator call+reply: %d iterations\n" iterations;
          Printf.printf "minor_words/call: %.2f\n"
            ((after.minor_words -. before.minor_words) /. float_of_int iterations);
          Printf.printf "major_words/call: %.2f\n"
            ((after.major_words -. before.major_words) /. float_of_int iterations);
          Printf.printf "total allocated words/call: %.2f\n"
            ((after.minor_words +. after.major_words -. before.minor_words
            -. before.major_words)
            /. float_of_int iterations);
          Ox_rpc.Correlator.close correlator))
