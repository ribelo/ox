#!/bin/sh
# ^nwake-fz0j: keep both populations bounded by an OS timer, not an Eio timer.
set -eu
case "$1" in
  /*) exe=$1 ;;
  *) exe=./$1 ;;
esac
runs=${2:-50}
interval=${3:-50}
passed=0
timed_out=0
failed=0
i=1
while [ "$i" -le "$runs" ]; do
  status=0
  timeout --kill-after=1 5 env EIO_BACKEND=posix OX_POSIX_WAKEUP_MS="$interval" \
    "$exe" >stress.log 2>&1 || status=$?
  case "$status" in
    0) passed=$((passed + 1)) ;;
    124) timed_out=$((timed_out + 1)) ;;
    *) failed=$((failed + 1)); printf "run %s: exit %s\n" "$i" "$status" >&2 ;;
  esac
  i=$((i + 1))
done
printf "wakeup_ms=%s: %s/%s passed, %s timed out, %s other failures (1000 children/run, 5 s/run)\n" \
  "$interval" "$passed" "$runs" "$timed_out" "$failed"
# A disabled baseline is evidence, not a correctness gate; the enabled run is.
[ "$failed" -eq 0 ] && { [ "$interval" -eq 0 ] || [ "$timed_out" -eq 0 ]; }
