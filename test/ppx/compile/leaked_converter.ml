(* ^nderive-cd80: a nested converter must not leak into its outer module. *)
let encoder = Module_codecs.yojson_of_t
