(* ^nspawn-lhyg: [Ox.Spawner] is [Scope.Spawner]; defining it in [Scope] avoids a
   Scope-Spawner dependency cycle. *)
include Scope.Spawner
