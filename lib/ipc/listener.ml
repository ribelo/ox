type policy = {
  peers : int;
  backlog : int;
  max_line_bytes : int;
  max_reply_bytes : int;
  ingress : Eta.Duration.t;
  egress : Eta.Duration.t;
}

let default_policy =
  {
    peers = 16;
    backlog = 16;
    max_line_bytes = 65536;
    max_reply_bytes = 65536;
    ingress = Eta.Duration.seconds 1;
    egress = Eta.Duration.seconds 1;
  }

type error =
  [ `Invalid_policy of string
  | `Unsafe_runtime_dir
  | `Inaccessible_runtime_dir
  | `Ownership_conflict of string
  | `Active_listener
  | `Lock_conflict
  | `Lock_identity
  | `Probe_failed
  | `Bind_failed of string ]

type ('d, 'h) peer_error =
  [ `Ingress_timeout
  | `Ingress_too_large
  | `Ingress_closed
  | `Decode of 'd
  | `Handler of 'h
  | `Handler_budget_exceeded
  | `Egress_timeout
  | `Egress_too_large
  | `Egress_closed
  | `Disconnected ]

exception Refusal of error

let same a b = a.Unix.st_dev = b.Unix.st_dev && a.st_ino = b.st_ino
let ours s = s.Unix.st_uid = Unix.geteuid ()
let private_dir s = s.Unix.st_kind = Unix.S_DIR && ours s && s.st_perm land 0o077 = 0
let reg = Hashtbl.create 8
let mutex = Mutex.create ()

let synchronized f =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) f

let claim key =
  synchronized (fun () ->
      if Hashtbl.mem reg key then false
      else (
        Hashtbl.add reg key ();
        true))

let release key = synchronized (fun () -> Hashtbl.remove reg key)

let rec parent path =
  match Unix.lstat path with
  | s ->
      if s.st_kind <> Unix.S_DIR then raise (Refusal `Inaccessible_runtime_dir);
      if not (private_dir s) then raise (Refusal `Unsafe_runtime_dir);
      s
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      (try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      parent path
  | exception Unix.Unix_error _ -> raise (Refusal `Inaccessible_runtime_dir)

let verify_parent path before =
  match Unix.lstat path with
  | s when private_dir s && same s before -> ()
  | _ -> raise (Refusal `Inaccessible_runtime_dir)
  | exception Unix.Unix_error _ -> raise (Refusal `Inaccessible_runtime_dir)

let protect_fd fd f =
  match f fd with
  | x -> x
  | exception e ->
      Unix.close fd;
      raise e

