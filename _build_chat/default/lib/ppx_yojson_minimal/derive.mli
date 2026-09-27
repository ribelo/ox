(** Minimal [@@deriving yojson] for OxCaml (route (c) of row 15).

    The shared switch's compiler is OxCaml 5.4.0+ox, for which no ppxlib-based deriver is
    installable (see the row's spec status for the routes that were tried). This module is
    the whole deriver instead: it reads one source file, finds top-level
    [type ... [@@deriving yojson]] groups, and splices the generated converters into the
    text right after the declaration. It is built only on the compiler's own
    [compiler-libs] ([Parse], [Parsetree]), so the tree it reads is by construction the
    tree this compiler parses.

    A file without [[@@deriving yojson]] is returned byte-identical: the preprocessor is
    safe to run over every file of a stanza. A file with the attribute gets that
    attribute's span — and any declaration-level yojson attribute spans — blanked (same
    length) and the converters inserted right after the declaration behind a [#]-line
    directive pointing at it, so an error inside generated code is reported at the
    declaration that requested it; a second directive after the insert restores the
    original numbering for the code that follows.

    Supported shapes: records (with [@json.key "name"] renames and [@json.default expr]
    missing-field defaults), variants (nullary constructors as strings, payload
    constructors as [[tag, values...]] arrays, [@json.name "wire_tag"] on either kind),
    aliases over any supported shape, options (absent or null is [None]; a [None] record
    field is omitted on encoding unless it carries [@json.null]), raw [Yojson.Safe.t]
    (passed through unchanged), lists, arrays, tuples, [string], [int] (accepting integer
    literals), [float] (accepting integers), [bool], [unit] (as null), and references to
    other types by name: a name in the same [type ... and ...] group threads the dotted
    path through, while any other name delegates to its public converters ([Other.t] to
    [Other.yojson_of_t]/[Other.t_of_yojson]), restarting the path at that type:
    [user.home] failing inside [address] reports [user.home: address.city: ...]. A
    qualified name works the same way at any depth ([A.B.t] calls [A.B.yojson_of_t] and
    [A.B.t_of_yojson]), so a field of another package's type needs no [open].

    Field and constructor attributes carry jsonkit's names — [@json.key], [@json.default],
    [@json.null], [@json.name] — so that a later switch to jsonkit's ppx is a change of
    deriver, not of every declaration (^nderive-ze85). The names this deriver accepted
    before the rename ([@key], [@default], [@yojson.null], [@name]) are refused with the
    name to write instead: ignoring one would silently change a wire key or tag. The
    declaration attributes keep their [yojson] namespace — [[@@yojson.allow_extra_fields]]
    and [[@@yojson.empty_record]] — because the deriver they configure is still
    [@@deriving yojson], and the empty-record marker has no jsonkit counterpart.

    OxCaml cannot parse [type t = {}]. For the same one-value shape on the wire,
    [type t = unit [@@deriving yojson] [@@yojson.empty_record]] encodes as [{}] and
    decodes only an empty object (not [null] or an object with keys). The marker takes no
    payload and is valid only on a unit alias. Plain [unit] remains encoded as null.

    Unknown object fields are refused, as [<path>: unknown field <key>]: a key the type
    does not name is a typo in a config file or a request, so a record decoder reports it
    instead of dropping it. A record declaration that carries
    [[@@yojson.allow_extra_fields]] opts out and ignores the fields it does not know —
    what a shape we do not own (a peer's payload, a forward-compatible reply) needs. The
    attribute applies to that declaration only, takes no payload, and is blanked like the
    deriving attribute, so the compiler never sees either. Anything else — type
    parameters, functions, objects, polymorphic variants, GADTs, inline record
    constructors, [@@deriving] anything but [yojson] on a top-level type, a
    [@@deriving yojson] below the top level — is a loud [Error], never a silent
    pass-through, because the compiler itself silently ignores unknown derivers.

    Generated identifiers all carry the [ppx_yojson_] prefix. Generated code refers to
    [Yojson.Safe], which must be visible where the attribute is used, and to
    [Stdlib.String], [Stdlib.List], [Stdlib.Array] and [Stdlib.string_of_int]; a file
    using the attribute must not shadow those.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards.

    ^nppx-h4gz: this module is the yojson deriver the row delivers. ^nppx-mao8 and
    ^nderive-mmnx ^nderive-0wzg ^nderive-fpd4 ^nderive-q2om ^nderive-qk91 ^nderive-ze85:
    its contract is pinned by [test/ppx/run.ml]. *)

val process : filename:string -> source:string -> (string, string) result
(** [process ~filename ~source] is [Ok output] with the converters spliced in, or
    [Ok source] unchanged when [source] asks for no derivation, or [Error message] naming
    the type and the reason when derivation was asked for but is not supported. [filename]
    decides the grammar ([.mli] is a signature, anything else an implementation) and
    appears in messages and [#]-line directives. A file that does not lex or parse is
    returned unchanged so the compiler reports the problem itself. *)
