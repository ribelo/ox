# Interface documentation triage

^nlintd-a7oq ^nlintd-6abn. This is the explicit-val accounting ledger, not a suppression list. Missing claims below remain rule diagnostics. The [contract](<../../rules/interface-documentation.md>) checks sentence **shape, never truth**; tests and row 85 own behavioural evidence. No interface types or production implementations were changed for this audit.

## Numerical accounting

The compiler-matched production inventory is **97 interfaces / 1,301 explicit vals**, the same denominator as the historical spike. Typed family selection finds **225 / 1,301 vals** (17.29%); **1,076 unrelated vals are excluded**. The current whole-library tool run also scans nine lint-engine interfaces (41 vals): **106 interfaces / 1,342 vals**, with the same 225 selected values.

| Selected-val outcome | Count |
| --- | ---: |
| All required behaviour and safety shapes, including documented exemptions | 134 |
| Individually reason-listed below | 91 |
| Selected total | 225 |
| Missing behaviour shape (also missing safety) | 79 |
| Behaviour shaped but safety reason-listed | 12 |
| Unaccounted selected vals | 0 |

These are **effective attached/inherited** shapes, not a count of new comments. Existing selected comments that do not use the new field grammar are reason-listed rather than silently rewritten or treated as safe.

Reproduce after rebuilding typed evidence:

```sh
nix develop -c dune build @check test/lint/doc_inventory.exe
nix develop -c dune exec test/lint/doc_inventory.exe -- lib
```

[The inventory executable](<../../../test/lint/doc_inventory.ml>) writes one TSV row per selected val: source, line, qualified val name, resolved families, behaviour shape and cancellation-safety shape. It separately reports the explicit-val denominator. Excluding the lint-engine directory yields the production denominator above.

## Implementation-derived documentation

Capability wrappers were checked against [Stdlib wrappers](<../../../lib/caps/cap_stdlib.ml>), [Sys wrappers](<../../../lib/caps/cap_sys.ml>), [Unix wrappers](<../../../lib/caps/cap_unix.ml>) and [the door constructor](<../../../lib/caps/door/ox_caps_door.ml>). The wrappers add no Eio operation or cancellation check; callbacks/exit hooks are explicitly qualified, and Unix domain blocking is not called Eio suspension. Returned resource ownership stays with callers except explicit channel brackets.

Channel queue probes mutate without suspension; only their condition waits suspend, so cancellation there has not consumed/enqueued an item. Agent admission and reply waiting are separated: cast retries only its non-consuming admission, whereas request/reply calls may lose already-committed progress or a reply. Actor subscription waiting was also checked against the upstream Eio stream waiter cancellation path. Pure accessor/constructor claims come from bodies that only allocate/store values or return a field; constructors which actually start fibers, open a database or handshake are not called pure. Scope.await waits on a non-consuming promise. Select.receive joins its observer branches before the non-suspending channel probe. These source audits justify the written sentences; typed fixtures do not prove them.

### Documented selected vals (134)

Each row links the effective interface location and its implementation. Module defaults account for many capability wrappers and channel/accessor operations.

