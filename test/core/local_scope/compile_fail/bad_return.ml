(* ^nlscope-dodx: returning the scope is refused. *)
(* expect: local *)
let body ~sw = Ox.Scope.supervised ~sw (fun scope -> Ok scope)
