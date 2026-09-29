#!/usr/bin/env bash
# ^ncaps-n6r0 ^ncaps-w6n2 ^ncaps-a27b ^ncaps-tpjy ^ncaps-uiq6
# ^ncaps-znyh ^ncaps-rwnz: the gate script as installed, over fixture trees copied
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

cp -R violating clean skip-clean skip-violating door-dependency door-access stream-violating shadowed "$work/"
# dune fmt leaves .formatted copies beside the fixtures in the build tree.
find "$work" -name .formatted -type d -prune -exec rm -rf {} +
for fixture in violating clean skip-clean skip-violating door-dependency door-access stream-violating shadowed; do
  git -C "$work/$fixture" init -q
done

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
# ^ncaps-a27b ^ncaps-tpjy ^ncaps-rwnz: a partially parsed OxCaml file.
(cd "$work/skip-clean" && bash "$gate") >"$work/skip-clean.out" 2>&1
code=$?
if [ "$code" -eq 0 ] && grep -q 'lexical scan lib/unparseable.ml (Semgrep PartialParsing)' "$work/skip-clean.out"; then
  echo "ok: partially parsed clean file passes after a reported lexical scan"
else
  echo "FAIL: clean OxCaml file exit $code or missing lexical scan"
  cat "$work/skip-clean.out"
  status=1
fi
(cd "$work/skip-violating" && bash "$gate") >"$work/skip-violating.out" 2>&1
code=$?
if [ "$code" -eq 1 ] && grep -q 'lexical scan lib/unparseable.ml (Semgrep PartialParsing)' "$work/skip-violating.out" && grep -q 'forbidden identifier Unix.fork' "$work/skip-violating.out"; then
  echo "ok: partially parsed forbidden call fails the lexical scan"
else
  echo "FAIL: forbidden call in OxCaml file exit $code or missing finding"
  cat "$work/skip-violating.out"
  status=1
fi
if (cd "$work/skip-violating" && bash "$gate" --allow lib/unparseable.ml) >"$work/skip-allowed.out" 2>&1 && ! grep -q 'lexical scan' "$work/skip-allowed.out"; then
  echo "ok: --allow also excludes files from the lexical fallback"
else
  echo "FAIL: --allow did not exclude the partial-parse file"
  cat "$work/skip-allowed.out"
  status=1
fi

# ^ncaps-uiq6 ^ncaps-rwnz: direct door access and a Dune dependency.
(cd "$work/door-dependency" && bash "$gate") >"$work/door-dependency.out" 2>&1
code=$?
if [ "$code" -eq 1 ] && grep -q 'lib/dune:3: forbidden dependency ox_caps.door' "$work/door-dependency.out"; then
  echo "ok: a library cannot depend on ox_caps.door"
else
  echo "FAIL: unexpected door dependency exit $code"
  cat "$work/door-dependency.out"
  status=1
fi
(cd "$work/door-access" && bash "$gate") >"$work/door-access.out" 2>&1
code=$?
if [ "$code" -eq 1 ] && grep -q 'lib/intruder.ml:2: forbidden Ox_caps_door access' "$work/door-access.out"; then
  echo "ok: a library cannot name Ox_caps_door directly"
else
  echo "FAIL: unexpected direct door access exit $code"
  cat "$work/door-access.out"
  status=1
fi

# ^ncaps-znyh ^ncaps-rwnz: bare channels and file openers.
(cd "$work/stream-violating" && bash "$gate") >"$work/stream-violating.out" 2>&1
code=$?
if [ "$code" -eq 1 ] && grep -q 'ox-caps-stdin' "$work/stream-violating.out" && grep -q 'ox-caps-stdout' "$work/stream-violating.out" && grep -q 'ox-caps-stderr' "$work/stream-violating.out" && grep -q 'ox-caps-fs-read' "$work/stream-violating.out" && grep -q 'ox-caps-fs-write' "$work/stream-violating.out"; then
  echo "ok: bare channels and In_channel/Out_channel file openers fail"
else
  echo "FAIL: stream/file rules exit $code or missing findings"
  cat "$work/stream-violating.out"
  status=1
fi

(cd "$work/shadowed" && bash "$gate") >"$work/shadowed.out" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  echo "ok: shadowed channel names and record labels are not Stdlib streams"
else
  echo "FAIL: shadowed stdout exit $code"
  cat "$work/shadowed.out"
  status=1
fi

exit "$status"
