---
status: completed
package: eta_ipc
consumer: Leash milestone 1 (chrome-fwnu, chrome-38a4), milestone 6 (svc-5wm8), L35 (hard-yi0a)
---

# IPC: a private Unix-socket control listener

## Problem Statement

Leash serves a private control socket; Pie already had to learn the hard way what "private" and "owned" mean for a Unix socket: never replace a live listener or a stray file, verify the runtime directory, bound peers, bound bytes, bound time. Those rules were Pie-local; they become a package.

## Solution

`eta_ipc`: `Listener.run ~sw ~fs ~net ~clock ~path ~policy ~decode ~encode ~budget ~handler`, with `?on_budget_exceeded` naming the reply a request cut at that budget gets, a scoped listener with endpoint ownership, owner-only permissions, bounded admission, an ingress deadline for reading a request line, a per-request handler budget the caller derives from the decoded request, an egress deadline for the reply, one request per connection, and clean retirement.

## User Stories

1. As an operator, I want the listener to verify its runtime directory is a real directory owned by me with owner-only permissions (creating it 0700 if absent, never chmodding an existing shared directory, never following an unverified symlink), so that the socket cannot be planted elsewhere. ^nipc-tafd
2. As an operator, I want a pre-existing regular file, symlink, foreign socket or live listener at the path to be preserved and reported as a typed ownership conflict, so that two services never fight over one endpoint. ^nipc-4kuy
3. As an operator, I want a stale owned socket recovered only after a definitive probe and an identity recheck under an exclusive lock, so that a crashed predecessor does not block restart but a live one is never replaced. ^nipc-vayc
4. As an operator, I want the socket created mode 0600, so that only my user can connect. ^nipc-f264
5. As a service author, I want at most N concurrent peers with a bounded backlog and no unbounded queue of waiting fibers, so that a flood cannot exhaust the process. ^nipc-skdt
6. As a service author, I want an ingress deadline on reading the request line and a byte bound on it, so that a stalled or oversized peer is dropped before any application work. ^nipc-x8ph
7. As a service author, I want the handler run under a budget my `budget : request -> Duration.t option` function returns for the decoded request (None = no listener-imposed limit), so that a fifteen-minute handoff and a one-second status share one listener. ^nipc-6i86
8. As a service author, I want an egress deadline on writing the reply and a byte bound on it, so that a peer that stops reading cannot hold a slot. ^nipc-eiy8
9. As a service author, I want a peer disconnect during the handler to cancel the handler as an interruption and free the slot, so that abandoned requests do not run on. ^nipc-1v8z
10. As a service author, I want exactly one request and one newline-terminated reply per connection, then close, so that the protocol is trivial for a CLI. ^nipc-ajmi
11. As an operator, I want retirement to stop admission, cancel and join every peer, and unlink only the socket identity it created, so that a replacement started meanwhile is untouched. ^nipc-uatz
12. As a test author, I want the listener testable with real Unix sockets in a temporary runtime directory: existing file, live listener, stale socket, insecure directory, saturation, slowloris, disconnect mid-handler, and shutdown. ^nipc-01bn
13. As a service author, I want a request cut at its handler budget to receive a reply I choose, so that a client learns it timed out instead of seeing the connection close. ^nipc-i5ni

## Implementation Decisions

- Copy the ownership sequence from Pie's `assistant_service/server.ml` (v1-era; `/home/ribelo/projects/ribelo/pie/packages/pie/assistant_service/server.ml`): verified parent directory, process-local registry keyed by device/inode, adjacent lockfile with a nonblocking OS lock, stale probe, bind, retained socket identity; keep the lock until retirement finishes. The Pie ticket `control-socket-ownership` documents why each step exists.
- Listening socket imported with `Eio_unix.Net.import_socket_listening ~close_unix:true` (Eio's `listen` unlinks the path on switch exit; we must not).
- Deadlines through `Eta.Timeout` on the supplied clock; the handler budget wraps only the handler; disconnect detection by the read side closing.
- Story 13 ^nipc-i5ni: a handler cut at its budget still reports `Handler_budget_exceeded through `on_peer_error`; with `?on_budget_exceeded` supplied, the listener calls it with the decoded request and the budget that expired, encodes its response and writes it through the same egress path as a handler's own reply — same byte bound, same egress deadline — and closes as it does after any reply. Without the callback nothing is written, which is the behaviour the twelve stories above shipped. The callback runs in the peer's fiber with no listener-imposed deadline of its own — a quick reply, Leash's naming the command and the elapsed time — so only the write it feeds is bounded.
- Decode/encode are caller-supplied; the listener never sees JSON.
- Defaults: 16 peers, backlog 16, 64 KiB line, 1 s ingress, 1 s egress.

## Testing Decisions

- All thirteen stories at the socket seam under `test/ipc/` with a temporary directory per test and a mock clock for deadlines where possible (real sockets, virtual time for the budget).
- Story 13 ^nipc-i5ni at the same seam: a handler sleeping past a two-second budget answers a real client with the callback's reply, which names the request and the elapsed budget, and then closes; the byte bound refuses that reply with `Egress_too_large` and writes nothing; the egress deadline cuts the write of an eight-megabyte reply with `Egress_timeout`; and with no callback the peer is closed with no reply, as before. Leash L35 (hard-yi0a) needs the first of these: the `timeout` reply that names the command and the elapsed time.

## Out of Scope

TCP, authentication, multiple requests per connection, streaming replies.

Verification: scoped `nix develop -c env DUNE_BUILD_DIR=_build_ipc dune build --only-packages eta_ipc,eta,eta_test @install` passed (full install also passed before a concurrent empty eta_observability package was added).
Verification: `nix develop -c env DUNE_BUILD_DIR=_build_ipc dune test` passed (including twelve IPC socket tests).
Verification: story 13 `^nipc-i5ni` (Leash L35 hard-yi0a) adds four socket cases — a handler cut at a two-second budget answers the client with the callback's reply, which names the request and the elapsed budget, and the connection closes after it; the byte bound and the egress deadline cut that reply exactly as they cut a handler's own; and with no callback the peer is closed with no reply — and `nix develop -c env DUNE_BUILD_DIR=_build_ipcb dune build @install`, `dune test` (sixteen IPC cases, the other twelve unchanged) and `dune build @fmt` passed on the whole tree.
