(* Covers docs/issues/README.md row 0, "Build skeleton". Row 0 defines no
   story ID — the delivery map is its spec — so this placeholder test cites the
   row. It uses the standard library only: ox_test arrives with row 2. *)

let () =
  (* The compiler fact every Ox package depends on: the switch the flake
     selects is OxCaml 5.4.0+ox. conf-ox-oxcaml states the same check at the
     opam level, so a tree built with another compiler is caught there first. *)
  let expected = "5.4.0+ox" in
  if Sys.ocaml_version <> expected then begin
    Printf.eprintf "compiler %s is not %s\n%!" Sys.ocaml_version expected;
    exit 1
  end;
  Printf.printf "build skeleton: compiled with %s, dune test runs\n%!" Sys.ocaml_version
