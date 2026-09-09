#!/QOpenSys/pkgs/bin/bash
#
# narration-test.sh - the lines sc prints while it is CHANGING STATE: which
# stream they land on, the order they come in, the blank line after them, and
# whether -q silences any of it.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and
# tools/error-delivery-test.sh, and modelled closely on the second of those. It
# is deliberately a shell script and not an iRPGUnit suite for the same reason
# that one is: stream routing, line ORDER within a command's output, exit status
# and the effect of a command-line flag only exist OUTSIDE the ILE job, and
# iRPGUnit runs inside one. No assertion in this file is reachable from RPG.
#
# ITS OTHER HALF IS qtestsrc/SCOUT.TEST.RPGLE, which holds the WORDING. The four
# procedures return their line rather than printing it, so every byte of every
# sentence is asserted there, where the test needs no service and no fixture.
# The split is not arbitrary and it is worth stating which side answers what:
#
#   SCOUT.TEST      what the sentence says
#   this script     which name reaches it, which stream it goes to, what else
#                   is printed alongside it, and in what order
#
# THE ONE RULE THAT ONLY THIS SIDE CAN TEST. docs/messages.md § "The two
# whole-surface differences" names it first: the progress line uses the SHORT
# name and the state lines use the FRIENDLY name. SCOUT_op_progress is handed
# one name and SCOUT_svc_state is handed one name, so neither can pick the wrong
# one - the CALLER picks, and only a real definition with two different names
# can catch it picking wrongly. SCOUT.TEST says so in as many words and does not
# attempt it. This script does, in every case below.
#
# WHY THE FIXTURE NAMES LOOK THE WAY THEY DO. Every short name is lower case
# with an underscore and every friendly name is capitalised words with spaces,
# and no short name is a substring of any friendly name or the other way round.
# That is what makes "the friendly name does not appear on the progress line" a
# real assertion rather than an accident of spelling - the same trick
# SCOUT.TEST's invalid-criteria cases use with 'Z last' against 'zzzlast'.
#
# BASIS OF EACH ASSERTION - read this before believing a failure
#
#   measured   the exact text was captured from sc 1.7.1 on 3 September with
#              tools/d2-probe.sh and is transcribed in docs/messages.md
#              § "Narration - the family RMSC does not have". Stage 4 re-runs
#              upstream against these same staged definitions and compares its
#              stdout to the same expectations, so the reference cannot go stale
#              underneath them.
#
#   composed   the sentence is captured but not for THIS verb or THIS state
#              combination - `Performing operation 'KILL' ...` is the captured
#              progress sentence with a verb docs/messages.md never quotes.
#              Stage 4 measures every one of these afresh on each run, so a
#              composed expectation that is wrong is reported as REFDRIFT
#              against upstream rather than as a defect in RMSC.
#
#   inferred   follows from a rule stated in docs/messages.md or docs/parity.md
#              rather than from a line of captured text. If one of these fails,
#              ask whether the inference was wrong before assuming the
#              implementation is.
#
# NOTHING docs/messages.md MARKS `unmeasured` IS ASSERTED ANYWHERE. In
# particular there is no case for the `(asynchronously)` progress variant:
# batch_mode was measured NOT to produce it and where it does come from is
# unknown, so a test would be pinning a guess.
#
# Stdout and stderr are captured to SEPARATE files throughout. Nothing here uses
# `2>&1`. docs/messages.md records at length what a merged capture cost when
# `loginfo`'s stream difference hid inside one - and, in the other direction,
# that reading the two streams apart made a group start look as though its lines
# arrived out of order when they did not. Both views are kept: the assertions
# are made on the separated captures, and the ordering assertions are made
# within one stream, which is the only place order is meaningful.
#
# THIS SCRIPT STARTS AND STOPS SERVICES, and runs by default anyway. The
# reasoning is the one error-delivery-test.sh sets out for its group case:
# fidelity-gate.sh excludes the state-changing operations because they would act
# on whatever real services the machine has, and that is right - but everything
# here acts ONLY on definitions this script has just written, in a group it
# invented, whose start command is a bounded python listener on a port it has
# checked is free. Nothing on the system is started, nothing is stopped, and the
# trap leaves nothing behind. Set NARRATE_DRY=1 to see the plan without running.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/narration-test.$$}"

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
# and names it by PID. That is the membership rule, and it is stated as a
# PROPERTY rather than as a count because the count was wrong twice over: this
# line used to read "all five harnesses", and load-warning-test.sh is a harness
# that has never carried the block while fidelity-gate.sh carries it and is not
# a harness at all.
#
# Deliberately duplicated rather than shared: each is deployed and run
# standalone, and a shared file would be a dependency that costs more than the
# repetition does. Change one, change all of them.
ls -dt /tmp/narration-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
SVCDIR="$WORK/services"

# Ports the staged services are checked on. High, contiguous, and every one of
# them is proved free before anything is written - see the setup below for why
# that is a hard failure and not a warning.
PORT_SOLO=65350
PORT_DEP=65351
PORT_TOP=65352
PORT_OTHER=65353
# The failure side. PORT_FAIL is the one port NOTHING ever binds: rmscn_fail's
# start command deliberately does not listen on it, so the start times out. It
# is proved free like the others, and for a sharper reason - if anything were
# listening there the service would come up and the whole failure stage would
# capture success wording.
PORT_FAIL=65354
PORT_FAIL2=65358
PORT_PART=65355
PORT_G2BASE=65356
PORT_G2USER=65357
# THE LOG-CONTENT PAIR. PORT_NOISY is a second port NOTHING ever binds - it is
# rmscn_noisy's unsatisfiable criterion, and it is separate from PORT_FAIL
# because two definitions naming one port produce the conflicting-criteria
# WARNING on stderr, which every blank-line ratio in this file counts.
#
# PORT_HALFOK is the opposite and the only port in this list bound by the
# HARNESS rather than by a service: rmscn_half is checked on it and on a job
# name that never exists, so with a listener of this script's own sitting on it
# the service reads PARTIAL without ever having been started, and its own start
# command never has to bind anything. That is what makes it silent on every
# attempt - see the log-detail cases in stage 3b.
PORT_NOISY=65359
PORT_HALFOK=65364

# Without this the PASE side of both implementations behaves differently.
export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud. A run that skipped a case
# because a fixture was missing would report success while testing nothing.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory - it drives" \
  "the wrapper, and the wrapper calls an ILE program. Set SCR=<path> or DEPLOY=" \
  "<deploy dir> if the build lives somewhere else."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Stage 4 re-measures every expectation in this file against upstream, because" \
  "several of them are COMPOSED rather than captured and the rest were" \
  "transcribed into markdown, which cannot preserve a trailing space. Running" \
  "without that anchor would leave the expectations unchecked. Set SC=<path> if" \
  "it is installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The staged services must ACTUALLY COME UP, or every capture below is" \
  "upstream's timeout wording filed under the heading 'successfully started'." \
  "A bare sleep can never satisfy a port criterion, so the start command is a" \
  "listener that binds the port it is checked on. Set PY=<path> if python3" \
  "lives elsewhere. This is a hard failure and not a skip: the whole family" \
  "this script exists to test is only reachable through a service that works."

mkdir -p "$SVCDIR" || setup_fail "cannot create work directory $SVCDIR"

# A listener that holds the port and then goes away on its own. Bounded, so
# nothing outlives this script even if it is killed before the trap runs.
cat > "$WORK/listen.py" <<'PEOF'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", int(sys.argv[1])))
s.listen(5)

# READY GOES TO A FILE NAMED BY THE CALLER, NOT TO STDOUT, and that is not
# fastidiousness - it is the whole difference between a fix and a defect.
#
# THIS SCRIPT HAS TWO ROLES. It is the harness's own listener for the half-up
# fixture, AND it is the start_cmd of several staged services. `sc` captures a
# service's output into its log, and `For details, see log file at:` is printed
# exactly when that log HAS CONTENT - see docs/messages.md.
#
# So the first version of this printed READY to stdout, six bytes landed in
# every service's log, and upstream started emitting a line the expectations do
# not have. Six REFDRIFTs, every one of them real, from a one-line change made
# to fix something else. The harness was right and I was wrong.
#
# AFTER the bind, never before: the caller waits for this word, so announcing
# it any earlier would restore the guess it replaces.
if len(sys.argv) > 2:
    with open(sys.argv[2], "w") as f:
        f.write("READY\n")
        f.flush()
time.sleep(600)
PEOF

# A process that lives but binds NOTHING. rmscn_fail's start command, and the
# whole reason a start can be made to fail on demand: the command succeeds, the
# job exists, and the criterion is never satisfied, which is upstream's TIMEOUT
# path rather than its could-not-launch path. `sleep` alone would do, but a
# script under $WORK keeps it inside the one directory the teardown sweeps.
cat > "$WORK/nobind.py" <<'PEOF'
import time
time.sleep(600)
PEOF

# A START COMMAND THAT PRINTS ONE LINE AND STOPS. It is the whole fixture for
# the log-content gate: both implementations redirect a service's start command
# into that service's log file, so this is the only staged service whose log
# has anything in it. One line, on stdout, and then it exits - nothing binds,
# so the start still times out exactly as rmscn_fail's does. The two runs
# differ in one thing only, which is the point.
cat > "$WORK/noisy.py" <<'PEOF'
import sys
sys.stdout.write("narration-test: one line, and then this start fails\n")
sys.stdout.flush()
PEOF

# PROVE EVERY PORT IS FREE BEFORE STAGING ANYTHING, and fail rather than pick
# another one.
#
# This is not tidiness. If something else is already listening on one of these
# ports, the service that is checked on it reports RUNNING before it has ever
# been started - so `start` prints "is already running" where the case wanted
# "successfully started", `stop` cannot take it down, and the run reports a
# handful of confident failures about wording that is in fact correct. The
# fixture would be broken in the one way that produces a plausible red rather
# than an obvious one.
#
# SO_REUSEADDR is deliberately NOT set here, unlike in the listener: the
# question is whether anyone at all holds the port, and REUSEADDR would answer
# a different one.
port_free() {
  "$PY" -c '
import socket, sys
s = socket.socket()
try:
    s.bind(("", int(sys.argv[1])))
except OSError:
    sys.exit(1)
sys.exit(0)' "$1" 2>/dev/null
}

for p in "$PORT_SOLO" "$PORT_DEP" "$PORT_TOP" "$PORT_OTHER" \
         "$PORT_FAIL" "$PORT_FAIL2" "$PORT_PART" "$PORT_G2BASE" "$PORT_G2USER" \
         "$PORT_NOISY" "$PORT_HALFOK"; do
  port_free "$p" || setup_fail \
    "port $p is already in use, so a service checked on it would report RUNNING" \
    "before this script had started anything." \
    "" \
    "That is the fixture failure that produces a believable red rather than an" \
    "obvious one: every 'successfully started' case would capture 'is already" \
    "running' and be reported as a wording defect. Free the port, or move the" \
    "PORT_* values at the top of this script." \
    "" \
    "A previous run of this script killed before its trap could fire is the" \
    "likeliest cause - its listeners sleep for ten minutes."
done

# ---------------------------------------------------------------------------
# The staged definitions.
#
# Four services and one group. Short names are lower case with underscores;
# friendly names are capitalised words with spaces. No short name is a substring
# of any friendly name, and no friendly name of any short name, so every "names
# it by X and not by Y" assertion below is a real question.
#
# The friendly names deliberately avoid the words the narration sentences
# themselves contain - "service", "dependency", "dependent" - so that a grep for
# a friendly name cannot match the fixed part of a line.
#
#   rmscn_solo   Alpha One Narrate       no dependencies, in the group
#   rmscn_dep    Bravo Two Narrate       the dependency
#   rmscn_top    Charlie Three Narrate   depends on rmscn_dep, NOT in the group
#   rmscn_other  Delta Four Narrate      no dependencies, in the group
#
# rmscn_top is kept out of the group on purpose. The group cases are about
# ORDER between members, and a member that drags a dependency in behind it would
# make the sequence a question about two rules at once.
# ---------------------------------------------------------------------------
SOLO=rmscn_solo;  SOLO_F='Alpha One Narrate'
DEP=rmscn_dep;    DEP_F='Bravo Two Narrate'
TOP=rmscn_top;    TOP_F='Charlie Three Narrate'
OTHER=rmscn_other; OTHER_F='Delta Four Narrate'
GROUP=rmscnarr

# THE FAILURE SIDE, added after the re-probe. docs/messages.md § "The fifth
# state, and three messages nobody had seen": three of the four lines below were
# invisible until a start was made to FAIL, and one of them is on STDOUT. A
# success-path probe measures the success path; it does not measure "what this
# command prints".
#
#   rmscn_fail   Echo Five Narrate     starts a process that binds nothing, so
#                                      the check_alive port is never satisfied
#                                      and the start TIMES OUT. Alone in its own
#                                      group, so a group start can be made to
#                                      fail without touching anything else.
#   rmscn_part   Foxtrot Six Narrate   TWO criteria, one satisfiable and one
#                                      not - the shape the gap probe used. It
#                                      reads PARTIAL to `check`, which is this
#                                      fixture's own proof that it staged.
FAIL=rmscn_fail;  FAIL_F='Echo Five Narrate'
# A SECOND failing member, and it exists for exactly one assertion.
#
# The blank-line rule on stderr was flagged in the last report as written but
# not yet SEPARATING: every fixture then produced one error per command, so
# "one blank per ERROR" and "one blank per command" agreed on every value and
# the ratio could not tell them apart. Two failing members in one group produces
# two errors under one command, which is the only shape that can.
# ITS SHORT NAME IS NOT rmscn_fail2, AND THAT IS DELIBERATE. It was, and
# 'rmscn_fail' is a prefix of it - so every substring test naming one member
# matched inside the other's name and could not fail for the defect it named.
# The same slip was found in qtestsrc/SCAPI.TEST.RPGLE's staged pair. No staged
# name here is a prefix or a substring of any other staged name, in either
# direction, and that is a rule this file relies on rather than a tidiness.
FAIL2=rmscn_second; FAIL2_F='India Nine Narrate'
PART=rmscn_part;  PART_F='Foxtrot Six Narrate'
FAILGROUP=rmscnfail
BADJOB=ZZNOSUCHJOB

# THE LOG-CONTENT PAIR, added when the gate on `For details, see log file at:`
# was measured properly. docs/messages.md § "The fifth state" has the table;
# what these two fixtures do is separate the two rules that had always moved
# together:
#
#   rmscn_noisy  Juliett Ten Narrate   NEVER comes up, and its start command
#                                      PRINTS ONE LINE before exiting. Not
#                                      partial, and its log has content
#   rmscn_half   Kilo Eleven Narrate   ALREADY PARTIAL on every attempt, and
#                                      its start command is silent. Partial,
#                                      and its log stays empty
#
# Between them and rmscn_fail - never up, silent start command, empty log -
# the three rows of the measured table are all present in one run, and no two
# of the three candidate rules agree on all three.
NOISY=rmscn_noisy; NOISY_F='Juliett Ten Narrate'
HALF=rmscn_half;   HALF_F='Kilo Eleven Narrate'

# A SECOND GROUP, for the member reached twice.
#
# Kept separate from $GROUP on purpose. The ordering case in stage 3 asks one
# question - is a group a plain sequence - and a member that drags a dependency
# in behind it would make that a question about two rules at once. This group
# exists to ask the second question, and nothing else is in it.
#
#   rmscn_g2base  Golf Seven Narrate    depended on by g2user
#   rmscn_g2user  Hotel Eight Narrate   depends on g2base; BOTH are members
G2BASE=rmscn_g2base; G2BASE_F='Golf Seven Narrate'
G2USER=rmscn_g2user; G2USER_F='Hotel Eight Narrate'
GROUP2=rmscnarr2

write_def() {  # short friendly port [extra yaml...]
  local short="$1" friendly="$2" port="$3"; shift 3
  {
    printf 'name: %s\n' "$friendly"
    printf 'start_cmd: %s %s/listen.py %s\n' "$PY" "$WORK" "$port"
    printf 'check_alive: %s\n' "$port"
    printf 'startup_wait_time: 20\n'
    printf 'stop_wait_time: 10\n'
    local line; for line in "$@"; do printf '%s\n' "$line"; done
  } > "$SVCDIR/$short.yaml"
}

