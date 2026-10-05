let () =
  Alcotest.run "JSON bounded values"
    [
      ( "nparse-gb03 safe-6ukl",
        [ Alcotest.test_case "native byte semantics" `Quick Runtime.run ] );
    ]
