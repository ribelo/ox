val discarded_result :
  (Ocaml_common.Location.t -> unit) -> Ocaml_common.Tast_iterator.iterator
(** Finite local result-disposal analysis. Does not prove handling through unknown
    higher-order calls or inspect other compilation units. ^safe-1bc7 ^safe-s6km *)
