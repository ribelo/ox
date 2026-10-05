include module type of Syntax

val known_export : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> string -> bool
(** Test-only compiler lookup seam. Suspension: never suspends in Eio itself; synchronous
    compiler work may block the domain; operations delegate to Stdlib and Env and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider. Cancellation: not a cancellation point in Eio itself; operations delegate to
    Stdlib and Env and their higher-order callbacks; capability object method dispatch
    depends on the supplied provider. Cancellation safety: safe to re-run; no progress or
    resources are consumed. Finalizers: none. Locking: compiler caches retain their
    existing locking. Missing identities return false. *)
