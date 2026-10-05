val tests :
  caps:< Ox_caps.Cap.time ; Ox_caps.Cap.fs_read ; .. > -> unit Alcotest.test_case list
(** ^safe-p9cw ^safe-8peq ^safe-5a9k: deterministic native SQL clock controls. Suspension:
    may suspend if delegated Alcotest.test_case or construction callbacks suspend;
    delegated Stdlib and Stdlib.List operations retain their own behaviour. Cancellation:
    depends on delegated Alcotest.test_case and callback dispatch; this function does not
    itself execute the test bodies. Finalizers: no cleanup is registered by this function
    until a returned test runs. Locking: no lock is acquired by this function while
    constructing test closures. Cancellation safety: unsafe because progress is lost if
    delegated construction is interrupted; no SQL resources have been opened by this
    function. *)

val verify : caps:< Ox_caps.Cap.time ; Ox_caps.Cap.fs_read ; .. > -> unit -> unit
(** Suspension: may suspend in mock fiber, promise, lease and deadline operations; SQLite
    calls may block the domain. Cancellation: propagates external cancellation; requested
    worker cancellation is classified by Scope.run; Alcotest assertions raise on fixture
    failure and delegated Alcotest, Eio, Eio_mock, Ox, Ox_sql, Stdlib operations retain
    their own behaviour. Finalizers: switch-owned pools close after every test;
    transaction rollback and lease restoration precede timeout or cancellation
    observation. Locking: test fibers use exclusive leases and the pool's protected state
    mutex. Cancellation safety: unsafe because progress is lost if the verification suite
    is cancelled; fixture resources are scoped and a fresh suite can run again. *)
