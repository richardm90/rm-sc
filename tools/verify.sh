#!/QOpenSys/pkgs/bin/bash
#
# verify.sh - the full verification: every suite, every harness, the gate and
# the fixture pack, in one run, with a time against each stage.
#
# Runs ON the IBM i box, from the deploy directory. It compiles each test
# program and then runs it, so it needs nothing built beforehand EXCEPT the
# service program itself:
#
#     makei build && tools/verify.sh
#
# Running it without a build is the stale-object trap docs/testing-notes.md
# describes - the suites compile and pass against the PREVIOUS RMSC.SRVPGM, and
# report success for code that was never tested. Nothing here can detect that,
# because a stale service program is indistinguishable from a current one at
# run time. Build first.
#
# WHY EACH STAGE IS TIMED. The fixture pack is roughly ninety `sc` invocations,
# each starting a JVM, and it is the reason a full run takes closer to an hour
# than a minute. Whether it belongs in a routine verification at all is an open
# question, and it cannot be answered without a number against each stage - a
# total says a run is slow but not which part to move. Earlier logs carried an
# end mtime and no duration, so no comparison could be drawn from them.
#
# SELECTING STAGES. With no arguments every stage runs. Otherwise only the named
# ones do, in the order given here rather than the order typed:
#
#     tools/verify.sh                      everything
#     tools/verify.sh suites               the iRPGUnit suites alone
#     tools/verify.sh suites gate          a quick pass while iterating
#
# Stage names are the lower-case words below: suites, narration, api-silence,
# error-delivery, load-warning, colour, gate, fixture-pack.
#
# A PARTIAL RUN IS NOT A VERIFICATION. The stage list exists for the edit-run
# loop, not for deciding something is finished. Before a commit, run the lot.
#
# BASELINE. The gate needs it, and it is deliberately NOT defaulted here: it
# points at captured upstream output which names real services, so it lives
# outside this repository. The gate exits 2 with a clear message when it is
# unset, which is better than this script guessing at a path.
#
#     BASELINE=/path/to/captured tools/verify.sh
#
# Every path below is derived or overridable, so no developer's home directory
# is written into a published file. Same rule and same mechanism as
# fidelity-gate.sh.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"

# The libraries the suites need on the list, and where the copybooks come from.
# INCDIRS mirrors iproj.json's includePath; keep the two in step.
SRVLIB="${SRVLIB:-RMSC}"
TSTLIB="${TSTLIB:-RMSCT}"
LIBS="${LIBS:-RPGUNIT $SRVLIB $TSTLIB RMTOOLS}"
INCDIRS="${INCDIRS:-'QPROTOSRC' '/prj/rmtools'}"

SUITES="${SUITES:-SCYAML SCDEF SCDIRS SCCOLL SCQRY SCNET SCJOB SCOUT SCLAUNCH SCEXEC SCMAIN SCAPI SCLIFE}"

cd "$DEPLOY" || { echo "verify: cannot cd to $DEPLOY" >&2; exit 2; }

# Which stages to run. No arguments means all of them.
WANTED="$*"
want() {
  [ -z "$WANTED" ] && return 0
  case " $WANTED " in *" $1 "*) return 0;; *) return 1;; esac
}

# Reject a stage name that matches nothing, rather than running a subset the
# caller did not ask for and reporting it as a pass.
ALL="suites narration api-silence error-delivery load-warning colour gate fixture-pack"
for w in $WANTED; do
  case " $ALL " in
    *" $w "*) ;;
    *) echo "verify: unknown stage '$w'; choose from: $ALL" >&2; exit 2;;
  esac
done

RUN_START=$(date +%s)
STAGE_START=$RUN_START
echo "START $(date '+%Y-%m-%d %H:%M:%S')   deploy=$DEPLOY"
[ -n "$WANTED" ] && echo "STAGES $WANTED   (partial run - not a verification)"

# WHAT COUNTS AS A FAILED RUN. Every stage's exit status is captured and the
# script exits non-zero if any of them failed - "fail rather than skip" applies
# to the harness that runs the tests as much as to the tests. Without this a
# harness that fell over and one that passed produce the same result, and the
# only evidence either way is whatever happened to land in its last few lines.
#
# THE FIXTURE PACK IS ADVISORY, and deliberately so. It exits 1 on ANY
# difference, and six differences are currently expected and recorded - so
# treating its status as pass/fail would make every run red and the signal
# worthless. It becomes a pass/fail stage when it gains a list of expected
# differences to classify against, which is the outstanding Phase C item. Until
# then its result is printed and called out, and it does not decide the run.
failed_stages=""
advisory_note=""
note_failure() { failed_stages="$failed_stages $1"; }

