(** Direct-style HTTP/1.1 server. Bodies and sockets belong to the caller's switch;
    cancellation interrupts I/O and every accepted flow is closed on exit. *)

module Error : sig
  type kind =
    | Bad_request of { message : string }
    | Request_body_too_large of { limit : int; length : int }
    | Handler_failed of { message : string }

  type t = { method_ : string; target : string; kind : kind }

  val make : method_:string -> target:string -> kind -> t
  val pp : Format.formatter -> t -> unit
end

module Body : sig
  type t

  val empty : unit -> t
  val of_reader : (unit -> (bytes option, Error.t) result) -> t
  val read : t -> (bytes option, Error.t) result
  val read_all : ?max_bytes:int -> t -> (bytes, Error.t) result
  val discard : t -> (unit, Error.t) result
end

module Request : sig
  type peer = { address : string option; port : int option }

  type t = {
    id : string Lazy.t;
    version : Version.t;
    scheme : string;
    authority : string option;
    method_ : string;
    target : string;
    path : string;
    query : string option;
    headers : Header.t;
    body : Body.t;
    trailers : unit -> (Header.t, Error.t) result;
    peer : peer;
    tls : bool;
    alpn_protocol : string option;
    stream_id : int option;
    connection_id : string;
  }

  val split_target : string -> string * string option
  val header : string -> t -> string option
  val body : t -> Body.t
end

module Response : sig
  module Body : sig
    type stream = {
      length : int option;
      read : unit -> (bytes option, Error.t) result;
      release : unit -> unit;
    }

    type t = Empty | Fixed of bytes list | Stream of stream

    val empty : t
    val fixed : bytes list -> t
    val string : string -> t

    val stream :
      ?length:int ->
      ?release:(unit -> unit) ->
      (unit -> (bytes option, Error.t) result) ->
      t
  end

  type t

  val make :
    ?headers:Header.t ->
    ?trailers:(unit -> (Header.t, Error.t) result) ->
    status:int ->
    body:Body.t ->
    unit ->
    t

  val empty : ?headers:Header.t -> status:int -> unit -> t
  val text : ?headers:Header.t -> ?status:int -> string -> t
  val status : t -> int
  val headers : t -> Header.t
  val body : t -> Body.t
  val trailers : t -> unit -> (Header.t, Error.t) result
end

type handler = Request.t -> (Response.t, Error.t) result

module Handler : sig
  val of_sync : (Request.t -> Response.t) -> handler
  val of_result : handler -> handler
  val route_not_found : handler
  val default_error_response : Error.t -> Response.t
  val with_default_error_response : handler -> handler
end

module Config : sig
  type t = {
    max_request_line_bytes : int;
    max_request_header_bytes : int;
    max_request_headers : int;
    max_request_body_bytes : int;
    max_response_header_bytes : int;
  }

  val default : t
end

val run_h1_on_socket :
  sw:Eio.Switch.t ->
  clock:[> float Eio.Time.clock_ty ] Eio.Std.r ->
  ?stop:unit Eio.Promise.t ->
  ?drain_timeout:Eta.Duration.t ->
  ?config:Config.t ->
  ?on_error:(exn -> unit) ->
  socket:_ Eio.Net.listening_socket ->
  handler ->
  unit
(** Serve an already listening, caller-owned socket. Stopping accepts no more connections;
    active handlers drain up to [drain_timeout]. Idle flows close. Caller owns [socket]
    and closes it after this function returns. *)

val run_h1 :
  sw:Eio.Switch.t ->
  net:_ Eio.Net.t ->
  clock:[> float Eio.Time.clock_ty ] Eio.Std.r ->
  ?stop:unit Eio.Promise.t ->
  ?drain_timeout:Eta.Duration.t ->
  ?config:Config.t ->
  ?on_error:(exn -> unit) ->
  addr:Eio.Net.Sockaddr.stream ->
  handler ->
  unit
(** Listen on [addr] inside the provided switch and run the HTTP/1.1 server. *)
