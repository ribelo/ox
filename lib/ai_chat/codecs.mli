(** The completion a caller gets, and the step that extracts it from a reply.

    Cancellation and finalizers: {!completion_of_response} is pure and synchronous. It
    performs no I/O, blocks on nothing, forks no fiber and registers no finalizer.

    ^nchat-dys0 *)

type completion = {
  content : string;  (** the first choice's message text *)
  model : string;  (** the model the reply named *)
  finish_reason : string option;  (** why generation stopped, when the reply says *)
  usage : Types.usage;
      (** the tokens the completion cost, and the provider's own cost when the reply
          reports one (^nchat-qu3j) *)
  id : string option;  (** the provider's request id, when it sends one *)
}
(** What one {!Chat.complete} call returns. *)

val completion_of_response : Types.response -> (completion, string) result
(** [completion_of_response response] is [Ok] of the first choice — its content, the
    reply's model, usage and id — and [Error message] when the reply names no choice at
    all. Pure: nothing is completed here, the reply was already read. *)
