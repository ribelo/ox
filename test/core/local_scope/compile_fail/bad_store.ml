(* ^nlscope-dodx: storing the scope is refused. *)
(* expect: local *)
let kept : string Ox.Scope.t option ref = ref None

let body ~sw =
  Ox.Scope.supervised ~sw (fun scope ->
      kept := Some scope;
      Ok ())
