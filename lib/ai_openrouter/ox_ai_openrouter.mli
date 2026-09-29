(** Focused OpenRouter endpoints: the Responses call with WAV audio, indexed text
    embeddings and the WAV transcription upload. Each call performs bounded I/O in the
    caller's fiber; cancellation closes the HTTP request socket and no finalizer is
    registered here. *)

module Responses = Responses
(** One non-streaming Responses call: model, prompt and WAV input, optional structured
    text output and reasoning effort, and the reply's status, every output item with its
    kind, and the {!Responses.deliverable} verdict a text caller obeys. *)

module Embeddings = Embeddings
(** One or many text embeddings with the caller's dimensions, returned in the order the
    provider indexed them. *)

module Audio = Audio
(** The bounded WAV multipart upload behind direct speech-to-text. *)
