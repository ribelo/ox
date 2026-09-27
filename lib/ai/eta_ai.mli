(** The transport the AI clients share.

    A client keeps the pieces that do not differ between endpoints — bearer auth, a
    bounded JSON POST, the two-attempt retry policy, and the six typed failures — here, so
    the System One client and the chat client cannot drift apart under failure
    (^nso-y4rw).

    Cancellation and finalizers: this module is pure except for {!Transport.post_json},
    which performs one bounded POST per attempt in the calling fiber; see that function's
    contract. *)

module Error = Error
(** The typed failures every AI client returns, with {!Error.retryable}. *)

module Bearer = Bearer
(** The [Authorization: Bearer] header, built from a redacted key. *)

module Transport = Transport
(** The bounded JSON POST, the retry policy and the eta_http error mapping. *)
