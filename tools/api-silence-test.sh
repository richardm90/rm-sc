#!/QOpenSys/pkgs/bin/bash
#
# api-silence-test.sh - "RMSC prints when a human is watching"
#
# SCAPI's header makes a promise, verbatim:
#
#   "Nothing here writes to standard output: a green-screen program calling
#    this must not have stray text appear underneath its display file, so
#    status is returned rather than printed."
#
# Nothing has ever checked it, and it is not true today. Measured 3 September
# 2026 against the build then deployed, through qtestsrc/SCAPIDRV.PGM.RPGLE:
#
#   SC_start of a service that comes up   -> 43 bytes on STDOUT
#       Service 'Zulu Api Up' successfully started
#   SC_stop  of a service with a dependent -> 140 bytes on STDOUT, three lines
#   SC_check_all, with a junk file staged   -> 160 bytes on STDERR
#       WARNING: Ignoring file: ...
#       WARNING: Unrecognized attribute 'no_such_key' in file ...
#   SC_start of a service that never comes up -> 221 bytes on STDERR
#       ... and ERROR: Timed out waiting for service 'Zulu Api Ok' to start
#   and on every one of those, msg came back EMPTY
#
# So both halves of the problem are real and both are reachable from here: the
# narration on stdout, added for the command line and now escaping through the
# API as well, and the loader warnings on stderr, which have been escaping since
# the load-time warnings moved off stdout.
#
# WHAT IS DELIBERATELY NOT HERE. The progress line - `Performing operation
# 'START' on service '<short>'` - is NOT emitted on the API path today, on any
# operation. Measured: `scr start x` prints it and SCAPIDRV start x does not, so
# it comes from the command-line dispatcher and not from SCEXEC. Nothing in this
# file asserts its absence from the API path, because an assertion that is true
# by construction cannot fail and would read like coverage of a rule it does not
# touch. The lines this file asserts about are exactly the lines that were
# measured escaping.
#
# ---------------------------------------------------------------------------
# WHY THERE IS A DRIVER PROGRAM, AND WHAT IT HAD TO BE
#
# The property under test is an ABSENCE ON A FILE DESCRIPTOR. iRPGUnit runs
# inside the ILE job whose descriptor 1 is the subject, and a suite cannot
# capture its own stdout - so no assertion in qtestsrc/*.TEST.RPGLE can see
# whether the promise holds. qtestsrc/SCOUT.TEST.RPGLE pins the silence FLAG's
# own contract, which is all it can reach, and says so.
#
# From the shell there was nothing to point at: `scripts/scr` runs SCRUN, which
# is the command line and is supposed to print, and the API is a set of bound
# procedures no shell can call. So the harness needed a caller of its own, and
# qtestsrc/SCAPIDRV.PGM.RPGLE is it - a program CALLable from `system -kpieO`
# that makes one API call and writes NOTHING to either stream itself. Its
# outcome goes to an IFS file, which is the whole reason it has one: a driver
# that reported by printing would make the assertion "the API path printed
# nothing" impossible to state.
#
# It is built here, on every run, rather than by TOBi. qtestsrc/ is excluded
# from SUBDIRS, so `makei build` never touches it, and a driver left over from
# an older build would test an older API. The build is a hard failure.
#
# ---------------------------------------------------------------------------
# THE DISCIPLINE THIS FILE IS BUILT ON: EVERY ABSENCE HAS A COMPANION
#
# An absence assertion is satisfied by a stub that does nothing at all. "The API
# path printed nothing" passes against an API that never ran, against a fixture
# that staged nothing, and against a services directory with no warnings to
# give. So every absence below is PAIRED with a companion that proves the thing
# would otherwise have been there, and the companions run FIRST:
#
#   absent on the API path                 companion, on the command line
#   ------------------------------------   --------------------------------
#   the two loader WARNING lines           scr check prints both on stderr
#   the state and dependency lines         scr start/stop print them on stdout
#   ERROR: Timed out waiting for service   scr start <fail> prints it on stderr
#
# and every absence is additionally paired with the driver's own RESULT FILE,
# which says the call was made and what it returned. Silence from a program that
# did nothing is not the silence being asked for.
#
# The same rule as tools/narration-test.sh's read-only-stays-silent case, which
# is where this discipline in this project comes from.
#
# ---------------------------------------------------------------------------
# BASIS OF EACH ASSERTION
#
#   measured   captured from the deployed build or from upstream sc 1.7.1 on
#              3 September 2026 and reproduced in the header above
#   design     the rule Richard settled - one switch silences both, for the API
#              path only, default off. A failure here means the implementation
#              took a different shape, not that a measurement drifted
#   inferred   follows from a rule stated in CLAUDE.md or docs/parity.md
#
# ---------------------------------------------------------------------------
# THIS SCRIPT STARTS AND STOPS SERVICES, and runs by default anyway - the same
# reasoning tools/narration-test.sh sets out. Everything it acts on is a
# definition it has just written, in a directory it invented, whose start
# command is a bounded python listener on a port it has proved free. Nothing on
# the system is started and nothing is stopped. Set API_SILENCE_DRY=1 to see the
# plan without running it.
# ---------------------------------------------------------------------------

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
SYSTEM="${SYSTEM:-/QOpenSys/usr/bin/system}"
DRVLIB="${DRVLIB:-RMSCT}"
DRVSRC="${DRVSRC:-$DEPLOY/qtestsrc/SCAPIDRV.PGM.RPGLE}"
PROTO="${PROTO:-$DEPLOY/QPROTOSRC}"
RMTOOLS_INC="${RMTOOLS_INC:-/prj/rmtools}"
WORK="${WORK:-/tmp/api-silence-test.$$}"

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
# The same block appears in all five harnesses. Deliberately duplicated rather
# than shared: each is deployed and run standalone, and a shared file would be
# a dependency that costs more than the repetition does. Change one, change
# all five.
ls -dt /tmp/api-silence-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
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

