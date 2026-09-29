type 'base t = { base : 'base; logger : Ox_observability.Logger.t }
(** Door-created handles. [base] is the original Eio environment; [logger] writes to its
    stderr. This record owns no resource; writes may suspend and be cancelled, while the
    Door's root switch runs all Service finalizers. *)
