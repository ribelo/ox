#!/bin/sh
# Run via: nix develop -c sh /tmp/suspend-token-cost/leash/compile.sh
set -u
cd /tmp/suspend-token-cost/leash
ocamlc -version > compiler-version.txt
ocamlfind ocamlopt -package eio,yojson -c io.ml shim.ml download_setup.ml > positive.stdout 2> positive.stderr
p=$?
ocamlfind ocamlopt -package eio,yojson -c download_setup_negative.ml > negative.stdout 2> negative.stderr
n=$?
ocamlfind ocamlopt -package eio,yojson -c bind_negative.ml > bind-negative.stdout 2> bind-negative.stderr
b=$?
printf "positive=%s negative=%s bind_negative=%s\n" "$p" "$n" "$b"
test "$p" -eq 0 && test "$n" -ne 0 && test "$b" -ne 0