write_def "$SOLO"  "$SOLO_F"  "$PORT_SOLO"  'groups:' "  - $GROUP"
write_def "$DEP"   "$DEP_F"   "$PORT_DEP"
write_def "$TOP"   "$TOP_F"   "$PORT_TOP"   'service_dependencies:' "  - $DEP"
write_def "$OTHER" "$OTHER_F" "$PORT_OTHER" 'groups:' "  - $GROUP"
write_def "$G2BASE" "$G2BASE_F" "$PORT_G2BASE" 'groups:' "  - $GROUP2"
write_def "$G2USER" "$G2USER_F" "$PORT_G2USER" 'groups:' "  - $GROUP2" \
          'service_dependencies:' "  - $G2BASE"

# rmscn_fail and rmscn_part do not go through write_def: one needs a start
# command that binds nothing, and the other needs two criteria on one line.
# startup_wait_time is 2 and 5 rather than 20, because both of these are
# WAITED OUT on every run and the default would put a minute of dead time into
# the middle of the script.
{
  printf 'name: %s\n' "$FAIL_F"
  printf 'start_cmd: %s %s/nobind.py\n' "$PY" "$WORK"
  printf 'check_alive: %s\n' "$PORT_FAIL"
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 5\n'
  printf 'groups:\n  - %s\n' "$FAILGROUP"
} > "$SVCDIR/$FAIL.yaml"

{
  printf 'name: %s\n' "$FAIL2_F"
  printf 'start_cmd: %s %s/nobind.py\n' "$PY" "$WORK"
  printf 'check_alive: %s\n' "$PORT_FAIL2"
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 5\n'
  printf 'groups:\n  - %s\n' "$FAILGROUP"
} > "$SVCDIR/$FAIL2.yaml"

# NEVER RUNS, AND SAYS ONE THING WHILE FAILING. Identical to rmscn_fail in
# every respect that any rule about this line could depend on - it never comes
# up, it is never partial, it times out and it exits 253 - except that its
# start command writes a line, which ends up in its log.
{
  printf 'name: %s\n' "$NOISY_F"
  printf 'start_cmd: %s %s/noisy.py\n' "$PY" "$WORK"
  printf 'check_alive: %s\n' "$PORT_NOISY"
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$NOISY.yaml"

# ALREADY PARTIAL, AND SILENT WHILE FAILING. Two criteria: a port this script's
# own listener holds, and a job name that never exists. It is therefore PARTIAL
# before either implementation has been asked to do anything, and stays partial
# however often it is started - and because its own start command binds nothing
# and prints nothing, its log stays EMPTY on every attempt.
#
# WHY NOT REUSE rmscn_part FOR THIS. rmscn_part's start command is the port
# listener, so on the second attempt the port is already held, python fails to
# bind and prints a traceback - into the log. That is exactly the fixture that
# moved two things at once and made the partial-state reading look measured:
# the service became partial and its log gained content on the same attempt.
# Separating them needs a partial service that stays quiet, which is this one.
{
  printf 'name: %s\n' "$HALF_F"
  printf 'start_cmd: /QOpenSys/usr/bin/sleep 30\n'
  printf 'check_alive: %s, %s\n' "$PORT_HALFOK" "$BADJOB"
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$HALF.yaml"

# TWO CRITERIA, one satisfiable and one not - `check_alive: <port>, ZZNOSUCHJOB`
# is the shape the gap probe used, and the job name is the one from that run
# rather than an invented one, so the suffix this produces is the suffix
# docs/messages.md recorded.
{
  printf 'name: %s\n' "$PART_F"
  printf 'start_cmd: %s %s/listen.py %s\n' "$PY" "$WORK" "$PORT_PART"
  printf 'check_alive: %s, %s\n' "$PORT_PART" "$BADJOB"
  printf 'startup_wait_time: 5\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$PART.yaml"

# ---------------------------------------------------------------------------
# Teardown. Removing the work directory is not enough: a started listener
# outlives the definition it came from and holds its port. Killing by the work
# directory PATH rather than by the script name means a listener belonging to
# some other work is left alone - the same care tools/d2-probe.sh takes.
# ---------------------------------------------------------------------------
kill_listeners() {
  local d="$1" p
  # Both helper scripts, and nothing else under $WORK: an upstream `sc` carries
  # -Dservices.dir=$WORK/services on its command line, and a bare "$d/" match
  # would kill the reference implementation mid-run.
  for p in $(ps -ef 2>/dev/null | grep -E "$d/(listen|nobind|noisy)\.py" | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}

cleanup() {
  local s
  for s in "$TOP" "$DEP" "$SOLO" "$OTHER" "$G2USER" "$G2BASE" "$PART" "$FAIL" \
           "$FAIL2" "$NOISY" "$HALF"; do
    SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$s" >/dev/null 2>&1
  done
  kill_listeners "$WORK"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}
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

if [ -n "${NARRATE_DRY:-}" ]; then
  echo "narration-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

# THE ONE LISTENER THIS SCRIPT OWNS DIRECTLY.
#
# Every other port in this file is bound by a service's own start command, run
# by whichever implementation is under test. This one is not: rmscn_half has to
# be PARTIAL without anything having started it and without its own start
# command ever binding anything, so the satisfied half of its criterion is held
# by a process of this script's. It is killed by kill_listeners with the rest.
# WAITED FOR, NOT SLEPT THROUGH. This was `sleep 2`, which is an estimate of
# how long Python takes to start and bind rather than a check that it has.
#
# It cost a day. On 7 September, under a loaded box - narration took 17:29
# against a normal 10:00 - two seconds was not enough, the listener had not
# bound when rmscn_half was checked, the service read NOT RUNNING instead of
# PARTIAL, and `half-log-detail` failed on its precondition with `sc:sc-half`
# skipped behind it. On a quiet box the same code passes 65/0/0, so it looked
# like a defect in the day's work rather than a race that had been sitting here
# since the harness was written.
#
# That is the same class as the flaky suites fixed the day before: a fixture
# whose precondition is timing-dependent, green when the machine is idle and
# red when it is not. The cure is the same too - stop asserting the stability
# of something you have not confirmed.
# The second argument is the readiness file. The staged services call this same
# script WITHOUT it, so they stay silent and their logs stay empty.
rm -f "$WORK/half.ready" "$WORK/half.log"
"$PY" "$WORK/listen.py" "$PORT_HALFOK" "$WORK/half.ready" > "$WORK/half.log" 2>&1 &
HALF_LISTENER=$!

half_ready=false
for _ in $(seq 1 200); do
  if grep -q '^READY' "$WORK/half.ready" 2>/dev/null; then half_ready=true; break; fi
  # NO EARLY EXIT ON A DEAD LISTENER, deliberately. The obvious check is
  # `kill -0`, and it does not work here: a background child that has exited
  # stays a zombie until it is reaped, and kill -0 succeeds on a zombie. So a
  # listener dying on bind() in 50ms would still run this loop to its end.
  #
  # `wait -n "$HALF_LISTENER"` reaps properly, but BLOCKS until the process
  # exits - which for a healthy listener is ten minutes, so it would hang the
  # very loop it was meant to shorten. That was written here and removed.
  #
  # The loop is bounded at twenty seconds and the diagnostic below carries the
  # listener's own output either way, so a dead listener costs twenty seconds
  # on a path that is already failing. That is cheaper than a reliable
  # zombie test, and it cannot be subtly wrong.
  sleep 0.1
done

if [ "$half_ready" != true ]; then
  setup_fail \
    "the listener holding port $PORT_HALFOK never reported READY." \
    "" \
    "$HALF ($HALF_F) is checked on that port AND on a job that cannot exist, so" \
    "it is PARTIAL only while this listener is up. Without it the service reads" \
    "NOT RUNNING, its case fails on the precondition, and the case behind it is" \
    "skipped - which is a believable red pointing at the wrong thing entirely." \
    "" \
    "what the listener said: $(tr '\n' ' ' < "$WORK/half.log" 2>/dev/null)"
fi

pass=0; failed=0; refdrift=0; skipped=0

# ---------------------------------------------------------------------------
# The service log, which is the gate on one line and therefore a fixture
#
# `For details, see log file at: <path>` is printed when the log file HAS
# CONTENT - see docs/messages.md - so for the three cases that separate that
# rule the log's size before and after a run is evidence and has to be handled
# like any other fixture.
#
# RMSC APPENDS TO THE LOG RATHER THAN TRUNCATING IT. Measured 4 September 2026:
# a start command printing 36 bytes leaves a 36-byte log on the first attempt
# and a 72-byte one on the second. So a log left behind by an EARLIER RUN of
# this script is content, and the service that must print no log-file line
# would print one - a fixture failure that looks exactly like a defect. Every
# case below therefore resets the log before the run it measures.
RMSC_LOGS="$HOME/.sc/logs"
log_reset() { rm -f "$RMSC_LOGS/$1.log"; }
log_bytes() { if [ -f "$RMSC_LOGS/$1.log" ]; then wc -c < "$RMSC_LOGS/$1.log" | tr -d ' '; else echo 0; fi; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# wc -l undercounts a final line with no trailing newline. grep -c '' does not.
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-32s %s\n' "$verdict" "$tag" "$*"
}

detail() { printf '  %-9s %-32s   - %s\n' "" "" "$*"; }

fail_case() {  # tag basis problem...
  local tag="$1" basis="$2"; shift 2
  report FAIL "$tag" "($basis)"
  local p; for p in "$@"; do detail "$p"; done
  failed=$((failed+1))
}

# WHOLE-LINE, BYTE-EXACT matching throughout. `grep -Fx` is what makes a
# trailing space a difference, which is the entire reason it is used here rather
# than a substring match: docs/messages.md's narration lines were transcribed
# into markdown prose, and markdown does not preserve a trailing space. The
# expectations below therefore assert that there is none, and stage 4 asks
# upstream whether that is true.
n_exact() { grep -Fxc -- "$2" "$1" 2>/dev/null || true; }
has_exact() { grep -Fqx -- "$2" "$1" 2>/dev/null; }

# 1-based index of the first line exactly equal to $2, or 0.
idx_exact() {
  local n
  n=$(grep -Fxn -- "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1)
  [ -n "$n" ] || n=0
  echo "$n"
}

# A line a column-parsing consumer would accept AS A SERVICE ROW. Same pattern
# as tools/error-delivery-test.sh, and used here for the opposite purpose: there
# it asks whether every stdout line IS a row, here whether any narration line
# could be MISTAKEN for one.
CHECK_ROW='^  .{18} \| .*\(.*\)'

# Every sentence in the family, as a pattern, for the cases that ask whether
# narration appeared where it should not.
NARRATION="^Performing operation |^Service '.*' (successfully|is already) |^Attempting to (start service dependency|stop dependent service) "

# scr_run TAG -- argv...   captures the two streams separately, returns the exit
# status, and leaves $WORK/TAG.out and $WORK/TAG.err behind as artefacts.
scr_run() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  local rc
  SC_SERVICES_DIR="$SVCDIR" "$SCR" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  rc=$?
  return $rc
}

# sc_run TAG -- argv...    the same for upstream.
#
# Upstream's services directory is a JVM property rather than an environment
# variable, and setting it through JAVA_TOOL_OPTIONS makes the JVM announce
# itself on STDERR. error-delivery-test.sh declines to run upstream for that
# reason - its subject IS stderr. Here the subject is STDOUT, which the
# announcement never touches, so upstream can be run against the same staged
# definitions and its stdout compared byte for byte. Its stderr is captured too
# and filtered, so that a genuine upstream error is still visible in the
# artefacts.
sc_run() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  local rc
  JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" "$@" \
    > "$WORK/sc.$tag.out" 2> "$WORK/sc.$tag.err.raw"
  rc=$?
  grep -v 'Picked up' "$WORK/sc.$tag.err.raw" > "$WORK/sc.$tag.err" 2>/dev/null
  return $rc
}

# ---------------------------------------------------------------------------
# State, and the precondition discipline
#
# docs/messages.md records what it cost to skip this, and puts it in italics:
# an earlier capture appeared to show `restart` printing "successfully stopped"
# for a service that was down. It was not - the service was up, because the
# `stop` that was supposed to precede the case had silently failed. "A probe
# that does not capture its own precondition cannot tell you which question it
# answered."
#
# So every case below states the state it needs, and require_state CHECKS it and
# hard-fails the case if it is not that. A case whose precondition was not met
# is never run and never passes: an assertion about `start` from a down service,
# made against one that was up, is not evidence for anything.
# ---------------------------------------------------------------------------

# PARTIAL IS ANSWERED HERE, and it used to fall through to '?'. The
# log-content cases need a service that is partial to be RECOGNISED as partial
# - require_state's whole job is to refuse to run a case against the wrong
# starting state, and it cannot do that for a state it cannot name. The order
# matters and mirrors sc_state's: NOT RUNNING is tested first because it
# contains RUNNING, and PARTIAL carries a count immediately after it rather
# than a space.
svc_state() {  # short -> RUNNING | PARTIAL | NOT | ?
  local o
  o=$(SC_SERVICES_DIR="$SVCDIR" "$SCR" check "$1" 2>/dev/null)
  case "$o" in
    *"  NOT RUNNING "*) echo NOT ;;
    *"  PARTIAL"*)      echo PARTIAL ;;
    *"  RUNNING "*)     echo RUNNING ;;
    *)                  echo '?' ;;
  esac
}

