#!/QOpenSys/pkgs/bin/bash
#
# sampletime-test.sh - whether `--sampletime=` is CONVERTED correctly, and
# whether converting it can still take the program down.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses,
# and modelled on tools/error-delivery-test.sh and tools/load-warning-test.sh.
#
# WHY IT IS A SHELL SCRIPT AND NOT A SUITE
#
# The value parser is a LOCAL procedure inside the command-line module, so no
# iRPGUnit suite can call it. SCMAIN.TEST reaches the parse step that STORES the
# raw text and stops there - the conversion from text to a sampling window
# happens later and returns nothing a suite could read. What it produces instead
# is three things that only exist outside the ILE job: an elapsed WINDOW, a
# WARNING on a stream, and an EXIT STATUS. That is a shell's question.
#
# WHY IT IS A NEW FILE RATHER THAN CASES ADDED TO AN EXISTING HARNESS
#
#   error-delivery-test.sh  asks which STREAM a failure lands on, how many
#                           copies of it there are, and what the exit status
#                           says about the KIND of failure. Its own closing
#                           note lists timing as something it cannot assert,
#                           because it captures redirected streams and throws
#                           the clock away. Half the subject here IS the clock.
#
#   load-warning-test.sh    asks what sc says while READING DEFINITIONS, before
#                           any operation has run. It stages YAML through
#                           SC_SERVICES_DIR and touches nothing live. This needs
#                           a running, multi-job service and an operation that
#                           samples it.
#
#   narration-test.sh       start/stop narration.
#
# It is also the only harness here whose cases COST SECONDS BY DESIGN - a case
# spends (jobs x sampletime) in the sampling loop - so keeping it separate keeps
# that cost out of harnesses that are currently fast. See THE COST OF A RUN.
#
# WHY IT EXISTS
#
# The value parser abended three times on the day it was written, each time on
# a value a user could type, and each one was found by hand rather than by a
# test:
#
#   MCH1210   --sampletime=9999999999   guard sized against a 10-digit
#                                       receiver, value bigger than it
#   RNX0103   --sampletime=9999999999   guard re-sized, still counting
#                                       CHARACTERS rather than the receiver's
#                                       integer digits
#   RNX0100   --sampletime=             a substring taken past the end of the
#                                       string
#
# Three fixes, no tests, and nothing to stop the next person reintroducing any
# of them.
#
# A FOURTH instance of the same family was found by WRITING this file, and a
# FIFTH defect was found by RUNNING it against the fix for the fourth:
#
#   RNX0100    --sampletime=2.        the empty FRACTION, reaching %SUBST past
#                                     the end the same way the empty argument
#                                     did. Fixed 8 September 2026; held by the
#                                     two trailing-dot cases in stage 1.
#
#   no escape  the option ABSENT      the default stopped being one second and
#                                     became ZERO, when the conversion moved
#                                     into the argument-parse loop. Held by
#                                     no-argument in stage 0.
#
# The second is the one worth remembering, and it is why no-argument sits in the
# FIXTURE stage rather than among the others. It broke no value anybody typed -
# every explicit value, valid or invalid, still behaved exactly as measured - so
# nothing that exercised the PARSER could see it. What moved was what happens
# when there is nothing to parse. And because every range in stage 1 is stated
# relative to a one-second default, a silent change to that default does not
# just go unnoticed: it quietly redefines what the rest of the file is
# measuring.
#
# WHAT EVERY CASE ASSERTS, WHATEVER ELSE IT ASSERTS
#
# NO ABEND. `CEE9901`, `RNX....` or `MCH....` on either stream, or exit 255, is
# a failure of the case whatever else it did. That check runs first and its
# message says so, so a crash reports as a crash rather than as a wording or a
# range difference twenty lines further down.
#
# THE RIVAL EVERY WINDOW CASE HAS TO RULE OUT
#
# A parser that IGNORED the argument entirely and always sampled for one second
# passes every assertion that only looks at the exit status, and it passes an
# assertion that only asks whether a report was produced. So each case names a
# RANGE for the window, and every range deliberately excludes 1.0. A case whose
# range contained the default would be watching the command not crash.
#
# The window is measured TWO INDEPENDENT WAYS, because the obvious one can be
# fooled:
#
#   (a) the `->Sampling time (s):` field, per job, out of the report. This is
#       the value the implementation reports it achieved.
#
#   (b) the WALL CLOCK of the run, compared against the wall clock of the
#       default run made in the fixture stage. If `->Sampling time` were echoed
#       back from the argument rather than measured, (a) would agree with a
#       parser that stored the number and never used it; (b) would not. The
#       comparison is between two runs rather than against an absolute, so JVM
#       and job start-up cancel instead of having to be estimated.
#
# BASIS OF EACH ASSERTION - read this before believing a failure
#
#   measured   taken from a side-by-side run against the installed sc 1.7.1 on
#              8 September 2026, and RE-TAKEN in stage 3 on every run, so the
#              reference cannot go stale underneath the expectations.
#
#   inferred   follows from the contract rather than from anything observed
#              upstream. Weigh a failure accordingly.
#
#   pinned     a place where the two implementations DELIBERATELY DISAGREE and
#              RMSC keeps its own behaviour. Pinned so a later change to it is
#              visible rather than silent. A failure here may be the intended
#              fix arriving, in which case this script and docs/parity.md both
#              need updating together.
#
# THE TWO SANCTIONED DIVERGENCES, and the reasoning, which is the coordinator's:
#
#   --sampletime=-1            upstream accepts the number and then its own
#                              gather FAILS per job, printing "Unable to
#                              retrieve performance data for job ..." on stderr
#                              and dropping the whole sampled block from the
#                              report. Exit 0.
#                              RMSC clamps the window to 0, says nothing, and
#                              still produces a full report.
#
#   --sampletime=9999999999    upstream: the same failure.
#                              RMSC: the WARNING, and a fall back to one second.
#
# Reproducing a crash faithfully is not parity worth having. RMSC produces a
# report where upstream produces error text, and that is the better answer even
# though it is not the same answer. Both are pinned so that a change to either
# is visible.
#
# THE COST OF A RUN, and a hazard for whoever adds a case
#
# Measured at 4m00s on a two-job service: twenty `scr` runs and eleven `sc` runs,
# and a case spends (jobs x sampletime) seconds inside the sampling loop on top
# of start-up. It scales with the fixture's job count, so a busier service costs
# more. Every window here is under three seconds for that reason.
#
# THERE IS NO UPPER SANITY BOUND ON THE VALUE. Measured: `--sampletime=86400`
# is accepted and samples for a day PER JOB. The only thing that rejects a large
# value is the width guard, and 100, 3600 and 86400 are all inside it. So a case
# added here with a large value does not fail - it hangs, and it hangs a
# verification run rather than this script alone. Keep them small.
#
# NO SERVICE NAME FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The repository is
# public. The fixture service is DISCOVERED from `scr check` at run time, the
# way tools/d2-probe.sh and tools/error-delivery-test.sh do it, and a run that
# cannot find one FAILS rather than capturing an empty result that would read
# like a pass.
#
# Stdout and stderr are captured to SEPARATE files throughout. Nothing here uses
# `2>&1`: the warning is a stderr assertion and the report is a stdout one, and
# a merged capture would let either satisfy the other.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-/tmp/rmsc-sampletime.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT.
#
# The same block appears in every script in tools/ that keeps its work directory
# and names it by PID. That is the membership rule.
#
# IT IS NOT "EVERY HARNESS", and this file had that wrong first. Every copy of
# this block used to say "all five harnesses" and CLAUDE.md's verify.sh
# paragraph used to say "the five harnesses", and THEY MEANT DIFFERENT FIVES:
# the block lives in narration, api-silence, error-delivery, colour and
# fidelity-gate, while CLAUDE.md was counting verify.sh stages - narration,
# api-silence, error-delivery, load-warning and colour. load-warning-test.sh has
# no copy of this block at all (it uses mktemp and a trap) and fidelity-gate.sh
# is not a harness. The two agreed on the number and never on the membership, so
# correcting the digit to six would have preserved the fault and sent the next
# reader hunting for a copy in load-warning-test.sh that has never existed. Both
# the count and the word "harness" have been dropped everywhere in favour of the
# property above.
#
# Deliberately duplicated rather than shared: each is deployed and run
# standalone, and a shared file would be a dependency that costs more than the
# repetition does. Change one, change all of them.
#
# NEVER DELETE A DIRECTORY SOMETHING IS STILL USING. The name carries the PID
# that made it - WORK defaults to <prefix>.$$ - so ownership needs no
# bookkeeping, only `kill -0` on the suffix. The two most recent are kept so
# "inspect the artefacts" still works for the run that just failed and the one
# before it.
#
# The two failure modes are not symmetrical, and that decides the rule. A
# recycled PID means skipping a delete that could have been made: debris kept.
# Getting it wrong the other way destroys a run in flight. So anything that
# might be alive is left alone, and so is any name whose suffix is not a plain
# number - an overridden WORK= belongs to whoever set it.
ls -dt /tmp/rmsc-sampletime.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in
    ''|*[!0-9]*) continue ;;
  esac
  # `kill -0` fails two ways and they mean opposite things: ESRCH is "no such
  # process", EPERM is "alive, but not yours". Testing only the exit status
  # treats another user's LIVE run as dead and deletes its work directory - the
  # exact failure this block exists to prevent, on a shared box.
  if kill_err=$(kill -0 "$owner" 2>&1); then
    continue
  fi
  case "$kill_err" in
    *ermitted*|*EPERM*|*ermission*) continue ;;
  esac
  rm -rf "$stale" 2>/dev/null
