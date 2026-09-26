(** Minimal [@@deriving yojson] for OxCaml (route (c) of row 15).

    The shared switch's compiler is OxCaml 5.4.0+ox, for which no ppxlib-based deriver is
    installable (see the row's spec status for the routes that were tried). This module is
    the whole deriver instead: it reads one source file, finds top-level
    [type ... [@@deriving yojson]] groups, and splices the generated converters into the
    text right after the declaration. It is built only on the compiler's own
    [compiler-libs] ([Parse], [Parsetree]), so the tree it reads is by construction the
    tree this compiler parses.

    A file without [[@@deriving yojson]] is returned byte-identical: the preprocessor is
    safe to run over every file of a stanza. A file with the attribute gets its attribute
    spans blanked (same length) and the converters inserted right after the declaration
    behind a [#]-line directive pointing at it, so an error inside generated code is
    reported at the declaration that requested it; a second directive after the insert
    restores the original numbering for the code that follows.

    Supported shapes: records (with [@key "name"] renames and [@default expr]
    missing-field defaults), variants (nullary constructors as strings, payload
    constructors as [[tag, values...]] arrays), aliases over any supported shape, options
    (absent or null is [None]), lists, arrays, tuples, [string], [int] (accepting integer
    literals), [float] (accepting integers), [bool], [unit] (as null), and references to
    other types by name: a name in the same [type ... and ...] group threads the dotted
    path through, while any other name delegates to its public converters ([Other.t] to
    [Other.yojson_of_t]/[Other.t_of_yojson]), restarting the path at that type:
    [user.home] failing inside [address] reports [user.home: address.city: ...]. A
    qualified name works the same way at any depth ([A.B.t] calls [A.B.yojson_of_t] and
    [A.B.t_of_yojson]), so a field of another package's type needs no [open]. Extra object
    fields are ignored on decode. Anything else — type parameters, functions, objects,
    polymorphic variants, GADTs, inline record constructors, [@@deriving] anything but
    [yojson] on a top-level type, a [@@deriving yojson] below the top level — is a loud
    [Error], never a silent pass-through, because the compiler itself silently ignores
    unknown derivers.

    Generated identifiers all carry the [ppx_yojson_] prefix. Generated code refers to
    [Yojson.Safe], which must be visible where the attribute is used, and to
    [Stdlib.String], [Stdlib.List], [Stdlib.Array] and [Stdlib.string_of_int]; a file
    using the attribute must not shadow those.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards.

    ^nppx-h4gz: this module is the yojson deriver the row delivers. ^nppx-mao8: its
    contract is pinned by [test/ppx/run.ml]. *)

val process : filename:string -> source:string -> (string, string) result
(** [process ~filename ~source] is [Ok output] with the converters spliced in, or
    [Ok source] unchanged when [source] asks for no derivation, or [Error message] naming
    the type and the reason when derivation was asked for but is not supported. [filename]
    decides the grammar ([.mli] is a signature, anything else an implementation) and
    appears in messages and [#]-line directives. A file that does not lex or parse is
    returned unchanged so the compiler reports the problem itself. *)