settle() {  # short wanted   - poll, because a stop returns before the job goes
  local s="$1" want="$2" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(svc_state "$s")" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

ensure_up() {    # short
  SC_SERVICES_DIR="$SVCDIR" "$SCR" start "$1" >/dev/null 2>&1
  settle "$1" RUNNING
}
ensure_down() {  # short
  SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$1" >/dev/null 2>&1
  settle "$1" NOT
}

# require_state TAG short wanted...   pairs of short/wanted, all must hold.
# Returns non-zero and reports a FAIL if any does not.
require_state() {
  local tag="$1"; shift
  local bad=() s want got
  while [ $# -gt 0 ]; do
    s="$1"; want="$2"; shift 2
    got=$(svc_state "$s")
    [ "$got" = "$want" ] || bad+=("$s is $got, the case needs $want")
  done
  [ ${#bad[@]} -eq 0 ] && return 0
  report FAIL "$tag" "(precondition) the case was NOT RUN"
  local b; for b in "${bad[@]}"; do detail "$b"; done
  detail "a case run against the wrong starting state answers a question nobody asked"
  failed=$((failed+1))
  return 1
}

# ---------------------------------------------------------------------------
# assert_narration TAG BASIS EXPECTED_FILE -- argv...
#
# The catch-all: run the command, require exit 0, and require stdout to be
# BYTE-IDENTICAL to the expected file. That one comparison covers the trailing
# blank line, the absence of any extra line, the absence of any missing line and
# the order all at once, which is why it is worth having alongside the named
# assertions each case makes for itself.
#
# It also requires, for every case:
#   - no narration sentence on STDERR. These are reports of success on stdout,
#     not warnings; docs/messages.md § Narration is explicit that this is why -q
#     does not touch them.
#   - no stdout line that a column-parsing consumer would accept AS A ROW.
#     docs/parity.md asks for exactly this confirmation before the lines are
#     added: "that is a property of the consumer, not of the output, and is
#     worth confirming".
#
# The named assertions come first in each case and this comes last, so a
# failure names the rule that broke before it shows the diff.
# ---------------------------------------------------------------------------
assert_narration() {
  local tag="$1" basis="$2" expected="$3"; shift 3
  [ "$1" = "--" ] && shift
  local rc problems=()

  scr_run "$tag" -- "$@"; rc=$?

  [ "$rc" -eq 0 ] || problems+=("exit $rc, wanted 0")

  if ! diff -u "$expected" "$WORK/$tag.out" > "$WORK/$tag.diff" 2>&1; then
    problems+=("stdout is not byte-identical to the expectation (diff below)")
  fi

  local on_err
  on_err=$(grep -cE "$NARRATION" "$WORK/$tag.err" 2>/dev/null || true)
  [ -z "$on_err" ] && on_err=0
  [ "$on_err" -eq 0 ] || problems+=("$on_err narration line(s) on STDERR: $(grep -m1 -E "$NARRATION" "$WORK/$tag.err")")

  local rows
  rows=$(grep -cE "$CHECK_ROW" "$WORK/$tag.out" 2>/dev/null || true)
  [ -z "$rows" ] && rows=0
  [ "$rows" -eq 0 ] || problems+=("$rows narration line(s) would be ACCEPTED as a service row by a column-parsing consumer: $(grep -m1 -E "$CHECK_ROW" "$WORK/$tag.out")")

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) exit 0, $(count_lines "$WORK/$tag.out") stdout line(s), byte-exact"
    pass=$((pass+1))
    return 0
  fi

  report FAIL "$tag" "($basis)"
  local p; for p in "${problems[@]}"; do detail "$p"; done
  if [ -s "$WORK/$tag.diff" ]; then
    while IFS= read -r l; do detail "$l"; done < "$WORK/$tag.diff"
  fi
  detail "artefacts: $tag.out $tag.err"
  failed=$((failed+1))
  return 1
}

# check_named TAG BASIS PROBLEM... - a named separating assertion. Each caller
# builds its own list of problems; an empty list is a pass.
check_named() {
  local tag="$1" basis="$2" note="$3"; shift 3
  if [ $# -eq 0 ]; then
    report PASS "$tag" "($basis) $note"
    pass=$((pass+1))
    return 0
  fi
  fail_case "$tag" "$basis" "$@"
  return 1
}

# ---------------------------------------------------------------------------
# The expected lines, once, as variables. Every literal is a transcription from
# docs/messages.md § "Narration - the family RMSC does not have" with this
# script's fixture names substituted in.
# ---------------------------------------------------------------------------
p_start_solo="Performing operation 'START' on service '$SOLO'"
p_stop_solo="Performing operation 'STOP' on service '$SOLO'"
p_kill_solo="Performing operation 'KILL' on service '$SOLO'"
p_restart_solo="Performing operation 'RESTART' on service '$SOLO'"
p_start_top="Performing operation 'START' on service '$TOP'"
p_stop_dep="Performing operation 'STOP' on service '$DEP'"
p_start_other="Performing operation 'START' on service '$OTHER'"

s_solo_started="Service '$SOLO_F' successfully started"
s_solo_stopped="Service '$SOLO_F' successfully stopped"
s_solo_running="Service '$SOLO_F' is already running"
s_solo_halted="Service '$SOLO_F' is already stopped"
s_dep_started="Service '$DEP_F' successfully started"
s_dep_stopped="Service '$DEP_F' successfully stopped"
s_dep_running="Service '$DEP_F' is already running"
s_top_started="Service '$TOP_F' successfully started"
s_top_stopped="Service '$TOP_F' successfully stopped"
s_other_started="Service '$OTHER_F' successfully started"

d_start_dep="Attempting to start service dependency '$DEP' ($DEP_F)..."
d_stop_top="Attempting to stop dependent service '$TOP_F'..."

# expect FILE LINE...   writes an expected-stdout file, with the single trailing
# blank line docs/messages.md records after a command that exits 0.
expect() {
  local f="$1"; shift
  local l; : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
  printf '\n' >> "$f"
}

# expect_nb FILE LINE...   the same, with NO trailing blank line.
#
# THE TWO WRITERS ARE THE RULE, ENCODED. Re-measured 3 September 2026: upstream
# ends a command's stdout with one blank line when the command EXITS 0 and with
# none when it does not. Every expectation for a command that failed is built
# with this one, and every expectation for a command that succeeded with the one
# above, so the difference is visible at the call site rather than buried in a
# count. See stage 3b's fail-blank-line-asymmetry case for the measurement and
# for the two rival rules it rules out.
expect_nb() {
  local f="$1"; shift
  local l; : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
}

printf 'narration: which stream, in what order, with what blank line\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s\n' "$SC"
printf 'staged in: %s   (ports %s %s %s %s)\n\n' \
  "$SVCDIR" "$PORT_SOLO" "$PORT_DEP" "$PORT_TOP" "$PORT_OTHER"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture proves itself"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------

# (a) SC_SERVICES_DIR WAS READ AT ALL.
#
# Everything below is staged through it, and the failure mode of staging is that
# it silently does not take effect and every case then passes while testing
# nothing. Proved from `check group:`, whose stdout rows ARE the evidence and
# are not moved by anything this change does - the same shape, and the same
# reasoning, as error-delivery-test.sh's group guard.
scr_run fixture-group -- check "group:$GROUP"
gm=$(grep -c "rmscn_" "$WORK/fixture-group.out" 2>/dev/null || true)
[ -z "$gm" ] && gm=0
if [ "$gm" -ne 2 ]; then
  report FAIL staged-definitions "FIXTURE DID NOT TAKE: group:$GROUP has $gm member(s), wanted 2"
  detail "SC_SERVICES_DIR=$SVCDIR was not read, or the definitions did not load"
  detail "nothing below this line is evidence for anything"
  detail "artefacts: fixture-group.out fixture-group.err"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed"
  echo "FAILED: the fixture did not stage"
  exit 1
fi
report PASS staged-definitions "(fixture) group:$GROUP has both members"
pass=$((pass+1))

# (b) THE SERVICE ACTUALLY COMES UP.
#
# The lesson tools/d2-probe.sh had to learn twice and wrote into its own
# comments: "A bare `sleep` with a port criterion can never satisfy that
# criterion". If the listener does not bind, `start` still prints something -
# upstream's timeout wording - and every "successfully started" case below would
# be asserting against a message about failure. That failure is invisible from
# inside a case, so it is proved once, here, before any case runs.
#
# HARD FAILURE, NOT A SKIP. CLAUDE.md: a suite that passes because its fixture
# is absent is worse than one that fails, because it reports success.
if ensure_up "$SOLO"; then
  report PASS staged-service-comes-up "(fixture) $SOLO reaches RUNNING, so 'successfully started' is reachable"
  pass=$((pass+1))
else
  report FAIL staged-service-comes-up "FIXTURE DID NOT TAKE: $SOLO never reached RUNNING"
  detail "the listener did not bind port $PORT_SOLO, or the start never happened"
  detail "every 'successfully started' case below would be capturing upstream's"
  detail "TIMEOUT wording under the heading 'success'. Nothing below is evidence."
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed"
  echo "FAILED: the staged service does not come up"
  exit 1
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 1: one service, no dependencies - the four states and the four verbs"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------

# --- start, from up: the no-op form ----------------------------------------
#
# Taken first because the fixture proof above has just left the service RUNNING,
# so this case's precondition is already established rather than manufactured.
#
# SEPARATING VALUE: `is already running` present AND `successfully started`
# ABSENT. The rival rule is "the outcome line always reports the state the
# operation was aiming at", which an implementation that printed its intent
# rather than its result would satisfy, and which the first assertion alone
# cannot tell apart from the real one.
if require_state start-already "$SOLO" RUNNING; then
  expect "$WORK/e.start-already" "$p_start_solo" "$s_solo_running"
  assert_narration start-already measured "$WORK/e.start-already" -- start "$SOLO"

  probs=()
  has_exact "$WORK/start-already.out" "$s_solo_running" \
    || probs+=("no 'is already running' line")
  [ "$(n_exact "$WORK/start-already.out" "$s_solo_started")" -eq 0 ] \
    || probs+=("'successfully started' printed for a service that was already up")
  check_named start-already-not-a-success measured \
    "the no-op line, and not the success line" "${probs[@]}"
fi

# --- the progress line names the SHORT name, the state line the FRIENDLY one --
#
# THE RULE THIS SCRIPT EXISTS FOR, and the one qtestsrc/SCOUT.TEST.RPGLE cannot
# reach. docs/messages.md § "The two whole-surface differences": "RMSC names a
# service by its short name where upstream names it by its friendly name.
# Upstream's progress line uses the SHORT name and its status and error lines
# use the FRIENDLY name; RMSC uses the short name throughout."
#
# Four separating values, each ruling out a rule that would satisfy the others:
#
#   friendly ABSENT from the progress line   rules out "name it by the friendly
#                                            name everywhere", and "short
#                                            (friendly)" on the progress line
#   short PRESENT on the progress line       rules out the reverse mix-up
#   short ABSENT from the state line         rules out RMSC's own present habit
#                                            of using the short name throughout
#   friendly PRESENT on the state line       rules out dropping the name
#
# The fixture names make all four meaningful: 'rmscn_solo' and 'Alpha One
# Narrate' share no substring, so none of these greps can match by accident.
probs=()
pl=$(grep -F "Performing operation" "$WORK/start-already.out" | head -n 1)
sl=$(grep -F "Service '" "$WORK/start-already.out" | head -n 1)
[ -n "$pl" ] || probs+=("no progress line at all")
[ -n "$sl" ] || probs+=("no state line at all")
if [ -n "$pl" ]; then
  case "$pl" in *"$SOLO"*) ;; *) probs+=("the progress line does not carry the short name '$SOLO': $pl") ;; esac
  case "$pl" in *"$SOLO_F"*) probs+=("the progress line carries the FRIENDLY name '$SOLO_F', which upstream's does not: $pl") ;; esac
fi
if [ -n "$sl" ]; then
  case "$sl" in *"$SOLO_F"*) ;; *) probs+=("the state line does not carry the friendly name '$SOLO_F': $sl") ;; esac
  case "$sl" in *"$SOLO"*) probs+=("the state line carries the SHORT name '$SOLO' - this is RMSC naming a service its own way, the difference docs/messages.md raises first: $sl") ;; esac
fi
check_named short-then-friendly measured \
  "progress by short name, state by friendly name" "${probs[@]}"

# --- stop, from up: the success form ---------------------------------------
#
# SEPARATING VALUE: the verb in the progress line is STOP. An implementation
# that rendered a constant, or the last verb it happened to hold, would pass
# every start case and fail here - which is why the verb is asserted per case
# and not once.
if require_state stop-success "$SOLO" RUNNING; then
  expect "$WORK/e.stop-success" "$p_stop_solo" "$s_solo_stopped"
  assert_narration stop-success measured "$WORK/e.stop-success" -- stop "$SOLO"

  probs=()
  has_exact "$WORK/stop-success.out" "$p_stop_solo" \
    || probs+=("the progress line does not say STOP")
  [ "$(n_exact "$WORK/stop-success.out" "$p_start_solo")" -eq 0 ] \
    || probs+=("the progress line says START for a stop")
  check_named stop-names-its-own-verb measured "the verb follows the operation" "${probs[@]}"
fi

# --- stop, from down: the other no-op form ---------------------------------
if require_state stop-already "$SOLO" NOT; then
  expect "$WORK/e.stop-already" "$p_stop_solo" "$s_solo_halted"
  assert_narration stop-already measured "$WORK/e.stop-already" -- stop "$SOLO"
fi

# --- kill, from down -------------------------------------------------------
#
# THE COUNTER-INTUITIVE ONE, and docs/messages.md states it in bold: "`kill` on
# a stopped service says `is already stopped`, exactly as `stop` does - it does
# not say `ERROR: No running jobs for service '%s'`. Where that message comes
# from is still unmeasured; it is in the jar's catalogue but nothing probed
# reaches it."
#
# SEPARATING VALUE: the absence of `No running jobs` on EITHER stream. The rival
# rule is the one an implementer reading the jar's message catalogue would pick,
# and it is a rule about a message this run must not produce - so it has to be
# asserted as an absence, and asserted on both streams, or a copy that moved to
# stderr would satisfy it.
#
# The progress line's verb is COMPOSED: docs/messages.md quotes the progress
# sentence for START and STOP and never for KILL. Stage 4 measures it.
if require_state kill-already "$SOLO" NOT; then
  expect "$WORK/e.kill-already" "$p_kill_solo" "$s_solo_halted"
  assert_narration kill-already composed "$WORK/e.kill-already" -- kill "$SOLO"

  probs=()
  has_exact "$WORK/kill-already.out" "$s_solo_halted" \
    || probs+=("kill on a stopped service does not say 'is already stopped'")
  n=$(cat "$WORK/kill-already.out" "$WORK/kill-already.err" 2>/dev/null | grep -Fc 'No running jobs' || true)
  [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] || probs+=("$n line(s) say 'No running jobs' - that message is unmeasured and nothing probed reaches it upstream")
  check_named kill-is-stop-shaped composed \
    "kill on a stopped service narrates as stop does" "${probs[@]}"
fi

# --- start, from down: the success form ------------------------------------
if require_state start-success "$SOLO" NOT; then
  expect "$WORK/e.start-success" "$p_start_solo" "$s_solo_started"
  assert_narration start-success measured "$WORK/e.start-success" -- start "$SOLO"

  # THE TRAILING BLANK LINE, as its own named question.
  #
  # docs/messages.md: "All on stdout, exit 0, with one trailing blank line after
  # each command." The byte-exact comparison above already covers it, but a
  # blank line is the thing a diff reports least legibly, so it is stated here
  # too - and stated as EXACTLY ONE.
  #
  # SEPARATING VALUES: the last line is blank, ruling out none; and the
  # second-to-last is not, ruling out two. `check` already ends in a blank line
  # and fixtures/check.txt pins it, so "one" is the number that makes narration
  # consistent with the rest of the output rather than a number chosen freely.
  probs=()
  n=$(count_lines "$WORK/start-success.out")
  if [ "$n" -lt 2 ]; then
    probs+=("only $n stdout line(s) - there is nothing to say about a trailing blank")
  else
    [ -z "$(sed -n "${n}p" "$WORK/start-success.out")" ] \
      || probs+=("the last line is not blank: $(sed -n "${n}p" "$WORK/start-success.out")")
    [ -n "$(sed -n "$((n-1))p" "$WORK/start-success.out")" ] \
      || probs+=("the second-to-last line is blank too - that is two trailing blanks, not one")
  fi
  check_named one-trailing-blank measured "exactly one blank line at the end" "${probs[@]}"
fi

# --- restart, from up ------------------------------------------------------
#
# docs/messages.md: "restart, from up - one RESTART progress line, then
# `successfully stopped`, then `successfully started`" and "`restart` has no
# special case of its own. It is `stop`'s narration followed by `start`'s, under
# one RESTART progress line".
#
# SEPARATING VALUE: EXACTLY ONE progress line. The natural implementation of
# restart is to call stop and then start, and the natural consequence of that is
# THREE progress lines - RESTART, STOP, START - or two. Counting them is what
# tells "under one progress line" apart from "stop's narration followed by
# start's" read literally, and the count is the only value that can.
if require_state restart-from-up "$SOLO" RUNNING; then
  expect "$WORK/e.restart-up" "$p_restart_solo" "$s_solo_stopped" "$s_solo_started"
  assert_narration restart-from-up measured "$WORK/e.restart-up" -- restart "$SOLO"

  probs=()
  n=$(grep -c "^Performing operation " "$WORK/restart-from-up.out" 2>/dev/null || true)
  [ -z "$n" ] && n=0
  [ "$n" -eq 1 ] || probs+=("$n progress line(s), wanted exactly 1 - restart narrates under ONE, not one per sub-operation")
  has_exact "$WORK/restart-from-up.out" "$p_restart_solo" \
    || probs+=("the one progress line does not say RESTART")
  a=$(idx_exact "$WORK/restart-from-up.out" "$s_solo_stopped")
  b=$(idx_exact "$WORK/restart-from-up.out" "$s_solo_started")
  [ "$a" -gt 0 ] || probs+=("no 'successfully stopped' line")
  [ "$b" -gt 0 ] || probs+=("no 'successfully started' line")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -ge "$b" ]; then
    probs+=("'successfully started' (line $b) comes before 'successfully stopped' (line $a)")
  fi
  check_named restart-one-progress-line measured \
    "one RESTART progress line, stopped then started" "${probs[@]}"
fi

# --- restart, from down ----------------------------------------------------
#
# docs/messages.md: "restart, from down - one RESTART progress line, then
# **`is already stopped`**, then `successfully started`", and the italicised
# paragraph beneath it recording that an earlier capture appeared to show
# `successfully stopped` here and was wrong because the precondition had not
# held.
#
# TWO SEPARATING VALUES, each ruling out a different plausible rival:
#
#   'is already stopped' PRESENT     rules out "restart on a down service just
#                                    starts it" - the obvious implementation,
#                                    which prints two lines rather than three
#   'successfully stopped' ABSENT    rules out the mis-capture the document
#                                    itself records having made. That reading
#                                    would have been "a quirk worth copying",
#                                    so it is not a straw man: it is what this
#                                    project believed for a while.
#
# And this case's own precondition is checked before it runs, which is exactly
# what the mis-capture lacked.
ensure_down "$SOLO" >/dev/null 2>&1
if require_state restart-from-down "$SOLO" NOT; then
  expect "$WORK/e.restart-down" "$p_restart_solo" "$s_solo_halted" "$s_solo_started"
  assert_narration restart-from-down measured "$WORK/e.restart-down" -- restart "$SOLO"

  probs=()
  has_exact "$WORK/restart-from-down.out" "$s_solo_halted" \
    || probs+=("no 'is already stopped' line - restart does not skip the stop side when there is nothing to stop")
  [ "$(n_exact "$WORK/restart-from-down.out" "$s_solo_stopped")" -eq 0 ] \
    || probs+=("'successfully stopped' printed for a service that was already down - this is the mis-capture docs/messages.md records, arriving as real behaviour")
  has_exact "$WORK/restart-from-down.out" "$s_solo_started" \
    || probs+=("no 'successfully started' line")
  check_named restart-down-still-stops measured \
    "already-stopped, then started" "${probs[@]}"
