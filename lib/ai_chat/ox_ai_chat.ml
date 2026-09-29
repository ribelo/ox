module Types = Types
module Codecs = Codecs
module Chat = Chat

(* The names Leash's drive spec uses (drive-ls3c calls [Ox_ai_chat.complete]): the client's
   own, at the package's top level. [t] is manifestly {!Chat.t}, so the two spellings
   interchange freely. *)
type t = Chat.t

let create = Chat.create
let complete = Chat.complete
let default_endpoint = Chat.default_endpoint
