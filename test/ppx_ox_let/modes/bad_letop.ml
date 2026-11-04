(* ^nlet-4eh4: the same program through let* is refused; this is why the rewriter exists. *)
(* expect: letop *)
open Ox.Result.Syntax

let use (s : int ref @ local) (r : (int, string) result) =
  let* x = r in
  s := x;
  Ok ()
