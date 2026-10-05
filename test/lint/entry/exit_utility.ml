(* ^nlintc-du4v ^nlintc-kdcl: an executable's utility module is not its entry. *)
let () =
  exit
    (try
       ignore ();
       0
     with _ -> 1)
