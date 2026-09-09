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
WORK="${WORK:-/tmp/fidelity-gate.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT.
#
# This script keeps its work directory deliberately - it prints the path so a
# failure can be inspected afterwards - and nothing ever removed an old one.
# Thirty-six of them had accumulated across /tmp before anyone looked, and the
# rule they break is already written down in the plan: a trap does not run if
# the process is killed, so the next run must assume the last one left debris.
#
# The two most recent are kept, so "inspect the artefacts" still works for the
# run that just failed and the one before it. Only this script's own
# directories are touched, by name, so a sibling harness's are left alone.
# NEVER DELETE A DIRECTORY SOMETHING IS STILL USING. The name carries the PID
# that made it - WORK defaults to <prefix>.$$ - so ownership needs no
# bookkeeping, only `kill -0` on the suffix.
#
# Without this, two runs at once leave three directories and the oldest still
# RUNNING one is removed underneath itself. It then fails on missing capture
# files, and it does not fail saying its files vanished - it fails looking like
# a fidelity regression. A harness that reports a defect in the thing under
# test when the fault is its own cleanup is worse than one that leaks debris.
#
# The two failure modes are not symmetrical, which is what decides the rule. A
# recycled PID means skipping a delete that could have been made: debris kept.
# Getting it wrong the other way destroys a run in flight. So anything that
# might be alive is left alone, and so is any name whose suffix is not a plain
# number - an overridden WORK= belongs to whoever set it, and this cannot know
# who that is.
#
# The same block appears in every script in tools/ that keeps its work directory
# and names it by PID. THIS SCRIPT IS HALF OF WHY THAT IS PHRASED AS A PROPERTY.
# It carries the block and it is NOT a harness - verify.sh runs it as the `gate`
# stage - so "all five harnesses", which this line used to say, counted it as one
# and was wrong here first. It was wrong at the other end too: load-warning-test.sh
# is a harness and has never carried the block, taking a mktemp directory and a
# trap instead.
#
# Deliberately duplicated rather than shared: each is deployed and run
# standalone, and a shared file would be a dependency that costs more than the
# repetition does. Change one, change all of them.
ls -dt /tmp/fidelity-gate.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in
    ''|*[!0-9]*) continue ;;
  esac
  # `kill -0` fails two ways and they mean opposite things: ESRCH is "no such
  # process", EPERM is "alive, but not yours". Testing only the exit status
  # treats another user's LIVE run as dead and deletes its work directory -
  # the exact failure this block exists to prevent, on a shared box.
  if kill_err=$(kill -0 "$owner" 2>&1); then
    continue
  fi
  case "$kill_err" in
    *ermitted*|*EPERM*|*ermission*) continue ;;
  esac
  rm -rf "$stale" 2>/dev/null
done

# BASELINE has no default, deliberately. The obvious one - the tracked
# fixtures/ directory - holds same-layout equivalents with INVENTED service
# names, describing a different machine. A gate defaulting there would diff
# this system's output against another system's and report a mismatch that
# reads like a formatting defect. The real captures are not published, because
# they record a live system's services; keep them outside the repository and
# name the directory here.
#
#   BASELINE=$HOME/rm-sc-baselines ssh $HOST "$DEPLOY/tools/fidelity-gate.sh"
#
if [ -z "$BASELINE" ]; then
  cat >&2 <<'MSG'
BASELINE is not set.

Set it to the directory holding the captured Java output - baseline-check.txt,
baseline-list.txt and baseline-groups.txt. Those captures are not in this
repository: they name a live system's services.

The tracked fixtures/ directory is NOT a substitute. It holds invented names
describing a different machine, and diffing against it fails in a way that
looks like a formatting defect rather than a wrong baseline.
MSG
  exit 2
fi

export QIBM_MULTI_THREADED=Y

