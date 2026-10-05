(* ^nparse-gb03: checked physical worker concurrency, not waiting-queue typing. *)
let () =
  Alcotest.run "blocking-concurrency"
    [
      ( "public bounds",
        [
          Alcotest.test_case "checked construction" `Quick Runtime.checked_construction;
          Alcotest.test_case "physical worker limits" `Quick Runtime.worker_limits;
          Alcotest.test_case "cancelled native worker retains its slot" `Quick
            Runtime.cancelled_worker;
          Alcotest.test_case "raw queue boundary stays unchanged" `Quick
            Runtime.queue_boundary;
        ] );
    ]
