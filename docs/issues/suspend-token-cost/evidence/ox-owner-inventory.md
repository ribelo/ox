<details>
<summary>Complete current-Logger Ox named-owner inventory (261 functions)</summary>

Locals with the same name at different lines are separate bindings. This records the propagated estimate, not 261 independently suspending primitives.

| Source | Functions | Binding:line |
|---|---:|---|
| [transport.ml](<lib/ai/transport.ml#L115>) | 4 | `attempt:115, wait:130, run:145, post_json:180` |
| [chat.ml](<lib/ai_chat/chat.ml#L26>) | 1 | `complete:26` |
| [ox_ai_chat.ml](<lib/ai_chat/ox_ai_chat.ml#L11>) | 1 | `complete:11` |
| [audio.ml](<lib/ai_openrouter/audio.ml#L63>) | 1 | `create:63` |
| [common.ml](<lib/ai_openrouter/common.ml#L10>) | 1 | `post:10` |
| [embeddings.ml](<lib/ai_openrouter/embeddings.ml#L60>) | 1 | `create:60` |
| [responses.ml](<lib/ai_openrouter/responses.ml#L229>) | 3 | `post:229, create:241, create_text:251` |
| [session.ml](<lib/ai_realtime/session.ml#L5>) | 4 | `connect:5, send:11, receive:27, close:34` |
| [ai_systemone/client.ml](<lib/ai_systemone/client.ml#L23>) | 1 | `evaluate:23` |
| [config.ml](<lib/app/config.ml#L164>) | 1 | `read_regular:164` |
| [ox_app.ml](<lib/app/ox_app.ml#L15>) | 15 | `serve:15, run_for_test_with_args:66, run_owned:94, run_owned_code:106, execute:151, run_for_test:274, log_posix_wakeup:305, posix_wakeup:314, tick:320, run_with_args:326, program:351, on_switch:372, read:390, run:409, run_simple:421` |
| [ox_blocking.ml](<lib/blocking/ox_blocking.ml#L65>) | 10 | `shutdown:65, reserve:86, try_reserve:108, execute:120, run:177, try_run:182, run_result:192, try_run_result:197, run_result_timeout:202, try_run_result_timeout:210` |
| [http/client.ml](<lib/http/client.ml#L43>) | 15 | `refill:43, perform:44, available:66, take_byte:68, read_line:74, loop:76, read_exact:90, loop:92, read_response:103, headers:105, chunks:140, trailers:153, until_close:170, request:189, perform:192` |
| [server.ml](<lib/http/server.ml#L220>) | 20 | `refill:220, next_byte:225, line:231, loop:233, take:247, loop:249, parse_head:262, headers:275, request_body:326, trailers:357, write_response:408, write_bytes:446, loop:460, serve_flow:478, loop:487, run_h1_on_socket:556, close_idle:569, run:574, accept:575, run_h1:608` |
| [service.ml](<lib/http/service.ml#L246>) | 1 | `h1:246` |
| [tls_flow.ml](<lib/http/tls_flow.ml#L47>) | 17 | `with_lock:47, drain:50, loop:51, flush:70, try_flush:75, feed:105, handshake:120, loop:121, single_read:139, loop:142, write_once:171, single_write:189, attempt:195, close:211, copy:228, shutdown:229, create:232` |
| [ws_client.ml](<lib/http/ws_client.ml#L50>) | 17 | `read_exact:50, loop:52, read_head:66, loop:68, create_tls:149, connect:161, perform:165, dial:192, finish:287, writing:295, send_frame:303, send_text:309, send_binary:312, close:314, read_frame:346, receive:403, loop:407` |
| [listener.ml](<lib/ipc/listener.ml#L175>) | 10 | `read_line:175, read:177, scan:179, respond:195, peer:211, refuse:215, work:233, monitor:248, drain:250, run:273` |
| [logger.ml](<lib/observability/logger.ml#L213>) | 10 | `emit:213, emit_if_enabled:228, log:260, debug:263, info:264, warn:265, error:266, span:268, run:276, finish:278` |
| [ox_otel.ml](<lib/otel/ox_otel.ml#L142>) | 13 | `post:142, send:152, send_metrics:199, export_metrics:211, send_window:212, drain:232, finish:285, worker:298, flush_window:305, loop:309, create:351, flush:437, shutdown:448` |
| [actor.ml](<lib/ox/actor.ml#L50>) | 7 | `next:50, enqueue:82, tell:85, ask:92, wait:98, create:133, loop:148` |
| [agent.ml](<lib/ox/agent.ml#L26>) | 9 | `create:26, loop:31, request:55, get:70, update:75, get_and_update:80, cast:85, update_result:92, get_and_update_result:98` |
| [channel.ml](<lib/ox/channel.ml#L38>) | 3 | `wait_changed:38, send:40, receive:48` |
| [concurrent.ml](<lib/ox/concurrent.ml#L15>) | 7 | `par:15, both:24, all:29, for_each:37, race:45, race_first:71, with_background:76` |
| [rate_limiter.ml](<lib/ox/rate_limiter.ml#L89>) | 4 | `acquire:89, run:93, wait_for_permit:94, run_or_drop:104` |
| [resource.ml](<lib/ox/resource.ml#L1>) | 2 | `use_in_scope:1, use_closeable_in_scope:11` |
| [retry.ml](<lib/ox/retry.ml#L2>) | 5 | `sleep:2, retry_loop:13, retry:29, repeat_loop:32, repeat:42` |
| [scope.ml](<lib/ox/scope.ml#L45>) | 7 | `run:45, supervised_error:144, fork_error:152, fork:160, fork_daemon:162, fork_error_daemon:167, await:171` |
| [select.ml](<lib/ox/select.ml#L50>) | 4 | `select:50, block:80, block:98, receive:106` |
| [supervisor.ml](<lib/ox/supervisor.ml#L203>) | 22 | `supervise:203, launch:230, settle_spontaneous:291, settle_induced:317, stop_entry:325, sweep:354, wait_ready:384, start_downs:411, go:412, recover:454, shutdown_all:485, loop:489, react:503, handle:510, config:609, launch_supervisor:621, start:631, stop:645, await:649, terminate_child:666, start_simple:682, start_child:694` |
| [timeout.ml](<lib/ox/timeout.ml#L1>) | 1 | `timeout:1` |
| [child.ml](<lib/process/child.ml#L19>) | 4 | `await:19, stop:28, spawn:42, output:60` |
| [supervised.ml](<lib/process/supervised.ml#L28>) | 4 | `stop:28, start:42, run:56, loop:59` |
| [correlator.ml](<lib/rpc/correlator.ml#L76>) | 5 | `close:76, create:84, loop:117, call:135, run:136` |
| [migrate.ml](<lib/sql/migrate.ml#L403>) | 13 | `query:403, execute:405, script:408, create_table:410, read_states:417, list_applied:453, apply_migration:482, run_migrations:507, loop:512, run:523, run_to:527, undo:540, loop:548` |
| [pool.ml](<lib/sql/pool.ml#L19>) | 18 | `guard:19, shutdown_state:21, create:32, make:41, shutdown:76, apply_timeout:78, use:86, select:112, returning:113, execute_compiled:115, run_schema:118, fold_select:120, query:125, fold:128, execute:131, execute_script:134, with_connection:137, with_transaction:144` |

</details>