done

# Without this the PASE side of both implementations behaves differently and
# neither the windows nor the streams are comparable.
export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud. A run that skipped a case because
# a fixture was missing would report success while testing nothing.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory - it drives" \
  "the wrapper, and the wrapper calls an ILE program. Set SCR=<path> or" \
  "DEPLOY=<deploy dir> if the build lives somewhere else."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Stage 3 re-takes the upstream reference that stage 1's 'measured' cases are" \
  "written against, and stage 2's two divergences are only meaningful beside" \
  "the behaviour they diverge FROM. Running without it would leave both" \
  "unanchored. Set SC=<path> if it is installed elsewhere."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"
cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$WORK"; }
# INTERRUPT HANDLING. `trap cleanup EXIT INT TERM` looks right and is not.
# Bash runs the handler on the signal and then RESUMES the script, so the
# remaining cases run against fixtures cleanup has just removed, cleanup fires
# a second time on EXIT, and the script finishes with STATUS 0 - an
# interrupted harness reporting SUCCESS to verify.sh, for stages that never
# ran. Measured 9 September 2026, both shapes side by side:
#
#   trap cleanup EXIT INT TERM   -> cleanup, case 2, cleanup, exit 0
#   the shape below              -> cleanup, exit 130
#
# Disarming EXIT inside the handler is what stops the second cleanup; exiting
# is what stops the resumed run. docs/testing-notes.md carries the account.
on_signal() {
  trap - EXIT
  cleanup
  exit 130
}
trap cleanup EXIT
trap on_signal INT TERM

# SUB-SECOND WALL CLOCK IS REQUIRED, not optional.
#
# Measure (b) compares two runs that differ by about three seconds, against a
# threshold of two. Whole-second resolution would leave a one-second margin on
# a three-second signal, and a `date` that does not understand %N prints the
# letter N rather than failing - so the arithmetic would silently start
# operating on a string. Prove it once, here, rather than discovering it in a
# range comparison.
now() { date +%s.%N; }
probe_clock=$(now)
case "$probe_clock" in
  *N*|'') setup_fail \
    "date +%s.%N does not produce a sub-second timestamp here (got '$probe_clock')." \
    "" \
    "The wall-clock measure needs it. Without sub-second resolution the" \
    "elapsed comparison would be made against a threshold it cannot resolve," \
    "and would pass or fail on rounding." ;;
esac

# Discovered, never hardcoded: this file is published and must not name a
# service from this machine. The service has to be RUNNING - perfinfo against a
# stopped service prints an eight-line NOT RUNNING form with no sampled block at
# all, so every window assertion below would have nothing to read and the run
# would be vacuous. The fixture stage proves the block is there before any case
# is believed.
SERVICE="${SERVICE:-$("$SCR" check 2>/dev/null \
          | awk -F'|' '/^  RUNNING /{print $2; exit}' | sed 's/^ *//; s/ (.*//')}"
[ -n "$SERVICE" ] || setup_fail \
  "no RUNNING service could be read from '$SCR check'." \
  "" \
  "This harness measures a SAMPLING WINDOW, and there is nothing to sample" \
  "unless a service is up. It is a hard failure rather than a skip: a run that" \
  "passed because its fixture was absent would report success for a parser it" \
  "never invoked - and the three defects this file exists to close all live" \
  "inside that parser." \
  "" \
  "Start a service, or set SERVICE=<name>."