# The marker qtestsrc/SCAPIDRV.PGM.RPGLE writes through SCOUT_writeln after an
# API call. Kept in step with LEAK_MARKER in that file.
LEAK_MARKER='SCAPIDRV-STILL-SPEAKING'

# The sweep markers, kept in step with SWEEP_0..SWEEP_7 in the same file. One
# per return out of SCAPI's private funnel, plus a control written before any
# API call at all - see stage 3.
SWEEP_MARKS=(
  'SCAPIDRV-SWEEP-0-BEFORE-ANY-CALL'
  'SCAPIDRV-SWEEP-1-GROUP-NO-MEMBER'
  'SCAPIDRV-SWEEP-2-GROUP-RAN'
  'SCAPIDRV-SWEEP-3-UNKNOWN-SERVICE'
  'SCAPIDRV-SWEEP-4-SINGLE-RAN'
  'SCAPIDRV-SWEEP-5-NESTED-RESTART'
  'SCAPIDRV-SWEEP-6-KILL'
  'SCAPIDRV-SWEEP-7-CHECK-ALL'
)

# What each sweep step is, and what it must have returned for the step to have
# reached the shape it claims. A group nothing matched and an unknown service
# are REFUSALS, so they must come back false; the other four must succeed, or
# the run did not exercise the return it is named after.
SWEEP_LABELS=(- group-no-member group-ran unknown-single single-ran nested-restart kill check-all)
SWEEP_WANT_RC=(- 1 0 1 0 0 0 0)

PORT_UP=65360
PORT_DEP=65361
PORT_FAIL=65362

export QIBM_MULTI_THREADED=Y

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory. It needs" \
  "the wrapper for every COMPANION assertion - the command line is what proves" \
  "that the lines the API path must not print would otherwise have been there." \
  "Set SCR=<path> or DEPLOY=<deploy dir>."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "A staged service must ACTUALLY COME UP, or the case that asserts the API" \
  "path prints no 'successfully started' line passes because there was no such" \
  "line to print. A bare sleep can never satisfy a port criterion."

[ -f "$DRVSRC" ] || setup_fail \
  "the API driver source is missing: $DRVSRC" \
  "" \
  "qtestsrc/SCAPIDRV.PGM.RPGLE is the only caller of the bound-call API that a" \
  "shell can reach. Without it nothing in this file can observe anything."

mkdir -p "$SVCDIR" || setup_fail "cannot create $SVCDIR"

cat > "$WORK/listen.py" <<'EOF'
import socket, sys, time
s = socket.socket()
s.bind(("", int(sys.argv[1])))
s.listen(5)
time.sleep(600)
EOF

cat > "$WORK/nobind.py" <<'EOF'
import time
time.sleep(600)
EOF

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

for p in "$PORT_UP" "$PORT_DEP" "$PORT_FAIL"; do
  port_free "$p" || setup_fail \
    "port $p is already in use" \
    "" \
    "A service checked on it would read RUNNING before this script started" \
    "anything, and PORT_FAIL in particular must never be bound: the whole" \
    "failure case rests on a start that times out. Free it, or move the PORT_*" \
    "values at the top of this script."
done

# ---------------------------------------------------------------------------
# The staged definitions.
#
#   zzapis_up    Zulu Api Alpha    comes up - its start command binds the port
#                                  it is checked on. It is also the ONLY member
#                                  of $GRP, which is what makes stage 3's
#                                  "a group operation that ran" step run
#   zzapis_dep   Zulu Api Bravo    depends on zzapis_up, so starting it prints
#                                  the dependency line AND two outcome lines -
#                                  the run with the most stdout on the API path,
#                                  and therefore the sharpest absence
#   zzapis_fail  Zulu Api Charlie  never comes up, so the start times out and
#                                  the ERROR line is produced
#
# and two things that exist only to make the LOADER speak:
#
#   notes.txt              a file the filename rule rejects
#                          -> WARNING: Ignoring file: <path>
#   zzapis_odd.yaml        a definition carrying a key RMSC does not know
#                          -> WARNING: Unrecognized attribute '<k>' in file <p>
#
# Short names are lower case with underscores and friendly names are
# capitalised words, and no short name is a substring of any friendly name -
# the same rule tools/narration-test.sh states, for the same reason.
# ---------------------------------------------------------------------------
UP=zzapis_up;     UP_F='Zulu Api Alpha'
DEP=zzapis_dep;   DEP_F='Zulu Api Bravo'
FAIL=zzapis_fail; FAIL_F='Zulu Api Charlie'
ODD=zzapis_odd;   ODD_F='Zulu Api Delta'
ODDKEY=no_such_attribute_here

# TWO GROUP NAMES, AND THE SECOND ONE IS DELIBERATELY EMPTY.
#
# Stage 3's sweep needs a group operation of each shape, because SCAPI's four
# public operations funnel through one private procedure that returns from four
# places and only two of them are group-shaped:
#
#   $GRP     zzapis_up belongs to it, so a group start RUNS
#   $NOGRP   nothing belongs to it, so a group start matches NO MEMBER
#
# The empty one needs no definition - being unclaimed IS the fixture - but it
# is named here rather than written inline so that a definition acquiring this
# group by accident is a one-line change to notice.
GRP=zzapisgrp
NOGRP=zzapisnogrp

