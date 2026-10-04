(* Covers docs/issues/README.md row 0, "Build skeleton". Row 0 defines no
   story ID — the delivery map is its spec — so this placeholder test cites the
   row. The test entry obtains its capabilities through ox_test. *)

let main ~(caps : < Ox_caps.Cap.stderr ; Ox_caps.Cap.stdout ; Ox_caps.Cap.exit ; .. >) ()
    =
  (* The compiler fact every Ox package depends on: the switch the flake
     selects is OxCaml 5.4.0+ox. conf-ox-oxcaml states the same check at the
     opam level, so a tree built with another compiler is caught there first. *)
  let expected = "5.4.0+ox" in
  if Sys.ocaml_version <> expected then begin
    Ox_caps.Cap_stdlib.eprintf ~caps "compiler %s is not %s\n%!" Sys.ocaml_version
      expected;
    Ox_caps.Cap_stdlib.exit ~caps 1
  end;
  Ox_caps.Cap_stdlib.printf ~caps "build skeleton: compiled with %s, dune test runs\n%!"
    Sys.ocaml_version

let () = main ~caps:(Ox_test.powerbox ()) ()