pass=0; failed=0; changed=0; refdrift=0

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-26s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-26s   - %s\n' "" "" "$*"; }

heading() {
  printf '  %-9s %-26s %s\n' verdict case detail
  printf '  %-9s %-26s %s\n' --------- -------------------------- ------
}

# awk rather than bc: bc is not guaranteed in PASE and awk is, and every
# comparison here is on values this script parsed out of text rather than
# computed, so a missing tool would show up as a false verdict.
in_range() {  # value lo hi
  awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN{exit !(v+0>=lo+0 && v+0<=hi+0)}'
}
elapsed() {  # start end -> seconds, 2dp
  awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b-a}'
}
at_least() {  # value threshold
  awk -v v="$1" -v t="$2" 'BEGIN{exit !(v+0>=t+0)}'
}

# The field the report prints per job. Matched on the arrow deliberately:
# docs/messages.md records that `->Sampling time (s)` really does carry it, and
# that the arrow is why the line sorts first in upstream's alphabetical block.
# A bare "Sampling time" would also match "Disk I/O operations during sampling
# time", which is a different field with a different value.
SAMPLE_FIELD='->Sampling time (s):'

samples() { grep -F -- "$SAMPLE_FIELD" "$1" 2>/dev/null | sed 's/.*: *//'; }
jobs_in()  { grep -c '^Job: ' "$1" 2>/dev/null || true; }
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

# The three markers a crash leaves, on either stream. RNX and MCH are matched
# with their four digits so a service description containing the letters cannot
# match; CEE9901 is the ILE wrapper the other two arrive inside.
ABEND_RE='CEE9901|RNX[0-9]{4}|MCH[0-9]{4}'

# ---------------------------------------------------------------------------
# The runner.
#
# Every case goes through here, so the abend check cannot be forgotten by a case
# that was only interested in something else.
#
# Sets: RC WALL OUT ERR NSAMP NWARN, and ABEND_WHY (empty when clean).
# ---------------------------------------------------------------------------
perf_run() {  # tag -- argv...
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  OUT="$WORK/$tag.out"; ERR="$WORK/$tag.err"
  local t0 t1
  t0=$(now)
  "$SCR" "$@" perfinfo "$SERVICE" > "$OUT" 2> "$ERR"
  RC=$?
  t1=$(now)
  WALL=$(elapsed "$t0" "$t1")
  NSAMP=$(samples "$OUT" | grep -c '' || true); [ -z "$NSAMP" ] && NSAMP=0
  NWARN=$(grep -Fc -- 'sample time argument is not valid' "$ERR" 2>/dev/null || true)
  [ -z "$NWARN" ] && NWARN=0

  ABEND_WHY=""
  if grep -qE "$ABEND_RE" "$OUT" "$ERR" 2>/dev/null; then
    ABEND_WHY="ABEND: $(grep -hE -m1 "$ABEND_RE" "$OUT" "$ERR")"
  elif [ "$RC" -eq 255 ]; then
    ABEND_WHY="exit 255 - the command did not complete"
  fi
}

# assert_perf TAG BASIS LO HI WARN -- argv...
#
#   LO HI   the window every job's `->Sampling time (s)` must fall in. Chosen so
#           that a one-second fallback is OUTSIDE it - see the header.
#   WARN    silent           nothing on stderr about the sample time
#           <literal>        exactly one stderr line, containing <literal>
assert_perf() {
  local tag="$1" basis="$2" lo="$3" hi="$4" want_warn="$5"; shift 5
  [ "$1" = "--" ] && shift
  local problems=() v

  perf_run "$tag" -- "$@"

  # First, and reported first: a crash is not a range difference.
  if [ -n "$ABEND_WHY" ]; then
    report FAIL "$tag" "($basis) $ABEND_WHY"
    detail "the value parser is the thing this harness exists to keep standing"
    detail "artefacts: $tag.out $tag.err"
    failed=$((failed+1))
    return 1
  fi

  [ "$RC" -eq 0 ] || problems+=("exit $RC, wanted 0")

  # A report was produced at all. Without this every range assertion below is
  # vacuously true on empty output - zero samples, none of them out of range.
  if [ "$NSAMP" -eq 0 ]; then
    problems+=("no '$SAMPLE_FIELD' line in the report - nothing was sampled")
  elif [ "$NSAMP" -ne "$NJOBS" ]; then
    problems+=("$NSAMP sampled job(s), but the fixture run found $NJOBS")
  else
    for v in $(samples "$OUT"); do
      in_range "$v" "$lo" "$hi" || \
        problems+=("window $v is outside [$lo, $hi] - a 1.0s default is outside it too, which is the point")
    done
  fi

  case "$want_warn" in
    silent)
      [ "$NWARN" -eq 0 ] || problems+=("$NWARN sample-time warning line(s) on stderr for a value that is valid: $(grep -F -m1 -- 'sample time' "$ERR")") ;;
    *)
      local n_lit
      n_lit=$(grep -Fc -- "$want_warn" "$ERR" 2>/dev/null || true); [ -z "$n_lit" ] && n_lit=0
      if [ "$n_lit" -eq 0 ]; then
        problems+=("no stderr line contains '$want_warn' ($(count_lines "$ERR") stderr line(s))")
      elif [ "$n_lit" -ne 1 ]; then
        problems+=("the warning appears $n_lit times on stderr, wanted once for the whole command")
      fi
      # The other half of "once, whatever the job count".
      if [ "$NWARN" -gt 1 ]; then
        problems+=("$NWARN sample-time warning line(s) - it is emitted per job, not per command")
      fi
      # And never on the format-critical stream.
      local on_out
      on_out=$(grep -Fc -- 'sample time argument is not valid' "$OUT" 2>/dev/null || true)
      [ -z "$on_out" ] && on_out=0
      [ "$on_out" -eq 0 ] || problems+=("the warning also appears on STDOUT ($on_out line(s)), which a column-parsing consumer reads") ;;
  esac

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) exit $RC, window $(samples "$OUT" | tr '\n' ' ')wall ${WALL}s"
    pass=$((pass+1))
    return 0
  fi

  if [ "$basis" = pinned ]; then
    report CHANGED "$tag" "RMSC's pinned behaviour moved - see the comment above this case"
    changed=$((changed+1))
  else
    report FAIL "$tag" "($basis) wall ${WALL}s"
    failed=$((failed+1))
  fi
  local p; for p in "${problems[@]}"; do detail "$p"; done
  detail "artefacts: $tag.out $tag.err"
  return 1
}

