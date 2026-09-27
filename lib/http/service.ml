module S = Server
module Path_router = Router

let bad_request (request : S.Request.t) message =
  Error
    (S.Error.make ~method_:request.method_ ~target:request.target
       (S.Error.Bad_request { message }))

module Req = struct
  type t = { raw : S.Request.t; params : Path_router.Params.t; route_pattern : string }

  let raw t = t.raw
  let params t = t.params
  let route_pattern t = t.route_pattern
  let param t name = Path_router.Params.get t.params name
  let path t = t.raw.S.Request.path
  let query t = t.raw.S.Request.query
  let method_ t = t.raw.S.Request.method_
  let header t name = S.Request.header name t.raw
  let body t = t.raw.S.Request.body
end

module Router = struct
  type route = Req.t -> (S.Response.t, S.Error.t) result

  type registration_error =
    | Empty_method_set of { pattern : string }
    | Invalid_method of { pattern : string; method_ : string }
    | Duplicate_route of { pattern : string; method_ : string option }
    | Ambiguous_any_route of { pattern : string }
    | Invalid_pattern of { pattern : string; reason : Path_router.Error.insert }

  type entry = {
    pattern : string;
    mutable any : route option;
    mutable methods : (string * route) list;
  }

  type t = { router : entry Path_router.t; entries : (string, entry) Hashtbl.t }

  let pp_registration_error fmt = function
    | Empty_method_set { pattern } -> Format.fprintf fmt "empty method set for %S" pattern
    | Invalid_method { pattern; method_ } ->
        Format.fprintf fmt "invalid method %S for %S" method_ pattern
    | Duplicate_route { pattern; method_ } ->
        Format.fprintf fmt "duplicate route %S (%s)" pattern
          (Option.value ~default:"any" method_)
    | Ambiguous_any_route { pattern } ->
        Format.fprintf fmt "ambiguous any-method route %S" pattern
    | Invalid_pattern { pattern; _ } ->
        Format.fprintf fmt "invalid route pattern %S" pattern

  let create () = { router = Path_router.create (); entries = Hashtbl.create 32 }

  let ensure_entry t pattern =
    match Hashtbl.find_opt t.entries pattern with
    | Some entry -> Ok entry
    | None -> (
        let entry = { pattern; any = None; methods = [] } in
        match Path_router.insert t.router pattern entry with
        | Error reason -> Error (Invalid_pattern { pattern; reason })
        | Ok () ->
            Hashtbl.add t.entries pattern entry;
            Ok entry)

  let validate_methods pattern methods =
    if methods = [] then Error (Empty_method_set { pattern })
    else
      let rec loop seen = function
        | [] -> Ok ()
        | method_ :: _ when Header.validate_name method_ <> None || method_ = "" ->
            Error (Invalid_method { pattern; method_ })
        | method_ :: _ when List.mem method_ seen ->
            Error (Duplicate_route { pattern; method_ = Some method_ })
        | method_ :: rest -> loop (method_ :: seen) rest
      in
      loop [] methods

  let add t ~methods pattern route =
    match validate_methods pattern methods with
    | Error _ as error -> error
    | Ok () -> (
        match ensure_entry t pattern with
        | Error _ as error -> error
        | Ok entry -> (
            if entry.any <> None then Error (Ambiguous_any_route { pattern })
            else
              match
                List.find_opt
                  (fun method_ -> List.mem_assoc method_ entry.methods)
                  methods
              with
              | Some method_ ->
                  Error (Duplicate_route { pattern; method_ = Some method_ })
              | None ->
                  entry.methods <-
                    entry.methods @ List.map (fun method_ -> (method_, route)) methods;
                  Ok ()))

  let add_any t pattern route =
    match ensure_entry t pattern with
    | Error _ as error -> error
    | Ok entry when entry.any <> None ->
        Error (Duplicate_route { pattern; method_ = None })
    | Ok entry when entry.methods <> [] -> Error (Ambiguous_any_route { pattern })
    | Ok entry ->
        entry.any <- Some route;
        Ok ()

  let add_exn t ~methods pattern route =
    match add t ~methods pattern route with
    | Ok () -> ()
    | Error e -> invalid_arg (Format.asprintf "%a" pp_registration_error e)

  let add_any_exn t pattern route =
    match add_any t pattern route with
    | Ok () -> ()
    | Error e -> invalid_arg (Format.asprintf "%a" pp_registration_error e)

  let default_method_not_allowed ~allowed _ =
    Ok
      (S.Response.text ~status:405
         ~headers:(Header.unsafe_of_list [ ("allow", String.concat ", " allowed) ])
         "method not allowed\n")

  let compile ?(not_found = S.Handler.route_not_found)
      ?(method_not_allowed = default_method_not_allowed) t =
    let snapshot = Path_router.create () in
    Hashtbl.iter
      (fun pattern entry ->
        let value = { pattern; any = entry.any; methods = entry.methods } in
        match Path_router.insert snapshot pattern value with
        | Ok () -> ()
        | Error _ -> assert false)
      t.entries;
    fun request ->
      match Path_router.at snapshot request.S.Request.path with
      | Error _ -> not_found request
      | Ok matched -> (
          let entry = matched.value in
          let req =
            Req.{ raw = request; params = matched.params; route_pattern = entry.pattern }
          in
          match entry.any with
          | Some f -> f req
          | None -> (
              match List.assoc_opt request.method_ entry.methods with
              | Some f -> f req
              | None -> method_not_allowed ~allowed:(List.map fst entry.methods) request))