fi

ensure_down "$SOLO" >/dev/null 2>&1

echo
# ---------------------------------------------------------------------------
echo "== stage 2: dependencies - the two lines that are not symmetrical"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------

ensure_down "$TOP" >/dev/null 2>&1
ensure_down "$DEP" >/dev/null 2>&1

# --- start a parent whose dependency must be started -----------------------
#
# docs/messages.md, quoted whole because this case is a transcription of it:
#
#     Performing operation 'START' on service 'rmscd2_parent'
#     Attempting to start service dependency 'rmscd2_depsvc' (RMSC D2 depsvc)...
#     Service 'RMSC D2 depsvc' successfully started
#     Service 'RMSC D2 parent' successfully started
#
# "Every service in the walk gets its own outcome line, dependencies included.
# Starting a service whose dependency must be started first prints four lines,
# not two."
#
# SEPARATING VALUES:
#
#   exactly ONE progress line          rules out the dependency being handled as
#                                      a nested operation with a progress line
#                                      of its own, which is what "performing an
#                                      operation on it" would suggest
#   the dependency's OWN outcome line  rules out "the outcome line belongs to
#                                      the service that was named" - the reading
#                                      docs/messages.md corrects in bold
#   dep outcome BEFORE parent outcome  rules out the walk reporting the named
#                                      service first
#   short name inside the quotes AND   rules out the stop side's shape being
#   friendly inside the parentheses    reused here, which is the mistake the
#                                      document says an implementer will make
if require_state deps-start "$TOP" NOT "$DEP" NOT; then
  expect "$WORK/e.deps-start" "$p_start_top" "$d_start_dep" "$s_dep_started" "$s_top_started"
  assert_narration deps-start measured "$WORK/e.deps-start" -- start "$TOP"

  probs=()
  n=$(grep -c "^Performing operation " "$WORK/deps-start.out" 2>/dev/null || true)
  [ -z "$n" ] && n=0
  [ "$n" -eq 1 ] || probs+=("$n progress line(s), wanted exactly 1 - a dependency does not get one of its own")
  has_exact "$WORK/deps-start.out" "$d_start_dep" \
    || probs+=("no dependency line, or not in the '<short>' (<friendly>)... shape")
  dl=$(grep -F 'Attempting to start' "$WORK/deps-start.out" | head -n 1)
  if [ -n "$dl" ]; then
    case "$dl" in *"'$DEP'"*) ;; *) probs+=("the dependency line does not quote the SHORT name '$DEP': $dl") ;; esac
    case "$dl" in *"($DEP_F)"*) ;; *) probs+=("the dependency line does not parenthesise the FRIENDLY name '$DEP_F': $dl") ;; esac
    case "$dl" in *...) ;; *) probs+=("the dependency line does not end in three dots: $dl") ;; esac
  fi
  a=$(idx_exact "$WORK/deps-start.out" "$s_dep_started")
  b=$(idx_exact "$WORK/deps-start.out" "$s_top_started")
  [ "$a" -gt 0 ] || probs+=("the dependency gets no outcome line of its own")
  [ "$b" -gt 0 ] || probs+=("the named service gets no outcome line")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -ge "$b" ]; then
    probs+=("the named service's outcome (line $b) comes before the dependency's (line $a)")
  fi
  check_named deps-start-walks-and-reports measured \
    "one progress line, four lines, dependency reported first" "${probs[@]}"
fi

# --- start a parent whose dependency is ALREADY RUNNING --------------------
#
# THE OTHER COUNTER-INTUITIVE ONE, and docs/messages.md gives it a heading:
# "The dependency line is unconditional. It is printed even when the dependency
# is already running and nothing is done. ... It announces that a dependency is
# being CONSIDERED, not that work is being done - which is the opposite of what
# the wording suggests, and the reading an implementer would naturally take."
#
# SEPARATING VALUE: the presence of `Attempting to start service dependency` in
# a run where the dependency was untouched. The rival rule - print it when the
# dependency is actually started - agrees with the case above on every line and
# disagrees only here. There is no other value that tells them apart, which is
# why this case exists separately from deps-start rather than being folded into
# it.
#
# The precondition is the whole case: parent DOWN, dependency UP.
ensure_down "$TOP" >/dev/null 2>&1
if require_state deps-already-up "$TOP" NOT "$DEP" RUNNING; then
  expect "$WORK/e.deps-up" "$p_start_top" "$d_start_dep" "$s_dep_running" "$s_top_started"
  assert_narration deps-already-up measured "$WORK/e.deps-up" -- start "$TOP"

  probs=()
  has_exact "$WORK/deps-already-up.out" "$d_start_dep" \
    || probs+=("no dependency line for a dependency that was already running - the line is unconditional, it announces that the dependency is being CONSIDERED")
  has_exact "$WORK/deps-already-up.out" "$s_dep_running" \
    || probs+=("the dependency gets no 'is already running' line of its own")
  check_named dep-line-is-unconditional measured \
    "announced even though nothing was done" "${probs[@]}"
fi

# --- stop a dependency while its dependent is up ---------------------------
#
# THE ASYMMETRY. docs/messages.md: "The two dependency lines are not
# symmetrical. The start side names the service twice, short then friendly in
# parentheses; the stop side names it once, friendly only. That is upstream's
# behaviour, not a transcription slip, and anyone implementing this from the
# table above will get it wrong by making them match."
#
# SEPARATING VALUES, each ruling out one way of making them match:
#
#   '$TOP' ABSENT from the line     rules out '<short>' (<friendly>)... and
#                                   '<short>'... - the two shapes that would
#                                   follow from symmetry
#   no '(' on the line              rules out the parenthesised form even if
#                                   the short name were dropped
#   'dependent' present and         rules out the start side's noun surviving
#   'dependency' absent             the copy, which is the subtler half of the
#                                   same mistake and would otherwise read fine
#
# The fixture's friendly names carry no parenthesis of their own, so the second
# of those is a question about the FORMAT and not about the name.
#
# BASIS: the sentence is measured - docs/messages.md's group-stop transcript has
# `Attempting to stop dependent service 'RMSC D2 labels'...` - but that
# transcript shows it followed by `is already stopped`, whereas here the
# dependent really is up, so the outcome lines are COMPOSED. Stage 4 measures
# this exact sequence.
ensure_up "$TOP" >/dev/null 2>&1
if require_state deps-stop "$TOP" RUNNING "$DEP" RUNNING; then
  expect "$WORK/e.deps-stop" "$p_stop_dep" "$d_stop_top" "$s_top_stopped" "$s_dep_stopped"
  assert_narration deps-stop composed "$WORK/e.deps-stop" -- stop "$DEP"

  probs=()
  has_exact "$WORK/deps-stop.out" "$d_stop_top" \
    || probs+=("no dependent line, or not in the friendly-name-only shape")
  dl=$(grep -F 'Attempting to stop' "$WORK/deps-stop.out" | head -n 1)
  if [ -n "$dl" ]; then
    case "$dl" in *"$TOP"*) probs+=("the dependent line carries the SHORT name '$TOP' - the stop side names the service once, friendly only: $dl") ;; esac
    case "$dl" in *"("*) probs+=("the dependent line carries a parenthesis - that is the START side's shape: $dl") ;; esac
    case "$dl" in *dependency*) probs+=("the dependent line says 'dependency' - the stop side's noun is 'dependent': $dl") ;; esac
    case "$dl" in *dependent*) ;; *) probs+=("the dependent line does not say 'dependent': $dl") ;; esac
    case "$dl" in *...) ;; *) probs+=("the dependent line does not end in three dots: $dl") ;; esac
  fi
  # And the two lines really are different lines, in one run each.
  if has_exact "$WORK/deps-start.out" "$d_start_dep" && [ -n "$dl" ]; then
    sl=$(grep -F 'Attempting to start' "$WORK/deps-start.out" | head -n 1)
    [ "$sl" != "$dl" ] || probs+=("the start-side and stop-side dependency lines are identical")
  fi
  a=$(idx_exact "$WORK/deps-stop.out" "$s_top_stopped")
  b=$(idx_exact "$WORK/deps-stop.out" "$s_dep_stopped")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -ge "$b" ]; then
    probs+=("the named service's outcome (line $b) comes before its dependent's (line $a) - a stop walks dependents first")
  fi
  check_named dep-stop-is-not-symmetrical composed \
    "friendly name only, no parentheses, 'dependent' not 'dependency'" "${probs[@]}"
fi

ensure_down "$TOP" >/dev/null 2>&1
ensure_down "$DEP" >/dev/null 2>&1

echo
# ---------------------------------------------------------------------------
echo "== stage 3: a group, -q, and the operations that must stay silent"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------

# --- a group start is a plain sequence -------------------------------------
#
# docs/messages.md: "Ordering within a group is plain sequence, one member fully
# handled before the next begins. The progress line comes from the dispatcher,
# the rest from the worker as it walks." And the italicised note beneath it:
# "This paragraph first said the progress lines came first and the dependency
# line arrived out of turn. That was an artefact of reading the two streams
# apart."
#
# SEPARATING VALUE: each member's outcome line falls BETWEEN its own progress
# line and the next progress line. The rival rule is the one this project
# briefly believed - all the progress lines first, then the outcomes - and it
# agrees with "both lines are present" on every value except this one.
#
# ORDER-AGNOSTIC BETWEEN MEMBERS. Which member is handled first is not asserted:
# nothing measured says, and a rule about the order two staged definitions come
# back from a directory walk would be pinning this machine rather than either
# implementation.
ensure_down "$SOLO" >/dev/null 2>&1
ensure_down "$OTHER" >/dev/null 2>&1
if require_state group-start "$SOLO" NOT "$OTHER" NOT; then
  scr_run group-start -- start "group:$GROUP"; g_rc=$?
  o="$WORK/group-start.out"

  probs=()
  [ "$g_rc" -eq 0 ] || probs+=("exit $g_rc, wanted 0")
  n=$(grep -c "^Performing operation " "$o" 2>/dev/null || true)
  [ -z "$n" ] && n=0
  [ "$n" -eq 2 ] || probs+=("$n progress line(s), wanted one per member (2)")

  p_solo=$(idx_exact "$o" "$p_start_solo")
  p_other=$(idx_exact "$o" "$p_start_other")
  o_solo=$(idx_exact "$o" "$s_solo_started")
  o_other=$(idx_exact "$o" "$s_other_started")
  [ "$p_solo"  -gt 0 ] || probs+=("no progress line for $SOLO")
  [ "$p_other" -gt 0 ] || probs+=("no progress line for $OTHER")
  [ "$o_solo"  -gt 0 ] || probs+=("no outcome line for $SOLO_F")
  [ "$o_other" -gt 0 ] || probs+=("no outcome line for $OTHER_F")

  # Each member's outcome must follow its own progress line and precede the
  # other member's progress line, whichever order the two members come in.
  if [ "$p_solo" -gt 0 ] && [ "$p_other" -gt 0 ] && [ "$o_solo" -gt 0 ] && [ "$o_other" -gt 0 ]; then
    if [ "$p_solo" -lt "$p_other" ]; then
      first_p=$p_solo; first_o=$o_solo; second_p=$p_other; second_o=$o_other
      first_n=$SOLO;   second_n=$OTHER
    else
      first_p=$p_other; first_o=$o_other; second_p=$p_solo; second_o=$o_solo
      first_n=$OTHER;   second_n=$SOLO
    fi
    [ "$first_o" -gt "$first_p" ] \
      || probs+=("$first_n's outcome (line $first_o) comes before its own progress line (line $first_p)")
    [ "$first_o" -lt "$second_p" ] \
      || probs+=("$first_n's outcome (line $first_o) comes AFTER $second_n's progress line (line $second_p) - the members are interleaved, not handled one at a time")
    [ "$second_o" -gt "$second_p" ] \
      || probs+=("$second_n's outcome (line $second_o) comes before its own progress line (line $second_p)")
  fi

  # One trailing blank for the whole command, not one per member.
  nb=$(grep -c '^$' "$o" 2>/dev/null || true)
  [ -z "$nb" ] && nb=0
  [ "$nb" -eq 1 ] || probs+=("$nb blank line(s) in a two-member group start - the blank line follows the COMMAND, not each member")

  rows=$(grep -cE "$CHECK_ROW" "$o" 2>/dev/null || true)
  [ -z "$rows" ] && rows=0
  [ "$rows" -eq 0 ] || probs+=("$rows line(s) would be accepted as a service row by a column-parsing consumer")

  check_named group-plain-sequence measured \
    "one member fully handled before the next begins" "${probs[@]}"
fi

# --- -q does not suppress any of it ----------------------------------------
#
# docs/messages.md: "`-q` does not suppress narration. Measured on both `start`
# and `stop`, in both the success and the already-in-that-state forms. `-q` is
# documented as suppressing WARNINGS, and these are not warnings - they go to
# stdout and they report success."
#
# THIS CANNOT BE ALLOWED TO PASS ON SILENCE. The trap
# tools/error-delivery-test.sh documents twice: a case that only looks at the -q
# run would go green against an implementation that had stopped narrating
# altogether, having confirmed absence and called it non-suppression. Here the
# direction is reversed - we want the lines PRESENT - so the danger is the
# mirror image: the case would go green against an implementation that had never
# implemented -q and refused the flag. Both guards are therefore carried:
#
#   the flag must be ACCEPTED (exit 0), or silence is refusal, not suppression
#   the equivalent run WITHOUT -q must have produced narration, or there is
#   nothing to fail to suppress - and that is the case above, which has run
#
# All four forms are covered because all four were measured.
q_cases=0; q_bad=()

q_run() {  # tag expected-file -- argv...
  local tag="$1" exp="$2"; shift 2
  [ "$1" = "--" ] && shift
  local rc
  scr_run "$tag" -- "$@"; rc=$?
  q_cases=$((q_cases+1))
  if [ "$rc" -ne 0 ]; then
    q_bad+=("$tag: exit $rc - if -q was refused, silence is not suppression")
    return
  fi
  diff -u "$exp" "$WORK/$tag.out" > "$WORK/$tag.diff" 2>&1 \
    || q_bad+=("$tag: stdout under -q differs from the same command without it (see $tag.diff)")
}

# THE STAGING HALF IS CHECKED FIRST, not after the fact. All four expectations
# have to have been produced WITHOUT -q earlier in this run, or there was
# nothing to fail to suppress and a green row here would mean nothing. Checked
# against the non-quiet CAPTURES rather than the expected files, because the
# expected files exist whether or not the case that used them ran.
q_ready=1
for f in start-success start-already stop-success stop-already; do
  [ -s "$WORK/$f.out" ] && grep -q "^Performing operation " "$WORK/$f.out" 2>/dev/null \
    || q_ready=0
done

ensure_down "$SOLO" >/dev/null 2>&1
if [ "$q_ready" -eq 0 ]; then
  report SKIPPED quiet-does-not-suppress \
    "one or more of the four non-quiet cases did not narrate, so there is nothing to fail to suppress"
  skipped=$((skipped+1))
elif require_state quiet "$SOLO" NOT; then
  q_run quiet-start-success "$WORK/e.start-success" -- -q start "$SOLO"
  q_run quiet-start-already "$WORK/e.start-already" -- -q start "$SOLO"
  q_run quiet-stop-success  "$WORK/e.stop-success"  -- -q stop  "$SOLO"
  q_run quiet-stop-already  "$WORK/e.stop-already"  -- -q stop  "$SOLO"

  check_named quiet-does-not-suppress measured \
    "$q_cases forms, all four identical with -q and without" "${q_bad[@]}"
fi
ensure_down "$SOLO" >/dev/null 2>&1

