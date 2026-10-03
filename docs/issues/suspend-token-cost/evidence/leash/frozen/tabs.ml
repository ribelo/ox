module P = Protocol

type caps =
  < Ox_caps.Cap.env ; Ox_caps.Cap.fs_read ; Ox_caps.Cap.fs_write ; Ox_caps.Cap.random >

type 'clock deps = {
  chrome : Chrome.t;
  clock : 'clock Eio.Time.clock;
  logger : Ox_observability.Logger.t;
  desktop : Desktop.t;
  caps : caps;
}

let obj fields = `Assoc fields
let str s = `String s
let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None
let text key json = match member key json with Some (`String s) -> Some s | _ -> None

let enum of_string value =
  match of_string value with Ok v -> v | Error _ -> assert false

let disposition name : P.Disposition.t = enum P.Disposition.of_string name

let error ?detail code message : P.error =
  P.make_error ?detail (enum P.Error_code.of_string code) ~message

let unavailable () = error "browser-unavailable" "Chrome is restarting; try again shortly"

let lost () =
  error "tab-gone" "the tab is gone"
    ~detail:
      (obj [ ("disposition", P.Disposition.yojson_of_t (disposition "browser_lost")) ])

let refusal () =
  error "url-refused" "only http(s) URLs without userinfo and about:blank are allowed"

let valid_url url =
  if url = "about:blank" then true
  else
    let scheme =
      if String.starts_with ~prefix:"https://" url then Some 8
      else if String.starts_with ~prefix:"http://" url then Some 7
      else None
    in
    match scheme with
    | None -> false
    | Some start ->
        let last =
          let rec scan i =
            if i = String.length url || String.contains "/?#" url.[i] then i
            else scan (i + 1)
          in
          scan start
        in
        last > start
        && (not (String.contains (String.sub url start (last - start)) '@'))
        && not (String.exists (fun c -> Char.code c <= 32 || Char.code c = 127) url)

(* chrome-qnul: [new] waits for a load exactly when it was asked for a document with one
   to come. [about:blank] is already the loaded document when the target exists, so there
   is no event left to await; [Control.budget] asks this same question, so the handler's
   budget and the registry's wait cannot drift apart. *)
let waits_for_load = function Some url -> url <> "about:blank" | None -> false

let handle ~caps =
  let bytes = Ox_caps.Cap_sys.urandom ~caps 16 in
  let hex = "0123456789abcdef" in
  let buf = Buffer.create 34 in
  Buffer.add_string buf "t_";
  String.iter
    (fun c ->
      let v = Char.code c in
      Buffer.add_char buf hex.[v lsr 4];
      Buffer.add_char buf hex.[v land 15])
    bytes;
  enum P.Handle.of_string (Buffer.contents buf)

(* hand-qos2 hand-fr87: the only access restriction is a human handoff. *)
type access = Act | Dialog | Close | Resume

let held_by_human () = error "with-human" "the tab is with the human; resume it first"
let nothing_waiting () = error "no-handoff" "there is no handoff to resume"

let authorize access ~with_human =
  match access with
  | Resume -> if with_human then Ok () else Error (nothing_waiting ())
  | Act | Dialog | Close -> if with_human then Error (held_by_human ()) else Ok ()

type idleness = {
  handle : P.Handle.t;
  origin : P.Origin.t;
  with_human : bool;
  idle_for_s : float;
}

type sweep_step = Close_idle | Keep_idle
type outcome = Resumed | Ended of P.error

(* hand-lz3p hand-r4t1: the record one live handoff leaves on its tab — the reason the
   human is shown, and the promise the blocked request awaits. [outcome] is written once,
   by whichever ending got there first, before the promise is resolved. *)
type waiting = {
  reason : string;
  promise : unit Eio.Promise.t;
  resolve : unit Eio.Promise.u;
  mutable outcome : outcome option;
}

type tab = {
  id : string;
  mutable session : string option;
      (** The page session Leash talks to the tab in: [Some] once Chrome attached — by
          auto-attach, or by {!page_session}'s own attach — and [None] for a target that
          is only discovered, which the first command that needs the page attaches
          (own-c0cl). *)
  mutable enabled_session : string option;
      (** The session the reading and action domains were enabled in; [None] until a
          command needs the page. *)
  mutable handle : P.Handle.t option;
  label : string option;
  opened_at : float;
  mutable url : string;
  mutable title : string;
  mutable origin : P.Origin.t;
  generation : int;
  lock : Eio.Mutex.t;
  mutable loading : bool;
  mutable navigated : bool;
  mutable completed : bool;
  mutable load_waiter : unit Eio.Promise.u option;
  mutable navigations : int;
      (** svc-hi4f: main-frame navigations observed on this tab. An action's watch reads
          it before its dispatch and again when the action is done, so it knows whether
          this action navigated the page. *)
  mutable page_loading : bool;
      (** A main-frame navigation is in flight — set by [Page.frameNavigated], cleared by
          the load event, whether or not a load wait is armed. *)
  mutable page_loads : unit Eio.Promise.u list;
      (** The action watches waiting for that load to finish; resolved once, when it does,
          like the waiter of {!with_load_wait}. *)
  mutable snapshot : (P.Snapshot_id.t * string * (P.row * int) list) option;
  mutable dom_snapshot : bool;
  mutable baselines : (P.Snapshot_id.t * Reading.page_state) list;
      (** The page's loader id and mutation guard as each of the last few snapshots saw
          them, newest first (hard-sckn). Unlike [snapshot] this survives a navigation. *)
  mutable dialog : P.dialog option;
  mutable dialog_listeners : (P.dialog -> unit) list;
  mutable main_frame : string option;
  mutable downloads : P.download_info list;
  mutable counter_installed : bool;
  mutable same_document : int;
      (** Main-frame [Page.navigatedWithinDocument] events. A post-action settle compares
          this with the count it saw at dispatch, so a [history.pushState] is a transition
          even though it is not a cross-document navigation. *)
  mutable net_seq : int;  (** Monotonic id of [Network.requestWillBeSent] on this tab. *)
  mutable armed_net : int;
  mutable armed_doc : int;
      (** [net_seq] and [same_document] just before an input dispatch. Settle treats a
          request or same-document navigation after these as caused by that action, even
          if the event is processed before settle starts. *)
  inflight : (string, int) Hashtbl.t;
      (** Request id to the [net_seq] that started it, while the request is in flight. *)
  mutable focus_holders : int;
      (** The agent operations running on this tab with focus emulation on (tab-8la3,
          chrome-9ex7): emulation is on exactly while this is positive. *)
  mutable opener : string option;
      (** The target id of the tab that opened this one, Chrome's [openerId]. *)
  mutable close_on_resume : bool;  (** map-puhi: only a drive-owned tab. *)
  mutable settlements : (Dispatch.outcome -> unit) list;
      (** The dispatches currently waiting on an acknowledgement (tab-0ohq tab-gjo0): a
          trusted input's reply or an [eval]'s may never come because its handler opened a
          popup, so the registry wakes them when the popup's target appears or when this
          tab's target dies. Empty between dispatches. *)
  reading : Reading.t;
}

let baselines_kept = 8

type tomb = { disposition : P.Disposition.t; at : float }

let key handle = P.Handle.to_string handle
let credential (tab : tab) = Option.get tab.handle

let ledger_key (tab : tab) =
  match tab.handle with Some h -> key h | None -> "human:" ^ tab.id

module Keys = Map.Make (String)

type entry = {
  tab : tab;
  with_human : bool;
  last_activity : float;
  handoff : waiting option;
}

(* The registry's whole bookkeeping as one immutable value: every live tab, the target ids
   that name them, the tombstones of the tabs that left, the targets Chrome reported while
   Leash was creating one of its own (own-6ndc), and how many creations are in flight.
   Nothing else writes any of it (^nactor-8z1n). *)
type ledger = {
  entries : entry Keys.t;
  targets : string Keys.t;  (** target id to handle key *)
  tombs : tomb Keys.t;
  pending : (string option * Discovery.target) Keys.t;
  creating : int;
}

let empty_ledger =
  {
    entries = Keys.empty;
    targets = Keys.empty;
    tombs = Keys.empty;
    pending = Keys.empty;
    creating = 0;
  }

(* Everything that changes the ledger is one of these, handled one at a time in arrival
   order by the actor, so no transition can interleave with another. *)
type request =
  | Locate of { access : access; handle : P.Handle.t; at : float }
  | Take of { id : string; at : float }
  | Hand_over of { reason : string; handle : P.Handle.t; at : float }
  | Hand_over_held of { reason : string; handle : P.Handle.t; at : float }
  | Resume of { handle : P.Handle.t; at : float }
  | Restore of { handle : P.Handle.t; waiting : waiting; at : float }
  | Touch of { handle : P.Handle.t; at : float }
  | Register of {
      id : string;
      session : string option;
      origin : P.Origin.t;
      label : string option;
      url : string;
      title : string;
      opener : string option;
      at : float;
    }
  | Disappear of { key : string; disposition : P.Disposition.t; at : float }
  | Creating of { delta : int; at : float }
  | Discover of { session : string option; info : Discovery.target; at : float }

type answer =
  | Entry of entry
  | Known of entry  (** a report about a tab the ledger already had *)
  | Adopted of (entry * tab option) list
      (** tabs registered from Chrome's reports, each with the tab that opened it *)
  | Gone of entry  (** the entry that left *)
  | Nothing

type t = {
  chrome : Chrome.t;
  caps : caps;
      (** ^ncaps-4tjy: handles from the system's randomness; screenshots, [run --out] and
          proposals written, uploads and playbooks read, the XDG directories looked up. *)
  now : unit -> float;
  sleep : float -> unit;
  await_load : unit Eio.Promise.t -> (unit, [ `Timeout ]) result;
  await_handoff : Ox.Duration.t -> unit Eio.Promise.t -> (unit, [ `Timeout ]) result;
  desktop : Desktop.t;
  notify : string -> (unit, string) result;
  handoff_timeout_s : int;
  challenge_attempt : bool;
  challenge_turns : int;
  logger : Ox_observability.Logger.t;
  download_dir : string option;
  downloads_by_guid : (string, string) Hashtbl.t;
  cap : int;
  tombstone_s : int;
  idle : float;
  started : float;
  ledger :
    ( ledger,
      request,
      answer,
      [ `Refused of P.error | `Actor_stopped | `Timeout ] )
    Ox.Actor.t;
      (** The registry's bookkeeping, owned by one fiber (^nactor-8z1n). Reads that need
          no ordering — [list], [status], the event fiber's routing — take
          {!Ox.Actor.state} and never queue behind a transition. *)
  mutable stopping : bool;
}

let now t = t.now ()

(* The ledger as of now, without a message (^nactor-l87k). *)
let snapshot t = Ox.Actor.state t.ledger
let live_entries t = Keys.fold (fun _ entry acc -> entry :: acc) (snapshot t).entries []
let live_tabs t = List.map (fun entry -> entry.tab) (live_entries t)
let open_tabs t = Keys.cardinal (snapshot t).entries
let iter_tabs t f = List.iter f (live_tabs t)

let closes_in_s t (entry : entry) =
  if entry.with_human || P.Origin.to_string entry.tab.origin <> "agent" then None
  else Some (max 0 (int_of_float (Float.ceil (t.idle -. (now t -. entry.last_activity)))))

let settle (waiting : waiting) outcome =
  if waiting.outcome = None then waiting.outcome <- Some outcome;
  Eio.Promise.resolve waiting.resolve ()

