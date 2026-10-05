(* ^safe-pufa: this allow-list is policy, not a general lint suppression channel. *)
open Ocaml_common
open Parsetree

type decision = {
  id : string;
  scope : Location.t;
  site : Location.t;
  mutable used : bool;
}

type t = {
  origin : string -> string;
  source : string;
  mutable checked : string option;
  known : string list;
  enabled : string list;
  mutable decisions : decision list;
  mutable invalid : (Location.t * string) list;
}

let eligible = [ "ox-discarded-result"; "ox-partial-option"; "ox-partial-list" ]

let normalize path =
  String.split_on_char '/' path
  |> List.fold_left
       (fun parts -> function
         | "" | "." -> parts
         | ".." -> ( match parts with [] -> [] | _ :: rest -> rest)
         | part -> part :: parts)
       []
  |> List.rev |> String.concat "/"
  |> fun path -> "/" ^ path

let create ~root ~source ~known ~enabled =
  let absolute path =
    normalize
      (if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path)
  in
  let root = absolute root in
  let root =
    if Filename.check_suffix root "/_build/default" then
      Filename.dirname (Filename.dirname root)
    else root
  in
  let canonical path =
    let path = normalize path in
    let build = root ^ "/_build/default/" in
    if String.starts_with ~prefix:build path then
      root ^ "/"
      ^ String.sub path (String.length build) (String.length path - String.length build)
    else path
  in
  let expected = canonical (absolute source) in
  let origin name =
    if name = source then expected
    else canonical (if Filename.is_relative name then Filename.concat root name else name)
  in
  {
    origin;
    source = expected;
    checked = None;
    known;
    enabled;
    decisions = [];
    invalid = [];
  }

let checked_source t ~filename = t.checked <- Some filename
let reject t attr message = t.invalid <- (attr.attr_loc, message) :: t.invalid

let add t scope attr =
  if attr.attr_name.txt = "ox.allow" then
    match attr.attr_payload with
    | PStr
        [
          {
            pstr_desc =
              Pstr_eval
                ( {
                    pexp_desc =
                      Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ };
                    _;
                  },
                  [] );
            _;
          };
        ] -> (
        match String.index_opt text ':' with
        | None -> reject t attr "expected ox.allow \"RULE: nonempty reason\""
        | Some colon ->
            let id = String.sub text 0 colon |> String.trim in
            let reason =
              String.sub text (colon + 1) (String.length text - colon - 1) |> String.trim
            in
            if not (List.mem id eligible) then
              reject t attr ("rule is not eligible for policy exceptions: " ^ id)
            else if not (List.mem id t.known) then
              reject t attr ("rule is not installed: " ^ id)
            else if reason = "" then reject t attr "ox.allow requires a nonempty reason"
            else
              t.decisions <-
                { id; scope; site = attr.attr_loc; used = false } :: t.decisions)
    | _ -> reject t attr "expected ox.allow \"RULE: nonempty reason\""

let collect t (base : Ast_iterator.iterator) =
  let scoped = ref [] in
  let register scope attrs =
    List.iter
      (fun attr ->
        if attr.attr_name.txt = "ox.allow" then begin
          scoped := attr.attr_loc :: !scoped;
          add t scope attr
        end)
      attrs
  in
  {
    base with
    expr =
      (fun self e ->
        register e.pexp_loc e.pexp_attributes;
        base.expr self e);
    value_binding =
      (fun self vb ->
        register vb.pvb_loc vb.pvb_attributes;
        base.value_binding self vb);
    attribute =
      (fun self attr ->
        if attr.attr_name.txt = "ox.allow" && not (List.mem attr.attr_loc !scoped) then
          reject t attr "ox.allow must be attached to one expression or value binding";
        base.attribute self attr);
  }

let contains t scope loc =
  let origin name = if t.checked = Some name then t.source else t.origin name in
  (not scope.Location.loc_ghost)
  && (not loc.Location.loc_ghost)
  && origin scope.loc_start.pos_fname = t.source
  && origin scope.loc_end.pos_fname = t.source
  && origin loc.loc_start.pos_fname = t.source
  && origin loc.loc_end.pos_fname = t.source
  &&
  let coordinate position =
    (position.Lexing.pos_lnum, position.pos_cnum - position.pos_bol)
  in
  coordinate scope.loc_start <= coordinate loc.loc_start
  && coordinate loc.loc_end <= coordinate scope.loc_end

let allows t ~id loc =
  if not (List.mem id eligible && List.mem id t.enabled) then false
  else
    let candidates =
      List.filter (fun d -> d.id = id && contains t d.scope loc) t.decisions
    in
    let width d = d.scope.loc_end.pos_cnum - d.scope.loc_start.pos_cnum in
    match List.sort (fun a b -> Int.compare (width a) (width b)) candidates with
    | [] -> false
    | d :: _ ->
        d.used <- true;
        true

let finish t ~complete emit =
  List.iter (fun (loc, message) -> emit loc message) (List.rev t.invalid);
  if complete then
    List.iter
      (fun d ->
        if List.mem d.id t.enabled && not d.used then
          emit d.site ("unused ox.allow for enabled rule " ^ d.id))
      (List.rev t.decisions)
