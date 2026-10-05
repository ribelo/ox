let () =
  Alcotest.run "bounded integer values"
    [
      ( "nparse-gb03 safe-6ukl",
        [ Alcotest.test_case "native boundaries" `Quick Runtime.run ] );
    ]