{
  printf 'name: %s\n' "$UP_F"
  printf 'start_cmd: %s %s/listen.py %s\n' "$PY" "$WORK" "$PORT_UP"
  printf 'check_alive: %s\n' "$PORT_UP"
  printf 'startup_wait_time: 20\n'
  printf 'stop_wait_time: 10\n'
  printf 'groups:\n  - %s\n' "$GRP"
} > "$SVCDIR/$UP.yaml"

{
  printf 'name: %s\n' "$DEP_F"
  printf 'start_cmd: %s %s/listen.py %s\n' "$PY" "$WORK" "$PORT_DEP"
  printf 'check_alive: %s\n' "$PORT_DEP"
  printf 'startup_wait_time: 20\n'
  printf 'stop_wait_time: 10\n'
  printf 'service_dependencies:\n  - %s\n' "$UP"
} > "$SVCDIR/$DEP.yaml"

# startup_wait_time is 2 rather than 20: this one is WAITED OUT on every run.
{
  printf 'name: %s\n' "$FAIL_F"
  printf 'start_cmd: %s %s/nobind.py\n' "$PY" "$WORK"
  printf 'check_alive: %s\n' "$PORT_FAIL"
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$FAIL.yaml"

{
  printf 'name: %s\n' "$ODD_F"
  printf 'start_cmd: /QOpenSys/usr/bin/true\n'
  printf 'check_alive: ZZAPISNOSUCHJOB\n'
  printf 'startup_wait_time: 2\n'
  printf 'stop_wait_time: 2\n'
  printf '%s: 1\n' "$ODDKEY"
} > "$SVCDIR/$ODD.yaml"

printf 'this is not a service definition\n' > "$SVCDIR/notes.txt"

kill_listeners() {
  local d="$1" p
  for p in $(ps -ef 2>/dev/null | grep -E "$d/(listen|nobind)\.py" | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}

cleanup() {
  local s
  for s in "$DEP" "$UP" "$FAIL" "$ODD"; do
    SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$s" >/dev/null 2>&1
  done
  kill_listeners "$WORK"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

if [ -n "${API_SILENCE_DRY:-}" ]; then
  echo "api-silence-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

pass=0; failed=0

report() { printf '  %-9s %-34s %s\n' "$1" "$2" "${*:3}"; }
detail() { printf '  %-9s %-34s   - %s\n' "" "" "$*"; }

check_named() {  # tag basis note problem...
  local tag="$1" basis="$2" note="$3"; shift 3
  if [ $# -eq 0 ]; then
    report PASS "$tag" "($basis) $note"
    pass=$((pass+1))
    return 0
  fi
  report FAIL "$tag" "($basis)"
  local p; for p in "$@"; do detail "$p"; done
  failed=$((failed+1))
  return 1
}

bytes()   { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo MISSING; fi; }
has_line() { grep -Fqx -- "$2" "$1" 2>/dev/null; }
has_text() { grep -Fq  -- "$2" "$1" 2>/dev/null; }
first()   { head -n 1 "$1" 2>/dev/null | cut -c1-100; }

# scr_run TAG -- argv...   the command line, two streams kept apart.
scr_run() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  local rc
  SC_SERVICES_DIR="$SVCDIR" "$SCR" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  rc=$?
  return $rc
}

# drv TAG OP SVC [--no-services-dir]   the API, through the driver.
#
# Leaves $WORK/TAG.out, .err and .res behind. .res is the driver's result file
# and is the proof that the call was made at all.
#
# SCAPIDRV_GRP and SCAPIDRV_NOGRP go on every call. Only leak-sweep reads them,
# and passing them unconditionally keeps one place where the fixture names are
# written down rather than two.
drv() {
  local tag="$1" op="$2" svc="$3" nodir="${4:-}"
  local rc
  rm -f "$WORK/$tag.res"
  if [ "$nodir" = "--no-services-dir" ]; then
    env -u SC_SERVICES_DIR \
      SCAPIDRV_OP="$op" SCAPIDRV_SVC="$svc" SCAPIDRV_OUT="$WORK/$tag.res" \
      SCAPIDRV_GRP="$GRP" SCAPIDRV_NOGRP="$NOGRP" \
      "$SYSTEM" -kpieO "CALL $DRVLIB/SCAPIDRV" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  else
    SC_SERVICES_DIR="$SVCDIR" \
      SCAPIDRV_OP="$op" SCAPIDRV_SVC="$svc" SCAPIDRV_OUT="$WORK/$tag.res" \
      SCAPIDRV_GRP="$GRP" SCAPIDRV_NOGRP="$NOGRP" \
      "$SYSTEM" -kpieO "CALL $DRVLIB/SCAPIDRV" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  fi
  rc=$?
  return $rc
}

res_field() {  # TAG FIELD -> the value, or the empty string
  sed -n "s/^$2=//p" "$WORK/$1.res" 2>/dev/null | head -n 1
}

# THE COMMON HALF OF EVERY SILENCE CASE.
#
# Both streams byte-empty, and the call demonstrably made. Byte-empty rather
# than "carries no narration sentence" on purpose: SCAPI's promise is about the
# DESCRIPTOR, not about a family of sentences, and a display file is corrupted
# by any byte at all - including one from a message this file has never heard
# of. A weaker rule would pass a fix that silenced the sentences it knew about.
silence_problems() {  # TAG -> echoes one problem per line
  local tag="$1"
  local o="$WORK/$tag.out" e="$WORK/$tag.err" r="$WORK/$tag.res"
  local nb

  if [ ! -f "$r" ]; then
    echo "the driver wrote no result file, so the API call cannot be shown to have happened - an empty stream from a program that did not run proves nothing"
    return
  fi
  if ! grep -q '^rc=' "$r"; then
    echo "the result file carries no rc= line: $(first "$r")"
    return
  fi

  nb=$(bytes "$o")
  [ "$nb" = 0 ] || echo "$nb byte(s) on STDOUT, wanted 0: [$(first "$o")]"
  nb=$(bytes "$e")
  [ "$nb" = 0 ] || echo "$nb byte(s) on STDERR, wanted 0: [$(first "$e")]"
}

printf 'api silence: what a bound-call caller receives on its two streams\n'
printf 'scr:    %s\n' "$SCR"
printf 'driver: %s/SCAPIDRV  (rebuilt from %s)\n' "$DRVLIB" "$DRVSRC"
printf 'staged: %s   (ports %s %s %s)\n\n' "$SVCDIR" "$PORT_UP" "$PORT_DEP" "$PORT_FAIL"

# ---------------------------------------------------------------------------
echo "== stage 0: the driver builds, and the fixture proves itself"
echo
printf '  %-9s %-34s %s\n' verdict case detail
printf '  %-9s %-34s %s\n' --------- ---------------------------------- ------
# ---------------------------------------------------------------------------

# THE DRIVER IS BUILT ON EVERY RUN, and a stale one is the failure mode worth
# naming. qtestsrc/ is excluded from SUBDIRS so `makei build` never touches it;
# an object left from an older build would be bound to an older API and would
# answer a question about that instead.
qsh -c "liblist -a RMSC; liblist -a $DRVLIB; liblist -a RMTOOLS;
        system \"CRTBNDRPG PGM($DRVLIB/SCAPIDRV) SRCSTMF('$DRVSRC') DFTACTGRP(*NO) TGTCCSID(*JOB) INCDIR('$PROTO' '$RMTOOLS_INC')\"" \
  > "$WORK/build.log" 2>&1
if grep -q 'placed in library' "$WORK/build.log"; then
  report PASS driver-builds "(fixture) SCAPIDRV rebuilt into $DRVLIB from the deployed source"
  pass=$((pass+1))
else
  report FAIL driver-builds "FIXTURE DID NOT TAKE: SCAPIDRV would not compile"
  grep -E '^ +\*RNF[0-9]+ +[13-9][0-9]' "$WORK/build.log" | head -n 8 | while IFS= read -r l; do detail "$l"; done
  detail "nothing below can run: the driver is the only caller of the API a shell can reach"
  detail "build log: $WORK/build.log"
  detail "if the complaint is SCOUT_set_silent or SCOUT_silent, the flag is not exported yet"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed"
  echo "FAILED: the API driver could not be built"
  exit 1
fi

# THE STAGING TOOK. Proved from `check`, whose row is evidence and is not moved
# by anything under test - the same guard, and the same reasoning, as
# tools/narration-test.sh's stage 0.
scr_run fixture-check -- check "$UP"
if grep -Fq "$UP ($UP_F)" "$WORK/fixture-check.out"; then
  report PASS staged-definitions "(fixture) $UP is visible to RMSC through SC_SERVICES_DIR"
  pass=$((pass+1))
else
  report FAIL staged-definitions "FIXTURE DID NOT TAKE: check does not see $UP"
  detail "check said: $(first "$WORK/fixture-check.out")"
  detail "every absence below would pass against a directory RMSC never read"
  failed=$((failed+1))
fi

# ---------------------------------------------------------------------------
# THE COMPANIONS. Every one of these must be POSITIVE, and they run before any
# absence is asserted, because an absence whose companion failed is not evidence
# of anything.
# ---------------------------------------------------------------------------

# (a) the loader warns, on stderr, for this directory
w_ignore="WARNING: Ignoring file: $SVCDIR/notes.txt"
w_attr="WARNING: Unrecognized attribute '$ODDKEY' in file $SVCDIR/$ODD.yaml"

probs=()
has_line "$WORK/fixture-check.err" "$w_ignore" \
  || probs+=("the command line does not warn about the junk file: [$w_ignore]")
has_line "$WORK/fixture-check.err" "$w_attr" \
  || probs+=("the command line does not warn about the unrecognised key: [$w_attr]")
[ "$(bytes "$WORK/fixture-check.out")" != 0 ] \
  || probs+=("check printed nothing on stdout, so this run tested nothing")
check_named companion-loader-warns measured \
  "both loader warnings are on the command line's stderr" "${probs[@]}"

# (b) the state and dependency lines are on the command line's stdout
#
# ASSERTED ON EXACTLY THE LINES THE API PATH EMITS, and not on the progress
# line. `Performing operation ...` comes from the command-line dispatcher and
# never reaches the API path at all, so its presence here would prove nothing
# about what the API is being asked not to print.
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$DEP" >/dev/null 2>&1
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$UP"  >/dev/null 2>&1
sleep 2
scr_run companion-start -- start "$DEP"

probs=()
has_line "$WORK/companion-start.out" "Attempting to start service dependency '$UP' ($UP_F)..." \
  || probs+=("no dependency line on stdout - the sharpest absence below has no companion")
has_line "$WORK/companion-start.out" "Service '$UP_F' successfully started" \
  || probs+=("no 'successfully started' line for the dependency on stdout")
has_line "$WORK/companion-start.out" "Service '$DEP_F' successfully started" \
  || probs+=("no 'successfully started' line for $DEP on stdout")
check_named companion-narrates measured \
  "the dependency walk prints three lines on the command line's stdout" "${probs[@]}"

SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$DEP" >/dev/null 2>&1
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$UP"  >/dev/null 2>&1
sleep 2

# (c) the timeout ERROR is on the command line's stderr
e_timeout="ERROR: Timed out waiting for service '$FAIL_F' to start"
scr_run companion-fail -- start "$FAIL"
probs=()
has_line "$WORK/companion-fail.err" "$e_timeout" \
  || probs+=("the command line does not produce the timeout error: [$e_timeout]; first stderr line: $(first "$WORK/companion-fail.err")")
check_named companion-errors measured \
  "the timeout error is on the command line's stderr" "${probs[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the API path says nothing, on either stream"
echo
printf '  %-9s %-34s %s\n' verdict case detail
printf '  %-9s %-34s %s\n' --------- ---------------------------------- ------
# ---------------------------------------------------------------------------
#
# THE TWO HALVES ARE SEPARATED ON PURPOSE, and this is the separating value for
# "ONE switch silences BOTH":
#
#   check-all  loads definitions and does nothing else. It produces the loader
#              WARNINGs on stderr and NO narration at all. A fix that silenced
#              only SCOUT_writeln leaves this case red.
#   start (up) narrates on stdout and produces nothing on stderr. A fix that
#              silenced only SCOUT_warnln leaves this case red.
#
# Either case alone would pass against half a fix. Neither is redundant.

# --- the loader half -------------------------------------------------------
#
# THE FIXTURE PROOF THIS CASE NEEDS IS ITS OWN. "No warnings appeared" passes
# against a services directory that was never read, so the row count is compared
# with and without SC_SERVICES_DIR: the staged directory must contribute
# services, or there was nothing there to warn about and the silence is vacuous.
drv api-check-bare  check-all '' --no-services-dir
drv api-check-all   check-all ''

rows_staged=$(res_field api-check-all msg)
rows_bare=$(res_field api-check-bare msg)
n_staged=${rows_staged#rows=}
n_bare=${rows_bare#rows=}

probs=()
case "$n_staged$n_bare" in
  *[!0-9]*|'') probs+=("the driver did not report row counts: staged [$rows_staged] bare [$rows_bare]") ;;
  *) [ "$n_staged" -gt "$n_bare" ] \
       || probs+=("SC_check_all sees $n_staged services with SC_SERVICES_DIR set and $n_bare without it - the staged directory contributed nothing, so there was nothing for the loader to warn about and an empty stderr means nothing") ;;
esac
while IFS= read -r p; do [ -n "$p" ] && probs+=("$p"); done < <(silence_problems api-check-all)
check_named api-loader-warnings-silent design \
  "SC_check_all loads $n_staged services and says nothing ($n_bare without the staged directory)" "${probs[@]}"

# --- the narration half, on a start that SUCCEEDS --------------------------
#
# The dependency walk, because it is the run with the most stdout on the API
# path: three lines today, one of them the dependency line that carries a
# parenthesised name. A fix that suppressed outcome lines and forgot the
# dependency line fails here and nowhere else.
drv api-start-dep start "$DEP"

probs=()
[ "$(res_field api-start-dep rc)" = 0 ] \
  || probs+=("the driver reports rc=$(res_field api-start-dep rc) - the start did not succeed, so an absence of 'successfully started' proves nothing; msg=[$(res_field api-start-dep msg)]")
while IFS= read -r p; do [ -n "$p" ] && probs+=("$p"); done < <(silence_problems api-start-dep)
check_named api-narration-silent design \
  "a dependency walk that started two services printed nothing" "${probs[@]}"

# --- and on a stop, which walks the other way ------------------------------
drv api-stop stop "$UP"

probs=()
[ "$(res_field api-stop rc)" = 0 ] \
  || probs+=("the driver reports rc=$(res_field api-stop rc) for the stop; msg=[$(res_field api-stop msg)]")
while IFS= read -r p; do [ -n "$p" ] && probs+=("$p"); done < <(silence_problems api-stop)
check_named api-stop-silent design \
  "stopping a service with a dependent printed nothing" "${probs[@]}"

SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$DEP" >/dev/null 2>&1
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$UP"  >/dev/null 2>&1
sleep 2

# --- and on a start that FAILS ---------------------------------------------
#
# The stderr half again, and by a different route from the loader warnings: this
# one is SCEXEC's own error line rather than the collection loader's. Both are
# on stderr and a single switch has to catch both, so both are asked.
#
# THE MESSAGE IS ASSERTED HERE TOO. A failure that reports no reason is the
# regression qtestsrc/SCAPI.TEST.RPGLE was extended for; this is the same rule
# seen from outside the job, and it is the reason the silence is safe to want.
# Silencing a stream that carried the only copy of the reason would be a
# straight loss of information - it is only acceptable BECAUSE the reason comes
# back in msg.
drv api-start-fail start "$FAIL"

probs=()
[ "$(res_field api-start-fail rc)" = 1 ] \
  || probs+=("the driver reports rc=$(res_field api-start-fail rc) - the start did not fail, so an absence of the timeout error proves nothing")
while IFS= read -r p; do [ -n "$p" ] && probs+=("$p"); done < <(silence_problems api-start-fail)
check_named api-error-silent design \
  "a start that timed out printed nothing" "${probs[@]}"

# THE GUARD COMES FIRST, and it is not a formality. A start that SUCCEEDED
# returns an empty message and is right to - there is no reason to report - so
# without this the case would fire its "the reason is lost" complaint at a run
# where nothing was lost, and name a defect that was not there. A case failing
# for a reason its own description does not cover is worse than no case at all.
probs=()
fmsg=$(res_field api-start-fail msg)
frc=$(res_field api-start-fail rc)
if [ "$frc" != 1 ]; then
  probs+=("the driver reports rc=$frc - the staged service did not fail to start, so there is no reason for it to report and this case cannot ask about one")
else
  [ -n "$fmsg" ] \
    || probs+=("SC_start returned failure with an EMPTY message - through the API the reason is simply lost, and it is the only copy once the stream is silenced")
  case "$fmsg" in
    ''|*"$FAIL"*|*"$FAIL_F"*) ;;
    *) probs+=("the message does not name the service by either name: [$fmsg]") ;;
  esac
fi
check_named api-failure-has-a-reason measured \
  "a failed start returns a message: [$fmsg]" "${probs[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 2: the command line is untouched - the switch defaults OFF"
echo
printf '  %-9s %-34s %s\n' verdict case detail
printf '  %-9s %-34s %s\n' --------- ---------------------------------- ------
# ---------------------------------------------------------------------------
#
# THE OTHER HALF OF THE DESIGN, and the half a silence switch is most likely to
# break. Richard's rule is "RMSC prints when a human is watching", and the two
# ways to get that wrong in one direction are a flag that defaults ON and a
# flag set in SCOUT's own initialisation rather than by SCAPI. Both leave the
# command line mute, and neither is visible from stage 1 - every case there
# asserts an ABSENCE, and both mistakes make absences MORE true.
#
# So this repeats the companions AFTER the API path has run, and requires them
# still to be positive. The runs are separate jobs, so this cannot detect state
# leaking between them; what it detects is the flag being on when nobody asked.

SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$DEP" >/dev/null 2>&1
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$UP"  >/dev/null 2>&1
sleep 2
scr_run after-start -- start "$DEP"
scr_run after-check -- check "$UP"

probs=()
has_line "$WORK/after-start.out" "Performing operation 'START' on service '$DEP'" \
  || probs+=("no progress line on stdout after the API path ran")
has_line "$WORK/after-start.out" "Attempting to start service dependency '$UP' ($UP_F)..." \
  || probs+=("no dependency line on stdout")
has_line "$WORK/after-start.out" "Service '$DEP_F' successfully started" \
  || probs+=("no outcome line on stdout")
check_named cmdline-still-narrates design \
  "the command line still prints its narration" "${probs[@]}"

probs=()
has_line "$WORK/after-check.err" "$w_ignore" \
  || probs+=("the command line no longer warns about the junk file - the switch is silencing more than the API path")
has_line "$WORK/after-check.err" "$w_attr" \
  || probs+=("the command line no longer warns about the unrecognised key")
check_named cmdline-still-warns design \
  "the command line still warns about what it cannot load" "${probs[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 3: the switch is module state - does it outlive the call?"
echo
printf '  %-9s %-34s %s\n' verdict case detail
printf '  %-9s %-34s %s\n' --------- ---------------------------------- ------
# ---------------------------------------------------------------------------
#
# THE HAZARD, STATED PLAINLY. A flag held in SCOUT is MODULE state: it lives for
# the whole activation, not for the call. If SCAPI switches it on and never
# switches it back, then everything else that shares the activation is silenced
# too - and silenced invisibly, because nothing returns an error and nothing
# appears.
#
# WHY THAT IS NOT HYPOTHETICAL. SCAPI's own reason for existing is a green-
# screen program, and a green-screen program is exactly the kind that calls
# several things in one activation group. A caller that does SC_check_all to
# fill a subfile and then, for its own reasons, writes a line through SCOUT gets
# nothing, with no way to find out why.
#
# THE PROBE. qtestsrc/SCAPIDRV.PGM.RPGLE's leak-probe operation makes an API
# call and then writes a marker through SCOUT_writeln - the ordinary way any
# consumer of the service program writes a line. The marker must appear.
#
# WHAT THIS CASE REACHES, AND WHAT IT DOES NOT. leak-probe calls SC_check_all,
# and SC_check_all reaches the LOADER and nothing else. It never enters the
# private procedure the four public operations funnel through, so this case
# alone leaves the four returns out of that procedure covered by no assertion:
# any one of their restores could be deleted and this would still pass. The
# api-leak-sweep case below is what covers them, and this one is kept as the
# cheap control for the one path it does reach.
#
# THE TWO DESIGNS THIS TELLS APART, on the loader path:
#
#   set on entry, never restored   the marker is SWALLOWED. Silence has escaped
#                                  the call it was meant to scope, and the flag
#                                  is now a property of the job.
#   saved and restored round each  the marker APPEARS. Silence lasts exactly as
#   API entry point                long as the call, which is what "for the API
#                                  path only" has to mean if it is to mean
#                                  anything.
#
# A FAILURE HERE IS A DESIGN VERDICT, NOT A DEFECT REPORT. It says the flag was
# switched on and left on, and the choice is between saving and restoring it in
# SCAPI - which costs one local variable per entry point - and writing down that
# any caller of the API forfeits SCOUT for the rest of the job.
#
# IT PASSES TODAY, because there is no silence yet, and it is recorded as a
# DESIGN PIN rather than as a red-before-the-fix for that reason. Its ability to
# fail was proved by mutation: pointed at a marker the driver does not write, it
# reports the swallow.
drv leak-probe leak-probe ''

probs=()
if [ ! -f "$WORK/leak-probe.res" ]; then
  probs+=("the driver wrote no result file, so nothing about the marker can be concluded")
elif [ "$(res_field leak-probe rc)" != 0 ]; then
  probs+=("SC_check_all returned rc=$(res_field leak-probe rc) inside the probe - the API call has to succeed for the marker that follows it to mean anything")
else
  # ONLY THE MARKER IS ASKED ABOUT HERE, and the streams deliberately are not.
  #
  # An earlier version also required this run's stderr to be empty, and it was
  # wrong in the way tools/narration-test.sh records for its own timeout case:
  # it made this case fail on the loader warnings, which stage 1 already owns,
  # so the report said "silence outlived the call" about a run where the marker
  # was present and nothing had leaked. A case failing for a reason its own
  # description does not cover is worse than no case at all.
  has_line "$WORK/leak-probe.out" "$LEAK_MARKER" \
    || probs+=("SCOUT_writeln wrote nothing after the API call: the marker [$LEAK_MARKER] is not on stdout, so the silence outlived the call and now belongs to the activation")
fi
check_named silence-does-not-outlive-the-call design \
  "a write after the API call is still seen" "${probs[@]}"

# ---------------------------------------------------------------------------
# THE SWEEP: every return out of SCAPI's private funnel, in ONE activation
#
# WHY THE CASE ABOVE IS NOT ENOUGH, stated as the gap it left. SC_start,
# SC_stop, SC_kill and SC_restart all go through one private procedure, and
# that procedure returns from FOUR places:
#
#   a group operation where NO MEMBER MATCHED
#   a group operation that RAN
#   an UNKNOWN single service
#   a single service that RAN
#
# Each has to put the silence flag back. leak-probe reaches none of them - it
# calls SC_check_all, which stops at the loader - and qtestsrc/SCAPI.TEST.RPGLE
# does not include SCOUT_D at all, so it cannot ask what the flag holds. The
# consequence was exact and worth writing down: DELETE ANY ONE OF THE FOUR
# RESTORES AND EVERY SUITE IN THIS PROJECT STAYED GREEN.
#
# ONE ACTIVATION IS THE WHOLE POINT. The flag is module state, so a leak is only
# observable by something that runs LATER IN THE SAME JOB. Seven separate driver
# runs would be seven fresh activations and would each start from a clean flag,
# which is precisely the mistake that makes a leak invisible in ordinary use. So
# the driver makes all seven calls in one CALL, and writes a distinct marker
# after each.
#
# WHAT EACH OF THE THREE ASSERTIONS BELOW RULES OUT:
#
#   the marker after every step is on stdout
#       the leak itself. If step N's restore is missing, the flag is still on
#       when step N's marker is written, so that marker and every one after it
#       is swallowed - the FIRST missing marker names the return that leaked.
#       That is why there is one marker per step and not one at the end: a
#       single marker would go missing for any of the four and say nothing
#       about which
#
#   SCOUT_silent() reads 0 after every step
#       the same defect named directly rather than through its consequence,
#       and it survives changes that would blunt the marker rule. It is not a
#       duplicate: a fix that put the flag back but left SCOUT unable to write
#       would satisfy this and fail that, and one that left the flag on while
#       SCOUT wrote anyway would do the reverse. Both are asked because either
#       alone would accept half a fix
#
#   stdout carries the markers and NOTHING ELSE, stderr nothing at all
#       the OTHER half, and the nested restart is what needs it. A restore that
#       assigns "off" instead of putting the SAVED value back is correct for
#       every step here except step 5, where the inner call returns into an
#       outer one that is still supposed to be silent - and the symptom is not
#       a missing marker but an EXTRA line, the outer operation's narration
#       arriving after the inner one un-silenced it. Only a whole-stream rule
#       can see that
#
# AND THE FIXTURE PROVES ITSELF FIRST, as everything in this file does. An
# absence is satisfied by a program that did nothing, and so is a flag that
# reads 0 because no call was ever made. The result file carries one line per
# step with the verdict that step reached, and the step that was supposed to be
# refused must have been refused: if the empty group turned out to have a
# member, that step reached the "ran" return and the run never visited the
# return it is named after.
drv api-sweep leak-sweep "$DEP"

sweep_field() {  # N FIELD -> the value from sweep<N>=...|FIELD=...|
  sed -n "s/^sweep$1=//p" "$WORK/api-sweep.res" 2>/dev/null | head -n 1 \
    | tr '|' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# (a) the fixture: seven steps, each reaching the verdict its shape requires
probs=()
if [ ! -f "$WORK/api-sweep.res" ]; then
  probs+=("the driver wrote no result file - the sweep did not run, and nothing below means anything")
else
  for n in 1 2 3 4 5 6 7; do
    got_lbl=$(sed -n "s/^sweep$n=//p" "$WORK/api-sweep.res" | head -n 1 | cut -d'|' -f1)
    got_rc=$(sweep_field "$n" rc)
    want_lbl=${SWEEP_LABELS[$n]}
    want_rc=${SWEEP_WANT_RC[$n]}
    if [ -z "$got_lbl" ]; then
      probs+=("step $n ($want_lbl) is not in the result file - the sweep stopped before it")
    elif [ "$got_lbl" != "$want_lbl" ]; then
      probs+=("step $n reports '$got_lbl' where this harness expects '$want_lbl' - the driver and this file have drifted apart")
    elif [ "$got_rc" != "$want_rc" ]; then
      probs+=("step $n ($want_lbl) returned rc=$got_rc, wanted $want_rc: msg=[$(sweep_field "$n" msg)]. That step did not reach the shape it is named after, so its restore was never exercised")
    fi
  done
fi
check_named api-sweep-fixture design \
  "all seven shapes reached a verdict, refusals refused and operations run" "${probs[@]}"

# (b) THE DEFAULT IN A FRESH ACTIVATION, which this file has recorded as out of
# reach ever since it was written - see "WHAT THIS SCRIPT CANNOT ASSERT" at the
# end. The driver now reads SCOUT_silent() BEFORE it makes any API call, in a
# job that has not yet entered SCAPI, so the question is settled here rather
# than inferred from the command line not having been muted.
probs=()
sb=$(sed -n 's/^silent_before=//p' "$WORK/api-sweep.res" 2>/dev/null | head -n 1)
case "$sb" in
  0) ;;
  1) probs+=("SCOUT_silent() reads ON in a job that has not called SCAPI at all - the flag defaults ON, and every consumer of the service program is muted until something turns it off") ;;
  *) probs+=("the driver did not report the flag's value before its first call: [$sb]") ;;
