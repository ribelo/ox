(** The one place a raw API key is revealed.

    Every AI client takes its key as {!Eta_observability.Redact.t}, so a key cannot be
    logged, encoded or rendered by accident; this module builds the header with
    {!Eta_observability.Redact.expose} alone, on the path that writes the request.

    Cancellation and finalizers: [header] is pure and synchronous. It performs no I/O,
    blocks on nothing, forks no fiber and registers no finalizer. *)

val header : api_key:Eta_observability.Redact.t -> (string * string) list
(** [header ~api_key] is [["Authorization", "Bearer <key>"]]: the exact header the
    endpoints expect. The result does contain the key, so it belongs in a request and
    nowhere else. *)