# Elapsed since the previous stage boundary, as m:ss.
stage() {
  local now d
  now=$(date +%s)
  d=$(( now - STAGE_START ))
  printf "  -- %s took %d:%02d\n" "$1" $(( d / 60 )) $(( d % 60 ))
  STAGE_START=$now
}

# A harness is only run if it is present. Missing is reported loudly rather than
# skipped quietly: a verification that says nothing about a harness it could not
# find reads exactly like one where the harness passed.
harness() {
  local name=$1 script=$2 lines=$3 advisory=${4:-} rc=0
  want "$name" || return 0
  echo "########## ${name} ##########"
  if [ -x "$DEPLOY/$script" ]; then
    # PIPESTATUS[0], not $?: $? here is tail's status, which is 0 whatever the
    # harness did. Reading the wrong one is how a script comes to report
    # success for every run it ever makes.
    "$DEPLOY/$script" 2>&1 | tail -"$lines"
    rc=${PIPESTATUS[0]}
  else
    echo "MISSING: $script is not present or not executable - NOT RUN"
    rc=127
  fi
  if [ "$rc" -ne 0 ]; then
    if [ -n "$advisory" ]; then
      echo "  (exit $rc - advisory stage, does not fail the run; see the note at the end)"
      advisory_note="$advisory_note $name(rc=$rc)"
    else
      echo "  FAILED: $name exited $rc"
      note_failure "$name"
    fi
  fi
  stage "$name"
}

if want suites; then
  echo "########## suites ##########"
  liblist=""
  for l in $LIBS; do liblist="${liblist}liblist -a $l; "; done
  for s in $SUITES; do
    qsh -c "${liblist}
            system \"RUCRTRPG TSTPGM($TSTLIB/$s) SRCSTMF('qtestsrc/$s.TEST.RPGLE') TGTCCSID(*JOB) DBGVIEW(*SOURCE) RPGPPOPT(*LVL2) COPTION(*EVENTF) INCDIR($INCDIRS)\"" \
        >"/tmp/verify.c.$s" 2>&1
    crc=$?
    out=$(qsh -c "${liblist}
            system \"RUCALLTST TSTPGM($TSTLIB/$s) ORDER(*API) DETAIL(*BASIC) OUTPUT(*ALLWAYS) RCLRSC(*NO)\"" 2>&1)
    # Both codes are printed. A suite whose compile failed runs the PREVIOUS
    # program and reports its result - which is a pass for code that does not
    # compile. compile=0 is the half that says the other half means anything.
    summary=$(echo "$out" | grep -E "test cases, .* assertions" | tail -1)
    printf "%-10s compile=%s  %s\n" "$s" "$crc" "$summary"
    # Three ways a suite fails, and all three have been seen on this project:
    # the compile failed (and the PREVIOUS program then ran and reported ITS
    # result), the run produced no summary line at all, or the summary names a
    # failure or an error. An abend is an ERROR in iRPGUnit, not a failure, so
    # both words are tested.
    if [ "$crc" -ne 0 ]; then
      echo "           FAILED: $s did not compile - its result is from a STALE program"
      note_failure "suite:$s"
    elif [ -z "$summary" ]; then
      echo "           FAILED: $s produced no summary line - it did not run to completion"
      note_failure "suite:$s"
    elif ! echo "$summary" | grep -qE "0 failure, 0 error"; then
      note_failure "suite:$s"
    fi
  done
  stage suites
fi

harness narration       tools/narration-test.sh      3
harness api-silence     tools/api-silence-test.sh    6
harness error-delivery  tools/error-delivery-test.sh 3
harness load-warning    tools/load-warning-test.sh   4
harness colour          tools/colour-test.sh         3
harness gate            tools/fidelity-gate.sh       4
harness fixture-pack    tools/gate-fixtures-run.sh   6  advisory

TOTAL=$(( $(date +%s) - RUN_START ))
echo "END   $(date '+%Y-%m-%d %H:%M:%S')"
printf "TOTAL %d:%02d\n" $(( TOTAL / 60 )) $(( TOTAL % 60 ))

[ -n "$advisory_note" ] && echo "ADVISORY:$advisory_note - reported, not counted against the run"
if [ -n "$failed_stages" ]; then
  echo "VERDICT FAILED:$failed_stages"
else
  echo "VERDICT OK"
fi

# The sentinel. Without it a log that stops early and a log that finished look
# identical, and a partial log gets read as a complete run - which has happened
# here and produced a false report.
echo "VERIFY_DONE"

# After the sentinel, so a log is complete whichever way the run went.
[ -z "$failed_stages" ]
