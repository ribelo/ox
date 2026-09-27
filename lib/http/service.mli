(** Consumer-used routing and extraction helpers for {!Server}. All helpers are
    synchronous results; caller switch owns the request body and socket. *)
module Req : sig
  type t

  val raw : t -> Server.Request.t
  val params : t -> Router.Params.t
  val route_pattern : t -> string
  val param : t -> string -> string option
  val path : t -> string
  val query : t -> string option
  val method_ : t -> string
  val header : t -> string -> string option
  val body : t -> Server.Body.t
end

module Router : sig
  type route = Req.t -> (Server.Response.t, Server.Error.t) result

  type registration_error =
    | Empty_method_set of { pattern : string }
    | Invalid_method of { pattern : string; method_ : string }
    | Duplicate_route of { pattern : string; method_ : string option }
    | Ambiguous_any_route of { pattern : string }
    | Invalid_pattern of { pattern : string; reason : Router.Error.insert }

  type t

  val pp_registration_error : Format.formatter -> registration_error -> unit
  val create : unit -> t

  val add :
    t -> methods:string list -> string -> route -> (unit, registration_error) result

  val add_exn : t -> methods:string list -> string -> route -> unit
  val add_any : t -> string -> route -> (unit, registration_error) result
  val add_any_exn : t -> string -> route -> unit

  val compile :
    ?not_found:Server.handler ->
    ?method_not_allowed:(allowed:string list -> Server.handler) ->
    t ->
    Server.handler
  (** Freeze route topology and method associations; later builder mutations do not alter
      a compiled handler. *)
end

module Extractors : sig
  module Param : sig
    val string : string -> Req.t -> (string, Server.Error.t) result
  end

  module Query : sig
    type t = (string * string) list

    val all : Req.t -> (t, Server.Error.t) result
    val get : string -> t -> string option
    val get_all : string -> t -> string list
  end

  val body_text : ?max_bytes:int -> Req.t -> (string, Server.Error.t) result
end

module Json : sig
  val response : ?status:int -> ?newline:bool -> Eta_json.t -> Server.Response.t
end

module Serve : sig
  val tcp_addr : host:string -> port:int -> Eio.Net.Sockaddr.stream

  val h1 :
    sw:Eio.Switch.t ->
    net:_ Eio.Net.t ->
    clock:[> float Eio.Time.clock_ty ] Eio.Std.r ->
    ?stop:unit Eio.Promise.t ->
    ?drain_timeout:Eta.Duration.t ->
    ?config:Server.Config.t ->
    ?on_error:(exn -> unit) ->
    ?addr:Eio.Net.Sockaddr.stream ->
    ?host:string ->
    ?port:int ->
    Server.handler ->
    unit
end
