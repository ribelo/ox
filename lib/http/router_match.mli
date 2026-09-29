(* Copied from v1:lib/router/match.mli (story ^hserv-e3q9); module paths adapted only.
   Internal to {!Ox_http.Router}. *)

(** A successful match from {!Ox_http.Router.at}. *)

type 'a t = { value : 'a; params : Router_params.t }
