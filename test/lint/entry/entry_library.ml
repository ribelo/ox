(* ^nlintc-du4v ^nlintc-kdcl: terminating library initializers receive no entry privilege. *)
let () =
  exit
    (try
       ignore ();
       0
     with _ -> 1)
