(* ^safe-9ved ^safe-r5ye ^safe-ohen ^safe-sr6e ^safe-eftp: one probe, not certification. *)
open Ocaml_common

let scan ~caps annotation source =
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let observations = ref [] in
  let record channel loc message =
    let a = loc.Location.loc_start and b = loc.loc_end in
    observations :=
      ( a.Lexing.pos_fname,
        a.pos_lnum,
        a.pos_cnum - a.pos_bol,
        b.pos_lnum,
        b.pos_cnum - b.pos_bol,
        channel,
        message )
      :: !observations
  in
  let visitor =
    Execution_context.check ~caps ~emit:(record "finding") ~undecided:(record "unknown")
  in
  (match artifact.info.cmt_annots with
  | Interface tree -> visitor.signature visitor tree
  | Implementation tree -> visitor.structure visitor tree
  | _ -> failwith "implementation or interface evidence required");
  (Option.value ~default:source artifact.info.cmt_sourcefile, !observations)

let expected file =
  let site line first last message =
    (file, line, first, line, last, "finding", message)
  in
  let native line first last entry origin =
    site line first last
      (Printf.sprintf
         "%s native callback at %s:%d: Eio.Fiber.yield requires an Eio fiber context"
         entry file origin)
  in
  let owner line first last name =
    site line first last ("Eio owner callback: " ^ name ^ " blocks the Eio owner thread")
  in
  [
    native 2 51 66 "Ox_blocking.run" 2;
    native 9 4 15 "Ox_blocking.run_result" 12;
    owner 15 43 54 "Unix.sleepf";
    owner 16 40 50 "Unix.sleep";
    owner 17 39 51 "Thread.delay";
    owner 18 51 77 "Stdlib.Semaphore.Counting.acquire";
  ]

let fixtures ~caps clean_i clean_is bad_i bad_is clean clean_s bad bad_s =
  List.iter
    (fun (a, s) ->
      let _, rows = scan ~caps a s in
      assert (rows = []))
    [ (clean_i, clean_is); (bad_i, bad_is); (clean, clean_s) ];
  let file, rows = scan ~caps bad bad_s in
  if List.sort compare rows <> List.sort compare (expected file) then
    failwith
      ("literal observation mismatch: "
      ^ String.concat " | "
          (List.map
             (fun (file, line, first, _, last, channel, message) ->
               Printf.sprintf "%s %s:%d:%d-%d %s" channel file line first last message)
             rows))

let owner_block () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let semaphore = Semaphore.Counting.make 0 in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Fiber.yield ();
              Semaphore.Counting.release semaphore);
          Semaphore.Counting.acquire semaphore))

let witness () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let bound =
            match Ox.Concurrency.of_int 1 with
            | Ok x -> x
            | Error _ -> failwith "literal bound"
          in
          let config : Ox_blocking.Pool.config =
            { max_threads = bound; max_queued = 1; shutdown_policy = Drain }
          in
          let pool = Ox_blocking.Pool.create ~sw config in
          (match Ox_blocking.run ~pool (fun () -> Eio.Fiber.yield ()) with
          | exception Effect.Unhandled _ -> ()
          | Error _ -> failwith "pool refusal is not native execution evidence"
          | Ok () -> failwith "native Eio yield unexpectedly succeeded");
          Ox_blocking.Pool.shutdown pool))

let main
    ~(caps :
       < Ox_caps.Cap.fs_read
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.stdout
       ; .. >) () =
  match Array.to_list Sys.argv with
  | [ _; "--fixtures"; ci; cis; bi; bis; c; cs; b; bs ] ->
      fixtures ~caps ci cis bi bis c cs b bs
  | [ _; "--owner-block" ] -> owner_block ()
  | [ _; "--witness" ] -> witness ()
  | _ :: pairs ->
      let rec loop = function
        | [] -> ()
        | annotation :: source :: rest ->
            let _, rows = scan ~caps annotation source in
            List.iter
              (fun (file, line, first, _, last, channel, message) ->
                Ox_caps.Cap_stdlib.printf ~caps "%s %s:%d:%d-%d %s\n" channel file line
                  first last message)
              rows;
            loop rest
        | _ -> failwith "usage: corpus [ANNOTATION SOURCE]..."
      in
      loop pairs
  | [] -> assert false

let () = main ~caps:(Ox_test.powerbox ()) ()
