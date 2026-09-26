---
status: completed
package: eta_app, eta_observability (Redact codecs), removal of eta_schema and eta_schema_yojson
consumer: Leash milestone 1 (Config and protocol types); depends on row 15 (deriving) and keeps row 14 (door-validate)
---

# Remove eta_schema; types with derived codecs are the schema

## Problem Statement

`eta_schema` restates OCaml types as combinator values so that decoding can report JSON-pointer locations, fields can carry marks, and a JSON Schema can be derived. It is a second type system: every shape is written twice, and it reads badly. With deriving available (row `ppx-on-oxcaml`), the type is the schema, the deriver is the codec, and the three extras are obtained more simply.

## Solution

Delete `eta_schema` and `eta_schema_yojson`. `Eta_app`'s config takes a derived decoder, a validation function and an environment-override function; `Redact.t` gets yojson codecs so redaction is by type; decode errors render the deriver's message with the offending JSON subtree; `config check` prints `yojson_of_t`.

## User Stories

1. As a kernel maintainer, I want `lib/schema`, `lib/schema_yojson`, their tests, opam files, package stanzas, flake entries and README rows removed, so that the DSL is gone. ^nnoschema-ttb5
2. As a service author, I want `Eta_app.run ~name ~config:{ of_yojson; validate; env }` where `of_yojson : Yojson.Safe.t -> ('cfg, string) result` is the derived decoder, `validate` is row 14's Door validator — `'base Env.t -> 'cfg -> (unit, validation_error list) result`, run after decoding and env overrides and by `config check` — for checks that need the environment (a binary exists, a directory is readable); constraints a type can express live in smart-constructor modules per ADR-0008, not here, and `env : getenv:(string -> string option) -> 'cfg -> 'cfg` applies environment overrides, so that config is a plain type plus two small functions. As delivered, the bundle is `'cfg Eta_app.Config.t` and row 14's hook stays a separate optional argument: `~config:{ of_yojson; yojson_of_t; env }` with `?validate`. `yojson_of_t : 'cfg -> Yojson.Safe.t` is the derived encoder story 5 prints, and keeping `validate` exactly where row 14 delivered it leaves one validation path, not two. ^nnoschema-5mdj
3. As an operator, I want a config decode failure to exit 2 printing the deriver's error and the offending JSON subtree (bounded), so that misconfiguration still names the field. ^nnoschema-zi2m
4. As a service author, I want `Eta_observability.Redact.t` to derive as `"<redacted>"` when encoded and to decode from a string, so that a secret field is redacted in `config check` output and in any log by being of that type. ^nnoschema-ifg0
5. As an operator, I want `<name> config check` to print `yojson_of_t` of the effective config after environment overrides, so that the check shows what the service will run with. ^nnoschema-36cj
6. As a kernel maintainer, I want the TOML-to-JSON step kept in `eta_app` (`toml` → `Yojson.Safe.t`), so that the config file format is unchanged. ^nnoschema-boxo
7. As a kernel maintainer, I want the `app` and `json-and-schema` specs updated: superseded stories marked, new IDs for the changed shapes, and the Leash protocol smoke test rewritten as a derived-type round-trip in `test/json/`, so that the specs stay true. ^nnoschema-44wj
8. As a kernel maintainer, I want `eta_app`'s test for a two-Service program to use a derived config type, so that the shape consumers will write is the one tested. ^nnoschema-p7fv

## Implementation Decisions

- Row 14 (`door-validate`) added a Door validator for environment-dependent checks (binary exists, directory readable). Keep that hook exactly as delivered; this row only replaces the *decoding* half: `of_yojson` (derived) replaces the schema decode, and pure constraints move into smart-constructor modules or the existing `validate`. Do not build a second validation path.

- The config record for a consumer is a plain type with `[@@deriving yojson]`; optional fields use `[@default]` (or the deriver's equivalent); `validate` is where bounds and enumerations live; `env` is explicit code (`match getenv "OPENROUTER_API_KEY" with Some k -> { c with models = { c.models with api_key = Redact.make k } } | None -> c`).
- `Eta_json` stays for unchecked JSON (CDP); derived codecs are for shapes we own.
- No compatibility layer: `Eta_schema` disappears in one commit after the Door is switched.

## Testing Decisions

- `test/app`: derived config round-trip, decode failure output, env override, redaction in `config check` — stories 2–5, 8.
- Grep the tree for `Eta_schema` after removal; only `docs/issues` history may mention it.

## Delivered signatures

```ocaml
type 'cfg Eta_app.Config.t = {
  of_yojson : Yojson.Safe.t -> ('cfg, string) result;   (* derived *)
  yojson_of_t : 'cfg -> Yojson.Safe.t;                  (* derived, printed by config check *)
  env : getenv:(string -> string option) -> 'cfg -> 'cfg;
}

val run_for_test :
  ?on_switch:(Eio.Switch.t -> unit) ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?validate:('base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  env:(< clock : _ Eio.Time.clock ; mono_clock : _ Eio.Time.Mono.t ; .. > as 'base) ->
  journal:Eta_observability.Logger.Reporter.t ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  getenv:(string -> string option) ->
  read:(string -> (string, string) result) ->
  stderr:(string -> unit) ->
  stdout:(string -> unit) ->
  argv:string array ->
  ('base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) ->
  int

val run :
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?validate:(Eio_unix.Stdenv.base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) ->
  int
```

`Config.decode ~spec ~getenv text` and `Config.load ~spec ~getenv ~read ~path` run TOML → `Yojson.Safe.t` → `of_yojson` → `env ~getenv` in that order.

## Out of Scope

JSON Schema generation for AI tool definitions (its own row when the AI package is pulled).

## Verification

`nix develop -c dune build @install`, `nix develop -c dune test` and `nix develop -c dune build @fmt` are green for the whole tree: 19 `test/app` cases (derived config round-trip, decode failure output, environment override, redaction in `config check`, the two-Service program on a derived config type, and row 14's unchanged validator cases), 8 `test/json` cases including the derived Leash protocol round-trip, 24 `test/observability` cases including the new `Redact` codecs, 22 `test/ppx` cases, and every other suite unchanged.

The grep for `Eta_schema` outside `_build` finds no code, build or configuration file: `lib/schema`, `lib/schema_yojson`, `test/schema`, `test/schema_yojson`, their `dune-project` stanzas and opam files, the flake's derived package list and the README rows are gone; the surviving mentions are this row's history under `docs/issues/` and ADR-0008, which decided the removal.

Two additions made by this row, both in service of the consumer stories above: `lib/ppx_yojson_minimal` now resolves a qualified type reference at any depth (`Eta_observability.Redact.t` calls `Redact.yojson_of_t`/`Redact.t_of_yojson`, so a config record needs no `open`; ^nnoschema-ifg0), and `eta_app`/`eta_observability` take `yojson` as a dependency, recorded in ADR-0007 (`^napp-deps`).