(* ---------- The ledger's fold ---------- *)

let refused error = Error (`Refused error)
let refuse = function Ok _ as ok -> ok | Error error -> refused error

let with_entry ledger entry =
  { ledger with entries = Keys.add (ledger_key entry.tab) entry ledger.entries }

(* A tombstone outlives the tab for [tombstone_s]; older ones are dropped whenever the
   ledger next changes shape, and are already answered as unknown before that. *)
let prune ~tombstone_s ~at ledger =
  {
    ledger with
    tombs = Keys.filter (fun _ tomb -> at -. tomb.at < float tombstone_s) ledger.tombs;
  }

(* own-0pnk: the one gate every tab command passes through. The decision is the pure
   [authorize]; this is the only place that also records a forced override, with the
   command, the caller, the tab and the state it overrode. *)
let refusal_for_gone ~tombstone_s ledger ~at handle =
  match Keys.find_opt (key handle) ledger.tombs with
  | Some tomb when at -. tomb.at < float tombstone_s -> P.tab_gone tomb.disposition
  | _ -> error "unknown-tab" "unknown tab handle"

let authorized ~tombstone_s ledger ~(access : access) ~at handle =
  match Keys.find_opt (key handle) ledger.entries with
  | Some entry when entry.tab.handle = Some handle ->
      Result.map
        (fun () -> if access = Resume then entry else { entry with last_activity = at })
        (authorize access ~with_human:entry.with_human)
  | _ -> Error (refusal_for_gone ~tombstone_s ledger ~at handle)

let handed_over entry ~reason =
  let promise, resolve = Eio.Promise.create () in
  {
    entry with
    with_human = true;
    handoff = Some { reason; promise; resolve; outcome = None };
  }

let register_entry ~tombstone_s ~at ledger tab =
  let k = ledger_key tab in
  let entry = { tab; with_human = false; last_activity = at; handoff = None } in
  let ledger =
    {
      ledger with
      entries = Keys.add k entry ledger.entries;
      targets = Keys.add tab.id k ledger.targets;
    }
  in
  (prune ~tombstone_s ~at ledger, entry)

let new_record ~fresh ~generation ~at ~id ~session ~origin ~label ~url ~title ~opener =
  {
    id;
    session;
    enabled_session = None;
    handle = (if P.Origin.to_string origin = "agent" then Some (fresh ()) else None);
    label;
    opened_at = at;
    url;
    title;
    origin;
    generation;
    lock = Eio.Mutex.create ();
    loading = false;
    navigated = false;
    completed = false;
    load_waiter = None;
    navigations = 0;
    page_loading = false;
    page_loads = [];
    snapshot = None;
    dom_snapshot = false;
    baselines = [];
    dialog = None;
    dialog_listeners = [];
    main_frame = None;
    downloads = [];
    counter_installed = false;
    same_document = 0;
    net_seq = 0;
    armed_net = 0;
    armed_doc = 0;
    inflight = Hashtbl.create 8;
    focus_holders = 0;
    opener;
    close_on_resume = false;
    settlements = [];
    reading = Reading.create ();
  }

let adopt ~fresh ~tombstone_s ~generation ~at ledger ~id ~session
    (info : Discovery.target) =
  let opener_entry =
    Option.bind info.opener (fun opener ->
        Option.bind (Keys.find_opt opener ledger.targets) (fun k ->
            Keys.find_opt k ledger.entries))
  in
  let tab =
    new_record ~fresh ~generation ~at ~id ~session
      ~origin:(enum P.Origin.of_string "human")
      ~label:None
      ~url:(Option.value ~default:"about:blank" info.url)
      ~title:(Option.value ~default:"" info.title)
      ~opener:info.opener
  in
  let ledger, entry = register_entry ~tombstone_s ~at ledger tab in
  (ledger, (entry, Option.map (fun opener -> opener.tab) opener_entry))

(* Targets Chrome reported while Leash was creating one of its own: the tab it created —
   which createTarget's reply has registered by now — and anything else that appeared in
   that window, a human's tab included. *)
let flush_pending ~fresh ~tombstone_s ~generation ~at ledger =
  let ledger, adopted =
    Keys.fold
      (fun id (session, info) (ledger, adopted) ->
        if Keys.mem id ledger.targets then (ledger, adopted)
        else
          let ledger, one =
            adopt ~fresh ~tombstone_s ~generation ~at ledger ~id ~session info
          in
          (ledger, one :: adopted))
      ledger.pending (ledger, [])
  in
  ({ ledger with pending = Keys.empty }, List.rev adopted)

(* The whole behaviour of the registry's actor: one request against the current ledger,
   answered with the next ledger and what the caller needs. A refusal is an [Error] and
   leaves the ledger as it was (^nactor-7qi7). It never suspends. *)
let fold ~fresh ~logger ~tombstone_s ~generation ledger request =
  let authorized = authorized ~tombstone_s ledger in
  match request with
  | Locate { access; handle; at } -> (
      match authorized ~access ~at handle with
      | Error e -> refused e
      | Ok entry -> Ok (with_entry ledger entry, Entry entry))
  | Take { id; at } -> (
      match Keys.find_opt id ledger.targets with
      | None -> refused (error "no-match" "the tab disappeared before take")
      | Some old -> (
          match Keys.find_opt old ledger.entries with
          | None -> refused (error "no-match" "the tab disappeared before take")
          | Some entry when entry.with_human -> refused (held_by_human ())
          | Some entry when entry.tab.handle <> None ->
              refused
                (error "taken"
                   "the tab already has a live handle; ask the holder for the handle")
          | Some entry ->
              let h = fresh () in
              entry.tab.handle <- Some h;
              entry.tab.origin <- enum P.Origin.of_string "agent";
              let entry = { entry with last_activity = at } in
              let ledger =
                {
                  ledger with
                  entries = Keys.remove old ledger.entries;
                  targets = Keys.add id (key h) ledger.targets;
                }
              in
              Ox_observability.Logger.info logger
                ~fields:
                  [
                    ("at", Ox_observability.Logger.Float at);
                  ]
                "tab taken";
              Ok (with_entry ledger entry, Entry entry)))
  | Hand_over { reason; handle; at } | Hand_over_held { reason; handle; at } -> (
      match authorized ~access:Act ~at handle with
      | Error e -> refused e
      | Ok entry ->
          let entry = handed_over entry ~reason in
          Ok (with_entry ledger entry, Entry entry))
  | Resume { handle; at } -> (
      match authorized ~access:Resume ~at handle with
      | Error e -> refused e
      | Ok entry -> (
          match entry.handoff with
          | None -> refused (nothing_waiting ())
          | Some waiting ->
              let entry =
                { entry with with_human = false; handoff = None; last_activity = at }
              in
              settle waiting Resumed;
              Ok (with_entry ledger entry, Entry entry)))
  | Restore { handle; waiting; at } -> (
      match Keys.find_opt (key handle) ledger.entries with
      | Some ({ handoff = Some current; _ } as entry) when current == waiting ->
          Ok
            ( with_entry ledger
                { entry with handoff = None; with_human = false; last_activity = at },
              Nothing )
      | _ -> Ok (ledger, Nothing))
  | Touch { handle; at } -> (
      match authorized ~access:Act ~at handle with
      | Ok entry -> Ok (with_entry ledger entry, Entry entry)
      | Error _ -> Ok (ledger, Nothing))
  | Register { id; session; origin; label; url; title; opener; at } ->
      let tab =
        new_record ~fresh ~generation:(generation ()) ~at ~id ~session ~origin ~label ~url
          ~title ~opener
      in
      let ledger, entry = register_entry ~tombstone_s ~at ledger tab in
      Ok (ledger, Entry entry)
  | Disappear { key = k; disposition; at } -> (
      match Keys.find_opt k ledger.entries with
      | None -> Ok (ledger, Nothing)
      | Some entry ->
          Option.iter (fun w -> settle w (Ended (P.tab_gone disposition))) entry.handoff;
          let tombs =
            match entry.tab.handle with
            | None -> ledger.tombs
            | Some h -> Keys.add (key h) { disposition; at } ledger.tombs
          in
          let ledger =
            {
              ledger with
              entries = Keys.remove k ledger.entries;
              targets = Keys.remove entry.tab.id ledger.targets;
              tombs;
            }
          in
          Ok (prune ~tombstone_s ~at ledger, Gone entry))
  | Creating { delta; at } ->
      let ledger = { ledger with creating = max 0 (ledger.creating + delta) } in
      if ledger.creating > 0 then Ok (ledger, Nothing)
      else
        let ledger, adopted =
          flush_pending ~fresh ~tombstone_s ~generation:(generation ()) ~at ledger
        in
        Ok (ledger, Adopted adopted)
  | Discover { session; info; at } -> (
      match Keys.find_opt info.id ledger.targets with
      | Some k -> (
          match Keys.find_opt k ledger.entries with
          | Some entry -> Ok (ledger, Known entry)
          | None -> Ok (ledger, Nothing))
      | None ->
          if ledger.creating > 0 then
            Ok
              ( { ledger with pending = Keys.add info.id (session, info) ledger.pending },
                Nothing )
          else
            let ledger, adopted =
              adopt ~fresh ~tombstone_s ~generation:(generation ()) ~at ledger ~id:info.id
                ~session info
            in
            Ok (ledger, Adopted [ adopted ]))

(* The ledger's own arguments never need a clock of their own: every request that reads
   time carries the caller's [at]. *)
let entry_of_answer = function
  | Entry entry | Known entry | Gone entry -> entry
  | _ -> assert false

(* One request, answered. The actor's fold never suspends, so the wait is as short as the
   mailbox. A caller cancelled while it waits leaves its request applied and unanswered;
   the ones that must not be left half-done — a tab leaving, a creation ending — ask
   through {!call_protected}. *)
let call t request =
  match Ox.Actor.ask t.ledger request with
  | Ok answer -> Ok answer
  | Error (`Refused error) -> Error error
  | Error _ -> Error (error "internal" "the tab registry has stopped")

let call_protected t request = Eio.Cancel.protect (fun () -> call t request)
let transition t request = Result.map entry_of_answer (call t request)

(* kind-tdrv kind-4qke: list and snap name the page. An installed playbook's kind
   wins; otherwise the URL and title are inferred. Text markers need page text, which
   list and snap do not read, so a marker-only kind stays inferred here. *)
let installed_books t =
  match Playbook.list ~caps:t.caps () with Ok books -> books | Error _ -> []

let page_label ~books ~url ~title =
  if not (Page_kind.is_page ~url) then None
  else
    match
      List.find_map
        (fun (book : Playbook.loaded) ->
          Playbook.page_kind book.playbook.pages ~url ~text:"")
        books
    with
    | Some name -> Some P.{ name; source = Declared }
    | None ->
        let inferred = Page_kind.infer ~url ~title in
        Some P.{ name = inferred.name; source = Inferred }

let listing_of t ?(books = installed_books t) (entry : entry) : P.tab_listing =
  {
    label = entry.tab.label;
    url = entry.tab.url;
    title = entry.tab.title;
    page_kind = page_label ~books ~url:entry.tab.url ~title:entry.tab.title;
    origin = entry.tab.origin;
    age_s = max 0 (int_of_float (now t -. entry.tab.opened_at));
    idle_s = max 0 (int_of_float (now t -. entry.last_activity));
    closes_in_s = closes_in_s t entry;
    with_human = entry.with_human;
    reason = Option.map (fun (w : waiting) -> w.reason) entry.handoff;
  }

let info_of t (entry : entry) : P.tab_info =
  let i = listing_of t entry in
  {
    tab = credential entry.tab;
    label = i.label;
    url = i.url;
    title = i.title;
    page_kind = i.page_kind;
    origin = i.origin;
    age_s = i.age_s;
    idle_s = i.idle_s;
    closes_in_s = i.closes_in_s;
    with_human = i.with_human;
    reason = i.reason;
    generation = entry.tab.generation;
    dialog = entry.tab.dialog;
    loaded = None;
  }

let entry_of t (tab : tab) : entry =
  match Keys.find_opt (ledger_key tab) (snapshot t).entries with
  | Some entry -> entry
  | None -> { tab; with_human = false; last_activity = now t; handoff = None }

let info t tab = info_of t (entry_of t tab)
let locate_entry t ~access handle = transition t (Locate { access; handle; at = now t })
let locate t ~access handle = Result.map (fun e -> e.tab) (locate_entry t ~access handle)

let peek t ~access handle =
  Result.map
    (fun e -> e.tab)
    (authorized ~tombstone_s:t.tombstone_s (snapshot t) ~access ~at:(now t) handle)

let tab_of_target t id =
  let ledger = snapshot t in
  Option.bind (Keys.find_opt id ledger.targets) (fun k ->
      Option.map (fun entry -> entry.tab) (Keys.find_opt k ledger.entries))

(* A tab leaves the ledger, and whatever waited on its load is woken. *)
let disappear t (tab : tab) disposition =
  ignore (call_protected t (Disappear { key = ledger_key tab; disposition; at = now t }));
  match tab.load_waiter with
  | None -> ()
  | Some waiter ->
      tab.load_waiter <- None;
      Eio.Promise.resolve waiter ()

let cdp_call ?(deadline = Ox.Duration.seconds 30) ?session cdp meth params =
  match Cdp.call cdp ?session ~deadline meth params with
  | Error `Timeout ->
      let code =
        match session with None -> "timeout" | Some _ -> "renderer-unresponsive"
      in
      Error (error code "browser operation timed out")
  | Error _ -> Error (unavailable ())
  | Ok reply -> (
      match Cdp.error_of_reply reply with
      | Some (_, message)
        when meth = "Runtime.callFunctionOn"
             && String.starts_with ~prefix:"SyntaxError" message ->
          (* hdoc-vqj7: a malformed caller function is not a service defect. *)
          Error (error "script-failed" message)
      | Some _ -> Error (error "internal" ("browser refused " ^ meth))
      | None -> (
          match Cdp.result reply with
          | Some result -> Ok result
          | None -> Error (error "internal" ("browser omitted " ^ meth ^ " result"))))

(* field-cde7: diagnosis is local to this tab and reads the ring without asking
   the stuck renderer for anything. Do not change transport/browser deadlines. *)
let diagnose tab (failure : P.error) =
  if P.Error_code.to_string failure.code <> "renderer-unresponsive" then failure
  else
    let entries =
      match
        Reading.debug tab.reading
          { P.tab = credential tab; limit = Some 20; clear = None }
      with
      | Ok debug -> debug.entries
      | Error _ -> []
    in
    {
      failure with
      P.detail =
        Some
          (obj
             [
               ("tab", P.Handle.yojson_of_t (credential tab));
               ("url", str tab.url);
               ("title", str tab.title);
               ("entries", `List (List.map P.yojson_of_debug_entry entries));
             ]);
    }

let session_call cdp tab session meth params =
  cdp_call ~session cdp meth params |> Result.map_error (diagnose tab)

let ready t =
  match Chrome.connection t.chrome with
  | Ok cdp -> Ok cdp
  | Error _ -> Error (unavailable ())

(* own-6ndc: a tab Leash created, or one Chrome reported, enters the ledger here. *)
let register t ~id ~session ~origin ~label ~url ~title ?opener () =
  transition t (Register { id; session; origin; label; url; title; opener; at = now t })

let ( let* ) = Result.bind

let dialog_race (tab : tab) : Dialog_race.t =
  {
    current = (fun () -> tab.dialog);
    subscribe =
      (fun notify ->
        tab.dialog_listeners <- notify :: tab.dialog_listeners;
        fun () ->
          tab.dialog_listeners <-
            List.filter (fun listener -> listener != notify) tab.dialog_listeners);
  }

(* hard-yi0a: CDP calls under a tab lock must remain cancellable by the listener
   budget. Eio.Mutex.use_rw ~protect:true masks cancellation for the entire handler;
   ~protect:false poisons the lock on cancellation. Each mutating operation leaves
   its registry fields consistent at yield points, so unlock in a finally instead.
   Synchronous bookkeeping-only sections still use protected use_rw below. *)
let with_tab_lock tab fn =
  Eio.Mutex.lock tab.lock;
  Fun.protect ~finally:(fun () -> Eio.Mutex.unlock tab.lock) fn

let acknowledge (tab : tab) : Dispatch.t =
  let pending, resolve = Dispatch.make () in
  tab.settlements <- resolve :: tab.settlements;
  {
    pending with
    release =
      (fun () ->
        tab.settlements <- List.filter (fun waiter -> waiter != resolve) tab.settlements);
  }

let wake (tab : tab) outcome =
  let waiters = tab.settlements in
  tab.settlements <- [];
  List.iter (fun resolve -> resolve outcome) waiters

(* tab-bw4j: the domains a page session needs for observation, action-time
   revalidation, and the debug ring. None of them is visible to the page (chrome-9ex7);
   focus emulation is, so it is not here but in {!with_focus}. They are asked for once per session,
   when Leash first uses that session: the discovery path itself only records the session,
   so a target Chrome reports is registered without waiting on the browser (own-c0cl), and
   a tab nobody acts on costs nothing. Best effort: a domain the browser refuses is
   ignored, and the command that needed it reports its own failure. *)
let use_session t cdp tab session =
  tab.session <- Some session;
  if tab.enabled_session <> Some session then (
    tab.enabled_session <- Some session;
    let enable meth params = ignore (session_call cdp tab session meth params) in
    enable "Page.enable" (obj []);
    enable "Runtime.enable" (obj []);
    enable "Network.enable" (obj []);
    enable "DOM.enable" (obj []))

