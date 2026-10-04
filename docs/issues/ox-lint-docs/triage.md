# Interface documentation triage

^nlintd-a7oq ^nlintd-6abn ^nlintd-4ja0 ^nlintd-truth ^nlintd-raises. This is the explicit-val accounting ledger, not a suppression list. The [contract](<../../rules/interface-documentation.md>) checks effective attached/inherited fields against compiler-matched implementations and names unresolved evidence. This documentation audit changes no interface types or production implementations. Concurrent engine/Resource work is accounted separately below.

## Numerical accounting

The current production inventory is **98 interfaces / 1,308 explicit vals**: **229 selected**, **1,079 unrelated vals excluded**. Including the nine lint-engine interfaces gives **107 interfaces / 1,358 vals**, **268 selected** and **1,090 unrelated vals excluded**. The lint engine contributes 50 vals, 39 selected. These replace the stale historical 97-interface / 225-selected ledger.

| Scope | Selected vals | Complete effective behaviour shape | Complete required safety shape | Unaccounted |
| --- | ---: | ---: | ---: | ---: |
| Production interfaces | 229 | 229 | 229 | 0 |
| Lint-engine interfaces, separate worker | 39 | 39 | 39 | 0 |
| Whole-library typed inventory | 268 | 268 | 268 | 0 |

“Complete safety shape” includes a documented non-cancellation/protected exemption when no safety sentence is required. Named module defaults inherit only the applicable fields; a local cancellation/suspension override has its own safety claim when needed. No selected val remains merely reason-listed instead of documented.

### Before/after diagnostics

| Captured scope | ox-val-behaviour before | ox-cancel-safety before | Final behaviour | Final safety |
| --- | ---: | ---: | ---: | ---: |
| Historical request baseline | 89 | 79 | 0 | 0 |
| Initial local whole-library scan | 82 | 78 | 0 | 0 |
| Initial local production subset | 62 | 61 | 0 | 0 |
| Initial local lint-engine subset, separate worker | 20 | 17 | 0 | 0 |

The historical 168-finding baseline contained 73 missing behaviour blocks and 16 contradictions; the first locally captured 160-finding scan contained 66 missing blocks and 16 contradictions. These are different starting captures, not an asserted eight-finding reduction from a single recorded run. Production contributed 49 missing behaviour blocks and 13 contradictions to the local capture; the engine contributed 17 missing blocks and three contradictions. The initial local scan is preserved in [before evidence](</tmp/ox-doc-before.txt>); [final stdout](</tmp/ox-doc-final.txt>) is empty and [final stderr](</tmp/ox-doc-final.err>) contains only Nix's dirty-tree warning. Final strict scan exit: **0**.

Reproduce the inventory and strict contract scan after rebuilding typed evidence:

```sh
nix develop -c dune build @install @check
nix develop -c dune exec test/lint/doc_inventory.exe -- lib
nix develop -c _build/default/lib/ox_lint/main.exe --require-typed --rules ox-val-behaviour --rules ox-cancel-safety lib
```

The [inventory executable](<../../../test/lint/doc_inventory.ml>) writes one TSV row per selected val: source, line, qualified name, resolved families, behaviour shape and safety shape. [Final inventory](</tmp/ox-doc-final.tsv>) and [denominator](</tmp/ox-doc-final-inventory.err>) were regenerated after source formatting. Shapes and a zero-finding scan are not a proof about arbitrary future callback/provider implementations: those boundaries are explicitly named in the contracts.

## Corrected or qualified claims

