(* ^safe-9ved ^safe-ohen ^safe-r5ye: literal sites and full certainty/message multisets. *)
open Ocaml_common

let inspect_sites ?(transform = Fun.id) ~caps ~source annotation =
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let events = ref [] in
  let collect category loc message =
    let first = loc.Location.loc_start and last = loc.Location.loc_end in
    events :=
      ( category,
        first.Lexing.pos_fname,
        first.pos_lnum,
        first.pos_cnum - first.pos_bol,
        last.pos_lnum,
        last.pos_cnum - last.pos_bol,
        message )
      :: !events
  in
  let iterator =
    Fiber_blocking.check ~caps ~emit:(collect "finding") ~undecided:(collect "undecided")
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator (transform tree)
  | _ -> failwith "implementation evidence required");
  List.sort compare !events

let at category file line column last_line last_column entry origin reason =
  ( category,
    file,
    line,
    column,
    last_line,
    last_column,
    Printf.sprintf "%s Eio callback at %s:%d: %s" entry file origin reason )

let wait ?(entry = "Eio_main.run") file line column last_column origin callee =
  at "finding" file line column line last_column entry origin
    (callee
   ^ " synchronously waits on the scheduler domain; use Eio.Time.sleep with an explicit \
      clock, or Ox_blocking.run ~pool")

let unknown file line column last_line last_column origin reason =
  at "undecided" file line column last_line last_column "Eio_main.run" origin reason

(* All coordinates, caller origins, callees and reasons below are literal reviewed
   source obligations. No AST locations, findings or line counts build expectations. *)
let expected name =
  let file = "test/lint/safety_fiber_blocking/fixtures/" ^ name ^ ".ml" in
  match name with
  | "direct" -> [ wait file 2 36 47 2 "Unix.sleepf" ]
  | "hooks" ->
      [
        wait file 3 42 53 2 "Unix.sleepf";
        wait file 5 54 66 4 "Thread.delay";
        wait file 7 54 65 6 "Unix.sleepf";
      ]
  | "aliases" ->
      [
        wait file 4 19 23 5 "Unix.sleepf";
        wait file 6 41 51 6 "Unix.sleep";
        wait file 7 40 52 7 "Thread.delay";
        wait file 8 67 71 8 "Unix.sleepf";
        wait file 9 31 42 10 "Unix.sleepf";
        wait file 11 74 85 11 "Unix.sleepf";
        wait file 12 71 83 12 "Thread.delay";
        wait ~entry:"Ox_test.run" file 13 43 54 13 "Unix.sleepf";
        wait file 14 88 99 14 "Unix.sleepf";
      ]
  | "controls" -> []
  (* Ordinary unmodelled callbacks/methods are outside Rule C, not certified safe. *)
  | "unresolved" ->
      [
        unknown file 7 41 7 42 6
          "Unix.sleep: unresolved compound callee containing known wait";
      ]
  | "waits" ->
      [
        at "finding" file 2 46 2 57 "Eio_main.run" 2
          "Thread.join may synchronously wait on the scheduler domain; join outside the \
           Eio owner, or use Ox_blocking.run ~pool";
        at "finding" file 3 54 3 65 "Eio_main.run" 3
          "Domain.join may synchronously wait on the scheduler domain; join outside the \
           Eio owner, or use Ox_blocking.run ~pool";
        at "finding" file 4 85 4 94 "Eio_main.run" 4
          "Unix.read on a proven blocking descriptor may synchronously wait on the \
           scheduler domain; use Eio.Flow in the owner fiber, or Ox_blocking.run ~pool";
        at "finding" file 5 99 5 109 "Eio_main.run" 5
          "Unix.write on a proven blocking descriptor may synchronously wait on the \
           scheduler domain; use Eio.Flow in the owner fiber, or Ox_blocking.run ~pool";
        at "finding" file 7 127 7 136 "Eio_main.run" 7
          "Unix.read on a proven blocking descriptor may synchronously wait on the \
           scheduler domain; use Eio.Flow in the owner fiber, or Ox_blocking.run ~pool";
        unknown file 9 51 9 60 9
          "Unix.read: descriptor blocking mode is unresolved; audit its creation and \
           flag changes before claiming owner safety";
        unknown file 11 58 11 69 11
          "Unix.sleepf synchronously waits on the scheduler domain; use Eio.Time.sleep \
           with an explicit clock, or Ox_blocking.run ~pool; owner execution context \
           cannot be established for this candidate";
        unknown file 14 149 14 158 14
          "Unix.read: descriptor blocking mode is unresolved; audit its creation and \
           flag changes before claiming owner safety";
      ]
  | "native" ->
      List.map
        (fun (line, column, last_column) ->
          at "finding" file line column line last_column "Eio_main.run" line
            "Stdlib.Semaphore.Counting.acquire may synchronously wait on the scheduler \
             domain; use Eio.Semaphore.acquire in the owner fiber, or Ox_blocking.run \
             ~pool")
        [ (2, 48, 74); (6, 54, 61) ]
  | _ -> failwith "unknown literal oracle"

let same_multiset expected actual = List.sort compare expected = List.sort compare actual

