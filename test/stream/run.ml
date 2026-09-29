(* Executable migration recipes, not an ox_stream compatibility library.
   The concrete PCM admission state belongs beside Pie's byte/capture budgets. *)

let ( let* ) = Result.bind

(* nstream-a7k2: the sink runs before the stop predicate, so its triggering
   value is included. Neither stop nor failure speculatively pulls again. *)
let rec receive ~pull ~stop ~step state =
  let* next = pull () in
  match next with
  | None -> Ok state
  | Some value ->
      let* state = step state value in
      let* done_ = stop value in
      if done_ then Ok state else receive ~pull ~stop ~step state

let test_seq () =
  let mapped = ref [] in
  let input =
    List.to_seq [ 1; 2; 3 ]
    |> Seq.map (fun n ->
        mapped := n :: !mapped;
        n * 2)
    |> Seq.filter (fun n -> n <> 4)
    |> Seq.flat_map (fun n -> Seq.append (Seq.return n) (Seq.return (n + 1)))
  in
  Alcotest.(check (list int)) "construction is lazy" [] !mapped;
  Alcotest.(check (list int)) "fixture operators" [ 2; 3; 6; 7 ] (List.of_seq input);
  Alcotest.(check (list int)) "once, in order" [ 3; 2; 1 ] !mapped

let test_receive () =
  let pulls = ref 0 in
  let events = ref [] in
  let pull () =
    incr pulls;
    Ok (Some !pulls)
  in
  let stop n =
    events := ("predicate", n) :: !events;
    Ok (n = 2)
  in
  let step acc n =
    events := ("sink", n) :: !events;
    Ok (acc + n)
  in
  Alcotest.(check (result int string))
    "inclusive terminal" (Ok 3) (receive ~pull ~stop ~step 0);
  Alcotest.(check int) "no third pull" 2 !pulls;
  Alcotest.(check (list (pair string int)))
    "sink before predicate"
    [ ("sink", 1); ("predicate", 1); ("sink", 2); ("predicate", 2) ]
    (List.rev !events);
  pulls := 0;
  Alcotest.(check (result int string))
    "callback error" (Error "sink")
    (receive ~pull
       ~stop:(fun _ -> Alcotest.fail "predicate after failed sink")
       ~step:(fun _ _ -> Error "sink")
       0);
  Alcotest.(check int) "error stops pulling" 1 !pulls;
  let not_called _ _ = Alcotest.fail "unexpected sink" in
  Alcotest.(check (result int string))
    "source error" (Error "source")
    (receive ~pull:(fun () -> Error "source") ~stop ~step:not_called 0);
  Alcotest.(check (result int string))
    "predicate error" (Error "predicate")
    (receive ~pull ~stop:(fun _ -> Error "predicate") ~step 0);
  Alcotest.(check (result int string))
    "clean EOF" (Ok 7)
    (receive ~pull:(fun () -> Ok None) ~stop ~step:not_called 7)

(* nstream-b4m8: Eio already supplies bounded FIFO delivery and cancellation. *)
let test_backpressure () =
  Eio_mock.Backend.run @@ fun () ->
  Eio.Switch.run @@ fun sw ->
  let q = Eio.Stream.create 1 in
  let attempting, set_attempting = Eio.Promise.create () in
  let finished, set_finished = Eio.Promise.create () in
  Eio.Stream.add q 1;
  Eio.Fiber.fork ~sw (fun () ->
      Eio.Promise.resolve set_attempting ();
      Eio.Stream.add q 2;
      Eio.Promise.resolve set_finished ());
  Eio.Promise.await attempting;
  Alcotest.(check bool) "second add is blocked" false (Eio.Promise.is_resolved finished);
  Alcotest.(check int) "bounded" 1 (Eio.Stream.length q);
  Alcotest.(check int) "FIFO first" 1 (Eio.Stream.take q);
  Eio.Promise.await finished;
  Alcotest.(check int) "FIFO second" 2 (Eio.Stream.take q)

let test_owner_cancellation () =
  Eio_mock.Backend.run @@ fun () ->
  let q = Eio.Stream.create 1 in
  let attempting, set_attempting = Eio.Promise.create () in
  let cleaned = ref false in
  Eio.Stream.add q 1;
  Eio.Fiber.first
    (fun () ->
      Eio.Switch.run @@ fun sw ->
      Eio.Switch.on_release sw (fun () -> cleaned := true);
      Eio.Promise.resolve set_attempting ();
      Eio.Stream.add q 2)
    (fun () -> Eio.Promise.await attempting);
  Alcotest.(check bool) "owner finalized blocked producer" true !cleaned;
  Alcotest.(check int) "cancelled add was not enqueued" 1 (Eio.Stream.length q);
  Alcotest.(check int) "original remains" 1 (Eio.Stream.take q);
  let waiting, set_waiting = Eio.Promise.create () in
  Eio.Fiber.first
    (fun () ->
      Eio.Promise.resolve set_waiting ();
      ignore (Eio.Stream.take q))
    (fun () -> Eio.Promise.await waiting);
  Eio.Stream.add q 3;
  Alcotest.(check int) "cancelled reader cannot steal" 3 (Eio.Stream.take q)

(* nstream-c9r3: a small, concrete audio-owner recipe. Queue state and byte
   accounting share one lock. No polymorphic channel, producer DSL or effects.
   Low-level locking deliberately avoids poisoning on a cancelled condition
   wait; mutations below never suspend and always leave consistent state. *)
type audio_error = [ `Full | `Closed | `Overload | `Disconnected ]
type admission = Accepting | Finished of (unit, audio_error) result

type recording = {
  pcm : string Queue.t;
  mutex : Eio.Mutex.t;
  changed : Eio.Condition.t;
  max_items : int;
  max_bytes : int;
  mutable bytes : int;
  mutable admission : admission;
}

let recording ~max_items ~max_bytes =
  {
    pcm = Queue.create ();
    mutex = Eio.Mutex.create ();
    changed = Eio.Condition.create ();
    max_items;
    max_bytes;
    bytes = 0;
    admission = Accepting;
  }

let locked t f =
  Eio.Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Eio.Mutex.unlock t.mutex) f

