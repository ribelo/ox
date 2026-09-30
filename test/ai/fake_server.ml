(* The local HTTP test server the System One tests drive (^nso-hcfr).

   Row 19 serves plaintext over a loopback listener on the test's own switch and clock;
   this is the same shape, scripted: each connection reads one complete request, records
   it, and answers with the script's next step after that step's delay, which is real time
   on the caller's clock.

   Cancellation and finalizers: the accept loop is a daemon of the caller's switch, so the
   switch's release cancels it; it registers no finalizer of its own. The caller owns the
   switch, the clock and the net. *)

type response =
  | Response of string  (** Raw HTTP bytes, written after the script's delay. *)
  | Chunks of (Ox.Duration.t * string) list
      (** Response fragments, each written after its delay; exercises idle progress. *)
  | Silent
      (** The connection is closed with no reply at all: a transport failure for the
          client, after the script's delay so a test can make the client's deadline the
          thing that fires. *)

type script = { delay : Ox.Duration.t; response : response }
(** What one connection does. *)

type t = {
  port : int;
  requests : (string * (string * string) list * string) list ref;
      (** method, headers (lowercased names, with [host] carrying the request target),
          body *)
  connections : int ref;
}

let http_response ?(status = 200) ?(reason = "OK") ?(headers = []) body =
  let headers =
    ("Content-Length", string_of_int (String.length body))
    :: ("Connection", "close") :: headers
  in
  Printf.sprintf "HTTP/1.1 %d %s\r\n%s\r\n\r\n%s" status reason
    (String.concat "\r\n" (List.map (fun (name, value) -> name ^ ": " ^ value) headers))
    body

let ok ?status ?reason ?headers body =
  [
    {
      delay = Ox.Duration.zero;
      response = Response (http_response ?status ?reason ?headers body);
    };
  ]

let after delay response = [ { delay; response } ]

let read_request flow =
  let input = Eio.Buf_read.of_flow ~max_size:(8 * 1024 * 1024) flow in
  let line = Eio.Buf_read.line input in
  let method_, target =
    match String.split_on_char ' ' line with
    | method_ :: target :: _ -> (method_, target)
    | _ -> ("", "")
  in
  let rec headers acc =
    let line = Eio.Buf_read.line input in
    if String.equal line "" then List.rev acc
    else
      match String.index_opt line ':' with
      | Some at ->
          headers
            (( String.lowercase_ascii (String.trim (String.sub line 0 at)),
               String.trim (String.sub line (at + 1) (String.length line - at - 1)) )
            :: acc)
      | None -> headers acc
  in
  let headers = headers [] in
  let body =
    match List.assoc_opt "content-length" headers with
    | Some length -> Eio.Buf_read.take (int_of_string length) input
    | None -> ""
  in
  (method_, ("host", target) :: headers, body)

let start ~clock ~sw listener scripts =
  let port =
    match Eio.Net.listening_addr listener with
    | `Tcp (_, port) -> port
    | _ -> assert false
  in
  let requests = ref [] and connections = ref 0 in
  ignore
    (Eio.Fiber.fork_daemon ~sw (fun () ->
         let rec accept () : [ `Stop_daemon ] =
           let flow, _ = Eio.Net.accept ~sw listener in
           connections := !connections + 1;
           requests := !requests @ [ read_request flow ];
           let script =
             match List.nth_opt scripts (!connections - 1) with
             | Some script -> script
             | None -> { delay = Ox.Duration.zero; response = Silent }
           in
           if Ox.Duration.to_seconds_float script.delay > 0. then
             Eio.Time.sleep clock (Ox.Duration.to_seconds_float script.delay);
           (* A client that stops reading (a response past its bound) closes its side
              first, so a write can fail; that is the client's verdict to make, not the
              server's. *)
           (try
              match script.response with
              | Silent -> Eio.Flow.shutdown flow `Send
              | Response bytes ->
                  Eio.Flow.copy_string bytes flow;
                  Eio.Flow.shutdown flow `Send
              | Chunks chunks ->
                  List.iter
                    (fun (delay, bytes) ->
                      Eio.Time.sleep clock (Ox.Duration.to_seconds_float delay);
                      Eio.Flow.copy_string bytes flow)
                    chunks;
                  Eio.Flow.shutdown flow `Send
            with Eio.Io _ | End_of_file -> ());
           accept ()
         in
         accept ()));
  { port; requests; connections }

(* The accept loop parks on the listening socket, and a plain [Eio.Fiber.fork] parked in
   [accept] is never woken by the switch release — the teardown then waits forever. A
   daemon fiber is cancelled by the release, so the loop is a daemon and a test needs no
   teardown of its own. *)
let serve ~net ~clock ~sw scripts =
  let listener =
    Eio.Net.listen ~sw ~backlog:8 net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  start ~clock ~sw listener scripts

let requests server = !(server.requests)
let connections server = !(server.connections)
let port server = server.port
let url server path = Printf.sprintf "http://127.0.0.1:%d%s" server.port path

let request server =
  match requests server with [] -> None | request :: _ -> Some request

let body server = match request server with Some (_, _, body) -> body | None -> ""
