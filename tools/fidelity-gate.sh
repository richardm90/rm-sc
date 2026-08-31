#!/QOpenSys/pkgs/bin/bash
#
# fidelity-gate.sh - compare RMSC output against upstream sc, operation by operation.
#
# Runs ON the IBM i box, because a per-command ssh round trip makes a full sweep
# take minutes rather than seconds.
#
# Two stages, deliberately different:
#
#   Byte-exact    check, list and groups are diffed against the CAPTURED Java
#                 fixtures. These are the acceptance criterion, they contain no
#                 volatile data, and they must match to the byte.
#
#   Differential  Every other read-only operation is run through BOTH
#                 implementations right now, on this system, and the two outputs
#                 compared. Nothing is captured, because these operations embed
#                 job numbers, timestamps and storage figures that change between
#                 any two runs - a stored fixture would rot within minutes.
#
# Only VALUES known to be volatile are normalised. Whitespace is left alone: a
# stray blank line is exactly the class of difference this exists to catch, since
# a consumer parsing by column drops any row that does not yield three fields.
#
# start/stop/kill/restart are NOT gated here. They change system state, and a
# suite that takes services down on whatever machine it runs on is not worth
# having. SCLIFE.TEST covers the lifecycle against a service it creates itself.
#
# Service names are discovered from `scr list`, never hardcoded - this file is
# published and must not name a client's services.

set -o pipefail

# This script lives at $DEPLOY/tools/, so it can find the deploy directory from
# its own location. That assumes nothing about where anyone deploys, and keeps a
# developer's home directory out of a published file. Override any of these to
# compare a build somewhere else.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
BASELINE="${BASELINE:-$DEPLOY/fixtures}"
WORK="${WORK:-/tmp/fidelity-gate.$$}"

export QIBM_MULTI_THREADED=Y

# Operations compared live. Read-only, safe to run against real services.
DIFF_OPS="info file loginfo jobinfo scrunattrs perfinfo"

# Operations known to diverge as of 31 August 2026. The gate passes when reality
# matches this list, and fails when it does not - so a fix that is not recorded
# here is reported just as loudly as a regression. Burn entries down, do not add.
KNOWN_DIVERGENT="info file loginfo jobinfo scrunattrs perfinfo"

mkdir -p "$WORK"
pass=0; fail=0; unexpected=0

# Replace values that legitimately differ between two runs seconds apart. Job
# numbers, wall-clock timestamps, and the storage/CPU/IO counters that both
# implementations sample live. Everything else, including whitespace, is compared
# as-is.
normalise() {
  sed -E \
    -e 's#[0-9]{6}/#NNNNNN/#g' \
    -e 's#/home/[A-Za-z0-9_.-]+/#/home/USER/#g' \
    -e 's#[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}#TIMESTAMP#g' \
    -e 's#^([[:space:]]*(CPU time used|Temporary storage used|Peak temporary storage used|Threads|Disk I/O operations during sampling time|Total Disk I/O operations|->Sampling time \(s\)|CPU Usage \(%\)|started|threads|temporary storage \(MB\)|CPU %|disk I/O)[^0-9-]*)[-0-9.]+#\1VALUE#'
}

echo "== stage 1: byte-exact against captured Java fixtures"
for op in check list groups; do
  b="$BASELINE/baseline-$op.txt"
  if [ ! -f "$b" ]; then
    # Not a skip. A gate pointed at the wrong BASELINE would otherwise pass
    # while comparing nothing at all, which is worse than failing outright.
    printf '  %-12s FAIL  (no fixture at %s)\n' "$op" "$b"
    fail=$((fail+1)); unexpected=$((unexpected+1)); continue
  fi
  "$SCR" "$op" > "$WORK/$op.actual" 2>&1
  if cmp -s "$b" "$WORK/$op.actual"; then
    printf '  %-12s PASS\n' "$op"; pass=$((pass+1))
  else
    printf '  %-12s FAIL  (diff in %s)\n' "$op" "$WORK/$op.diff"
    diff "$b" "$WORK/$op.actual" > "$WORK/$op.diff"
    fail=$((fail+1)); unexpected=$((unexpected+1))
  fi
done

# The colour decision is made by the wrapper, not by RMSC. If it ever leaks an
# escape into a non-terminal stream, every column-parsing consumer breaks at once.
esc=$("$SCR" check | grep -c $'\033' )
if [ "$esc" -eq 0 ]; then
  printf '  %-12s PASS\n' "no-colour"; pass=$((pass+1))
else
  printf '  %-12s FAIL  (%s lines carry ANSI escapes)\n' "no-colour" "$esc"
  fail=$((fail+1)); unexpected=$((unexpected+1))
fi

services=$("$SCR" list 2>/dev/null | awk 'NF{print $1}')
n_svc=$(echo "$services" | grep -c .)
echo
echo "== stage 2: live differential, $n_svc service(s) x $(echo $DIFF_OPS | wc -w) operations"

for op in $DIFF_OPS; do
  op_fail=0
  for svc in $services; do
    "$SC"  "$op" "$svc" 2>&1 | normalise > "$WORK/$op.$svc.java"
    "$SCR" "$op" "$svc" 2>&1 | normalise > "$WORK/$op.$svc.rmsc"
    cmp -s "$WORK/$op.$svc.java" "$WORK/$op.$svc.rmsc" || {
      op_fail=$((op_fail+1))
      diff "$WORK/$op.$svc.java" "$WORK/$op.$svc.rmsc" > "$WORK/$op.$svc.diff"
    }
  done

  expected=no
  case " $KNOWN_DIVERGENT " in *" $op "*) expected=yes ;; esac

  if [ "$op_fail" -eq 0 ] && [ "$expected" = no ]; then
    printf '  %-12s PASS\n' "$op"; pass=$((pass+1))
  elif [ "$op_fail" -eq 0 ] && [ "$expected" = yes ]; then
    printf '  %-12s FIXED (matches on all %s - remove from KNOWN_DIVERGENT)\n' "$op" "$n_svc"
    unexpected=$((unexpected+1))
  elif [ "$expected" = yes ]; then
    printf '  %-12s known  (%s/%s differ)\n' "$op" "$op_fail" "$n_svc"; fail=$((fail+1))
  else
    printf '  %-12s FAIL  (%s/%s differ - REGRESSION, diffs in %s)\n' "$op" "$op_fail" "$n_svc" "$WORK"
    fail=$((fail+1)); unexpected=$((unexpected+1))
  fi
done

echo
echo "pass=$pass  known-divergent=$fail  unexpected=$unexpected"
echo "artefacts: $WORK"
[ "$unexpected" -eq 0 ] || { echo "GATE FAILED: state differs from what is recorded"; exit 1; }
echo "GATE OK: matches recorded state"
