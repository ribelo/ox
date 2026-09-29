#!/usr/bin/env bash
# rename-eta-to-ox.sh — rename Eta to ox across a checkout.
#
# The rename of 2026-09-29 (Eta row 49, docs/issues/ox-rename/01-ox-rename.md)
# was applied to ox itself with
#
#   scripts/rename-eta-to-ox.sh --skip docs/issues --skip docs/migration-plan.md
#
# and to the consumers (Leash, Pie, nema, inn, grip) with
#
#   scripts/rename-eta-to-ox.sh
#
# Rules, word-bounded so that beta, theta, metadata, detail, retained, meta_state
# and META_* are untouched:
#
#   \bEta_([A-Za-z0-9_]+)  ->  Ox_\1      Eta_json      -> Ox_json
#   \bEta([A-Z_])          ->  Ox\1       EtaNext       -> OxNext
#   \bEta\b                ->  Ox         Eta.Cause     -> Ox.Cause
#   \beta_([A-Za-z0-9_]+)  ->  ox_\1      eta_http      -> ox_http
#   \beta([A-Z_])          ->  ox\1       etaSrc        -> oxSrc
#   \beta\b                ->  ox         eta           -> ox
#   \bETA([A-Z_])          ->  OX\1       ETA_PATH      -> OX_PATH
#   \bETA\b                ->  OX
#
# Paths are renamed with the same rules per component (lib/eta -> lib/ox,
# eta_ai.ml -> ox_ai.ml, eta.opam -> ox.opam, conf-eta-oxcaml ->
# conf-ox-oxcaml), plus docs/why-next.md -> docs/why-ox.md.
#
# Skipped trees: .git, any _build* or node_modules at any depth, and .scratch
# (research evidence, like the archive).
#
# Protected spans keep their names because they name the archive, not the
# library: v1:<path> references (they must keep resolving against the v1 tag,
# story ^oxname-y149), the eta-next branch and worktree, and "Eta v1".
# ppx_yojson_minimal carries no eta token and is never touched; neither do
# story IDs (ncore-*, napp-*, ^oxname-*), which contain no eta token.
#
# Usage: scripts/rename-eta-to-ox.sh [--skip PREFIX]... [--dry-run] [ROOT]
#   ROOT defaults to the toplevel of the checkout this script lives in.
set -euo pipefail

dry_run=0
root=""
skips=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip)
      skips+=("$2")
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    *)
      root="$1"
      shift
      ;;
  esac
done
root="${root:-$(git rev-parse --show-toplevel)}"
cd "$root"

is_skipped() {
  case "$1" in
    # Build trees at any depth, .git, node_modules, and the research bundles:
    # .scratch is evidence, like the archive, and some of it is read-only.
    .git/* | */.git/* | _build* | */_build* | node_modules/* | */node_modules/*) return 0 ;;
    .scratch/* | */.scratch/*) return 0 ;;
  esac
  local s
  for s in "${skips[@]+"${skips[@]}"}"; do
    case "$1" in "$s" | "$s"/*) return 0 ;; esac
  done
  return 1
}

# The rename rules, applied in one perl pass so that protected spans can be
# masked first and restored last. (sed has no per-match placeholders; the rules
# are the ones documented above.)
rename_stream() {
  perl -0pe '
    my @keep;
    s{(v1:[^\s),;`\]\}]*|eta-next|Eta v1)}{push(@keep, $1); "\x01" . $#keep . "\x02"}ge;
    s/\bEta_([A-Za-z0-9_]+)/Ox_$1/g;
    s/\bEta([A-Z_])/Ox$1/g;
    s/\bEta\b/Ox/g;
    s/\beta_([A-Za-z0-9_]+)/ox_$1/g;
    s/\beta([A-Z_])/ox$1/g;
    s/\beta\b/ox/g;
    s/\bETA([A-Z_])/OX$1/g;
    s/\bETA\b/OX/g;
    s/\x01(\d+)\x02/$keep[$1]/ge;
  '
}

rename_path() {
  perl -e '
    my $p = shift;
    my @parts = split(m{/}, $p, -1);
    for my $part (@parts) {
      $part =~ s/\bEta_([A-Za-z0-9_]+)/Ox_$1/g;
      $part =~ s/\bEta([A-Z_])/Ox$1/g;
      $part =~ s/\bEta\b/Ox/g;
      $part =~ s/\beta_([A-Za-z0-9_]+)/ox_$1/g;
      $part =~ s/\beta([A-Z_])/ox$1/g;
      $part =~ s/\beta\b/ox/g;
      $part =~ s/\bETA([A-Z_])/OX$1/g;
      $part =~ s/\bETA\b/OX/g;
    }
    my $new = join("/", @parts);
    $new =~ s{^docs/why-next\.md$}{docs/why-ox.md};
    print $new;
  ' -- "$1"
}

mapfile -d '' files < <(git ls-files -z)

changed=0
renamed=0
for f in "${files[@]}"; do
  is_skipped "$f" && continue
  [ -f "$f" ] || continue
  grep -Iq . "$f" || continue
  grep -qE '\b(Eta|eta|ETA)' "$f" || continue
  if [ "$dry_run" = 1 ]; then
    echo "would rewrite $f"
  else
    tmp="$(mktemp)"
    rename_stream <"$f" >"$tmp"
    if ! cmp -s "$f" "$tmp"; then
      cat "$tmp" >"$f"
      changed=$((changed + 1))
    fi
    rm -f "$tmp"
  fi
done

for f in "${files[@]}"; do
  is_skipped "$f" && continue
  new="$(rename_path "$f")"
  [ "$new" = "$f" ] && continue
  if [ "$dry_run" = 1 ]; then
    echo "would rename $f -> $new"
  else
    mkdir -p "$(dirname "$new")"
    git mv -f "$f" "$new"
    renamed=$((renamed + 1))
  fi
done

if [ "$dry_run" = 0 ]; then
  find . -path ./.git -prune -o -type d -empty -print -delete >/dev/null 2>&1 || true
  echo "rename-eta-to-ox: $changed file(s) rewritten, $renamed path(s) renamed"
  echo "remaining eta tokens (review these):"
  git grep -nE '\b(Eta|eta|ETA)' -- . | grep -v '^docs/issues/' || echo "  none"
fi
