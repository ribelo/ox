let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.time ; Ox_caps.Cap.fs_read >) in
  Alcotest.run "SQL monotonic ^safe-p9cw ^safe-8peq ^safe-5a9k"
    [ ("native elapsed contracts", Sql_monotonic.tests ~caps) ]