let offer_pcm t input =
  locked t @@ fun () ->
  match t.admission with
  | Finished (Ok ()) -> Error `Closed
  | Finished (Error e) -> Error e
  | Accepting ->
      let size = Bytes.length input in
      if Queue.length t.pcm >= t.max_items || size > t.max_bytes - t.bytes then
        Error `Full
      else (
        Queue.add (Bytes.to_string input) t.pcm;
        t.bytes <- t.bytes + size;
        Eio.Condition.broadcast t.changed;
        Ok ())

let finish t outcome =
  locked t @@ fun () ->
  match t.admission with
  | Finished _ -> ()
  | Accepting ->
      t.admission <- Finished outcome;
      Eio.Condition.broadcast t.changed

let read_pcm t =
  locked t @@ fun () ->
  let rec next () =
    match Queue.take_opt t.pcm with
    | Some pcm ->
        t.bytes <- t.bytes - String.length pcm;
        Ok (Some pcm)
    | None -> (
        match t.admission with
        | Finished (Ok ()) -> Ok None
        | Finished (Error e) -> Error e
        | Accepting ->
            Eio.Condition.await t.changed t.mutex;
            next ())
  in
  next ()

let error =
  Alcotest.of_pp (fun f -> function
    | `Full -> Format.pp_print_string f "Full"
    | `Closed -> Format.pp_print_string f "Closed"
    | `Overload -> Format.pp_print_string f "Overload"
    | `Disconnected -> Format.pp_print_string f "Disconnected")

let check_offer = Alcotest.check (Alcotest.result Alcotest.unit error)
let check_read = Alcotest.check (Alcotest.result (Alcotest.option Alcotest.string) error)

