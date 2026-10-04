(* Throwaway annotation inventory; pinned OxCaml compiler-libs. *)
let () =
  Printf.printf "COMPILER\t%s\t%s\t%s\n" Sys.ocaml_version Config.cmt_magic_number Config.cmi_magic_number;
  for arg = 1 to Array.length Sys.argv - 1 do
    let name = Sys.argv.(arg) in
    try
      let c = Cmt_format.read_cmt name in
      let kind, count = match c.cmt_annots with
        | Implementation t -> "Implementation", List.length t.str_items
        | Interface t -> "Interface", List.length t.sig_items
        | Packed (_, xs) -> "Packed", List.length xs
        | Partial_implementation xs -> "Partial_implementation", Array.length xs
        | Partial_interface xs -> "Partial_interface", Array.length xs in
      Printf.printf "READ\t%s\t%s\t%d\t%s\t%s\t%s\t%b\t%s\n"
        name kind count (Option.value c.cmt_sourcefile ~default:"-") c.cmt_builddir
        (Option.fold ~none:"-" ~some:Digest.to_hex c.cmt_source_digest) c.cmt_use_summaries
        (String.concat " " (Array.to_list c.cmt_args))
    with ex -> Printf.printf "FAIL\t%s\t%s\n" name (Printexc.to_string ex)
  done
