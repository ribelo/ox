val check : unit -> unit
(** ^safe-p9cw ^safe-8peq ^safe-5a9k: native-clock public consumer control.

    Suspension: may suspend in the private mock backend and switch cleanup; delegated
    Eio_mock.Backend, Eio_mock.Net, Ox_http.Client, Ox_http.Ws_client, Ox_otel and
    Ox.Duration operations retain their own behaviour. Cancellation: propagates from the
    private owner switch; delegated mock and HTTP/OTel operations retain their own
    behaviour. Cancellation safety: safe to re-run; each control owns a fresh switch and
    refuses configuration before exporting or connecting. Finalizers: the private switch
    releases all mock resources and the HTTP client. Locking: no mutex is held across
    callback or caller code. *)