# --- the read-only operations narrate on neither side ----------------------
#
# docs/parity.md: "This affects every STATE-CHANGING operation - start, stop,
# kill, restart - for a single service and for a group alike; the read-only
# operations narrate on neither side."
#
# SEPARATING VALUE: the absence of any narration sentence from `check`, `list`,
# `groups` and `info`. The rival rule is "every operation gets a progress line",
# which is a perfectly reasonable reading of "progress, every operation" in
# docs/messages.md's narration table - that row means every state-changing
# operation, and nothing in the table itself says so.
#
# THIS IS THE ASSERTION WITH THE MOST AT STAKE IN THE FILE. `check`, `list` and
# `groups` are byte-exact against fixtures/, and CLAUDE.md's first warning is
# that a slip there is silent: the consumer drops any row that does not yield
# three fields, so a stray progress line above the rows would make nothing fail
# and would make nothing visible either. fidelity-gate.sh would catch it on the
# next run; this catches it in the change that introduces it.
# AN OPERATION THAT FAILED PRINTS NOTHING, and nothing satisfies an absence
# assertion without meaning anything by it - the guard
# tools/error-delivery-test.sh puts on its unknown-key-not-on-stdout case. So
# each operation has to exit 0 and produce output before its silence counts.
ro_bad=()
ro_check() {  # tag argv...
  local tag="$1"; shift
  local rc n
  scr_run "$tag" -- "$@"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ro_bad+=("$* exits $rc, so an absence of narration in its output proves nothing")
    return
  fi
  if [ ! -s "$WORK/$tag.out" ]; then
    ro_bad+=("$* printed nothing at all, so an absence of narration in it proves nothing")
    return
  fi
  n=$(grep -cE "$NARRATION" "$WORK/$tag.out" 2>/dev/null || true)
  [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] || ro_bad+=("$* printed $n narration line(s) on stdout: $(grep -m1 -E "$NARRATION" "$WORK/$tag.out")")
}

ro_check ro-check  check
ro_check ro-list   list
ro_check ro-groups groups
ro_check ro-info   info "$SOLO"

check_named read-only-stays-silent inferred \
  "check, list, groups and info narrate nothing" "${ro_bad[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 3b: the failure side - the fifth state, and three lines nobody had seen"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------
#
# EVERY CASE IN THIS STAGE EXISTS BECAUSE A PROBE WAS MADE TO FAIL. The four
# lines below were absent from docs/messages.md until then - not marked
# unmeasured, simply absent - because every capture had watched services
# succeed. A success-path probe measures the success path.
#
# One of the four is on STDOUT, and it is the one nothing had ever seen:
#
#   For details, see log file at: <path>
#
# That is the stream a consumer parses by column position, reached only on a
# path testing does not normally take. It is the shape of CLAUDE.md's opening
# warning arriving through a door nobody was watching.

# Can upstream be driven against these definitions at all? Stage 4 proves this
# properly and refuses to run without it; this stage needs the same fact
# earlier, for the anchors at its end, so it is asked once here and the answer
# reused. A failure is not reported twice - stage 4 owns that verdict.
sc_run sc-early-group -- check "group:$GROUP"
sc_ok_early=0
[ "$(grep -c 'rmscn_' "$WORK/sc.sc-early-group.out" 2>/dev/null || echo 0)" -ge 2 ] && sc_ok_early=1

# confirm_sc is stage 4's, and this stage now uses it too - see the block just
# above the sc-fail runs at the end of this stage for why. It reads $sc_ok, so
# the early answer is put there as well; stage 4 asks the same question again
# and reports the verdict, which is where a failure is owned.
sc_ok=$sc_ok_early

# The literals. docs/messages.md gives these as TEMPLATES rather than as
# transcribed lines, so each is the captured sentence with a value substituted.
# The counts and the job name are the ones from the same probe run - they appear
# verbatim in the PARTIAL check row it captured - so the substitution is a
# transcription too and not a plausible-looking guess.
e_timeout_fail="ERROR: Timed out waiting for service '$FAIL_F' to start"
e_timeout_fail2="ERROR: Timed out waiting for service '$FAIL2_F' to start"
e_timeout_part="ERROR: Timed out waiting for service '$PART_F' to start"
e_partial="Service '$PART_F' is already partially running. You may need to restart if this operation fails."
e_only="WARNING: Service '$PART_F' only 1/2 started [failed to start --> [not running at -->JOBNAME:$BADJOB]]"
LOGDETAIL="For details, see log file at: "

# on_out / on_err FILE PATTERN - whole-line count and prefix count. The log-file
# line carries a path this script cannot know, so it is matched by PREFIX; every
# other line here is matched whole, so a trailing space is a difference.
n_prefix() { grep -Fc -- "$2" "$1" 2>/dev/null || true; }

# --- a single-service start that FAILS --------------------------------------
#
# FOUR THINGS AT ONCE, and they are separated into named cases below so a
# failure says which: the exit status, the timeout error and its stream, the
# log-file line and ITS stream, and the blank-line rule on stderr.
#
# THE EXIT STATUS IS THE ONE TO READ CAREFULLY. docs/messages.md: "A
# single-service start that fails exits 253, where a group start exits 0
# whatever happens. Both measured. RMSC's exit status on this path has not been
# checked against it." So this is not a regression guard - it is the first time
# anybody has asked. A red here on the first run is the expected outcome and
# means the question has been answered, not that something broke.
ensure_down "$FAIL" >/dev/null 2>&1
# The log is reset because it is a FIXTURE for case (3) below, not a leftover:
# RMSC appends, so a log this script wrote on a previous run is content, and
# content is the gate on the line case (3) requires to be absent.
log_reset "$FAIL"
if require_state fail-start "$FAIL" NOT; then
  scr_run fail-start -- start "$FAIL"; f_rc=$?
  fo="$WORK/fail-start.out"; fe="$WORK/fail-start.err"

  # (1) exit 253
  probs=()
  [ "$f_rc" -eq 253 ] || probs+=("exit $f_rc, wanted 253 - upstream's measured status for a single-service start that failed")
  check_named fail-start-exit-253 unchecked \
    "a failed single-service start exits 253" "${probs[@]}"

  # (2) the timeout error, on stderr and NOT on stdout
  #
  # SEPARATING VALUES:
  #   the line on stderr, whole          rules out RMSC's own wording surviving
  #                                      - `<short> did not start within <n>
  #                                      seconds` shares not one word of this
  #   the FRIENDLY name in it            rules out the short name, which is what
  #                                      RMSC uses on this path today
  #   nothing matching it on stdout      rules out a second copy on the
  #                                      format-critical stream, which is the
  #                                      defect error-delivery-test.sh exists for
  probs=()
  [ "$(n_exact "$fe" "$e_timeout_fail")" -ge 1 ] \
    || probs+=("the measured timeout line is not on stderr; first stderr line: $(head -n 1 "$fe")")
  [ "$(n_exact "$fo" "$e_timeout_fail")" -eq 0 ] \
    || probs+=("the timeout line is ALSO on stdout")
  # THE SHORT NAME IS CHECKED ON THE TIMEOUT LINE, NOT ACROSS STDERR.
  #
  # An earlier version asked whether '$FAIL' appeared anywhere on stderr, and it
  # was wrong in a way a mutation found: upstream's log PATH is named after the
  # service, so any line quoting a path carries the short name legitimately, and
  # a load warning naming a file would too. The assertion fired on a mutation
  # that had nothing to do with naming, and would have fired on a real run for
  # the same reason - a case failing for a reason its own description does not
  # cover is worse than no case at all.
  tl=$(grep -F -m1 'Timed out waiting' "$fe" 2>/dev/null)
  if [ -n "$tl" ]; then
    case "$tl" in *"$FAIL"*) probs+=("the timeout line carries the SHORT name '$FAIL': $tl") ;; esac
    case "$tl" in *"$FAIL_F"*) ;; *) probs+=("the timeout line does not carry the friendly name '$FAIL_F': $tl") ;; esac
  fi
  check_named fail-start-timeout-error measured \
    "ERROR: Timed out …, on stderr, by the friendly name" "${probs[@]}"

  # (3) THE LINE ON STDOUT IS **ABSENT** HERE, AND WHY IT IS ABSENT HAS BEEN
  # WRONG TWICE.
  #
  # docs/messages.md § "The fifth state" now carries the measured table. The
  # gate is the LOG FILE HAVING CONTENT:
  #
  #     fixture                              log       upstream
  #     ---------------------------------    -------   --------
  #     rmscn_fail   never up, silent cmd     0 bytes   no line   <- HERE
  #     rmscn_noisy  never up, prints a line  36 bytes  THE LINE
  #     rmscn_half   partial, silent cmd      0 bytes   no line
  #
  # THIS CASE OWNS ROW 1, and what it rules out is "any failed start prints
  # where to look" - the natural reading of a sentence offering help after a
  # failure, and the reading the first version of this file took. That rule
  # predicts the line here. It is the only row that rules it out, because every
  # other fixture in the table is also a failure.
  #
  # IT DOES NOT, ON ITS OWN, ESTABLISH THE LOG-CONTENT RULE. Row 1 is equally
  # well explained by "already partial" - this service is not partial either -
  # which is why rows 2 and 3 exist and are asserted below under
  # noisy-log-detail-present and half-log-detail-absent. The three together
  # leave one rule standing; no two of them do.
  #
  # THE LOG SIZE IS ASSERTED ALONGSIDE THE ABSENCE, and that is not decoration.
  # Under the rule that was measured, an empty log is the REASON there is no
  # line, so a run whose log had content would satisfy this absence for a
  # reason the rule does not permit - and would do it silently, because a
  # leftover log from an earlier run of this very script is the likeliest way
  # to get one.
  probs=()
  n=$(n_prefix "$fo" "$LOGDETAIL"); [ -z "$n" ] && n=0
  ne=$(n_prefix "$fe" "$LOGDETAIL"); [ -z "$ne" ] && ne=0
  fb=$(log_bytes "$FAIL")
  [ "$fb" = 0 ] \
    || probs+=("$FAIL's log holds $fb byte(s) after a start whose command prints nothing - the gate is log CONTENT, so this run cannot ask about row 1 of the table at all; something else wrote to $RMSC_LOGS/$FAIL.log")
  [ "$n" -eq 0 ] || probs+=("$n '$LOGDETAIL' line(s) on stdout for a service that never came up, with $fb byte(s) in its log: at 0 bytes the line follows nothing, and above 0 the row above says this run cannot ask the question at all - see the table in this case's comment")
  [ "$ne" -eq 0 ] || probs+=("$ne of them on stderr, where upstream puts none of them")
  check_named fail-log-detail-absent measured \
    "no log-file line when the log is empty ($fb bytes)" "${probs[@]}"

  # (4) THE BLANK LINE FOLLOWS A COMMAND THAT EXITS 0, AND EVERY ERROR.
  #
  # THIS CASE USED TO DEMAND ONE BLANK LINE ON STDOUT HERE, AND IT WAS WRONG.
  # Upstream prints NONE. The rule "one blank per command" was measured on
  # SUCCESSFUL commands only - docs/messages.md's narration section says so in
  # its own first line, "All on stdout, exit 0, with one trailing blank line
  # after each command" - and was then generalised to every command by whoever
  # wrote this case, including this one. It was labelled `measured` throughout,
  # which is how a generalisation came to read like a transcription.
  #
  # It is the exact shape CLAUDE.md opens with, arriving from the other side:
  # RMSC prints no blank here either, so the assertion agreed with the code
  # while both disagreed with upstream, and a green run said so.
  #
  # RE-MEASURED 3 September 2026 against sc 1.7.1, stdout counted with
  # `grep -c '^$'`:
  #
  #     run                                  exit   blank lines on stdout
  #     ---------------------------------    ----   ---------------------
  #     start, service came up                  0            1
  #     start, service already running          0            1
  #     start, service NEVER comes up         253            0     <- here
  #     start, service already PARTIAL        253            0
  #     group start, both members failed        0            1
  #     group start, one failed one came up     0            1
  #     check                                   0            1
  #
  # THE RULE IS THE EXIT STATUS, and it takes BOTH failing shapes to establish
  # it, because two rivals survive any single run:
  #
  #   per command                asserts 1 here. Ruled out by THIS run: one
  #                              command, exit 253, no blank.
  #   after the last OUTCOME     asserts 0 here, so it agrees with the rule on
  #   line on stdout             this run and cannot be told apart by it. Ruled
  #                              out by the GROUP run below, where both members
  #                              failed: no outcome line on stdout anywhere, and
  #                              upstream still printed the blank.
  #
  # So the group case's `nbo -eq 1` is not a duplicate of this one with a
  # different number in it. It is the other half of the same measurement, and
  # neither half establishes the rule alone.
  #
  # THE STDERR HALF IS UNCHANGED and was right: one blank after each ERROR. The
  # separating value for that is a run with a different number of errors from
  # commands, which is the group case below (two errors, one command) and the
  # partial case after it (one ERROR beside one WARNING, one blank).
  #
  # Upstream's own stdout for this run is now compared byte for byte in stage
  # 3b's sc:sc-fail case, so the expectation cannot drift back.
  probs=()
  nb_out=$(grep -c '^$' "$fo" 2>/dev/null || true); [ -z "$nb_out" ] && nb_out=0
  ne_err=$(grep -c '^ERROR' "$fe" 2>/dev/null || true); [ -z "$ne_err" ] && ne_err=0
  nb_err=$(grep -c '^$' "$fe" 2>/dev/null || true); [ -z "$nb_err" ] && nb_err=0
  [ "$nb_out" -eq 0 ] \
    || probs+=("$nb_out blank line(s) on stdout for a command that exited $f_rc, wanted 0 - the blank follows a command that exits 0, and this one did not")
  if [ "$ne_err" -eq 0 ]; then
    probs+=("no ERROR line on stderr, so the per-error blank line cannot be checked")
  else
    [ "$nb_err" -eq "$ne_err" ] \
      || probs+=("$nb_err blank line(s) on stderr for $ne_err ERROR line(s) - the blank line is per-ERROR on stderr, not per-command")
  fi
  check_named fail-blank-line-asymmetry measured \
    "no blank on stdout for a command that failed, one per ERROR on stderr" "${probs[@]}"
fi

