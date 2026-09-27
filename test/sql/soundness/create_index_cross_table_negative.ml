module Q = Eta_sql

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

(* ^sqlhet-lusj: [Column.any] erases a column's value type but keeps its phantom
   table identity, so an index column list cannot borrow another table's
   column even though the list is heterogeneous. *)
let _bad_index =
  Q.Eta_schema.create_index ~name:"users_by_title" Users.table
    [ Q.Column.any Posts.title ]