| Interface contract | Implementation-derived behaviour |
| --- | --- |
| [create](<../../../lib/ox/actor.mli#L48>), [create](<../../../lib/ox/agent.mli#L47>) | A cancelled unfinished switch raises Eio.Cancel.Cancelled; a finished switch raises Invalid_argument. Starting a daemon can begin caller effects before return; cancellation loses progress rather than making startup safe to replay. Actor body/on_stop defects can combine as Eio.Exn.Multiple. |
| [Changes.close](<../../../lib/ox/actor.mli#L154>), [changes](<../../../lib/ox/actor.mli#L166>) | Both terminal additions have a free-slot invariant: close drains the buffer and subscription creates a new empty buffer. They do not suspend or check cancellation. Subscription performs no switch check; it does not reject an already-cancelled owning switch. The comparison arguments are integers; numeric-bound Invalid_argument is distinct from polymorphic functional comparison. Subscription capacity + 1 overflow also reaches Invalid_argument. |
| [Stdlib wrappers](<../../../lib/caps/cap_stdlib.mli>), [Sys wrappers](<../../../lib/caps/cap_sys.mli>), [Unix wrappers](<../../../lib/caps/cap_unix.mli>) | Wrappers add no Eio suspension/check; native I/O may block the domain. Formatter printers, supplied callbacks and exit hooks retain their own effects. Sys metadata/constants are not all blocking calls. Returned channels/descriptors remain caller-owned except documented brackets. Writable-open validation and delegated Unix errors are not hidden. |
| [race](<../../../lib/ox/concurrent.mli#L56>), [race_first](<../../../lib/ox/concurrent.mli#L64>), [Scope forks](<../../../lib/ox/scope.mli>) | Race chooses first success, or typed failure only when every branch fails; race_first chooses the first completed outcome. Other parallel combinators end on first typed error/exception. Simultaneous defects can combine. Scope forks delegate to Eio; finished or wrong-domain switches raise Invalid_argument, stated as precise prose rather than an unsupported local @raise witness. |
| [read_regular](<../../../lib/app/config.mli#L116>), [serve](<../../../lib/app/ox_app.mli#L64>) | Negative limits and service bounds are actual validation failures; config channel cleanup is bracketed. Delegated parsers/filesystem/provider operations retain their own behaviour. |
| [run_for_test_with_args](<../../../lib/app/ox_app.mli#L79>), [run_for_test](<../../../lib/app/ox_app.mli#L203>) | Supplying both telemetry hooks triggers Invalid_argument inside Scope.run. It is classified/rendered using defect_exit, not directly raised to the test runner's caller. In contrast, invalid wakeup_ms or OX_POSIX_WAKEUP_MS in outer run/exit entry points fails before the inner program scope; run_and_exit does not invoke Stdlib.exit then. |
| [HTTP server](<../../../lib/http/server.mli>), [HTTP service](<../../../lib/http/service.mli>), [IPC listener](<../../../lib/ipc/listener.mli>), [WebSocket connect](<../../../lib/http/ws_client.mli>), [OTel create](<../../../lib/otel/ox_otel.mli>) | Bounds and finished-switch/provider checks can raise Invalid_argument. Starting serving/export fibers is not pure allocation; ownership and callback progress are explicit. Exporter cleanup callback failure can propagate as Eio.Switch.Release_error; its terminal-event assertion is stated under the bounded-queue invariant. |
| [TLS flow create](<../../../lib/http/tls_flow.mli>), [AI transport](<../../../lib/ai/transport.mli>) | Native TLS handshake/session defects raise Tls_failure rather than only returning typed transport errors. Retry/deadline cleanup owns each socket, but request/callback effects may already have committed. The transport status assertion is disclosed as the exhaustive-classification invariant. |
| [Source.resolve](<../../../lib/sql/migrate.mli#L115>), [run](<../../../lib/sql/migrate.mli#L129>), [run_to](<../../../lib/sql/migrate.mli#L141>), [undo](<../../../lib/sql/migrate.mli#L153>) | Initial Cap_sys.readdir is outside the per-file loop handler: directory enumeration Sys_error propagates. Per-file read failures become Source_error. Migration/pooled cleanup can propagate Fun.Finally_raised; not every failure is converted to a migration error. |
| [SQL pool operations](<../../../lib/sql/pool.mli>), [SQL connection](<../../../lib/sql/connection.mli>) | Lease waiting can suspend; native SQLite work can block the domain, and an exclusive lease/native mutex may span row callbacks. Return/restoration and active-count cleanup are protected; defects during those finalizers are wrapped by Fun.Finally_raised. Database rollback does not undo arbitrary callback effects. Phantom transaction restrictions exclude the documented Transaction invariant branches. |
| [Testing.with_db](<../../../lib/sql/sqlite.mli#L277>) | Opening and callback ordinary exceptions become Error strings; cancellation propagates. Temporary-path setup happens before those catches. Close and outer unlink cleanup run through nested Fun.protect; failing cleanup escapes as Fun.Finally_raised rather than being converted by the opening/callback exception cases. |
| [spawn](<../../../lib/process/child.mli#L13>), [start](<../../../lib/process/supervised.mli#L16>), [supervisor startup](<../../../lib/ox/supervisor.mli>) | Partial startup has owned switch cleanup; child effects cannot be replayed generically. Private-switch release callback failure propagates as Eio.Switch.Release_error. Multiple recorded supervisor defects combine as Eio.Exn.Multiple and are classified by the owning Scope.run. |
| [RPC correlator](<../../../lib/rpc/correlator.mli>), [test runner helpers](<../../../lib/test/ox_test.mli>) | Reader/pending state, protected writes, disposal and caller progress are distinct. Mock-clock advance mutates before yielding, so replay can advance twice. Process/mock-flow providers, native pipe requirements and Eio fork validation are explicitly delegated, not invented local @raise witnesses. |

The free-slot conclusion was checked against [Eio stream implementation](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/stream.ml>); [Eio fork](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/fiber.ml#L11-L27>) calls [check_our_domain](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/switch.ml#L40-L48>). Non-Eio domain blocking, masking, switch release and Fun.protect wrapper identity are kept separate.

## Unresolved evidence and ownership

**No unqualified typed evidence remains unresolved in the strict library scan.** The final repository capability gate reports **0 findings and 0 modules with typed rules undecided**. Named callback, provider, native and Stdlib delegates remain intentional API boundaries; their runtime behaviour is not certified by pretending they are pure known leaves. Impossible assertions/type-excluded branches are disclosed as invariants, and real raises with opaque paths are described in precise prose instead of unsupported @raise tags.

The lint-engine implementations/interfaces and Resource semantic work belonged to separate workers; this ledger records their final inventory without claiming this documentation worker changed them. Other reserved implementations/interfaces were not modified. The [clean truth fixture](<../../../test/lint/clean/docs_truth.mli>), [clean safety fixture](<../../../test/lint/clean/cancel_safety.mli>) and [clean behaviour fixture](<../../../test/lint/clean/val_behaviour.mli>) received documentation shape/dependency completion only. Safety grammar examples remain identified as inert shape fixtures. Intentionally violating fixtures, implementation bodies, types, assertions and allow-lists were not changed to make the gate pass.

## Final gates

Executed in this exact order with direct capture and no pipes; no interface edits followed this final run:

| Command | Exit | Captured output |
| --- | ---: | --- |
| `nix develop -c dune build @fmt; echo rc=$?` | 0 | [format](</tmp/ox-interface-final-fmt.txt>) |
| `nix develop -c dune build @install @check; echo rc=$?` | 0 | [install/check](</tmp/ox-interface-final-build.txt>) |
| `nix develop -c dune test; echo rc=$?` | 0 | [tests](</tmp/ox-interface-final-test.txt>) |
| `nix develop -c scripts/caps-gate; echo rc=$?` | 0 | [capability gate](</tmp/ox-interface-final-caps.txt>) |

## Documented production selected vals (229)

Every row has the complete effective behaviour shape and required safety shape. Defaults account for many wrapper/accessor operations; local overrides carry their own exact dependency and safety disclosures. The implementation links identify the paired source, including thin re-exports.

| Interface val | Typed families | Implementation |
| --- | --- | --- |
| [ai/transport.mli · post_json](<../../../lib/ai/transport.mli#L55>) | clock,flow/capability | [source](<../../../lib/ai/transport.ml>) |
| [ai_chat/chat.mli · create](<../../../lib/ai_chat/chat.mli#L24>) | clock,flow/capability | [source](<../../../lib/ai_chat/chat.ml>) |
| [ai_chat/ox_ai_chat.mli · create](<../../../lib/ai_chat/ox_ai_chat.mli#L27>) | clock,flow/capability | [source](<../../../lib/ai_chat/ox_ai_chat.ml>) |
| [ai_openrouter/common.mli · post](<../../../lib/ai_openrouter/common.mli#L15>) | clock,flow/capability | [source](<../../../lib/ai_openrouter/common.ml>) |
| [ai_openrouter/embeddings.mli · create](<../../../lib/ai_openrouter/embeddings.mli#L20>) | clock,flow/capability | [source](<../../../lib/ai_openrouter/embeddings.ml>) |
| [ai_openrouter/responses.mli · create](<../../../lib/ai_openrouter/responses.mli#L118>) | clock,flow/capability | [source](<../../../lib/ai_openrouter/responses.ml>) |
| [ai_openrouter/responses.mli · create_text](<../../../lib/ai_openrouter/responses.mli#L144>) | clock,flow/capability | [source](<../../../lib/ai_openrouter/responses.ml>) |
| [ai_realtime/session.mli · connect](<../../../lib/ai_realtime/session.mli#L16>) | clock,flow/capability,switch | [source](<../../../lib/ai_realtime/session.ml>) |
| [ai_systemone/client.mli · create](<../../../lib/ai_systemone/client.mli#L31>) | clock,flow/capability | [source](<../../../lib/ai_systemone/client.ml>) |
| [app/config.mli · read_regular](<../../../lib/app/config.mli#L116>) | flow/capability | [source](<../../../lib/app/config.ml>) |
| [app/ox_app.mli · SERVICE.create](<../../../lib/app/ox_app.mli#L51>) | switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · serve](<../../../lib/app/ox_app.mli#L64>) | switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · request_stop](<../../../lib/app/ox_app.mli#L73>) | switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_for_test_with_args](<../../../lib/app/ox_app.mli#L79>) | capability,clock,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_for_test](<../../../lib/app/ox_app.mli#L203>) | capability,clock,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_with_args](<../../../lib/app/ox_app.mli#L291>) | capability,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run](<../../../lib/app/ox_app.mli#L360>) | capability,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_and_exit_with_args](<../../../lib/app/ox_app.mli#L435>) | capability,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_and_exit](<../../../lib/app/ox_app.mli#L516>) | capability,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · posix_wakeup](<../../../lib/app/ox_app.mli#L577>) | capability,clock,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · with_powerbox](<../../../lib/app/ox_app.mli#L610>) | capability | [source](<../../../lib/app/ox_app.ml>) |
| [app/ox_app.mli · run_simple](<../../../lib/app/ox_app.mli#L621>) | capability,flow/capability,switch | [source](<../../../lib/app/ox_app.ml>) |
| [blocking/ox_blocking.mli · Pool.create](<../../../lib/blocking/ox_blocking.mli#L34>) | pool,switch | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · Pool.shutdown_policy](<../../../lib/blocking/ox_blocking.mli#L47>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · Pool.stats](<../../../lib/blocking/ox_blocking.mli#L53>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · Pool.shutdown](<../../../lib/blocking/ox_blocking.mli#L59>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · run](<../../../lib/blocking/ox_blocking.mli#L92>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · try_run](<../../../lib/blocking/ox_blocking.mli#L116>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · run_result](<../../../lib/blocking/ox_blocking.mli#L125>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · try_run_result](<../../../lib/blocking/ox_blocking.mli#L134>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · run_result_timeout](<../../../lib/blocking/ox_blocking.mli#L142>) | clock,flow/capability,pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · try_run_result_timeout](<../../../lib/blocking/ox_blocking.mli#L155>) | clock,flow/capability,pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [caps/cap_stdlib.mli · exit](<../../../lib/caps/cap_stdlib.mli#L26>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · stdin](<../../../lib/caps/cap_stdlib.mli#L36>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · read_line](<../../../lib/caps/cap_stdlib.mli#L37>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · stdout](<../../../lib/caps/cap_stdlib.mli#L38>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · std_formatter](<../../../lib/caps/cap_stdlib.mli#L39>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_string](<../../../lib/caps/cap_stdlib.mli#L40>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_bytes](<../../../lib/caps/cap_stdlib.mli#L41>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_char](<../../../lib/caps/cap_stdlib.mli#L42>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_int](<../../../lib/caps/cap_stdlib.mli#L43>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_float](<../../../lib/caps/cap_stdlib.mli#L44>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_endline](<../../../lib/caps/cap_stdlib.mli#L45>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_newline](<../../../lib/caps/cap_stdlib.mli#L46>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · printf](<../../../lib/caps/cap_stdlib.mli#L48>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · stderr](<../../../lib/caps/cap_stdlib.mli#L55>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · err_formatter](<../../../lib/caps/cap_stdlib.mli#L56>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_string](<../../../lib/caps/cap_stdlib.mli#L57>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_bytes](<../../../lib/caps/cap_stdlib.mli#L58>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_char](<../../../lib/caps/cap_stdlib.mli#L59>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_int](<../../../lib/caps/cap_stdlib.mli#L60>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_float](<../../../lib/caps/cap_stdlib.mli#L61>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_endline](<../../../lib/caps/cap_stdlib.mli#L62>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_newline](<../../../lib/caps/cap_stdlib.mli#L63>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · eprintf](<../../../lib/caps/cap_stdlib.mli#L65>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in](<../../../lib/caps/cap_stdlib.mli#L74>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in_bin](<../../../lib/caps/cap_stdlib.mli#L75>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in_gen](<../../../lib/caps/cap_stdlib.mli#L77>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out](<../../../lib/caps/cap_stdlib.mli#L80>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out_bin](<../../../lib/caps/cap_stdlib.mli#L81>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out_gen](<../../../lib/caps/cap_stdlib.mli#L83>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.open_bin](<../../../lib/caps/cap_stdlib.mli#L87>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.open_text](<../../../lib/caps/cap_stdlib.mli#L88>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.with_open_bin](<../../../lib/caps/cap_stdlib.mli#L90>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.with_open_text](<../../../lib/caps/cap_stdlib.mli#L98>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.with_open_gen](<../../../lib/caps/cap_stdlib.mli#L106>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_bin](<../../../lib/caps/cap_stdlib.mli#L122>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_text](<../../../lib/caps/cap_stdlib.mli#L123>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_gen](<../../../lib/caps/cap_stdlib.mli#L125>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.with_open_bin](<../../../lib/caps/cap_stdlib.mli#L132>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.with_open_text](<../../../lib/caps/cap_stdlib.mli#L140>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.with_open_gen](<../../../lib/caps/cap_stdlib.mli#L148>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Random.self_init](<../../../lib/caps/cap_stdlib.mli#L166>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Random.make_self_init](<../../../lib/caps/cap_stdlib.mli#L167>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.temp_file](<../../../lib/caps/cap_stdlib.mli#L173>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.open_temp_file](<../../../lib/caps/cap_stdlib.mli#L175>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.temp_dir](<../../../lib/caps/cap_stdlib.mli#L184>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_sys.mli · command](<../../../lib/caps/cap_sys.mli#L14>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · chdir](<../../../lib/caps/cap_sys.mli#L15>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · getenv](<../../../lib/caps/cap_sys.mli#L16>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · getenv_opt](<../../../lib/caps/cap_sys.mli#L17>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · signal](<../../../lib/caps/cap_sys.mli#L19>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · set_signal](<../../../lib/caps/cap_sys.mli#L24>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · time](<../../../lib/caps/cap_sys.mli#L29>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · readdir](<../../../lib/caps/cap_sys.mli#L30>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · remove](<../../../lib/caps/cap_sys.mli#L31>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · rename](<../../../lib/caps/cap_sys.mli#L32>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · mkdir](<../../../lib/caps/cap_sys.mli#L33>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · rmdir](<../../../lib/caps/cap_sys.mli#L34>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · urandom](<../../../lib/caps/cap_sys.mli#L39>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_unix.mli · fork](<../../../lib/caps/cap_unix.mli#L28>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execv](<../../../lib/caps/cap_unix.mli#L29>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execve](<../../../lib/caps/cap_unix.mli#L30>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execvp](<../../../lib/caps/cap_unix.mli#L31>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execvpe](<../../../lib/caps/cap_unix.mli#L32>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · create_process](<../../../lib/caps/cap_unix.mli#L34>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · create_process_env](<../../../lib/caps/cap_unix.mli#L43>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_in](<../../../lib/caps/cap_unix.mli#L53>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_out](<../../../lib/caps/cap_unix.mli#L54>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process](<../../../lib/caps/cap_unix.mli#L55>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_full](<../../../lib/caps/cap_unix.mli#L57>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args_in](<../../../lib/caps/cap_unix.mli#L63>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args_out](<../../../lib/caps/cap_unix.mli#L66>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args_full](<../../../lib/caps/cap_unix.mli#L69>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args](<../../../lib/caps/cap_unix.mli#L80>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · system](<../../../lib/caps/cap_unix.mli#L83>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · _exit](<../../../lib/caps/cap_unix.mli#L87>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · chdir](<../../../lib/caps/cap_unix.mli#L88>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · getenv](<../../../lib/caps/cap_unix.mli#L89>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · environment](<../../../lib/caps/cap_unix.mli#L90>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · putenv](<../../../lib/caps/cap_unix.mli#L92>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · kill](<../../../lib/caps/cap_unix.mli#L96>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · sigprocmask](<../../../lib/caps/cap_unix.mli#L98>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · time](<../../../lib/caps/cap_unix.mli#L101>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · gettimeofday](<../../../lib/caps/cap_unix.mli#L102>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · openfile](<../../../lib/caps/cap_unix.mli#L106>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · openfile_write](<../../../lib/caps/cap_unix.mli#L115>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_dev_null](<../../../lib/caps/cap_unix.mli#L127>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · opendir](<../../../lib/caps/cap_unix.mli#L132>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · unlink](<../../../lib/caps/cap_unix.mli#L133>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · rename](<../../../lib/caps/cap_unix.mli#L134>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · mkdir](<../../../lib/caps/cap_unix.mli#L135>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · rmdir](<../../../lib/caps/cap_unix.mli#L136>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · chmod](<../../../lib/caps/cap_unix.mli#L137>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · truncate](<../../../lib/caps/cap_unix.mli#L138>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · symlink](<../../../lib/caps/cap_unix.mli#L139>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · link](<../../../lib/caps/cap_unix.mli#L140>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · socket](<../../../lib/caps/cap_unix.mli#L144>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_connection](<../../../lib/caps/cap_unix.mli#L152>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · establish_server](<../../../lib/caps/cap_unix.mli#L155>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/door/ox_caps_door.mli · powerbox](<../../../lib/caps/door/ox_caps_door.mli#L23>) | capability | [source](<../../../lib/caps/door/ox_caps_door.ml>) |
| [http/client.mli · create](<../../../lib/http/client.mli#L10>) | clock,flow/capability,switch | [source](<../../../lib/http/client.ml>) |
| [http/server.mli · run_h1_on_socket](<../../../lib/http/server.mli#L127>) | flow/capability,switch | [source](<../../../lib/http/server.ml>) |
| [http/server.mli · run_h1](<../../../lib/http/server.mli#L145>) | flow/capability,switch | [source](<../../../lib/http/server.ml>) |
| [http/service.mli · Serve.h1](<../../../lib/http/service.mli#L83>) | flow/capability,switch | [source](<../../../lib/http/service.ml>) |
| [http/tls_flow.mli · create](<../../../lib/http/tls_flow.mli#L23>) | flow/capability | [source](<../../../lib/http/tls_flow.ml>) |
| [http/ws_client.mli · connect](<../../../lib/http/ws_client.mli#L30>) | clock,flow/capability,switch | [source](<../../../lib/http/ws_client.ml>) |
| [ipc/listener.mli · run](<../../../lib/ipc/listener.mli#L62>) | capability,clock,flow/capability,switch | [source](<../../../lib/ipc/listener.ml>) |
| [observability/logger.mli · Reporter.journal](<../../../lib/observability/logger.mli#L90>) | flow/capability | [source](<../../../lib/observability/logger.ml>) |
| [observability/logger.mli · create](<../../../lib/observability/logger.mli#L159>) | clock,flow/capability | [source](<../../../lib/observability/logger.ml>) |
| [otel/ox_otel.mli · create](<../../../lib/otel/ox_otel.mli#L40>) | capability,clock,flow/capability,switch | [source](<../../../lib/otel/ox_otel.ml>) |
| [ox/actor.mli · create](<../../../lib/ox/actor.mli#L48>) | actor,switch | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · ask](<../../../lib/ox/actor.mli#L93>) | actor,clock,flow/capability | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · tell](<../../../lib/ox/actor.mli#L115>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · try_tell](<../../../lib/ox/actor.mli#L124>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · state](<../../../lib/ox/actor.mli#L128>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.next](<../../../lib/ox/actor.mli#L141>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.dropped](<../../../lib/ox/actor.mli#L149>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.close](<../../../lib/ox/actor.mli#L154>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · changes](<../../../lib/ox/actor.mli#L166>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/agent.mli · create](<../../../lib/ox/agent.mli#L47>) | actor,switch | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · get](<../../../lib/ox/agent.mli#L70>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · update](<../../../lib/ox/agent.mli#L74>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · get_and_update](<../../../lib/ox/agent.mli#L78>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · cast](<../../../lib/ox/agent.mli#L84>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · update_result](<../../../lib/ox/agent.mli#L93>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · get_and_update_result](<../../../lib/ox/agent.mli#L101>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/channel.mli · create](<../../../lib/ox/channel.mli#L26>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · send](<../../../lib/ox/channel.mli#L32>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · receive](<../../../lib/ox/channel.mli#L40>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · try_send](<../../../lib/ox/channel.mli#L49>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · try_receive](<../../../lib/ox/channel.mli#L52>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · done_](<../../../lib/ox/channel.mli#L55>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · error](<../../../lib/ox/channel.mli#L60>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · wait_changed](<../../../lib/ox/channel.mli#L65>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/concurrent.mli · par](<../../../lib/ox/concurrent.mli#L27>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · both](<../../../lib/ox/concurrent.mli#L35>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · all](<../../../lib/ox/concurrent.mli#L42>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · for_each](<../../../lib/ox/concurrent.mli#L46>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · race](<../../../lib/ox/concurrent.mli#L56>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · race_first](<../../../lib/ox/concurrent.mli#L64>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/concurrent.mli · with_background](<../../../lib/ox/concurrent.mli#L69>) | switch | [source](<../../../lib/ox/concurrent.ml>) |
| [ox/rate_limiter.mli · create](<../../../lib/ox/rate_limiter.mli#L40>) | clock,flow/capability,switch | [source](<../../../lib/ox/rate_limiter.ml>) |
| [ox/resource.mli · use_in_scope](<../../../lib/ox/resource.mli#L27>) | switch | [source](<../../../lib/ox/resource.ml>) |
| [ox/resource.mli · use_closeable_in_scope](<../../../lib/ox/resource.mli#L31>) | flow/capability,switch | [source](<../../../lib/ox/resource.ml>) |
| [ox/retry.mli · retry](<../../../lib/ox/retry.mli#L24>) | clock,flow/capability | [source](<../../../lib/ox/retry.ml>) |
| [ox/retry.mli · repeat](<../../../lib/ox/retry.mli#L37>) | clock,flow/capability | [source](<../../../lib/ox/retry.ml>) |
| [ox/scope.mli · run](<../../../lib/ox/scope.mli#L12>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · supervised_error](<../../../lib/ox/scope.mli#L35>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · fork_error](<../../../lib/ox/scope.mli#L54>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · fork](<../../../lib/ox/scope.mli#L62>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · fork_daemon](<../../../lib/ox/scope.mli#L69>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · fork_error_daemon](<../../../lib/ox/scope.mli#L76>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · await](<../../../lib/ox/scope.mli#L83>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · switch](<../../../lib/ox/scope.mli#L91>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/select.mli · receive_clause](<../../../lib/ox/select.mli#L24>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · send_clause](<../../../lib/ox/select.mli#L33>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · timeout_clause](<../../../lib/ox/select.mli#L46>) | clock,flow/capability | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · receive](<../../../lib/ox/select.mli#L61>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/supervisor.mli · child](<../../../lib/ox/supervisor.mli#L111>) | switch | [source](<../../../lib/ox/supervisor.ml>) |
| [ox/supervisor.mli · template](<../../../lib/ox/supervisor.mli#L127>) | switch | [source](<../../../lib/ox/supervisor.ml>) |
| [ox/supervisor.mli · start](<../../../lib/ox/supervisor.mli#L175>) | clock,flow/capability,switch | [source](<../../../lib/ox/supervisor.ml>) |
| [ox/supervisor.mli · start_simple](<../../../lib/ox/supervisor.mli#L243>) | clock,flow/capability,switch | [source](<../../../lib/ox/supervisor.ml>) |
| [ox/timeout.mli · timeout](<../../../lib/ox/timeout.mli#L1>) | clock,flow/capability | [source](<../../../lib/ox/timeout.ml>) |
| [process/child.mli · spawn](<../../../lib/process/child.mli#L13>) | capability,clock,flow/capability,switch | [source](<../../../lib/process/child.ml>) |
| [process/child.mli · stdout](<../../../lib/process/child.mli#L62>) | flow/capability | [source](<../../../lib/process/child.ml>) |
| [process/child.mli · stderr](<../../../lib/process/child.mli#L68>) | flow/capability | [source](<../../../lib/process/child.ml>) |
| [process/supervised.mli · start](<../../../lib/process/supervised.mli#L16>) | clock,flow/capability,switch | [source](<../../../lib/process/supervised.ml>) |
| [process/supervised.mli · events](<../../../lib/process/supervised.mli#L47>) | channel | [source](<../../../lib/process/supervised.ml>) |
| [rpc/correlator.mli · create](<../../../lib/rpc/correlator.mli#L16>) | clock,flow/capability,switch | [source](<../../../lib/rpc/correlator.ml>) |
| [rpc/correlator.mli · notifications](<../../../lib/rpc/correlator.mli#L62>) | channel | [source](<../../../lib/rpc/correlator.ml>) |
| [sql/connection.mli · create](<../../../lib/sql/connection.mli#L12>) | capability | [source](<../../../lib/sql/connection.ml>) |
| [sql/migrate.mli · Source.resolve](<../../../lib/sql/migrate.mli#L115>) | capability | [source](<../../../lib/sql/migrate.ml>) |
| [sql/migrate.mli · list_applied](<../../../lib/sql/migrate.mli#L127>) | pool | [source](<../../../lib/sql/migrate.ml>) |
| [sql/migrate.mli · run](<../../../lib/sql/migrate.mli#L129>) | capability,pool | [source](<../../../lib/sql/migrate.ml>) |
| [sql/migrate.mli · run_to](<../../../lib/sql/migrate.mli#L141>) | capability,pool | [source](<../../../lib/sql/migrate.ml>) |
| [sql/migrate.mli · undo](<../../../lib/sql/migrate.mli#L153>) | capability,pool | [source](<../../../lib/sql/migrate.ml>) |
| [sql/pool.mli · create](<../../../lib/sql/pool.mli#L22>) | capability,clock,flow/capability,pool,switch | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · shutdown](<../../../lib/sql/pool.mli#L38>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Typed.select](<../../../lib/sql/pool.mli#L47>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Typed.returning](<../../../lib/sql/pool.mli#L48>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Typed.fold_select](<../../../lib/sql/pool.mli#L49>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Typed.execute_compiled](<../../../lib/sql/pool.mli#L50>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Typed.run_schema](<../../../lib/sql/pool.mli#L51>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Raw.query](<../../../lib/sql/pool.mli#L54>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Raw.fold](<../../../lib/sql/pool.mli#L55>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Raw.execute](<../../../lib/sql/pool.mli#L56>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Raw.execute_script](<../../../lib/sql/pool.mli#L57>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · Raw.with_connection](<../../../lib/sql/pool.mli#L58>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/pool.mli · with_transaction](<../../../lib/sql/pool.mli#L60>) | pool | [source](<../../../lib/sql/pool.ml>) |
| [sql/sqlite.mli · Testing.with_db](<../../../lib/sql/sqlite.mli#L277>) | capability | [source](<../../../lib/sql/sqlite.ml>) |
| [test/ox_test.mli · run](<../../../lib/test/ox_test.mli#L12>) | flow/capability,switch | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · advance](<../../../lib/test/ox_test.mli#L23>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · fork_run](<../../../lib/test/ox_test.mli#L33>) | switch | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · powerbox](<../../../lib/test/ox_test.mli#L76>) | capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · flow_pair](<../../../lib/test/ox_test.mli#L89>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.make](<../../../lib/test/ox_test.mli#L125>) | clock,flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.mgr](<../../../lib/test/ox_test.mli#L141>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.spawns](<../../../lib/test/ox_test.mli#L163>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |

## Separately owned lint-engine selected vals (39)

All effective shapes are complete. These entries explain the difference between the production and whole-library denominators, not additional work claimed by the interface-documentation worker.

| Interface val | Typed families | Implementation |
| --- | --- | --- |
| [ox_lint/artifact.mli · ignored](<../../../lib/ox_lint/artifact.mli#L20>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · workspace](<../../../lib/ox_lint/artifact.mli#L31>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · read](<../../../lib/ox_lint/artifact.mli#L39>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · membership](<../../../lib/ox_lint/artifact.mli#L44>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · generated_sources](<../../../lib/ox_lint/artifact.mli#L58>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · find](<../../../lib/ox_lint/artifact.mli#L68>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · setup](<../../../lib/ox_lint/artifact.mli#L73>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · rebuild_check](<../../../lib/ox_lint/artifact.mli#L78>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/artifact.mli · check](<../../../lib/ox_lint/artifact.mli#L85>) | capability | [source](<../../../lib/ox_lint/artifact.ml>) |
| [ox_lint/caps.mli · source](<../../../lib/ox_lint/caps.mli#L21>) | capability | [source](<../../../lib/ox_lint/caps.ml>) |
| [ox_lint/caps.mli · raw](<../../../lib/ox_lint/caps.mli#L29>) | capability | [source](<../../../lib/ox_lint/caps.ml>) |
| [ox_lint/caps.mli · signature](<../../../lib/ox_lint/caps.mli#L35>) | capability | [source](<../../../lib/ox_lint/caps.ml>) |
| [ox_lint/caps_policy.mli · self_check](<../../../lib/ox_lint/caps_policy.mli#L16>) | capability | [source](<../../../lib/ox_lint/caps_policy.ml>) |
| [ox_lint/caps_policy.mli · declares_door](<../../../lib/ox_lint/caps_policy.mli#L24>) | capability | [source](<../../../lib/ox_lint/caps_policy.ml>) |
| [ox_lint/caps_policy.mli · check_dune](<../../../lib/ox_lint/caps_policy.mli#L28>) | capability | [source](<../../../lib/ox_lint/caps_policy.ml>) |
| [ox_lint/caps_policy.mli · declares_test](<../../../lib/ox_lint/caps_policy.mli#L32>) | capability | [source](<../../../lib/ox_lint/caps_policy.ml>) |
| [ox_lint/caps_policy.mli · private_module](<../../../lib/ox_lint/caps_policy.mli#L35>) | capability | [source](<../../../lib/ox_lint/caps_policy.ml>) |
| [ox_lint/concurrency.mli · catch_all](<../../../lib/ox_lint/concurrency.mli#L16>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/concurrency.mli · suspending_finalizer](<../../../lib/ox_lint/concurrency.mli#L20>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/concurrency.mli · stdlib_lock](<../../../lib/ox_lint/concurrency.mli#L24>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/concurrency.mli · raw_concurrency](<../../../lib/ox_lint/concurrency.mli#L29>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/concurrency.mli · obj_magic](<../../../lib/ox_lint/concurrency.mli#L33>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/concurrency.mli · race_deadline](<../../../lib/ox_lint/concurrency.mli#L37>) | capability | [source](<../../../lib/ox_lint/concurrency.ml>) |
| [ox_lint/interface_docs.mli · iterator](<../../../lib/ox_lint/interface_docs.mli#L30>) | capability | [source](<../../../lib/ox_lint/interface_docs.ml>) |
| [ox_lint/interface_docs.mli · behaviour](<../../../lib/ox_lint/interface_docs.mli#L34>) | capability | [source](<../../../lib/ox_lint/interface_docs.ml>) |
| [ox_lint/interface_docs.mli · cancel_safety](<../../../lib/ox_lint/interface_docs.mli#L37>) | capability | [source](<../../../lib/ox_lint/interface_docs.ml>) |
| [ox_lint/interface_docs.mli · truth](<../../../lib/ox_lint/interface_docs.mli#L40>) | capability | [source](<../../../lib/ox_lint/interface_docs.ml>) |
| [ox_lint/paths.mli · env](<../../../lib/ox_lint/paths.mli#L14>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · value](<../../../lib/ox_lint/paths.mli#L18>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · module_](<../../../lib/ox_lint/paths.mli#L20>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · is_value](<../../../lib/ox_lint/paths.mli#L23>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · in_module](<../../../lib/ox_lint/paths.mli#L24>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · values](<../../../lib/ox_lint/paths.mli#L25>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/paths.mli · modules](<../../../lib/ox_lint/paths.mli#L26>) | capability | [source](<../../../lib/ox_lint/paths.ml>) |
| [ox_lint/rules.mli · all](<../../../lib/ox_lint/rules.mli#L32>) | capability | [source](<../../../lib/ox_lint/rules.ml>) |
| [ox_lint/rules.mli · select](<../../../lib/ox_lint/rules.mli#L45>) | capability | [source](<../../../lib/ox_lint/rules.ml>) |
| [ox_lint/rules.mli · self_check](<../../../lib/ox_lint/rules.mli#L48>) | capability | [source](<../../../lib/ox_lint/rules.ml>) |
| [ox_lint/syntax.mli · value_origin](<../../../lib/ox_lint/syntax.mli#L24>) | capability | [source](<../../../lib/ox_lint/syntax.ml>) |
| [ox_lint/syntax.mli · walk](<../../../lib/ox_lint/syntax.mli#L28>) | capability | [source](<../../../lib/ox_lint/syntax.ml>) |
