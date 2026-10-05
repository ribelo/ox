type error = [ `Ox_sql of Types.sql_error | `Pool_shutdown | `Timeout ]
type pool
type tx

type state = {
  resources : Connection.t Eio.Pool.t;
  mutable closed : bool;
  mutable active : int;
  handles : Connection.t list ref;
  mutex : Eio.Mutex.t;
  changed : Eio.Condition.t;
  clock : Eio.Time.Mono.ty Eio.Time.Mono.t option;
  default_timeout : Ox.Duration.t option;
}

type 'kind runner = Pool of state | Transaction of state * Connection.t * bool ref
type t = pool runner

let guard s f = Eio.Mutex.use_rw ~protect:true s.mutex f

let shutdown_state s =
  guard s (fun () -> s.closed <- true);
  Eio.Mutex.use_ro s.mutex (fun () ->
      while s.active <> 0 do
        Eio.Condition.await s.changed s.mutex
      done);
  guard s (fun () ->
      List.iter
        (fun c ->
          (* ^safe-xls8 ^safe-pufa: shutdown closes every handle best effort without changing its outcome. *)
          let _close_result = Connection.close c in
          ())
        !(s.handles);
      s.handles := []);
  Ok ()

let create ~caps ~sw ?clock ?default_timeout ?(max_size = 4) config =
  if max_size < 1 then Error (`Ox_sql (Types.Pool_error "max_size must be positive"))
  else
    match Connection.create ~caps config with
    | Error err -> Error (`Ox_sql err)
    | Ok initial ->
        let mutex = Eio.Mutex.create () in
        let handles = ref [ initial ] in
        let first = ref (Some initial) in
        let make () =
          match !first with
          | Some c ->
              first := None;
              c
          | None -> (
              match Connection.create ~caps config with
              | Ok c ->
                  Eio.Mutex.use_rw ~protect:true mutex (fun () ->
                      handles := c :: !handles);
                  c
              | Error err -> raise (Sql_failure.Error err))
        in
        let resources =
          Eio.Pool.create
            ~validate:(fun c -> Connection.ping c)
            ~dispose:(fun c ->
              (* ^safe-xls8 ^safe-pufa: disposal is best effort and must not replace a checkout failure. *)
              let _close_result = Connection.close c in
              ())
            max_size make
        in
        let s =
          {
            resources;
            closed = false;
            active = 0;
            handles;
            mutex;
            changed = Eio.Condition.create ();
            clock;
            default_timeout;
          }
        in
        (* The first handle is already owned even if nobody checks it out. *)
        Eio.Switch.on_release sw (fun () ->
            (* ^safe-xls8 ^safe-pufa: switch release retains the pool's best-effort shutdown policy. *)
            let _shutdown_result = shutdown_state s in
            ());
        Ok (Pool s)

let shutdown = function Pool s -> shutdown_state s | Transaction _ -> assert false

let apply_timeout s override f =
  match
    (s.clock, match override with Some _ -> override | None -> s.default_timeout)
  with
  | Some clock, Some timeout ->
      Eio.Time.Timeout.run
        (Eio.Time.Timeout.seconds clock (Ox.Duration.to_seconds timeout))
        f
  | _ -> f ()

let use ?timeout runner f =
  let run s c = match f c with Ok x -> Ok x | Error err -> Error (`Ox_sql err) in
  match runner with
  | Transaction (s, c, valid) ->
      if not !valid then Error `Pool_shutdown
      else apply_timeout s timeout (fun () -> run s c)
  | Pool s ->
      if guard s (fun () -> s.closed) then Error `Pool_shutdown
      else
        apply_timeout s timeout (fun () ->
            try
              Eio.Pool.use s.resources (fun c ->
                  if guard s (fun () -> s.closed) then Error `Pool_shutdown
                  else (
                    guard s (fun () -> s.active <- s.active + 1);
                    Fun.protect
                      ~finally:(fun () ->
                        (match Connection.ensure_autocommit c with
                        | Ok () -> ()
                        | Error _ ->
                            (* ^safe-xls8 ^safe-pufa: close the unusable handle without replacing run's outcome. *)
                            let _close_result = Connection.close c in
                            ());
                        (* ^nlintc-g6k3: [guard] protects the update, not its lock wait. *)
                        Eio.Cancel.protect (fun () ->
                            guard s (fun () -> s.active <- s.active - 1));
                        Eio.Condition.broadcast s.changed)
                      (fun () -> run s c)))
            with Sql_failure.Error err -> Error (`Ox_sql err))

module Typed = struct
  let select ?timeout r q = use ?timeout r (fun c -> Connection.Typed.select c q)
  let returning ?timeout r q = use ?timeout r (fun c -> Connection.Typed.returning c q)

  let execute_compiled ?timeout r q =
    use ?timeout r (fun c -> Connection.Typed.execute_compiled c q)

  let run_schema ?timeout r q = use ?timeout r (fun c -> Connection.Typed.run_schema c q)

  let fold_select ?timeout r q ~init ~f =
    use ?timeout r (fun c -> Connection.Typed.fold_select c q ~init ~f)
end

module Raw = struct
  let query ?timeout r sql params =
    use ?timeout r (fun c -> Connection.Raw.query c sql params)

  let fold ?timeout r sql params ~init ~f =
    use ?timeout r (fun c -> Connection.Raw.fold c sql params ~init ~f)

  let execute ?timeout r sql params =
    use ?timeout r (fun c -> Connection.Raw.execute c sql params)

  let execute_script ?timeout r sql =
    use ?timeout r (fun c -> Connection.Raw.execute_script c sql)

  let with_connection r f =
    (* Borrow the live handle only within the lease. Preserve caller errors. *)
    match use r (fun c -> Ok (f (Connection.sqlite c))) with
    | Error err -> Error err
    | Ok value -> value
end

let with_transaction ?timeout pool body =
  use ?timeout pool (fun c ->
      let s = match pool with Pool s -> s | Transaction _ -> assert false in
      let valid = ref true in
      let outcome =
        Connection.with_transaction c (fun _ ->
            Fun.protect
              ~finally:(fun () -> valid := false)
              (fun () ->
                match body (Transaction (s, c, valid)) with
                | Ok x -> Ok x
                | Error (`Ox_sql err) -> Error err
                | Error `Pool_shutdown -> Error (Types.Pool_error "pool shut down")
                | Error `Timeout -> Error (Types.Pool_error "transaction timed out")))
      in
      match outcome with
      | Ox_sql_dsl.Committed x -> Ok x
      | Failed failure -> (
          match failure.primary with
          | Returned err -> Error err
          | Raised (exn, backtrace) -> Printexc.raise_with_backtrace exn backtrace))
