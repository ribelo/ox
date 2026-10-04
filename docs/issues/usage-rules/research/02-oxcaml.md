# Published patterns for using OxCaml's mode system to make resource and concurrency misuse fail to compile

Slot **02-oxcaml**. Research only: nothing in any repository was changed. All working files,
saved page copies and library extractions are under /tmp/eio-hardening/02-oxcaml/.

**Scope and method.** I read the OxCaml documentation, the OxCaml compiler source, the
compiler's own mode test suite, the Jane Street oxcaml-branch libraries, the two
peer-reviewed OxCaml papers' metadata, and the OCaml manual. Where I quote a library
interface I copied it verbatim from the downloaded source. Every inference is marked
**INFERENCE**; every unverified name is marked **UNVERIFIED**. Versions: the pinned compiler
on this machine is 5.4.0+ox (~/.cache/opam/5.4.0+ox/bin/ocamlc -vnum prints 5.4.0+ox);
where behaviour differs on github.com/oxcaml/oxcaml branch main I say so and give both.

Local evidence (raw copies of every page cited): sources/oxcaml-org/ (docs),
sources/js-libs/<repo>/ (tarballs of the oxcaml branch), sources/proposals/, sources/blog/,
sources/ppx_let/, and the OxCaml compiler source tree from the nix store
(/nix/store/mmll4109cs8czha31hc6kvy4wi0x21pv-oxcaml-source-patched, VERSION = 5.4.0+ox).

---

# 1. Findings that apply to ox

## F1. The eight modal axes, and the bug class each one is defined against

- **Source:** official docs - https://oxcaml.org/documentation/modes/intro/
  (saved as sources/oxcaml-org/documentation__modes__intro.md)
- **Quote:** "Modes are deep properties of values that are tracked by the OxCaml compiler.
  Like types, they are inferred from definitions and checked for consistency." and, for the
  axis ox cares most about: "Yielding is a future axis that tracks whether a function is
  permitted to perform effects that will be handled in its parent stack."
- **What it says:** eight axes: locality (local/global), portability
  (portable/shareable/corruptible/nonportable) with its dual contention
  (uncontended/shared/corrupted/contended), uniqueness (unique/aliased) with its dual
  linearity (once/many), forkable (forkable/unforkable), yielding (yielding/unyielding),
  visibility (immutable/read/write/read_write) with its dual statefulness
  (stateless/reading/writing/stateful). Each axis is a deep property, so it applies
  recursively to components; modalities cut off the deepness.
- **What it prevents:** each axis names one failure mode. Contention/portability -> data
  races on shared mutable state. Yielding -> performing an effect that escapes to a handler
  you did not account for. Visibility/statefulness -> unsequenced mutation. Locality -> a
  region-allocated value escaping. Uniqueness/linearity -> aliasing bugs such as
  use-after-free or double-consume.
- **How it is enforced:** compiler (mode checking is part of type checking).
- **Concrete shape in ox:** this is the vocabulary the rest of the report uses; ox's
  docs/modes.md already uses global/local/portable this way.
- **INFERENCE:** the axis names map onto ox's own bug list as follows: "finalizer that
  suspends while already cancelled" and "callback must not suspend" -> yielding; "two fibers
  sharing one mutable I/O buffer" -> uniqueness/linearity; "Stdlib mutex held across a
  suspension" -> no single axis (see F4, F5); "half frames in a protocol parser" -> not a
  mode problem at all.

## F2. The closure defaults, and the implication global => unyielding / local => yielding

- **Source:** official docs plus **compiler source** (primary).
  - https://oxcaml.org/documentation/modes/intro/ : "Yielding has different defaults
    depending on the locality axis: *global* values are defaulted to *unyielding*, while
    *local* values are defaulted to *yielding*." Same page for forkable: "global values are
    defaulted to *forkable*, while *local* values are defaulted to *unforkable*."
  - Compiler: typing/typemode.ml, function default_mode_annots, in the pinned tree:
    "| (Some _ as y), _ | y, None -> y | None, Some Locality.Const.Global -> Some
    Yielding.Const.Unyielding | None, Some Locality.Const.Local -> Some
    Yielding.Const.Yielding". And implied_modalities carries the source comment: "Since
    [unforkable yielding] is the default mode in presence of [local], the [global] modality
    must also apply [forkable unyielding] unless specified. [...] [global] must imply
    [aliased] for soundness of borrowing."
- **What it says:** a closure with no annotation in an .mli is at the legacy mode -
  global, forkable, unyielding, aliased. Locality drives the yielding and forkable defaults.
- **What it prevents:** an unannotated, globally-allocated callback cannot be assumed to
  suspend, and cannot capture a local (hence yielding) value.
- **How it is enforced:** compiler.
- **Concrete shape in ox:** every callback ox passes to pinned Eio is unmoded in Eio's
  .mli, hence legacy, hence already **global unyielding** - the compiler already gives ox a
  "this callback must not suspend" property on those parameters. The cost is that ox cannot
  hand a yielding-typed callback to Eio at all (see section 3).
- **INFERENCE:** this is why ox's table in docs/modes.md can say both "callbacks forwarded
  to Eio are global" and (implicitly) that those callbacks are unyielding.

## F3. The local witness / capability-token pattern (Bonsai, handled_effect, Effect.Handler)

The most portable pattern I found; published three times by the same organisation.