printf 'sampletime: whether --sampletime= is converted, honoured, and survivable\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null | head -n 1 || echo 'version unknown')"
printf 'fixture service: %s\n\n' "$SERVICE"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture, and the baseline every window is measured against"
echo
heading
# ---------------------------------------------------------------------------

# THE DEFAULT RUN IS BOTH A CASE AND THE FIXTURE PROOF, and it has to be both.
#
# As a case it pins that the absent argument still means one second - the row
# that would catch a "fix" to the parser that changed the default while making
# every explicit value work.
#
# As a fixture proof it establishes two numbers the rest of the run depends on:
# how many jobs the service has (NJOBS), and how long a default run takes
# (WALL_DEFAULT). Both are read from a live service, so neither can be written
# down in advance.
perf_run default --
NJOBS=$(jobs_in "$WORK/default.out"); [ -z "$NJOBS" ] && NJOBS=0
WALL_DEFAULT="$WALL"
DEFAULT_SAMPLES=$(samples "$WORK/default.out" | tr '\n' ' ')

if [ -n "$ABEND_WHY" ]; then
  report FAIL fixture "$ABEND_WHY on the DEFAULT run, with no argument at all"
  detail "nothing below is evidence; the harness cannot establish a baseline"
  echo
  echo "pass=$pass   failed=1   pinned-changed=0   reference-drift=0"
  echo "FAILED: the default run does not complete"
  exit 1
fi

if [ "$RC" -ne 0 ] || [ "$NJOBS" -eq 0 ] || [ "$NSAMP" -eq 0 ]; then
  report FAIL fixture "exit $RC, $NJOBS job line(s), $NSAMP sampled block(s)"
  detail "'$SCR perfinfo $SERVICE' did not produce a sampled report"
  detail "the service was RUNNING when it was discovered - it may have stopped since,"
  detail "or perfinfo may be printing the NOT RUNNING form"
  detail "every window assertion below would be vacuously true on this output"
  detail "artefacts: default.out default.err"
  echo
  echo "pass=$pass   failed=1   pinned-changed=0   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi

report PASS fixture "$NJOBS job(s), $NSAMP sampled block(s), default run ${WALL_DEFAULT}s"
pass=$((pass+1))

# THE ONCE-ONLY ASSERTION IS ONLY WORTH ANYTHING ON MORE THAN ONE JOB, and a run
# that does not say so invites the stronger reading. With a single-job service
# "once per command" and "once per job" produce the same line count, so the
# assertion cannot separate them - it still runs, it just proves less. The
# verdict column is what gets scanned in scrollback, so the qualifier goes there.
if [ "$NJOBS" -lt 2 ]; then
  report WEAKENED once-only-warning \
    "the fixture service has $NJOBS job - 'once per command' and 'once per job' agree at one job, so the warning cases below cannot tell them apart"
fi

# Basis measured: absent argument, ~1.03s, exit 0, on both implementations.
# The range is the one every OTHER window case is built to exclude, which is
# why it is stated here once and referred to below.
if [ "$RC" -eq 0 ] && [ "$NSAMP" -eq "$NJOBS" ]; then
  dbad=0
  for v in $(samples "$WORK/default.out"); do
    in_range "$v" 0.90 1.60 || dbad=$((dbad+1))
  done
  if [ "$dbad" -eq 0 ]; then
    report PASS no-argument "(measured) default window $DEFAULT_SAMPLES- one second"
    pass=$((pass+1))
  else
    report FAIL no-argument "(measured) $dbad job(s) outside [0.90, 1.60]: $DEFAULT_SAMPLES"
    detail "the default is one second; if this moved, every range below is measuring the wrong thing"
    detail "upstream samples ~1.05s with no argument at all - stage 3's sc:default re-takes it"
    detail "IF AN INVALID VALUE STILL FALLS BACK TO ~1.0 while this reads ~0.0, the default is"
    detail "being applied by the fallback path and NOT by the absent-option path - look at where"
    detail "the window is initialised before the argument loop, not at the conversion"
    failed=$((failed+1))
  fi
fi

# Whether the DEFAULT window is itself indistinguishable from zero. Not a case:
# no-argument above is the case. This is what the zero case needs in order to
# know whether it is still separating anything - see the note above it.
DEFAULT_ZEROISH=0
for v in $(samples "$WORK/default.out"); do
  in_range "$v" 0.000 0.20 && DEFAULT_ZEROISH=1
done

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the window is honoured, an invalid value is survivable, and the"
echo "   value is converted where and when it should be"
echo
heading
# ---------------------------------------------------------------------------

# A PLAIN DECIMAL. Measured: sc 2.534/2.558, scr 2.560. The range excludes both
# the 1.0 default and 0, so it separates a parser that ignored the argument, one
# that clamped it, and one that read only the integer part (which would give 2.0
# - inside the range, and deliberately so: telling 2.0 from 2.5 is measure (b)'s
# job, not this range's, because the sampling loop's own overhead is larger than
# the difference would be reliable at).
assert_perf plain-decimal measured 2.40 3.40 silent -- --sampletime=2.5

# MEASURE (b): the same run's WALL CLOCK against the default run's.
#
# This is the case that does not trust the report. `->Sampling time (s)` is a
# number the implementation prints about itself; if it were echoed from the
# argument instead of measured, every range assertion in this file would agree
# with a parser that stored the value and never used it. Wall clock cannot be
# echoed.
#
# The comparison is between two runs rather than against an absolute so that JVM
# and job start-up cancel rather than having to be estimated. Requesting 2.5
# instead of 1.0 costs (jobs x 1.5) extra seconds - 3.0s at two jobs. The
# threshold is (jobs x 1.0), a third below that, and a parser that ignored the
# argument scores about 0.
WALL_25="$WALL"
wall_delta=$(awk -v a="$WALL_DEFAULT" -v b="$WALL_25" 'BEGIN{printf "%.2f", b-a}')
wall_want=$(awk -v n="$NJOBS" 'BEGIN{printf "%.2f", n*1.0}')
if at_least "$wall_delta" "$wall_want"; then
  report PASS window-costs-time \
    "(inferred) 2.5s run took ${wall_delta}s longer than the default, wanted >= ${wall_want}s"
  pass=$((pass+1))
else
  report FAIL window-costs-time \
    "(inferred) 2.5s run took only ${wall_delta}s longer than the default, wanted >= ${wall_want}s"
  detail "default ${WALL_DEFAULT}s, --sampletime=2.5 ${WALL_25}s, $NJOBS job(s)"
  detail "the report may be echoing the requested value rather than sampling for it"
  detail "a loaded box inflates BOTH runs, so this compares them rather than either alone"
  failed=$((failed+1))
