"""Own one release-plus-annotations recipe, including real source packaging. ^nonce-lrzq"""
import hashlib
import json
import pathlib
import re
import shutil
import sys

upstream, patch, source, out, manifest = map(pathlib.Path, sys.argv[1:])
identity = json.loads(manifest.read_text())
assert hashlib.sha256(patch.read_bytes()).hexdigest() == identity["patchSha256"]
project = (source / "dune-project").read_text()
assert not re.search(r"^\(version\s", project, re.M)
project_version = (project + f'\n(version {identity["version"]})\n').encode()
out.mkdir()
(out / "repo").write_text('opam-version: "2.0"\n')
shutil.copyfile(manifest, out / "identity.json")
for name in ("eio", "eio_posix", "eio_linux", "eio_main"):
    original = upstream / "packages" / name / f"{name}.{identity['upstreamVersion']}" / "opam"
    metadata = original.read_text()
    assert identity["sourceUrl"] in metadata, original
    assert "sha256=" + identity["sourceSha256"] in metadata, original
    assert not re.search(r"^(patches|extra-files):", metadata, re.M), original
    version = f'version: "{identity["version"]}"'
    if re.search(r"^version:", metadata, re.M):
        metadata = re.sub(r'^version:.*$', version, metadata, flags=re.M)
    else:
        metadata = version + "\n" + metadata
    directory = out / "packages" / name / f"{name}.{identity['version']}"
    files = directory / "files"
    files.mkdir(parents=True)
    shutil.copyfile(patch, files / "local-once.patch")
    # Generated-opam projects require project version metadata for installed
    # META/dune-package identity. Only the authenticated project version changes;
    # this is packaging, not a provider implementation patch or fake interface.
    (files / "dune-project").write_bytes(project_version)
    package_opam = metadata.encode()
    (files / f"{name}.opam").write_bytes(package_opam)
    metadata += ('\npatches: [ "local-once.patch" ]\nextra-files: [\n'
                 f'  [ "local-once.patch" "sha256={identity["patchSha256"]}" ]\n'
                 f'  [ "{name}.opam" "sha256={hashlib.sha256(package_opam).hexdigest()}" ]\n'
                 f'  [ "dune-project" "sha256={hashlib.sha256(project_version).hexdigest()}" ]\n'
                 ']\n')
    (directory / "opam").write_text(metadata)