- **Source 1:** maintainer blog post - https://blog.janestreet.com/icfp-2024-index/
  ("ICFP 2024", by Nailen Matschke).
  - **Quote:** "The solution? During the graph-building phase, Bonsai provides users with a
    witness value *at mode local*, which they are then required to provide to various
    functions." and "This leverages the compiler's escape analysis for local values, with
    the phase1_witness serving as proof we are in the correct phase."
  - **Code in the post:** "val only_callable_in_phase1 : phase1_witness @ local ->
    phase1_value" and "val run_phase1 : (phase1_witness @ local -> 'a) -> 'a".
  - **What it prevents:** using a graph-building-only operation at runtime (and the mirror:
    constructing a Computation.t Computation.t that "was always a bug, which often presented
    itself far away from where the mistake was made").
- **Source 2:** library README, primary - https://github.com/janestreet/handled_effect
  (branch oxcaml), README.md.
  - **Quote:** "the standard library interface for effects in OCaml is not *effect-safe*:
    the compiler provides no guarantee that every performed effectful operation will be
    handled. Luckily, OxCaml gives us a convenient tool to track whether given code has an
    effect handler installed on its stack: the local mode. Each effect handler can be
    represented as a local argument, which is needed to perform its operations. Functions
    accepting local functions are then effect-polymorphic".
  - **Signature:** "val perform : ('p, 'q) t Handler.t @ c_arg local -> (...) ops @ p_arg ->
    'a @ c_arg once unique" (raises_in_jsoo/handled_effect_intf.ml).
  - **What it prevents:** performing an effect whose handler is not on the stack - a
    statically impossible unhandled effect, instead of a runtime Effect.Unhandled.
- **Source 3:** compiler, upstream main - https://github.com/oxcaml/oxcaml, stdlib/effect.mli.
  - **Quote:** "A value of type [Effect.Handler.t] at mode [local] is proof that the current
    function is running within an effect handler, and hence may perform effects."
  - **Signature:** "type t : void mod external_ many stateless immutable" (uninhabited - it
    carries no runtime value) and "val perform : Handler.t @ local -> 'a t -> 'a".
- **How it is enforced:** type signature plus compiler (the local escape check). No lint, no
  test.
- **Concrete shape in ox:** ox can define its own uninhabited, local-only token types for
  exactly the capabilities whose absence should be a compile error. docs/modes.md already
  reasons about a "handled_effect-style local token"; this is where that pattern is
  published, and handled_effect is the library to copy.
- **Note (verified):** the token works because local implies yielding (F2), so a closure that
  captures the token becomes yielding; and it is void, so it costs nothing at runtime.

## F4. "@ unyielding" on a callback parameter is the published spelling of "this callback must not suspend"

- **Source:** library interfaces, primary - https://github.com/janestreet/await (branch
  oxcaml), sync/mutex_intf.ml and capsule/await_capsule_intf.ml:
  - "val with_access : Sync.t @ local -> 'k t @ local -> f:(Sync.t @ local ->
    'k Capsule.Access.t -> 'a @ contended l once portable unique) @ local once portable
    unyielding -> 'a @ contended l once portable unique"
  - "val with_lock : Sync.t @ local -> 'k t -> f:(Sync.t @ local -> 'k Capsule.Access.t ->
    'a @ contended portable) @ local once portable unyielding -> 'a @ contended portable"
- **Source:** compiler, upstream main - stdlib/effect.mli: "val match_with : (Handler.t @
  local -> 'c -> 'a) @ unyielding -> 'c -> ('a,'b) handler -> 'b" (module Effect.Deep.Safe).
- **Source:** library, primary - https://github.com/janestreet/concurrent (branch oxcaml),
  src/types.ml: "and 'ctx scheduler = { spawn : ... @@ unyielding }".
- **Source:** PR with rationale, primary - https://github.com/oxcaml/oxcaml/pull/6281 ("Add a
  'safe' version of the effects API", merged 2026-07-17), body: "the point of this is to
  make sure that it's never possible (without silencing alerts, of course) to perform an
  effect without either the function being called or any of its arguments being at the
  yielding mode."
- **What it says:** "must not suspend" is written by *omitting* yielding from a callback
  parameter's mode; the callback is then checked not to close over anything yielding. Where
  the callback legitimately needs to suspend, the API hands it a local token *as an
  argument* - the closure itself can stay unyielding because the token is a parameter, not a
  capture (see Effect.Deep.Safe.With_handler).
- **What it prevents:** the class "a finalizer / lock-guard / callback suspended when it must
  not", i.e. ox's "finalizer that suspends while already cancelled" and the mutex-held-across-
  a-suspension family - *provided* the suspending operation requires a yielding capability
  (see the gap in section 4).
- **How it is enforced:** type signature plus compiler. The PR body's parenthetical is the
  honest statement of the gate's strength: it can be silenced with alerts.
- **Concrete shape in ox:** annotate ox's own callback parameters "@ unyielding" where the
  body runs under a lock, and "@ local" where it must not escape.

## F5. The capability-absence pattern: make the dangerous operation unrepresentable

- **Source:** library source with an explicit comment, primary -
  https://github.com/janestreet/parallel (branch oxcaml), kernel/parallel_kernel0.ml:
  **"Subtasks must not [Await] or [Yield]; [Parallel.t] does not provide the capability."**
- **Source:** library doc, primary - kernel/parallel_kernel.mli: "**[f] is also [forkable],
  so cannot capture capsule passwords.**"
- **What it says:** the operation is not blocked by a mode check; the value you would need to
  perform it is not in scope. Parallel.t simply has no function giving a subtask an Await.t.
- **What it prevents:** suspending in a scheduling context that cannot suspend it; capturing
  synchronization capabilities into subtasks.
- **How it is enforced:** type signature (absence) - the strongest available form, because it
  cannot be silenced with an alert.
- **Concrete shape in ox:** ox already has this machinery in another form - Ox_caps.Cap_*
  plus scripts/caps-gate. The finding is that the gate is the right shape and should be
  extended with a suspension capability (see A2).

## F6. "@ unique" for open-once/close-once, with the worked file example and its error message

