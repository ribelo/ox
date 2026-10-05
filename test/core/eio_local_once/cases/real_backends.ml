(* The same 14 controls on each genuine scheduler. ^nonce-lrzq ^nonce-mjpe *)
let run label backend =
  List.iter
    (fun (name, test) ->
      backend test;
      Printf.printf "PASS %s: %s\n%!" label name)
    Runtime.tests

let () =
  Printexc.record_backtrace true;
  assert (List.length Runtime.tests = 14);
  run "MOCK" Eio_mock.Backend.run;
  run "POSIX" (fun body -> Eio_posix.run (fun _ -> body ()));
  run "MAIN" (fun body ->
      Eio_main.run (fun env ->
          if Sys.os_type = "Unix" && Sys.file_exists "/proc/sys/kernel/ostype" then
            if env#backend_id <> "linux" then failwith "Main did not select Linux";
          Printf.printf "MAIN selected backend: %s\n%!" env#backend_id;
          body ()))
