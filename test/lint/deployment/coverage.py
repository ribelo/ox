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
import re
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
# ^nlintcov-8g4p: reuse the gate's actual decisions without a second scan/rebuild.
parser.add_argument("--inventory", help="read the just-completed engine inventory from FILE",
                    metavar="FILE")
parser.add_argument("--scan-exit", type=int, help="exit code of that inventory-producing scan")
args = parser.parse_args()
if (args.inventory is None) != (args.scan_exit is None):
    parser.error("--inventory and --scan-exit must be supplied together")
try:
    engine = str(Path(args.engine).resolve())
    root = Path(subprocess.check_output(
        ["git", "-C", args.workspace, "rev-parse", "--show-toplevel"], text=True
    ).strip())
    tracked = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--", "*.ml", "*.mli"]
    ).decode().split("\0")
    tracked = {path for path in tracked if path}
    if args.inventory is not None:
        inventory = Path(args.inventory).read_text()
        scan_exit, scan_stderr = args.scan_exit, ""
    else:
        scan = subprocess.run(
            [engine, "--caps-gate", "--require-typed", "--inventory"],
            cwd=root, text=True, capture_output=True,
        )
        inventory, scan_exit, scan_stderr = scan.stdout, scan.returncode, scan.stderr
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
for line in inventory.splitlines():
    fields = line.split("\t")
    if len(fields) != 3:
        errors.append("non-inventory output: " + line)
        continue
    path, decision, reason = fields
    # ^nlintcov-8g4p: a successful decision has no diagnostic reason.
    # Exclusions and undecided evidence must still explain themselves.
    if not path or (decision != "decided" and not reason):
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
    # ^nlintcov-8g4p: provenance is the documentation tree, not subdirectory
    # names. Actual Dune-resolved membership must still say this source is unbuilt;
    # built or undecided documentation receives the same checks as ordinary code.
    if path.startswith("docs/") and entry in {
            ("excluded", "not-built"), ("excluded", "data-only")}:
        if entry == ("excluded", "data-only") and not re.search(
                r"(?m)^\(data_only_dirs\s+docs\s*\)\s*$", (root / "dune").read_text()):
            errors.append("documentation data-only exclusion lacks root Dune declaration: " + path)
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
    elif reason == "not-built":
        errors.append("unbuilt tracked source outside documentation: " + path)
        counts["coverage-holes"] += 1
    elif reason == "data-only":
        counts[reason] += 1
    else:
        # A tracked OCaml source is not an empty directory or ignored mirror.
        errors.append("unjustified tracked-source exclusion: " + path + ": " + reason)

if scan_exit != 0:
    errors.append("strict inventory exit=" + str(scan_exit))
print("tracked-source coverage: " + str(len(tracked)) + " tracked; "
      + "; ".join(str(count) + " " + name for name, count in sorted(counts.items())
                  if name not in {"coverage-holes", "undecided"})
      + "; " + str(counts["coverage-holes"]) + " coverage holes; "
      + str(counts["undecided"]) + " undecided")
if errors:
    print("\n".join(errors), file=sys.stderr)
    if scan_stderr:
        print(scan_stderr, file=sys.stderr)
    sys.exit(1)
