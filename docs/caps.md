# Capabilities: a function's type says what it may touch

Rows 48 and 54 (^ncaps-xzx5 ^ncaps-uiq6). Every line here is written by agents, so the interface is what a reviewer trusts. A function that forks, execs, reads the environment, writes a file outside Eio's `fs`, prints, exits or seeds randomness from the system says so in its type, and a Semgrep gate refuses the raw call everywhere else.

## The shape

`ox_caps` (`lib/caps/`) has one module of types and three of wrappers. Its separate constructor library is `ox_caps.door` (`lib/caps/door/`).

- `Ox_caps.Cap`: one capability per thing a program can touch outside Eio — `fork`, `exec`, `exit`, `chdir`, `env`, `signal`, `time`, `random`, `stdin`, `stdout`, `stderr`, `fs_read`, `fs_write`, `tmp`, `network`. Each is an object type with one method whose result is an abstract token (`Cap.fork = < fork : Cap.Token.fork >`), so a capability cannot be written by hand. Row types compose them: `< Cap.fork; Cap.exec; .. >`. Groups: `Cap.process`, `Cap.console`, `Cap.fs`, `Cap.all_caps`, `Cap.no_caps`.
- `Ox_caps.Cap_unix`, `Cap_sys`, `Cap_stdlib`: the dangerous `Unix`, `Sys` and `Stdlib` calls, each taking `~caps` with exactly the capability it needs and doing nothing else. `Cap_sys.urandom` (random bytes, `Cap.random`) and `Cap_unix.open_dev_null` (no capability) are the two additions.
- `caps.yaml` and `caps-gate`: the rules and the gate script, installed under `share/ox_caps`.

Eio's own capabilities stay Eio values (^ncaps-jkku): `net`, `fs`, `process_mgr`, `clock`, `domain_mgr` are passed as they are today, and `ox_caps` covers only what Eio does not hand out. Where both apply, a function takes both: `Ox_process.Child.spawn` takes Eio's `mgr`, which does the work, and `~caps:< Cap.fork; Cap.exec; .. >`, which makes the signature say what the work is.

## Where a powerbox comes from

Only the Door mints one (^ncaps-0mvw ^ncaps-uiq6). `Ox_app` calls `Ox_caps_door.powerbox ()` once per process and puts it in every `Ox_app.Env.t` it builds: the program's, the validator's, and the one `commands_with_env` / `config_commands_with_env` give to command builders. A process that already owns its CLI and runtime — grip does — calls `Ox_app.with_powerbox` once at the entry and passes the result down; that call does not start Eio or parse arguments (^grpcap-4kdm). The gate treats that call as a mint: it is allowed only in `bin/**/main.ml`, or in a file the repository's `scripts/caps-gate` names with `--allow`. A library that calls it fails. Tests take `Ox_test.powerbox ()`. There is no constructor in public `Ox_caps.Cap`; the `ox_caps.door` sub-library has the constructor, marked with a `mint` alert. Only `lib/caps/dune` (for token identity), `lib/app/dune` and `lib/test/dune` list that library. The gate rejects other Dune dependencies on `ox_caps.door` and other source references to `Ox_caps_door`; it also rejects `Ox_test.powerbox` in production.

`Cap.Token` aliases the token types from `Ox_caps_door`; the token types remain abstract in the door library's interface, so a hand-written object cannot forge them. The type equations in `Cap.mli` let `Ox_app` and `Ox_test` accept the door constructor's result as `Cap.all_caps`. A direct transitive module reference is not permission to mint: the gate rejects the identifier outside the two allowed libraries.

## Narrowing a powerbox

The program narrows by type ascription and hands each service the capabilities its signature names:

```ocaml
let program (env : _ Ox_app.Env.t) config sw =
  let chrome =
    Leash.Chrome.create ~sw (Leash.Config.chrome_config config.chrome)
      { clock = env.base#clock; mgr = env.base#process_mgr; logger = env.logger;
        caps = (env.caps :> Leash.Chrome.caps) }   (* < Cap.fork; Cap.exec > *)
  in
  ...
```

A function takes `~caps:< Cap.env; Cap.fs_read; .. >`; the row variable lets a wider powerbox through, and the body can call only the methods the type lists. A Service's `deps` record names a closed type (`caps : Tabs.caps`) and the program coerces into it. A program that narrowed its powerbox cannot call a function that needs a capability it dropped: that is a type error (`test/caps/compile_fail/excluded.ml`, ^ncaps-aw5n), and so is an object written to look like a capability (`forged.ml`).

A capability is an ordinary global argument. A partial application such as `~getenv:(Cap_sys.getenv_opt ~caps)` is an ordinary closure, and a `@ local` closure (`Rate_limiter.run`'s thunk, `Resource.use_in_scope`'s acquire) captures a capability and calls a wrapper as it would any value.

The wrappers block the domain and observe no cancellation. `Ox.Actor` handlers and `Ox.Agent` closures run cancel-protected in their owner fiber and must not block for long or call back into their own actor, so keep `Cap_unix.system`, file reads of unknown size and the like out of them; spawn children through Eio's `process_mgr` and blocking work through `Ox_blocking`.

