val allowances : (string * string) list
(** The shipped capability allow-list is empty. ^ncapslint-x3gi ^ncapslint-snhg *)

val self_check : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> string list

val policy_path : string -> string
(** Normalize lexical paths relative to the invocation root. *)

val excluded : string list -> string -> bool
(** Only explicit caller-supplied --allow patterns exclude a source. *)

val declares_door : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** The owning Dune stanza must directly declare [ox_caps.door]. Module ownership and
    include_subdirs are respected; comments and unrelated stanzas grant nothing. *)

val check_dune :
  caps:< Ox_caps.Cap.fs_read ; .. > -> string list -> (string -> int -> unit) -> unit
(** Declaring a dependency is a grant, not an error; retained CLI integration point. *)

val private_module : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** Whether the source belongs to a module listed in its owning Dune stanza's
    [private_modules]. Such an interface is not a package-published API. *)