fi

# SUB-SECOND. Measured: scr 0.267/0.280. The range excludes 1.0 above and 0.000
# below, so it separates the default fallback from a clamp-to-zero - which is a
# real rival here, since a parser that only handled integers would floor 0.25 to
# 0 and produce a report that still looks complete.
assert_perf sub-second measured 0.15 0.85 silent -- --sampletime=0.25

# ZERO IS A VALID VALUE, not a missing one. Measured 0.000 on RMSC, exit 0, full
# report. The upper bound is 0.20, below sub-second's observed 0.27, so this
# case and the one above disagree about at least one implementation: a parser
# that treated 0 as "unset" and applied the default would land at 1.03 and fail
# here while passing everywhere else.
#
# ITS SEPARATING POWER DEPENDS ON THE BASELINE, AND THE BASELINE CAN BREAK. That
# reasoning holds only while the DEFAULT window is one second. If the absent
# option also produces ~0 - which is exactly the regression no-argument caught
# on 8 September - then "0 was honoured" and "0 is what this build does with no
# option at all" produce the same number and this case stops telling them apart.
# It still runs; it just proves less, and a run that did not say so would invite
# the stronger reading. The verdict column is what gets scanned in scrollback,
# so the qualifier goes there rather than into a footnote.
if [ "$DEFAULT_ZEROISH" -eq 1 ]; then
  report WEAKENED zero \
    "the PASS below is REDUCED - the DEFAULT window is also ~0 on this build, so this case cannot separate '0 was honoured' from 'everything samples for 0'; fix no-argument first"
fi
assert_perf zero measured 0.000 0.20 silent -- --sampletime=0

# MORE PRECISION THAN THE FIELD HOLDS. Measured 2.612, so the extra digits are
# dropped and the value is still used.
#
# WHAT THIS CASE DOES NOT SEPARATE, said plainly. The specification calls this
# "truncates to 3dp". Truncating 2.5555 gives 2.555 and rounding gives 2.556 -
# one millisecond apart, against a sampling loop whose own overhead is sixty
# times that. No assertion here can tell those two apart and none pretends to.
# What it DOES rule out is the reading that matters: that a value with more
# precision than the parser expects is refused, or warns, or falls back to one
# second. That is worth a case; the third decimal place is not.
assert_perf excess-precision measured 2.40 3.40 silent -- --sampletime=2.5555

# LEADING ZEROS. Measured 2.533/2.560 - accepted, and worth two cases rather
# than one.
#
# THE SPECIFICATION'S FIXTURE FOR THIS IS 0000002.5, AND IT CANNOT SEPARATE THE
# DEFECT IT IS AIMED AT. The second of the three abends was a guard that counted
# CHARACTERS where it should have counted the receiver's integer DIGITS. A
# character-counting guard sized against a ten-digit receiver accepts anything
# up to ten characters, and `0000002.5` is nine. So it passes either way - the
# exact shape CLAUDE.md describes as watching the change not crash.
#
# The second fixture below carries fifteen characters before the decimal point
# and still means 2.5. A guard counting characters refuses it and falls back to
# one second; a guard reading the value accepts it and samples for 2.5. They
# disagree, which is what makes it a test.
assert_perf leading-zeros      measured 2.40 3.40 silent -- --sampletime=0000002.5
assert_perf leading-zeros-long measured 2.40 3.40 silent -- --sampletime=000000000000002.5

# A LEADING DOT, no integer part at all. Measured: sc 0.548/0.602, scr 0.530.
#
# NOT IN THE SPECIFICATION, and it belongs here because it is the same SHAPE as
# the third abend: a substring of the value that turns out to be empty. That one
# was the whole string; this is the part before the dot. Both implementations
# accept it, so the assertion is parity and not merely survival.
assert_perf leading-dot measured 0.40 0.90 silent -- --sampletime=.5

# NOT A NUMBER. Measured on both: WARNING on stderr, exit 0, one-second window,
# full report. Three things are asserted and each rules out a different reading:
#
#   the window falls in the DEFAULT range   the fallback is one second, not zero
#                                           and not "whatever was in the field"
#   exactly one line carries the literal    the warning is emitted once for the
#                                           command, not once per job
#   the literal is the WHOLE ARGUMENT       upstream names `--sampletime=abc`,
#                                           not `abc`. A message quoting only
#                                           the value would still contain 'abc'
#                                           and pass a looser match.
assert_perf not-a-number measured 0.90 1.60 '--sampletime=abc' -- --sampletime=abc

# AN EMPTY VALUE - the third abend, RNX0100, a substring taken past the end.
# Measured on both: the same warning, naming the argument with nothing after the
# equals sign, and the same one-second fallback.
assert_perf empty-value measured 0.90 1.60 '--sampletime=' -- --sampletime=

# A NUMBER TOO BIG FOR THE RECEIVER - the first two abends, MCH1210 then RNX0103.
# Measured on RMSC: the warning, and a fall back to one second. This is one of
# the two rows where upstream differs; it is pinned in stage 2 and asserted here
# for the thing that is not a divergence at all - that it does not abend, and
# that a usable report still comes out.
assert_perf too-big measured 0.90 1.60 '--sampletime=9999999999' -- --sampletime=9999999999

# MALFORMED IN THE FRACTION rather than in the whole value. Measured on RMSC:
# the warning and the one-second fallback, for both `2.abc` and `2.5.6`.
#
# NOT IN THE SPECIFICATION. It is here because the trailing-dot case below shows
# the fraction is parsed separately, so it has its own edges, and a fix for the
# trailing dot could plausibly be written in a way that accepts `2.abc` as 2 -
# which would be worse than warning, since it would silently sample for a
# different length than the user asked for.
assert_perf bad-fraction  measured 0.90 1.60 '--sampletime=2.abc' -- --sampletime=2.abc
assert_perf two-dots      measured 0.90 1.60 '--sampletime=2.5.6' -- --sampletime=2.5.6

# A BARE DOT. Measured on RMSC: the warning, one-second fallback. Included
# because it is the value that is empty on BOTH sides of the dot, and it works -
# which is what makes the trailing-dot failure below specific rather than
# general.
assert_perf bare-dot measured 0.90 1.60 '--sampletime=.' -- --sampletime=.

