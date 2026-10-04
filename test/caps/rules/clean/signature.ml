(* ^ncapslint-8jcy: real tokens, explicit and captured argument authority. *)
let visible ~caps () = Ox_caps.Cap_unix.fork ~caps ()

let create ~caps =
  let hidden () = Ox_caps.Cap_unix.fork ~caps () in
  hidden

type deps = { caps : Ox_caps.Cap.fork }

let via_record (deps : deps) () = Ox_caps.Cap_unix.fork ~caps:deps.caps ()

let via_alias ~caps () =
  let alias = caps in
  Ox_caps.Cap_unix.fork ~caps:alias ()

(* Leash carries file authority with the directory, inside an option of a tuple. *)
type script_dir = (Ox_caps.Cap.fs_read * string) option

let read_script_file ~(dir : script_dir) name =
  match dir with
  | None -> ""
  | Some (caps, root) ->
      Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps (Filename.concat root name)
        In_channel.input_all

let read_sidecar ~(dir : script_dir) name =
  let directory = dir in
  match directory with
  | None -> ""
  | Some (caps, root) ->
      let authority = caps in
      Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps:authority
        (Filename.concat root name) In_channel.input_all

(* Constructor/variant payloads and record fields compose at arbitrary depth. *)
type authority = Ready of (deps * string) option | Absent
type envelope = { payload : [ `Authority of authority option ] }

let via_record_in_variant source () =
  match source with
  | Ready (Some ({ caps }, _)) -> Ox_caps.Cap_unix.fork ~caps ()
  | Ready None | Absent -> 0

let via_nested_payload (source : envelope) () =
  match source.payload with
  | `Authority (Some (Ready (Some (deps, _)))) ->
      let caps = deps.caps in
      Ox_caps.Cap_unix.fork ~caps ()
  | `Authority (None | Some (Ready None | Absent)) -> 0

let via_function_cases = function
  | Ready (Some (deps, _)) -> Ox_caps.Cap_unix.fork ~caps:deps.caps ()
  | Ready None | Absent -> 0

let via_tuple_parameter (({ caps }, _) : deps * string) () =
  Ox_caps.Cap_unix.fork ~caps ()

let via_raw_payload source () =
  match source with
  | Ready (Some ({ caps }, _)) ->
      ignore caps;
      Unix.fork ()
  | Ready None | Absent -> 0

let via_nested_options (source : Ox_caps.Cap.fork option option) () =
  ignore source;
  Unix.fork ()

type 'a packaged = { data : 'a }
type 'a carrier = Carried of 'a packaged | Empty

let via_generic_payload (source : Ox_caps.Cap.fork carrier) () =
  ignore source;
  Unix.fork ()

type recursive_authority = Next of recursive_authority | Leaf of deps

let via_recursive_payload (source : recursive_authority) () =
  ignore source;
  Unix.fork ()

type 'a object_deps = { authority : < fork : 'a > }

let via_generic_token (source : Ox_caps.Cap.Token.fork object_deps) () =
  ignore source;
  Unix.fork ()

let via_fst source () =
  let caps = Stdlib.fst source in
  Ox_caps.Cap_unix.fork ~caps ()

let via_snd source () = Ox_caps.Cap_unix.fork ~caps:(snd source) ()

(* Leash's first reader also passes the extracted pair through Result.bind. *)
let via_result_bind ~(dir : script_dir) name =
  let ( let* ) = Result.bind in
  let* caps, root =
    match dir with None -> Error "no directory" | Some pair -> Ok pair
  in
  let path = Unix.realpath (Filename.concat root name) in
  Ok (Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps path In_channel.input_all)

(* A projected binder is checked at its instantiated type even when recursive
   declaration expansion cannot expose authority from the unprojected root. *)
type 'a growing = End of 'a | Grow of ('a * deps) growing

let via_projected_recursive (source : unit growing) () =
  match source with
  | Grow (End (_, deps)) ->
      ignore deps;
      Unix.fork ()
  | _ -> 0

type recursive_poly = [ `Again of recursive_poly | `Authorized of deps ]

let via_recursive_poly (source : recursive_poly) () =
  ignore source;
  Unix.fork ()

(* ^ncapslint-8jcy: identical declared fields under distinct substitutions must
   not share a negative visited state. *)
type 'token generic_holder = { holder : < fork : 'token > }

let via_distinct_substitutions
    (source : int generic_holder * Ox_caps.Cap.Token.fork generic_holder) () =
  ignore source;
  Unix.fork ()

(* ^ncapslint-8jcy: shared projection DAG, not an exponentially unfolded tree. *)
type shared0 = unit
type shared1 = Graph_left1 of shared0 | Graph_right1 of shared0
type shared2 = Graph_left2 of shared1 | Graph_right2 of shared1
type shared3 = Graph_left3 of shared2 | Graph_right3 of shared2
type shared4 = Graph_left4 of shared3 | Graph_right4 of shared3
type shared5 = Graph_left5 of shared4 | Graph_right5 of shared4
type shared6 = Graph_left6 of shared5 | Graph_right6 of shared5
type shared7 = Graph_left7 of shared6 | Graph_right7 of shared6
type shared8 = Graph_left8 of shared7 | Graph_right8 of shared7
type shared9 = Graph_left9 of shared8 | Graph_right9 of shared8
type shared10 = Graph_left10 of shared9 | Graph_right10 of shared9
type shared11 = Graph_left11 of shared10 | Graph_right11 of shared10
type shared12 = Graph_left12 of shared11 | Graph_right12 of shared11
type shared13 = Graph_left13 of shared12 | Graph_right13 of shared12
type shared14 = Graph_left14 of shared13 | Graph_right14 of shared13
type shared15 = Graph_left15 of shared14 | Graph_right15 of shared14
type shared16 = Graph_left16 of shared15 | Graph_right16 of shared15
type shared17 = Graph_left17 of shared16 | Graph_right17 of shared16
type shared18 = Graph_left18 of shared17 | Graph_right18 of shared17

let via_shared_graph source =
  let selected = match source with Graph_left18 value | Graph_right18 value -> value in
  ignore selected
