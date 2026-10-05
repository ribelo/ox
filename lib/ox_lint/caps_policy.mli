(** Cancellation and finalizers: Suspension: never suspends in Eio itself; synchronous
    filesystem/compiler work may block the domain; operations delegate to Stdlib, Unix and
    Ox_caps and their higher-order callbacks; capability object method dispatch depends on
    the supplied provider; running returned visitors depends on caller code. Cancellation:
    not a cancellation point in Eio itself; operations delegate to Stdlib, Unix and
    Ox_caps and their higher-order callbacks; capability object method dispatch depends on
    the supplied provider; running returned visitors depends on caller code; malformed
    Dune stanzas raise Failure. Finalizers: input channels opened by these checks are
    bracketed by Cap_stdlib.In_channel.with_open_bin; no switch hook is registered.
    Locking: runtime I/O synchronization is delegated to Stdlib and Unix; no lock is
    acquired by this module. ^nlintd-z5p5 ^nlintd-vneh ^nlintd-truth *)

val allowances : (string * string) list
(** The shipped capability allow-list is empty. ^ncapslint-x3gi ^ncapslint-snhg *)

val self_check : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> string list

val policy_path : string -> string
(** Normalize lexical paths relative to the invocation root. *)

val excluded : string list -> string -> bool
(** Only explicit caller-supplied --allow patterns exclude a source. *)

val executable_entry : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** The source is the named entry of its owning executable stanza, not a library, test, or
    utility module. ^nlintc-du4v *)

val declares_door : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** The owning Dune stanza must directly declare [ox_caps.door]. Module ownership and
    include_subdirs are respected; comments and unrelated stanzas grant nothing. *)

val check_dune :
  caps:< Ox_caps.Cap.fs_read ; .. > -> string list -> (string -> int -> unit) -> unit
(** Declaring a dependency is a grant, not an error; retained CLI integration point. *)

val declares_test : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** The owning stanza directly depends on [ox_test], authorizing only its test mint. *)

val private_module : caps:< Ox_caps.Cap.fs_read ; .. > -> string -> bool
(** Whether the source belongs to a module listed in its owning Dune stanza's
    [private_modules]. Such an interface is not a package-published API. *)