# --- THE OTHER TWO ROWS OF THE LOG-CONTENT TABLE ----------------------------
#
# ROW 2: NEVER RUNS, AND ITS START COMMAND PRINTS ONE LINE.
#
# This is the fixture the gate was measured with, and the only one that rules
# out "the service was already partially running" - the reading docs/messages.md
# carried until 4 September 2026 and the one the implementation was written to
# first. rmscn_noisy is NOT partial and never has been; it fails exactly the way
# rmscn_fail does, in the same time, with the same exit status and the same
# timeout error. The single difference is that its start command wrote a line,
# and the line appears. No rule about the service's STATE can produce that.
#
# WHY THE OLD PROBE COULD NOT SEE IT. The fixture then available was rmscn_part,
# whose start command is the port listener: on the second attempt the port is
# already held, python cannot bind, and the traceback goes into the log. So the
# service became partial and its log gained content on the SAME attempt, and the
# two rules predicted identically on every row anyone had. Separating them
# needed a fixture that moved one of the two, which is this one.
#
# THE PATH IS ASSERTED BY SHAPE AND NOT BYTE FOR BYTE, and the reason is a real
# divergence rather than a convenience: RMSC's log is ~/.sc/logs/<short>.log
# and upstream's is ~/.sc/logs/<timestamp>.<short>.log, so the two lines cannot
# be equal however right the gate is. What is common to both - the prefix, the
# directory, the service's own short name, the .log suffix - is asserted; the
# timestamp is not. docs/messages.md records the divergence as a property of
# SCLOG_path that pre-dates all of this.
ensure_down "$NOISY" >/dev/null 2>&1
log_reset "$NOISY"
if require_state noisy-log-detail "$NOISY" NOT; then
  scr_run noisy-start -- start "$NOISY"; n_rc=$?
  no="$WORK/noisy-start.out"; nerr="$WORK/noisy-start.err"

  probs=()
  nb=$(log_bytes "$NOISY")
  [ "$nb" -gt 0 ] \
    || probs+=("$NOISY's log is empty after a start command that prints a line - the fixture did not take, and with no content there is nothing for the gate to be open on; this case would then be asserting the opposite of what it says")
  [ "$(svc_state "$NOISY")" = NOT ] \
    || probs+=("$NOISY reads $(svc_state "$NOISY") after the attempt - it must NEVER come up, or 'not partial' is not what this run measured and the partial-state rule is not ruled out")
  ldn=$(n_prefix "$no" "$LOGDETAIL"); [ -z "$ldn" ] && ldn=0
  lde=$(n_prefix "$nerr" "$LOGDETAIL"); [ -z "$lde" ] && lde=0
  [ "$ldn" -ge 1 ] \
    || probs+=("no '$LOGDETAIL' line on stdout for a service that never ran and whose log holds $nb byte(s) - either the gate is not log content, or the line is not implemented on this path")
  [ "$lde" -eq 0 ] || probs+=("$lde of them on stderr, where upstream puts none of them")

  # The shape, on the line itself. Not the whole path: see the note above.
  ldline=$(grep -F -m1 -- "$LOGDETAIL" "$no" 2>/dev/null)
  if [ -n "$ldline" ]; then
    ldpath=${ldline#"$LOGDETAIL"}
    case "$ldpath" in
      */.sc/logs/*) ;;
      *) probs+=("the path is not under ~/.sc/logs: [$ldpath]") ;;
    esac
    case "$ldpath" in
      *"$NOISY".log) ;;
      *) probs+=("the path does not end in the service's own short name and .log, so it does not point at this service's log: [$ldpath]") ;;
    esac
    [ -f "$ldpath" ] \
      || probs+=("the path the line offers does not exist: [$ldpath] - there is no point telling anyone to read a file that is not there")
  fi
  check_named noisy-log-detail-present measured \
    "a never-running service with a $nb-byte log DOES print it" "${probs[@]}"

  # THE EXIT STATUS, so that "identical to rmscn_fail except for the log" is
  # a claim this file checks rather than one it asserts in a comment. If this
  # run exited differently the two fixtures would not be comparable and the
  # difference between them could be something other than the log.
  probs=()
  [ "$n_rc" -eq "${f_rc:--1}" ] \
    || probs+=("this run exits $n_rc where the silent one exits ${f_rc:--1} - the two fixtures were supposed to differ ONLY in what the start command printed, and they do not")
  [ "$(n_exact "$nerr" "ERROR: Timed out waiting for service '$NOISY_F' to start")" -ge 1 ] \
    || probs+=("no timeout error on stderr, so this run did not fail the same way the silent one did")
  check_named noisy-fails-the-same-way measured \
    "it fails exactly as the silent one does - exit $n_rc, same timeout error" "${probs[@]}"
fi
ensure_down "$NOISY" >/dev/null 2>&1
log_reset "$NOISY"

# ROW 3: ALREADY PARTIAL, AND ITS START COMMAND SAYS NOTHING.
#
# The row the partial-state rule wrongly predicts, and the ONLY row that rules
# out the tidier compromise "partial OR the log has content" - which fits rows
# 1 and 2 perfectly well and is what a reader would settle on if the table
# stopped at two.
#
# rmscn_half is partial before this script touches it: its satisfiable
# criterion is a port a listener of this script's own holds, and its
# unsatisfiable one is a job name that never exists. Its own start command is a
# bounded sleep, so however many times it is started it binds nothing, prints
# nothing, and leaves its log empty.
# NOT ensure_down. Measured the hard way on the first run: `stop` on this
# service ends whatever is listening on its satisfied criterion, and what is
# listening there is THIS SCRIPT'S OWN listener - so the tidy-looking
# precondition took the fixture apart, the service read NOT RUNNING, and both
# this case and the upstream anchor below refused to run. rmscn_half is partial
# by construction and has no down state to be put into.
log_reset "$HALF"
if require_state half-log-detail "$HALF" PARTIAL; then
  scr_run half-start -- start "$HALF"
  ho="$WORK/half-start.out"; herr="$WORK/half-start.err"

  probs=()
  hb=$(log_bytes "$HALF")
  [ "$hb" = 0 ] \
    || probs+=("$HALF's log holds $hb byte(s) after a silent start command - this row needs an EMPTY log beside a PARTIAL service, and with content in it the row measures nothing")
  [ "$(svc_state "$HALF")" = PARTIAL ] \
    || probs+=("$HALF reads $(svc_state "$HALF") after the attempt, not PARTIAL - the row that rules out 'partial OR content' needs the service to be partial")
  hd=$(n_prefix "$ho" "$LOGDETAIL"); [ -z "$hd" ] && hd=0
  hde=$(n_prefix "$herr" "$LOGDETAIL"); [ -z "$hde" ] && hde=0
  [ "$hd" -eq 0 ] \
    || probs+=("$hd '$LOGDETAIL' line(s) on stdout for a PARTIAL service with $hb byte(s) in its log - at 0 bytes this is the row 'partial OR content' gets wrong, and above 0 the row above says the fixture stopped being silent")
  [ "$hde" -eq 0 ] || probs+=("$hde of them on stderr")
  check_named half-log-detail-absent measured \
    "a partial service with an empty log does NOT print it" "${probs[@]}"
fi
# The log only - see above: stopping this one would end the listener that makes
# it partial, and stage 3b's upstream anchor needs it still partial.
log_reset "$HALF"

# --- a GROUP start whose only member fails, and the two statuses together ----
#
# docs/messages.md: "The group operation exits 0 even when a member fails",
# measured again by the re-probe, and pinned by error-delivery-test.sh with a
# warning that it must not be "fixed".
#
# ASSERTED HERE FOR A REASON THAT CASE CANNOT COVER: this run has just observed
# 253 from the same failure through a single service. The two statuses are the
# point. A case that only saw the group would pass against an implementation
# that returned 0 from every failed start, and a case that only saw the single
# service would pass against one that returned 253 from both - so neither, on
# its own, tests that the two paths are TOLD APART. That is the same argument
# error-delivery-test.sh's codes-differentiated case makes, and it is made the
# same way: assert the property directly rather than hoping two expectations
# imply it.
ensure_down "$FAIL" >/dev/null 2>&1
ensure_down "$FAIL2" >/dev/null 2>&1
if require_state group-fail "$FAIL" NOT "$FAIL2" NOT; then
  scr_run group-fail -- start "group:$FAILGROUP"; g_rc=$?
  ge="$WORK/group-fail.err"; go="$WORK/group-fail.out"

  probs=()
  [ "$g_rc" -eq 0 ] || probs+=("exit $g_rc, wanted 0 - a group start exits 0 whatever happens to its members")
  [ "$(n_exact "$ge" "$e_timeout_fail")" -ge 1 ] \
    || probs+=("no timeout error for $FAIL_F on stderr, so that member did not actually fail and exit 0 means nothing here")
  [ "$(n_exact "$ge" "$e_timeout_fail2")" -ge 1 ] \
    || probs+=("no timeout error for $FAIL2_F on stderr - both members must fail for the ratio case below to have two errors")
  check_named group-fail-exit-0 measured \
    "a group start exits 0 even when both its members failed" "${probs[@]}"

  # THE BLANK-LINE RATIO, NOW SEPARATING.
  #
  # The last report flagged this as written but not yet separating: every
  # fixture then produced one error per command, so "one blank per ERROR" and
  # "one blank per command" agreed on every value and nothing could tell them
  # apart. This run is the shape that can - ONE command, TWO errors:
  #
  #     per-ERROR    predicts 2 blank lines   <- measured
  #     per-command  predicts 1
  #
  # A second failing member is the entire reason rmscn_fail2 exists.
  #
  # And the stdout half in the same breath. It is the other side of the
  # asymmetry - one blank on stdout for the whole command, however many members
  # it touched - and, since the re-measurement above, it is also the ONLY run in
  # this file that rules out the second rival:
  #
  #     exits 0                      predicts 1 blank   <- measured
  #     follows the last OUTCOME     predicts 0, because both members failed and
  #     line on stdout               there is no outcome line here at all
  #
  # Measured 3 September 2026: a group start whose members both failed exits 0,
  # prints two progress lines and nothing else on stdout, and still ends with
  # the blank. The single-service failure above and this run are a pair; neither
  # establishes the rule on its own.
  probs=()
  ne=$(grep -c '^ERROR' "$ge" 2>/dev/null || true); [ -z "$ne" ] && ne=0
  nb=$(grep -c '^$' "$ge" 2>/dev/null || true); [ -z "$nb" ] && nb=0
  nbo=$(grep -c '^$' "$go" 2>/dev/null || true); [ -z "$nbo" ] && nbo=0
  if [ "$ne" -lt 2 ]; then
    probs+=("$ne ERROR line(s) on stderr - this case needs two under one command or it cannot separate per-ERROR from per-command")
  else
    [ "$nb" -eq "$ne" ] \
      || probs+=("$nb blank line(s) on stderr for $ne ERROR line(s) under ONE command: per-ERROR predicts $ne, per-command predicts 1")
  fi
  # The guard that keeps the stdout half SEPARATING. It only rules out "the
  # blank follows the last outcome line" while there is no outcome line to
  # follow; if a member came up after all, this run agrees with both rivals and
  # says so rather than passing as though it had settled something.
  n_outcome=$(grep -c "^Service '" "$go" 2>/dev/null || true); [ -z "$n_outcome" ] && n_outcome=0
  [ "$n_outcome" -eq 0 ] \
    || probs+=("$n_outcome outcome line(s) on stdout - both members were supposed to fail, and while one of them succeeded this run cannot tell 'blank when the command exits 0' from 'blank after the last outcome line'")
  [ "$nbo" -eq 1 ] \
    || probs+=("$nbo blank line(s) on stdout for a command that exited $g_rc, wanted 1 - the command exited 0, so the blank is there even though no member produced an outcome line")
  check_named group-blank-per-error measured \
    "$nb blank(s) for $ne error(s) on stderr, $nbo for one command on stdout" "${probs[@]}"

  probs=()
  if [ "$f_rc" -eq "$g_rc" ]; then
    probs+=("the same failure exits $f_rc as a single service and $g_rc as a group - the two paths are not being told apart")
  fi
  check_named fail-statuses-differentiated measured \
    "single-service $f_rc, group $g_rc - different, as measured" "${probs[@]}"
fi

# --- THE FIFTH STATE, and the two warnings beside it ------------------------
#
# docs/messages.md § "The fifth state, and three messages nobody had seen": the
# partial line is NOT a fifth sibling of the four states. The four are on
# stdout; this one is on STDERR. "An implementation that grew SCOUT_svc_state by
# a fifth constant would put it on the wrong stream."
#
# SO THE STREAM IS THE ASSERTION. The wording is pinned in
# qtestsrc/SCOUT.TEST.RPGLE, where it needs no fixture; what only this file can
# ask is which stream it came out on, and that is exactly the thing the obvious
# implementation gets wrong.
#
# WHICH INVOCATION CARRIES WHICH LINE IS NOT RECORDED, and this case does not
# pretend otherwise. docs/messages.md lists all four lines in one table against
# one probe of "a service with two criteria, one satisfiable and one not"
# without saying whether the partial line came from the first start or from a
# second one made while it was already partial. So the case runs BOTH, asserts
# each line on stderr in one of them, asserts it on stdout in NEITHER, and
# reports which run carried it - turning the residual ambiguity into a
# measurement instead of a guess.
ensure_down "$PART" >/dev/null 2>&1
log_reset "$PART"
scr_run part-one -- start "$PART"; p1_rc=$?
pb1=$(log_bytes "$PART")
scr_run part-check -- check "$PART"
scr_run part-two -- start "$PART"; p2_rc=$?
pb2=$(log_bytes "$PART")

# FIXTURE PROOF, and the coordinator's own suggestion: the service must read
# PARTIAL to `check`. That is invariant under everything this stage tests - the
# narration can be wrong in every particular and the check row still says
# PARTIAL - so it can tell a working fixture from an absent one.
#
# It cannot be proved from the warnings themselves: those are the thing under
# test and RMSC emits none of them today, so a guard built on them would report
# the fixture broken for as long as the defect exists.
if grep -q '^  PARTIAL' "$WORK/part-check.out" 2>/dev/null; then
  report PASS staged-partial-service \
    "(fixture) $PART reads PARTIAL - one criterion satisfied, one not"
  pass=$((pass+1))
  part_ok=1
else
  report FAIL staged-partial-service \
    "FIXTURE DID NOT TAKE: $PART does not read PARTIAL"
  detail "check said: $(grep -m1 '|' "$WORK/part-check.out" 2>/dev/null || echo '(nothing)')"
  detail "the listener did not bind port $PORT_PART, or '$BADJOB' resolved to a real job,"
  detail "or RMSC does not report PARTIAL at all - which docs/messages.md records as a"
  detail "separate live defect on the byte-exact check path"
  detail "the three cases below are not evidence until this works"
  failed=$((failed+1))
  part_ok=0
fi

# where_seen LABEL LINE - which of the two runs carried it, on which stream
if [ "$part_ok" -eq 1 ]; then
  for spec in "partial-state:$e_partial" "only-n-of-m:$e_only"; do
    lbl=${spec%%:*}; want=${spec#*:}
    err1=$(n_exact "$WORK/part-one.err" "$want"); err2=$(n_exact "$WORK/part-two.err" "$want")
    out1=$(n_exact "$WORK/part-one.out" "$want"); out2=$(n_exact "$WORK/part-two.out" "$want")

    probs=()
    if [ $((err1 + err2)) -eq 0 ]; then
      probs+=("the measured line appears on stderr in neither run: [$want]")
      # Say whether the SENTENCE is there at all, so a wrong suffix or a wrong
      # count reads differently from nothing having been printed.
      case "$lbl" in
        partial-state) key="is already partially running" ;;
        *)             key="only 1/2 started" ;;
      esac
      if cat "$WORK/part-one.err" "$WORK/part-two.err" "$WORK/part-one.out" \
             "$WORK/part-two.out" 2>/dev/null | grep -Fq -- "$key"; then
        probs+=("but a line containing '$key' IS present - the sentence is there and some part of it differs")
      else
        probs+=("and nothing containing '$key' was printed at all, on either stream, in either run")
      fi
    fi
    [ $((out1 + out2)) -eq 0 ] \
      || probs+=("it is on STDOUT (run 1: $out1, run 2: $out2) - the four states are on stdout and this one is NOT; a fifth SCOUT_svc_state constant would put it here")

    check_named "$lbl" measured \
      "stderr only (run 1: $err1, run 2: $err2)" "${probs[@]}"
  done

  # THE WARNING DOES NOT GET A BLANK LINE, AND THE ERROR DOES.
  #
  # The third value the ratio needs, and the partial run is the only place it
  # exists: this stderr carries a WARNING line AND an ERROR line, so the count
  # of blank lines tells three rules apart rather than two.
  #
  #     per-ERROR         predicts 1   <- measured
  #     per-stderr-line   predicts 2
  #     per-command       predicts 1
  #
  # It does not separate per-ERROR from per-command on its own - the group case
  # above does that - but it is the only fixture that rules out the reading
  # "every message on stderr is followed by a blank line", which is the tidier
  # rule and the one an implementation would reach for if it put the blank line
  # in whatever writes to stderr rather than beside the error.
  probs=()
  pw=$(grep -c '^WARNING' "$WORK/part-one.err" 2>/dev/null || true); [ -z "$pw" ] && pw=0
  pe=$(grep -c '^ERROR' "$WORK/part-one.err" 2>/dev/null || true); [ -z "$pe" ] && pe=0
  pb=$(grep -c '^$' "$WORK/part-one.err" 2>/dev/null || true); [ -z "$pb" ] && pb=0
  if [ "$pw" -lt 1 ] || [ "$pe" -lt 1 ]; then
    probs+=("stderr carries $pw WARNING and $pe ERROR line(s) - this case needs one of each, or it cannot rule out 'a blank after every stderr line'")
  else
    [ "$pb" -eq "$pe" ] \
      || probs+=("$pb blank line(s) for $pe ERROR and $pw WARNING line(s): per-ERROR predicts $pe, a blank after every stderr message predicts $((pe+pw))")
  fi
  check_named part-warning-gets-no-blank measured \
    "$pb blank(s) for $pe error(s) beside $pw warning(s)" "${probs[@]}"

  # And the log-file line again, from THIS fixture - the one that used to be
  # read as evidence for the partial-state rule, and is not.
  #
  # WHAT ACTUALLY HAPPENS HERE, and it is worth spelling out because it is how
  # a wrong rule came to look measured. rmscn_part's start command is the port
  # listener. On attempt 1 it binds, prints nothing, and the log stays EMPTY -
  # and there is no line. On attempt 2 the port is already held, python cannot
  # bind, and the traceback is written to the log - and the line appears. The
  # service also became partial between the two attempts, so both readings fit,
  # and the log content is the one that survives rows 2 and 3 above.
  #
  # SO THE ASSERTION IS NOW THE PAIRING, not merely the presence: the run whose
  # log is empty must not carry the line, and the run whose log has content
  # must. Stated that way this fixture stops being ambiguous evidence and
  # becomes a fourth row of the same table - and it is the only row where the
  # log gains its content DURING the sequence rather than on the first attempt,
  # which is a shape the other three do not cover.
  probs=()
  lp1=$(n_prefix "$WORK/part-one.out" "$LOGDETAIL"); [ -z "$lp1" ] && lp1=0
  lp2=$(n_prefix "$WORK/part-two.out" "$LOGDETAIL"); [ -z "$lp2" ] && lp2=0
  le=$(( $(n_prefix "$WORK/part-one.err" "$LOGDETAIL") + $(n_prefix "$WORK/part-two.err" "$LOGDETAIL") ))
  if [ "$pb1" = 0 ]; then
    [ "$lp1" -eq 0 ] || probs+=("attempt 1 printed the line with an empty log ($pb1 bytes)")
  else
    [ "$lp1" -ge 1 ] || probs+=("attempt 1's log holds $pb1 byte(s) and it printed no line")
  fi
  if [ "$pb2" = 0 ]; then
    [ "$lp2" -eq 0 ] || probs+=("attempt 2 printed the line with an empty log ($pb2 bytes)")
  else
    [ "$lp2" -ge 1 ] || probs+=("attempt 2's log holds $pb2 byte(s) and it printed no line")
  fi
  [ $((lp1 + lp2)) -ge 1 ] \
    || probs+=("neither attempt printed it and neither log has content ($pb1 and $pb2 bytes) - this fixture is supposed to gain log content on the second attempt, so it is no longer the shape this case describes")
  [ "$le" -eq 0 ] || probs+=("$le of them on stderr")
  check_named part-log-detail-follows-the-log measured \
    "attempt 1 log $pb1 bytes line $lp1, attempt 2 log $pb2 bytes line $lp2" "${probs[@]}"
fi

# --- NO LINE ON THE FAILURE PATH PARSES AS A CHECK ROW ----------------------
#
# THE GAP THIS CLOSES. assert_narration applies the row-shape rule to every case
# that goes through it, and not one case in this stage does: the failure runs
# have unpredictable stdout - a log path this script cannot know - so they are
# asserted line by line instead. The consequence was that the four runs which
# produce the LEAST predictable stdout were the four nothing checked.
#
# It cannot be asked of the log-file line alone, and that is worth saying
# because that is where it was first written. The case already requires that
# line to BEGIN with `For details, ` at column 1, and a line beginning at column
# 1 cannot also begin with the two spaces a check row begins with - so the
# assertion would have been true by construction and could never have failed.
# Asked of the whole stream it is a real question, because the streams carry
# lines this script does not enumerate.
#
# docs/parity.md asked for this confirmation before the lines were added. The
# failure path is where it matters most: a consumer sees these lines exactly
# when something has gone wrong, which is the moment a vanished service row is
# least likely to be noticed and most likely to matter.
fp_bad=()
for f in fail-start noisy-start half-start part-one part-two group-fail; do
  [ -s "$WORK/$f.out" ] || continue
  n=$(grep -cE "$CHECK_ROW" "$WORK/$f.out" 2>/dev/null || true); [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] || fp_bad+=("$f: $n stdout line(s) a column-parsing consumer would accept as a service row: $(grep -m1 -E "$CHECK_ROW" "$WORK/$f.out")")
done
check_named failure-stdout-not-rows inferred \
  "nothing on the failure path parses as a check row" "${fp_bad[@]}"

ensure_down "$PART" >/dev/null 2>&1
ensure_down "$FAIL" >/dev/null 2>&1
ensure_down "$FAIL2" >/dev/null 2>&1
log_reset "$PART"
log_reset "$FAIL"

# --- a group stop that reaches one member TWICE -----------------------------
#
# docs/messages.md, and it says "That one is real":
#
#     Performing operation 'STOP' on service 'rmscd2_dep'
#     Attempting to stop dependent service 'RMSC D2 labels'...
#     Service 'RMSC D2 labels' is already stopped
#     Service 'RMSC D2 dependency' is already stopped
#     Performing operation 'STOP' on service 'rmscd2_labels'
#     Service 'RMSC D2 labels' is already stopped
#
# A member is reached once as another member's dependent and once in its own
# right, and gets an outcome line both times.
#
# SEPARATING VALUE: the dependent's friendly name appears in exactly TWO outcome
# lines where the other member's appears in ONE. The rival rule is the one any
# implementation would arrive at by being careful - keep a set of services
# already handled, and skip a repeat - and it produces output identical to this
# in every respect except that count. Nothing else tells them apart.
#
# ORDER-AGNOSTIC, and this is what let the case be added without disturbing the
# ordering case in stage 3. Which member the walk reaches first is not asserted:
# whichever it is, the dependent is reached twice and the other once. Both
# orders were worked through before this was written, and the observed order is
# reported so a change in it is visible without being a failure.
g2_case() {  # tag  wanted-state-of-both  expected-outcomes-for-the-dependent
  local tag="$1" want="$2" note="$3"
  local o="$WORK/$tag.out"

  require_state "$tag" "$G2BASE" "$want" "$G2USER" "$want" || return 1
  scr_run "$tag" -- stop "group:$GROUP2"; local rc=$?

  local probs=() n
  [ "$rc" -eq 0 ] || probs+=("exit $rc, wanted 0")

  n=$(grep -c "^Performing operation " "$o" 2>/dev/null || true); [ -z "$n" ] && n=0
  [ "$n" -eq 2 ] || probs+=("$n progress line(s), wanted one per member (2)")

  # The counts that are the whole case.
  local user_lines base_lines dep_lines
  user_lines=$(grep -c "^Service '$G2USER_F' " "$o" 2>/dev/null || true); [ -z "$user_lines" ] && user_lines=0
  base_lines=$(grep -c "^Service '$G2BASE_F' " "$o" 2>/dev/null || true); [ -z "$base_lines" ] && base_lines=0
  dep_lines=$(n_exact "$o" "Attempting to stop dependent service '$G2USER_F'...")

  [ "$user_lines" -eq 2 ] \
    || probs+=("the dependent '$G2USER_F' has $user_lines outcome line(s), wanted 2 - it is reached once as a dependent and once in its own right, and upstream does NOT de-duplicate")
  [ "$base_lines" -eq 1 ] \
    || probs+=("'$G2BASE_F' has $base_lines outcome line(s), wanted 1 - only the dependent is reached twice")
  [ "$dep_lines" -eq 1 ] \
    || probs+=("$dep_lines 'Attempting to stop dependent service' line(s) for '$G2USER_F', wanted 1 - the dependent line belongs to the walk, not to each mention")

  # The two outcome lines the dependent gets, as a multiset. From both DOWN they
  # are both `is already stopped`, which is the measured transcript. From both
  # UP the walk does the work the first time, so one of them is `successfully
  # stopped` and the other `is already stopped` - and that holds whichever
  # member the walk reaches first, which is what keeps this order-agnostic.
  local n_halt n_done
  n_halt=$(n_exact "$o" "Service '$G2USER_F' is already stopped")
  n_done=$(n_exact "$o" "Service '$G2USER_F' successfully stopped")
  case "$want" in
    NOT)
      [ "$n_halt" -eq 2 ] || probs+=("the dependent says 'is already stopped' $n_halt time(s), wanted 2 - both members were down, so nothing was stopped either time")
      [ "$n_done" -eq 0 ] || probs+=("$n_done 'successfully stopped' line(s) for a service that was already down") ;;
    RUNNING)
      [ "$n_done" -eq 1 ] || probs+=("the dependent says 'successfully stopped' $n_done time(s), wanted 1 - the walk stops it the first time it is reached")
      [ "$n_halt" -eq 1 ] || probs+=("the dependent says 'is already stopped' $n_halt time(s), wanted 1 - the second time it is reached there is nothing left to do") ;;
  esac

  # One blank line for the whole command, not one per member and not one per
  # mention of a service.
  n=$(grep -c '^$' "$o" 2>/dev/null || true); [ -z "$n" ] && n=0
  [ "$n" -eq 1 ] || probs+=("$n blank line(s), wanted 1 - the blank line follows the COMMAND")

  n=$(grep -cE "$NARRATION" "$WORK/$tag.err" 2>/dev/null || true); [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] || probs+=("$n narration line(s) on stderr")

  local first
  first=$(grep -m1 "^Performing operation " "$o" 2>/dev/null | sed "s/.*service '//; s/'.*//")
  check_named "$tag" measured "$note; walked ${first:-?} first" "${probs[@]}"
}

