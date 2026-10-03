#!/bin/sh
set -eu
rm -rf /tmp/cancellation-value && mkdir -p /tmp/cancellation-value && cp "$(dirname "$0")"/*.ml "$(dirname "$0")"/*.mli /tmp/cancellation-value/ && cd /tmp/cancellation-value
ocamlopt -version
for m in interrupt_id cause exit scope concurrent duration timeout cancellation channel_base channel; do
  ocamlfind ocamlopt -package eio -c "$m.mli" "$m.ml"
done
modules="interrupt_id.cmx cause.cmx exit.cmx scope.cmx concurrent.cmx duration.cmx timeout.cmx cancellation.cmx channel_base.cmx channel.cmx"
ocamlfind ocamlopt -package eio_main -linkpkg $modules ox.ml main.ml -o spike
timeout 20 ./spike
ocamlfind ocamlopt -package eio_main -linkpkg channel_base.cmx eio_view.ml view_main.ml -o view_control
timeout 10 ./view_control
ocamlfind ocamlopt -package eio_main -linkpkg cancellation.cmx local_callback.ml -o local_callback
./local_callback
ocamlfind ocamlopt -package eio_main -linkpkg $modules ox.cmx door_mapping.ml door_main.ml -o door_control
timeout 20 ./door_control
for f in escape capture direct_eio double_callback; do
  if ocamlfind ocamlopt -package eio -c "$f.ml" > "$f.log" 2>&1; then
    printf 'UNEXPECTED ACCEPT %s\n' "$f"
    exit 1
  else
    printf 'EXPECTED REFUSAL %s\n' "$f"
  fi
done
