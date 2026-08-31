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

# Verification step 8 requires the sweep to include "two system-group services".
# These two are chosen to reach the check_alive forms the three default services
# never exercise: system_admin1 is the SBS/JOB form (QHTTPSVR/ADMIN1), which
# stays on SQL because JOBL0100 cannot filter by subsystem, and system_telnet is
# port-only, which reaches SCNET with no job lookup at all. The PGM- form has no
# reachable service - its only definition is filtered out by only_if_executable.
STEP8_SYSTEM="${STEP8_SYSTEM:-system_admin1 system_telnet}"

# Divergences the PLAN sanctions. These are not defects and are not to be burned
# down; the plan specifies the behaviour RMSC has:
#   file        "Raw YAML passthrough" - and Risks relies on it: "scr file <svc>
#               prints the raw file so the source of truth stays inspectable"
#   perfinfo    "Improved - drops upstream's optional Python 3 + ibm_db
#               dependency", so a narrower output is the point
#   scrunattrs  "SCOMMANDER_* vars from the running job", which is what it emits
INTENTIONAL="file perfinfo scrunattrs"

# Divergences the plan does NOT settle either way. These need a decision before
# step 8 can be called complete - the plan describes them only as "Formatted
# definition dump", "Active job names" and "Log paths, sizes, spooled files",
# with no fidelity requirement stated. Byte-exactness is required for check only.
UNDECIDED="info jobinfo loginfo"

mkdir -p "$WORK"
pass=0; bydesign=0; undecided_n=0; unexpected=0

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
    unexpected=$((unexpected+1)); continue
  fi
  "$SCR" "$op" > "$WORK/$op.actual" 2>&1
  if cmp -s "$b" "$WORK/$op.actual"; then
    printf '  %-12s PASS\n' "$op"; pass=$((pass+1))
  else
    printf '  %-12s FAIL  (diff in %s)\n' "$op" "$WORK/$op.diff"
    diff "$b" "$WORK/$op.actual" > "$WORK/$op.diff"
    unexpected=$((unexpected+1))
  fi
done

# The colour decision is made by the wrapper, not by RMSC. If it ever leaks an
# escape into a non-terminal stream, every column-parsing consumer breaks at once.
esc=$("$SCR" check | grep -c $'\033' )
if [ "$esc" -eq 0 ]; then
  printf '  %-12s PASS\n' "no-colour"; pass=$((pass+1))
else
  printf '  %-12s FAIL  (%s lines carry ANSI escapes)\n' "no-colour" "$esc"
  unexpected=$((unexpected+1))
fi

services="$("$SCR" list 2>/dev/null | awk 'NF{print $1}') $STEP8_SYSTEM"
n_svc=$(echo $services | wc -w)
echo
echo "== stage 2: live differential (verification step 8)"
echo "   $n_svc services x $(echo $DIFF_OPS | wc -w) operations"
echo
printf '  %-12s %-11s %-8s %s\n' operation verdict differs note
printf '  %-12s %-11s %-8s %s\n' ------------ ----------- -------- ----

for op in $DIFF_OPS; do
  op_fail=0; failed_on=""
  for svc in $services; do
    "$SC"  "$op" "$svc" 2>&1 | normalise > "$WORK/$op.$svc.java"
    "$SCR" "$op" "$svc" 2>&1 | normalise > "$WORK/$op.$svc.rmsc"
    cmp -s "$WORK/$op.$svc.java" "$WORK/$op.$svc.rmsc" || {
      op_fail=$((op_fail+1)); failed_on="$failed_on $svc"
      diff "$WORK/$op.$svc.java" "$WORK/$op.$svc.rmsc" > "$WORK/$op.$svc.diff"
    }
  done

  klass=none
  case " $INTENTIONAL " in *" $op "*) klass=intentional ;; esac
  case " $UNDECIDED "   in *" $op "*) klass=undecided ;; esac

  ratio="$op_fail/$n_svc"
  if [ "$op_fail" -eq 0 ]; then
    case "$klass" in
      none)  printf '  %-12s %-11s %-8s %s\n' "$op" "PASS" "$ratio" "matches upstream"
             pass=$((pass+1)) ;;
      *)     printf '  %-12s %-11s %-8s %s\n' "$op" "RECLASSIFY" "$ratio" \
                    "now matches - remove from $klass list"
             unexpected=$((unexpected+1)) ;;
    esac
  else
    case "$klass" in
      intentional) printf '  %-12s %-11s %-8s %s\n' "$op" "by design" "$ratio" \
                          "plan specifies this"
                   bydesign=$((bydesign+1)) ;;
      undecided)   printf '  %-12s %-11s %-8s %s\n' "$op" "undecided" "$ratio" \
                          "needs a decision"
                   undecided_n=$((undecided_n+1)) ;;
      none)        printf '  %-12s %-11s %-8s %s\n' "$op" "REGRESSION" "$ratio" \
                          "differs on:$failed_on"
                   unexpected=$((unexpected+1)) ;;
    esac
  fi
done

echo
echo "stage 1 pass=$pass   by design=$bydesign   undecided=$undecided_n   unexpected=$unexpected"
echo "artefacts: $WORK"
if [ "$unexpected" -ne 0 ]; then
  echo "GATE FAILED: something differs that is neither sanctioned nor recorded"
  exit 1
fi
if [ "$undecided_n" -ne 0 ]; then
  echo "GATE OK, step 8 INCOMPLETE: $undecided_n operation(s) still undecided"
  exit 0
fi
echo "GATE OK: step 8 complete - every difference is intentional and listed"