let lock path =
  let path = path ^ ".lock" in
  let valid s =
    s.Unix.st_kind = Unix.S_REG && ours s && s.st_perm land 0o022 = 0 && s.st_nlink = 1
  in
  let rec open_fd () =
    match Unix.lstat path with
    | before ->
        if not (valid before) then raise (Refusal `Lock_identity);
        let fd = Unix.openfile path [ Unix.O_RDWR; Unix.O_CLOEXEC ] 0o600 in
        protect_fd fd (fun fd ->
            if not (valid (Unix.fstat fd) && same before (Unix.fstat fd)) then
              raise (Refusal `Lock_identity);
            fd)
    | exception Unix.Unix_error (Unix.ENOENT, _, _) -> (
        match
          Unix.openfile path
            [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC ]
            0o600
        with
        | fd ->
            protect_fd fd (fun fd ->
                if not (valid (Unix.fstat fd)) then raise (Refusal `Lock_identity);
                fd)
        | exception Unix.Unix_error (Unix.EEXIST, _, _) -> open_fd ())
  in
  let fd = open_fd () in
  protect_fd fd (fun fd ->
      match Unix.lockf fd Unix.F_TLOCK 0 with
      | () -> fd
      | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EACCES), _, _) ->
          raise (Refusal `Lock_conflict))

type probe = Live | Stale | Missing

let probe path =
  let fd = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close fd)
    (fun () ->
      Unix.set_nonblock fd;
      match Unix.connect fd (Unix.ADDR_UNIX path) with
      | () -> Live
      | exception Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> Stale
      | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Missing
      | exception Unix.Unix_error _ -> raise (Refusal `Probe_failed))

let recover path =
  match Unix.lstat path with
  | before -> (
      if before.st_kind <> Unix.S_SOCK || not (ours before) then
        raise (Refusal (`Ownership_conflict path));
      match probe path with
      | Live -> raise (Refusal `Active_listener)
      | Missing -> ()
      | Stale -> (
          match Unix.lstat path with
          | after when after.st_kind = Unix.S_SOCK && ours after && same before after ->
              Unix.unlink path
          | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
          | _ -> raise (Refusal (`Ownership_conflict path))))
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let unlink_owned path id =
  match Unix.lstat path with
  | s when s.st_kind = Unix.S_SOCK && ours s && same s id -> Unix.unlink path
  | _ -> ()
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let validate p =
  let check ok name = if not ok then raise (Refusal (`Invalid_policy name)) in
  check (p.peers > 0) "peers";
  check (p.backlog > 0) "backlog";
  check (p.max_line_bytes > 0) "max_line_bytes";
  check (p.max_reply_bytes > 0) "max_reply_bytes";
  check (Eta.Duration.to_ms p.ingress > 0) "ingress";
  check (Eta.Duration.to_ms p.egress > 0) "egress"

let disconnected = function
  | End_of_file
  | Unix.Unix_error ((Unix.EPIPE | Unix.ECONNRESET | Unix.ECONNABORTED), _, _) ->
      true
  | Eio.Io (Eio.Net.E (Eio.Net.Connection_reset _), _) -> true
  | _ -> false

let read_line flow max_bytes =
  let buf = Cstruct.create 4096 and out = Buffer.create (min 4096 max_bytes) in
  let rec read () =
    let n = Eio.Flow.single_read flow buf in
    let rec scan i =
      if i = n then read ()
      else if Cstruct.get_char buf i = '\n' then Ok (Buffer.contents out)
      else if Buffer.length out >= max_bytes then Error `Ingress_too_large
      else (
        Buffer.add_char out (Cstruct.get_char buf i);
        scan (i + 1))
    in
    scan 0
  in
  match read () with x -> x | exception e when disconnected e -> Error `Ingress_closed

type ('reply, 'error) outcome = Disconnected | Reply of 'reply | Failed of 'error

(* One egress path for every reply the listener writes, a handler's own or the one a
   budget-cut request is answered with: byte bound, then the egress deadline. *)
let respond ~clock ~policy ~encode ~on_peer_error flow reply =
  let bytes = encode reply in
  if String.length bytes > policy.max_reply_bytes || String.contains bytes '\n' then
    on_peer_error `Egress_too_large
  else
    match
      Eta.Timeout.timeout ~clock policy.egress (fun () ->
          try
            Eio.Flow.copy_string (bytes ^ "\n") flow;
            Ok ()
          with e when disconnected e -> Error `Egress_closed)
    with
    | Ok () -> ()
    | Error `Timeout -> on_peer_error `Egress_timeout
    | Error `Egress_closed -> on_peer_error `Egress_closed

let peer ~clock ~policy ~decode ~encode ~budget ~on_budget_exceeded ~error_response
    ~handler ~on_peer_error flow =
  (* An ingress failure reaches no handler, so the caller decides whether the peer still
     hears about it: the chosen reply goes through the same egress path as a handler's. *)
  let refuse e =
    on_peer_error e;
    match error_response e with
    | None -> ()
    | Some reply -> respond ~clock ~policy ~encode ~on_peer_error flow reply
  in
  let ingress =
    Eta.Timeout.timeout ~clock policy.ingress (fun () ->
        read_line flow policy.max_line_bytes)
  in
  match ingress with
  | Error `Timeout -> refuse `Ingress_timeout
  | Error (`Ingress_too_large as e) -> refuse e
  | Error (`Ingress_closed as e) -> on_peer_error e
  | Ok line -> (
      match decode line with
      | Error e -> refuse (`Decode e)
      | Ok request -> (
          let work () =
            match budget request with
            | None -> (
                match handler request with Ok x -> Ok x | Error e -> Error (`Handler e))
            | Some d -> (
                match
                  Eta.Timeout.timeout ~clock d (fun () ->
                      match handler request with
                      | Ok x -> Ok x
                      | Error e -> Error (`Handler e))
                with
                | Ok x -> Ok x
                | Error (`Handler e) -> Error (`Handler e)
                | Error `Timeout -> Error (`Budget d))
          in
          let monitor () =
            let buf = Cstruct.create 1024 in
            let rec drain () =
              match Eio.Flow.single_read flow buf with
              | _ -> drain ()
              | exception e when disconnected e -> Disconnected
            in
            drain ()
          in
          let outcome =
            Eio.Fiber.first
              (fun () -> match work () with Ok x -> Reply x | Error e -> Failed e)
              monitor
          in
          match outcome with
          | Disconnected -> on_peer_error `Disconnected
          | Reply reply -> respond ~clock ~policy ~encode ~on_peer_error flow reply
          | Failed (`Handler e) -> on_peer_error (`Handler e)
          | Failed (`Budget d) -> (
              on_peer_error `Handler_budget_exceeded;
              match on_budget_exceeded with
              | None -> ()
              | Some reply ->
                  respond ~clock ~policy ~encode ~on_peer_error flow (reply request d))))

let run ~sw ~fs:(_ : _ Eio.Path.t) ~net:(_ : _ Eio.Net.ty Eio.Resource.t) ~clock ~path
    ?(policy = default_policy) ~decode ~encode ~budget ~handler ?on_budget_exceeded
    ?(error_response = fun _ -> None) ?(on_peer_error = fun _ -> ()) () =
  try
    validate policy;
    let dirname = Filename.dirname path in
    let parent_id = parent dirname in
    let key = (parent_id.st_dev, parent_id.st_ino, Filename.basename path) in
    if not (claim key) then raise (Refusal `Lock_conflict);
    let lock_fd = ref None
    and raw = ref None
    and identity = ref None
    and released = ref false in
    let retire () =
      if not !released then (
        released := true;
        Fun.protect
          ~finally:(fun () -> release key)
          (fun () ->
            Fun.protect
              ~finally:(fun () -> Option.iter Unix.close !lock_fd)
              (fun () ->
                Fun.protect
                  ~finally:(fun () -> Option.iter (unlink_owned path) !identity)
                  (fun () -> Option.iter Unix.close !raw))))
    in
    Eio.Switch.on_release sw retire;
    let guarded f =
      match f () with
      | x -> x
      | exception e ->
          retire ();
          raise e
    in
    guarded (fun () ->
        lock_fd := Some (lock path);
        verify_parent dirname parent_id;
        recover path;
        verify_parent dirname parent_id;
        let fd = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
        raw := Some fd;
        Unix.bind fd (Unix.ADDR_UNIX path);
        let id = Unix.lstat path in
        if id.st_kind <> Unix.S_SOCK || not (ours id) then
          raise (Refusal (`Ownership_conflict path));
        identity := Some id;
        Unix.listen fd policy.backlog;
        Unix.chmod path 0o600;
        verify_parent dirname parent_id;
        Eio.Switch.check sw;
        let listener = Eio_unix.Net.import_socket_listening ~sw ~close_unix:true fd in
        raw := None;
        let slots = Eio.Semaphore.make policy.peers in
        Eio.Fiber.fork_daemon ~sw (fun () ->
            try
              while true do
                Eio.Semaphore.acquire slots;
                let flow, _ =
                  try Eio.Net.accept ~sw listener
                  with e ->
                    Eio.Semaphore.release slots;
                    raise e
                in
                Eio.Fiber.fork_daemon ~sw (fun () ->
                    Fun.protect
                      ~finally:(fun () ->
                        Eio.Cancel.protect (fun () ->
                            Fun.protect
                              ~finally:(fun () -> Eio.Semaphore.release slots)
                              (fun () -> Eio.Flow.close flow)))
                      (fun () ->
                        peer ~clock ~policy ~decode ~encode ~budget ~on_budget_exceeded
                          ~error_response ~handler ~on_peer_error flow);
                    `Stop_daemon)
              done;
              `Stop_daemon
            with
            | Eio.Cancel.Cancelled _ -> `Stop_daemon
            | e ->
                Eio.Switch.fail sw e;
                `Stop_daemon);
        Ok ())
  with
  | Refusal e -> Error e
  | Unix.Unix_error (err, op, _) ->
      Error (`Bind_failed (op ^ ": " ^ Unix.error_message err))
