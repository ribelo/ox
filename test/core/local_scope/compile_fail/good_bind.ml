(* ^nlscope-dodx: forks after a let%bind, a nested scope, and a spawner for later. *)
let later : string Ox.Spawner.t option ref = ref None

let body ~sw (r : (int, string) result) =
  Ox.Scope.supervised ~sw (fun scope ->
      let%bind x = r in
      Ox.Scope.fork scope (fun () -> ignore x);
      later := Some (Ox.Scope.spawner scope);
      let%map nested =
        Ox.Scope.supervised ~sw:(Ox.Scope.switch scope) (fun inner ->
            Ox.Scope.fork inner (fun () -> ());
            Ok (x + 1))
      in
      nested)
