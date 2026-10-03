module B = Playbook
module P = Protocol
module S = Ox_caps.Cap_sys
module F = Ox_caps.Cap_stdlib
module U = Ox_caps.Cap_unix

type caps =
  < Ox_caps.Cap.env ; Ox_caps.Cap.fs_read ; Ox_caps.Cap.fs_write ; Ox_caps.Cap.time >

type t = {
  caps : caps;
  config : Config.learning;
  warn : string -> unit;
  sw : Eio.Switch.t;
  locks : Eio.Mutex.t;
  sites : (string, Eio.Mutex.t) Hashtbl.t;
  pending_mu : Eio.Mutex.t;
  pending_done : Eio.Condition.t;
  mutable pending : int;
}

let create ~sw ~caps ~config ?(warn = fun _ -> ()) () =
  {
    caps :> caps;
    config;
    warn;
    sw;
    locks = Eio.Mutex.create ();
    sites = Hashtbl.create 8;
    pending_mu = Eio.Mutex.create ();
    pending_done = Eio.Condition.create ();
    pending = 0;
  }

let site_lock t site =
  Eio.Mutex.use_rw ~protect:true t.locks (fun () ->
      match Hashtbl.find_opt t.sites site with
      | Some lock -> lock
      | None ->
          let lock = Eio.Mutex.create () in
          Hashtbl.add t.sites site lock;
          lock)

let await_pending t =
  Eio.Mutex.use_rw ~protect:true t.pending_mu (fun () ->
      while t.pending > 0 do
        Eio.Condition.await t.pending_done t.pending_mu
      done)

let finish_pending t =
  Eio.Mutex.use_rw ~protect:true t.pending_mu (fun () ->
      t.pending <- t.pending - 1;
      if t.pending = 0 then Eio.Condition.broadcast t.pending_done)

let schedule t ~site work =
  Eio.Mutex.use_rw ~protect:true t.pending_mu (fun () -> t.pending <- t.pending + 1);
  match
    Eio.Fiber.fork ~sw:t.sw (fun () ->
        Fun.protect
          ~finally:(fun () -> finish_pending t)
          (fun () ->
            try Eio.Mutex.use_rw ~protect:true (site_lock t site) work with
            | Eio.Cancel.Cancelled _ as exn -> raise exn
            | exn -> t.warn (Printexc.to_string exn)))
  with
  | () -> ()
  | exception exn ->
      finish_pending t;
      raise exn

let config t = t.config
let ( let* ) = Result.bind

let get key = function
  | `Assoc fields -> Option.value ~default:`Null (List.assoc_opt key fields)
  | _ -> `Null

let protect f =
  try Ok (f ()) with
  | Sys_error why | Yojson.Json_error why -> Error why
  | Unix.Unix_error (code, fn, p) -> Error (fn ^ " " ^ p ^ ": " ^ Unix.error_message code)

let read t file =
  protect (fun () ->
      let ch = F.open_in_bin ~caps:t.caps file in
      Fun.protect ~finally:(fun () -> close_in ch) (fun () -> Yojson.Safe.from_channel ch))

let write t file json =
  let* () = Config.ensure_dir ~caps:t.caps (Filename.dirname file) in
  B.atomic_write_json ~caps:t.caps ~mode:0o600 file json

let root t = B.proposed_directory ~caps:t.caps ()
let state_file t = Filename.concat (Filename.dirname (root t)) "learning.json"
let state t = match read t (state_file t) with Ok (`Assoc fields) -> fields | _ -> []

let update t key value =
  let fields = state t in
  match
    write t (state_file t) (`Assoc ((key, value) :: List.remove_assoc key fields))
  with
  | Ok () -> ()
  | Error why -> t.warn why

let counter t key = match List.assoc_opt key (state t) with Some (`Int n) -> n | _ -> 0

let proposal_files t =
  match protect (fun () -> S.readdir ~caps:t.caps (root t)) with
  | Error _ -> []
  | Ok files ->
      Array.to_list files
      |> List.filter (fun name ->
          Filename.check_suffix name ".json"
          && not (Filename.check_suffix name ".provenance.json"))
      |> List.sort String.compare
      |> List.map (Filename.concat (root t))

type draft = {
  file : string;
  book : B.loaded;
  proc : B.procedure;
  provenance : B.provenance;
}