esac
check_named api-silence-defaults-off design \
  "the flag reads OFF before the activation has entered SCAPI" "${probs[@]}"

# (c) the flag is back after every one of the four returns
probs=()
for n in 1 2 3 4 5 6 7; do
  sv=$(sweep_field "$n" silent)
  case "$sv" in
    0) ;;
    1) probs+=("after step $n (${SWEEP_LABELS[$n]}) SCOUT_silent() still reads ON - that return does not put the flag back, and everything later in the activation is mute") ;;
    *) probs+=("step $n (${SWEEP_LABELS[$n]}) reported no flag reading: [$sv]") ;;
  esac
done
check_named api-sweep-flag-restored design \
  "the silence flag is put back at every return out of the funnel" "${probs[@]}"

# (d) and the consequence: every marker was actually written
probs=()
missing=''
for m in "${SWEEP_MARKS[@]}"; do
  if ! has_line "$WORK/api-sweep.out" "$m"; then
    [ -z "$missing" ] && missing="$m"
    probs+=("$m is not on stdout")
  fi
done
case "$missing" in
  'SCAPIDRV-SWEEP-0-BEFORE-ANY-CALL')
    probs+=("and it is the CONTROL, written before any API call - SCOUT could not write in this job at all, so nothing above is about silence") ;;
  '') ;;
  *)  probs+=("the first missing marker is $missing, so the return that step reached is the one that did not put the flag back") ;;
