# ^safe-tpzm ^safe-zxc1: execute declared nested fixtures under CLEAN compiler policy.
# SOURCE_FIXTURES is the registered source tree or mandatory genuinely installed data.
source_control="$scratch/source-controls"
mkdir "$source_control"
for fixture in dune-project dune bad.ml bad.mli restored.ml restored.mli attached_bad.ml attached_bad.mli attached_clean.ml attached_clean.mli two_sites.ml two_sites.mli duplicate_sites.ml duplicate_sites.mli nonliteral.ml nonliteral.mli; do
  cp "$SOURCE_FIXTURES/$fixture" "$source_control/$fixture"
done
# Registered Dune source-tree copies are read-only; only this scratch project is edited.
chmod u+w "$source_control/dune-project"
for language in 3.21 3.22; do
  printf '(lang dune %s)\n(name warning_policy_negative)\n' "$language" > "$source_control/dune-project"
  (cd "$source_control"; "${DUNE:-dune}" build @check)
  # Positive restored/no-annotation sites prove no ambient compiler restriction.
  check_source_control 0 "$source_control/restored.ml" clean
  check_source_control 0 "$source_control/restored.mli" clean
  check_source_control 1 "$source_control/bad.ml" source-8-one
  check_source_control 1 "$source_control/bad.mli" source-8-one
  check_source_control 1 "$source_control/attached_bad.ml" source-8-two
  check_source_control 1 "$source_control/attached_bad.mli" source-8-two
  check_source_control 0 "$source_control/attached_clean.ml" clean
  check_source_control 0 "$source_control/attached_clean.mli" clean
  check_source_control 1 "$source_control/two_sites.ml" source-two-sites
  oracle_calibrate "$source_control/two_sites.ml"
  check_source_control 1 "$source_control/duplicate_sites.ml" source-duplicate-sites
  check_source_control 2 "$source_control/nonliteral.ml" source-nonliteral
  check_source_control 2 "$source_control/nonliteral.mli" source-nonliteral
done
