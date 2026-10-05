#!/usr/bin/env bash
# ^safe-p9cw ^safe-8peq ^safe-5a9k: serial full-gate evidence for this SQL slice.
set -uo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd -- "$source_dir/../../.." && pwd -P)
round=${1:-round-01}
case "$round" in round-[0-9][0-9]) ;; *) printf 'invalid gate round\n' >&2; exit 2 ;; esac
root=/var/tmp/ox-sql-monotonic-safe-p9cw-8peq-5a9k
out="$root/gates/$round"
mkdir -p "$out"
cd -- "$repo"
sha256sum lib/sql/pool.ml lib/sql/pool.mli lib/sql/migrate.ml lib/sql/migrate.mli test/sql/run.ml "$source_dir"/*.ml "$source_dir"/*.mli "$source_dir"/consumer/*.ml "$source_dir"/consumer/*.mli "$source_dir"/*.sh "$source_dir"/consumer/*.sh >"$out/source.sha256"
printf '%s\n' "$repo" >"$out/worktree"
overall=0
gate() {
  name=$1; shift
  printf 'running\n' >"$out/$name.status"
  date -u +%FT%TZ >"$out/$name.started"
  printf 'nix develop -c'; printf ' %q' "$@"; printf '\n'
  nix develop -c "$@" >"$out/$name.log" 2>&1
  status=$?
  printf '%s\n' "$status" >"$out/$name.status"
  date -u +%FT%TZ >"$out/$name.finished"
  printf '%s exit=%s\n' "$name" "$status"
  if [ "$status" -ne 0 ]; then overall=1; fi
}
gate 01-install dune build @install
gate 02-test dune test
gate 03-fmt dune build @fmt
gate 04-caps scripts/caps-gate
printf '%s\n' "$overall" >"$out/overall.status"
exit "$overall"