esac
check_named api-sweep-markers-survive design \
  "a write after every one of the four returns is still seen" "${probs[@]}"

# (e) the whole stream, which is what the nested restart needs
probs=()
n_lines=$(grep -c '' "$WORK/api-sweep.out" 2>/dev/null || true); [ -z "$n_lines" ] && n_lines=0
n_marks=${#SWEEP_MARKS[@]}
if [ "$n_lines" -gt "$n_marks" ]; then
  probs+=("$n_lines line(s) on stdout where only the $n_marks markers were wanted - the surplus is RMSC's own narration arriving on a path that promised none, which is what a restore that assigns OFF rather than putting the saved value back produces at step 5")
  while IFS= read -r l; do
    probs+=("  unexpected: [$l]")
  done < <(grep -Fv -f <(printf '%s\n' "${SWEEP_MARKS[@]}") "$WORK/api-sweep.out" 2>/dev/null | head -n 5)
elif [ "$n_lines" -lt "$n_marks" ]; then
  # FEWER lines is the LEAK, not a surplus, and api-sweep-markers-survive owns
  # that verdict and names the step. Saying it here as well would report one
  # defect twice under two descriptions; saying it in the surplus's words would
  # describe it wrongly.
  probs+=("only $n_lines of the $n_marks markers reached stdout - that is the leak, and api-sweep-markers-survive above says which step it starts at")
fi
nb=$(bytes "$WORK/api-sweep.err")
[ "$nb" = 0 ] || probs+=("$nb byte(s) on STDERR, wanted 0: [$(first "$WORK/api-sweep.err")]")
check_named api-sweep-nothing-else design \
  "the markers are the only thing on stdout, and stderr is empty" "${probs[@]}"

# The sweep killed $DEP and left $UP up. Put the fixture back down so a later
# run of this script starts from the same place - the cleanup trap does it too,
# but not until the script ends.
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$DEP" >/dev/null 2>&1
SC_SERVICES_DIR="$SVCDIR" "$SCR" stop "$UP"  >/dev/null 2>&1

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (.out .err .res per case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT CANNOT ASSERT
#
#   THE FLAG'S OWN CONTRACT. SCOUT_set_silent and SCOUT_silent are procedures,
#   and their round trip, their default and their independence from
#   SCOUT_set_colour belong in qtestsrc/SCOUT.TEST.RPGLE, where they need no
#   service and no fixture. What is here is only what needs a file descriptor.
#
#   (THE DEFAULT VALUE IN A FRESH ACTIVATION used to be listed here, and it is
#   now asserted: SCOUT_set_silent and SCOUT_silent are exported, so leak-sweep
#   reads the flag before it makes any call and api-silence-defaults-off in
#   stage 3 states the answer. It is left recorded here only so that the note
#   which promised it can be seen to have been kept.)
#
#   WHICH RETURN A STEP TOOK, from outside. The sweep reaches each of the four
#   returns by giving the funnel an argument of that SHAPE - an unclaimed group,
#   a claimed one, a name nothing answers to, a live service - and proves the
#   shape held by the verdict that came back. It cannot see the return itself.
#   If the funnel were restructured so that two of those shapes left through one
#   return, this file would go on reporting four and would be wrong about which
#   restores it had exercised.
#
#   -q AND THE SILENCE SWITCH TOGETHER. -q suppresses warnings on the command
#   line; silence suppresses everything on the API path. Whether a caller can
#   ask for one and not the other has not been decided and nothing here assumes
#   an answer.
#
#   COLOUR. Everything here runs with the streams redirected, so scr never
#   appends --colors. Whether a silenced SCOUT still answers SCOUT_colour() the
#   same way is a question for SCOUT.TEST, and it is asked there.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: the bound-call API does not keep the promise in its own header"
  exit 1
fi
echo "OK: the API path is silent on both streams, and the command line is not"
