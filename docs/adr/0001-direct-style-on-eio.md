# Direct style on Eio, no blueprint interpreter

Eta v1 described programs as `('a, 'err) Effect.t` blueprints interpreted by a runtime over an SPI, with Eio as the backend. The interpreter was where every hard bug lived (interruption identity, background provenance, silent defects at the door, a child-process SIGKILL race), it duplicated Eio's cancellation model, and its unique benefit — other backends — had no users. eta-next writes programs as ordinary OCaml functions running in Eio fibers: Eio owns concurrency and cancellation, Eta adds only the combinators Eio lacks (`race`, `timeout`, `par`, `with_background`, `acquire_release`, `retry`, `repeat`), each a direct-style function that classifies its outcome into a Cause at the scope boundary. Eta defines no effects of its own and no capability layer: operating-system capabilities are Eio's values passed explicitly, dynamic context is Eio fiber-local storage, and a raw `perform` is permitted only inside a stream implementation.

## Considered options

- **Keep the blueprint and shrink the surface.** Rejected: the cost is the interpreter itself, not the surface around it.
- **Ambient Eta-owned effects (`Now`, `Sleep`, `Log`) handled at the door.** Rejected: a handler installed outside `Fiber.fork` is not on the forked fiber's stack, so ambient effects and Eio fibers do not compose without exactly the plumbing the interpreter had. Fiber-local keys already do this correctly.
