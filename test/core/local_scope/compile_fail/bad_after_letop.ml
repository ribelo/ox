(* ^nlscope-dodx: let* cannot carry the scope; let%bind can. *)
(* expect: letop *)
open Ox.Result.Syntax

let body ~sw (r : (int, string) result) =
  Ox.Scope.supervised ~sw (fun scope ->
      let* x = r in
      Ox.Scope.fork scope (fun () -> ignore x);
      Ok ())
