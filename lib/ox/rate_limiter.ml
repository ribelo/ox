type verdict = Granted | Wait of Duration.t
type algorithm = { try_acquire : now_ms:int -> verdict }

type config =
  | Fixed_window of { n : int; per : Duration.t }
  | Sliding_window of { n : int; per : Duration.t }
  | Token_bucket of { capacity : int; per : Duration.t }
  | Custom of (now_ms:int -> algorithm)

type t = {
  algorithm : algorithm;
  now_ms : unit -> int;
  sleep : Duration.t -> unit;
  lock : Eio.Mutex.t;
}

let wait ms = Wait (Duration.ms (Int.max 1 ms))

let fixed_window ~n ~per_ms ~start =
  let window = ref 0 and used = ref 0 in
  let try_acquire ~now_ms =
    let index = Int.max 0 (now_ms - start) / per_ms in
    if index <> !window then (
      window := index;
      used := 0);
    if !used < n then (
      incr used;
      Granted)
    else wait (start + ((index + 1) * per_ms) - now_ms)
  in
  { try_acquire }

let sliding_window ~n ~per_ms =
  let starts = Queue.create () in
  let try_acquire ~now_ms =
    while (not (Queue.is_empty starts)) && now_ms - Queue.peek starts >= per_ms do
      ignore (Queue.take starts)
    done;
    if Queue.length starts < n then (
      Queue.add now_ms starts;
      Granted)
    else wait (Queue.peek starts + per_ms - now_ms)
  in
  { try_acquire }

let token_bucket ~capacity ~per_ms ~start =
  let tokens = ref capacity and refilled_at = ref start in
  let try_acquire ~now_ms =
    let gained = Int.max 0 (now_ms - !refilled_at) / per_ms in
    if gained > 0 then (
      tokens := Int.min capacity (!tokens + gained);
      refilled_at := if !tokens = capacity then now_ms else !refilled_at + (gained * per_ms));
    if !tokens > 0 then (
      decr tokens;
      Granted)
    else wait (!refilled_at + per_ms - now_ms)
  in
  { try_acquire }

let positive name n = if n < 1 then invalid_arg ("Rate_limiter.create: " ^ name ^ " < 1")

let period per =
  let ms = Duration.to_ms per in
  if ms < 1 then invalid_arg "Rate_limiter.create: per is zero" else ms

let make_algorithm config ~now_ms =
  match config with
  | Fixed_window { n; per } ->
      positive "n" n;
      fixed_window ~n ~per_ms:(period per) ~start:now_ms
  | Sliding_window { n; per } ->
      positive "n" n;
      sliding_window ~n ~per_ms:(period per)
  | Token_bucket { capacity; per } ->
      positive "capacity" capacity;
      token_bucket ~capacity ~per_ms:(period per) ~start:now_ms
  | Custom make -> make ~now_ms

let create ~sw ~clock config =
  Eio.Switch.check sw;
  (* ^safe-p9cw ^safe-8peq: the custom and built-in algorithms share local
     monotonic milliseconds, truncated only after exact nanosecond subtraction. *)
  let origin = Eio.Time.Mono.now clock in
  let now_ms () =
    Mtime.span origin (Eio.Time.Mono.now clock)
    |> Mtime.Span.to_uint64_ns
    |> fun ns -> Int64.to_int (Int64.unsigned_div ns 1_000_000L)
  in
  {
    algorithm = make_algorithm config ~now_ms:0;
    now_ms;
    sleep = (fun d -> Eio.Time.Mono.sleep clock (Duration.to_seconds d));
    lock = Eio.Mutex.create ();
  }

let acquire t =
  Eio.Mutex.use_rw ~protect:true t.lock (fun () ->
      t.algorithm.try_acquire ~now_ms:(t.now_ms ()))

let run t (f @ local) =
  let rec wait_for_permit () =
    match acquire t with
    | Granted -> ()
    | Wait delay ->
        t.sleep delay;
        wait_for_permit ()
  in
  wait_for_permit ();
  f ()

let run_or_drop t (f @ local) =
  match acquire t with Granted -> Some (f ()) | Wait _ -> None