# Operations compared live. Read-only, safe to run against real services.
#
# check is here as well as in stage 1, and the two are not the same test. Stage
# 1 diffs a BARE check - every service, through SCEXEC_check_all - against a
# captured baseline. Naming a single service takes a different path entirely,
# and nothing compared it until this line existed: a trailing blank line that
# upstream prints and RMSC did not went unnoticed because no test ran
# 'check <service>' against upstream at all.
DIFF_OPS="check info file loginfo jobinfo scrunattrs perfinfo"

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
#   scrunattrs  "SCOMMANDER_* vars from the running job", which is what it emits
#   perfinfo    TWO differences, and BOTH are now settled - it sat in
#               UNDECIDED until 9 September 2026 because only one was.
#
#               Three lines per job: the thread-resources-affinity pair and
#               the resources affinity group. Upstream scrapes DSPJOB
#               OPTION(*RUNA) for them; RMSC reads QUSRJOBI, which does not
#               carry them (IBM's reference for the API does not contain the
#               word "affinity"). Richard's decision, 8 September 2026.
#
#               The order of the job blocks. Upstream's is Java HashSet
#               iteration order over the job-name strings - measured, by
#               predicting its output exactly on three job sets from
#               String.hashCode and the HashMap bucket layout. It is a
#               function of the job numbers, so it reshuffles on every
#               restart and there is no order there to match. RMSC sorts
#               ascending by job number instead. Same answer as the conflict
#               block members in 7791266, for the same reason.
#
#               docs/parity.md carries both, with the evidence.
#
#               STILL per-operation, not per-line: this list accepts any
#               perfinfo difference, not only those two. A THIRD would pass
#               unnoticed. That is the open granularity item on the fixture
#               pack, and this is one of the entries it should cover.
INTENTIONAL="file scrunattrs perfinfo"

# Divergences the plan does NOT settle either way. These need a decision before
# step 8 can be called complete. Byte-exactness is required for check only, so
# none of these is a correctness problem - but none is a documented choice.
#
#   info        plan says only "Formatted definition dump"
#   jobinfo     plan says only "Active job names"
#   loginfo     plan says only "Log paths, sizes, spooled files"
UNDECIDED="info jobinfo loginfo"

mkdir -p "$WORK"
pass=0; bydesign=0; undecided_n=0; unexpected=0

# Replace values that legitimately differ between two runs seconds apart. Job
# numbers, wall-clock timestamps, and the storage/CPU/IO counters that both
# implementations sample live. Everything else, including whitespace, is compared
# as-is.
# Masks the fields that move between two invocations seconds apart, so a live
# differential compares what is stable rather than reporting noise forever.
#
# WHAT IS DELIBERATELY NOT MASKED, and this matters more than what is: the run
# attributes (RUNPTY, TIMESLICE, PURGE, DFTWAIT, and the three limits),
# Current User, Job active since, Java Heap Maximum Size and Java Shared Class
# Size. Those are the fields that would catch RMSC reading the wrong column -
# notably the maximum temporary storage, which exists in the source in both
# kilobytes and megabytes and reads plausibly either way. Masking them to
# quieten the output would leave this comparing labels and nothing else.
#
# Numeric masks accept commas because the memory figures are separated.
normalise() {
  sed -E \
    -e 's#[0-9]{6}/#NNNNNN/#g' \
    -e 's#/home/[A-Za-z0-9_.-]+/#/home/USER/#g' \
    -e 's#[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}#TIMESTAMP#g' \
    -e 's#^([[:space:]]*(CPU time used|Temporary storage used|Peak temporary storage used|Threads|Disk I/O operations during sampling time|Total Disk I/O operations|->Sampling time \(s\)|CPU Usage \(%\)|Java GC Cycle Number|Java GC Total Time \(ms\)|Java Heap In Use \(Kb\)|Java Heap Current Size \(MB\)|Java JIT Memory \(KB\)|Malloc.ed Memory estimate \(Kb\)|started|threads|temporary storage \(MB\)|CPU %|disk I/O)[^0-9-]*)[-0-9.,]+#\1VALUE#' \
    -e 's#^([[:space:]]*(Function|Job Status): ).*#\1VALUE#'
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