let page_session t cdp tab =
  match tab.session with
  | Some session ->
      use_session t cdp tab session;
      Ok session
  | None -> (
      let* reply =
        cdp_call cdp "Target.attachToTarget"
          (obj [ ("targetId", str tab.id); ("flatten", `Bool true) ])
      in
      match text "sessionId" reply with
      | None -> Error (error "internal" "browser omitted sessionId")
      | Some session ->
          use_session t cdp tab session;
          Ok session)

(* tab-8la3 chrome-9ex7: Chrome's focus emulation makes a page behave as focused and
   visible — a background tab keeps rendering and animating, and takes focus events — and
   the page can see it (document.hasFocus(), visibilityState). So it is on only while an
   agent operation is working on the page: [f] gets [engage], which the operation calls
   once its request is valid and it is about to read or act on the page (a refused
   request, or a read a dialog blocks, never touches the browser). Operations on one tab
   share one enable: the first engaged turns it on, the last out turns it off, after the
   operation has its result. Otherwise document.hasFocus() and visibilityState answer
   what the operator's own Chrome would. Best effort both ways; the disable is bounded and
   survives cancellation of the operation. *)
let focus_emulation cdp session enabled =
  ignore
    (cdp_call ~deadline:(Ox.Duration.seconds 2) ~session cdp
       "Emulation.setFocusEmulationEnabled"
       (obj [ ("enabled", `Bool enabled) ]))

let with_focus t tab f =
  let engaged = ref None in
  let engage () =
    match (!engaged, tab.dialog, ready t, tab.session) with
    | None, None, Ok cdp, Some session ->
        engaged := Some (cdp, session);
        tab.focus_holders <- tab.focus_holders + 1;
        if tab.focus_holders = 1 then focus_emulation cdp session true
    | _ -> ()
  in
  Fun.protect
    ~finally:(fun () ->
      match !engaged with
      | None -> ()
      | Some (cdp, session) ->
          tab.focus_holders <- tab.focus_holders - 1;
          if tab.focus_holders = 0 then
            Eio.Cancel.protect (fun () -> focus_emulation cdp session false))
    (fun () -> f engage)

(* tab-0ohq tab-gjo0: the first report Chrome makes about a target is the acknowledgement
   of the dispatch that opened it -- [Target.targetCreated], or the attachment or the info
   change that carries the opener first when the announcement was missed -- and the tab is
   registered before its opener's waiters are woken, so the action that settles already
   sees the popup in [popups] (tab-tm6c tab-8k2g). *)
let wake_openers adopted =
  List.iter
    (fun (_, opener) ->
      Option.iter (fun opener_tab -> wake opener_tab Dispatch.Popup) opener)
    adopted

let adopted_of = function Adopted adopted -> adopted | _ -> []

let discover t ~session (info : Discovery.target) =
  match call t (Discover { session; info; at = now t }) with
  | Error _ -> ()
  | Ok (Known { tab; _ }) ->
      (match (tab.session, session) with
      | None, Some session -> tab.session <- Some session
      | _ -> ());
      Option.iter (fun url -> tab.url <- url) info.url;
      Option.iter (fun title -> tab.title <- title) info.title;
      Option.iter (fun opener -> tab.opener <- Some opener) info.opener
  | Ok answer -> wake_openers (adopted_of answer)

(* chrome-qnul: Chrome pushes the *tab-strip* title in Target.targetInfoChanged — the
   formatted URL, "example.com" for example.com — and does not push the document title
   that the load brings. A query right after the load carries the document title and the
   committed URL, so the reply and [list] report the page rather than the tab strip. Best
   effort: a tab that vanished during the load is reported by the caller's own lookup, not
   by this call. *)
let refresh_from_target cdp tab =
  match cdp_call cdp "Target.getTargetInfo" (obj [ ("targetId", str tab.id) ]) with
  | Error _ -> ()
  | Ok result -> (
      match member "targetInfo" result with
      | None -> ()
      | Some info ->
          Option.iter (fun url -> tab.url <- url) (text "url" info);
          Option.iter (fun title -> tab.title <- title) (text "title" info))

(* svc-hi4f: the page an action navigates to is titled only once its document has
   loaded, and the settle that ends an action is two frames — far too early, which is what
   the L23 live run saw: the reply and [list] carried the tab strip's formatted URL instead
   of the document title. A watch is armed before the action is dispatched, exactly as a
   load wait is armed before its navigate. [refresh] reads the tab's target back at once,
   waits — bounded like a load — when a main-frame navigation landed since the last watch
   and the document is still loading, and reads again. Best effort: a page that never
   finishes loading costs the wait, not the action. *)
let watch_navigation t cdp tab =
  let seen = ref tab.navigations in
  fun () ->
    let since = !seen in
    refresh_from_target cdp tab;
    if tab.dialog = None && tab.navigations <> since && tab.page_loading then (
      let promise, waiter = Eio.Promise.create () in
      tab.page_loads <- waiter :: tab.page_loads;
      Fun.protect
        ~finally:(fun () ->
          tab.page_loads <- List.filter (fun pending -> pending != waiter) tab.page_loads)
        (fun () -> ignore (t.await_load promise)));
    if tab.dialog = None && tab.navigations <> since then refresh_from_target cdp tab;
    seen := tab.navigations

(* chrome-1yn9, chrome-qnul: a url is loaded when the load event fires, or when the
   document's main frame navigated and its DOM content is in — never when the network is
   idle. [start] issues whatever begins the load; the waiter is armed before it runs, so
   no event it provokes can be missed. Bounded to 30 seconds. The caller holds the tab's
   lock. *)
let with_load_wait t cdp tab start =
  let promise, waiter = Eio.Promise.create () in
  tab.loading <- true;
  tab.navigated <- false;
  tab.completed <- false;
  tab.load_waiter <- Some waiter;
  Fun.protect
    ~finally:(fun () ->
      tab.loading <- false;
      tab.load_waiter <- None)
    (fun () ->
      match
        Dialog_race.first (dialog_race tab) (fun () ->
            let* () = start () in
            match t.await_load promise with
            | Error `Timeout ->
                refresh_from_target cdp tab;
                Ok false
            | Ok () ->
                refresh_from_target cdp tab;
                Ok true)
      with
      | `Dialog _ -> Ok false
      | `Value result -> result)

let new_tab ?label t ~url =
  let target = Option.value ~default:"about:blank" url in
  if not (valid_url target) then Error (refusal ())
  else if open_tabs t >= t.cap then Error (error "tab-cap" "tab cap reached")
  else
    let* cdp = ready t in
    Ox.Actor.tell t.ledger (Creating { delta = 1; at = now t });
    Fun.protect
      ~finally:(fun () ->
        (* The last creation to end adopts what Chrome reported meanwhile. The ask must
           not be cancelled halfway, whatever ended the creation. *)
        match call_protected t (Creating { delta = -1; at = now t }) with
        | Ok answer -> wake_openers (adopted_of answer)
        | Error _ -> ())
      (fun () ->
        let* created =
          (* Creating directly at [target] can finish a fast local load before
            Page.enable has subscribed to events. Create blank, subscribe, then
            navigate explicitly so the load waiter cannot miss it (chrome-qnul). *)
          (* chrome-9ex7: by default Chrome gives a created tab page focus even when its
             window has none, so the page would see document.hasFocus() true in a
             background window. [focus:false] leaves focus to the window, as a tab the
             operator opens; the tab is still the window's active one. *)
          cdp_call cdp "Target.createTarget"
            (obj [ ("url", str "about:blank"); ("focus", `Bool false) ])
        in
        match text "targetId" created with
        | None -> Error (error "internal" "browser omitted targetId")
        | Some id -> (
            (* field-m5jw: record the target as soon as Chrome creates it, before
               attachment, domain setup or the load wait can suspend. *)
            let* { tab; _ } =
              register t ~id ~session:None
                ~origin:(enum P.Origin.of_string "agent")
                ~label ~url:"about:blank" ~title:"" ()
            in
            let* attached =
              cdp_call cdp "Target.attachToTarget"
                (obj [ ("targetId", str id); ("flatten", `Bool true) ])
            in
            match text "sessionId" attached with
            | None -> Error (error "internal" "browser omitted sessionId")
            | Some session ->
                (* own-6ndc: the tab an agent creates is owned by that agent from the
                   start. *)
                tab.session <- Some session;
                (* chrome-qnul: a tab created with a url is only titled once its document
                   has loaded, so the reply waits exactly as [nav] does. Without a url (or
                   for [about:blank]) there is nothing to await and the reply is immediate. *)
                let* _ =
                  session_call cdp tab session "Page.addScriptToEvaluateOnNewDocument"
                    (obj
                       [
                         ("source", str Snapshot_source.counter_script);
                         ("worldName", str Snapshot_source.world_name);
                       ])
                in
                tab.counter_installed <- true;
                (* chrome-qnul: Page.enable before the navigate, so the load waiter cannot
                   miss the load's events; tab-bw4j tab-8la3: the domains actions need. *)
                use_session t cdp tab session;
                let* loaded =
                  if waits_for_load url then
                    with_load_wait t cdp tab (fun () ->
                        let* reply =
                          session_call cdp tab session "Page.navigate"
                            (obj [ ("url", str target) ])
                        in
                        (match text "frameId" reply with
                        | Some id -> tab.main_frame <- Some id
                        | None -> ());
                        match text "errorText" reply with
                        | Some _ -> Error (error "internal" "browser navigation failed")
                        | None -> Ok ())
                  else Ok true
                in
                Ok { (info t tab) with P.loaded = Some loaded }))

(* chrome-1yn9: the lock-free body, for a caller that already holds the tab's lock (the
   run's playbook switch, run-xh5d). *)
let navigate_locked t ~tab url =
  let* cdp = ready t in
  let* session = page_session t cdp tab in
  (* chrome-1yn9: the tab is navigating to [url] now, so [url] is the fallback until
     Chrome speaks; the load wait's own [Target.getTargetInfo] refresh replaces it with
     the URL Chrome committed, which is what a redirect changes. *)
  tab.url <- url;
  tab.snapshot <- None;
  let* loaded =
    with_load_wait t cdp tab (fun () ->
        let* reply =
          session_call cdp tab session "Page.navigate" (obj [ ("url", str url) ])
        in
        (match text "frameId" reply with
        | Some id -> tab.main_frame <- Some id
        | None -> ());
        match text "errorText" reply with
        | Some _ -> Error (error "internal" "browser navigation failed")
        | None -> Ok ())
  in
  let* _ = locate t ~access:Act (credential tab) in
  let* _ = ready t in
  Ok { (info t tab) with P.loaded = Some loaded }

let navigate t handle url =
  if not (valid_url url) then Error (refusal ())
  else
    let* tab = peek t ~access:Act handle in
    with_tab_lock tab (fun () ->
        let* tab = locate t ~access:Act handle in
        navigate_locked t ~tab url)

let close t handle =
  let k = key handle in
  match Keys.find_opt k (snapshot t).tombs with
  | Some tomb
    when P.Disposition.to_string tomb.disposition = "closed_by_handle"
         && now t -. tomb.at < float t.tombstone_s ->
      Ok P.{ closed = true }
  | _ ->
      let* tab = peek t ~access:Close handle in
      with_tab_lock tab (fun () ->
          let* tab = locate t ~access:Close handle in
          let* cdp = ready t in
          let* session = page_session t cdp tab in
          let close_target () =
            cdp_call cdp "Target.closeTarget" (obj [ ("targetId", str tab.id) ])
          in
          let already_open = tab.dialog <> None in
          let* _ =
            match Dialog_race.first (dialog_race tab) close_target with
            | `Value result -> result
            | `Dialog dialog when P.Dialog_kind.to_string dialog.kind = "beforeunload" ->
                let* _ =
                  session_call cdp tab session "Page.handleJavaScriptDialog"
                    (obj [ ("accept", `Bool true) ])
                in
                (* An already-open beforeunload needs the close dispatched now; an
                   opening during this call came from the close already in flight. *)
                if already_open then close_target () else Ok (`Assoc [])
            | `Dialog _ ->
                Error (error "dialog-open" "answer the dialog before closing the tab")
          in
          disappear t tab (disposition "closed_by_handle");
          Ok P.{ closed = true })

(* hand-lmd5: the deadline a handoff runs on — the caller's [timeout_s], fifteen minutes
   when it names none (or names something a clock cannot use). [Control.budget] asks this
   same question, so the handler's budget and the request's own deadline cannot drift
   apart. *)
let handoff_timeout_s t = t.handoff_timeout_s

let handoff_timeout ?(default = 300) = function
  | Some seconds when seconds > 0 -> Ox.Duration.seconds seconds
  | Some _ | None -> Ox.Duration.seconds default

(* hand-len8 hand-nisr: the transition itself, for a caller that already holds the tab's
   lock — which the run does for its whole duration (run-d82w) — and for the command
   below. *)
let begin_handoff_locked t ~reason tab =
  let* entry =
    transition t (Hand_over_held { reason; handle = credential tab; at = now t })
  in
  match entry.handoff with
  | Some waiting -> Ok (entry, waiting)
  | None -> Error (error "internal" "a handoff was not installed")

let begin_handoff t ~reason handle =
  let* tab = peek t ~access:Act handle in
  Eio.Mutex.use_rw ~protect:true tab.lock (fun () ->
      let* entry = transition t (Hand_over { reason; handle; at = now t }) in
      match entry.handoff with
      | Some waiting -> Ok (entry, waiting)
      | None -> Error (error "internal" "a handoff was not installed"))

let hand_over t ~reason handle =
  let* entry, _ = begin_handoff t ~reason handle in
  Ok (info_of t entry)

let close_after_resume t handle =
  let* tab = peek t ~access:Act handle in
  Eio.Mutex.use_rw ~protect:true tab.lock (fun () ->
      tab.close_on_resume <- true;
      Ok ())

let resume t handle =
  let* tab = peek t ~access:Resume handle in
  let* () =
    Eio.Mutex.use_rw ~protect:true tab.lock (fun () ->
        (* hand-0sja own-ay3s: resume resets the idle clock of a supplied tab. *)
        let* _ = transition t (Resume { handle; at = now t }) in
        Ok ())
  in
  if tab.close_on_resume then Result.map (fun _ -> P.{ resumed = true }) (close t handle)
  else Ok P.{ resumed = true }

(* hand-04rb: every human-facing step a handoff waits on is bounded by five seconds — the
   browser call that raises the view here, and the window lookup and focus command inside
   {!Desktop} — so a desktop that has stopped answering cannot hold the handler. *)
let step_deadline = Ox.Duration.seconds 5

(* hand-04rb hand-phof hand-rg9h: the human-facing side of one handoff, best effort by
   contract. The tab is already [With_human] when this runs, every step that fails becomes
   a warning the reply carries and a log line, and no failure here ends the handoff: a
   missing notify-send must not break the agent.

   - hand-04rb: [Target.activateTarget] raises the tab inside the managed Chrome's window
     first — a compositor may still ignore it (ADR-0003) — and then the configured desktop
     command runs, bounded by its own five seconds.
   - hand-phof: the notification runs on the handoff's own switch, for as long as the
     handoff does, so the human's Done action can arrive at any moment and the child is
     stopped the moment the handoff ends by any path — resume, deadline, disconnect, or
     the tab going away. Its Done action is the human's [resume] (hand-0sja); one that
     arrives after the handoff already ended is logged, not retried. *)
let announce t ~sw ~tab ~reason ~warn ~clean =
  let context =
    Desktop.{ tab = credential tab; reason=clean reason; url = clean tab.url; title = clean tab.title }
  in
  let guarded step f =
    match
      try f () with
      | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
      | ex -> Error (Printexc.to_string ex)
    with
    | Ok () -> ()
    | Error message -> warn step message
  in
  guarded "activate-target" (fun () ->
      match ready t with
      | Error error -> Error error.P.message
      | Ok cdp -> (
          (* Five seconds, not the browser-op deadline: raising the view is best effort,
             and a wedged browser must not hold the handoff (control.ml's margin counts
             on this bound). *)
          match
            cdp_call ~deadline:step_deadline cdp "Target.activateTarget"
              (obj [ ("targetId", str tab.id) ])
          with
          | Ok _ -> Ok ()
          | Error error -> Error error.P.message));
  guarded "focus" (fun () -> Desktop.focus t.desktop context);
  (* A daemon, not a plain fork: Eio's [Switch.run] waits for plain fibers, so a notifier
     that outlives the handoff would hold the reply. The switch cancels a daemon once the
     handoff's own work is done and still waits for the cancellation to finish — which is
     what stops the child and reaps it before the request answers. *)
  Eio.Fiber.fork_daemon ~sw (fun () ->
      guarded "notify" (fun () ->
          Desktop.notify t.desktop ~sw context ~on_done:(fun () ->
              match resume t (credential tab) with
              | Ok _ -> ()
              | Error error ->
                  Ox_observability.Logger.info t.logger
                    ~fields:[ ("url", Ox_observability.Logger.String (clean tab.url)) ]
                    ("the notification answered a handoff that had already ended: "
                   ^ clean error.P.message)));
      `Stop_daemon)

let handoff ?(secrets=[]) t ~reason ~timeout_s handle =
  let clean text = P.redact_string secrets text in
  (* hand-lmd5: the deadline counts from the request, not from the moment the ledger's
     answer reaches this fiber. *)
  let started = now t in
  let* { tab; _ }, waiting = begin_handoff t ~reason handle in
  let warnings = ref [] in
  let warn step message =
    let warning = clean (step ^ ": " ^ message) in
    warnings := warning :: !warnings;
    Ox_observability.Logger.warn t.logger
      ~fields:
        [
          ("url", Ox_observability.Logger.String (clean tab.url));
          ("reason", Ox_observability.Logger.String (clean reason));
        ]
      ("handoff warning: " ^ warning)
  in
  let release () =
    (* The listener cancels this fiber when the client disconnects, so the restore runs
       under [Eio.Cancel.protect]: it must not be cancelled halfway, and it must not wait
       on a lock it will never get. *)
    Eio.Cancel.protect (fun () ->
        Eio.Mutex.use_rw ~protect:true tab.lock (fun () ->
            ignore (call t (Restore { handle = credential tab; waiting; at = now t }))))
  in
  let warnings_json () =
    match List.rev !warnings with
    | [] -> None
    | warnings -> Some (obj [ ("warnings", `List (List.map str warnings)) ])
  in
  let answer () =
    match waiting.outcome with
    | Some Resumed ->
        Ok
          P.
            {
              resumed = true;
              url = tab.url;
              title = tab.title;
              warnings =
                (match List.rev !warnings with [] -> None | warnings -> Some warnings);
            }
    | Some (Ended error) -> Error error
    | None ->
        (* hand-rg9h: an unanswered handoff is exactly when the human-facing failures
           explain it, so the timeout carries them in [detail]. *)
        Error (error ?detail:(warnings_json ()) "timeout" "the handoff timed out")
  in
  (* hand-lmd5: the deadline is the request's own, so the human-facing steps that ran
     before the wait count against it — a handoff never outlives the deadline its caller
     gave it — and a deadline already spent answers at once. *)
  let remaining () =
    let spent = Ox.Duration.ms (int_of_float ((now t -. started) *. 1000.)) in
    Ox.Duration.max Ox.Duration.zero
      (Ox.Duration.subtract
         (handoff_timeout ~default:t.handoff_timeout_s timeout_s)
         spent)
  in
  Fun.protect ~finally:release (fun () ->
      Eio.Switch.run (fun human ->
          (* hand-04rb hand-phof: the human-facing steps, on this handoff's own switch, so
             the notifier is stopped when the request ends however it ends. *)
          announce t ~sw:human ~tab ~reason ~warn ~clean;
          let left = remaining () in
          if not (Ox.Duration.is_zero left) then
            ignore (t.await_handoff left waiting.promise);
          answer ()))

