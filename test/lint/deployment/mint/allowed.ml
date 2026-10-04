let mint () = Ox_test.powerbox ()

module Test = Ox_test

let alias () = Test.powerbox ()

let opened () =
  let open Ox_test in
  powerbox ()
