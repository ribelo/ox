(* ^safe-qmcw ^safe-t50j: existing complete-transfer seams, no production wrapper. *)
module Scripted_sink = struct
  type step = Count of int | Raise of exn
  type t = { output : Buffer.t; mutable steps : step list; mutable calls : int }

  let single_write t bufs =
    t.calls <- t.calls + 1;
    match t.steps with
    | [] -> failwith "bounded write script exhausted"
    | step :: rest -> (
        t.steps <- rest;
        match step with
        | Raise exn -> raise exn
        | Count limit ->
            let text = Cstruct.to_string (Cstruct.concat bufs) in
            let count = min limit (String.length text) in
            Buffer.add_substring t.output text 0 count;
            count)

  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
end

let with_flows actions f =
  Ox_test.run (fun _env sw ->
      let source = Eio_mock.Flow.make "short-io-source" in
      Eio.Switch.on_release sw (fun () -> Eio.Flow.close source);
      Eio_mock.Flow.on_read source actions;
      f source)

let sink steps =
  let state = Scripted_sink.{ output = Buffer.create 16; steps; calls = 0 } in
  (state, Eio.Resource.T (state, Eio.Flow.Pi.sink (module Scripted_sink)))

let same_exception expected f =
  match f () with
  | () -> failwith "expected unchanged exception"
  | exception actual -> if actual != expected then raise actual

let run () =
  let state, destination = sink Scripted_sink.[ Count 2; Count 1; Count 3 ] in
  Eio.Flow.write destination [ Cstruct.of_string "abc"; Cstruct.of_string "def" ];
  assert (Buffer.contents state.output = "abcdef");
  assert (state.calls = 3);
  with_flows
    [ `Return "a"; `Return "bc"; `Return "def"; `Raise End_of_file ]
    (fun source ->
      let buffer = Cstruct.create 6 in
      Eio.Flow.read_exact source buffer;
      assert (Cstruct.to_string buffer = "abcdef");
      match Eio.Flow.single_read source (Cstruct.create 1) with
      | _ -> failwith "expected EOF"
      | exception End_of_file -> ());
  with_flows
    [ `Return "ab"; `Raise End_of_file ]
    (fun source ->
      let buffer = Cstruct.create 4 in
      same_exception End_of_file (fun () -> Eio.Flow.read_exact source buffer);
      assert (Cstruct.to_string (Cstruct.sub buffer 0 2) = "ab"));
  with_flows
    [ `Return "a"; `Return "bc"; `Raise End_of_file ]
    (fun source ->
      let state, destination = sink Scripted_sink.[ Count 1; Count 1; Count 1 ] in
      Eio.Flow.copy source destination;
      assert (Buffer.contents state.output = "abc");
      assert (state.calls = 3));
  let error = Failure "transfer sentinel" in
  with_flows
    [ `Return "a"; `Raise error ]
    (fun source ->
      let buffer = Cstruct.create 3 in
      same_exception error (fun () -> Eio.Flow.read_exact source buffer));
  with_flows
    [ `Return "a"; `Raise error ]
    (fun source ->
      let state, destination = sink Scripted_sink.[ Count 1 ] in
      same_exception error (fun () -> Eio.Flow.copy source destination);
      assert (Buffer.contents state.output = "a"));
  let state, destination = sink Scripted_sink.[ Count 1; Raise error ] in
  same_exception error (fun () -> Eio.Flow.write destination [ Cstruct.of_string "abc" ]);
  assert (Buffer.contents state.output = "a");
  let os_error = Unix.Unix_error (Unix.ENOSPC, "write", "short-io fixture") in
  let state, destination = sink Scripted_sink.[ Count 1; Raise os_error ] in
  same_exception os_error (fun () ->
      Eio.Flow.write destination [ Cstruct.of_string "abc" ]);
  assert (Buffer.contents state.output = "a");
  (* A zero read violates the Eio provider contract; it is not EOF. *)
  with_flows
    [ `Return "" ]
    (fun source ->
      match Eio.Flow.read_exact source (Cstruct.create 1) with
      | () -> failwith "zero progress was mistaken for completion"
      | exception Assert_failure _ -> ());
  (* Eio's write seam retries zero. Bound the fault script: no claim of a zero guard. *)
  let state, destination = sink Scripted_sink.[ Count 0; Raise error ] in
  same_exception error (fun () -> Eio.Flow.write destination [ Cstruct.of_string "abc" ]);
  assert (state.calls = 2);
  assert (Buffer.contents state.output = "")

let () = run ()
