# ^safe-tpzm ^safe-zxc1: the first executable name alone owns the object directory.
reorder="$scratch/reorder"
mkdir "$reorder"
printf '(lang dune 3.21)\n(name first_object_owner)\n' > "$reorder/dune-project"
printf 'let value = 1\n' > "$reorder/helper.ml"
printf 'val value : int\n' > "$reorder/helper.mli"
for module in first second; do printf 'let () = ignore Helper.value\n' > "$reorder/$module.ml"; done
printf '(executables (names first second) (modules first second helper))\n' > "$reorder/dune"
(cd "$reorder"; "${DUNE:-dune}" build @check)
reorder_cmt="$reorder/_build/default/.first.eobjs/byte/dune__exe__Helper.cmt"
reorder_cmti="$reorder/_build/default/.first.eobjs/byte/dune__exe__Helper.cmti"
reorder_generated="$reorder/_build/default/.first.eobjs/byte/dune__exe__First.cmti"
reorder_body="$reorder/_build/default/first.mli"
reorder_files=("$reorder/first.ml" "$reorder/second.ml" "$reorder/helper.ml" "$reorder/helper.mli" "$reorder_cmt" "$reorder_cmti" "$reorder_generated" "$reorder_body")
reorder_hash=$(sha256sum "${reorder_files[@]}")
reorder_time=$(stat -c '%n:%y' "${reorder_files[@]}")
check_annotation 0 "$reorder_cmt"
check_annotation 0 "$reorder_cmti"
check_annotation 0 "$reorder_generated"
# No rebuild: preserving a non-first member is not preserving the object owner.
printf '(executables (names second first) (modules first second helper))\n' > "$reorder/dune"
check_annotation 2 "$reorder_cmt"
check_annotation 2 "$reorder_cmti"
check_annotation 2 "$reorder_generated" generated-owner
printf '(executables (names first second) (modules first second helper))\n' > "$reorder/dune"
check_annotation 0 "$reorder_cmt"
check_annotation 0 "$reorder_cmti"
check_annotation 0 "$reorder_generated"
# A literal first name is not an owner when the constructor's name field is invalid.
for invalid in \
  '(executable (names first second) (modules first second helper))' \
  '(executables (name first) (modules first second helper))' \
  '(executable (name first second) (modules first second helper))'; do
  printf '%s\n' "$invalid" > "$reorder/dune"
  check_annotation 2 "$reorder_cmt"
  check_annotation 2 "$reorder_cmti"
  check_annotation 2 "$reorder_generated" generated-owner
done
printf '(executables (names first second) (modules first second helper))\n' > "$reorder/dune"
check_annotation 0 "$reorder_cmt"
check_annotation 0 "$reorder_cmti"
check_annotation 0 "$reorder_generated"
[[ "$(sha256sum "${reorder_files[@]}")" = "$reorder_hash" ]]
[[ "$(stat -c '%n:%y' "${reorder_files[@]}")" = "$reorder_time" ]]