let proposals t =
  List.concat_map
    (fun file ->
      match read t file with
      | Error why ->
          t.warn why;
          []
      | Ok json -> (
          let book =
            match B.of_json ~file json with
            | Ok book -> Ok book
            | Error _ -> (
                let* proposal = B.proposal_of_yojson json in
                let* books = B.list ~caps:t.caps () in
                match
                  List.find_opt
                    (fun (b : B.loaded) -> b.playbook.site = proposal.site)
                    books
                with
                | None -> Error "procedure proposal has no installed book"
                | Some b ->
                    B.of_json ~file
                      (B.yojson_of_t
                         { b.playbook with procedures = [ proposal.procedure ] }))
          in
          match book with
          | Error why ->
              t.warn why;
              []
          | Ok book ->
              List.filter_map
                (fun (proc : B.procedure) ->
                  match
                    B.read_provenance ~caps:t.caps
                      (Filename.concat (Filename.dirname file)
                         (B.provenance_filename proc.slug))
                  with
                  | Ok (Some provenance) -> Some { file; book; proc; provenance }
                  | Ok None -> None
                  | Error why ->
                      t.warn why;
                      None)
                book.playbook.procedures))
    (proposal_files t)

let installed t =
  match B.list ~caps:t.caps () with
  | Ok books -> books
  | Error why ->
      t.warn why;
      []

let applicable entry kind = entry = "" || entry = "unknown" || kind = Some entry

let eligible t ~site ~kind d =
  d.book.playbook.site = site
  && d.provenance.tries < t.config.max_tries
  && applicable d.provenance.entry_kind kind

let candidates t ~site ~kind =
  let known = installed t |> List.filter (fun (b : B.loaded) -> b.playbook.site = site) in
  let known =
    List.concat_map
      (fun (b : B.loaded) ->
        List.filter_map
          (fun (p : B.procedure) ->
            let entry =
              match b.dir with
              | None -> ""
              | Some dir -> (
                  match
                    B.read_provenance ~caps:t.caps
                      (Filename.concat dir (B.provenance_filename p.slug))
                  with
                  | Ok (Some v) -> v.entry_kind
                  | _ -> "")
            in
            if applicable entry kind then Some (p, `Installed) else None)
          b.playbook.procedures)
      known
  in
  if t.config.mode = Config.Learning_mode.Off then known
  else
    known
    @ (proposals t
      |> List.filter_map (fun d ->
          if eligible t ~site ~kind d then
            Some (d.proc, `Draft (B.draft_revision d.book.playbook))
          else None))

let drafts t ~site ~kind =
  if t.config.mode = Config.Learning_mode.Off then []
  else
    proposals t
    |> List.filter_map (fun d ->
        if eligible t ~site ~kind d then
          Some
            B.
              {
                procedure = d.proc;
                pages = d.book.playbook.pages;
                scripts = d.book.scripts;
                revision = B.draft_revision d.book.playbook;
              }
        else None)

let books t known =
  if t.config.mode = Config.Learning_mode.Off then known
  else
    List.fold_left
      (fun known d ->
        if
          List.exists (fun (b : B.loaded) -> b.playbook.site = d.book.playbook.site) known
        then known
        else
          known @ [ { d.book with playbook = { d.book.playbook with procedures = [] } } ])
      known (proposals t)

let report t = function Ok _ -> () | Error why -> t.warn why

let generalize args text =
  let out = Buffer.create (String.length text) in
  let rec loop i =
    if i >= String.length text then Buffer.contents out
    else
      match
        List.find_opt
          (fun (_, value) ->
            i + String.length value <= String.length text
            && String.sub text i (String.length value) = value)
          args
      with
      | Some (name, value) ->
          Buffer.add_string out ("{" ^ name ^ "}");
          loop (i + String.length value)
      | None ->
          Buffer.add_char out text.[i];
          loop (i + 1)
  in
  loop 0

