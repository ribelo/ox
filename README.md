# Eta

Eta is a private application kernel for OCaml services: typed errors, structured failure causes, Eio concurrency with scoped resources, one door for every process, and the protocol clients and servers those services need. It is built on OxCaml and Eio, in direct style.

This branch (`eta-next`) is a fresh start. The previous design — an effect blueprint interpreted by a runtime layered over Eio — lives on the `v1` tag and branch for the applications that still use it. `docs/why-next.md` explains the change and how code is written here.

Nothing enters this tree without a consumer. The first consumer is Leash (`/home/ribelo/projects/ribelo/leash`).

- `CONTEXT.md` — vocabulary
- `docs/why-next.md` — why v1 was abandoned, how direct style works here, where effect handlers fit
- `docs/adr/` — the decisions that are hard to reverse
- `eta` — core typed failures, scoped resources, schedules, and Eio concurrency
- `eta_test` — Eio mock clocks, scripted I/O and processes, and Exit assertions
- `eta_json` — unchecked Yojson accessors: bounded parse, builders, member reads (depends on Yojson only)
- `eta_schema` — pure schemas: records, variants, lists, options, refinements, field marks, JSON-pointer issues (standard library only)
- `eta_schema_yojson` — the Yojson bridge for `eta_schema` codecs
- `eta_rpc` — scoped request/reply correlation over message streams
- `eta_ipc` — private Unix control listeners with scoped socket ownership and bounded peers
- `eta_process` — scoped Unix children with graceful termination and scheduled supervision
