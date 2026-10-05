"""Mutate actual patched provider bodies, never interfaces or consumer shims. ^nonce-mjpe"""
import pathlib
import sys

source, out = map(pathlib.Path, sys.argv[1:])
bodies = {
    "cancel": (source / "lib_eio/core/cancel.ml").read_text(),
    "eio_mutex": (source / "lib_eio/eio_mutex.ml").read_text(),
}
changes = {
    "cancel-reuse": ("cancel", "  match fn t with", "  ignore (fn t);\n  match fn t with"),
    "cancel-store": ("cancel", "  match fn t with", "  let heap_edge = ref fn in\n  match (!heap_edge) t with"),
    "mutex-reuse": ("eio_mutex", "let use_rw ~protect t (fn @ local once) =", "let use_rw ~protect t (fn @ local once) =\n  ignore (fn ());"),
    "mutex-store": ("eio_mutex", "let use_rw ~protect t (fn @ local once) =", "let use_rw ~protect t (fn @ local once) =\n  let heap_edge = ref fn in\n  ignore heap_edge;"),
}
for name, body in bodies.items():
    directory = out / (name + "-genuine")
    directory.mkdir(parents=True)
    (directory / (name + ".ml")).write_text(body)
for name, (module, old, new) in changes.items():
    body = bodies[module]
    assert body.count(old) == 1, name
    directory = out / name
    directory.mkdir(parents=True)
    (directory / (module + ".ml")).write_text(body.replace(old, new))
