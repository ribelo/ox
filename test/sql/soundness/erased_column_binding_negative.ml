module Q = Ox_sql

module Users = struct
  module T = Q.Table.Make (struct
    let name = "users"
  end)

  include T

  let id = column "id" Q.int
  let name = column "name" Q.text
end

(* Erasure is construction-only: [Column.any] drops the value type, so an
   erased column cannot be bound as an insert parameter. *)
let _bad_binding = Q.Insert.(into Users.table |> value (Q.Column.any Users.id) 1)
