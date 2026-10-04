(* ^ncapslint-8jcy: payload shape must not turn ambient tokens into arguments. *)
type script_dir = (Ox_caps.Cap.fs_read * string) option

let door_slot : script_dir ref = ref None

let via_global_slot name =
  match !door_slot with
  | None -> ""
  | Some (caps, root) ->
      Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps (Filename.concat root name)
        In_channel.input_all

type deps = { caps : Ox_caps.Cap.fork }
type authority = [ `Ready of deps option ]

let ambient : authority = `Ready (Some { caps = Obj.magic () })

let via_global_payload () =
  match ambient with
  | `Ready None -> 0
  | `Ready (Some deps) -> Ox_caps.Cap_unix.fork ~caps:deps.caps ()

let impostor_payload (source : (< fork : int > * string) option) =
  match source with
  | None -> 0
  | Some (caps, _) ->
      ignore caps;
      Unix.fork ()

let minted_payload () =
  let source = Some (Ox_caps_door.powerbox (), ".") in
  match source with None -> 0 | Some (caps, _) -> Ox_caps.Cap_unix.fork ~caps ()

let unrelated_argument ~caps () =
  ignore (caps : Ox_caps.Cap.fork);
  match ambient with
  | `Ready None -> 0
  | `Ready (Some deps) -> Ox_caps.Cap_unix.fork ~caps:deps.caps ()

type 'a phantom = Phantom

let phantom_payload (_ : Ox_caps.Cap.fork phantom) () = Unix.fork ()

type recursive_impostor = Next of recursive_impostor | Fake of < fork : int >

let recursive_payload (_ : recursive_impostor) () = Unix.fork ()
let global_pair : Ox_caps.Cap.fork * string = (Obj.magic (), ".")
let via_global_projection () = Ox_caps.Cap_unix.fork ~caps:(fst global_pair) ()

let via_shadowed_projection source () =
  let fst _ : Ox_caps.Cap.fork = Obj.magic () in
  Ox_caps.Cap_unix.fork ~caps:(fst source) ()

exception Ambient_exception of Ox_caps.Cap.fork

let via_exception (source : unit option) () =
  match source with
  | None | Some () -> 0
  | exception Ambient_exception caps -> Ox_caps.Cap_unix.fork ~caps ()

type recursive_poly = [ `Again of recursive_poly | `Fake of < fork : int > ]

let recursive_poly_payload (_ : recursive_poly) () = Unix.fork ()

let via_ambient_bind () =
  let ( let* ) = Result.bind in
  let* caps, _ = Ok global_pair in
  Ok (Ox_caps.Cap_unix.fork ~caps ())

let via_fake_bind (source : Ox_caps.Cap.fork option) () =
  let ( let* ) _ f = f (Obj.magic ()) in
  let* caps = source in
  Ox_caps.Cap_unix.fork ~caps ()

(* Inn obtains a record from its global slot, then projects [(door ()).caps]. *)
let inn_door_slot : deps option ref = ref None

let door () =
  match !inn_door_slot with Some door -> door | None -> invalid_arg "no door"

let via_global_getter () =
  let caps = (door ()).caps in
  Ox_caps.Cap_unix.fork ~caps ()
