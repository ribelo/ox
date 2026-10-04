(** Minimal [@@deriving yojson] for OxCaml (route (c) of row 15).

    The shared switch's compiler is OxCaml 5.4.0+ox, for which no ppxlib-based deriver is
    installable (see the row's spec status for the routes that were tried). This module is
    the whole deriver instead: it reads one source file, finds
    [type ... [@@deriving yojson]] or [type ... [@@deriving yojson_of]] groups in ordinary
    structures and signatures, and splices converters into the declaring module right
    after the declaration. It is built only on the compiler's own [compiler-libs]
    ([Parse], [Parsetree]), so the tree it reads is by construction the tree this compiler
    parses.

    A file without native derivation is returned byte-identical: the preprocessor is safe
    to run over every file of a stanza. A file with the attribute gets that attribute's
    span — and any declaration-level yojson attribute spans — blanked (same length) and
    the converters inserted right after the declaration behind a [#]-line directive
    pointing at it, so an error inside generated code is reported at the declaration that
    requested it; a second directive after the insert restores the original numbering for
    the code that follows.

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
    deriving attribute, so the compiler never sees either. Each record field is bound
    once, in declaration order, and a missing-key default is applied in that binding
    rather than by copying the rest of the decoder, so generated size is linear in the
    number of fields (lindec-ho00). The unknown-key check still runs only after every
    field binding has succeeded (lindec-e5n0).

    [@@deriving yojson_of] generates only [yojson_of_<name>], depending only on
    constituent encoders. No public/private decoder or decoder signature is generated. An
    abstract signature type may request its encoder; an abstract implementation cannot
    invent a representation. Concrete signature declarations validate the same shapes and
    attributes as implementations. A recursive group inherits its requested mode;
    conflicting [yojson]/[yojson_of] annotations in one group are refused.

    Ordinary nested [module M = struct ... end], [module M : sig ... end] and
    [module type S = sig ... end] declarations work at any depth, including simple
    signature constraints in implementations. Converters and decoder helpers live in the
    declaring structure/signature; sibling type names do not collide. Existing
    local/qualified references and monomorphic recursion work in either mode. Type
    parameters, functions, objects, polymorphic variants, GADTs, private types,
    inline-record constructors, functors, first-class/local modules, recursive modules,
    module applications, non-ordinary module types, and unknown type derivers are loud
    [Error] results, never partial generation or silent pass-through. Unsupported module
    forms without native deriving attributes are left unchanged.

    Generated identifiers all carry the [ppx_yojson_] prefix. Generated code refers to
    [Yojson.Safe], which must be visible where the attribute is used, and to
    [Stdlib.String], [Stdlib.List], [Stdlib.Array] and [Stdlib.string_of_int]; a file
    using the attribute must not shadow those.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards.

    ^nppx-h4gz: this module is the yojson deriver the row delivers. ^nppx-mao8 and
    ^nderive-mmnx ^nderive-0wzg ^nderive-fpd4 ^nderive-q2om ^nderive-qk91 ^nderive-ze85:
    its contract is pinned by [test/ppx/run.ml]. ^lindec-ho00 ^lindec-nt5k ^lindec-48sm
    ^lindec-e5n0 ^lindec-1szx ^lindec-4t98: a record with many [@json.default] fields
    stays linear, and the existing fixtures keep their messages; [test/ppx/size_bound.ml]
    measures the driver output. ^nderive-s2lt ^nderive-u3ux ^nderive-9atb ^nderive-07js
    ^nderive-i3v2 ^nderive-sfta ^nderive-cd80 ^nderive-p4tq ^nderive-ufnu ^nderive-e5va:
    [test/ppx/extensions.ml] and compiled fixtures pin the native extension contract. *)

val process : filename:string -> source:string -> (string, string) result
(** [process ~filename ~source] is [Ok output] with the converters spliced in, or
    [Ok source] unchanged when [source] asks for no derivation, or [Error message] naming
    the type and the reason when derivation was asked for but is not supported. [filename]
    decides the grammar ([.mli] is a signature, anything else an implementation) and
    appears in messages and [#]-line directives. A file that does not lex or parse is
    returned unchanged so the compiler reports the problem itself. *)
