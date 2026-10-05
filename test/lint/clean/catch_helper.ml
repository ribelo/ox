(* ^nlintc-du4v ^nlintc-kdcl: visible same-package delegation. *)
let propagate = function
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | Invalid_argument _ -> ()
  | exn -> raise exn
