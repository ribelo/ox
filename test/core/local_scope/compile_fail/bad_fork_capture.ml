(* ^nlscope-dodx: a fork capturing the scope is refused; it takes a spawner instead. *)
(* expect: local *)
let body ~sw =
  Ox.Scope.supervised ~sw (fun scope ->
      Ox.Scope.fork scope (fun () -> Ox.Scope.fork scope (fun () -> ()));
      Ok ())