let test_audio_admission () =
  Eio_mock.Backend.run @@ fun () ->
  let t = recording ~max_items:2 ~max_bytes:3 in
  let input = Bytes.of_string "ab" in
  check_offer "accepted" (Ok ()) (offer_pcm t input);
  Bytes.set input 0 'z';
  check_offer "byte budget, not item count" (Error `Full) (offer_pcm t input);
  check_offer "remaining byte" (Ok ()) (offer_pcm t (Bytes.of_string "c"));
  check_offer "item budget" (Error `Full) (offer_pcm t Bytes.empty);
  finish t (Ok ());
  (* Full FIFO: closing cannot wait for a sentinel slot. *)
  finish t (Error `Disconnected);
  check_offer "first terminal wins" (Error `Closed) (offer_pcm t input);
  check_read "immutable snapshot" (Ok (Some "ab")) (read_pcm t);
  check_read "rejected item absent" (Ok (Some "c")) (read_pcm t);
  check_read "drained EOF" (Ok None) (read_pcm t);
  Alcotest.(check int) "accounting drained" 0 t.bytes;
  let t = recording ~max_items:1 ~max_bytes:3 in
  check_offer "fill" (Ok ()) (offer_pcm t input);
  check_offer "Pulse overflow" (Error `Full) (offer_pcm t input);
  finish t (Error `Overload);
  (* Pulse's caller fails/detaches on Full. *)
  finish t (Ok ());
  check_read "data before failure" (Ok (Some "zb")) (read_pcm t);
  check_read "typed failure, not EOF" (Error `Overload) (read_pcm t);
  check_read "sticky failure" (Error `Overload) (read_pcm t);
  check_offer "failed admission" (Error `Overload) (offer_pcm t input)

let test_audio_waits () =
  Eio_mock.Backend.run @@ fun () ->
  List.iter
    (fun outcome ->
      Eio.Switch.run @@ fun sw ->
      let t = recording ~max_items:1 ~max_bytes:3 in
      let waiting, set_waiting = Eio.Promise.create () in
      let result =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Promise.resolve set_waiting ();
            read_pcm t)
      in
      Eio.Promise.await waiting;
      finish t outcome;
      check_read "close wakes reader"
        (Result.map (fun () -> None) outcome)
        (Eio.Promise.await_exn result))
    [ Ok (); Error `Disconnected ];
  let t = recording ~max_items:1 ~max_bytes:3 in
  let waiting, set_waiting = Eio.Promise.create () in
  Eio.Fiber.first
    (fun () ->
      Eio.Promise.resolve set_waiting ();
      ignore (read_pcm t))
    (fun () -> Eio.Promise.await waiting);
  check_offer "cancelled wait unlocked" (Ok ()) (offer_pcm t (Bytes.of_string "x"));
  check_read "next reader still works" (Ok (Some "x")) (read_pcm t);
  check_offer "budget recovered" (Ok ()) (offer_pcm t (Bytes.of_string "yz"));
  check_read "subsequent delivery" (Ok (Some "yz")) (read_pcm t)

let () =
  Alcotest.run "stream migration (no package)"
    [
      ( "nstream-a7k2",
        [
          Alcotest.test_case "lazy Seq fixtures" `Quick test_seq;
          Alcotest.test_case "inclusive typed receive loop" `Quick test_receive;
        ] );
      ( "nstream-b4m8",
        [
          Alcotest.test_case "bounded Eio backpressure" `Quick test_backpressure;
          Alcotest.test_case "owner cancellation and cleanup" `Quick
            test_owner_cancellation;
        ] );
      ( "nstream-c9r3",
        [
          Alcotest.test_case "PCM admission and terminal outcome" `Quick
            test_audio_admission;
          Alcotest.test_case "close wakeup and cancelled waits" `Quick test_audio_waits;
        ] );
    ]
