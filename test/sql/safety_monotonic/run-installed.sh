#!/usr/bin/env bash
# ^safe-p9cw ^safe-8peq ^safe-5a9k: create a permanent consumer outside all Git trees.
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd -- "$source_dir/../../.." && pwd -P)
root=/var/tmp/ox-sql-monotonic-safe-p9cw-8peq-5a9k
# This subtree is deliberate, durable evidence; never use mktemp or delete it.
python3 - "$root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve()
assert str(root) == '/var/tmp/ox-sql-monotonic-safe-p9cw-8peq-5a9k'
for ancestor in [root, *root.parents]:
    assert not (ancestor / '.git').exists(), ancestor
PY
mkdir -p "$root/prefix" "$root/consumer" "$root/evidence"
cd -- "$repo"
dune build @test/sql/safety_monotonic/installed-consumer-inputs
dune install --prefix "$root/prefix" >"$root/evidence/install.log" 2>&1
cp -- "$source_dir/sql_monotonic.ml" "$source_dir/sql_monotonic.mli" "$root/consumer/"
cp -- "$source_dir"/consumer/* "$root/consumer/"
# Verify the exported installed artifacts do not resolve into any repository.
python3 - "$root/prefix" <<'PY'
import pathlib, sys
prefix = pathlib.Path(sys.argv[1]).resolve()
for name in ['lib/ox_sql/ox_sql.cmi', 'lib/ox_sql/ox_sql__Pool.cmi', 'lib/ox_sql/ox_sql__Migrate.cmi']:
    artifact = (prefix / name).resolve(strict=True)
    assert artifact.is_relative_to(prefix), artifact
PY
sha256sum "$root/consumer"/*.ml "$root/consumer"/*.mli "$root/consumer/check-consumer.sh" >"$root/evidence/consumer.sha256"
expected='sql-monotonic-installed: public positive + 6 precise clock rejections + 15 runtime controls passed'
(cd / && bash "$root/consumer/check-consumer.sh") >"$root/evidence/cwd-root.stdout" 2>"$root/evidence/cwd-root.stderr"
(cd "$root/consumer" && bash "$root/consumer/check-consumer.sh") >"$root/evidence/cwd-consumer.stdout" 2>"$root/evidence/cwd-consumer.stderr"
printf '%s\n' "$expected" >"$root/evidence/installed.expected"
cmp "$root/evidence/installed.expected" "$root/evidence/cwd-root.stdout"
cmp "$root/evidence/installed.expected" "$root/evidence/cwd-consumer.stdout"
printf '%s\n' '0' >"$root/evidence/installed.status"
printf '%s\n' "$expected" 'sql-monotonic-installed: both / and permanent consumer CWD oracles passed'
