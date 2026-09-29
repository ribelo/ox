module Q = Ox_sql

module Users = struct
  module T = Q.Table.Make (struct
    let name = "users"
  end)

  include T

  let id = column "id" Q.int
  let name = column "name" Q.text
end

module Posts = struct
  module T = Q.Table.Make (struct
    let name = "posts"
  end)

  include T

  let id = column "id" Q.int
  let title = column "title" Q.text
end

(* ^sqlhet-lusj: a conflict target may mix value types but never tables. *)
let _bad_conflict_target =
  Q.Insert.(
    into Users.table |> value Users.id 1 |> value Users.name "Ada"
    |> on_conflict_do_nothing [ Q.Column.any Posts.id ])