- **Source:** maintainer blog post - https://blog.janestreet.com/oxidizing-ocaml-ownership/.
  - **Code in the post:** "type file" / "val open_ : path:string -> file @ unique" /
    "val read : file -> string" / "val close : file @ unique -> unit".
  - **Quote:** "Since close requires a unique parameter, we can be sure that files are never
    used after being closed."
  - **Quote (the failure):** "Even though read does not require a unique parameter, we're no
    longer allowed to close the file. Using a unique value at the shared mode is a one-way
    transformation: once we create a single shared reference to file, we're no longer allowed
    to use file uniquely." The post shows the compiler error: "Error: file is used uniquely
    so cannot be used twice."
  - **The remedy in the post:** borrowing - "write &file "data"; close file" typechecks
    because "Because the call to write borrows file exactly once, &file has mode local
    exclusive."
- **Source:** official docs, current shipped form -
  https://oxcaml.org/documentation/uniqueness/borrow/ : "The borrow_ operator lets you
  temporarily use a unique value as aliased and local, without permanently giving up its
  uniqueness." and one restriction: "It is local: it cannot escape the current borrow region
  (it cannot become global or be stored in a heap-allocated value)."
- **What it prevents:** use-after-close and double-close, by making the consuming operation
  take the only reference.
- **How it is enforced:** compiler.
- **Concrete shape in ox:** Child.stop and Correlator.close are named in ox's own
  docs/modes.md as candidates ("might eventually warrant unique/once contracts; this pass
  makes neither promise"). F6 is the published pattern for that promise.
- **Caveat from the same doc set:** you cannot force a unique return by annotating the
  expression - "The only way to reliably change the return mode of mk to be unique is through
  a type signature" (https://oxcaml.org/documentation/uniqueness/pitfalls/). So the promise
  must be stated in the .mli, which is the artefact the human reviews.

## F7. "@ once" - a function that captures a unique value may run only once

- **Source:** blog post, maintainer - https://blog.janestreet.com/oxidizing-ocaml-ownership/:
  "any closure capturing a unique value must be run at most once, as its first invocation may
  consume the value." and "A many variable can be used as if it were once, so many is a
  sub-mode of once."
- **Source:** official docs - https://oxcaml.org/documentation/uniqueness/intro/ :
  "let delay_free : t @ unique -> (unit -> unit) @ once = fun t -> fun () -> free t".
- **Source:** library, primary - https://github.com/janestreet/await, kernel/await.mli:
  "val await_with_terminate : t @ local -> Trigger.t -> terminate:('r @ contended once
  portable unique -> unit) @ global once portable -> 'r @ contended once portable unique ->
  unit".
- **What it prevents:** calling a cleanup/terminate callback twice, or two fibers both taking
  the same value (the callback is once and portable; the payload is unique).
- **How it is enforced:** compiler.
- **Concrete shape in ox:** any "run this once at teardown" callback (Resource.use_in_scope
  ~release, switch finalizers) is a natural "@ once" parameter and the payload it consumes a
  natural "@ unique".

## F8. Scoped handles that must not escape: local plus a scoped runner

- **Source:** official docs - https://oxcaml.org/documentation/uniqueness/borrow/ (borrow is
  local: "it cannot escape the current borrow region").
- **Source:** library interfaces, primary - https://github.com/janestreet/capsule0 (branch
  oxcaml), prim/extended_intf.ml:
  - "val with_ : 'a -> f:('a t @ local -> 'b) @ local once -> 'b" (module Scoped)
  - "val with_password_local : 'a t @ unique -> f:('k Password.t @ local -> 'a @ local)
    @ local once -> 'a @ local"
  - Doc: "[Scoped] uses ['k Capsule.Password.t] -- a token that is only ever available
    locally -- to grant permission for the current thread to have [uncontended] access to the
    capsule ['k] for the duration of the current region."
- **Source:** library interface, primary - https://github.com/janestreet/concurrent (branch
  oxcaml), src/types.ml: "'scope_ctx Scope.Task_handle.t @ local unique".
- **What it says:** the shape is (i) a local handle the callee may hand to a body but not
  store, (ii) a body whose own mode is local once so it cannot retain the handle, (iii) the
  region ends when the runner returns.
- **What it prevents:** a handle outliving the scope it belongs to; a borrowed token stashed
  in a heap structure.
- **How it is enforced:** compiler.
- **Concrete shape in ox:** Ox.Resource.use_in_scope currently takes "(unit -> 'a) @ local"
  and a release. A stronger shape hands the body a local token for the resource, so the body
  cannot copy the resource out. Cost: changes every call site.

## F9. Capsules: a brand plus a password, for "only one thread at a time"

- **Source:** official docs - https://oxcaml.org/documentation/parallelism/capsules/ : "The
  type parameter 'k is known as a *capsule brand*, and uniquely identifies a capsule at
  compile time." and "Accesses **do not** cross contention, and unwrap requires an
  uncontended access. Hence, accesses cannot be freely shared between portable
  functions-semantically, calling a portable function changes the current capsule, so we can
  no longer examine data in 'k."