| Interface val | Typed families | Implementation |
| --- | --- | --- |
| [ai_chat/chat.mli · create](<../../../lib/ai_chat/chat.mli#L24>) | clock,flow/capability | [source](<../../../lib/ai_chat/chat.ml>) |
| [ai_chat/ox_ai_chat.mli · create](<../../../lib/ai_chat/ox_ai_chat.mli#L27>) | clock,flow/capability | [source](<../../../lib/ai_chat/ox_ai_chat.ml>) |
| [ai_systemone/client.mli · create](<../../../lib/ai_systemone/client.mli#L31>) | clock,flow/capability | [source](<../../../lib/ai_systemone/client.ml>) |
| [blocking/ox_blocking.mli · Pool.create](<../../../lib/blocking/ox_blocking.mli#L23>) | pool,switch | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · Pool.shutdown_policy](<../../../lib/blocking/ox_blocking.mli#L34>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [blocking/ox_blocking.mli · Pool.stats](<../../../lib/blocking/ox_blocking.mli#L40>) | pool | [source](<../../../lib/blocking/ox_blocking.ml>) |
| [caps/cap_stdlib.mli · stdin](<../../../lib/caps/cap_stdlib.mli#L32>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · read_line](<../../../lib/caps/cap_stdlib.mli#L33>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · stdout](<../../../lib/caps/cap_stdlib.mli#L34>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · std_formatter](<../../../lib/caps/cap_stdlib.mli#L35>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_string](<../../../lib/caps/cap_stdlib.mli#L36>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_bytes](<../../../lib/caps/cap_stdlib.mli#L37>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_char](<../../../lib/caps/cap_stdlib.mli#L38>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_int](<../../../lib/caps/cap_stdlib.mli#L39>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_float](<../../../lib/caps/cap_stdlib.mli#L40>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_endline](<../../../lib/caps/cap_stdlib.mli#L41>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · print_newline](<../../../lib/caps/cap_stdlib.mli#L42>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · stderr](<../../../lib/caps/cap_stdlib.mli#L50>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · err_formatter](<../../../lib/caps/cap_stdlib.mli#L51>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_string](<../../../lib/caps/cap_stdlib.mli#L52>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_bytes](<../../../lib/caps/cap_stdlib.mli#L53>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_char](<../../../lib/caps/cap_stdlib.mli#L54>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_int](<../../../lib/caps/cap_stdlib.mli#L55>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_float](<../../../lib/caps/cap_stdlib.mli#L56>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_endline](<../../../lib/caps/cap_stdlib.mli#L57>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · prerr_newline](<../../../lib/caps/cap_stdlib.mli#L58>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in](<../../../lib/caps/cap_stdlib.mli#L68>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in_bin](<../../../lib/caps/cap_stdlib.mli#L69>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_in_gen](<../../../lib/caps/cap_stdlib.mli#L71>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out](<../../../lib/caps/cap_stdlib.mli#L74>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out_bin](<../../../lib/caps/cap_stdlib.mli#L75>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · open_out_gen](<../../../lib/caps/cap_stdlib.mli#L77>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.open_bin](<../../../lib/caps/cap_stdlib.mli#L81>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · In_channel.open_text](<../../../lib/caps/cap_stdlib.mli#L82>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_bin](<../../../lib/caps/cap_stdlib.mli#L113>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_text](<../../../lib/caps/cap_stdlib.mli#L114>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Out_channel.open_gen](<../../../lib/caps/cap_stdlib.mli#L116>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Random.self_init](<../../../lib/caps/cap_stdlib.mli#L154>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Random.make_self_init](<../../../lib/caps/cap_stdlib.mli#L155>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.temp_file](<../../../lib/caps/cap_stdlib.mli#L161>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.open_temp_file](<../../../lib/caps/cap_stdlib.mli#L163>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_stdlib.mli · Filename.temp_dir](<../../../lib/caps/cap_stdlib.mli#L172>) | capability | [source](<../../../lib/caps/cap_stdlib.ml>) |
| [caps/cap_sys.mli · command](<../../../lib/caps/cap_sys.mli#L12>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · chdir](<../../../lib/caps/cap_sys.mli#L13>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · getenv](<../../../lib/caps/cap_sys.mli#L14>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · getenv_opt](<../../../lib/caps/cap_sys.mli#L15>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · signal](<../../../lib/caps/cap_sys.mli#L17>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · set_signal](<../../../lib/caps/cap_sys.mli#L22>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · time](<../../../lib/caps/cap_sys.mli#L27>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · readdir](<../../../lib/caps/cap_sys.mli#L28>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · remove](<../../../lib/caps/cap_sys.mli#L29>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · rename](<../../../lib/caps/cap_sys.mli#L30>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · mkdir](<../../../lib/caps/cap_sys.mli#L31>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · rmdir](<../../../lib/caps/cap_sys.mli#L32>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_sys.mli · urandom](<../../../lib/caps/cap_sys.mli#L37>) | capability | [source](<../../../lib/caps/cap_sys.ml>) |
| [caps/cap_unix.mli · fork](<../../../lib/caps/cap_unix.mli#L25>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execv](<../../../lib/caps/cap_unix.mli#L26>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execve](<../../../lib/caps/cap_unix.mli#L27>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execvp](<../../../lib/caps/cap_unix.mli#L28>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · execvpe](<../../../lib/caps/cap_unix.mli#L29>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · create_process](<../../../lib/caps/cap_unix.mli#L31>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · create_process_env](<../../../lib/caps/cap_unix.mli#L40>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_in](<../../../lib/caps/cap_unix.mli#L50>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_out](<../../../lib/caps/cap_unix.mli#L51>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process](<../../../lib/caps/cap_unix.mli#L52>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_full](<../../../lib/caps/cap_unix.mli#L54>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args_in](<../../../lib/caps/cap_unix.mli#L60>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args_out](<../../../lib/caps/cap_unix.mli#L62>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_process_args](<../../../lib/caps/cap_unix.mli#L65>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · system](<../../../lib/caps/cap_unix.mli#L68>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · _exit](<../../../lib/caps/cap_unix.mli#L72>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · chdir](<../../../lib/caps/cap_unix.mli#L73>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · getenv](<../../../lib/caps/cap_unix.mli#L74>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · environment](<../../../lib/caps/cap_unix.mli#L75>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · putenv](<../../../lib/caps/cap_unix.mli#L77>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · kill](<../../../lib/caps/cap_unix.mli#L81>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · sigprocmask](<../../../lib/caps/cap_unix.mli#L83>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · time](<../../../lib/caps/cap_unix.mli#L86>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · gettimeofday](<../../../lib/caps/cap_unix.mli#L87>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · openfile](<../../../lib/caps/cap_unix.mli#L91>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · openfile_write](<../../../lib/caps/cap_unix.mli#L100>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · opendir](<../../../lib/caps/cap_unix.mli#L115>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · unlink](<../../../lib/caps/cap_unix.mli#L116>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · rename](<../../../lib/caps/cap_unix.mli#L117>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · mkdir](<../../../lib/caps/cap_unix.mli#L118>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · rmdir](<../../../lib/caps/cap_unix.mli#L119>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · chmod](<../../../lib/caps/cap_unix.mli#L120>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · truncate](<../../../lib/caps/cap_unix.mli#L121>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · symlink](<../../../lib/caps/cap_unix.mli#L122>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · link](<../../../lib/caps/cap_unix.mli#L123>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · socket](<../../../lib/caps/cap_unix.mli#L127>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/cap_unix.mli · open_connection](<../../../lib/caps/cap_unix.mli#L135>) | capability | [source](<../../../lib/caps/cap_unix.ml>) |
| [caps/door/ox_caps_door.mli · powerbox](<../../../lib/caps/door/ox_caps_door.mli#L23>) | capability | [source](<../../../lib/caps/door/ox_caps_door.ml>) |
| [http/client.mli · create](<../../../lib/http/client.mli#L10>) | clock,flow/capability,switch | [source](<../../../lib/http/client.ml>) |
| [observability/logger.mli · Reporter.journal](<../../../lib/observability/logger.mli#L90>) | flow/capability | [source](<../../../lib/observability/logger.ml>) |
| [observability/logger.mli · create](<../../../lib/observability/logger.mli#L159>) | clock,flow/capability | [source](<../../../lib/observability/logger.ml>) |
| [ox/actor.mli · ask](<../../../lib/ox/actor.mli#L81>) | actor,clock,flow/capability | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · tell](<../../../lib/ox/actor.mli#L102>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · try_tell](<../../../lib/ox/actor.mli#L111>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · state](<../../../lib/ox/actor.mli#L115>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.next](<../../../lib/ox/actor.mli#L128>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.dropped](<../../../lib/ox/actor.mli#L136>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · Changes.close](<../../../lib/ox/actor.mli#L141>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/actor.mli · changes](<../../../lib/ox/actor.mli#L146>) | actor | [source](<../../../lib/ox/actor.ml>) |
| [ox/agent.mli · get](<../../../lib/ox/agent.mli#L64>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · update](<../../../lib/ox/agent.mli#L68>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · get_and_update](<../../../lib/ox/agent.mli#L72>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · cast](<../../../lib/ox/agent.mli#L78>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · update_result](<../../../lib/ox/agent.mli#L87>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/agent.mli · get_and_update_result](<../../../lib/ox/agent.mli#L95>) | actor | [source](<../../../lib/ox/agent.ml>) |
| [ox/channel.mli · create](<../../../lib/ox/channel.mli#L24>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · send](<../../../lib/ox/channel.mli#L30>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · receive](<../../../lib/ox/channel.mli#L37>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · try_send](<../../../lib/ox/channel.mli#L45>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · try_receive](<../../../lib/ox/channel.mli#L48>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · done_](<../../../lib/ox/channel.mli#L51>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · error](<../../../lib/ox/channel.mli#L56>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/channel.mli · wait_changed](<../../../lib/ox/channel.mli#L61>) | channel | [source](<../../../lib/ox/channel.ml>) |
| [ox/scope.mli · await](<../../../lib/ox/scope.mli#L56>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/scope.mli · switch](<../../../lib/ox/scope.mli#L64>) | switch | [source](<../../../lib/ox/scope.ml>) |
| [ox/select.mli · receive_clause](<../../../lib/ox/select.mli#L24>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · send_clause](<../../../lib/ox/select.mli#L33>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · timeout_clause](<../../../lib/ox/select.mli#L46>) | clock,flow/capability | [source](<../../../lib/ox/select.ml>) |
| [ox/select.mli · receive](<../../../lib/ox/select.mli#L61>) | channel | [source](<../../../lib/ox/select.ml>) |
| [ox/supervisor.mli · child](<../../../lib/ox/supervisor.mli#L111>) | switch | [source](<../../../lib/ox/supervisor.ml>) |
| [ox/supervisor.mli · template](<../../../lib/ox/supervisor.mli#L127>) | switch | [source](<../../../lib/ox/supervisor.ml>) |
| [process/child.mli · stdout](<../../../lib/process/child.mli#L42>) | flow/capability | [source](<../../../lib/process/child.ml>) |
| [process/child.mli · stderr](<../../../lib/process/child.mli#L48>) | flow/capability | [source](<../../../lib/process/child.ml>) |
| [process/supervised.mli · events](<../../../lib/process/supervised.mli#L30>) | channel | [source](<../../../lib/process/supervised.ml>) |
| [rpc/correlator.mli · notifications](<../../../lib/rpc/correlator.mli#L42>) | channel | [source](<../../../lib/rpc/correlator.ml>) |
| [test/ox_test.mli · powerbox](<../../../lib/test/ox_test.mli#L60>) | capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.make](<../../../lib/test/ox_test.mli#L104>) | clock,flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.mgr](<../../../lib/test/ox_test.mli#L115>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |
| [test/ox_test.mli · Process.spawns](<../../../lib/test/ox_test.mli#L136>) | flow/capability | [source](<../../../lib/test/ox_test.ml>) |

## Individual reason ledger (91)

A reason records exactly the unavailable claim, not an assertion that the operation is unsafe. Arbitrary callbacks can be documented as callback-dependent, but that alone does not establish one of the three retry-safety laws. No blanket “safe” paragraph has been invented for them.

| Interface val | Missing shape | Individual reason |
| --- | --- | --- |
| [ai/transport.mli · post_json](<../../../lib/ai/transport.mli#L40>) | behaviour + safety | The transport combines timeout, network I/O and response decoding; the request-sent/response-read cancellation boundary and remote retry law are not audited. |
| [ai_openrouter/common.mli · post](<../../../lib/ai_openrouter/common.mli#L7>) | behaviour + safety | The shared remote POST path is not audited for cancellation after transmission or server-side effects. |
| [ai_openrouter/embeddings.mli · create](<../../../lib/ai_openrouter/embeddings.mli#L13>) | behaviour + safety | Validation is followed by Common.post, not just allocation; cancellation after the embedding request is sent has no audited retry law. |
| [ai_openrouter/responses.mli · create](<../../../lib/ai_openrouter/responses.mli#L111>) | behaviour + safety | The encoded response request reaches Common.post; no audited cancellation/remote-completion law justifies a safety sentence. |
| [ai_openrouter/responses.mli · create_text](<../../../lib/ai_openrouter/responses.mli#L137>) | behaviour + safety | This response-creation variant also delegates to Common.post; retry safety after transmission is not established. |
| [ai_realtime/session.mli · connect](<../../../lib/ai_realtime/session.mli#L9>) | behaviour + safety | WebSocket establishment, handshake cleanup and cancellation after server acceptance need an upstream-plus-wrapper audit. |
| [app/config.mli · read_regular](<../../../lib/app/config.mli#L106>) | behaviour + safety | The open/stat/bounded-read path delegates cancellation and close ordering to the filesystem backend; that dependency boundary is not audited. |
| [app/ox_app.mli · SERVICE.create](<../../../lib/app/ox_app.mli#L34>) | behaviour + safety | This is an abstract module-type method, with no single implementation from which to derive callback suspension or safety. |
| [app/ox_app.mli · serve](<../../../lib/app/ox_app.mli#L47>) | behaviour + safety | The cancellation wait is visible, but a complete four-field contract and the enclosing service/switch lifecycle were not audited together. |
| [app/ox_app.mli · request_stop](<../../../lib/app/ox_app.mli#L54>) | behaviour + safety | Switch failure and cancellation-hook execution need an audited non-suspension/locking law before calling this request safe to repeat. |
| [app/ox_app.mli · run_for_test_with_args](<../../../lib/app/ox_app.mli#L60>) | behaviour + safety | Configuration, service startup and shutdown callbacks compose here; callback effects and partially-started service retry are unclassified. |
| [app/ox_app.mli · run_for_test](<../../../lib/app/ox_app.mli#L180>) | behaviour + safety | The test runner delegates startup/shutdown through the argument-taking runner; caller callbacks prevent an implementation-independent retry law. |
| [app/ox_app.mli · run_with_args](<../../../lib/app/ox_app.mli#L266>) | behaviour + safety | Signal handling, service creation and cleanup form a lifecycle; cancellation during partial startup is not classified. |
| [app/ox_app.mli · run](<../../../lib/app/ox_app.mli#L331>) | behaviour + safety | The public runner delegates the full application lifecycle; configuration and supplied service effects need individual lifecycle evidence. |
| [app/ox_app.mli · posix_wakeup](<../../../lib/app/ox_app.mli#L402>) | behaviour + safety | Signal-handler installation, cleanup and repeated installation need an audited ownership/cancellation contract. |
| [app/ox_app.mli · with_powerbox](<../../../lib/app/ox_app.mli#L423>) | behaviour + safety | The wrapper invokes arbitrary caller code with freshly minted authority; it cannot establish that code’s effects or retry safety. |
| [app/ox_app.mli · run_simple](<../../../lib/app/ox_app.mli#L434>) | behaviour + safety | The simple runner invokes caller application code and owns its switch; partial callback progress is not classified. |
| [blocking/ox_blocking.mli · Pool.shutdown](<../../../lib/blocking/ox_blocking.mli#L46>) | behaviour + safety | Drain/cancel shutdown changes pool state and waits for capacity; interrupted shutdown and repeated shutdown need a completion-race audit. |
| [blocking/ox_blocking.mli · run](<../../../lib/blocking/ox_blocking.mli#L57>) | behaviour + safety | Admission, worker completion and cancellation callbacks cross a thread/fiber boundary; repeating the supplied blocking job is not proven safe. |
| [blocking/ox_blocking.mli · try_run](<../../../lib/blocking/ox_blocking.mli#L79>) | behaviour + safety | Non-waiting admission does not classify cancellation after an admitted worker starts or its callback side effects. |
| [blocking/ox_blocking.mli · run_result](<../../../lib/blocking/ox_blocking.mli#L88>) | behaviour + safety | The result-classifying wrapper still launches an arbitrary blocking job; classification alone proves no retry law. |
| [blocking/ox_blocking.mli · try_run_result](<../../../lib/blocking/ox_blocking.mli#L97>) | behaviour + safety | The admitted-job completion/cancellation race remains unclassified despite non-waiting admission and result conversion. |
| [blocking/ox_blocking.mli · run_result_timeout](<../../../lib/blocking/ox_blocking.mli#L105>) | behaviour + safety | Timeout, cancellation notification and the still-running worker need a joint audit before retrying arbitrary jobs. |
| [blocking/ox_blocking.mli · try_run_result_timeout](<../../../lib/blocking/ox_blocking.mli#L118>) | behaviour + safety | Non-waiting admission still composes timeout callbacks with worker completion; their retained progress is not classified. |
| [caps/cap_stdlib.mli · exit](<../../../lib/caps/cap_stdlib.mli#L24>) | safety | Registered at_exit hooks are arbitrary caller code; hook progress before cancellation has no universal retry law. |
| [caps/cap_stdlib.mli · printf](<../../../lib/caps/cap_stdlib.mli#L44>) | safety | User formatter printers may suspend or commit output; a partially printed message has no audited general retry law. |
| [caps/cap_stdlib.mli · eprintf](<../../../lib/caps/cap_stdlib.mli#L60>) | safety | User formatter printers may suspend or commit stderr output; repeated printing cannot be classified universally. |
| [caps/cap_stdlib.mli · In_channel.with_open_bin](<../../../lib/caps/cap_stdlib.mli#L84>) | safety | Channel closure is documented, but the supplied input callback may consume data or commit arbitrary effects before cancellation. |
| [caps/cap_stdlib.mli · In_channel.with_open_text](<../../../lib/caps/cap_stdlib.mli#L91>) | safety | The supplied text-input callback may consume data or commit effects; automatic close does not establish its retry safety. |
| [caps/cap_stdlib.mli · In_channel.with_open_gen](<../../../lib/caps/cap_stdlib.mli#L98>) | safety | Opening flags and a supplied input callback do not provide a universal cancellation/consumption law. |
| [caps/cap_stdlib.mli · Out_channel.with_open_bin](<../../../lib/caps/cap_stdlib.mli#L123>) | safety | The supplied output callback may write before cancellation; closure does not establish whether a retry duplicates data. |
| [caps/cap_stdlib.mli · Out_channel.with_open_text](<../../../lib/caps/cap_stdlib.mli#L130>) | safety | The supplied text-output callback may partly commit output; its cancellation safety is caller-specific. |
| [caps/cap_stdlib.mli · Out_channel.with_open_gen](<../../../lib/caps/cap_stdlib.mli#L137>) | safety | Arbitrary open flags and output callback effects prevent a universal retry-safety sentence. |
| [caps/cap_unix.mli · establish_server](<../../../lib/caps/cap_unix.mli#L138>) | safety | The server callback is arbitrary and child/process effects may already exist; delegated Unix cleanup does not classify retry safety. |
| [http/server.mli · run_h1_on_socket](<../../../lib/http/server.mli#L114>) | behaviour + safety | Connection fibers, request-handler callbacks and draining need a combined cancellation/finalizer/locking audit. |
| [http/server.mli · run_h1](<../../../lib/http/server.mli#L128>) | behaviour + safety | Listener creation composes with connection serving and caller handlers; partial startup and shutdown retry are unclassified. |
| [http/service.mli · Serve.h1](<../../../lib/http/service.mli#L71>) | behaviour + safety | This calls Server.run_h1 rather than merely storing dependencies; serving/draining and handler effects inherit an unaudited lifecycle. |
| [http/tls_flow.mli · create](<../../../lib/http/tls_flow.mli#L6>) | behaviour + safety | Construction invokes handshake; transport I/O and TLS session progress are not a pure allocation or an audited retry law. |
| [http/ws_client.mli · connect](<../../../lib/http/ws_client.mli#L16>) | behaviour + safety | Upgrade I/O, transport ownership and cancellation after peer acceptance are not audited as one connection-establishment contract. |
| [ipc/listener.mli · run](<../../../lib/ipc/listener.mli#L48>) | behaviour + safety | Listener ownership, accepted connections and callbacks form a long-lived lifecycle whose cancellation ordering is not classified. |
| [otel/ox_otel.mli · create](<../../../lib/otel/ox_otel.mli#L35>) | behaviour + safety | Exporter startup and background fibers are not a pure constructor; cancellation during partial initialization lacks a full lifecycle audit. |
| [ox/actor.mli · create](<../../../lib/ox/actor.mli#L46>) | safety | Behaviour and switch exception distinctions are documented; retry after startup/initial-state callback progress needs a cancellation-race audit. |
| [ox/agent.mli · create](<../../../lib/ox/agent.mli#L46>) | safety | Behaviour and switch exception distinctions are documented; protected initialization and later startup waits need a single retry-safety audit. |
| [ox/concurrent.mli · par](<../../../lib/ox/concurrent.mli#L15>) | behaviour + safety | Both supplied computations may commit effects; fork/join cancellation ordering does not establish a universal retry law. |
| [ox/concurrent.mli · both](<../../../lib/ox/concurrent.mli#L23>) | behaviour + safety | Pairing two arbitrary computations preserves their caller-specific side effects; whole-operation retry is unclassified. |
| [ox/concurrent.mli · all](<../../../lib/ox/concurrent.mli#L30>) | behaviour + safety | The list of supplied computations may partly complete before cancellation; completed work cannot be classified generically. |
| [ox/concurrent.mli · for_each](<../../../lib/ox/concurrent.mli#L34>) | behaviour + safety | Some supplied element callbacks may complete before cancellation; replay safety depends on those callbacks. |
| [ox/concurrent.mli · race](<../../../lib/ox/concurrent.mli#L44>) | behaviour + safety | Cancelled losing computations may already have side effects; first-success selection is not a retry-safety guarantee. |
| [ox/concurrent.mli · race_first](<../../../lib/ox/concurrent.mli#L52>) | behaviour + safety | First-result selection still cancels arbitrary losers with potentially retained effects; whole-race replay is unclassified. |
| [ox/concurrent.mli · with_background](<../../../lib/ox/concurrent.mli#L57>) | behaviour + safety | Background and body callbacks may both make progress; their cleanup/join boundary and replay law need callback-specific evidence. |
| [ox/rate_limiter.mli · create](<../../../lib/ox/rate_limiter.mli#L40>) | behaviour + safety | Limiter setup forks a replenishment fiber; partial startup and cancellation-hook ownership need an audit, unlike a pure config constructor. |
| [ox/resource.mli · use_in_scope](<../../../lib/ox/resource.mli#L10>) | behaviour + safety | Acquisition and release are arbitrary callbacks; the acquire/register cancellation window and repeating acquisition need callback-specific evidence. |
| [ox/resource.mli · use_closeable_in_scope](<../../../lib/ox/resource.mli#L14>) | behaviour + safety | The supplied acquisition callback and close implementation govern suspension and retry; switch ownership alone is insufficient. |
| [ox/retry.mli · retry](<../../../lib/ox/retry.mli#L16>) | behaviour + safety | Schedule waits wrap an arbitrary operation that may already have committed effects; its cancellation safety is not implied by retry policy. |
| [ox/retry.mli · repeat](<../../../lib/ox/retry.mli#L29>) | behaviour + safety | Repeated arbitrary callbacks and schedule waits cannot establish whether cancelled progress can be replayed. |
| [ox/scope.mli · run](<../../../lib/ox/scope.mli#L1>) | behaviour + safety | The boundary classifies exceptions but executes an arbitrary body; classification does not establish body replay safety. |
| [ox/scope.mli · supervised_error](<../../../lib/ox/scope.mli#L22>) | behaviour + safety | The supplied supervised body and registered failure paths need callback-specific cancellation/cleanup evidence. |
| [ox/scope.mli · fork_error](<../../../lib/ox/scope.mli#L39>) | behaviour + safety | The forked result-returning callback may commit effects before cancellation; task admission and replay are not jointly classified. |
| [ox/scope.mli · fork](<../../../lib/ox/scope.mli#L44>) | behaviour + safety | The spawned callback may commit arbitrary effects; spawning again is not generically a safe retry. |
| [ox/scope.mli · fork_daemon](<../../../lib/ox/scope.mli#L48>) | behaviour + safety | Daemon admission and cancellation depend on enclosing-switch lifecycle and callback effects; replay is unclassified. |
| [ox/scope.mli · fork_error_daemon](<../../../lib/ox/scope.mli#L52>) | behaviour + safety | A result-returning daemon adds error handling but retains arbitrary callback effects; cancellation retry is not established. |
| [ox/supervisor.mli · start](<../../../lib/ox/supervisor.mli#L175>) | behaviour + safety | Child startup, restart, event callbacks and shutdown interact; a partial supervisor startup has no audited retry law. |
| [ox/supervisor.mli · start_simple](<../../../lib/ox/supervisor.mli#L225>) | behaviour + safety | The template-based supervisor still starts and restarts arbitrary child callbacks; its full lifecycle is unclassified. |
| [ox/timeout.mli · timeout](<../../../lib/ox/timeout.mli#L1>) | behaviour + safety | Timeout cancellation interrupts arbitrary caller code, which may already have committed effects; no universal retry claim is justified. |
| [process/child.mli · spawn](<../../../lib/process/child.mli#L13>) | behaviour + safety | OS process creation, pipe setup and switch-hook registration need an audit of partial creation and cancellation ownership. |
| [process/supervised.mli · start](<../../../lib/process/supervised.mli#L16>) | behaviour + safety | Process spawning, output pumps and restart supervision combine; cancellation during partial startup is not classified. |
| [rpc/correlator.mli · create](<../../../lib/rpc/correlator.mli#L16>) | behaviour + safety | Reader/background startup and framing cleanup are not merely allocation; partially established correlator retry needs a lifecycle audit. |
| [sql/connection.mli · create](<../../../lib/sql/connection.mli#L12>) | behaviour + safety | The constructor opens/configures SQLite and reads the clock; partial open/configuration cleanup and cancellation are not fully audited. |
| [sql/migrate.mli · Source.resolve](<../../../lib/sql/migrate.mli#L104>) | behaviour + safety | Filesystem source resolution delegates opening/reading/closing to Eio paths; cancellation and source-consumption ownership are not audited. |
| [sql/migrate.mli · list_applied](<../../../lib/sql/migrate.mli#L114>) | behaviour + safety | The migration-history query delegates to pooled SQL execution; cancellation while acquiring/executing has no audited complete contract. |
| [sql/migrate.mli · run](<../../../lib/sql/migrate.mli#L116>) | behaviour + safety | Migration effects and history updates span multiple statements; interrupted migration progress is not classified. |
| [sql/migrate.mli · run_to](<../../../lib/sql/migrate.mli#L124>) | behaviour + safety | Running to a target composes migration steps that may already commit; whole-call replay requires migration-specific evidence. |
| [sql/migrate.mli · undo](<../../../lib/sql/migrate.mli#L132>) | behaviour + safety | Undo steps may partly change schema/history before cancellation; repeating those user-defined effects is not classified. |
| [sql/pool.mli · create](<../../../lib/sql/pool.mli#L9>) | behaviour + safety | Pool construction opens a Connection and installs synchronization; partial database setup and cleanup are not audited. |
| [sql/pool.mli · shutdown](<../../../lib/sql/pool.mli#L17>) | behaviour + safety | Closing pooled connections and changing shutdown state need an interrupted-shutdown/idempotency audit. |
| [sql/pool.mli · Typed.select](<../../../lib/sql/pool.mli#L20>) | behaviour + safety | Compiled query execution and pooled connection acquisition need an upstream SQLite cancellation/cleanup audit. |
| [sql/pool.mli · Typed.returning](<../../../lib/sql/pool.mli#L21>) | behaviour + safety | Returning statements may combine writes with unread results; their commit/cancellation boundary is unclassified. |
| [sql/pool.mli · Typed.fold_select](<../../../lib/sql/pool.mli#L22>) | behaviour + safety | Query folding invokes a supplied callback; row consumption and callback progress have no universal retry law. |
| [sql/pool.mli · Typed.execute_compiled](<../../../lib/sql/pool.mli#L23>) | behaviour + safety | Compiled statement effects may be committed before cancellation; no operation-independent replay guarantee is established. |
| [sql/pool.mli · Typed.run_schema](<../../../lib/sql/pool.mli#L24>) | behaviour + safety | Schema operations may partly change database state; cancellation and rollback/replay require statement-specific evidence. |
| [sql/pool.mli · Raw.query](<../../../lib/sql/pool.mli#L27>) | behaviour + safety | Raw query execution/row consumption and pooled cleanup need an upstream cancellation audit. |
| [sql/pool.mli · Raw.fold](<../../../lib/sql/pool.mli#L28>) | behaviour + safety | Raw row folding invokes arbitrary caller code; consumed rows and callback effects are not classified. |
| [sql/pool.mli · Raw.execute](<../../../lib/sql/pool.mli#L29>) | behaviour + safety | Raw SQL may modify state before cancellation; the statement-specific commit and retry boundary is not audited. |
| [sql/pool.mli · Raw.execute_script](<../../../lib/sql/pool.mli#L30>) | behaviour + safety | A multi-statement script may make partial progress; no script-independent replay law is established. |
| [sql/pool.mli · Raw.with_connection](<../../../lib/sql/pool.mli#L31>) | behaviour + safety | The supplied connection callback can perform arbitrary SQL/effects; connection return does not prove callback retry safety. |
| [sql/pool.mli · with_transaction](<../../../lib/sql/pool.mli#L33>) | behaviour + safety | Transaction callbacks, rollback and commit races need a complete cancellation audit; callback effects may extend beyond the database. |
| [sql/sqlite.mli · Testing.with_db](<../../../lib/sql/sqlite.mli#L255>) | behaviour + safety | The database bracket runs an arbitrary callback; close ownership does not establish callback/SQL replay safety. |
| [test/ox_test.mli · run](<../../../lib/test/ox_test.mli#L12>) | behaviour + safety | The test runner owns a switch but invokes arbitrary test code and real filesystem/network dependencies; replay is callback-specific. |
| [test/ox_test.mli · advance](<../../../lib/test/ox_test.mli#L18>) | behaviour + safety | The mock clock is changed before Fiber.yield; blind replay advances it again, and the allowed loss categories need an explicit audited interpretation. |
| [test/ox_test.mli · fork_run](<../../../lib/test/ox_test.mli#L24>) | behaviour + safety | The test callback runs in a fork and a classification boundary; its effects and repeated spawning are not a universal safety law. |
| [test/ox_test.mli · flow_pair](<../../../lib/test/ox_test.mli#L73>) | behaviour + safety | Mock flow/resource creation and census ownership depend on upstream mock-provider behaviour; that creation boundary is not fully audited. |

## Existing claims found wrong

The authorized corrections are documentation-only:

1. [Actor.create](<../../../lib/ox/actor.mli>) claimed an already-cancelled switch raises Invalid_argument. It calls Switch.check: a cancelled, unfinished switch raises Eio.Cancel.Cancelled; a finished switch raises Invalid_argument. Corrected those distinct cases.
2. [Agent.create](<../../../lib/ox/agent.mli>) had the same cancelled-versus-finished contradiction. Corrected the same distinction.
3. The [Stdlib](<../../../lib/caps/cap_stdlib.mli>) and [Unix](<../../../lib/caps/cap_unix.mli>) blanket synchronous-wrapper claims were too broad for formatter printers, exit hooks and supplied callbacks. Qualified the claim: the wrapper adds no Eio operation/check; caller hook/callback code may suspend or cancel. Local brackets/server callbacks have their own overrides.
4. [Sys](<../../../lib/caps/cap_sys.mli>) said every call blocks the domain. The implementation also has constant/pure metadata paths. Changed this to synchronous, may-block operations, with no wrapper-added Eio cancellation point.

Upstream proof: [Eio Switch.check](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/switch.ml#L46-L48>) checks finished state first, then Cancel.check. The existing [Scope](<../../../lib/ox/scope.mli>) and [Concurrent](<../../../lib/ox/concurrent.mli>) finished-versus-cancelled distinction was checked and is correct; no correction was made. No further contradiction was established by this scoped audit, which is not a claim that every prose sentence in all 97 interfaces has been proved.

## Ownership boundary and remaining work

This ledger finishes row 89 accounting: every selected val is documented or individually reason-listed. Completing the remaining sentences requires the specific callback/upstream/lifecycle evidence named above, not a linter bypass. No core behaviour test, timeout/cancellation semantic change, new API type, or other delivery-map row is claimed complete here. Concurrency tests and row 85 remain the authority for behaviour. The two new lint rules and their regression fixtures validate only typed selection, documentation inheritance and sentence shape.