(* hand-x3hi: list is for finding. Every live tab, never a handle. *)
(* hand-x3hi: a human types a URL or follows a link without Leash watching, and Chrome
   pushes only the tab-strip title (the formatted URL) for that. [list] and [take] find
   tabs by title, so they read every target's current title and URL first (one bounded
   call); a failure keeps the last known values. *)
let refresh_titles t =
  match ready t with
  | Error _ -> ()
  | Ok cdp -> (
      match
        cdp_call ~deadline:(Ox.Duration.seconds 2) cdp "Target.getTargets" (obj [])
      with
      | Error _ -> ()
      | Ok result -> (
          match member "targetInfos" result with
          | Some (`List infos) ->
              List.iter
                (fun info ->
                  match text "targetId" info with
                  | None -> ()
                  | Some id -> (
                      match tab_of_target t id with
                      | None -> ()
                      | Some tab ->
                          Option.iter (fun url -> tab.url <- url) (text "url" info);
                          Option.iter
                            (fun title -> if title <> "" then tab.title <- title)
                            (text "title" info)))
                infos
          | _ -> ()))

let list t =
  refresh_titles t;
  {
    P.tabs =
      List.map (listing_of t)
        (live_entries t |> List.sort (fun a b -> String.compare a.tab.id b.tab.id));
  }

(* hand-okk8 hand-gjqy: finding a tab is not authorization to act on it. *)
let take t (args : P.take_args) =
  refresh_titles t;
  let selectors =
    List.filter_map Fun.id
      [
        Option.map (fun v -> `Url v) args.url;
        Option.map (fun v -> `Title v) args.title;
        Option.map (fun v -> `Label v) args.label;
      ]
  in
  match selectors with
  | [ selector ] -> (
      let lower = String.lowercase_ascii in
      let contains s sub =
        let n = String.length sub in
        let rec loop i =
          i + n <= String.length s && (String.sub s i n = sub || loop (i + 1))
        in
        loop 0
      in
      let matches entry =
        match selector with
        | `Url v -> String.starts_with ~prefix:(lower v) (lower entry.tab.url)
        | `Title v -> contains (lower entry.tab.title) (lower v)
        | `Label v ->
            Option.fold ~none:false ~some:(fun l -> lower l = lower v) entry.tab.label
      in
      match List.filter matches (live_entries t) with
      | [] -> Error (error "no-match" "no tab matches the selector")
      | [ entry ] ->
          Eio.Mutex.use_rw ~protect:true entry.tab.lock (fun () ->
              Result.map (info_of t)
                (transition t (Take { id = entry.tab.id; at = now t })))
      | entries ->
          Error
            (error "ambiguous" "several tabs match; narrow the selector"
               ~detail:
                 (obj
                    [
                      ( "matches",
                        `List
                          (List.map
                             (fun e -> P.yojson_of_tab_listing (listing_of t e))
                             entries) );
                    ])))
  | _ -> Error (error "usage" "take requires exactly one of --url, --title or --label")

let idleness_of t (entry : entry) : idleness =
  {
    handle = credential entry.tab;
    origin = entry.tab.origin;
    with_human = entry.with_human;
    idle_for_s = now t -. entry.last_activity;
  }

let idleness t =
  live_entries t
  |> List.filter (fun e -> e.tab.handle <> None)
  |> List.map (idleness_of t)

(* hand-0ibq hand-ihcg: recheck under the action lock. A long-running action cannot be swept. *)
let sweep t ~decide =
  List.filter_map
    (fun entry ->
      if entry.tab.handle = None then None
      else
        let h = credential entry.tab in
        with_tab_lock entry.tab (fun () ->
            match Keys.find_opt (key h) (snapshot t).entries with
            | Some entry
              when (not entry.with_human) && P.Origin.to_string entry.tab.origin = "agent"
              -> (
                match (decide (idleness_of t entry), ready t) with
                | Close_idle, Ok cdp -> (
                    match
                      cdp_call cdp "Target.closeTarget"
                        (obj [ ("targetId", str entry.tab.id) ])
                    with
                    | Ok _ ->
                        disappear t entry.tab (disposition "closed_by_idle");
                        Some (h, Close_idle)
                    | Error _ -> None)
                | _ -> None)
            | _ -> None))
    (live_entries t)

(* The two reads a snapshot's currency rests on, shared by `snap` and by `wait
   --changed-since` (hard-sckn): the main frame's loader id, and the document's mutation
   guard — installed on the spot when this document has none. [call] is a page-session
   CDP call. *)
let frame_loader call =
  let* reply = call "Page.getFrameTree" (obj []) in
  match member "frameTree" reply with
  | Some tree ->
      let frame = Option.value ~default:`Null (member "frame" tree) in
      Ok (Option.value ~default:"" (text "loaderId" frame))
  | None -> Error (error "internal" "browser omitted frame tree")

(* chrome-9ex7: the guard lives in Leash's own isolated world, never in the page's main
   world, so a page cannot see it (no window global, no observer of its own). Chrome keeps
   one world per frame and name for this session: [Page.createIsolatedWorld] with the name
   the new-document script uses answers the context that script ran in, and makes it when
   the document predates the script. *)
let guard_context call =
  let* reply = call "Page.getFrameTree" (obj []) in
  let frame =
    Option.bind (member "frameTree" reply) (member "frame") |> Option.value ~default:`Null
  in
  match text "id" frame with
  | None -> Error (error "internal" "browser omitted frame tree")
  | Some frame_id -> (
      let* world =
        call "Page.createIsolatedWorld"
          (obj
             [ ("frameId", str frame_id); ("worldName", str Snapshot_source.world_name) ])
      in
      match member "executionContextId" world with
      | Some (`Int id) -> Ok id
      | _ -> Error (error "internal" "browser omitted the isolated world"))

let page_guard call =
  let* context = guard_context call in
  let evaluate expression =
    let* reply =
      call "Runtime.evaluate"
        (obj
           [
             ("expression", str expression);
             ("contextId", `Int context);
             ("returnByValue", `Bool true);
           ])
    in
    match member "result" reply with
    | Some result -> Ok (Option.value ~default:`Null (member "value" result))
    | None -> Error (error "internal" "browser omitted guard result")
  in
  let* current = evaluate Snapshot_source.guard_expression in
  match Snapshot_source.guard current with
  | Some guard -> Ok guard
  | None -> (
      let* _ = evaluate Snapshot_source.counter_script in
      let* reply = evaluate Snapshot_source.guard_expression in
      match Snapshot_source.guard reply with
      | Some guard -> Ok guard
      | None -> Error (error "internal" "document mutation guard unavailable"))

(* tab-of0i tab-tmoc tab-1r34 tab-hyap tab-1rx9 tab-0vh8:
   retain the unfiltered node table for later action-time revalidation. *)
let snap_locked ?(attempts = 3) t tab (args : P.snap_args) =
  let offset = Option.value ~default:0 args.offset in
  let limit = Option.value ~default:120 args.limit in
  if offset < 0 || limit < 0 || limit > 1000 then
    Error (error "invalid-request" "snap offset must be nonnegative and limit 0..1000")
  else
    let* cdp = ready t in
    let* session = page_session t cdp tab in
    with_focus t tab @@ fun engage ->
    engage ();
    let call meth params = session_call cdp tab session meth params in
    let* () =
      if tab.counter_installed then Ok ()
      else
        let* _ =
          call "Page.addScriptToEvaluateOnNewDocument"
            (obj
               [
                 ("source", str Snapshot_source.counter_script);
                 ("worldName", str Snapshot_source.world_name);
               ])
        in
        tab.counter_installed <- true;
        Ok ()
    in
    let loader () = frame_loader call in
    let guard () = page_guard call in
    let capture ~fallback () =
      let* before_loader = loader () in
      let* before = guard () in
      let* ax = call "Accessibility.getFullAXTree" (obj []) in
      let* dom =
        call "DOMSnapshot.captureSnapshot"
          (obj
             [
               ("computedStyles", `List [ str "display"; str "visibility" ]);
               ("includeDOMRects", `Bool true);
             ])
      in
      let _, _, width, height, scroll_x, scroll_y = before in
      let ax_rows = Snapshot_source.rows ~ax ~dom ~width ~height ~scroll_x ~scroll_y in
      let populated = Snapshot_source.has_interactive ax in
      let* empty_page =
        if populated then Ok false
        else
          let* context = guard_context call in
          let* count =
            call "Runtime.evaluate"
              (obj
                 [
                   ("expression", str Snapshot_source.interactive_count_expression);
                   ("contextId", `Int context);
                   ("returnByValue", `Bool true);
                 ])
          in
          Ok (Option.bind (member "result" count) (member "value") = Some (`Int 0))
      in
      let ax_empty = (not populated) && not empty_page in
      let* rows, source =
        if ax_empty && fallback then
          let* context = guard_context call in
          let* rows = Snapshot_source.dom_rows ~call ~context in
          Ok (rows, P.Dom)
        else
          let frames =
            Snapshot_source.frame_rows ~url:tab.url ~dom ~width ~height ~scroll_x
              ~scroll_y
          in
          let rows =
            ax_rows
            @ List.filter
                (fun (_, backend) ->
                  not (List.exists (fun (_, id) -> id = backend) ax_rows))
                frames
          in
          Ok
            ( List.mapi
                (fun index ((row : P.row), backend) ->
                  ({ row with P.index = index + 1 }, backend))
                rows,
              P.Ax )
      in
      let* after = guard () in
      let* after_loader = loader () in
      let stable = before = after && before_loader = after_loader in
      let settled = stable && not ax_empty in
      let reason =
        if ax_empty then Some "ax-tree-empty"
        else if not stable then Some "document-changing"
        else None
      in
      let epoch, count, _, _, _, _ = after in
      Ok (rows, settled, source, reason, after_loader, Some (epoch, count))
    in
    let rec attempt remaining =
      let* rows, settled, source, reason, loader_id, guard =
        if tab.dialog <> None then Ok ([], false, P.Ax, Some "dialog-open", "", None)
        else capture ~fallback:(remaining = 0 && attempts >= 3) ()
      in
      if (not settled) && remaining > 0 && tab.dialog = None then attempt (remaining - 1)
      else Ok (rows, settled, source, reason, loader_id, guard)
    in
    let* rows, settled, source, reason, loader_id, guard = attempt (attempts - 1) in
    (* trace-qe8c: targetInfoChanged may hold the tab-strip URL, not the document title. *)
    refresh_titles t;
    let snapshot =
      enum P.Snapshot_id.of_string ("s_" ^ P.Handle.to_string (handle ~caps:t.caps))
    in
    tab.snapshot <- Some (snapshot, loader_id, rows);
    tab.dom_snapshot <- source = P.Dom;
    (* hard-sckn: what the page was when this table was taken, kept beyond the next
       navigation (which clears the table itself) so `wait --changed-since` can tell that
       the page moved on. The last few tables are remembered. *)
    (match guard with
    | Some guard ->
        tab.baselines <-
          (snapshot, Reading.{ loader = loader_id; guard = Some guard })
          :: List.filteri (fun i _ -> i < baselines_kept - 1) tab.baselines
    | None -> ());
    let matches row =
      match args.match_ with
      | None -> true
      | Some pattern ->
          let pattern = String.lowercase_ascii pattern in
          let contains s =
            let s = String.lowercase_ascii s in
            let n = String.length pattern in
            let rec scan at =
              at + n <= String.length s && (String.sub s at n = pattern || scan (at + 1))
            in
            scan 0
          in
          contains row.P.role || contains row.name
          || Option.fold ~none:false ~some:contains row.value
    in
    let all = rows |> List.map fst |> List.filter matches in
    let total = List.length all in
    let shown = all |> List.filteri (fun i _ -> i >= offset && i - offset < limit) in
    Ok
      P.
        {
          snapshot;
          tab = credential tab;
          url = tab.url;
          title = tab.title;
          page_kind = page_label ~books:(installed_books t) ~url:tab.url ~title:tab.title;
          rows = shown;
          total;
          offset;
          truncated = offset + List.length shown < total;
          settled;
          source;
          reason;
          dialog = tab.dialog;
        }

