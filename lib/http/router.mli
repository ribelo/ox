(** Pure URL path router.

    v1's [eta_router] matcher ([v1:lib/router/]) copied into [ox_http] for inn and nema
    (story ^hserv-e3q9). The module is pure and synchronous — no I/O, no clock, no
    [Effect.t] — so dispatching a request costs one radix-trie walk. It stores the route
    patterns a caller inserts and returns the caller's value with the decoded parameters;
    turning that into an HTTP response belongs to {!Ox_http.Server}, not here.

    Route syntax:
    - static: [/users/list]
    - named parameter: [/users/{id}]
    - catch-all parameter: [/files/{*path}]
    - prefix/suffix parameter: [/images/img-{id}.png]
    - escaped braces: [{{] and [}}] denote the literal bytes [{] and [}]

    Example:
    {[
    let router = Ox_http.Router.create () in
    (match Ox_http.Router.insert router "/users/{id}" "user" with
    | Ok () -> ()
    | Error _ -> assert false);
    match Ox_http.Router.at router "/users/978" with
    | Ok m ->
        assert (Ox_http.Router.Params.get m.params "id" = Some "978");
        assert (m.value = "user")
    | Error _ -> assert false
    ]} *)

module Error = Router_error
(** Insertion conflicts, malformed routes, and lookup misses. *)

module Params = Router_params
(** The named and catch-all parameters of a matched path, decoded on demand. *)

module Match = Router_match
(** The value and parameters of a successful {!at}. *)

type 'a t
(** A mutable route table. It is not thread-safe: build it before sharing it, or keep one
    per fiber. Stored values are never copied or inspected. *)

val create : unit -> 'a t
(** [create ()] is a new, empty router. *)

val insert : 'a t -> string -> 'a -> (unit, Error.insert) result
(** [insert router route value] registers [value] under [route].

    [Error (Error.Invalid_route reason)] means [route] is malformed: an unmatched or empty
    brace, a parameter name containing [/] or [*], or an unterminated parameter.
    [Error (Error.Conflict reason)] means another route already occupies the same path, or
    two different parameter names would occupy the same position. *)

val at : 'a t -> string -> ('a Match.t, Error.match_) result
(** [at router path] looks up [path] and returns the matched value and its parameters.
    [Error Error.Not_found] means no registered route matches. *)

val find : 'a t -> string -> 'a option
(** [find router path] is the value of a successful {!at}, or [None]. *)

val remove : 'a t -> string -> 'a option
(** [remove router route] unregisters [route] and returns the stored value.

    [route] must denote the pattern that was inserted, parameter names included. *)

val merge : into:'a t -> 'a t -> (unit, Error.merge) result
(** [merge ~into from] inserts every route of [from] into [into]. Insertion is not
    transactional: routes that did not conflict stay in [into], and
    [Error (Error.Conflicts conflicts)] lists the ones that failed. *)

val compress : 'a t -> unit
(** [compress router] merges consecutive single-child static nodes to reduce lookup depth.
    Safe once all inserts are done; do not insert afterwards. *)

(** {1 Internal building blocks}

    Exposed for the copied regression suite and for benchmarking, not part of the
    supported API. *)

module Escape = Router_escape
module Route = Router_route
