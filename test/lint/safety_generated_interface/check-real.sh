#!/usr/bin/env bash
# ^safe-y047 ^nlintcov-q6n2: the four actual previously undecided source identities.
# Manual integration probe: run outside Dune (it queries this same workspace inventory).
# Build @test/app/check @test/json/check @test/ppx/check before running this probe.
# bash check-real.sh /absolute/path/to/test_generated.exe /absolute/workspace
set -euo pipefail
probe=$(realpath "$1")
root=$(realpath "$2")
unset DUNE_INSIDE_DUNE
for source in test/app/run test/app/signal_fixture test/json/run test/ppx/run; do
  [[ ! -e "$root/$source.mli" && ! -e "$root/_build/default/$source.mli" ]]
done
"$probe" checked "$root" \
  "$root/_build/default/test/app/.run.eobjs/byte/dune__exe__Run.cmti" \
  "$root/_build/default/test/app/.signal_fixture.eobjs/byte/dune__exe__Signal_fixture.cmti" \
  "$root/_build/default/test/json/.run.eobjs/byte/dune__exe__Run.cmti" \
  "$root/_build/default/test/ppx/.run.eobjs/byte/dune__exe__Run.cmti"
printf '%s\n' 'actual app/run, app/signal_fixture, json/run, ppx/run generated interfaces: pass'
