#!/usr/bin/env bash
# ^ncaps-n6r0 ^ncaps-w6n2: the gate script as installed, over fixture trees copied
# copied outside this checkout and made repositories of their own, as a consumer's tree
# is (Semgrep resolves --allow paths from the repository root). The files stay
# untracked: the gate scans untracked files too.
set -uo pipefail
gate="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home"
mkdir -p "$HOME"
status=0

cp -R violating clean "$work/"
# dune fmt leaves .formatted copies beside the fixtures in the build tree.
find "$work" -name .formatted -type d -prune -exec rm -rf {} +
git -C "$work/violating" init -q
git -C "$work/clean" init -q

# Every rule reports its line in violating/lib/raw.ml, and the gate fails.
(cd "$work/violating" && bash "$gate") >"$work/violating.out" 2>&1
code=$?
expected="ox-caps-chdir ox-caps-env ox-caps-exec ox-caps-exit ox-caps-forge ox-caps-fork ox-caps-fs-read ox-caps-fs-write ox-caps-mint ox-caps-network ox-caps-random ox-caps-signal ox-caps-stderr ox-caps-stdin ox-caps-stdout ox-caps-time ox-caps-tmp"
found="$(grep -o 'ox-caps-[a-z-]*' "$work/violating.out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
if [ "$code" -eq 1 ] && [ "$found" = "$expected" ]; then
  echo "ok: every rule fires on violating/ and the gate exits 1"
else
  echo "FAIL: violating/ exit $code, rules found: $found"
  cat "$work/violating.out"
  status=1
fi
if grep -q 'raw_test.ml' "$work/violating.out"; then
  echo "FAIL: a file under test/ was scanned"
  status=1
else
  echo "ok: test/ is outside the gate"
fi
if grep -q '(\* nosemgrep \*)' "$work/violating.out"; then
  echo "ok: an inline nosemgrep does not silence a rule"
else
  echo "FAIL: the nosemgrep line was not reported"
  status=1
fi

# The wrappers and the entry's exit form pass.
if (cd "$work/clean" && bash "$gate") >"$work/clean.out" 2>&1; then
  echo "ok: clean/ passes"
else
  echo "FAIL: clean/ was refused"
  cat "$work/clean.out"
  status=1
fi

# An allow-list entry excludes exactly the file it names.
if (cd "$work/violating" && bash "$gate" --allow lib/raw.ml) >"$work/allowed.out" 2>&1; then
  echo "ok: --allow excludes the named file"
else
  echo "FAIL: --allow lib/raw.ml did not exclude it"
  cat "$work/allowed.out"
  status=1
fi
exit "$status"
