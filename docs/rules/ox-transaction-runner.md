# ox-transaction-runner

<!-- ^safe-ldtb ^safe-j6t8 ^safe-fr73 ^safe-y047 ^safe-czoe ^safe-tlyw
     ^safe-m5sp ^safe-t37w ^safe-12o2: bounded identity evidence, not a name ban. -->

A transaction callback must send work through its supplied transaction runner,
not the originating pool. The pool requests another lease; it does not join the
callback's transaction. A one-connection pool can wait for the lease held by the
callback itself. More connections can permit work outside the rollback boundary.

## Demonstrated defect and replacement

Bad:

    Ox_sql.Pool.with_transaction pool (fun _tx ->
        Ox_sql.Pool.Raw.execute pool "INSERT INTO entries VALUES (1)" [])

Replace the runner, not the SQL operation:

    Ox_sql.Pool.with_transaction pool (fun tx ->
        Ox_sql.Pool.Raw.execute tx "INSERT INTO entries VALUES (1)" [])

Defect evidence is the resolved identity of the originating pool at a known
runner operation inside the callback. This is not a policy against SQL, aliases,
all pool values, or Raw APIs. No generic exemption permits deliberate bypass;
that work belongs behind an explicit reviewed application interface with its
separate lease/rollback contract.

## Detection horizon

- Requires fresh, complete implementation annotations and compiler context.
  Missing, mismatched and stale annotations are artifact evidence failures, never clean outcomes.
- Recognizes resolved `Ox_sql.Pool.with_transaction`, including module/value aliases.
- Runner operations: Raw `query`, `fold`, `execute`, `execute_script`,
  `with_connection`; Typed `select`, `returning`, `fold_select`,
  `execute_compiled`, `run_schema`. Nested transaction acquisition is checked too.
- Follows simple variable/alias-pattern bindings and local functions, substituting
  positional/labeled arguments and retaining captured lexical bindings. Supports
  direct function and function-case callbacks. At most 16 functions are active;
  recursive/deep runner routing is undecided, not a whole-program proof.
- Transaction roots inside ordinary callback arguments, including `Eio.Switch.run`
  and `Eio_main.run`, are discovered with empty incoming transaction contexts.
  Root discovery is not proof that an ordinary or independently forked callback
  executes within the caller's transaction lifetime. Known transaction and SQL
  callbacks are visited only by their invocation dispatch, not again as empty-context roots.
- Known SQL connection/fold callbacks are analyzed. Stored/returned closures and
  partially applied functions are not presumed executed. Relevant opaque routing
  involving runner values or captured runners produces located, reason-bearing
  undecided outcomes. Unrelated pure calls and pure recursion produce no findings.
- Opaque-routing relevance concerns transmitted values and captured runners, not
  every expression evaluated to produce an argument. Compiler-predefined `int`,
  `bool`, `char` and `unit` values cannot contain a runner; their eagerly evaluated
  child SQL operations and helper calls are still checked. Exact compiler type
  identity proves this, including transparent aliases, not a printed type name or
  a callee purity exemption. Closures returning scalars and tuples, records or
  results containing runners retain their routing obligations.
- Two different direct `Pool.create` expressions, each unpacked through resolved
  standard `Ok`, prove independent pools. Simple aliases preserve that identity.
  A direct creation executed after entry into a callback also proves independence
  from that already-active transaction’s originating pool. Result aliases preserve
  allocation-time context: merely unpacking an earlier result inside the callback
  does not establish independence. A fresh pool used as the transaction origin
  remains forbidden, and opaque factories do not establish freshness.
  Different parameter names, types, or identifier stamps alone do not establish
  separate instances; arbitrary pool parameters are undecided, not falsely banned.
- Unsupported destructuring, callback factories, partial-operation aliases,
  containers and cross-module helper bodies are not whole-program identity proofs.
  Relevant unresolved routing is undecided where visible in the supported context.
  Hidden SQL behind unconstrained polymorphic opaque APIs is outside this horizon.
- Known operation diagnostics locate the runner expression; unavailable routing
  locates the call/callback. There is no process-global finding store.

## Legitimate counterexamples

The transaction binder and its aliases, proven independent pools, operations
after the callback, and separately launched borrowers outside the transaction
callback are clean. A same-spelled local function named `execute` is
not a SQL operation. Unresolved helper routing may still be undecided when that
function actually receives a runner. Identifier spelling is never identity proof.

## Verification and integration

The native suite in `test/lint/safety_transaction_runner` copies the nested,
data-only evidence project to an external directory and explicitly compiles each
interface before its implementation. It checks literal filename/category/physical
span multisets, retaining duplicates; same-count duplicate-site and wrong-site
controls must fail. It exercises independent-pool controls, located undecided
routing and the actual SQL migration callback. The supported production site in `lib/sql/migrate.ml`
already uses its transaction binder; no production migration is necessary.

The public runtime fixture uses a one-connection memory pool and a three-second
outer deadline. Correct runner work commits on success, rolls back returned
errors and raised defects, and preserves the primary outcome. A bad pool runner
has a 10 ms deadline and fails without hanging or changing rows. ^safe-r1xw

`check-installed.sh` takes an absolute genuinely installed `ox-lint` binary, its
installed `ox_lint` share root, and the dependency installation prefix. It rejects
checkout/build-tree evidence. The share carries the clean/violating ML/MI triangle
and nested undecided fixture; the prefix supplies installed SQL compiler context.
Consumer compilation, invocation cwd and `--self-check` run outside the checkout,
without source-root fallback or Git asset lookup. Positive, clean, undecided,
missing, mismatched and stale evidence must have their respective exit statuses.
A separate serialized acceptance performs a genuine `dune install` and invokes
this installed script; it runs outside an enclosing Dune build to avoid recursive
workspace locking. Build-tree-library native testing is separately named, not passed off as
installed acceptance. Registry activation is reported by the running CLI. No production or test-file
exemption is added.
