#!/usr/bin/env python3
"""^nlintcov-8g4p: independent tracked-source census vs real engine decisions.

Usage: python3 coverage.py ENGINE WORKSPACE
Run after building ENGINE, outside any Dune invocation using WORKSPACE.
Stdout: one tracked-source count summary. Stderr: detailed failures.
Exit 0: complete strict coverage; 1: coverage/scan failed; 2: setup/usage error.
"""
import argparse
import collections
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(
    description="Compare Git-tracked OCaml sources with strict ox-lint inventory.",
    epilog="Run outside Dune after building the scanner. Example: python3 "
           "test/lint/deployment/coverage.py _build/default/lib/ox_lint/main.exe .",
)
parser.add_argument("engine", help="built ox-lint executable")
parser.add_argument("workspace", help="directory inside the Git workspace to scan")
args = parser.parse_args()
try:
    engine = str(Path(args.engine).resolve())
    root = Path(subprocess.check_output(
        ["git", "-C", args.workspace, "rev-parse", "--show-toplevel"], text=True
    ).strip())
    tracked = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--", "*.ml", "*.mli"]
    ).decode().split("\0")
    tracked = {path for path in tracked if path}
    scan = subprocess.run(
        [engine, "--caps-gate", "--require-typed", "--inventory"],
        cwd=root, text=True, capture_output=True,
    )
except (OSError, subprocess.CalledProcessError) as error:
    print("coverage setup failed: " + str(error), file=sys.stderr)
    sys.exit(2)

def key(path):
    # Preserve the source symlink's module name, not its target's basename.
    return os.path.relpath(os.path.abspath(root / path), root)

files = {}
directories = []
seen = set()
errors = []
for line in scan.stdout.splitlines():
    fields = line.split("\t")
    if len(fields) != 3:
        errors.append("non-inventory output: " + line)
        continue
    path, decision, reason = fields
    if not path or not reason:
        errors.append("empty inventory path/reason: " + line)
        continue
    inventory_path = key(path) + ("/" if path.endswith("/") else "")
    if inventory_path in seen:
        errors.append("duplicate inventory path: " + path)
        continue
    seen.add(inventory_path)
    if decision not in {"decided", "excluded", "undecided"}:
        errors.append("invalid inventory decision: " + line)
        continue
    entry = (decision, reason)
    if path.endswith("/"):
        if decision != "excluded":
            errors.append("directory inventory must be an exclusion: " + line)
            continue
        directories.append((key(path), entry))
    else:
        files[key(path)] = entry

counts = collections.Counter()
for path in sorted(tracked):
    # This is intentionally not Dune membership or the engine's directory walk.
    # The engine must account for every tracked source, including documentation.
    entry = files.get(path)
    if entry is None:
        ancestors = [(parent, decision) for parent, decision in directories
                     if path.startswith(parent + "/")]
        if ancestors:
            entry = max(ancestors, key=lambda item: len(item[0]))[1]
    if entry is None:
        errors.append("coverage hole: " + path)
        counts["coverage-holes"] += 1
        continue
    if path.startswith("docs/"):
        # Historical issue spikes/evidence are not Ox build targets. Keep this
        # named boundary narrow rather than accepting every unknown source root.
        if not path.startswith("docs/issues/") or not any(
                part in {"spike", "evidence"} for part in path.split("/")):
            errors.append("unreviewed documentation source: " + path)
        if any((root / "docs").rglob("dune")):
            errors.append("documentation evidence gained a Dune build stanza: " + path)
        if entry != ("excluded", "not-built"):
            errors.append("documentation evidence must be excluded as not-built: "
                          + path + ": " + ": ".join(entry))
            if entry[0] == "undecided":
                counts["undecided"] += 1
        counts["documentation-evidence"] += 1
        continue
    decision, reason = entry
    if decision == "undecided":
        errors.append("undecided: " + path + ": " + reason)
        counts["undecided"] += 1
    elif decision == "decided":
        counts["decided"] += 1
    elif reason == "nested-project":
        # Independently check the structural fact, not a source's self-claim.
        parents = (root / path).parents
        if not any(parent != root and (parent / "dune-project").is_file()
                   for parent in parents if parent.is_relative_to(root)):
            errors.append("unjustified nested-project exclusion: " + path)
        counts[reason] += 1
    elif reason in {"data-only", "not-built"}:
        counts[reason] += 1
    else:
        # A tracked OCaml source is not an empty directory or ignored mirror.
        errors.append("unjustified tracked-source exclusion: " + path + ": " + reason)

if scan.returncode != 0:
    errors.append("strict inventory exit=" + str(scan.returncode))
print("tracked-source coverage: " + str(len(tracked)) + " tracked; "
      + "; ".join(str(count) + " " + name for name, count in sorted(counts.items())
                  if name not in {"coverage-holes", "undecided"})
      + "; " + str(counts["coverage-holes"]) + " coverage holes; "
      + str(counts["undecided"]) + " undecided")
if errors:
    print("\n".join(errors), file=sys.stderr)
    print(scan.stderr, file=sys.stderr)
    sys.exit(1)
