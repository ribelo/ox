(* nmodes-78o3: exercise a complete request/reply round-trip, not a mocked call. *)
type message = { id : int option; payload : int }

let iterations = 10_000

let report ~caps:(_caps : < Ox_caps.Cap.stdout ; .. >) ~before ~after =
  let per_call delta = delta /. float_of_int iterations in
  Ox_caps.Cap_stdlib.printf ~caps:_caps "correlator call+reply: %d iterations\n"
    iterations;
  Ox_caps.Cap_stdlib.printf ~caps:_caps "minor_words/call: %.2f\n"
    (per_call (after.Gc.minor_words -. before.Gc.minor_words));
  Ox_caps.Cap_stdlib.printf ~caps:_caps "major_words/call: %.2f\n"
    (per_call (after.Gc.major_words -. before.Gc.major_words));
  Ox_caps.Cap_stdlib.printf ~caps:_caps "total allocated words/call: %.2f\n"
    (per_call
       (after.Gc.minor_words +. after.Gc.major_words -. before.Gc.minor_words
      -. before.Gc.major_words))

(* ^ncapslint-t4c6: a benchmark is code the gate reads like any other, so its
   output goes through the capability its signature declares. *)
let () =
  let caps = Ox_caps_door.powerbox () in
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
          (* ^nlint-hxar: the warm-up call's outcome is irrelevant; the loop below
             asserts every reply. *)
          let _warmup : (message, _) result = Ox_rpc.Correlator.call correlator request in
          Gc.full_major ();
          let before = Gc.quick_stat () in
          for _ = 1 to iterations do
            match Ox_rpc.Correlator.call correlator request with
            | Ok reply when reply.payload = 42 -> ()
            | _ -> failwith "correlator reply mismatch"
          done;
          let after = Gc.quick_stat () in
          report ~caps:(caps :> < Ox_caps.Cap.stdout >) ~before ~after;
          Ox_rpc.Correlator.close correlator))
