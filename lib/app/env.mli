type 'base t = {
  base : 'base;
  logger : Ox_observability.Logger.t;
  caps : Ox_caps.Cap.all_caps;
}
(** Door-created handles. [base] is the original Eio environment; [logger] writes to its
    stderr; [caps] is the process's powerbox, minted by the Door and nowhere else
    (^ncaps-0mvw): the program narrows it by type ascription and hands each Service the
    capabilities its signature names (docs/caps.md). This record owns no resource; writes
    may suspend and be cancelled, while the Door's root switch runs all Service
    finalizers. *)
