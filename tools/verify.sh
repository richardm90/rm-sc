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
# error-delivery, load-warning, loginfo, jobinfo, adhoc-name, sampletime,
# colour, gate, fixture-pack.
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
ALL="suites narration api-silence error-delivery load-warning loginfo jobinfo adhoc-name sampletime colour gate fixture-pack"
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
# THE FIXTURE PACK IS A PASS/FAIL STAGE as of 6 September. It used to be
# advisory because it exited 1 on ANY difference, and six are expected - so its
# status was permanently red and therefore worthless.
#
# It now classifies each difference the way the operation gate does, and exits
# on `unexpected` rather than on `differ`: a difference that is not on its list
# is a REGRESSION, and a listed difference that has stopped happening is a
# RECLASSIFY. Both fail. So a green pack now means something specific - every
# difference is one we know about, and every difference we know about is still
# there - and that is worth deciding the run on.
# NO STAGE IS ADVISORY TODAY. The mechanism below is kept because the case it
# exists for recurs - a stage meaningful to run but not yet able to decide a
# run, usually because it is blocked on something outside this repository -
# and because rediscovering it costs more than the ten lines. The fixture
# pack was the last user and stopped being one when it learned to classify.
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
# STAGES A SERVICE IN THE USER'S REAL SERVICES DIRECTORY, because that is the
# only place BOTH implementations look - SC_SERVICES_DIR is RMSC's alone. It
# invents both names from its own PID, refuses to overwrite a name it did not
# write, and removes them in a trap; a run killed between those points leaves
# debris the next run reaps. About 1m20s, most of it JVM start-up: eight `sc`
# invocations and seven `scr` ones.
#
# 4 lines is the summary block and nothing else, and that is deliberate rather
# than mean: its cases fail in stage 1 with the upstream reference table and the
# pinned row printed AFTER them, so no tail short enough to belong in this log
# reaches the evidence. The counts decide the run; a failure is diagnosed by
# running tools/loginfo-test.sh directly.
harness loginfo         tools/loginfo-test.sh        4
# STAGES NOTHING IN A SHARED DIRECTORY, unlike the stage above it. Its three
# invented definitions live in its own work directory and are shown to both
# implementations through -Dservices.dir and SC_SERVICES_DIR, because nothing
# here is ever started - the RUNNING fixture is running because the harness
# holds the two ports its criteria name. So a run killed mid-way leaves no
# definition for the gate to trip over; what it can leave is two listeners, and
# the next run's port check fails loudly on exactly that. About 1m, nine `sc`
# and `scr` invocations.
#
# 6 lines, not 4: the summary block is three, and the two above it are stage 3's
# pinned job-order row - the one row whose meaning is that something nobody
# asked for has changed. A failure is diagnosed by running the harness directly.
harness jobinfo         tools/jobinfo-test.sh        6
# STAGES NOTHING AT ALL for the six stages that matter, and that is the point of
# it: an ad-hoc service is named on the command line and has no definition, so
# there is no fixture to own. It reads port 22, which is listening because this
# run arrived over SSH, and job names that do not exist. Its one staging stage
# writes into its own work directory and shows it to RMSC through
# SC_SERVICES_DIR, never to $HOME/.sc/services, so a killed run leaves nothing
# anywhere. About 1m, and roughly a dozen `sc` invocations are all of it.
#
# 8 lines, not 4: three stages end in a row that can carry several detail lines
# - the pinned PGM- row, a REFDRIFT quoting upstream, and stage 5's three-way
# row comparison - and the summary counts must not be truncated away behind
# them. A failure is diagnosed by running the harness directly.
harness adhoc-name      tools/adhoc-name-test.sh     8
# NEEDS A RUNNING SERVICE, and fails loudly rather than skipping when there is
# none - see the fixture stage in the harness for why that is the right way
# round. It is also the slowest non-pack stage at about 4m on a two-job
# service, because each case spends (jobs x sampletime) seconds sampling.
harness sampletime      tools/sampletime-test.sh     6
harness colour          tools/colour-test.sh         3
harness gate            tools/fidelity-gate.sh       4
# 12, not 6. The pack's ordering note is a nine-line heredoc that prints only
# when order_only > 0, and it pushed the summary counts out of a six-line tail -
# so the stage that now decides the run could have its numbers truncated away.
harness fixture-pack    tools/gate-fixtures-run.sh   12

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