let snap t (args : P.snap_args) =
  let* tab = peek t ~access:Act args.tab in
  with_tab_lock tab (fun () ->
      let* tab = locate t ~access:Act args.tab in
      snap_locked t tab args)

(* tab-9x5e tab-x4v0 tab-a33o tab-qmei tab-5vnm tab-un75 tab-fepr tab-0lax:
   the registry owns identity and the page session; Reading owns browser-specific work. *)
let reading_browser t ~session tab cdp : Reading.browser =
  (* daily-6pde daily-9ggi: subscribe before each read so a dialog opening during
     a withheld CDP call wins over the command deadline. Answering it bypasses the guard. *)
  let call meth params =
    if meth = "Page.handleJavaScriptDialog" then session_call cdp tab session meth params
    else
      match
        Dialog_race.first (dialog_race tab) (fun () ->
            session_call cdp tab session meth params)
      with
      | `Value result -> result
      | `Dialog dialog ->
          Error
            (P.make_error
               (enum P.Error_code.of_string "dialog-open")
               ~message:"a dialog blocks page reads; answer it first"
               ~detail:(P.yojson_of_dialog dialog))
  in
  {
    call;
    now = (fun () -> now t);
    sleep = t.sleep;
    current = (fun () -> (tab.url, tab.title));
    dialog = (fun () -> tab.dialog);
    dialog_race = dialog_race tab;
    acknowledge = (fun () -> acknowledge tab);
    row =
      (fun index ->
        match tab.snapshot with
        | None -> None
        | Some (_, _, rows) ->
            List.find_map
              (fun ((row : P.row), backend) ->
                if row.P.index = index then Some backend else None)
              rows);
    snapshot = (fun () -> Option.map (fun (id, _, _) -> id) tab.snapshot);
    baseline = (fun id -> List.assoc_opt id tab.baselines);
    probe =
      (fun () ->
        let* loader = frame_loader call in
        let* epoch, count, _, _, _, _ = page_guard call in
        Ok Reading.{ loader; guard = Some (epoch, count) });
  }

let with_reading t ~access handle f =
  let* tab = peek t ~access handle in
  with_tab_lock tab (fun () ->
      let* tab = locate t ~access handle in
      let* cdp = ready t in
      let* session = page_session t cdp tab in
      with_focus t tab (fun engage ->
          let browser = reading_browser t ~session tab cdp in
          f tab
            {
              browser with
              call =
                (fun meth params ->
                  if meth <> "Page.handleJavaScriptDialog" then engage ();
                  browser.call meth params);
            }))

let read_text t (args : P.text_args) =
  with_reading t ~access:Act args.tab (fun _ browser -> Reading.text browser args)

(* map-op09: capture only structure, on the exact final page, before trace persistence. *)

let eval t (args : P.eval_args) =
  with_reading t ~access:Act args.tab (fun _ browser -> Reading.eval browser args)

let shot t (args : P.shot_args) =
  with_reading t ~access:Act args.tab (fun _ browser ->
      Reading.shot ~caps:t.caps browser args)

let debug t (args : P.debug_args) =
  let* tab = locate t ~access:Act args.tab in
  Reading.debug tab.reading args

(* hard-xg6y hard-ovbx hard-vq5s hard-ufb7: the request ring, cookies and storage are
   reads. They take no action lock, like [debug] and [wait]: reading a body while a long
   [drive] holds the tab is the point, and they change nothing a running action could
   trip over. Ownership is still checked, and the page session still comes from the
   registry. *)
let with_reading_unlocked t handle f =
  let* tab = locate t ~access:Act handle in
  let* cdp = ready t in
  let* session = page_session t cdp tab in
  f tab (reading_browser t ~session tab cdp)

let net t (args : P.net_args) =
  let* tab = locate t ~access:Act args.tab in
  Reading.net tab.reading args

let net_body t (args : P.net_entry_args) =
  with_reading_unlocked t args.tab (fun tab browser ->
      Reading.net_body browser tab.reading args)

let net_request t (args : P.net_entry_args) =
  with_reading_unlocked t args.tab (fun tab browser ->
      Reading.net_request browser tab.reading args)

let cookies t (args : P.tab_args) =
  with_reading_unlocked t args.tab (fun _ browser -> Reading.cookies browser)

let storage t (args : P.storage_args) =
  with_reading_unlocked t args.tab (fun _ browser -> Reading.storage browser args)

let dialog t (args : P.dialog_args) =
  let* tab = locate t ~access:Dialog args.tab in
  let* cdp = ready t in
  let* session = page_session t cdp tab in
  Reading.dialog (reading_browser t ~session tab cdp) args

let wait t (args : P.wait_args) =
  let* tab = locate t ~access:Act args.tab in
  let* cdp = ready t in
  let* session = page_session t cdp tab in
  let browser = reading_browser t ~session tab cdp in

  let touch () = Ox.Actor.tell t.ledger (Touch { handle = credential tab; at = now t }) in
  Reading.wait
    {
      browser with
      sleep =
        (fun seconds ->
          touch ();
          browser.sleep seconds);
    }
    args

(* L7 tab-bw4j tab-j1z2 tab-p3x1 tab-luo5 tab-5deq tab-8dop tab-tm6c tab-hxld tab-60kn
   tab-1lhx tab-8la3: the registry owns the tab's identity, its page session, and its
   lock; Actions owns revalidation, dispatch, and settlement. The lock is what makes one
   tab's actions run one at a time in arrival order while another tab's proceed. *)
let action_view t ~session tab cdp : Actions.tab =
  let observed = ref None in
  let opener_url = tab.url in
  let blank_url url = url = "" || url = "about:blank" in
  let refresh_popup popup =
    let rec refresh attempts =
      refresh_from_target cdp popup;
      if attempts > 0 && tab.dialog = None && blank_url popup.url then (
        t.sleep 0.01;
        refresh (attempts - 1))
    in
    refresh 100
  in
  {
    Actions.session;
    target = tab.id;
    handle = credential tab;
    page = (fun () -> (tab.url, tab.title));
    refresh = watch_navigation t cdp tab;
    snapshot = (fun () -> tab.snapshot);
    dom_snapshot = (fun () -> tab.dom_snapshot);
    dialog = (fun () -> tab.dialog);
    dialog_race = dialog_race tab;
    acknowledge = (fun () -> acknowledge tab);
    engage = (fun () -> ());
    sleep = t.sleep;
    same_document = (fun () -> tab.same_document);
    net_seq = (fun () -> tab.net_seq);
    requests_since =
      (fun since ->
        Hashtbl.to_seq tab.inflight |> Seq.exists (fun (_, seq) -> seq > since));
    reread = (fun () -> refresh_from_target cdp tab);
    arm_transition =
      (fun () ->
        tab.armed_doc <- tab.same_document;
        tab.armed_net <- tab.net_seq);
    armed_document = (fun () -> tab.armed_doc);
    armed_net = (fun () -> tab.armed_net);
    all_tabs =
      (fun () ->
        let entries = (snapshot t).entries in
        (match !observed with
        | None -> observed := Some entries
        | Some before ->
            Keys.iter
              (fun id (entry : entry) ->
                if
                  blank_url entry.tab.url
                  && (not (Keys.mem id before))
                  && entry.tab.opener = Some tab.id
                then refresh_popup entry.tab)
              entries);
        Keys.fold
          (fun _ (entry : entry) acc ->
            let i = listing_of t entry in
            let p : P.popup_info =
              {
                tab = entry.tab.handle;
                label = i.label;
                url = i.url;
                title = i.title;
                page_kind = i.page_kind;
                origin = i.origin;
                age_s = i.age_s;
                idle_s = i.idle_s;
                closes_in_s = i.closes_in_s;
                with_human = i.with_human;
                reason = i.reason;
                generation = entry.tab.generation;
                dialog = entry.tab.dialog;
                opener_url;
                state =
                  enum P.Popup_state.of_string
                    (if blank_url i.url then if i.age_s < 1 then "opening" else "blank"
                     else "ready");
              }
            in
            (p, entry.tab.id, entry.tab.opener) :: acc)
          entries []);
  }

(* field-swvb: a requested snapshot is taken after settlement, under the same lock,
   by the snap path. A failure here is the action's failure: the click already happened,
   and the caller must know the table did not come back. *)
let attach_snap t tab ~snap ~match_ ~limit (result : P.action_result) =
  match snap with
  | Some true ->
      let* fresh =
        snap_locked t tab { tab = credential tab; match_; limit; offset = None }
      in
      Ok { result with snapshot = Some fresh }
  | _ -> Ok result

let with_action ?(after = fun _tab result -> Ok result) t handle f =
  let* tab = peek t ~access:Act handle in
  with_tab_lock tab (fun () ->
      let* tab = locate t ~access:Act handle in
      let* cdp = ready t in
      let* session = page_session t cdp tab in
      with_focus t tab (fun engage ->
          let* result =
            f cdp { (action_view t ~session tab cdp) with Actions.engage }
            |> Result.map_error (diagnose tab)
          in
          after tab result))

let click t (args : P.click_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.click ~cdp view args)

let fill t (args : P.fill_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.fill ~cdp view args)

let press t (args : P.press_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.press ~cdp view args)

let select t (args : P.select_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.select ~cdp view args)

let scroll t (args : P.scroll_args) =
  with_action t args.tab (fun cdp view -> Actions.scroll ~cdp view args)

let upload t (args : P.upload_args) =
  with_action t args.tab (fun cdp view -> Actions.upload ~caps:t.caps ~cdp view args)

let hover t (args : P.hover_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.hover ~cdp view args)

let check t (args : P.click_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.check ~cdp view args)

let uncheck t (args : P.click_args) =
  with_action ~after:(attach_snap t ~snap:args.snap ~match_:args.match_ ~limit:args.limit)
    t args.tab (fun cdp view -> Actions.uncheck ~cdp view args)

type meter = {
  usage : (string, Yojson.Safe.t) Hashtbl.t;
  input_ms : int ref;
  settle_ms : int ref;
  observation_retries : int ref;
}

let meter () =
  {
    usage = Hashtbl.create 4;
    input_ms = ref 0;
    settle_ms = ref 0;
    observation_retries = ref 0;
  }

let note_usage meter kind json = Hashtbl.replace meter.usage kind json
let clear_usage meter kind = Hashtbl.remove meter.usage kind
let usage meter kind = Hashtbl.find_opt meter.usage kind

let telemetry meter () =
  obj
    [
      ("observation_retries", `Int !(meter.observation_retries));
      ("input_ms", `Int !(meter.input_ms));
      ("settle_ms", `Int !(meter.settle_ms));
    ]

let add_ms cell started ended =
  cell := !cell + max 0 (int_of_float ((ended -. started) *. 1000.))

type remembered = { marker : string; coverage : Snapshot_source.coverage }

let read_operator cdp ~session =
  let* context = guard_context (fun meth params -> cdp_call ~session cdp meth params) in
  let* result =
    cdp_call ~session cdp "Runtime.evaluate"
      (obj
         [
           ("expression", str Snapshot_source.operator_expression);
           ("contextId", `Int context);
           ("returnByValue", `Bool true);
         ])
  in
  match member "exceptionDetails" result with
  | Some _ -> Ok Snapshot_source.Navigating
  | None -> (
      match member "result" result with
      | None -> Ok Snapshot_source.Foreign
      | Some inner -> (
          match text "type" inner with
          | Some "undefined" -> Ok Snapshot_source.Foreign
          | _ ->
              let value = Option.value ~default:`Null (member "value" inner) in
              Ok (Snapshot_source.parse_operator value)))

