(* ^safe-pufa: installed policy contract. *)
let run () = (Obj.magic 1 : int) [@ox.allow "ox-obj-magic: reason"]