## One domain (^ncaps-vlwm)

v1 dropped object capabilities because objects are not `portable` across OxCaml domains. That stays true: a capability cannot be captured by a `portable` closure (`test/caps/compile_fail/portable.ml`), so it cannot be sent to another domain. This is a caveat, not a blocker (ADR-0009): no consumer crosses domains. A future parallel package that does mints a powerbox per domain inside its own Door and never ships one across.

## The gate (^ncaps-n6r0 ^ncaps-w6n2)

```sh
nix develop -c scripts/caps-gate      # in ox and in Leash; the fourth gate beside build, test, fmt
```

`caps-gate [--allow GLOB]... [PATH]...` checks `lib/`, `packages/` and `bin/` (whichever exist), excluding `test/` and `tests/` (tests mint their own powerbox). It runs Semgrep with JSON output, `--disable-nosem` and `--no-git-ignore`. A file skipped because Semgrep cannot parse it is checked by a lexical fallback against the forbidden identifiers in `caps.yaml`; a finding fails the gate and names the file. A skipped file passes only if that fallback finds no forbidden identifier. An inline `nosemgrep` does not silence either check; the allow-list is the `--allow` entries in the repository's own `scripts/caps-gate`, each with its reason. Run it from inside the repository: `--allow` paths are resolved from the repository root. Semgrep must be on `PATH`; it is in the dev shells of ox and Leash.

The rules, one per capability plus two:

| Rule | Refuses | Wrapper |
| --- | --- | --- |
| `ox-caps-fork` | `Unix.fork` | `Cap_unix.fork` |
| `ox-caps-exec` | `Unix.exec*`, `create_process*`, `open_process*`, `system`, `Sys.command` | `Cap_unix.*`, `Cap_sys.command` |
| `ox-caps-exit` | `exit`, `Stdlib.exit`, `Unix._exit` — except `exit (Ox_app.run ...)`, an entry passing the Door's code on | `Cap_stdlib.exit`, `Cap_unix._exit` |
| `ox-caps-chdir` | `Sys.chdir`, `Unix.chdir`, `Unix.chroot` | `Cap_sys.chdir`, `Cap_unix.chdir` |
| `ox-caps-env` | `Sys.getenv(_opt)`, `Unix.getenv`, `environment`, `putenv` | `Cap_sys.getenv(_opt)`, `Cap_unix.*` |
| `ox-caps-signal` | `Unix.kill`, `sigprocmask`, `Sys.signal`, `Sys.set_signal` | `Cap_unix.kill`, `Cap_sys.signal`, ... |
| `ox-caps-time` | `Unix.time`, `Unix.gettimeofday`, `Sys.time` (prefer an Eio clock) | `Cap_unix.time`, ... |
| `ox-caps-random` | `Random.self_init`, `Random.State.make_self_init` | `Cap_stdlib.Random.*`, `Cap_sys.urandom` |
| `ox-caps-stdin` | `read_line ()`, `Stdlib.stdin`, `In_channel.stdin`, `Scanf.scanf`, ... | `Cap_stdlib.read_line`, `stdin` |
| `ox-caps-stdout` | `print_*`, `Printf.printf`, `Format.printf`, `Stdlib.stdout`, ... | `Cap_stdlib.print_*`, `printf`, `stdout`, `std_formatter` |
| `ox-caps-stderr` | `prerr_*`, `Printf.eprintf`, `Format.eprintf`, `Stdlib.stderr`, ... | `Cap_stdlib.prerr_*`, `eprintf`, `stderr`, `err_formatter` |
| `ox-caps-fs-read` | `open_in*`, `In_channel.open_*` / `with_open_*`, `Sys.readdir`, `Unix.opendir` | `Cap_stdlib.open_in*`, `Cap_stdlib.In_channel.*`, `Cap_sys.readdir` |
| `ox-caps-fs-write` | `open_out*`, `Out_channel.open_*` / `with_open_*`, `Unix.openfile`, remove/rename/mkdir/rmdir/unlink/chmod/truncate/link/symlink | `Cap_stdlib.*`, `Cap_sys.*`, `Cap_unix.*` |
| `ox-caps-tmp` | `Filename.temp_file`, `open_temp_file`, `temp_dir` | `Cap_stdlib.Filename.*` |
| `ox-caps-network` | `Unix.socket`, `socketpair`, `open_connection`, `establish_server` (prefer Eio's `net`) | `Cap_unix.socket`, ... |
| `ox-caps-mint` | `Ox_caps_door.powerbox`, legacy `Ox_caps.Cap.powerbox`, `Ox_test.powerbox`, `Ox_app.with_powerbox` outside an executable entry; `Ox_caps_door` references and `ox_caps.door` dependencies outside the Door and test entry | receive capabilities as arguments; `with_powerbox` only in `bin/**/main.ml` or a file the repository's `--allow` names |
| `ox-caps-forge` | `Obj.magic` | — |

`test/caps/gate/` is the gate's own test: one violation per rule in `violating/lib/raw.ml` (every rule must fire, a `nosemgrep` comment must not help, `test/` is not scanned, `--allow` excludes exactly its file) and the same operations through the wrappers in `clean/`, which must pass.

### What the gate cannot see

- Semgrep does not resolve OCaml's implicit `Stdlib`, so each Stdlib function is listed bare and qualified. Some shadowed bare functions may still be reported; inspect the binding before renaming it. Bare `stdout`, `stderr`, `stdin` channel values are checked (^ncaps-znyh), while shadowed local channel names and record labels are not violations (the gate fixtures prove both). Use `Cap_stdlib.stdout ~caps`, `Cap_stdlib.stderr ~caps`, or `Cap_stdlib.stdin ~caps` for the actual Stdlib streams.
- Semgrep's OCaml parser does not know OxCaml's mode syntax (`@ local`, `global_`, `@@ portable`). The gate reads skipped-file diagnostics and checks those files lexically instead (^ncaps-a27b ^ncaps-tpjy): skipped files do not silently pass, though the fallback matches identifiers, not OCaml binding identity or syntax.
- A library that reads or writes files through its own API (`Yojson.Safe.from_file`, say) is not one of the calls the rules name. Wrap such a call behind a capability yourself (Leash reads through `Cap_stdlib.In_channel.with_open_bin` and `Yojson.Safe.from_channel`).
- Metadata reads (`Sys.file_exists`, `Unix.stat`, `Unix.realpath`) are not capabilities.

## Adding a capability, a wrapper and its rule

1. A new capability: add an abstract token type and method to `ox_caps.door`'s interface, its concrete representation and constructor method to `ox_caps_door.ml`, and the alias `type x = < x : Token.x >` plus sealed token type equation in `Cap`. Every Door powerbox gains it.
2. A new wrapper: the raw call with `~caps:< Cap.x; .. >` in front, in `Cap_unix`, `Cap_sys` or `Cap_stdlib` after the module it wraps, and nothing else in its body. Say in the `.mli` if it blocks.
3. Its rule: add the raw name to the rule of its capability in `caps.yaml` (bare and `Stdlib.`-qualified if it is a Stdlib value), a line to `test/caps/gate/violating/lib/raw.ml` if it is a new rule, and a row to the table above.

## Reading a violation

```
    packages/leash/tabs.ml
   ❯❯❱ ox-caps-fs-write
          Creating, writing, moving or deleting files outside Eio's fs ... Take the
          capability in the signature (Cap.fs_write) and call the Ox_caps wrapper instead
         2266┆ let channel = open_out path in
```

The rule id names the capability. Fix it by giving the enclosing function `~caps:< Cap.fs_write; .. >` (or a Service's `deps.caps` field of a closed type that includes it), replacing the call with the wrapper named in the table, and passing the capability down from the caller until it reaches a narrowing of the Door's powerbox. Do not add an `--allow` entry for application code; the allow-list is for the wrappers, the Door, build tools that are not Door programs, and library modules waiting for a consumer's migration.

## What each ox library needs (^ncaps-x7z8)

| Library | Capabilities | In the signature |
| --- | --- | --- |
| `ox_process` | `fork`, `exec` | `Child.spawn ~caps` |
| `ox_ipc` | `fs_write`, `network` (the socket, its directory and lock) | `Listener.run ~caps` |
| `ox_otel` | `random` (trace IDs), beside Eio’s `net` and clock | `create ~caps` required |
| `ox` | `random` only when a jittered schedule is stepped | `Schedule.start ~random` from the caller; no default seed |
| `ox_sql` | `time`, `fs_read` (migrations), `tmp` + `fs_write` (temporary databases) | `Pool.create` and `Connection.create` take `time`; `Migrate.run` and `run_to` take `fs_read` + `time`; `Source.resolve` and `undo` take `fs_read`; `Sqlite.Testing.with_db` takes `tmp` + `fs_write` |
| `ox_app` | mints them all | the Door |
| `ox_test` | mints them all | the test entry |
| `ox_http`, `ox_ai*`, `ox_rpc`, `ox_json`, `ox_observability`, `ox_blocking`, `ox_sql_dsl` | nothing beyond the Eio values they take | — |

`ox_sql` takes its capabilities (row 52, ^inncap-b8ts). Grip takes its capabilities (row 53, ^grpcap-4kdm). `Ox_otel.create` requires `~caps`, and `Schedule.start` no longer seeds a default random state, so neither file is on the allow-list. What remains is the wrappers (`lib/caps`), the Door (`lib/app/ox_app.ml`), and the ppx driver (`lib/ppx_yojson_minimal/main.ml`).

## Cost (^ncaps-21nk)

Leash, the first migration: 40 raw calls in 6 files before; 17 capability parameters and fields in its interfaces (plus 3 `caps` type aliases: Chrome, Tabs, Desktop), about 150 `~caps` sites threading them, and 88 test lines passing `Ox_test.powerbox ()`; no allow-list entry. The same rules over the other consumers today (`lib/`, `packages/`, `bin/`, tests excluded): Pie 87 findings in 20 files, nema 58 in 14, inn 52 in 5, grip 39 in 8.
