module C = Ox_process.Child
module S = Ox_process.Supervised

let ok = function Ok x -> x | Error _ -> failwith "spawn failed"

let gone ~caps pid =
  match Ox_caps.Cap_unix.kill ~caps pid 0 with
  | () -> failwith "physical child survived protected stop/join"
  | exception Unix.Unix_error (Unix.ESRCH, _, _) -> ()

let main ~caps () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let clock = env#mono_clock in
          let child =
            ok
              (C.spawn ~caps ~sw ~clock ~mgr:env#process_mgr
                 ~argv:[ "/bin/sh"; "-c"; "trap '' TERM; printf ready; exec sleep 30" ]
                 ~stdout:C.Pipe ~grace:(Ox.Duration.ms 5) ~fds:[] ())
          in
          let source =
            match C.stdout child with Some source -> source | None -> assert false
          in
          let ready = Eio.Buf_read.take 5 (Eio.Buf_read.of_flow ~max_size:32 source) in
          assert (ready = "ready");
          let pid = C.pid child in
          let exit = C.stop child in
          assert (exit = C.Signaled Sys.sigkill);
          gone ~caps pid;
          assert (C.stop child = exit);
          assert (C.await child = exit);
          let current = ref None in
          let supervisor =
            S.start ~sw ~clock ~schedule:Ox.Schedule.forever ~spawn:(fun ~sw ->
                let child =
                  C.spawn ~caps ~sw ~clock ~mgr:env#process_mgr
                    ~argv:[ "/bin/sh"; "-c"; "exec sleep 30" ]
                    ~grace:(Ox.Duration.ms 5) ~fds:[] ()
                in
                (match child with Ok child -> current := Some child | Error _ -> ());
                child)
          in
          (match Eio.Stream.take (S.events supervisor) with
          | S.Started 1 -> ()
          | _ -> assert false);
          S.stop supervisor;
          (match Eio.Stream.take (S.events supervisor) with
          | S.Stopped -> ()
          | _ -> assert false);
          (match !current with
          | Some child -> gone ~caps (C.pid child)
          | None -> assert false);
          S.stop supervisor;
          print_endline
            "installed public Mono Child/Supervised APIs: real SIGKILL grace, ESRCH \
             retirement and repeatable stop/join OK"))

let () = main ~caps:(Ox_caps_door.powerbox ()) ()