let page_fingerprint ~url ~page_text ~rows ~scroll_y ~scroll_height =
  Digest.to_hex
    (Digest.string
       (Yojson.Safe.to_string
          (obj
             [
               ("url", str url);
               ("text", str page_text);
               ("scroll_y", `Float scroll_y);
               ("scroll_height", `Float scroll_height);
               ("rows", `List (List.map P.yojson_of_row rows));
             ])))

let observation_of (snapshot : P.snapshot) (read : Snapshot_source.operator_read) =
  let rows = List.filter (fun (row : P.row) -> row.role <> "file-input") snapshot.rows in
  let snapshot = { snapshot with P.url = read.url; title = read.title; rows } in
  Drive.
    {
      snapshot;
      text = read.text;
      can_scroll_down = read.can_scroll_down;
      can_scroll_up = read.can_scroll_up;
      fingerprint =
        page_fingerprint ~url:snapshot.url ~page_text:read.text ~rows:snapshot.rows
          ~scroll_y:read.scroll_y ~scroll_height:read.scroll_height;
    }

(* drive-8n2z drive-tfqh fly-iodm fly-crcc: keep the lock across observe/decide/act.
   Never call a public Tabs action here: each would reacquire this very same mutex.
   An invalid operator payload is an observation error, never a weaker legacy read. *)
let drive_locked ?(secrets = fun () -> []) ?recent ?on_step ?(observed = fun (_ : Drive.observation) -> ())
    ?(meter = meter ())
    ?(decide =
      fun ~deadline:_ _ ->
        Error
          (error "model-unavailable" "System One client unavailable"
             ~detail:(obj [ ("code", str "client-unavailable") ])))
    ?(text_helper = fun () -> Text_helper.unavailable)
    ?(scripts = fun (_ : Drive.observation) -> []) ?run_script ?label t ~model tab
    (args : P.drive_args) =
  (* drive-kh2u drive-ix5t: one Decide is one System One call, and it is inside the
         drive's own deadline: the caller's remaining budget is what the model call is
         bounded by, so a slow provider cannot outlast the reply the client is waiting
         for. The text helper's completion is bounded by the same budget (drive-ls3c). *)
  let started = now t in
  let budget = float_of_int (Option.value ~default:120 args.deadline_s) in
  let remaining () =
    Ox.Duration.ms (max 1 (int_of_float ((budget -. (now t -. started)) *. 1000.)))
  in
  let decide request =
    clear_usage meter "operator";
    decide ~deadline:(remaining ()) (Jev_request.redact (secrets ()) request)
  in
  (* drive-ls3c: one helper per drive. It carries the one-entry memo that reuses an
         answer for an unchanged context — what a stale-row retry is — so it is taken
         here and goes away with the drive. *)
  let helper = text_helper () in
  let text_value context =
    clear_usage meter "text_helper";
    helper.Text_helper.complete ~deadline:(remaining ()) (Text_helper.redact (secrets ()) context)
  in
  let* cdp = ready t in
  let* session = page_session t cdp tab in
  with_focus t tab @@ fun engage ->
  let view = { (action_view t ~session tab cdp) with Actions.engage } in
  let remembered = Hashtbl.create 8 in
  let remember (snapshot : P.snapshot) (read : Snapshot_source.operator_read) =
    let omitted_elements =
      max read.coverage.omitted_elements (snapshot.total - List.length snapshot.rows)
    in
    let coverage =
      Snapshot_source.coverage_of ~unsupported_states:read.coverage.unsupported_states
        ~text_truncated:read.coverage.text_truncated ~omitted_elements
        ~can_scroll_up:read.can_scroll_up ~can_scroll_down:read.can_scroll_down
    in
    Hashtbl.replace remembered
      (P.Snapshot_id.to_string snapshot.snapshot)
      { marker = read.marker; coverage }
  in
  let page_id (page : Drive.observation) =
    P.Snapshot_id.to_string page.snapshot.snapshot
  in
  let coverage page =
    match Hashtbl.find_opt remembered (page_id page) with
    | Some saved -> Snapshot_source.coverage_json saved.coverage
    | None ->
        Snapshot_source.coverage_json
          (Snapshot_source.coverage_of ~unsupported_states:[]
             ~text_truncated:(String.length page.text >= Snapshot_source.text_limit)
             ~omitted_elements:
               (max 0 (page.snapshot.total - List.length page.snapshot.rows))
             ~can_scroll_up:page.can_scroll_up ~can_scroll_down:page.can_scroll_down)
  in
  let validate page =
    match Hashtbl.find_opt remembered (page_id page) with
    | None -> Ok ()
    | Some saved -> (
        match read_operator cdp ~session with
        | Error error -> Error error
        | Ok (Snapshot_source.Payload now) when now.marker = saved.marker -> Ok ()
        | Ok _ -> Error (P.stale_snapshot (Some page.snapshot.snapshot)))
  in
  let unsettled () = error "timeout" "the page did not settle" in
  let retry left =
    meter.observation_retries := !(meter.observation_retries) + 1;
    t.sleep Snapshot_source.observe_retry_s;
    left - 1
  in
  (* fly-qr70: a destroyed execution context is a document navigation, not a
     stale snapshot. The 10 by 20 ms budget is for an inconsistent live document.
     A click that leaves consent.google.com needs the same bounded load wait as nav. *)
  let wait_out_navigation () =
    let started = tab.navigations in
    let rec notice left =
      if tab.navigations <> started || tab.page_loading || left = 0 then ()
      else (
        t.sleep 0.05;
        notice (left - 1))
    in
    notice 8;
    if tab.page_loading then (
      let promise, waiter = Eio.Promise.create () in
      tab.page_loads <- waiter :: tab.page_loads;
      if not tab.page_loading then (
        tab.page_loads <- List.filter (fun pending -> pending != waiter) tab.page_loads;
        true)
      else
        Fun.protect
          ~finally:(fun () ->
            tab.page_loads <-
              List.filter (fun pending -> pending != waiter) tab.page_loads)
          (fun () ->
            ignore (t.await_load promise);
            true))
    else tab.navigations <> started
  in
  let rec acquire ~loads left =
    match read_operator cdp ~session with
    | Error error -> Error error
    | Ok Snapshot_source.Foreign ->
        Error (error "internal" "browser returned an invalid operator observation")
    | Ok Snapshot_source.Navigating when loads > 0 && wait_out_navigation () ->
        acquire ~loads:(loads - 1) left
    | Ok Snapshot_source.Navigating ->
        if left > 1 then acquire ~loads (retry left) else Error (unsettled ())
    | Ok (Snapshot_source.Payload before) -> (
        let* snapshot =
          snap_locked ~attempts:1 t tab
            P.{ tab = args.tab; match_ = None; limit = Some 250; offset = None }
        in
        match read_operator cdp ~session with
        | Error error -> Error error
        | Ok (Snapshot_source.Payload after)
          when snapshot.settled && after.marker = before.marker ->
            remember snapshot after;
            Ok (observation_of snapshot after)
        | Ok _ -> if left > 1 then acquire ~loads (retry left) else Error (unsettled ()))
  in
  let pending_settle = ref None in
  let observe () =
    let* () =
      match !pending_settle with
      | None -> Ok ()
      | Some autocomplete ->
          pending_settle := None;
          let at = now t in
          let* () = Actions.operator_settle ~cdp view ~autocomplete in
          add_ms meter.settle_ms at (now t);
          Ok ()
    in
    let* page = acquire ~loads:3 Snapshot_source.observe_attempts in
    observed page;
    Ok page
  in
  let idle () =
    P.
      {
        tab = args.tab;
        url = tab.url;
        title = tab.title;
        snapshot = None;
        dialog = tab.dialog;
        popups = [];
        via = None;
      }
  in
  let row_role page index =
    match
      List.find_opt (fun (row : P.row) -> row.index = index) page.Drive.snapshot.rows
    with
    | Some row -> row.role
    | None -> ""
  in
  let act (page : Drive.observation) (choice : Jev_request.decision) ~text =
    let* () = validate page in
    let snapshot = page.snapshot.snapshot in
    let index = Option.value ~default:0 choice.index in
    let op = P.Operation.to_string choice.operation in
    let* () =
      if op <> "click" then Ok ()
      else
        Result.map_error (error "row-not-actionable")
          (P.check_consent_click page.snapshot ~index)
    in
    let started_act = now t in
    let outcome =
      match op with
      | "click" ->
          Actions.click ~settle_after:false ~cdp view
            P.
              {
                tab = args.tab;
                snapshot;
                index;
                snap = None;
                match_ = None;
                limit = None;
              }
      | "select" ->
          Actions.select ~settle_after:false ~check_hit:true ~cdp view
            P.
              {
                tab = args.tab;
                snapshot;
                index;
                option = Option.value ~default:0 choice.option;
                snap = None;
                match_ = None;
                limit = None;
              }
      | "scroll_down" -> Actions.operator_scroll ~cdp view ~down:true
      | "scroll_up" -> Actions.operator_scroll ~cdp view ~down:false
      | "wait" ->
          t.sleep Snapshot_source.wait_s;
          Ok (idle ())
      | "type_text" -> (
          match text with
          | Some value ->
              let value = Option.value ~default:value (List.assoc_opt value (secrets ())) in
              Actions.fill ~settle_after:false ~check_hit:true ~blur_after:false ~cdp view
                P.
                  {
                    tab = args.tab;
                    snapshot;
                    index;
                    text = value;
                    snap = None;
                    match_ = None;
                    limit = None;
                  }
          | None ->
              Error
                (error "internal" "a type_text step reached the browser without a value"))
      | _ -> Error (error "invalid-request" "unsupported drive operation")
    in
    add_ms meter.input_ms started_act (now t);
    match outcome with
    | Ok acted when op <> "wait" ->
        (* Return the acknowledged input before settlement so Drive records it
               even if the next observation is cancelled or fails (fly-4mio). *)
        pending_settle := Some (op = "type_text" && row_role page index = "combobox");
        Ok acted
    | other -> other
  in
  (* fly-4mio: acquire already retries ten times at 20 ms. One Drive attempt,
     or the two loops would nest to a hundred observations. *)
  Drive.run ~validate ~coverage ~usage:(usage meter) ~telemetry:(telemetry meter)
    ~observe_attempts:1 ?recent ?on_step ~scripts ?run_script ?label
    ~handler:Drive.{ observe; decide; text_value; act }
    ~now:(fun () -> now t)
    ~model ~args
    ~dry_run:(Option.value ~default:false args.dry_run)
    ()

(* drive-8n2z: the public drive takes the tab's lock for the whole computation; the body
   above is what a caller that already holds it (the run's every step, run-d82w) uses. *)
let drive ?decide ?text_helper ?meter ?recent t ~model (args : P.drive_args) =
  let* tab = peek t ~access:Act args.tab in
  with_tab_lock tab (fun () ->
      let* tab = locate t ~access:Act args.tab in
      drive_locked ?decide ?text_helper ?meter ?recent t ~model tab args)

(* L31 run-9ypy run-vj48 run-shgh run-fwl8, L32 run-m0r8: a mission over the installed
   playbooks, with the
   tab's action lock held for the whole run. Every step is one [drive_locked] call — the
   very operator level the [drive] command runs — and every judgment goes through
   [Run.loop]'s handler, which this builds over the browser and the models service's levels
   (Control installs them; a scripted test installs its own, which is what makes the whole
   loop testable offline). The playbooks are loaded here, once, from the XDG directory the
   [playbook] commands read (run-tcuz) unless a test hands them in. *)
let no_levels : Run.levels =
  Run.
    {
      choose =
        (fun ~deadline:_ _ ->
          Error
            (error "model-unavailable"
               "no model client is configured for the run's playbook and procedure levels"));
      score =
        (fun ~deadline:_ ~sentence:_ ~state:_ ->
          Error
            (error "model-unavailable"
               "no model client is configured for the run's judgment score"));
      plan =
        (fun ~deadline:_ _ ->
          Error
            (error "model-unavailable"
               "no model client is configured for the run's planner"));
    }

let run ?(on_page = fun ~url:_ ~kind:_ ~pattern:_ -> ()) ?on_step
    ?(on_planner_step = fun _ -> ()) ?(on_arguments = fun _ -> ()) ?(planner_actions = 5)
    ?pilot ?(levels = no_levels) ?(model = "unconfigured")
    ?(decide =
      fun ~deadline:_ _ ->
        Error
          (error "model-unavailable" "System One client unavailable"
             ~detail:(obj [ ("code", str "client-unavailable") ])))
    ?(text_helper = fun () -> Text_helper.unavailable) ?learning ?meter t ~tab ?installed
    (args : P.run_args) =
  let handle = tab in
  let* tab = peek t ~access:Act handle in
  with_tab_lock tab (fun () ->
      let* tab = locate t ~access:Act handle in
      (* run-fwl8: a run starts from a state it can act in. Ownership and the human's hold
         are [locate]'s refusals; a dialog waiting to be answered is this one. *)
      match tab.dialog with
      | Some dialog ->
          Error
            (error "dialog-open"
               (Printf.sprintf "a %s dialog is open on the tab; answer it before the run"
                  (P.Dialog_kind.to_string dialog.P.kind)))
      | None -> (
          let* cdp = ready t in
          let* session = page_session t cdp tab in
          let browser = reading_browser t ~session tab cdp in
          let started = now t in
          let secret_values = ref args.P.secrets in
          let clean text = P.redact_string !secret_values text in
          let clean_json value = P.redact_json !secret_values value in
          let on_step = Option.map (fun callback step ->
            match P.step_of_yojson (clean_json (P.yojson_of_step step)) with Ok step -> callback step | Error _ -> ()) on_step in
          let run_args = Run.of_args args in
          let run_args = match pilot with None -> run_args | Some (pilot : Config.pilot) ->
            {run_args with max_plans = pilot.turns;
              deadline_s = Option.value ~default:pilot.deadline_s args.deadline_s} in
          let budget = float_of_int run_args.Run.deadline_s in
          let remaining () =
            Ox.Duration.ms
              (max 1 (int_of_float ((budget -. (now t -. started)) *. 1000.)))
          in
          let bounded limit text =
            if String.length text <= limit then text else String.sub text 0 limit
          in
          (* run-pvmc: the page text stays on this side of the loop; the upper levels are
             asked over the small state Run builds. *)
          (* trace-iqqz: only the selected authored book supplies declared kinds.
             Merely having a matching installed book does not classify the on-the-fly
             lane. kind-a7uy kind-dnye: a page with no declared kind is inferred, and the
             session keeps that name stable for the drive. *)
          let kinds = Page_kind.session () in
          let trace_book = ref None and trace_page = ref None in
          let declared_kind ~url ~text =
            Option.bind !trace_book (fun (book : Playbook.loaded) ->
                Playbook.page_kind book.playbook.pages ~url ~text)
          in
          let classify (snapshot : P.snapshot) text =
            let declared = declared_kind ~url:snapshot.url ~text in
            let inferred, source =
              Page_kind.classify kinds ~declared ~url:snapshot.url ~title:snapshot.title
            in
            let pattern =
              match source with
              | Page_kind.Inferred -> Some inferred.url_pattern
              | Page_kind.Declared -> None
            in
            on_page ~url:(clean snapshot.url)
              ~kind:
                (if Page_kind.is_page ~url:snapshot.url then Some (clean inferred.name) else None)
              ~pattern:(if Page_kind.is_page ~url:snapshot.url then Option.map clean pattern else None)
          in
          let label ~url ~title ~text =
            let inferred, source =
              Page_kind.classify kinds ~declared:(declared_kind ~url ~text) ~url ~title
            in
            Drive.
              {
                kind = inferred.name;
                source =
                  (match source with
                  | Page_kind.Declared -> "declared"
                  | Page_kind.Inferred -> "inferred");
                url =
                  (if !trace_book = None && Page_kind.is_page ~url then inferred.name
                   else url);
              }
          in
          let traced (snapshot : P.snapshot) text =
            trace_page := Some (snapshot, text);
            classify snapshot text
          in
          let on_book book =
            trace_book := book;
            Option.iter (fun (snapshot, text) -> classify snapshot text) !trace_page
          in
          let observe () =
            let* snapshot =
              snap_locked t tab
                P.{ tab = handle; match_ = None; limit = Some 250; offset = None }
            in
            let* rendered =
              if snapshot.P.dialog <> None then
                Ok
                  P.
                    {
                      url = snapshot.url;
                      title = snapshot.title;
                      text = "";
                      truncated = false;
                    }
              else
                Reading.text browser
                  P.{ tab = handle; index = None; max_chars = Some 12_000 }
            in
            traced snapshot (clean rendered.P.text);
            Ok
              Run.
                {
                  url = snapshot.P.url;
                  title = snapshot.P.title;
                  text = rendered.P.text;
                  dialog = snapshot.P.dialog;
                  rows =
                    List.map
                      (fun (row : P.row) -> (row.P.role, row.P.name))
                      snapshot.P.rows;
                  downloads =
                    List.map
                      (fun (download : P.download_info) ->
                        (download.P.suggested_name, download.P.mime, download.P.state))
                      (List.rev tab.downloads);
                  snapshot;
                }
          in
          (* map-3qag: the run already holds the tab lock; use the same row
             revalidation, hit-test, input and settle path as public actions. *)
          let planner_action command =
            let view = action_view t ~session tab cdp in
            match command with
            | P.Click args -> Actions.click ~cdp view args
            | P.Fill args -> Actions.fill ~check_hit:true ~cdp view args
            | P.Press args -> Actions.press ~cdp view args
            | P.Select args -> Actions.select ~cdp view args
            | P.Scroll args -> Actions.scroll ~cdp view args
            | P.Nav args ->
                let* _ = navigate_locked t ~tab args.url in
                Ok
                  P.
                    {
                      tab = handle;
                      url = tab.url;
                      title = tab.title;
                      snapshot = None;
                      dialog = tab.dialog;
                      popups = [];
                      via = None;
                    }
            | _ -> Error (error "invalid-request" "unsupported planner action")
          in
          (* run-l06s run-vbys run-xqh8: the checkers first and the JEV score only where no
             checker applies. The score is one model call per unchanged page — the bounded
             wait would otherwise ask it every 100 ms — so the answer is memoized on the
             sentence and the text it was asked over. *)
          let verify ~pages ~checks ~timeout_s =
            (* map-bjon: one judgment must not consume expect_timeout_s. Leave time
               to observe the page again after a loading frame. *)
            let expect_deadline = now t +. float_of_int timeout_s in
            let failure = ref None in
            let memo = Hashtbl.create 4 in
            let last = ref None in
            let observe_page () =
              match observe () with
              | Error _ ->
                  Playbook.
                    { kind = None; text = ""; dialog = false; rows = []; downloads = [] }
              | Ok observation ->
                  last := Some observation;
                  Playbook.
                    {
                      kind =
                        Playbook.page_kind pages ~url:observation.Run.url
                          ~text:observation.Run.text;
                      text = observation.Run.text;
                      dialog = Option.is_some observation.Run.dialog;
                      rows = observation.Run.rows;
                      downloads = observation.Run.downloads;
                    }
            in
            let score sentence (observation : Playbook.observation) =
              let key = sentence ^ "\000" ^ observation.Playbook.text in
              match Hashtbl.find_opt memo key with
              | Some value -> value
              | None ->
                  let state =
                    match !last with
                    | Some observation ->
                        `Assoc
                          [
                            ("title", `String observation.Run.title);
                            ("url", `String observation.Run.url);
                            ( "page_kind",
                              match
                                Playbook.page_kind pages ~url:observation.Run.url
                                  ~text:observation.Run.text
                              with
                              | Some kind -> `String kind
                              | None -> `Null );
                            ("text", `String (bounded 6_000 observation.Run.text));
                          ]
                    | None -> `Null
                  in
                  (* Leave time for another observation while the expect window is
                     open. Never skip the score: a run clock that has already
                     moved still has to judge the page (extr-5x9e). *)
                  let expect_left = expect_deadline -. now t in
                  let deadline =
                    if expect_left > 1. then
                      Ox.Duration.min (remaining ())
                        (Ox.Duration.ms
                           (max 1 (int_of_float (min 8. (expect_left -. 0.25) *. 1000.))))
                    else remaining ()
                  in
                  let value =
                    match levels.Run.score ~deadline ~sentence:(clean sentence) ~state:(clean_json state) with
                    | Ok value -> value
                    | Error error ->
                        if !failure = None then failure := Some error;
                        0.
                  in
                  Hashtbl.replace memo key value;
                  value
            in
            let outcome =
              Dialog_race.first (dialog_race tab) (fun () ->
                  Playbook.await_results
                    ~now:(fun () -> now t)
                    ~sleep:t.sleep ~observe:observe_page ~score ~timeout_s checks)
            in
            let results =
              match outcome with `Dialog _ -> [] | `Value results -> results
            in
            match outcome with
            | `Dialog _ ->
                let* observation = observe () in
                Ok ([], observation)
            | `Value _ -> (
                match !failure with
                | Some error -> Error error
                | None -> (
                    match !last with
                    | None -> Error (error "internal" "the verification observed nothing")
                    | Some observation ->
                        Ok
                          ( List.map
                              (fun (checked : Playbook.checked) ->
                                P.
                                  {
                                    sentence = checked.Playbook.expectation;
                                    checker =
                                      Playbook.checker_name checked.Playbook.checker;
                                    passed = checked.Playbook.passed;
                                    score = checked.Playbook.score;
                                  })
                              results,
                            observation )))
          in
          let handler : Run.handler =
            Run.
              {
                observe;
                navigate =
                  (fun url ->
                    let* _ = navigate_locked t ~tab url in
                    Ok ());
                choose =
                  (fun question -> levels.Run.choose ~deadline:(remaining ()) question);
                text_value =
                  (fun context ->
                    (match meter with
                    | Some meter -> clear_usage meter "text_helper"
                    | None -> ());
                    (text_helper ()).Text_helper.complete ~deadline:(remaining ()) (Text_helper.redact !secret_values context));
                step =
                  (fun request ->
                    drive_locked ~secrets:(fun () -> !secret_values) ~recent:request.Run.recent ?meter ?on_step
                      ~observed:(fun page -> traced page.Drive.snapshot page.text)
                      ~decide ~text_helper ~label
                      ~scripts:(fun page ->
                        request.Run.script_offers ~url:page.Drive.snapshot.url
                          ~text:page.text)
                      ~run_script:(fun ~url name -> request.Run.on_script ~url name)
                      t ~model tab
                      P.
                        {
                          tab = handle;
                          goal = request.Run.goal;
                          max_steps = Some request.Run.max_steps;
                          deadline_s = Some request.Run.deadline_s;
                          dry_run = Some request.Run.dry_run;
                        });
                verify;
                plan = (fun request -> levels.Run.plan ~deadline:(remaining ()) request);
                (* run-m0r8: a planner-written procedure that ran and passed its
                   expectations is written to XDG state here; the playbook the operator
                   authored is never written by a run, only by [playbook accept]. *)
                propose =
                  (fun ~site proc ->
                    match Playbook.propose ~caps:t.caps ~site proc with
                    | Ok path -> Ok path
                    | Error why -> Error (error "internal" why));
                hand_off =
                  (fun ~reason ->
                    (* notif-oslv: resume must acquire the lock while the run waits. *)
                    Eio.Mutex.unlock tab.lock;
                    Fun.protect
                      ~finally:(fun () ->
                        Eio.Cancel.protect (fun () -> Eio.Mutex.lock tab.lock))
                      (fun () ->
                        let* _ = handoff ~secrets:!secret_values t ~reason ~timeout_s:None handle in
                        let* tab = locate t ~access:Act handle in
                        Ok (info t tab)));
                (* extr-8o1h extr-k40c: the only script text that reaches the page in a run
                   is a loaded playbook's, through {!Reading.script}. A script that threw,
                   broke its shape or was too large is the procedure's failure; a browser
                   failure ends the run. *)
                script =
                  (fun script ~args ->
                    let started = now t in
                    (* pbk-eyya: a script reads a loaded document. A goal step that ends
                       the moment its until holds can hand over a page still streaming in
                       (the Default category's page 2 read 12 of 20 cards); the load wait
                       is bounded like every other. *)
                    if tab.page_loading && tab.dialog = None then (
                      let promise, waiter = Eio.Promise.create () in
                      tab.page_loads <- waiter :: tab.page_loads;
                      Fun.protect
                        ~finally:(fun () ->
                          tab.page_loads <-
                            List.filter (fun pending -> pending != waiter) tab.page_loads)
                        (fun () -> ignore (t.await_load promise)));
                    match Reading.script browser script ~args with
                    | Ok ran ->
                        Ok
                          (Run.Collected
                             {
                               value = ran.Reading.value;
                               records = ran.Reading.records;
                               bytes = ran.Reading.bytes;
                               elapsed_ms = ran.Reading.elapsed_ms;
                             })
                    | Error failure
                      when List.mem
                             (P.Error_code.to_string failure.P.code)
                             [ "script-failed"; "script-invalid"; "too-large" ] ->
                        Ok
                          (Run.Rejected
                             {
                               reason = failure.P.message;
                               elapsed_ms = int_of_float ((now t -. started) *. 1000.);
                             })
                    | Error failure -> Error failure);
              }
          in
          match
            match installed with
            | Some books -> Ok books
            | None -> Playbook.list ~caps:t.caps ()
          with
          | Error why -> Error (error "invalid-request" why)
          | Ok books ->
              let books =
                Option.fold ~none:books
                  ~some:(fun learning -> Learning.books learning books)
                  learning
              in
              let drafts =
                Option.fold
                  ~none:(fun ~site:_ ~kind:_ -> [])
                  ~some:(fun learning -> Learning.drafts learning)
                  learning
              in
              let challenge (_observation : Run.observation) =
                Reading.challenge_signal tab.reading
              in
              let execute on_record =
                Run.loop ~handler ~on_book ~on_record ~drafts ?learning ~secrets:args.secrets ~on_secrets:(fun values -> secret_values := values) ~planner_action
                  ~on_planner_step ~on_arguments ~planner_actions ~notify:t.notify
                  ~challenge ~challenge_attempt:t.challenge_attempt
                  ~challenge_turns:t.challenge_turns
                  ~pause_ms:(fun ms -> t.sleep (float_of_int ms /. 1000.))
                  ~now:(fun () -> now t)
                  ~page_kinds:kinds ~installed:books run_args
              in
              let* result =
                match args.P.out with
                | None -> execute (fun _ -> Ok ())
                | Some path -> (
                    try
                      let channel = Ox_caps.Cap_stdlib.open_out ~caps:t.caps path in
                      Fun.protect
                        ~finally:(fun () -> close_out channel)
                        (fun () ->
                          execute (fun record ->
                              try
                                output_string channel (Yojson.Safe.to_string record);
                                output_char channel '\n';
                                flush channel;
                                Ok ()
                              with Sys_error why -> Error (error "internal" why)))
                    with Sys_error why -> Error (error "invalid-request" why))
              in
              Ok result))

(* extr-mp5z extr-lslp: the playbook commands that need a page. The script is looked up in
   the playbook directory by name — nothing on the wire carries script text — and [installed]
   hands a control test its playbooks the way it does a run's. *)
let find_playbook ~caps ?installed name =
  match installed with
  | Some books -> (
      match
        List.find_opt
          (fun (book : Playbook.loaded) ->
            Option.map Filename.basename book.Playbook.dir = Some name)
          books
      with
      | Some book -> Ok book
      | None ->
          Error
            (error "invalid-request" (Printf.sprintf "no playbook %s is installed" name)))
  | None -> (
      match Playbook.show ~caps name with
      | Ok book -> Ok book
      | Error why -> Error (error "invalid-request" why))

let script_arguments = function
  | None -> Ok []
  | Some (`Assoc fields) ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (name, `String value) :: rest -> go ((name, value) :: acc) rest
        | (name, _) :: _ ->
            Error
              (error "invalid-request"
                 (Printf.sprintf "argument %s must be a string" name))
      in
      go [] fields
  | Some _ -> Error (error "invalid-request" "args must be an object of strings")

let echo_limit = 1_048_576

let playbook_test ?installed t (args : P.playbook_test_args) =
  let* playbook, name =
    match String.split_on_char '/' args.script with
    | [ playbook; script ] when playbook <> "" && script <> "" -> Ok (playbook, script)
    | _ -> Error (error "invalid-request" "script must be <playbook>/<script>")
  in
  let* book = find_playbook ~caps:t.caps ?installed playbook in
  let* script =
    match Playbook.script_named book name with
    | Some script -> Ok script
    | None ->
        Error
          (error "invalid-request"
             (Printf.sprintf "playbook %s has no script %s" playbook name))
  in
  let* arguments = script_arguments args.args in
  with_reading t ~access:Act args.tab (fun _ browser ->
      let* ran = Reading.script browser script ~args:arguments in
      let value, truncated =
        if ran.Reading.bytes <= echo_limit then (ran.Reading.value, false)
        else
          match ran.Reading.value with
          | `List items -> (`List (List.filteri (fun i _ -> i < 5) items), true)
          | _ -> (`Null, true)
      in
      Ok
        P.
          {
            script = args.script;
            value;
            records = ran.Reading.records;
            bytes = ran.Reading.bytes;
            elapsed_ms = ran.Reading.elapsed_ms;
            truncated;
          })

(* extr-lslp: every script of the playbook is compiled, never called, in a blank page of
   its own that the caller owns for the duration and that is closed after. *)
let playbook_check ?installed t (args : P.playbook_check_args) =
  let* book = find_playbook ~caps:t.caps ?installed args.playbook in
  match book.Playbook.scripts with
  | [] -> Ok P.{ playbook = args.playbook; scripts = [] }
  | scripts -> (
      let* blank = new_tab t ~url:None in
      let close () = Eio.Cancel.protect (fun () -> ignore (close t blank.P.tab)) in
      match
        with_reading t ~access:Act blank.P.tab (fun _ browser ->
            let rec go acc = function
              | [] -> Ok (List.rev acc)
              | (script : Playbook.script) :: rest -> (
                  match Reading.script_syntax browser script with
                  | Error failure -> Error failure
                  | Ok verdict ->
                      go
                        (P.
                           {
                             script = script.Playbook.name;
                             ok = verdict = None;
                             error = verdict;
                           }
                        :: acc)
                        rest)
            in
            go [] scripts)
      with
      | exception exn ->
          close ();
          raise exn
      | Error failure ->
          close ();
          Error failure
      | Ok verdicts ->
          close ();
          Ok P.{ playbook = args.playbook; scripts = verdicts })

let report t : P.status_result =
  let chrome = Chrome.status t.chrome in
  {
    generation = chrome.generation;
    tabs = { open_ = open_tabs t; cap = t.cap };
    chrome =
      enum P.Chrome_phase.of_string
        (if chrome.phase = `Running then "running" else "restarting");
    uptime_s = max 0. (now t -. t.started);
    (* L19: the models section belongs to the models service, which the control listener
       merges in before the reply goes out; the registry has no opinion about it. *)
    models = None;
    version = Version.version;
    pid = None;
    headed = chrome.headed;
    key_present = false;
    learning = None;
  }

let status t =
  let state =
    match (Chrome.status t.chrome).phase with
    | `Running -> Ox_app.Status.Ok
    | _ -> Ox_app.Status.Degraded "Chrome restarting"
  in
  Ox_app.Status.make
    ~details:[ ("open", string_of_int (open_tabs t)); ("cap", string_of_int t.cap) ]
    "tabs" state

(* run-ykq4: browser-level events carry the main frame id; page-level legacy
   events carry a session. Never credit an unattributed download to another tab. *)
let progress_bytes key params previous =
  match member key params with
  | Some (`Int bytes) when bytes >= 0 -> bytes
  | Some (`Float bytes)
    when Float.is_finite bytes && bytes >= 0. && bytes < float_of_int max_int ->
      int_of_float bytes
  | _ -> previous

let download_event t json method_ params =
  let session = text "sessionId" json in
  match method_ with
  | "Browser.downloadWillBegin" | "Page.downloadWillBegin" -> (
      match (text "guid" params, text "suggestedFilename" params) with
      | Some id, Some suggested_name ->
          let frame = text "frameId" params in
          let target =
            List.fold_left
              (fun found (tab : tab) ->
                if
                  match frame with
                  | Some frame -> tab.main_frame = Some frame
                  | None -> session <> None && tab.session = session
                then Some tab
                else found)
              None (live_tabs t)
          in
          Option.iter
            (fun (tab : tab) ->
              let mime =
                if String.ends_with ~suffix:".pdf" (String.lowercase_ascii suggested_name)
                then "application/pdf"
                else "application/octet-stream"
              in
              if
                not
                  (List.exists
                     (fun (download : P.download_info) -> download.id = id)
                     tab.downloads)
              then (
                tab.downloads <-
                  P.
                    {
                      id;
                      suggested_name;
                      mime;
                      state = "in_progress";
                      received_bytes = 0;
                      total_bytes = 0;
                      path = None;
                    }
                  :: tab.downloads;
                Hashtbl.replace t.downloads_by_guid id (key (credential tab))))
            target
      | _ -> ())
  | "Browser.downloadProgress" | "Page.downloadProgress" -> (
      match (text "guid" params, text "state" params) with
      | Some id, Some cdp_state ->
          let state =
            match cdp_state with "inProgress" -> "in_progress" | other -> other
          in
          Option.iter
            (fun handle ->
              Option.iter
                (fun (tab : tab) ->
                  tab.downloads <-
                    List.map
                      (fun (download : P.download_info) ->
                        if download.id <> id then download
                        else
                          {
                            download with
                            state;
                            received_bytes =
                              progress_bytes "receivedBytes" params
                                download.received_bytes;
                            total_bytes =
                              progress_bytes "totalBytes" params download.total_bytes;
                            path =
                              (if state = "completed" then text "filePath" params
                               else None);
                          })
                      tab.downloads)
                (Option.map
                   (fun entry -> entry.tab)
                   (Keys.find_opt handle (snapshot t).entries)))
            (Hashtbl.find_opt t.downloads_by_guid id)
      | _ -> ())
  | _ -> ()

let downloads t handle =
  let* tab = locate t ~access:Act handle in
  Ok P.{ downloads = List.rev tab.downloads }

let inspect t json =
  (match text "sessionId" json with
  | None -> ()
  | Some session ->
      iter_tabs t (fun (tab : tab) ->
          if tab.session = Some session then Reading.observe tab.reading ~at:(now t) json));
  (match (text "method" json, member "params" json) with
  | Some method_, Some params -> download_event t json method_ params
  | _ -> ());
  match (text "method" json, member "params" json) with
  | Some ("Target.targetCreated" | "Target.targetInfoChanged"), Some params -> (
      (* own-c0cl: the announcement every target Chrome reports arrives as, the ones Leash
         itself asked for included — [discover] tells them apart by the pending table. *)
      match Discovery.announced params with
      | Some info -> discover t ~session:None info
      | None -> ())
  | Some "Target.attachedToTarget", Some params -> (
      match Discovery.attached params with
      | Some info -> discover t ~session:info.session info
      | None -> ())
  | Some "Target.targetDestroyed", Some params -> (
      (* own-teh1: a target that goes away without Leash closing it is gone externally. A
         tab Leash closed left the registry when it issued the close, so its tombstone
         keeps closed_by_handle (or, with the TTL sweep, closed_by_idle) and this report
         finds no live tab to rewrite. *)
      match Discovery.destroyed params with
      | Some id -> (
          match tab_of_target t id with
          | Some tab ->
              (* tab-0ohq own-teh1: a tab's death settles the dispatch whose handler closed
                 it -- [tab-gone] with [closed_externally], the same answer the handle reads
                 from the tombstone afterwards -- before the tab leaves the registry. *)
              wake tab (Dispatch.Gone (P.tab_gone (disposition "closed_externally")));
              disappear t tab (disposition "closed_externally")
          | None -> ())
      | None -> ())
  | Some "Page.javascriptDialogOpening", Some params ->
      iter_tabs t (fun (tab : tab) ->
          if tab.session = text "sessionId" json then
            match (text "type" params, text "message" params) with
            | Some kind, Some message ->
                let dialog =
                  P.
                    {
                      kind = enum P.Dialog_kind.of_string kind;
                      message;
                      default_prompt = text "defaultPrompt" params;
                    }
                in
                tab.dialog <- Some dialog;
                List.iter (fun notify -> notify dialog) tab.dialog_listeners
            | _ -> ())
  | Some "Page.javascriptDialogClosed", _ ->
      iter_tabs t (fun (tab : tab) ->
          if tab.session = text "sessionId" json then tab.dialog <- None)
  | Some "Page.frameNavigated", Some params -> (
      (* svc-hi4f: a main-frame navigation is what clears the tab's snapshot and what an
          action's watch counts; a subframe's is neither. *)
      let main_frame =
        match member "frame" params with
        | Some frame -> text "parentId" frame = None
        | None -> false
      in
      iter_tabs t (fun (tab : tab) ->
          if main_frame && tab.session = text "sessionId" json then (
            tab.main_frame <- Option.bind (member "frame" params) (text "id");
            tab.snapshot <- None;
            tab.navigations <- tab.navigations + 1;
            tab.page_loading <- true));
      match text "sessionId" json with
      | Some session ->
          iter_tabs t (fun (tab : tab) ->
              if tab.session = Some session && tab.loading then tab.navigated <- true)
      | None -> ())
  | Some (("Page.loadEventFired" | "Page.domContentEventFired") as event), Some params
    -> (
      match text "sessionId" json with
      | None -> ()
      | Some session ->
          iter_tabs t (fun (tab : tab) ->
              if tab.session = Some session then (
                if
                  tab.loading
                  && (event = "Page.loadEventFired"
                     || (event = "Page.domContentEventFired" && tab.navigated))
                then (
                  tab.completed <- true;
                  match tab.load_waiter with
                  | None -> ()
                  | Some waiter ->
                      tab.load_waiter <- None;
                      Eio.Promise.resolve waiter ());
                (* svc-hi4f: the watch an action armed before it dispatched waits for the
                   navigation it counted to finish before its reply reads the title. *)
                if tab.page_loading then (
                  tab.page_loading <- false;
                  let pending = tab.page_loads in
                  tab.page_loads <- [];
                  List.iter (fun resolve -> Eio.Promise.resolve resolve ()) pending))))
  | Some "Page.navigatedWithinDocument", Some params ->
      iter_tabs t (fun (tab : tab) ->
          if tab.session = text "sessionId" json then
            let frame = text "frameId" params in
            let main =
              match (tab.main_frame, frame) with
              | None, _ -> true
              | Some id, Some frame -> id = frame
              | Some _, None -> false
            in
            if main then (
              tab.same_document <- tab.same_document + 1;
              Option.iter (fun url -> tab.url <- url) (text "url" params)))
  | Some "Network.requestWillBeSent", Some params -> (
      match text "requestId" params with
      | None -> ()
      | Some id ->
          iter_tabs t (fun (tab : tab) ->
              if tab.session = text "sessionId" json then (
                tab.net_seq <- tab.net_seq + 1;
                Hashtbl.replace tab.inflight id tab.net_seq)))
  | ( Some
        ( "Network.loadingFinished" | "Network.loadingFailed"
        | "Network.requestServedFromCache" ),
      Some params ) -> (
      match text "requestId" params with
      | None -> ()
      | Some id ->
          iter_tabs t (fun (tab : tab) ->
              if tab.session = text "sessionId" json then Hashtbl.remove tab.inflight id))
  | _ -> ()

let create ~sw ~cap ~tombstone_s ?download_dir ?(notify = fun _ -> Ok ())
    ?(handoff_timeout_s = 300) ?(challenge_attempt = true) ?(challenge_turns = 2)
    ?(idle = Ox.Duration.minutes 30) (deps : 'clock deps) =
  (* ^nactor-8z1n: the registry's bookkeeping is one actor's state, folded by [fold], for
     as long as the switch lives. A handler that raises fails the switch. *)
  let ledger =
    Ox.Actor.create ~sw ~init:empty_ledger
      ~handle:
        (fold
           ~fresh:(fun () -> handle ~caps:deps.caps)
           ~logger:deps.logger ~tombstone_s
           ~generation:(fun () -> Chrome.generation deps.chrome))
      ()
  in
  let t =
    {
      chrome = deps.chrome;
      caps = deps.caps;
      now = (fun () -> Eio.Time.now deps.clock);
      sleep = (fun seconds -> Eio.Time.sleep deps.clock seconds);
      await_load =
        (fun promise ->
          Ox.Timeout.timeout ~clock:deps.clock (Ox.Duration.seconds 30) (fun () ->
              Eio.Promise.await promise;
              Ok ()));
      (* hand-lmd5: the handoff deadline, measured by the service clock and cancelled —
         not raced — when it runs out, so the restore of {!handoff} still runs. *)
      await_handoff =
        (fun timeout promise ->
          Ox.Timeout.timeout ~clock:deps.clock timeout (fun () ->
              Eio.Promise.await promise;
              Ok ()));
      desktop = deps.desktop;
      notify;
      handoff_timeout_s;
      challenge_attempt;
      challenge_turns;
      logger = deps.logger;
      download_dir;
      downloads_by_guid = Hashtbl.create 32;
      cap;
      tombstone_s;
      (* own-vhqo: the two expiry durations are config; the ADR's defaults stand in when a
         caller does not name them, which is what a test registry gets. *)
      idle = Ox.Duration.to_seconds_float idle;
      started = Eio.Time.now deps.clock;
      ledger;
      stopping = false;
    }
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      let rec lifecycle () : [ `Stop_daemon ] =
        (match Eio.Stream.take (Chrome.events t.chrome) with
        | Chrome.Started _ -> (
            match ready t with
            | Ok cdp ->
                let setup_target = ref None in
                Eio.Fiber.fork_daemon ~sw (fun () ->
                    let rec notifications () : [ `Stop_daemon ] =
                      match Eio.Stream.take (Cdp.events cdp) with
                      | Ox_rpc.Correlator.Message json ->
                          let announced =
                            Option.bind (member "params" json) (fun params ->
                                Option.bind (member "targetInfo" params) (text "targetId"))
                          in
                          (* field-drpx: a popup opened by a page (Google's "Continue with
                             Google") is auto-attached paused — Chrome 152 shows "Debugger
                             paused in another tab" and the popup stays blank — even though
                             waitForDebuggerOnStart is false and the event says
                             waitingForDebugger:false. Resuming is a no-op for a target that
                             is running, so every attached target is resumed, off this event
                             fiber. Verified live 2026-10-01: the popup reached
                             accounts.google.com only with this. *)
                          (match (text "method" json, member "params" json) with
                          | Some "Target.attachedToTarget", Some params -> (
                              match text "sessionId" params with
                              | Some session ->
                                  Eio.Fiber.fork_daemon ~sw (fun () ->
                                      ignore
                                        (cdp_call ~deadline:(Ox.Duration.seconds 5)
                                           ~session cdp "Runtime.runIfWaitingForDebugger"
                                           (obj []));
                                      `Stop_daemon)
                              | None -> ())
                          | _ -> ());
                          if announced = None || announced <> !setup_target then
                            inspect t json;
                          notifications ()
                      | Ox_rpc.Correlator.Closed _ -> `Stop_daemon
                    in
                    notifications ());
                Option.iter
                  (fun download_dir ->
                    (match
                       Download_setup.prepare ~clock:deps.clock ~cdp
                         ~on_target:(fun target -> setup_target := Some target)
                     with
                    | Ok () -> ()
                    | Error _ ->
                        Ox_observability.Logger.warn t.logger
                          "daily-c4cl: download history bootstrap failed; continuing \
                           setup");
                    match
                      cdp_call cdp "Browser.setDownloadBehavior"
                        (obj
                           [
                             ("behavior", str "allow");
                             ("downloadPath", str download_dir);
                             ("eventsEnabled", `Bool true);
                           ])
                    with
                    | Ok _ -> ()
                    | Error _ ->
                        Ox_observability.Logger.warn t.logger
                          "run-ykq4: Browser.setDownloadBehavior failed; downloads \
                           unavailable")
                  t.download_dir;
                ignore
                  (cdp_call cdp "Target.setDiscoverTargets"
                     (obj [ ("discover", `Bool true) ]));
                ignore
                  (cdp_call cdp "Target.setAutoAttach"
                     (obj
                        [
                          ("autoAttach", `Bool true);
                          ("waitForDebuggerOnStart", `Bool false);
                          ("flatten", `Bool true);
                        ]))
            | Error _ -> ())
        | Chrome.Lost generation ->
            List.iter
              (fun (tab : tab) ->
                if tab.generation = generation then
                  disappear t tab (disposition "browser_lost"))
              (live_tabs t)
        | Chrome.Gave_up _ | Chrome.Stopped -> ());
        lifecycle ()
      in
      lifecycle ());
  t

let stop t =
  if not t.stopping then (
    t.stopping <- true;
    match ready t with
    | Error _ -> ()
    | Ok cdp ->
        List.iter
          (fun (tab : tab) ->
            if P.Origin.to_string tab.origin = "agent" then
              ignore
                (cdp_call cdp "Target.closeTarget" (obj [ ("targetId", str tab.id) ])))
          (live_tabs t))

let text = read_text