# -q SUPPRESSES THE WARNING, AND BOTH HALVES ARE ASSERTED.
#
# The half that is easy to forget is not-a-number above: a case that only
# checked the -q run would pass against an implementation that had stopped
# warning altogether, confirming silence and calling it suppression. So the run
# WITHOUT -q is this case's staging proof as well as a case in its own right,
# and it is invariant under any change to -q.
#
# The window is asserted too. Silence is not the whole contract: -q must
# suppress the warning and NOT the fallback, or a quiet run would sample for a
# different length than a loud one.
if [ "$(grep -Fc -- '--sampletime=abc' "$WORK/not-a-number.err" 2>/dev/null || echo 0)" -eq 0 ]; then
  report SKIPPED quiet-suppresses \
    "nothing warns without -q, so suppression is not testable - see not-a-number"
else
  perf_run quiet-abc -- -q --sampletime=abc
  qprob=()
  [ -z "$ABEND_WHY" ] || qprob+=("$ABEND_WHY")
  [ "$RC" -eq 0 ] || qprob+=("exit $RC, wanted 0 - silence because the flag was REFUSED is not suppression")
  q_lines=$(count_lines "$WORK/quiet-abc.err")
  [ "$NWARN" -eq 0 ] || qprob+=("$NWARN sample-time warning line(s) survive -q, wanted 0")
  if [ "$NSAMP" -eq 0 ]; then
    qprob+=("no sampled block under -q - the report itself was suppressed")
  else
    for v in $(samples "$WORK/quiet-abc.out"); do
      in_range "$v" 0.90 1.60 || qprob+=("window $v outside [0.90, 1.60] - -q changed the fallback as well as the warning")
    done
  fi
  if [ ${#qprob[@]} -eq 0 ]; then
    report PASS quiet-suppresses "(measured) warning gone, $q_lines stderr line(s), fallback unchanged"
    pass=$((pass+1))
  else
    report FAIL quiet-suppresses "(measured)"
    for p in "${qprob[@]}"; do detail "$p"; done
    detail "artefacts: quiet-abc.out quiet-abc.err"
    failed=$((failed+1))
  fi
fi

# -q AFTER THE BAD OPTION MUST *NOT* SUPPRESS. The other half of the pair
# above, and the only thing in this file that can see WHERE the value is
# converted.
#
# MEASURED 8 September 2026, on both implementations and identically:
#
#     sc  -q --sampletime=abc perfinfo    warning SUPPRESSED
#     sc  --sampletime=abc -q perfinfo    warning PRESENT
#     scr -q --sampletime=abc perfinfo    warning SUPPRESSED
#     scr --sampletime=abc -q perfinfo    warning PRESENT
#
# That asymmetry only happens if the value is converted inside the argument loop
# IN ARGUMENT ORDER, so that a -q read later cannot retroactively silence a
# warning already emitted. It is the observable signature of the design, and it
# is the reason this case exists: if the conversion ever moved back to the end
# of the parse - a natural-looking simplification, and one that makes every
# other case in this file pass - `-q` after would start suppressing, and only
# this row would notice.
#
# BOTH ORDERS ARE ASSERTED, in one case, on purpose. Split across two cases, the
# suppressing half would go green against an implementation that had stopped
# warning altogether and the non-suppressing half against one that had stopped
# honouring -q. Together they can only both hold if the ordering is real.
perf_run quiet-after -- --sampletime=abc -q
oprob=()
[ -z "$ABEND_WHY" ] || oprob+=("$ABEND_WHY")
[ "$RC" -eq 0 ] || oprob+=("exit $RC, wanted 0")
[ "$NWARN" -eq 1 ] || oprob+=("$NWARN warning line(s) with -q AFTER the bad option, wanted 1 - a -q read later must not silence a warning already emitted")
qbefore=$(grep -Fc -- 'sample time argument is not valid' "$WORK/quiet-abc.err" 2>/dev/null || true)
[ -z "$qbefore" ] && qbefore=0
[ "$qbefore" -eq 0 ] || oprob+=("$qbefore warning line(s) with -q BEFORE it, wanted 0 - see quiet-suppresses")
if [ ${#oprob[@]} -eq 0 ]; then
  report PASS quiet-order \
    "(measured) -q before suppresses, -q after does not - converted in argument order"
  pass=$((pass+1))
else
  report FAIL quiet-order "(measured)"
  for p in "${oprob[@]}"; do detail "$p"; done
  detail "both orders must hold together; either alone passes against a different defect"
  detail "artefacts: quiet-after.out quiet-after.err quiet-abc.out quiet-abc.err"
  failed=$((failed+1))
fi

# ---------------------------------------------------------------------------
# A TRAILING DOT - AN ABEND WHEN THIS FILE WAS WRITTEN, FIXED 8 SEPTEMBER 2026.
#
# Measured BEFORE the fix:
#
#     sc  --sampletime=2. perfinfo <svc>   exit 0, 66 lines, window 2.075/2.047
#     scr --sampletime=2. perfinfo <svc>   exit 255, NOTHING on stdout, and
#                                          CEE9901: Application error. RNX0100
#                                          unmonitored by RMSC
#
# A fourth instance of the family the other three abends belong to - the same
# RNX0100 as the empty value, reached through a different empty substring. The
# neighbours placed it precisely, and all four were measured:
#
#     --sampletime=.5   empty INTEGER part     worked, 0.530
#     --sampletime=.    empty BOTH sides       warned cleanly, fell back
#     --sampletime=2.   empty FRACTION         ABENDED
#     --sampletime=0.   empty FRACTION         ABENDED identically
#
# So it was not "a value with a dot in it" and not "an empty part": it was
# specifically the empty fraction.
#
# SETTLED AS UPSTREAM'S READING - `2.` means 2.0. Measured after the fix at
# 2.030 against upstream's 2.047.
#
# WHY THIS IS NOW A RANGE AND NOT A SURVIVAL CHECK. While the answer was
# undecided this case asserted only "exit 0, no escape, a report came out",
# which was right then and would be wrong to leave. Two readings were
# defensible - accept as 2.0, or warn and fall back to one second - and a case
# that admits both cannot tell the chosen one from the rejected one. Now that
# it is settled, the range excludes 1.0 so a retreat to the fallback fails
# here, and `silent` excludes warn-and-still-use-2.0.
#
# BOTH ENDS ARE KEPT because the fix had to guard both, and because `0.` is the
# one that reaches the empty fraction with an integer part that is itself
# falsy - the shape most likely to be missed by a fix written against `2.`
# alone.
assert_perf trailing-dot      measured 1.80 2.80 silent -- --sampletime=2.
assert_perf trailing-dot-zero measured 0.000 0.20 silent -- --sampletime=0.

# ---------------------------------------------------------------------------
# WHERE THE VALUE IS CONVERTED - AND IT IS NOW EVERY OPERATION, NOT JUST perfinfo.
#
# Found by writing this file. It was PINNED here as an RMSC divergence, fired
# CHANGED on 8 September when the design moved, and is repointed at the new
# measurement rather than deleted - which is the whole reason a pinned case is
# worth carrying.
#
# WHAT IT USED TO RECORD. Upstream validated the option when it PARSED it, so
# every operation warned; RMSC converted at the POINT OF USE, so only `perfinfo`
# did:
#
#     sc  --sampletime=abc check <svc>    exit 0, WARNING on stderr
#     scr --sampletime=abc check <svc>    exit 0, NOTHING on stderr
#
# WHAT IT RECORDS NOW, measured 8 September on both implementations, on `check`
# and on `list`: both warn, exactly once, exit 0. RMSC converts in the argument
# loop, in argument order - see quiet-order above, which is the case that pins
# the ORDER; this one pins the REACH.
#
# IT IS A DIFFERENTIAL, not a hardcoded expectation, and that is deliberate:
# the property is "RMSC warns here exactly when upstream does", which stays true
# if upstream is ever found to differ per operation and cannot go stale the way
# a written-down "warns on check" would.
#
# WHY THE HARNESS STILL PAYS FOR perfinfo ON EVERY OTHER CASE. It is tempting to
# read this row as licence to move the cheap cases onto `check` - two seconds
# against seven - now that `check` does invoke the parser. It is not. Every one
# of those cases asserts the FALLBACK WINDOW as well as the warning, and the
# window exists only where something is sampled. A `check` version of
# not-a-number would confirm the warning and say nothing about whether the
# fallback is one second, zero, or whatever was left in the field - and rival 4
# is half the point of the case.
# ---------------------------------------------------------------------------
for op in check list; do
  "$SCR" --sampletime=abc "$op" "$SERVICE" > "$WORK/parse-$op.out" 2> "$WORK/parse-$op.err"
  pt_rc=$?
  pt_warn=$(grep -Fc -- 'sample time argument is not valid' "$WORK/parse-$op.err" 2>/dev/null || true)
  [ -z "$pt_warn" ] && pt_warn=0
  "$SC" --sampletime=abc "$op" "$SERVICE" > "$WORK/sc.parse-$op.out" 2> "$WORK/sc.parse-$op.err"
  sc_pt_warn=$(grep -Fc -- 'sample time argument is not valid' "$WORK/sc.parse-$op.err" 2>/dev/null || true)
  [ -z "$sc_pt_warn" ] && sc_pt_warn=0
  pt_out=$(grep -Fc -- 'sample time argument is not valid' "$WORK/parse-$op.out" 2>/dev/null || true)
  [ -z "$pt_out" ] && pt_out=0

  ptprob=()
  if grep -qE "$ABEND_RE" "$WORK/parse-$op.out" "$WORK/parse-$op.err" 2>/dev/null; then
    ptprob+=("ABEND: $(grep -hE -m1 "$ABEND_RE" "$WORK/parse-$op.out" "$WORK/parse-$op.err")")
  fi
  [ "$pt_rc" -eq 0 ] || ptprob+=("exit $pt_rc - an invalid value for an option this operation does not USE must not fail it")
  [ "$pt_out" -eq 0 ] || ptprob+=("$pt_out warning line(s) on STDOUT, the format-critical stream")
  if [ "$sc_pt_warn" -ne "$pt_warn" ]; then
    ptprob+=("sc warns $sc_pt_warn time(s) on '$op' and RMSC warns $pt_warn - they must agree")
  elif [ "$pt_warn" -ne 1 ]; then
    ptprob+=("both warn $pt_warn time(s) on '$op'; one warning per command is the contract")
  fi

  if [ ${#ptprob[@]} -eq 0 ]; then
    report PASS "warns-on-$op" "(measured) both implementations warn once, exit 0 - converted at parse time"
    pass=$((pass+1))
  else
    report FAIL "warns-on-$op" "(measured)"
    for p in "${ptprob[@]}"; do detail "$p"; done
    detail "artefacts: parse-$op.out parse-$op.err sc.parse-$op.out sc.parse-$op.err"
    failed=$((failed+1))
  fi
done

echo
# ---------------------------------------------------------------------------
echo "== stage 2: known differences, pinned so a change is visible"
echo
heading
# ---------------------------------------------------------------------------

# PINNED - A NEGATIVE VALUE.
#
#   upstream sc:  accepts the number, then its own gather FAILS per job with
#                 "Unable to retrieve performance data for job ...". The sampled
#                 block is dropped entirely - 42 stdout lines against 58 - and
#                 stderr carries two lines per job. Exit 0.
#   RMSC:         no warning, window clamped to 0, full report, exit 0.
#
# Sanctioned: reproducing a crash faithfully is not parity worth having, and
# RMSC produces a report where upstream produces error text. Stage 3 re-takes
# upstream's side so the divergence cannot quietly close from the other end.
#
# The window is asserted at 0, not merely "not 1.0". A clamp to zero and a fall
# back to the default are the two plausible answers here and only one of them is
# RMSC's; a range that admitted both would pin nothing.
assert_perf negative pinned 0.000 0.20 silent -- --sampletime=-1

# PINNED - TOO BIG FOR THE RECEIVER.
#
#   upstream sc:  the same per-job gather failure as the negative case.
#   RMSC:         the WARNING, and a fall back to one second.
#
# The survival half of this is asserted in stage 1 as too-big. What is pinned
# HERE is that RMSC answers with a warning where upstream answers with error
# text and a truncated report - so if RMSC ever starts producing upstream's
# shape, that is a decision and should not arrive silently.
if [ "$(grep -Fc -- '--sampletime=9999999999' "$WORK/too-big.err" 2>/dev/null || echo 0)" -eq 1 ]; then
  report PASS too-big-pinned "(pinned) RMSC warns and falls back where upstream fails per job"
  pass=$((pass+1))
else
  report CHANGED too-big-pinned "(pinned) RMSC no longer warns about an over-large value"
  detail "see too-big in stage 1 for what it does instead"
  changed=$((changed+1))
fi


echo
# ---------------------------------------------------------------------------
echo "== stage 3: upstream reference, re-taken"
echo "   (stage 1's 'measured' expectations are only as good as this table, and"
echo "    stage 2's divergences only mean something beside it; a REFDRIFT means"
echo "    the reference moved, not that RMSC regressed)"
echo
heading
# ---------------------------------------------------------------------------

# sc_ref TAG -- argv...
# Runs upstream and reports what it did. Nothing here fails on RMSC's account.
sc_ref() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  local want_lo="$SC_LO" want_hi="$SC_HI" want_warn="$SC_WARN"
  local o="$WORK/sc.$tag.out" e="$WORK/sc.$tag.err" rc n s bad=0
  "$SC" "$@" perfinfo "$SERVICE" > "$o" 2> "$e"
  rc=$?
  n=$(samples "$o" | grep -c '' || true); [ -z "$n" ] && n=0
  local w; w=$(grep -Fc -- 'sample time argument is not valid' "$e" 2>/dev/null || true)
  [ -z "$w" ] && w=0

  local why=""
  [ "$rc" -eq 0 ] || why="$why exit=$rc(wanted 0)"
  case "$want_warn" in
    silent) [ "$w" -eq 0 ] || why="$why warns($w)(wanted silence)" ;;
    once)   [ "$w" -eq 1 ] || why="$why warns=$w(wanted 1)" ;;
    none)   ;;
  esac
  if [ "$want_lo" != "-" ]; then
    if [ "$n" -eq 0 ]; then
      why="$why no-sampled-block"
    else
      for s in $(samples "$o"); do
        in_range "$s" "$want_lo" "$want_hi" || { why="$why window=$s(wanted [$want_lo,$want_hi])"; bad=1; }
      done
    fi
  fi

  if [ -z "$why" ]; then
    report PASS "sc:$tag" "exit $rc, $n sampled job(s)$( [ "$want_lo" != - ] && echo ", window $(samples "$o" | tr '\n' ' ')")as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$tag" "$why"
    detail "artefacts: sc.$tag.out sc.$tag.err"
    refdrift=$((refdrift+1))
  fi
}

# The default, so the reference's own baseline is re-taken too.
SC_LO=0.90 SC_HI=1.60 SC_WARN=silent  sc_ref default --
# The window is honoured upstream as well, which is what makes stage 1's
# plain-decimal case a parity assertion rather than an RMSC-only one.
SC_LO=2.40 SC_HI=3.40 SC_WARN=silent  sc_ref plain-decimal -- --sampletime=2.5
# The warning, its text, and the one-second fallback behind it.
SC_LO=0.90 SC_HI=1.60 SC_WARN=once    sc_ref not-a-number -- --sampletime=abc
SC_LO=0.90 SC_HI=1.60 SC_WARN=once    sc_ref empty-value  -- --sampletime=
# And -q silencing it upstream, which is where RMSC's requirement comes from.
SC_LO=0.90 SC_HI=1.60 SC_WARN=silent  sc_ref quiet-abc    -- -q --sampletime=abc
# The other order, which upstream does NOT silence. This row is what makes
# quiet-order a parity assertion rather than a guess about RMSC's internals: if
# upstream ever started suppressing here, RMSC's asymmetry would stop being the
# thing to hold still and this reports REFDRIFT instead of quiet-order failing.
SC_LO=0.90 SC_HI=1.60 SC_WARN=once    sc_ref quiet-after  -- --sampletime=abc -q
# The trailing dot, which upstream accepts as 2.0. This row is what says the
# stage 1 failure is a defect rather than a difference of opinion.
SC_LO=1.80 SC_HI=2.80 SC_WARN=silent  sc_ref trailing-dot -- --sampletime=2.

# THE TWO DIVERGENCES, and their reference is a SHAPE rather than a window:
# upstream drops the sampled block entirely and writes per-job errors. So they
# are checked for exactly that - no sampled block, and error text on stderr -
# because a window range would be asserting the absence of a thing by measuring
# it.
for pair in "negative:--sampletime=-1" "too-big:--sampletime=9999999999"; do
  tag="${pair%%:*}"; arg="${pair#*:}"
  "$SC" "$arg" perfinfo "$SERVICE" > "$WORK/sc.$tag.out" 2> "$WORK/sc.$tag.err"
  sc_rc=$?
  sc_n=$(samples "$WORK/sc.$tag.out" | grep -c '' || true); [ -z "$sc_n" ] && sc_n=0
  sc_e=$(grep -Fc 'Unable to retrieve performance data' "$WORK/sc.$tag.err" 2>/dev/null || true)
  [ -z "$sc_e" ] && sc_e=0
  if [ "$sc_rc" -eq 0 ] && [ "$sc_n" -eq 0 ] && [ "$sc_e" -ge 1 ]; then
    report PASS "sc:$tag" "exit 0, no sampled block, $sc_e per-job failure(s) - the divergence still stands"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$tag" \
      "exit $sc_rc, $sc_n sampled block(s), $sc_e per-job failure(s) - upstream no longer fails here"
    detail "the pinned case in stage 2 records RMSC as the one that still works; re-read it"
    detail "artefacts: sc.$tag.out sc.$tag.err"
    refdrift=$((refdrift+1))
  fi
done

echo
echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and where it would have to be done instead
#
#   THE PARSER DIRECTLY. It is a local procedure and nothing can call it. Every
#   assertion here is made through its effect on a live sampling run, which
#   means a service has to be up and the run costs real seconds. If it were ever
#   exported, the range cases become a suite and this file keeps only the stream
#   and exit-status ones.
#
#   TRUNCATION VERSUS ROUNDING at the third decimal place - one millisecond,
#   against a loop whose overhead is sixty times that. See excess-precision.
#
#   THE UPPER BOUND OF THE ACCEPTED RANGE. `--sampletime=86400` is accepted and
#   samples for a day per job, so a case for it does not fail, it hangs. Where
#   the width guard starts refusing is between 86400 and 999999999 and is not
#   narrowed here for the same reason.
#
#   WHETHER AN ESCAPE IS STILL SIGNALLED. This sees the outcome, not the
#   mechanism. RMSC could signal and have something downstream tidy the streams,
#   and every assertion here would pass while the joblog filled with escapes.
#   That needs the joblog, not a shell.
#
#   INTERLEAVING. The streams are captured separately on purpose, so the
#   relative order of the warning and the report is thrown away.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: --sampletime= is not converted as the contract requires"
  exit 1
fi
if [ "$changed" -ne 0 ]; then
  echo "PINNED BEHAVIOUR CHANGED: $changed known difference(s) moved."
  echo "If that was intended, update this script and docs/parity.md together."
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer behaves as recorded."
  echo "Stage 1's expectations rest on that table - re-take it before trusting a"
  echo "pass or acting on a failure."
  exit 1
fi
echo "OK: every value is converted or refused, the window is honoured, and nothing abends"