# The measured transcript: both members already down, `is already stopped` twice.
ensure_down "$G2USER" >/dev/null 2>&1
ensure_down "$G2BASE" >/dev/null 2>&1
g2_case group-stop-twice-down NOT "reached twice, already stopped both times"

# The same shape with work actually done. COMPOSED: docs/messages.md's
# transcript of this case had both members down, so the already-stopped form is
# the measured one and this is its counterpart. It is worth running because the
# de-duplication an implementation would add is far likelier to appear on the
# path where the first visit DOES something - "we stopped it, no need to look
# again" is a more natural thought than "we found it stopped, no need to look
# again".
ensure_up "$G2BASE" >/dev/null 2>&1
ensure_up "$G2USER" >/dev/null 2>&1
g2_case group-stop-twice-up RUNNING "reached twice, stopped once then already stopped"

ensure_down "$G2USER" >/dev/null 2>&1
ensure_down "$G2BASE" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# DRIVING UPSTREAM, AND COMPARING ITS WHOLE STDOUT
#
# These are stage 4's helpers, defined here because stage 3b now uses them too.
# Stage 4 is where the fixture verdict is REPORTED; this stage borrows the
# machinery and reports nothing about the fixture itself.
# ---------------------------------------------------------------------------

# sc_state SHORT -> RUNNING | NOT | PARTIAL | ?
#
# PARTIAL IS REPORTED SEPARATELY and that is not cosmetic. It used to fall into
# '?' along with "upstream cannot see this service at all", so a precondition of
# "the service is half up" could not be stated - and the one case that needs it,
# the second partial start, is the case that measures the log-file line's gate.
# A precondition that cannot tell "half up" from "not there" is not one.
sc_state() {  # short -> RUNNING | NOT | PARTIAL | ?
  local o
  o=$(JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" check "$1" 2>/dev/null)
  case "$o" in
    *"  NOT RUNNING "*) echo NOT ;;
    *"  PARTIAL"*)      echo PARTIAL ;;
    *"  RUNNING "*)     echo RUNNING ;;
    *)                  echo '?' ;;
  esac
}
sc_settle() {
  local s="$1" want="$2" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(sc_state "$s")" = "$want" ] && return 0
    sleep 1
  done
  return 1
}
sc_down() { JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" stop "$1" >/dev/null 2>&1; sc_settle "$1" NOT; }
sc_up()   { JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" start "$1" >/dev/null 2>&1; sc_settle "$1" RUNNING; }

sc_confirmed=0
sc_last_rc=-1

# confirm_sc [--mask-logpath] TAG EXPECTED_FILE SERVICE REQUIRED_STATE -- argv...
#
# Runs upstream and compares its WHOLE stdout with the recorded expectation,
# byte for byte. That one comparison covers the trailing blank line, the absence
# of any extra line, the absence of any missing line and the order all at once -
# which is why it is worth having alongside the line-by-line anchors, and why
# leaving the failure runs out of it let a wrong blank-line rule survive.
#
# --mask-logpath replaces the tail of `For details, see log file at: <path>` on
# BOTH sides before the diff. It is the narrowest mask that works: the line's
# presence, its position and everything either side of it are still exact, and
# nothing else in the stream is touched. Without it the partial run could not be
# compared as a whole at all, because the path is a timestamped name in the
# caller's home directory.
#
# The run's exit status is left in $sc_last_rc, and set to -1 when the case was
# skipped, so a caller can tell "upstream exited 0" from "upstream was not run".
confirm_sc() {
  local mask=0
  if [ "$1" = "--mask-logpath" ]; then mask=1; shift; fi
  local tag="$1" exp="$2" svc="$3" want="$4"; shift 4
  [ "$1" = "--" ] && shift
  local got got_file exp_file
  sc_last_rc=-1
  if [ "${sc_ok:-0}" -eq 0 ]; then
    report SKIPPED "sc:$tag" "sc:staged-definitions failed - see stage 4"
    skipped=$((skipped+1))
    return
  fi
  got=$(sc_state "$svc")
  if [ "$got" != "$want" ]; then
    report SKIPPED "sc:$tag" "upstream sees $svc as $got, the case needs $want - not run"
    skipped=$((skipped+1))
    return
  fi
  sc_confirmed=$((sc_confirmed+1))
  sc_run "$tag" -- "$@"; sc_last_rc=$?

  got_file="$WORK/sc.$tag.out"
  exp_file="$exp"
  if [ "$mask" -eq 1 ]; then
    sed "s|^${LOGDETAIL}.*|${LOGDETAIL}<path>|" "$got_file" > "$WORK/sc.$tag.masked"
    got_file="$WORK/sc.$tag.masked"
  fi

  if diff -u "$exp_file" "$got_file" > "$WORK/sc.$tag.diff" 2>&1; then
    report PASS "sc:$tag" "upstream's stdout is byte-identical to the recorded expectation"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$tag" "upstream does not say what this file records"
    while IFS= read -r l; do detail "$l"; done < "$WORK/sc.$tag.diff"
    detail "the EXPECTATION is what is wrong here - correct it, and docs/messages.md with it"
    refdrift=$((refdrift+1))
  fi
}

# --- the four new literals, re-measured against upstream --------------------
#
# TWO KINDS OF ANCHOR, and this stage needs both.
#
# THE LINE-BY-LINE ANCHORS, below, ask whether upstream produces four particular
# STDERR lines. They need to be line-by-line: which of the two partial starts
# carries which warning was never recorded, so the cases look for each line
# across both runs rather than pinning it to one.
#
# THE WHOLE-STREAM ANCHORS come first, and they close a gap. confirm_sc - the
# byte-exact comparison of upstream's whole stdout against a recorded
# expectation - was called for the success and dependency cases only. The three
# FAILURE runs went through the present-on-a-stream checks alone, so NOTHING in
# this file had ever compared upstream's failure stdout as a whole.
#
# That is precisely how the spurious blank line survived. The
# fail-blank-line-asymmetry case demanded a blank on stdout that upstream does
# not print; every case that could have noticed was asking "is this line
# present?", and a line that is absent is not present in either implementation.
# A whole-stream comparison would have said so on the first run.
#
# So all three now go through confirm_sc, and the expectations are built with
# expect_nb - no trailing blank - which is the corrected rule written down where
# a reader trips over it.
#
# THE LOG PATH IS MASKED, and only the log path. sc-part2's stdout carries
# `For details, see log file at: <path>`, and the path is a timestamped name in
# the caller's home directory that this script cannot predict. --mask-logpath
# replaces the tail of that ONE line on both sides before the diff, so every
# other byte - the line's presence, its position, its prefix, and the absence of
# a trailing blank - is still compared exactly.
#
# THEY NEED ANCHORING MORE THAN ANYTHING ELSE IN THIS FILE. Every other
# expectation is a transcribed line; these four are TEMPLATES with a value
# substituted, so a wrong guess about the shape of the template - `only 1/2
# started` against `only 1/2 criteria started`, say - would look like a defect
# in RMSC on every run until somebody re-read the probe log.
#
# A REFDRIFT here means the literal at the top of this stage is wrong, and
# docs/messages.md's template with it. It does not mean RMSC regressed.

# The expectations. MEASURED 3 September 2026 against sc 1.7.1, driven against
# definitions of exactly this shape:
#
#   start of a service that never comes up      one progress line, no blank
#   start of a two-criteria service, 1st attempt one progress line, no blank
#   start of the same service, 2nd attempt      the progress line and the
#                                               log-file line, no blank
#
# The log-file line appears on the SECOND attempt and not the first, and it is
# asserted as a difference between two whole streams rather than as two counts
# of a prefix.
#
# THE REASON IT APPEARS ON THE SECOND IS THE LOG, NOT THE STATE. This pair used
# to be recorded as the measurement behind "already partial", and it is not: on
# attempt 2 the port is already held, the listener cannot bind, and its
# traceback goes into the log. The service became partial and its log gained
# content on the same attempt, so both readings fit this pair and neither is
# established by it. sc-noisy and sc-half below are the rows that separate
# them.
expect_nb "$WORK/e.sc-fail"  "Performing operation 'START' on service '$FAIL'"
expect_nb "$WORK/e.sc-part1" "Performing operation 'START' on service '$PART'"
expect_nb "$WORK/e.sc-part2" "Performing operation 'START' on service '$PART'" \
                             "${LOGDETAIL}<path>"

# THE TWO ROWS THAT SEPARATE THE GATE, ANCHORED AGAINST UPSTREAM.
#
# The RMSC cases above assert the measured rule; these two say that upstream
# does the same thing, and they are the two rows the old reading got wrong. If
# either of these drifts, the table in docs/messages.md is what is wrong and not
# RMSC - which is exactly the mistake that produced the second reading, where a
# rule was recorded as measured on a fixture that could not tell it from its
# rival.
expect_nb "$WORK/e.sc-noisy" "Performing operation 'START' on service '$NOISY'" \
                             "${LOGDETAIL}<path>"
expect_nb "$WORK/e.sc-half"  "Performing operation 'START' on service '$HALF'"

JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" stop "$FAIL" >/dev/null 2>&1
JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" stop "$PART" >/dev/null 2>&1
JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" stop "$NOISY" >/dev/null 2>&1

confirm_sc sc-fail  "$WORK/e.sc-fail"  "$FAIL" NOT -- start "$FAIL"
sc_fail_rc=$sc_last_rc

confirm_sc --mask-logpath \
           sc-noisy "$WORK/e.sc-noisy" "$NOISY" NOT     -- start "$NOISY"
confirm_sc sc-half  "$WORK/e.sc-half"  "$HALF"  PARTIAL -- start "$HALF"

# THE PRECONDITION ON THE SECOND PARTIAL RUN IS THE POINT OF SPLITTING THEM.
# sc-part1 must start from DOWN and sc-part2 from PARTIAL, and until now nothing
# checked that the first run had actually left the service half up - so the two
# runs could silently have been two copies of the same case, and the log-file
# line's gate would have been asserted against a state nobody had confirmed.
confirm_sc sc-part1 "$WORK/e.sc-part1" "$PART" NOT     -- start "$PART"
confirm_sc --mask-logpath \
           sc-part2 "$WORK/e.sc-part2" "$PART" PARTIAL -- start "$PART"

JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" stop "$PART" >/dev/null 2>&1

sc_anchor() {  # tag  line  stream-file...
  local tag="$1" want="$2"; shift 2
  local n=0 f
  for f in "$@"; do n=$(( n + $(n_exact "$f" "$want") )); done
  if [ "$n" -ge 1 ]; then
    report PASS "sc:$tag" "upstream says it, byte for byte"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$tag" "upstream does not produce this line"
    detail "recorded: [$want]"
    detail "the template in docs/messages.md is what is wrong here, not RMSC"
    refdrift=$((refdrift+1))
  fi
}

if [ "$sc_ok_early" = 1 ]; then
  sc_anchor timeout  "$e_timeout_fail" "$WORK/sc.sc-fail.err"
  sc_anchor partial  "$e_partial"      "$WORK/sc.sc-part1.err" "$WORK/sc.sc-part2.err"
  sc_anchor only-n-m "$e_only"         "$WORK/sc.sc-part1.err" "$WORK/sc.sc-part2.err"

  # THE THREE-ROW TABLE, ASKED OF UPSTREAM AS ONE QUESTION.
  #
  #     run        fixture                        upstream
  #     --------   ----------------------------   --------
  #     sc-fail    never up, silent start cmd     no line
  #     sc-noisy   never up, start cmd prints     THE LINE
  #     sc-half    partial, silent start cmd      no line
  #
  # and each row rules out a different rival:
  #
  #     sc-fail    rules out "any failed start prints where to look" - every
  #                other row here is also a failure, so nothing else can
  #     sc-noisy   rules out "the service was already partially running" - this
  #                one is not partial and prints it anyway. It is the row the
  #                second reading of this rule never had
  #     sc-half    rules out "partial OR the log has content", the compromise
  #                that fits the first two rows perfectly well
  #
  # sc-part2 is kept beside them as the row where the log gains its content
  # part-way through a sequence rather than on the first attempt.
  sc_ld_part=$(( $(n_prefix "$WORK/sc.sc-part1.out" "$LOGDETAIL") \
               + $(n_prefix "$WORK/sc.sc-part2.out" "$LOGDETAIL") ))
  sc_ld_fail=$(n_prefix "$WORK/sc.sc-fail.out" "$LOGDETAIL")
  sc_ld_noisy=$(n_prefix "$WORK/sc.sc-noisy.out" "$LOGDETAIL")
  sc_ld_half=$(n_prefix "$WORK/sc.sc-half.out" "$LOGDETAIL")
  for v in sc_ld_part sc_ld_fail sc_ld_noisy sc_ld_half; do
    [ -n "${!v}" ] || eval "$v=0"
  done
  ld_bad=()
  [ "$sc_ld_fail" -eq 0 ] \
    || ld_bad+=("never up with a silent start command: $sc_ld_fail line(s), wanted 0 - 'any failed start prints it' is back")
  [ "$sc_ld_noisy" -ge 1 ] \
    || ld_bad+=("never up with a start command that prints: $sc_ld_noisy line(s), wanted at least 1 - this is the row that rules out the partial-state reading, and without it the gate cannot be told from 'already partial'")
  [ "$sc_ld_half" -eq 0 ] \
    || ld_bad+=("PARTIAL with a silent start command and an empty log: $sc_ld_half line(s), wanted 0 - being partial is opening the gate, which is the reading review measured against")
  [ "$sc_ld_part" -ge 1 ] \
    || ld_bad+=("the two-criteria fixture printed it on neither attempt, and its second attempt's log gains a traceback")
  if [ ${#ld_bad[@]} -eq 0 ]; then
    report PASS sc:log-detail "upstream gates it on the LOG HAVING CONTENT - not on failure, not on being partial"
    pass=$((pass+1))
  else
    report REFDRIFT sc:log-detail "upstream does not follow the recorded three-row table"
    for b in "${ld_bad[@]}"; do detail "$b"; done
    detail "the table in docs/messages.md is what is wrong here, not RMSC"
    refdrift=$((refdrift+1))
  fi

  # And the exit status the RMSC case above is asserted against.
  #
  # -1 means confirm_sc did not run the case - upstream was in a state it could
  # not use - and that is a SKIP rather than a drift. Reporting it as "upstream
  # exits -1" would read like a measurement, and the whole point of the value is
  # that no measurement was taken.
  if [ "$sc_fail_rc" -eq -1 ]; then
    report SKIPPED sc:fail-start-exit "sc:sc-fail did not run, so upstream's exit status was not observed"
    skipped=$((skipped+1))
  elif [ "$sc_fail_rc" -eq 253 ]; then
    report PASS sc:fail-start-exit "upstream exits 253 for a failed single-service start, as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT sc:fail-start-exit "upstream exits $sc_fail_rc, the recorded reference says 253"
    refdrift=$((refdrift+1))
  fi
else
  report SKIPPED sc:failure-anchors "upstream could not be driven against the staged definitions"
  skipped=$((skipped+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 4: upstream reference, re-measured against the same fixtures"
echo "   (every expectation above is either a markdown transcription, which"
echo "    cannot preserve a trailing space, or COMPOSED from captured parts."
echo "    A REFDRIFT here means the EXPECTATION is wrong, not RMSC.)"
echo
printf '  %-9s %-32s %s\n' verdict case detail
printf '  %-9s %-32s %s\n' --------- -------------------------------- ------
# ---------------------------------------------------------------------------

# WHY THIS STAGE IS NOT OPTIONAL, and why it is more than error-delivery-test.sh
# needs. That script re-confirms upstream's EXIT STATUSES - eight integers. This
# one has to re-confirm upstream's BYTES, because two things make the recorded
# expectations weaker than a capture:
#
#   1. docs/messages.md is markdown. The probe captured through `cat -A`, so
#      whoever read it could see a trailing space - but a table cell and a
#      fenced block do not preserve one, so the document cannot testify about
#      trailing whitespace either way. Every literal above assumes there is
#      none. This stage asks upstream.
#
#   2. Several expectations are COMPOSED - `Performing operation 'KILL' ...` is
#      the captured sentence with a verb the document never quotes, and the
#      stop-side dependency sequence is measured only in its
#      `is already stopped` form.
#
# Upstream is driven against THE SAME staged definitions, so the comparison is
# not against a transcription at all: it is sc's stdout against the same
# expected files RMSC's stdout was compared with.

# UPSTREAM MUST BE READING THE SAME STAGED DEFINITIONS, and that is proved
# before a single reference case runs.
#
# THIS IS THE GUARD THE FIRST VERSION OF THIS SCRIPT DID NOT HAVE, and it was
# wrong without it in a way worth writing down. Upstream's services directory is
# a JVM property, not the environment variable RMSC reads, so it is entirely
# possible for the staging to take on one side and not the other. When that
# happened every case in this stage found upstream unable to see the service,
# reported SKIPPED, and THE RUN STILL EXITED 0 - a green run whose entire
# anchor had quietly disappeared. Every COMPOSED expectation and every
# assumption about trailing whitespace in this file rests on this stage, so a
# stage that did not run is not a detail to note in passing.
#
# Proved the same way stage 0 proves RMSC's: from `check group:`, whose rows are
# the evidence and are not moved by anything under test.
sc_run sc-fixture-group -- check "group:$GROUP"
sc_gm=$(grep -c "rmscn_" "$WORK/sc.sc-fixture-group.out" 2>/dev/null || true)
[ -z "$sc_gm" ] && sc_gm=0
if [ "$sc_gm" -eq 2 ]; then
  sc_ok=1
  report PASS sc:staged-definitions "(fixture) upstream reads the same staged definitions"
  pass=$((pass+1))
else
  sc_ok=0
  report FAIL sc:staged-definitions "FIXTURE DID NOT TAKE: upstream sees $sc_gm member(s) of group:$GROUP, wanted 2"
  detail "JAVA_TOOL_OPTIONS=-Dservices.dir=$SVCDIR was not honoured, or the definitions did not load"
  detail "the reference cannot be re-measured, so every COMPOSED expectation in this"
  detail "file is unanchored and the no-trailing-whitespace assumption is unchecked"
  detail "artefacts: sc.sc-fixture-group.out sc.sc-fixture-group.err"
  failed=$((failed+1))
fi

# The floor below is about THIS stage, so it counts only what this stage did.
# Stage 3b confirms three cases of its own through the same helper, and a stage
# 4 that ran nothing would otherwise be excused by them.
sc_confirmed_before_stage4=$sc_confirmed

sc_down "$TOP" >/dev/null 2>&1
sc_down "$DEP" >/dev/null 2>&1
sc_down "$SOLO" >/dev/null 2>&1

confirm_sc start-success   "$WORK/e.start-success" "$SOLO" NOT     -- start "$SOLO"
confirm_sc start-already   "$WORK/e.start-already" "$SOLO" RUNNING -- start "$SOLO"
confirm_sc restart-from-up "$WORK/e.restart-up"    "$SOLO" RUNNING -- restart "$SOLO"
confirm_sc stop-success    "$WORK/e.stop-success"  "$SOLO" RUNNING -- stop  "$SOLO"
confirm_sc stop-already    "$WORK/e.stop-already"  "$SOLO" NOT     -- stop  "$SOLO"
confirm_sc kill-already    "$WORK/e.kill-already"  "$SOLO" NOT     -- kill  "$SOLO"
confirm_sc restart-from-down "$WORK/e.restart-down" "$SOLO" NOT    -- restart "$SOLO"

sc_down "$SOLO" >/dev/null 2>&1
sc_down "$TOP"  >/dev/null 2>&1
sc_down "$DEP"  >/dev/null 2>&1
confirm_sc deps-start "$WORK/e.deps-start" "$TOP" NOT -- start "$TOP"

sc_down "$TOP" >/dev/null 2>&1
confirm_sc deps-already-up "$WORK/e.deps-up" "$TOP" NOT -- start "$TOP"

sc_up "$TOP" >/dev/null 2>&1
confirm_sc deps-stop "$WORK/e.deps-stop" "$DEP" RUNNING -- stop "$DEP"

sc_down "$TOP" >/dev/null 2>&1
sc_down "$DEP" >/dev/null 2>&1

# A FLOOR ON THE STAGE, not merely on its individual cases. Ten skips and no
# confirmations is the shape a vanished reference takes, and it must not be
# reported as ten small omissions.
if [ "$sc_ok" -eq 1 ] && [ "$sc_confirmed" -eq "$sc_confirmed_before_stage4" ]; then
  report FAIL sc:reference-unanchored \
    "upstream loaded the definitions but not one reference case could be run"
  detail "every case found upstream in a state it could not use - the preconditions"
  detail "could not be established, so nothing in this file has been re-measured"
  failed=$((failed+1))
elif [ "$sc_ok" -eq 1 ]; then
  report PASS sc:reference-anchored "$sc_confirmed of the recorded expectations re-measured against upstream ($sc_confirmed_before_stage4 of them in stage 3b)"
  pass=$((pass+1))
fi

echo
echo "pass=$pass   failed=$failed   reference-drift=$refdrift   skipped=$skipped"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT CANNOT ASSERT, and where it would have to be done instead
#
#   THE WORDING. Every sentence is asserted byte for byte in
#   qtestsrc/SCOUT.TEST.RPGLE, where it needs no service. What is asserted here
#   is the wording only as it appears in a whole line of real output - so a
#   failure here on a line's text is the SAME defect SCOUT.TEST reports, and
#   SCOUT.TEST is the better place to read it from.
#
#   INTERLEAVING BETWEEN THE STREAMS. The two are captured separately, which
#   throws their relative order away. docs/messages.md § Narration is explicit
#   about the cost both ways: a merged view hides which stream a line went to,
#   and a separated view hides an ordering. The group-start transcript in that
#   document had to be re-read with the streams put back together before it made
#   sense. If a consumer ever reads them merged, that wants its own case, run
#   through a pty or a merged capture.
#
#   THE FAILURE NARRATION. `ERROR: Timed out waiting for service '<friendly>' to
#   start` and `ERROR: Could not start dependency '<short>' for service
#   '<friendly>': <nested>` are measured and are on STDERR, so they belong with
#   the error-delivery contract rather than here. tools/error-delivery-test.sh
#   already stages two services that fail to start and asserts the stream and
#   the exit status; what it does NOT assert is the wording, deliberately, and
#   that is the piece this family's failure side still wants.
#
#   THE `(asynchronously)` PROGRESS VARIANT. docs/messages.md measured that
#   batch_mode does NOT produce it and records where it comes from as unmeasured.
#   Nothing here asserts anything about it, and nothing should until it has been
#   seen.
#
#   COLOUR. Everything here runs with stdout redirected, so the wrapper never
#   appends --colors and the narration is captured uncoloured. Whether upstream
#   colours any of these lines at a terminal is not measured anywhere.
#
#   THE PARTIAL STATE. docs/parity.md's family table carries a fifth state from
#   the jar's catalogue - `Service '%s' is already partially running. You may
#   need to restart if this operation fails.` - which docs/messages.md's measured
#   narration table does not have. Nothing probed has produced it. It is not
#   asserted here or in SCOUT.TEST, and SCOUT_svc_state's four-state parameter
#   would have to grow a fifth value if it turns out to be reachable.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: narration does not match the measured family"
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer says what this file records."
  echo "The expectations here and in docs/messages.md rest on that - re-take the"
  echo "capture with tools/d2-probe.sh --narrate before trusting a pass or acting"
  echo "on a failure elsewhere."
  exit 1
fi
if [ "$skipped" -ne 0 ]; then
  echo "OK, WITH $skipped SKIPPED CASE(S): read the SKIPPED rows above - a case that"
  echo "could not reach its precondition proves nothing, and a run with skips is not"
  echo "the same evidence as a clean one."
  exit 0
fi
echo "OK: narration goes to stdout, in sequence, with one trailing blank, and -q leaves it alone"