end

module Extractors = struct
  module Param = struct
    let string name req =
      match Req.param req name with
      | Some value -> Ok value
      | None -> bad_request (Req.raw req) ("missing route parameter " ^ name)
  end

  module Query = struct
    type t = (string * string) list

    let split_once char text =
      match String.index_opt text char with
      | None -> (text, "")
      | Some index ->
          ( String.sub text 0 index,
            String.sub text (index + 1) (String.length text - index - 1) )

    let hex_value = function
      | '0' .. '9' as c -> Some (Char.code c - Char.code '0')
      | 'a' .. 'f' as c -> Some (10 + Char.code c - Char.code 'a')
      | 'A' .. 'F' as c -> Some (10 + Char.code c - Char.code 'A')
      | _ -> None

    let percent_decode text =
      let len = String.length text in
      let b = Buffer.create len in
      let rec loop index =
        if index >= len then Ok (Buffer.contents b)
        else
          match text.[index] with
          | '+' ->
              Buffer.add_char b ' ';
              loop (index + 1)
          | '%' when index + 2 < len -> (
              match (hex_value text.[index + 1], hex_value text.[index + 2]) with
              | Some hi, Some lo ->
                  Buffer.add_char b (Char.chr ((hi lsl 4) + lo));
                  loop (index + 3)
              | _ -> Error "invalid percent-encoding in query string")
          | '%' -> Error "truncated percent-encoding in query string"
          | char ->
              Buffer.add_char b char;
              loop (index + 1)
      in
      loop 0

    let parse raw =
      match raw with
      | None | Some "" -> Ok []
      | Some query ->
          let rec loop acc = function
            | [] -> Ok (List.rev acc)
            | part :: rest -> (
                let key, value = split_once '=' part in
                match (percent_decode key, percent_decode value) with
                | Ok key, Ok value -> loop ((key, value) :: acc) rest
                | Error message, _ | _, Error message -> Error message)
          in
          loop [] (String.split_on_char '&' query)

    let all req =
      match parse (Req.query req) with
      | Ok query -> Ok query
      | Error message -> bad_request (Req.raw req) message

    let get name t = List.assoc_opt name t

    let get_all name t =
      List.filter_map (fun (key, value) -> if key = name then Some value else None) t
  end

  let body_text ?(max_bytes = 1024 * 1024) req =
    match S.Body.read_all ~max_bytes (Req.body req) with
    | Ok body -> Ok (Bytes.to_string body)
    | Error e ->
        let raw = Req.raw req in
        Error { e with S.Error.method_ = raw.method_; target = raw.target }
end

module Json = struct
  let response ?(status = 200) ?(newline = false) json =
    let content = Eta_json.compact json ^ if newline then "\n" else "" in
    S.Response.text ~status
      ~headers:
        (Header.unsafe_of_list [ ("content-type", "application/json; charset=utf-8") ])
      content
end

module Serve = struct
  let tcp_addr ~host ~port =
    if port < 0 || port > 65535 then invalid_arg "invalid port";
    `Tcp (Eio_unix.Net.Ipaddr.of_unix (Unix.inet_addr_of_string host), port)

  let h1 ~sw ~net ~clock ?stop ?drain_timeout ?config ?on_error ?addr
      ?(host = "127.0.0.1") ?(port = 8080) handler =
    let addr = match addr with Some addr -> addr | None -> tcp_addr ~host ~port in
    S.run_h1 ~sw ~net ~clock ?stop ?drain_timeout ?config ?on_error ~addr handler
end
