(* ^safe-o2b6 ^safe-3o27: scripted POST peer at the public transport seam.
   Each complete request commits at most once; losing the reply cannot undo it. *)
type action =
  | Before_commit
  | Lose_reply
  | Withhold_reply
  | Truncate_reply
  | Reply of int

type t = {
  endpoint : string;
  requests : int ref;
  effects : int ref;
  committed : unit Eio.Promise.t;
  closed : unit Eio.Promise.t;
}

let start ~sw ~net actions =
  let socket =
    Eio.Net.listen net ~sw ~reuse_addr:true ~backlog:8
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  let port =
    match Eio.Net.listening_addr socket with `Tcp (_, port) -> port | _ -> assert false
  in
  let requests = ref 0 and effects = ref 0 in
  let committed, commit = Eio.Promise.create () in
  let closed, close = Eio.Promise.create () in
  let remaining = ref actions in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      while true do
        Eio.Net.accept_fork socket ~sw ~on_error:raise (fun flow _ ->
            incr requests;
            let action =
              match !remaining with
              | [] -> Lose_reply
              | action :: rest ->
                  remaining := rest;
                  action
            in
            let reader = Eio.Buf_read.of_flow flow ~max_size:65536 in
            let request_line = Eio.Buf_read.line reader in
            Alcotest.(check bool)
              "^safe-o2b6 real POST" true
              (String.starts_with ~prefix:"POST " request_line);
            let rec headers length =
              match Eio.Buf_read.line reader with
              | "" -> length
              | line -> (
                  match String.index_opt line ':' with
                  | Some at
                    when String.lowercase_ascii (String.sub line 0 at) = "content-length"
                    ->
                      headers
                        (int_of_string
                           (String.trim
                              (String.sub line (at + 1) (String.length line - at - 1))))
                  | _ -> headers length)
            in
            ignore (Eio.Buf_read.take (headers 0) reader);
            if action <> Before_commit then (
              incr effects;
              if !effects = 1 then Eio.Promise.resolve commit ());
            match action with
            | Before_commit | Lose_reply -> ()
            | Withhold_reply -> (
                (* Wait for the client to close, not an arbitrary sleep. *)
                match Eio.Buf_read.any_char reader with
                | _ -> Alcotest.fail "unexpected bytes after complete POST"
                | exception End_of_file ->
                    if not (Eio.Promise.is_resolved closed) then
                      Eio.Promise.resolve close ())
            | Truncate_reply ->
                Eio.Flow.copy_string
                  "HTTP/1.1 200 Test\r\n\
                   Content-Length: 100\r\n\
                   Connection: close\r\n\
                   \r\n\
                   {}"
                  flow
            | Reply status ->
                Eio.Flow.copy_string
                  (Printf.sprintf
                     "HTTP/1.1 %d Test\r\n\
                      Content-Length: 2\r\n\
                      Connection: close\r\n\
                      \r\n\
                      {}"
                     status)
                  flow)
      done;
      `Stop_daemon);
  {
    endpoint = Printf.sprintf "http://127.0.0.1:%d/effect" port;
    requests;
    effects;
    committed;
    closed;
  }
