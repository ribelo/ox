# Handoff: eta_schema is removed; deriving replaces it (2026-09-26)

For the agent implementing L1 and the next eta-next rows. Read in this order.

**What changed.** The schema combinator library (`eta_schema`, `eta_schema_yojson`) is being removed from eta-next. Shapes we own — config records, control-protocol requests and replies — become plain OCaml types with `[@@deriving yojson]`; values with constraints become small modules with a smart constructor and their own codec; secrets are `Eta_observability.Redact.t`. `Eta_app`'s config decoding changes accordingly; your `door-validate` hook (row 14) stays as delivered. CDP JSON stays untyped through `Eta_json`.

**Why.** `docs/adr/0008-types-are-the-schema.md` — including the honest case for what a schema value buys and how each of those is obtained without a DSL.

**What to do, in order.**
1. Finish and commit what you have in flight for row 14 (`door-validate`); it is kept.
2. Row 15, `docs/issues/ppx-on-oxcaml/01-ppx-on-oxcaml.md`: make `[@@deriving yojson]` build on the 5.4.0+ox switch and in the Nix flake. The public OxCaml opam repository has no ppxlib for 5.3+; the spec lists the routes in order (the monorepo checkout at `/home/ribelo/projects/github/oxmono`, the `oxcaml` org's ppxlib fork at the compiler's tag, a minimal `Ast_mapper` deriver as last resort). "Not installable" is not an outcome; the row ends when the round-trip test passes under both build paths. Record which route worked in the spec's status.
3. Row 16, `docs/issues/remove-eta-schema/01-remove-eta-schema.md`: delete the two packages, switch the Door's config decoding to a derived `of_yojson` plus the existing validators, give `Redact.t` yojson codecs, render decode failures with the offending subtree, update the `app` and `json-and-schema` specs.
4. **Leash L1**: do not write `Config` or the protocol types on `Eta_schema`. If you already have, park that code; after row 16 they are plain records with `[@@deriving yojson]` matching `docs/protocol.md`. Everything else in L1 (Door program, CLI) is unaffected and can continue. `leash/docs/adr/0009-types-are-the-schema.md` and the updated `managed-chrome` spec describe the target.

**Rules unchanged.** Commit per slice citing story IDs; gates `dune build @install`, `dune test`, `dune build @fmt`; nothing enters without a story.
