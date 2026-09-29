(** The dangerous [Stdlib] calls, each requiring its capability (^ncaps-4btv): exiting,
    the standard streams, opening files outside Eio's [fs], seeding randomness from the
    system, and temporary files. Same contract as {!Cap_unix}: the raw call and nothing
    else, the capability only looked at, blocking the domain without observing
    cancellation — keep them out of [Ox.Actor] handlers and [Ox.Agent] closures.

    The channel accessors ({!stdout}, {!stderr}, {!stdin}, {!std_formatter},
    {!err_formatter}) are the safe variant of every other stream function: write
    [output_string (Cap_stdlib.stdout ~caps) s] or
    [Format.fprintf (Cap_stdlib.std_formatter ~caps) ...]. *)

(** {1 exit} *)

val exit : caps:< Cap.exit ; .. > -> int -> 'a

(** {1 Standard streams} *)

val stdin : caps:< Cap.stdin ; .. > -> in_channel
val read_line : caps:< Cap.stdin ; .. > -> unit -> string
val stdout : caps:< Cap.stdout ; .. > -> out_channel
val std_formatter : caps:< Cap.stdout ; .. > -> Format.formatter
val print_string : caps:< Cap.stdout ; .. > -> string -> unit
val print_bytes : caps:< Cap.stdout ; .. > -> bytes -> unit
val print_char : caps:< Cap.stdout ; .. > -> char -> unit
val print_int : caps:< Cap.stdout ; .. > -> int -> unit
val print_float : caps:< Cap.stdout ; .. > -> float -> unit
val print_endline : caps:< Cap.stdout ; .. > -> string -> unit
val print_newline : caps:< Cap.stdout ; .. > -> unit -> unit
val printf : caps:< Cap.stdout ; .. > -> ('a, out_channel, unit) format -> 'a
val stderr : caps:< Cap.stderr ; .. > -> out_channel
val err_formatter : caps:< Cap.stderr ; .. > -> Format.formatter
val prerr_string : caps:< Cap.stderr ; .. > -> string -> unit
val prerr_bytes : caps:< Cap.stderr ; .. > -> bytes -> unit
val prerr_char : caps:< Cap.stderr ; .. > -> char -> unit
val prerr_int : caps:< Cap.stderr ; .. > -> int -> unit
val prerr_float : caps:< Cap.stderr ; .. > -> float -> unit
val prerr_endline : caps:< Cap.stderr ; .. > -> string -> unit
val prerr_newline : caps:< Cap.stderr ; .. > -> unit -> unit
val eprintf : caps:< Cap.stderr ; .. > -> ('a, out_channel, unit) format -> 'a

(** {1 Files outside Eio's [fs]} *)

val open_in : caps:< Cap.fs_read ; .. > -> string -> in_channel
val open_in_bin : caps:< Cap.fs_read ; .. > -> string -> in_channel

val open_in_gen :
  caps:< Cap.fs_read ; .. > -> open_flag list -> int -> string -> in_channel

val open_out : caps:< Cap.fs_write ; .. > -> string -> out_channel
val open_out_bin : caps:< Cap.fs_write ; .. > -> string -> out_channel

val open_out_gen :
  caps:< Cap.fs_write ; .. > -> open_flag list -> int -> string -> out_channel

module In_channel : sig
  val open_bin : caps:< Cap.fs_read ; .. > -> string -> In_channel.t
  val open_text : caps:< Cap.fs_read ; .. > -> string -> In_channel.t
  val with_open_bin : caps:< Cap.fs_read ; .. > -> string -> (In_channel.t -> 'a) -> 'a
  val with_open_text : caps:< Cap.fs_read ; .. > -> string -> (In_channel.t -> 'a) -> 'a

  val with_open_gen :
    caps:< Cap.fs_read ; .. > ->
    In_channel.open_flag list ->
    int ->
    string ->
    (In_channel.t -> 'a) ->
    'a
end

module Out_channel : sig
  val open_bin : caps:< Cap.fs_write ; .. > -> string -> Out_channel.t
  val open_text : caps:< Cap.fs_write ; .. > -> string -> Out_channel.t

  val open_gen :
    caps:< Cap.fs_write ; .. > ->
    Out_channel.open_flag list ->
    int ->
    string ->
    Out_channel.t

  val with_open_bin : caps:< Cap.fs_write ; .. > -> string -> (Out_channel.t -> 'a) -> 'a
  val with_open_text : caps:< Cap.fs_write ; .. > -> string -> (Out_channel.t -> 'a) -> 'a

  val with_open_gen :
    caps:< Cap.fs_write ; .. > ->
    Out_channel.open_flag list ->
    int ->
    string ->
    (Out_channel.t -> 'a) ->
    'a
end

(** {1 Randomness from the system} *)

module Random : sig
  val self_init : caps:< Cap.random ; .. > -> unit -> unit
  val make_self_init : caps:< Cap.random ; .. > -> unit -> Random.State.t
end

(** {1 Temporary files} *)

module Filename : sig
  val temp_file : caps:< Cap.tmp ; .. > -> ?temp_dir:string -> string -> string -> string

  val open_temp_file :
    caps:< Cap.tmp ; .. > ->
    ?mode:open_flag list ->
    ?perms:int ->
    ?temp_dir:string ->
    string ->
    string ->
    string * out_channel

  val temp_dir :
    caps:< Cap.tmp ; .. > -> ?temp_dir:string -> ?perms:int -> string -> string -> string
end