let record_legs t ~site ~mission ~args ~legs ~expect =
  if
    t.config.mode <> Config.Learning_mode.Off
    && site <> "unknown" && legs <> [] && expect <> []
  then
    schedule t ~site (fun () ->
        let args =
          List.filter (fun (name, value) -> name <> "" && value <> "") args
          |> List.sort (fun (_, a) (_, b) ->
              Int.compare (String.length b) (String.length a))
        in
        let generalize = generalize args in
        let legs = List.map generalize legs in
        let steps = List.map (fun goal -> B.Goal { goal; hint = None }) legs in
        let duplicate =
          List.exists
            (fun (b : B.loaded) ->
              b.playbook.site = site
              && List.exists
                   (fun (p : B.procedure) -> p.steps = steps)
                   b.playbook.procedures)
            (installed t)
          || List.exists
               (fun d -> d.book.playbook.site = site && d.proc.steps = steps)
               (proposals t)
        in
        if not duplicate then
          let slug =
            "legs-"
            ^ String.sub
                (Digest.to_hex (Digest.string (site ^ String.concat "\n" legs)))
                0 12
          in
          let proc =
            B.
              {
                slug;
                description = generalize mission;
                args =
                  Some
                    (List.map
                       (fun (name, _) ->
                         { name; source = From_mission { optional = false } })
                       args);
                steps;
                expect = List.map generalize expect;
                repeat = None;
              }
          in
          let book =
            B.
              {
                site;
                entry = "https://" ^ site ^ "/";
                description = "Pilot memory";
                pages = [];
                procedures = [ proc ];
                shapes = None;
                scripts = None;
              }
          in
          let provenance =
            B.
              {
                traces = [];
                model = "pilot";
                time = string_of_float (U.gettimeofday ~caps:t.caps ());
                tries = 0;
                last_failure = None;
                path = [];
                entry_kind = "";
                exit_kind = "";
                signature = [];
                kind_mapping = [];
                repeatable = not (B.non_repeatable_context mission);
                reason = "pilot legs";
                gate = "replay";
                repair = false;
                model_calls = 0;
                model_cost = Some 0.;
              }
          in
          report t (B.propose ~book ~provenance ~caps:t.caps ~site proc))

let after_mission t ~site ~used ~outcome ~verified =
  if t.config.mode <> Config.Learning_mode.Off then
    schedule t ~site (fun () ->
        List.iter
          (fun (slug, origin) ->
            match origin with
            | `Draft revision -> (
                match
                  List.find_opt
                    (fun d ->
                      d.book.playbook.site = site && d.proc.slug = slug
                      && B.draft_revision d.book.playbook = revision)
                    (proposals t)
                with
                | None -> ()
                | Some d ->
                    if outcome = `Done && verified then
                      match B.accept ~revision ~consume:true ~caps:t.caps d.file with
                      | Ok _ -> update t ("fail:" ^ site ^ ":" ^ slug) (`Int 0)
                      | Error why -> t.warn why
                    else
                      let tries = d.provenance.tries + 1 in
                      if tries >= t.config.max_tries then
                        report t (B.archive_proposal ~revision ~caps:t.caps d.file)
                      else
                        report t
                          (B.write_provenance ~caps:t.caps ~dir:(Filename.dirname d.file)
                             ~slug
                             {
                               d.provenance with
                               tries;
                               last_failure =
                                 Some "mission failed or expectations unverified";
                               repair = true;
                             }))
            | `Installed ->
                let key = "fail:" ^ site ^ ":" ^ slug in
                if outcome = `Done && verified then update t key (`Int 0)
                else
                  let failures = counter t key + 1 in
                  update t key (`Int failures);
                  if failures >= t.config.retire_after then
                    report t (B.retire ~caps:t.caps ~site ~slug)
                  else if
                    failures >= 2
                    && not
                         (List.exists
                            (fun d -> d.book.playbook.site = site && d.proc.slug = slug)
                            (proposals t))
                  then
                    List.iter
                      (fun (book : B.loaded) ->
                        if book.playbook.site = site then
                          List.iter
                            (fun (proc : B.procedure) ->
                              if proc.slug = slug then
                                let provenance =
                                  B.
                                    {
                                      traces = [];
                                      model = "pilot";
                                      time =
                                        string_of_float (U.gettimeofday ~caps:t.caps ());
                                      tries = 0;
                                      last_failure =
                                        Some "installed procedure failed twice";
                                      path = [];
                                      entry_kind = "";
                                      exit_kind = "";
                                      signature = [];
                                      kind_mapping = [];
                                      repeatable =
                                        B.procedure_repeatable book.playbook
                                          ~context:proc.description proc;
                                      reason = "pilot repair";
                                      gate = "replay";
                                      repair = true;
                                      model_calls = 0;
                                      model_cost = Some 0.;
                                    }
                                in
                                report t
                                  (B.propose ~book:book.playbook ~provenance ~caps:t.caps
                                     ~site proc))
                            book.playbook.procedures)
                      (installed t))
          (List.sort_uniq compare used))

let status t =
  `Assoc
    [
      ("mode", `String (Config.Learning_mode.to_string t.config.mode));
      ("pending", `Int (Eio.Mutex.use_ro t.pending_mu (fun () -> t.pending)));
      ("drafts", `Int (List.length (proposals t)));
    ]
