(** Focused OpenRouter endpoints: Responses calls with WAV/MP3 or text input, indexed text
    embeddings and the WAV transcription upload. Each call performs bounded I/O in the
    caller's fiber; cancellation closes the HTTP request socket and no finalizer is
    registered here. *)

module Responses = Responses
(** Non-streaming audio and text-only Responses calls: optional structured text output and
    reasoning effort, request/reply byte bounds and response idle policy; the reply's
    status, every output kind, and the {!Responses.deliverable} verdict a text caller
    obeys. *)

module Embeddings = Embeddings
(** One or many text embeddings with the caller's dimensions, returned in the order the
    provider indexed them. *)

module Audio = Audio
(** The bounded WAV multipart upload behind direct speech-to-text. *)
