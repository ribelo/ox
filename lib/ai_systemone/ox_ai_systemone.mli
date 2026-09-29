(** The System One (JEV) client and its wire types.

    [Systemone.Client.evaluate] answers choice and score questions over a JSON state with
    probability distributions, fail-closed and bounded, over {!Ox_http} and the {!Ox_ai}
    core. Both contracts are served: OpenRouter's `https://openrouter.ai/api/v1/systemone`
    by default and `https://api.typesafe.ai/v1/systemone` when [~endpoint] says so.

    Cancellation and finalizers: nothing here owns a resource. [Client.evaluate] performs
    HTTP in the calling fiber and closes each attempt's socket; see its contract. *)

module Types = Types
(** The derived wire types. *)

module Codecs = Codecs
(** The answer and question unions, the reply, the request, and their fail-closed codecs.
*)

module Client = Client
(** The configured client and [evaluate]. *)
