(* ^nlet-4eh4: after let%bind a local value still cannot be stored. *)
(* expect: local *)
let leak : int ref ref = ref (ref 0)

let use (s : int ref @ local) (r : (int, string) result) =
  let%bind x = r in
  s := x;
  leak := s;
  Ok ()
