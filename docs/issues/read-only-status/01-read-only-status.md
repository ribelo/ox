---
status: ready
package: ox_app, ox, every Service
consumer: every consumer (Ox-internal; ADR-0010)
---

# Status queries read and never write

## Problem Statement

GLOSSARY.md says Status is "read from its real state at that moment" and the `SERVICE` contract says `status` "must not retain a snapshot"; nothing stops a status function from mutating the Service it reports on. OxCaml's visibility axis does: a value at mode `read` cannot have a mutable field written ("This value is read but is expected to be write or read_write"), verified on 5.4.0+ox.

## Solution

`SERVICE.status : t @ read -> Status.t`, and the same for other observers (`Actor.state`, `Channel` inspection, `Rate_limiter` inspection).

## User Stories

1. As a reviewer, I want `Ox_app.SERVICE.status : t @ read -> Status.t`, so that a status that writes is a compile error. ^nread-lv5j
2. As a reviewer, I want Ox's observers (`Actor.state`, `Channel.length`/`is_closed`, `Rate_limiter` and `Supervisor` status) to take `@ read`, so that inspecting never changes what is inspected. ^nread-puzm
3. As a kernel maintainer, I want the limit recorded — `read` restricts the value's own mutable fields; a status that calls through an aliased `Atomic` or an Eio object is not restricted unless those APIs accept `read` — and the observers that cannot take `@ read` listed with the reason, so that the guarantee is not overstated. ^nread-53wj
4. As a kernel maintainer, I want a compile-fail case (status writing a field), so that the refusal is pinned. ^nread-t1f5
5. As a reviewer, I want `SERVICE` either required by the Door (a Service is registered as a first-class module) or retired from GLOSSARY.md, decided in this row, so that the read-only contract binds something real. ^nread-wqkc

## Out of Scope

`stateless` closures (ADR-0010: unusable while the stdlib is unannotated).
