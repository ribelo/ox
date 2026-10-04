(* ^nwake-fz0j: Pie's plain-Eio SIGCHLD/ppoll reproducer under the Door.
   /bin/sh is used because NixOS has no /bin/true. "exit 0" is equivalent.
   No Ox_process wrapper or operation-level deadline masks the reaping race. *)
let pp_err _ (_ : [ `Never ]) = ()

let run ~(caps : < Ox_caps.Cap.exit ; .. >) () =
  Ox_caps.Cap_stdlib.exit ~caps
    (Ox_app.run_simple ~name:"posix-wakeup-stress" ~pp_err (fun env _sw ->
         let mgr = Eio.Stdenv.process_mgr env.Ox_app.Env.base in
         for _ = 1 to 1000 do
           Eio.Process.run mgr [ "/bin/sh"; "-c"; "exit 0" ]
         done;
         Ok ()))

let () = run ~caps:(Ox_test.powerbox ()) ()
