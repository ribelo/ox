---
status: ready-for-agent
package: eta_app, eta_observability (Redact codecs), removal of eta_schema and eta_schema_yojson
consumer: Leash milestone 1 (Config and protocol types)
---

# Remove eta_schema; types with derived codecs are the schema

## Problem Statement

`eta_schema` restates OCaml types as combinator values so that decoding can report JSON-pointer locations, fields can carry marks, and a JSON Schema can be derived. It is a second type system: every shape is written twice, and it reads badly. With deriving available (row `ppx-on-oxcaml`), the type is the schema, the deriver is the codec, and the three extras are obtained more simply.

## Solution

Delete `eta_schema` and `eta_schema_yojson`. `Eta_app`'s config takes a derived decoder, a validation function and an environment-override function; `Redact.t` gets yojson codecs so redaction is by type; decode errors render the deriver's message with the offending JSON subtree; `config check` prints `yojson_of_t`.

## User Stories

1. As a kernel maintainer, I want `lib/schema`, `lib/schema_yojson`, their tests, opam files, package stanzas, flake entries and README rows removed, so that the DSL is gone. ^nnoschema-ttb5
2. As a service author, I want `Eta_app.run ~name ~config:{ of_yojson; validate; env }` where `of_yojson : Yojson.Safe.t -> ('cfg, string) result` is the derived decoder, `validate : 'cfg -> (unit, string) result` checks constraints the type cannot express, and `env : getenv:(string -> string option) -> 'cfg -> 'cfg` applies environment overrides, so that config is a plain type plus two small functions. ^nnoschema-5mdj
3. As an operator, I want a config decode failure to exit 2 printing the deriver's error and the offending JSON subtree (bounded), so that misconfiguration still names the field. ^nnoschema-zi2m
4. As a service author, I want `Eta_observability.Redact.t` to derive as `"<redacted>"` when encoded and to decode from a string, so that a secret field is redacted in `config check` output and in any log by being of that type. ^nnoschema-ifg0
5. As an operator, I want `<name> config check` to print `yojson_of_t` of the effective config after environment overrides, so that the check shows what the service will run with. ^nnoschema-36cj
6. As a kernel maintainer, I want the TOML-to-JSON step kept in `eta_app` (`toml` → `Yojson.Safe.t`), so that the config file format is unchanged. ^nnoschema-boxo
7. As a kernel maintainer, I want the `app` and `json-and-schema` specs updated: superseded stories marked, new IDs for the changed shapes, and the Leash protocol smoke test rewritten as a derived-type round-trip in `test/json/`, so that the specs stay true. ^nnoschema-44wj
8. As a kernel maintainer, I want `eta_app`'s test for a two-Service program to use a derived config type, so that the shape consumers will write is the one tested. ^nnoschema-p7fv

## Implementation Decisions

- The config record for a consumer is a plain type with `[@@deriving yojson]`; optional fields use `[@default]` (or the deriver's equivalent); `validate` is where bounds and enumerations live; `env` is explicit code (`match getenv "OPENROUTER_API_KEY" with Some k -> { c with models = { c.models with api_key = Redact.make k } } | None -> c`).
- `Eta_json` stays for unchecked JSON (CDP); derived codecs are for shapes we own.
- No compatibility layer: `Eta_schema` disappears in one commit after the Door is switched.

## Testing Decisions

- `test/app`: derived config round-trip, decode failure output, env override, redaction in `config check` — stories 2–5, 8.
- Grep the tree for `Eta_schema` after removal; only `docs/issues` history may mention it.

## Out of Scope

JSON Schema generation for AI tool definitions (its own row when the AI package is pulled).
