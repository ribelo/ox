"""Reject inherited/mixed artifacts before any positive or negative control. ^nonce-mjpe"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys

manifest = json.loads(pathlib.Path(os.environ["EIO_LOCAL_ONCE_MANIFEST"]).read_text())
identity = manifest["identity"]
assert identity["version"] == "1.6+ox-local-once.1"
assert identity["patchSha256"] == "320bf57c259ed34c43306f83662a788eb1c721522bca4ec7a5f9806719e5cd84"
assert identity["sourceSha256"] == "c1f04986b401094176494863dde1ca9b292b59fdc679a9d7023e558d80fb5b15"
assert identity["sourceCommit"] == "1fc0efa41ccfb3818b09f54feec90ec29b47f1b6"
patch = pathlib.Path(os.environ["EIO_LOCAL_ONCE_PATCH"]).read_bytes()
assert hashlib.sha256(patch).hexdigest() == identity["patchSha256"]
assert patch.count(b"\n--- a/") + patch.startswith(b"--- a/") == 4
assert all(name not in os.environ for name in ("OPAMROOT", "OPAMSWITCH", "OPAM_SWITCH_PREFIX"))


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def inside(path, root):
    pathlib.Path(path).resolve().relative_to(pathlib.Path(root).resolve())


compiler = pathlib.Path(sys.argv[1]).resolve()
inside(compiler, manifest["compiler"])
assert command(str(compiler), "-version") == "5.4.0+ox"
assert command("dune", "--version") == "3.22.2"
inside(command("ocamlfind", "printconf", "conf"), manifest["findlib"])
inside(command(str(compiler), "-where"), manifest["compiler"])
for name in ("OCAMLPATH", "CAML_LD_LIBRARY_PATH"):
    for path in os.environ[name].split(":"):
        assert path.startswith("/nix/store/"), (name, path)
        assert any(path.startswith(root + "/") for root in manifest["libraryRoots"]), path
for name, root in manifest["providers"].items():
    packages = [name]
    if name == "eio":
        packages += ["eio.core", "eio.mock", "eio.runtime_events", "eio.unix"]
    for package in packages:
        directory = pathlib.Path(command("ocamlfind", "query", package))
        inside(directory, root)
        assert command("ocamlfind", "query", "-format", "%v", package) == identity["version"], package
        for extension in ("*.cmi", "*.cmxa", "*.cma", "*.a"):
            assert any(directory.rglob(extension)), (package, extension)
        print(f"ORIGIN {package}: {directory}")
    if name != "eio_main":
        stub_name = "eio_unix" if name == "eio" else name
        for pattern in (f"lib{stub_name}_stubs.a", f"dll{stub_name}_stubs.so"):
            artifacts = list(pathlib.Path(root).rglob(pattern))
            assert len(artifacts) == 1, (name, pattern, artifacts)
            print(f"STUB {name}: {artifacts[0]}")
for name, root in manifest["consumers"].items():
    directory = pathlib.Path(command("ocamlfind", "query", name))
    inside(directory, root)
    assert any(directory.rglob("*.cmi")) and any(directory.rglob("*.cmxa")), name
    print(f"REBUILT {name}: {directory}")
if manifest["scope"] == "ox":
    assert len(manifest["consumers"]) == 17
else:
    assert manifest["scope"] == "external" and manifest["externalConsumer"]
    probe = pathlib.Path(manifest["externalConsumer"]) / "bin/eio-local-once-probe"
    assert probe.is_file() and os.access(probe, os.X_OK)
    subprocess.run([str(probe)], check=True, timeout=120)
    print(f"EXTERNAL independent consumer: {probe}")
for path in command("ocamlfind", "query", "-recursive", "eio.mock", "eio_posix", "eio_main").splitlines():
    assert path.startswith("/nix/store/"), path
print(f"PROVENANCE {manifest['scope']}: exact source/patch/compiler, whole provider family, no OPAM fallback")
