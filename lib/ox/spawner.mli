(** The storable fork authority of a scope: {!Scope.Spawner}, obtained with
    {!Scope.spawner}. ^nspawn-lhyg *)

include module type of struct
  include Scope.Spawner
end
