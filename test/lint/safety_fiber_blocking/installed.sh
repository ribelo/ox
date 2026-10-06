#!/usr/bin/env bash
# ^safe-9ved ^safe-r5ye ^safe-ohen: installed consumer, explicit assets, no checkout fallback.
set -euo pipefail
[[ $# == 2 ]] || { printf 'usage: bash installed.sh ABS_BIN ABS_SHARE\n' >&2; exit 2; }
bin=$1
share=$2
[[ $bin == /* && $share == /* && -x $bin && -d $share ]] || exit 2
: "${OCAMLPATH:?Pass installed Ox and compiler-matched dependencies explicitly}"
[[ -f $share/test/lint/clean/fiber_blocking.ml && -f $share/test/lint/violating/fiber_blocking.ml ]] || {
  printf 'missing installed fiber_blocking assets\n' >&2; exit 2;
}
bin=$(realpath "$bin")
share=$(realpath "$share")
producer=$(realpath "$(ocamlfind query ox_blocking)")
[[ $producer == */lib/ox_blocking && -f $producer/ox_blocking.cmi ]] || exit 2
work=$(mktemp -d /var/tmp/ox-fiber-installed.XXXXXX)
[[ $(realpath "$work") == /var/tmp/ox-fiber-installed.* && ! -e $work/.git ]] || exit 2
trap 'rm -rf -- "${work:?}"' EXIT
cd "$work"
"$bin" --self-check --rules ox-execution-context --root "$share"
cat > good.ml <<'OCAML'
let timer () = Eio_main.run (fun env -> Eio.Time.sleep (Eio.Stdenv.clock env) 0.001)
let native ~pool () = Eio_main.run (fun _ -> ignore (Ox_blocking.run ~pool (fun () -> Unix.sleepf 0.001)))
let harmless () = Eio_main.run (fun _ -> ignore (Unix.getpid ()))
OCAML
printf 'val timer : unit -> unit\nval native : pool:Ox_blocking.Pool.t -> unit -> unit\nval harmless : unit -> unit\n' > good.mli
cat > bad.ml <<'OCAML'
module U = Unix
let wait = U.sleepf
let helper delay = wait delay
let run () = Eio_main.run (fun _ -> helper 0.001)
OCAML
printf 'val wait : float -> unit\nval helper : float -> unit\nval run : unit -> unit\n' > bad.mli
cat > opaque.ml <<'OCAML'
let run callback = Eio_main.run (fun _ -> callback (fun () -> Unix.sleepf 0.001))
OCAML
printf 'val run : ((unit -> unit) -> unit) -> unit\n' > opaque.mli
for name in good bad opaque; do
  ocamlfind ocamlc -thread -bin-annot -package eio_main,ox_blocking,unix,threads -c "$name.mli"
  ocamlfind ocamlc -thread -bin-annot -package eio_main,ox_blocking,unix,threads -c "$name.ml"
done
# ^safe-ohen: literal public site/category/full-message output, never substring or set checks.
check_output() {
  local wanted_status=$1 wanted_output=$2 source=$3 output status
  set +e
  output=$("$bin" --require-typed --rules ox-execution-context --root "$share" "$source" 2>&1)
  status=$?
  set -e
  [[ $status == "$wanted_status" && $output == "$wanted_output" ]] || {
    printf "expected status %s and literal output:\n%s\nactual status %s:\n%s\n" \
      "$wanted_status" "$wanted_output" "$status" "$output" >&2; exit 1;
  }
}
check_output 0 "" good.ml
check_output 1 "bad.ml:3: ox-execution-context: Eio_main.run Eio callback at bad.ml:4: Unix.sleepf synchronously waits on the scheduler domain; use Eio.Time.sleep with an explicit clock, or Ox_blocking.run ~pool" bad.ml
check_output 2 "opaque.ml:1: ox-lint: line 1: ox-execution-context: Eio_main.run Eio callback at opaque.ml:1: Unix.sleepf synchronously waits on the scheduler domain; use Eio.Time.sleep with an explicit clock, or Ox_blocking.run ~pool; owner execution context cannot be established for this candidate" opaque.ml
printf "\n(* stale evidence must not certify *)\n" >> good.ml
check_output 2 "good.ml:1: ox-lint: stale typed annotation: digest mismatch for $work/good.ml" good.ml
printf 'installed fiber_blocking consumer passed\n'
