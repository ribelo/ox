---
status: ready-for-agent
package: eta (Actor)
consumer: Leash (tab registry, expiry sweep, run loop state), Pie (recording coordinator), nema (watcher)
---

# Actor: a typed mailbox with a state fold, supervised in a scope

## Problem Statement

Several long-lived parts of the applications are one mutable state touched by many fibers: Leash's tab registry, Pie's recording coordinator, nema's watcher. Today each guards its state with a `Mutex` and hand-written message handling. Ox's `Actor.create(obj)` gives a typed mailbox over an object; Elixir's GenServer (and Tim Smart's `effect-genserver`) gives `state -> message -> (state, reply)` with the state as an explicit value and a stream of state changes. Eta wants the discipline of the second inside the scope rules of the first, without GenServer's schema, RPC or cluster machinery.

## Solution

`Actor.create ~sw ~init ~handle`: one fiber owns the state; `handle : 'state -> 'msg -> ('state * 'reply, 'e) result` is the whole behaviour; `ask actor msg` sends and awaits the reply, `tell actor msg` sends and returns; messages are processed in order, one at a time; a handler's `Error e` is reported to the asker and leaves the state unchanged; a handler's exception ends the actor and its scope (supervised); `changes actor` is a stream of states for observers; the actor lives exactly as long as its switch.

## User Stories

1. As a service author, I want `Actor.create ~sw ~init ~handle` returning `('msg, 'reply, 'e) Actor.t`, where `handle : 'state -> 'msg -> ('state * 'reply, 'e) result`, so that a stateful component is one pure fold plus a mailbox. ^nactor-agcr
2. As a service author, I want `Actor.ask actor msg : ('reply, 'e) result` to enqueue and await, and `Actor.tell actor msg : unit` to enqueue and return, so that both request-reply and fire-and-forget are available. ^nactor-jhl2
3. As a service author, I want messages handled strictly in arrival order, one at a time, so that the state needs no lock. ^nactor-mb6v
4. As a service author, I want a handler returning `Error e` to answer that `ask` with `Error e` and leave the state as it was, so that typed failures do not corrupt state or stop the actor. ^nactor-7qi7
5. As a service author, I want a handler raising an exception to end the actor and fail its switch with that exception (Ox supervision), with every pending `ask` answered `Error \`Actor_stopped`, so that a bug in the actor is loud and structured. ^nactor-pxfz
6. As a service author, I want `Actor.changes actor` to be a bounded stream of states after each successful handler, with documented overflow (drop oldest, count), so that observers (status, UI) can follow without asking. ^nactor-6z3i
7. As a service author, I want `Actor.state actor` to return the current state without sending a message (a snapshot read), so that cheap reads do not queue behind writes. ^nactor-l87k
8. As a service author, I want the mailbox bounded (default 1024) with `tell` blocking when full and `try_tell` returning `false`, so that a slow actor applies backpressure instead of growing without limit. ^nactor-512k
9. As a service author, I want `ask` to accept an optional `?timeout` and to answer `Error \`Timeout` without disturbing the actor, so that a caller can bound its wait. ^nactor-tc19
10. As a service author, I want the actor to stop when its switch ends: the mailbox is closed, in-flight handling finishes, pending asks get `\`Actor_stopped`, and `changes` ends, so that the actor is a resource like any other. ^nactor-e0l5
11. As a service author, I want an optional `~on_stop : 'state -> unit` run once at the end with the final state, so that state can be persisted or reported at shutdown (GenServer's `terminate`), without Eta owning persistence. ^nactor-oxao
12. As a maintainer, I want one consumer moved onto `Actor` in the same row — Leash's tab registry is the candidate — with its 108-cell authorization tests unchanged, so that the abstraction is proven on real state. ^nactor-8z1n

## Implementation Decisions

- One `Eio.Stream` for the mailbox, one fiber forked on `sw` looping `take` → `handle` → resolve the ask's `Promise`; `changes` is a second bounded `Eio.Stream`.
- `ask` = a `Promise` per message; `tell` = no promise. The actor's fiber is a plain `Fiber.fork`; an exception escapes to the switch, which is Ox's supervision.
- No schema, no RPC binding, no persistence, no cluster: GenServer's protocol typing is OCaml's variant type for `'msg`.
- The state type is the author's; immutability is the discipline, not enforced.

## Testing Decisions

- Seam: public module under `Eio_main` with `Eio_mock.Clock` (`test/core`). Ordering under concurrent tells; error leaves state; exception fails the switch and answers pending asks; changes stream and overflow; backpressure; timeout; stop on switch end; `on_stop` once.
- Story 12: Leash's existing registry tests.

## Out of Scope

Persistence, distribution, named registries, supervision trees beyond the owning switch, hot code reload.

## Further Notes

Tim Smart's effect-genserver was read for its handler shape (`state -> payload -> (state, reply)`, `changes` stream, `toLayerPersisted`); its Layer/Context wiring, RPC schemas and cluster entities do not fit and are not taken. Ox's `Actor.create(obj).ask(_.method)` wraps a mutable object with no supervision beyond the scope and no state stream; Eta takes its scope discipline and the explicit-state fold instead of the object.
