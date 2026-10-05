let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.time ; Ox_caps.Cap.fs_read >) in
  Sql_monotonic.verify ~caps ();
  print_endline
    "sql-monotonic-runtime: 15 native wall-jump/duration/cleanup controls passed"