let expect label expected actual =
  if not (same_multiset expected actual) then
    let describe (category, file, line, column, last_line, last_column, message) =
      Printf.sprintf "%s %s:%d:%d-%d:%d %s" category file line column last_line
        last_column message
    in
    failwith
      (Printf.sprintf
         "%s: exact site/category/message multiset mismatch; expected %d, got %d: %s"
         label (List.length expected) (List.length actual)
         (String.concat "; " (List.map describe actual)))

let check_oracle () =
  let event = List.hd (expected "direct") in
  let category, file, line, column, last_line, last_column, message = event in
  List.iter
    (fun forged ->
      if same_multiset [ event ] forged then
        failwith
          "safe-ohen: oracle accepted duplicate/wrong-site/wrong-certainty/wrong-message")
    [
      [ event; event ];
      [ (category, file ^ ".wrong", line, column, last_line, last_column, message) ];
      [ (category, file, line, column + 1, last_line, last_column, message) ];
      [ (category, file, line, column, last_line, last_column + 1, message) ];
      [ ("undecided", file, line, column, last_line, last_column, message) ];
      [ (category, file, line, column, last_line, last_column, message ^ " wrong") ];
    ];
  if not (same_multiset [ event; event ] [ event; event ]) then
    failwith "multiset multiplicity lost"

let poison_uid ~caps names tree =
  let target = Option.get (Paths.value ~caps names) in
  let _, foreign, _ =
    Env.lookup_value ~use:false ~loc:Location.none
      (Paths.lid ("Unix", [ "getpid" ]))
      (Lazy.force Env.initial)
  in
  let changed = ref false in
  let mapper =
    {
      Tast_mapper.default with
      expr =
        (fun self e ->
          let e = Tast_mapper.default.expr self e in
          match e.Typedtree.exp_desc with
          | Typedtree.Texp_ident id when Paths.is_value ~caps [ target ] e ->
              changed := true;
              {
                e with
                exp_desc =
                  Texp_ident { id with desc = { id.desc with val_uid = foreign.val_uid } };
              }
          | _ -> e);
    }
  in
  let tree = mapper.structure mapper tree in
  if not !changed then
    failwith "fake-UID counterexample did not alter an authentic callee";
  tree

let check_identity ~caps () =
  let file = "test/lint/safety_fiber_blocking/fixtures/direct.ml" in
  List.iter
    (fun (names, column, last_column, callee) ->
      expect
        ("safe-ohen fake UID " ^ callee)
        [
          ( "undecided",
            file,
            2,
            column,
            2,
            last_column,
            "unresolved callee identity for " ^ callee
            ^ ": declaration UID does not match imported compiler evidence" );
        ]
        (inspect_sites ~transform:(poison_uid ~caps names) ~caps
           ~source:"fixtures/direct.ml"
           "fixtures/.fiber_blocking_fixture.objs/byte/direct.cmt"))
    [
      (("Eio_main", [ "run" ]), 13, 25, "Eio_main.run");
      (("Unix", [ "sleepf" ]), 36, 47, "Unix.sleepf");
    ]

let check_native_identity ~caps () =
  let file = "test/lint/safety_fiber_blocking/fixtures/native.ml" in
  let message =
    "unresolved callee identity for Stdlib.Semaphore.Counting.acquire: declaration UID \
     does not match imported compiler evidence"
  in
  expect "safe-ohen genuine native callee UID cannot be substituted"
    [
      ("undecided", file, 2, 48, 2, 74, message);
      ("undecided", file, 3, 96, 3, 122, message);
      ("undecided", file, 5, 14, 5, 30, message);
      ("undecided", file, 8, 27, 8, 43, message);
    ]
    (inspect_sites
       ~transform:(poison_uid ~caps ("Stdlib", [ "Semaphore"; "Counting"; "acquire" ]))
       ~caps ~source:"fixtures/native.ml"
       "fixtures/.fiber_blocking_fixture.objs/byte/native.cmt")

let check_leased ~caps ~source annotation =
  let file = "leased.ml" in
  expect "safe-r5ye genuine leased owner/native"
    [
      wait file 4 104 116 4 "Thread.delay";
      wait file 5 106 116 5 "Unix.sleep";
      wait file 6 99 110 6 "Unix.sleepf";
      at "finding" file 12 57 12 83 "Eio_main.run" 12
        "Stdlib.Semaphore.Counting.acquire may synchronously wait on the scheduler \
         domain; use Eio.Semaphore.acquire in the owner fiber, or Ox_blocking.run ~pool";
      at "finding" file 13 118 13 144 "Eio_main.run" 13
        "Stdlib.Semaphore.Counting.acquire may synchronously wait on the scheduler \
         domain; use Eio.Semaphore.acquire in the owner fiber, or Ox_blocking.run ~pool";
    ]
    (inspect_sites ~caps ~source annotation)

let () =
  let caps = Ox_test.powerbox () in
  if Array.length Sys.argv = 3 then check_leased ~caps ~source:Sys.argv.(1) Sys.argv.(2)
  else (
    check_oracle ();
    List.iter
      (fun name ->
        expect name (expected name)
          (inspect_sites ~caps
             ~source:("fixtures/" ^ name ^ ".ml")
             ("fixtures/.fiber_blocking_fixture.objs/byte/" ^ name ^ ".cmt")))
      [ "direct"; "hooks"; "aliases"; "controls"; "unresolved"; "native"; "waits" ];
    check_identity ~caps ();
    check_native_identity ~caps ())