- **Source:** library interface, primary - https://github.com/janestreet/capsule0 (branch
  oxcaml), prim/prim.mli:
  - "The interface in this module ensures that only one thread can have [uncontended] access
    to that data at a time." and "Capsules are only ever associated with one thread at a
    time, which ensures there are no data races in the program."
  - "type 'k t : void mod contended external_ portable unyielding" for Password.t, documented:
    "Obtaining a ['k t] requires exclusive access to ['k], either through a ['k Key.t @
    unique] or indirectly through acquiring a mutex or rw-lock associated with ['k]. The mode
    system prevents retaining the ['k t] after releasing access to the capsule."
  - "val both : ('a, 'k) t -> ('b, 'k) t -> ('a * 'b, 'k) t" plus fst and snd - the brand
    lets you split and re-merge a handle to one shared resource knowably.
- **What it prevents:** two threads touching the same mutable state; and via both/fst/snd,
  accidentally treating two different resources as one.
- **How it is enforced:** type signature (the brand is an unconstructible type; the password
  is void) plus compiler checks on the modes.
- **INFERENCE:** the "split a duplex handle into read and write halves" idea in the mission
  brief has no direct published capsule equivalent that I found; the nearest published thing
  is Data.both/fst/snd, which splits a pointer into one capsule while keeping the brand. I
  found no published duplex-handle-split pattern (see section 4).

## F10. Branded locks: acquire and release the *right* mutex

- **Source:** design proposal in the compiler fork's own repository, primary -
  https://github.com/ocaml-flambda/ocaml-jst/blob/main/jane/doc/proposals/data-race-freedom.md
  (section "Mutex"): "The Mutex.t is associated with a particular key type 'k. That means to
  acquire the intended 'k Key.t one must be using the corresponding Mutex.t, and this is
  ensured by the type checker. This is a helpful improvement over the traditional mutex
  interface where one can easily acquire and release the wrong mutex without being warned by
  type system at all."
- **What it says:** the lock and the data it protects share a phantom brand, so lock/unlock
  pairing mistakes and cross-resource mistakes are type errors.
- **What it prevents:** releasing a lock you do not hold, or the wrong lock; accessing a
  resource under the wrong lock.
- **How it is enforced:** type signature.
- **Concrete shape in ox:** where ox has more than one named resource with its own
  serialization, give each a brand parameter. Cost: an extra type parameter threaded through
  signatures; only worth it where a real confusion is possible.
- **Caveat, stated in the same document:** this file is a *proposal*, and its interface
  (acquire/release on a key) is not the shipped one; the shipped Await.Sync.Mutex uses
  with_access/with_lock taking a callback "@ local once portable unyielding" (F4). The
  rationale quote is still the best published statement of why.

## F11. Type abstraction is how you *remove* mode crossing

- **Source:** official docs - https://oxcaml.org/documentation/modes/intro/ : "If mode
  crossing is not desired for a type even though it would typically mode cross, then type
  abstraction can be used to prevent its values from escaping (i.e., to prevent them from
  mode crossing the locality axis). For example, even though a file descriptor is commonly
  represented as an int at runtime, type abstraction can be used to hide this fact from the
  type system such that a function that takes a file descriptor as an argument cannot let it
  escape."
- **Source:** official docs - https://oxcaml.org/documentation/kinds/intro/ : "An interesting
  case in normalization is around abstract types. [...] you might see abstract types appear in
  with-bounds, because we are unable to normalize them away until we actually learn what type
  is being used."
- **Source:** library interface, primary - capsule0/prim/extended_intf.ml: "['k t]s cross
  portability, which means they can be shared with other threads. **However, they do not cross
  contention, which means that ['k t]s captured in a [portable] closure become [contended],
  thus preventing any access to its data**".
- **What it prevents:** a value secretly being an int/string and therefore silently
  mode-crossing and escaping a scope you wanted to seal.
- **How it is enforced:** compiler, via the signature the human reviews - the cheapest lever
  ox has.
- **Concrete shape in ox:** every wrapper in Ox_caps should be abstract with an explicit kind
  when the point is that it cannot cross. ox's docs/modes.md already records one such fact
  ("Capabilities are objects and do not cross into a portable closure").
- **Note:** the compiler provides an escape hatch, "[@@unsafe_allow_any_mode_crossing]",
  documented at https://oxcaml.org/documentation/kinds/types/ : "these declarations must have
  a kind annotation. The bounds given in the kind annotation override the bounds determined by
  the rules above." That belongs on ox's forbidden list.

## F12. Portable/contended with the actual compiler messages

- **Source:** official tutorial -
  https://oxcaml.org/documentation/tutorials/intro-to-parallelism-part-1/ ("Simple
  Parallelism Without Data Races"):
  - "you'll see how far you can get with just two modes and the Parallel.fork_join2 function."
  - Real error texts quoted in the tutorial: "The value total is nonportable, so cannot be
    used inside a function that is portable." and "This value is contended but expected to be
    uncontended."
  - The fix pattern: state the fact in the signature, "val price : t @ contended -> float
    @@ portable", with the tutorial's reading: "The precedences here are such that the t
    argument is contended and the whole function, namely price, is portable."
- **Source:** library README and interface, primary - https://github.com/janestreet/parallel
  (branch oxcaml): "val fork_join2 : t @ local -> (t @ local -> 'a) @ forkable local once
  shareable -> (t @ local -> 'b) @ once shareable -> #('a * 'b)"; README: "lib/parallel makes
  use of modes to prohibit data races at compile time. The primary restriction on user
  programs is that they must provide *portable* functions to fork_join. In brief, portable
  functions do not close over unprotected mutable state."
- **What it prevents:** a closure that closes over unprotected mutable state being scheduled
  in parallel; a contended reference used as uncontended.
- **How it is enforced:** compiler. The tutorial also states the compiler infers it: "from
  there, the compiler infers that our calls to Parallel.fork_join2 won't produce data races".
- **Concrete shape in ox:** ox cannot use this axis today. Eio.Domain_manager.run takes an
  unrestricted closure - ox's docs/modes.md records that "the pinned domain manager accepts an
  unrestricted closure, so this test **does not prove** an arbitrary schedule is portable",
  and that Eio.Fiber.fork/pair/first "take unmoded/global task callbacks by design". So
  portable buys ox documentation value only, not enforcement, until Eio annotates those
  parameters.
- **INFERENCE:** the reason this is a documentation rather than enforcement finding for ox is
  the unmoded Eio signature, not a gap in OxCaml.

## F13. let* and the mode of the continuation - known limitation, with a CR, a test, and an open PR

This answers the question in the brief directly.

- **Source:** compiler source, primary - parsing/parser.mly. Pinned 5.4.0+ox line 3403, and
  **still present on main at line 3407** (verified by fetching
  https://raw.githubusercontent.com/oxcaml/oxcaml/main/parsing/parser.mly):
  "(* CR zqian: support mode annotation on letop. *)". The same rule literally drops modes:
  "ghpat_with_modes ~loc ~pat ~cty:(Some typ) ~modes:[]".
- **Source:** compiler source - typing/typecore.ml, the Pexp_letop case: the body is typed as
  a *case* with "Env.add_const_closure_lock (loc, Letop) Value.Comonadic.Const.legacy env" and
  "type_cases Value body_env (simple_pat_mode Value.legacy) (mode_return Value.legacy) ...".
  (On main the same call reads With_regionality.Comonadic.Const.legacy.)
- **Source:** the compiler's own mode test suite - testsuite/tests/typing-modes/letop.ml in
  the pinned tree. It contains the comments "(* bindings are required to be legacy *)" and
  "(* Body required to be legacy *)" and pins the exact diagnostics, e.g. for
  "let* a = local_ "hello" in ()" the error "Error: This value is "local" but is expected to
  be "global"." and the same error for a local value in the body of a let*.
- **Source:** open PR, primary - https://github.com/oxcaml/oxcaml/pull/6276 "Parse modes on
  binding operators" (opened 2026-06-17, still open, last updated 2026-07-20). Body: "Parse
  mode annotations on application of binding operators, threading them through a new pbop_modes
  field on binding_op. **Don't actually implement them in typecore yet; just fatal error if
  they get this far. Actually checking these modes against user annotations will come next.**"
  The diff adds the production "| LPAREN let_ident at_mode_expr RPAREN exp = strict_binding",
  i.e. writing modes on a letop binder, and leaves the old modes:[] path intact.
- **Adjacent, open:** https://github.com/oxcaml/oxcaml/issues/4155 "Polymorphic parameters and
  letop don't interact" - same code path, different complaint ("when building the expected type
  for the let operator in typecore.ml we expect all values to be mono-morphic"). Not about
  modes, but it confirms the letop elaboration path is under-developed. Also open:
  https://github.com/oxcaml/oxcaml/pull/6292 (naming/scoping of the desugared fun x -> body,
  not modes).
- **What it prevents (in the current state):** nothing - it is a limitation, not a guard. Its
  practical effect is that a local value cannot be carried across a let*, and per F2 a
  yielding value cannot be used inside a let* body, because the continuation is pinned to
  legacy = global => unyielding.
- **How it is enforced:** the limitation is enforced by the compiler; awareness is enforced
  only by a CR comment and a test file.
- **Answer to "is that a known limitation, is there an issue or a plan?":** known - yes,
  recorded as a CR comment in the parser (present on main today) and pinned by
  testsuite/tests/typing-modes/letop.ml. Issue - I found no issue that is *about* the mode of
  the letop continuation (searched letop, binding operator, let* mode, unyielding across
  oxcaml/oxcaml issues and PRs). Plan - yes, PR #6276 is the first half of one; it is open and
  its body says checking "will come next".
- **The workaround's shape is confirmed by source:** ppx_let
  (https://github.com/janestreet/ppx_let, expander/ppx_let_expander.ml) expands to a plain
  application "bind arg ~f:(fun ... -> body)" (bind_apply builds
  "pexp_apply (eoperator op_name) [Nolabel, arg; Labelled fn_label, fn]"), and adds [@nontail]
  only when the local-locality extension is requested - "let nontail ~loc expr = let attr =
  attribute ~name:"nontail" ..." applied by "if allocate_function_on_stack then nontail ~loc
  expr else expr". Because it is a normal application, the closure's mode comes from the bind
  function's own signature instead of from the letop closure lock - which is why it escapes the
  limitation.

## F14. Alerts as a hard, mechanical gate

- **Source:** official language manual - https://ocaml.org/manual/5.3/alerts.html : alerts "can
  be used for instance to report usage of unsafe features", and the spec letters: "++id turns
  alert id into a fatal error", "@id equivalent to ++id+id".
- **Source:** library interface, primary - capsule0/prim/prim.mli:
  "[@@alert maybe_still_concurrent "Being on the initial thread does not provide any guarantees
  about thread-safety. This fact should only be used to avoid contention."]" on
  is_initial_thread and is_initial_domain.
- **Source:** compiler, upstream main - stdlib/effect.mli:
  "[@@alert unsafe_effects "Use [Effect.Safe.perform]. [Effect.perform] may not function
  correctly on Js_of_ocaml"]". And the merged PR body itself relies on this being defeatable:
  "it's never possible (without silencing alerts, of course)".
- **What it says:** a dangerous entry point can be marked, and the build can be configured so
  that using it is a compile error, not a warning.
- **What it prevents:** any escape-hatch call reaching the codebase silently.
- **How it is enforced:** compiler, via a build flag. It is a gate, and it is the one
  mechanism here that is a lint rather than a type.
- **Concrete shape in ox:** ox's scripts/caps-gate is a source-level check; alerts give a
  compiler-level one that cannot be bypassed by a differently-spelled call. Cost: a build flag
  plus discipline about where the alert is silenced.

## F15. Mode polymorphism exists (%template, [@mode]) and carries a documented caveat

- **Source:** library interface, primary - https://github.com/janestreet/handled_effect
  (branch oxcaml), raises_in_jsoo/handled_effect_intf.ml: the effect signature is written with
  "module type%template [@mode (p_arg, c_arg) = ((nonportable, uncontended), (portable,
  contended)), ...] S2_generic", immediately qualified by the comment: "**This is not a truly
  mode-polymorphic signature. Only select instances may be used, and each instance requires
  its specific result type for soundness.**"
- **Source:** library interfaces, primary - the oxcaml-branch libraries use the feature
  heavily: "val%template create : sync:Sync.t @ l -> terminator:Terminator.t @ l -> t @ l
  [@@alloc a @ l = (stack_local, heap_global)]" (await/kernel/await.mli);
  "[@@@mode.default l = (local, global)]" in parallel.
- **What it says:** a single signature can be instantiated at two mode combinations, but the
  compiler does not give full parametricity over modes; each instantiation is checked
  separately and the author must argue soundness per instance.
- **What it prevents:** writing the same function twice for local and global.
- **How it is enforced:** compiler (instantiates and checks each combination).
- **Concrete shape in ox:** usable for ox's bind/use_in_scope-style combinators to serve both
  local and global callers from one declaration. Cost: the caveat means each instantiation must
  be justified; treat it as an optimisation after the simple version works.

---

# 2. Things ox should adopt, ranked

Ranked by value to ox divided by cost. Every item names the concrete artefact.

### A1. Pin the let* mode behaviour in a compile test, and keep the documented global policy
*Highest value, lowest cost. Do this first.*
- **Shape:** test/modes/letop_modes.ml in the style of the compiler's own
  typing-modes/letop.ml: assert that (a) a local value cannot cross a let*, (b) a yielding
  value cannot be used in a let* body, (c) the workaround "bind e (fun x -> ...) [@nontail]"
  **does** compile with a local/yielding parameter in bind's signature. If ox's toolchain
  cannot express expected-failure tests, the fallback is a Cram test that runs ocamlc and greps
  the diagnostic - the compiler's own test is an expect test, so an expect-style test is the
  natural fit.
- **Also:** add one paragraph to docs/modes.md recording that this is an upstream limitation
  with a CR in parsing/parser.mly and open PR #6276, so the next agent does not re-derive it.
- **Cost:** hours. No signature changes. Converts a workaround discovered by hand into a
  mechanical gate, which is what ADR-0010 asks for.
- **Source of the pattern:** F13.

### A2. Add a suspension capability to the capability gate
*High value; the only shape that actually stops "must not suspend" under pinned Eio.*
- **Shape:** mirror parallel/kernel/parallel_kernel0.ml's embedded rule: a capability value
  that is **only** in scope in the places allowed to suspend, and a scripts/caps-gate rule that
  refuses raw suspension calls (Eio.Time.sleep, Eio.Fiber.yield, Eio.Condition.await,
  Switch.await, ...) outside the runtime layer. Where a callback must be provably
  non-suspending, give it a signature with no token at all so the compiler also rejects a
  capture.
- **Why not just the mode:** see section 3 - pinned Eio's suspension entry points are unmoded,
  so "@ unyielding" on a callback does not stop that callback calling Eio.Time.sleep.
  Capability absence does.
- **Cost:** medium. One capability type, one gate rule, and a sweep of the call sites that
  legitimately suspend. The compiler-side half (local tokens) has the extra cost that it
  changes signatures which callers must then satisfy.
- **Source of the pattern:** F5 (and F4 for the mode-level half).

### A3. Give Child.stop and Correlator.close a unique (or once) contract, with use-after-close and double-close compile tests
- **Shape:** "val stop : t @ unique -> unit" and "val close : t @ unique -> unit" in the .mli,
  plus test/modes/ cases that must fail to compile: closing twice, using after closing. Where
  the handle is genuinely shared, use borrowing (borrow_) so readers do not forfeit uniqueness.
- **Cost:** medium. The risk is named by the docs: the compiler only infers unique returns
  reliably "through a type signature", and any internal aliasing of the handle turns it aliased
  and the .mli will not typecheck. Budget for refactoring the handle's construction path so the
  unique return is real, and expect at least one round of "this value is aliased but expected
  to be unique".
- **Source of the pattern:** F6, F7.

### A4. Introduce one local witness token for ox's own phase-scoped API, and test that it cannot escape
- **Shape:** following the Bonsai pattern ("val only_callable_in_phase1 : phase1_witness @ local
  -> phase1_value", "val run_phase1 : (phase1_witness @ local -> 'a) -> 'a"): an uninhabited
  "type t" plus "val with_phase : (t @ local -> 'a) -> 'a", where only the operations valid in
  that phase accept the token.
- **Cost:** low for the first token; the price is that every API in that phase gains a
  parameter (and the human reviewing interfaces now sees the dependency explicitly, which is the
  point).
- **Source of the pattern:** F3, F8.

### A5. Turn the dangerous entry points into alerts and make them fatal in CI
- **Shape:** "[@@alert ox_unsafe_effects "..."]" on the raw suspension/close/escape functions
  that the capability wrappers exist to hide, and a dune flag
  "(flags (:standard -alert ++ox_unsafe_effects))" for everything except the runtime package
  that implements them.
- **Cost:** low. The failure mode to watch is a build that silently stops being fatal if the
  flag is dropped; assert it in a Cram test that compiles a one-line file and expects a nonzero
  exit.
- **Source of the pattern:** F14.

### A6. Keep "type abstraction blocks mode crossing" as an explicit review rule, with a test for the capability types
- **Shape:** a short rule in docs/modes.md - "an abstract type in a .mli without a kind
  annotation may still mode-cross; if the point of the wrapper is that it must not cross
  portable, say so with a kind and test it" - plus a compile test in the style of
  test/modes/portability.ml asserting that a Cap_* value cannot be captured in a portable
  closure.
- **Cost:** low (documentation plus one test). The trap is the escape hatch
  [@@unsafe_allow_any_mode_crossing], which should be on ox's forbidden list.
- **Source of the pattern:** F11.

### A7. Brand the resources where two of them can be confused
- **Shape:** the branded-Mutex idea: "type 'k t" with the brand shared between the lock and the
  data it protects, so acquiring the wrong lock is a type error.
- **Cost:** high relative to the others - a type parameter on the resource, the lock, and every
  function between them, which ox's own docs/modes.md shows is the sort of thing that leaks into
  call sites. Adopt only where a real lock-confusion bug has occurred or is structurally likely.
- **Source of the pattern:** F9, F10.

### A8. Adopt Unique.Once-style runtime-checked once-only cells where a static once does not fit
- **Shape:** Unique.Once.t (take_or_null, take_exn, borrow_or_null) gives "accessed at most
  once" for values whose static uniqueness cannot be established, with the static part still
  carried by "@ once unique" in the signature (unique/src/once.mli, branch oxcaml).
- **Cost:** low; it is an extra dependency and the failure becomes a runtime Null/Failure rather
  than a compile error, so it is a second-best gate and should be documented as one.
- **Source of the pattern:** F6/F7 plus unique/src/once.mli.

---

# 3. Things that look relevant but do not apply

1. **The full Capsule/Capsule0 API.** It is designed for a multi-domain Parallel/Await world:
   Data.t "crosses both contention and portability, so can be freely passed to other threads"
   (https://github.com/janestreet/capsule0, prim/extended_intf.ml), and access is synchronized
   through Await.Sync. ox is a single-domain direct-style Eio kernel with no parallel package.
   Reason it does not apply: **the object of protection (cross-domain mutable sharing) does not
   exist in ox today.** The shape (F3, F9, F10) does apply.
2. **Parallel.fork_join* and the shareable/forkable modes.** Their whole purpose is scheduling
   subtasks on other domains. ox has no such scheduler, and its own docs record that the pinned
   Eio.Domain_manager.run "accepts an unrestricted closure", so the modes would not be checked
   even if ox used it. Reason: **no enforcement point.**
3. **portable_memo, portable_ws_deque, portable_mpmc_queue, portable_lockfree_htbl,
   ppx_portable, portable_adaptive_backoff.** All solve cross-domain cache/queue/memoization
   problems. Same reason as (2).
4. **Unique.Ref, Unique.Atomic, Lockfree_stack, Lockfree_single_consumer_queue.** These move
   ownership of *elements* through lock-free containers; the discipline is
   "push : 'a t @ local -> 'a @ contended once portable unique -> unit" - elements are handed
   over, never copied, with a source comment "SAFETY: This data structure must not expose
   operations that would duplicate elems." Relevant conceptually, but ox has no lock-free
   container. Unique.Once is the one part that applies (A8).
5. **basement.** Its oxcaml branch contributes Portable_lazy, Portable_atomic, Subatomic, Modes
   - infrastructure for the other libraries. I found no resource-discipline interface in it that
   ox would consume. Listed here because I read its file list and doc headers, not all bodies.
6. **Session types and typestate as a library pattern.** They exist for OCaml
   (keigoi/session-ocaml, "An implementation of binary session types in OCaml";
   boystrange/FuSe, "A simple library implementation of binary sessions"; keigoi/ocaml-mpst,
   "Multiparty Session Types in OCaml"; the Session-ocaml paper,
   https://www.doc.ic.ac.uk/research/technicalreports/2017/DTRS17-8.pdf), but they are
   third-party libraries with their own abstract-type/monadic encodings, not compiler support,
   and I found no integration with OxCaml modes anywhere. Reason they do not apply: **cost (a
   protocol encoding per interface) with no compiler-level guarantee, when ox's handlers need
   only "this callback may not suspend" and "this handle is consumed once", which modes give
   directly.** I did not verify the maintenance or the exact enforcement mechanism of these
   libraries (see section 4).
7. **Effect.Handler / Effect.Deep.Safe as an available mechanism.** Verified absent from the
   pinned compiler: ~/.cache/opam/5.4.0+ox/lib/ocaml/effect.mli contains **zero** occurrences of
   "Handler" and has only "external perform : 'a t -> 'a = "%perform""; upstream main has both.
   Reason it does not apply today: **the pinned compiler does not have it.** Revisit on the next
   compiler bump; it is the cleanest "may I suspend?" proof token available.
8. **The yielding axis as a general "must not suspend" enforcement.** It is defined and defaults
   correctly (F2), and real libraries use "@ unyielding" on callback parameters (F4) - but every
   suspension point ox actually calls is unmoded in pinned Eio, and an unmoded parameter is
   legacy, i.e. unyielding, i.e. callable from an unyielding context. Verified in the installed
   pinned Eio, ~/.cache/opam/5.4.0+ox/lib/eio/: "val sleep : _ clock -> float -> unit"
   (time.mli:14), "val await : t -> Eio_mutex.t -> unit" (condition.mli:47), "val yield :
   unit -> unit" (core/eio__core.mli:323, module Fiber), "val await : _ t -> exit_status"
   (process.mli:131). Reason it does not apply: **the mode check has nothing to bite on until
   Eio (or an ox wrapper that the gate enforces) annotates the suspension points yielding.**
   This is a version-specific type gap, not a misunderstanding of the axis; ox's docs/modes.md
   records the same class of pinned-upstream gap for local (Eio.Switch.run, Fiber.with_binding,
   Time.with_timeout, Fiber.fork/pair/first, Domain_manager.run).
9. **[@@unsafe_allow_any_mode_crossing].** It exists
   (https://oxcaml.org/documentation/kinds/types/) and it is exactly the kind of hand-written
   hole a human reviewing interfaces cannot see through. Reason it does not apply: it is an
   escape hatch, not a pattern; ox should forbid it.
10. **Full mode-polymorphic %template signatures.** Available (F15) and used by Jane Street, but
    handled_effect's own comment - "This is not a truly mode-polymorphic signature. Only select
    instances may be used" - means each instantiation is a soundness argument someone must make.
    Reason it does not apply yet: **the cost is reasoning per instance, and ox does not currently
    have a signature that needs two instantiations.** Revisit if A2 grows a surface that must
    serve both local and global callers.

---

# 4. What I could not find out

Stated as absence, not filled in:

1. **No maintainer statement about *why* the letop continuation is pinned to legacy.** I found
   the CR comment, the test comments ("bindings are required to be legacy", "Body required to be
   legacy") and PR #6276's plan, but no issue, doc page, or comment saying whether this is a
   deliberate design decision or a temporary wart. I also found **no issue dedicated to the mode
   of the letop continuation** - searches for letop, binding operator, let* mode and unyielding
   over oxcaml/oxcaml issues and PRs (GitHub search API, 2026-10-04) returned PR #6276, PR #6292
   and issue #4155 and nothing else on point.
2. **No timeline** for PR #6276, and I did not verify whether it is behind a flag, blocked, or
   simply unreviewed. It is open, last updated 2026-07-20.
3. **No documentation page on the yielding axis beyond one paragraph** in
   documentation/modes/intro/. There is no worked "how to say this callback must not suspend"
   example in prose; I reconstructed the discipline from library signatures (Await, concurrent,
   Effect.Deep.Safe). The 65 links I enumerated from https://oxcaml.org/documentation contain no
   yielding-specific topic.
4. **No rationale for several interface choices I cite**, e.g. why Capsule.Password.t's kind
   mentions unyielding, and why with_access's callback is "@ local once portable unyielding" in
   that exact combination. Recorded as "found the rule, did not find the rationale".
5. **I did not enumerate OxCaml releases or tags.** I verified Effect.Handler exists on main and
   is absent from the pinned 5.4.0+ox; I cannot say from which release onwards it is available.
6. **No transcripts of the Jane Street talks.** yt-dlp is not installed and I installed nothing,
   so I verified talk titles/dates only from oxcaml.org's own list ("Making OCaml Safe for
   Performance Engineering", Chris Casinghino, Jane Street Tech Talk, Mar 20 2025; "Data Race
   Freedom a la Mode", Aina Linn Georges, POPL, Jan 23 2025; and others, at
   https://oxcaml.org/documentation). **No talk content is claimed here.**
7. **"Fun with Algebraic Effects" is a blog post, not a talk** -
   https://blog.janestreet.com/fun-with-algebraic-effects-hardcaml/, by Fu Yong Quah (the page's
   own byline confirms the author). I read its mode-related passages; it argues monads block the
   local mode, and it does **not** contain a "must not suspend" typing discipline.
8. **No published "split a duplex handle" pattern.** I looked for a read/write handle split in
   capsule, capsule0, await, concurrent and parallel and found only brand-preserving projection
   (Data.both/fst/snd). If such a pattern is published somewhere I did not look, I did not find
   it and I am not inferring one.
9. **Session types and typestate: I did not verify enforcement mechanisms.** I confirmed the
   repositories exist and are described as implementations of binary/multiparty session types
   (metadata from the GitHub API, 2026-10-04: keigoi/session-ocaml last pushed 2019-06-03;
   boystrange/FuSe 2024-06-18; keigoi/ocaml-mpst 2024-11-01), but I did **not** read their
   interfaces, so I cannot say whether they enforce with abstract types, a ppx, or a monadic
   discipline. I found **no OxCaml or mode-based session-type or typestate work at all.**
10. **No OCaml RFC for linear types.** A search of ocaml/RFCs for "linear" returned nine PRs,
    none about linear types (the nearest, #10 "Unboxed types proposal", is unrelated). I did not
    search ocaml/ocaml issues exhaustively.
11. **The two papers' full texts.** ACM returned HTTP 403 for both DOIs on 2026-10-04. I have
    titles, authors and venues from oxcaml.org's own bibliography page
    (https://oxcaml.org/documentation): "Oxidizing OCaml with Modal Memory Management",
    Lorenzen, White, Dolan, Eisenberg, Lindley, ICFP'24 (10.1145/3674642); "Data Race Freedom a
    la Mode", Georges, Peters, Elbeheiry, White, Dolan, Eisenberg, Casinghino, Pottier, Dreyer,
    POPL'25 (10.1145/3704859). **I did not read either paper**, so I claim nothing about their
    content beyond their titles.
12. **A "Mode Crossing" paper** came up in a search with the ICFP 2026 programme
    (https://icfp26.sigplan.org/details/icfp-2026-icfp-papers/9/Mode-Crossing, DOI
    10.1145/3828681). **UNVERIFIED**: I did not fetch it, so I do not know its authors, its
    claims, or whether it is related to the two papers above.
13. **I did not read** basement's bodies beyond file listing and headers, the last quarter of
    capsule0/prim/extended_intf.ml, the stack-allocation and optimisation pages,
    ppx_portable's source, or the oxcaml-typesafe-reference-counting-python blog post. Nothing
    in this report depends on them.

---

## Summary

The published OxCaml way to make resource and concurrency misuse fail to compile comes down to
four reusable shapes, all compiler-enforced:

1. **A local, uninhabited token as proof of context** (Bonsai's phase witness, handled_effect,
   Effect.Handler, Capsule.Password) - you may only do the operation if you were handed the
   token, and the escape analysis stops you retaining it.
2. **unique / once for consume-once resources** ("close : file @ unique -> unit", and
   Unique.Once where static uniqueness will not hold) - use-after-close and double-close become
   type errors.
3. **"@ unyielding" on a callback parameter for "this callback must not suspend"**, with the
   suspension token passed as an argument where suspending is legitimate
   (Await with_access/with_lock, Effect.Deep.Safe).
4. **Capability absence** - "Parallel.t does not provide the capability" - the only one of the
   four that cannot be silenced, and the one ox can apply today through its existing Cap_* gate.

For ox specifically: the let* limitation is real, recorded in the compiler as a CR comment that
is still on main, pinned by the compiler's own test, and being started on by an open PR - and
the "bind ... [@nontail]" workaround is structurally sound because ppx_let's expansion is an
ordinary application. The portable/yielding axes are documented and correct but have nothing to
bite on under pinned Eio's unmoded signatures; ox's enforceable wins today are compile tests
(A1), the capability gate (A2), unique/once contracts (A3), and alerts (A5).

**REPORT.md:** /tmp/eio-hardening/02-oxcaml/REPORT.md
