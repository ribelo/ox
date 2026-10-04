((deps
  ((File (External /home/ribelo/.cache/opam/5.4.0+ox/bin/ocamlopt.opt))
   (File
    (In_build_dir
     _build/default/lib/ppx_yojson_minimal/.main.eobjs/byte/dune__exe__Main.cmi))
   (File (In_build_dir _build/default/lib/ppx_yojson_minimal/main.ml))
   (glob
    ((dir
      (External
       /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml-compiler-libs/common))
     (predicate *.cmi)
     (only_generated_files false)))
   (glob
    ((dir
      (External
       /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml-compiler-libs/common))
     (predicate *.cmx)
     (only_generated_files false)))
   (glob
    ((dir
      (External /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml/compiler-libs))
     (predicate *.cmi)
     (only_generated_files false)))
   (glob
    ((dir
      (External /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml/compiler-libs))
     (predicate *.cmx)
     (only_generated_files false)))
   (glob
    ((dir
      (In_build_dir
       _build/default/lib/ppx_yojson_minimal/.ppx_yojson_minimal.objs/byte))
     (predicate *.cmi)
     (only_generated_files false)))))
 (targets
  ((files
    (_build/default/lib/ppx_yojson_minimal/.main.eobjs/native/dune__exe__Main.cmx
     _build/default/lib/ppx_yojson_minimal/.main.eobjs/native/dune__exe__Main.o))
   (directories ())))
 (context default)
 (action
  (chdir
   _build/default
   (run
    /home/ribelo/.cache/opam/5.4.0+ox/bin/ocamlopt.opt
    -short-paths
    -keep-locs
    -warn-error
    +a
    -g
    -I
    lib/ppx_yojson_minimal/.main.eobjs/byte
    -I
    lib/ppx_yojson_minimal/.main.eobjs/native
    -I
    /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml-compiler-libs/common
    -I
    /home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml/compiler-libs
    -I
    lib/ppx_yojson_minimal/.ppx_yojson_minimal.objs/byte
    -I
    lib/ppx_yojson_minimal/.ppx_yojson_minimal.objs/native
    -cmi-file
    lib/ppx_yojson_minimal/.main.eobjs/byte/dune__exe__Main.cmi
    -no-alias-deps
    -opaque
    -o
    lib/ppx_yojson_minimal/.main.eobjs/native/dune__exe__Main.cmx
    -c
    -impl
    lib/ppx_yojson_minimal/main.ml))))
