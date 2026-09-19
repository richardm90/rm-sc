#!/QOpenSys/pkgs/bin/bash
#
# stop-escalation-test.sh - whether `stop` gives up when its own `stop_cmd`
# does not actually bring a service down, or escalates to ENDJOB the way
# upstream does.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and
# tools/narration-test.sh, and modelled closely on the second of those - a
# shell script rather than an iRPGUnit suite for the same reason: which STREAM
# a line lands on, the command's EXIT STATUS, and whether the underlying job
# is actually gone only exist OUTSIDE the ILE job, and iRPGUnit runs inside
# one.
#
# THE FINDING THIS SCRIPT IS FOR. docs/parity.md § "Beyond the operations -
# `stop` does not escalate when its own `stop_cmd` fails" (found 19 September
# 2026, live, with a real self-bounded listener and streams captured apart):
#
#   A service with its own stop_cmd, where that command does not actually
#   bring the service down - either it fails to launch / exits non-zero, or
#   it succeeds and does nothing - is NOT given up on by upstream. It warns,
#   escalates to ENDJOB regardless of whether a custom stop command was
#   configured, and succeeds. RMSC gives up immediately, reports an ERROR, and
#   the service is left running.
#
# Measured, both scenarios, byte for byte (this is the reference the cases
# below are built from - stage 2 re-measures it live rather than trusting the
# transcription, for the reason every harness in this project re-measures
# upstream: a markdown table cannot preserve a trailing space, and cannot
# notice if upstream's wording moves):
#
#   stdout: Performing operation 'STOP' on service '<short>'
#           Stopping via endjob
#           Service '<friendly>' successfully stopped
#           <one trailing blank line>
#   stderr: WARNING: Timed out waiting for service '<friendly>' to stop. Will
#           try harder
#           <no trailing blank line>
#   exit:   0
#
# RMSC today: stderr `ERROR: Stop command failed for <short>: <reason>` (a
# stop_cmd that exits non-zero) or `ERROR: <short> did not stop within <n>
# seconds` (one that exits 0 and does nothing), exit 253, and the listener is
# never actually stopped.
#
# WHAT THIS FILE DOES NOT TOUCH, ON PURPOSE. The no-stop_cmd path - ENDJOB
# used directly, with its own *CNTRLD-then-*IMMED escalation - is explicitly
# out of scope. docs/parity.md records that measuring ITS failure/escalation
# wording live was attempted and abandoned as too risky: it needs a job that
# resists ENDJOB OPTION(*IMMED) on a real, shared box. Nothing here stages
# one, asks for one, or asserts anything about that path beyond the control
# case below, which is an ordinary success and never reaches escalation.
#
# THE CONTROL IS A WORKING stop_cmd, NOT AN ABSENT ONE, and that is
# deliberate. The break this fix could have been is not only "still doesn't
# escalate" - it is also "now escalates unconditionally, whether or not the
# configured stop_cmd actually worked". Only a service whose stop_cmd
# genuinely brings the job down can catch that: a control with no stop_cmd at
# all exercises a different branch entirely (SCEXEC.RPGLE's own comment,
# quoted in docs/parity.md, calls it "escalate only where upstream does" -
# that guard sits on the no-stop_cmd path too, so a no-stop_cmd control could
# not tell an over-eager fix from a correct one). So the control's stop_cmd
# (tools/stop-escalation-test.sh's own $WORK/stop_control.sh, below) finds and
# kills the listener directly - the case must show NO warning and NO
# "Stopping via endjob" line, and a fix that escalates unconditionally fails
# it exactly as today's code fails the other two.
#
# STAGING. Following tools/gate-fixtures/README.md and tools/narration-test.sh:
# each fixture's start_cmd is tools/gate-listen.py, self-bounded with
# --seconds so a script killed mid-run, or a case that goes wrong in some way
# nobody anticipated, cannot leave a listener running forever. check_alive is
# the port it binds. Every case still finishes by handing the fixture to
# `scr kill`, which bypasses stop_cmd entirely and goes straight to ENDJOB, and
# then confirms with `check` that nothing is left running - belt and braces
# over the --seconds bound, not a substitute for it.
#
# WHY BOTH `sc` AND `scr` RUN EVERY SCENARIO, AND WHY EACH GETS ITS OWN
# LISTENER INSTANCE. A service's underlying job is not aware which
# implementation started it, so the two sides cannot be measured against a
# single shared instance: whichever implementation stops (or fails to stop)
# it first changes the precondition for the second. Every scenario therefore
# runs as two fully independent rounds - start, stop, check, kill-and-verify -
# one through `scr` (RMSC, the subject) and one through `sc` (upstream, the
# reference), rather than one shared listener handed between them.
#
# BASIS OF EACH ASSERTION
#
#   measured   the exact text is the one docs/parity.md records having
#              captured live on 19 September 2026. This script's own stage 2
#              re-measures it against upstream on every run, so a reference
#              that has moved is reported as REFDRIFT rather than silently
#              trusted.
#
# NOTHING NAMES A REAL HOST, CLIENT OR SERVICE. Every short name, friendly
# name and port below is invented for this file.
#
# Stdout and stderr are captured to SEPARATE files throughout - no `2>&1`
# anywhere - for the reason docs/parity.md gives at length: a merged
# comparison cannot see a line that moves between streams, which is most of
# how this finding stayed unmeasured as long as it did.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/stop-escalation-test.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT.
#
# The same block as tools/narration-test.sh and every other script here that
# keeps its work directory and names it by PID - deliberately duplicated
# rather than shared, because each of these is deployed and run standalone.
# See tools/narration-test.sh's copy for the full reasoning; the property is
# stated once there and holds here unchanged: anything that might still be
# alive is left alone, and so is any name whose suffix is not a plain number.
ls -dt /tmp/stop-escalation-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in
    ''|*[!0-9]*) continue ;;
  esac
  if kill_err=$(kill -0 "$owner" 2>&1); then
    continue
  fi
  case "$kill_err" in
    *ermitted*|*EPERM*|*ermission*) continue ;;
  esac
  rm -rf "$stale" 2>/dev/null
done
SVCDIR="$WORK/services"

# Ports the staged listeners bind. High, and none a substring of another -
# the same care tools/narration-test.sh's fixture names take, for the same
# reason: a `ps -ef` filter or a stray `grep` could otherwise match the wrong
# process.
PORT_CMDFAIL=65460
PORT_CMDNOOP=65461
PORT_CONTROL=65462

# Without this the PASE side of both implementations behaves differently.
export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud - CLAUDE.md: a suite that
# passes because its fixture is absent is worse than one that fails, because
# it reports success.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory. Set" \
  "SCR=<path> or DEPLOY=<deploy dir> if the build lives somewhere else."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Stage 2 re-measures the escalation wording live against upstream, because" \
  "it was transcribed into docs/parity.md's prose and a markdown table cannot" \
  "preserve a trailing space. Set SC=<path> if it is installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The staged services must ACTUALLY COME UP, or every 'stop' below is being" \
  "measured against a service that was never running. Set PY=<path> if" \
  "python3 lives elsewhere."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py" \
  "" \
  "This is the project's sanctioned self-bounded listener - see" \
  "tools/gate-fixtures/README.md. Nothing here writes its own."

mkdir -p "$SVCDIR" || setup_fail "cannot create work directory $SVCDIR"

# PROVE EVERY PORT IS FREE BEFORE STAGING ANYTHING. If something else already
# holds one of these, the fixture checked on it reports RUNNING before
# anything here has started it, and every case downstream fails for a reason
# that has nothing to do with escalation. SO_REUSEADDR is deliberately not
# set: the question is whether anyone at all holds the port.
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
for p in "$PORT_CMDFAIL" "$PORT_CMDNOOP" "$PORT_CONTROL"; do
  port_free "$p" || setup_fail \
    "port $p is already in use, so a fixture checked on it would report" \
    "RUNNING before this script had started anything." \
    "" \
    "A previous run of this script killed before its trap could fire is the" \
    "likeliest cause - its listeners are bounded and should have exited on" \
    "their own; check for a leftover gate-listen.py."
done

# THE CONTROL'S WORKING stop_cmd. Finds the listener holding PORT_CONTROL by
# its command line and kills it - the plainest thing that can be called a
# "stop command that actually works", and the only one of the three fixtures
# whose stop_cmd is expected to bring the job down on its own. Filtered by
# the port number, which is unique to this fixture in this run.
cat > "$WORK/stop_control.sh" <<EOF
#!/QOpenSys/pkgs/bin/bash
for p in \$(ps -ef 2>/dev/null | grep -F 'gate-listen.py' | grep -F '$PORT_CONTROL' | grep -v grep | awk '{print \$2}'); do
  kill -TERM "\$p" 2>/dev/null
done
exit 0
EOF
chmod +x "$WORK/stop_control.sh"

# ---------------------------------------------------------------------------
# The staged definitions. Three services, none started automatically - no
# group, no autostart - because CLAUDE.md's caution about a public repository
# applies to a harness as much as to anything else it names, and there is
# nothing here that needs a group.
#
#   rmscse_cmdfail   Alpha One Escalate     stop_cmd exits non-zero
#   rmscse_cmdnoop   Bravo Two Escalate     stop_cmd exits 0 and does nothing
#   rmscse_control   Charlie Three Escalate stop_cmd actually stops it
#
# No short name is a substring of any friendly name or of another short name,
# and no friendly name of another - the same discipline
# tools/narration-test.sh's header explains at length, for the same reason:
# it is what makes "the line does not carry X" a real assertion.
# ---------------------------------------------------------------------------
CMDFAIL=rmscse_cmdfail; CMDFAIL_F='Alpha One Escalate'
CMDNOOP=rmscse_cmdnoop; CMDNOOP_F='Bravo Two Escalate'
CONTROL=rmscse_control; CONTROL_F='Charlie Three Escalate'

# startup_wait_time is generous because the listener binds almost instantly
# and there is nothing to be gained by cutting it fine. stop_wait_time is
# short and deliberate: escalation (where it happens) fires once this
# elapses, and every case downstream waits for it, so keeping it small keeps
# the whole run fast without making it any less real. --seconds bounds the
# listener itself, independently of stop_wait_time, so a case that goes wrong
# cannot leave a listener running past that regardless of what stop_wait_time
# is set to.
write_def() {  # short friendly port stop_cmd_line
  local short="$1" friendly="$2" port="$3" stopcmd="$4"
  {
    printf 'name: %s\n' "$friendly"
    printf 'start_cmd: %s %s/gate-listen.py --seconds 45 %s\n' "$PY" "$HERE" "$port"
    printf 'check_alive: %s\n' "$port"
    printf 'stop_cmd: %s\n' "$stopcmd"
    printf 'startup_wait_time: 15\n'
    printf 'stop_wait_time: 5\n'
  } > "$SVCDIR/$short.yaml"
}

write_def "$CMDFAIL" "$CMDFAIL_F" "$PORT_CMDFAIL" "/QOpenSys/usr/bin/false"
write_def "$CMDNOOP" "$CMDNOOP_F" "$PORT_CMDNOOP" "/QOpenSys/usr/bin/true"
write_def "$CONTROL" "$CONTROL_F" "$PORT_CONTROL" "$WORK/stop_control.sh"

# ---------------------------------------------------------------------------
# Teardown. `scr kill` bypasses stop_cmd entirely and goes straight to
# ENDJOB, which is exactly what is wanted here regardless of which
# implementation, or which buggy code path, left a job running. It is called
# under RMSC's own SC_SERVICES_DIR whether the job was started by `sc` or by
# `scr` - a running job does not know which one launched it, only that it
# matches the check_alive criterion this same staged definition carries.
# kill_stray_listeners is the last-resort net beneath that, filtered by the
# three ports above so it cannot touch a listener staged by some other
# harness or run.
# ---------------------------------------------------------------------------
kill_stray_listeners() {
  local p
  for p in $(ps -ef 2>/dev/null | grep -F 'gate-listen.py' \
             | grep -E "$PORT_CMDFAIL|$PORT_CMDNOOP|$PORT_CONTROL" \
             | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}

cleanup() {
  local s
  for s in "$CMDFAIL" "$CMDNOOP" "$CONTROL"; do
    SC_SERVICES_DIR="$SVCDIR" "$SCR" kill "$s" >/dev/null 2>&1
  done
  kill_stray_listeners
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}
# See tools/narration-test.sh for why EXIT is disarmed inside the handler
# rather than trapped alongside INT/TERM: a trap does not stop the script
# resuming after a signal, only exiting does, and `trap cleanup EXIT INT TERM`
# runs cleanup, resumes, and finishes reporting success for cases that never
# ran.
on_signal() {
  trap - EXIT
  cleanup
  exit 130
}
trap cleanup EXIT
trap on_signal INT TERM

if [ -n "${STOPESC_DRY:-}" ]; then
  echo "stop-escalation-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
  echo
  echo "--- $WORK/stop_control.sh"
  cat "$WORK/stop_control.sh"
  exit 0
fi

pass=0; failed=0; refdrift=0; skipped=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-28s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-28s   - %s\n' "" "" "$*"; }

# run_impl IMPL(rmsc|sc) TAG -- ARGS...   captures streams SEPARATELY.
# Upstream's services directory is a JVM property, set through
# JAVA_TOOL_OPTIONS, which makes the JVM announce itself on stderr - filtered
# by matching the line, not by dropping the first line of stderr, so a real
# message is never discarded with it.
run_impl() {
  local impl="$1" tag="$2"; shift 2
  [ "$1" = "--" ] && shift
  local rc
  if [ "$impl" = rmsc ]; then
    SC_SERVICES_DIR="$SVCDIR" "$SCR" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
    rc=$?
  else
    JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" "$@" \
      > "$WORK/$tag.out" 2> "$WORK/$tag.err.raw"
    rc=$?
    grep -v 'Picked up' "$WORK/$tag.err.raw" > "$WORK/$tag.err" 2>/dev/null
  fi
  return $rc
}

# impl_state IMPL SHORT -> RUNNING | PARTIAL | NOT | ?
impl_state() {
  local impl="$1" short="$2" o
  if [ "$impl" = rmsc ]; then
    o=$(SC_SERVICES_DIR="$SVCDIR" "$SCR" check "$short" 2>/dev/null)
  else
    o=$(JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" check "$short" 2>/dev/null)
  fi
  case "$o" in
    *"  NOT RUNNING "*) echo NOT ;;
    *"  PARTIAL"*)      echo PARTIAL ;;
    *"  RUNNING "*)     echo RUNNING ;;
    *)                  echo '?' ;;
  esac
}

impl_settle() {  # impl short want
  local impl="$1" short="$2" want="$3" i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ "$(impl_state "$impl" "$short")" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

# reset_down SHORT - unconditional, implementation-agnostic. Used before
# EVERY measurement and after every scenario: `scr kill` bypasses stop_cmd
# entirely, so it works whether the job was left running by a buggy `stop` or
# never touched at all.
reset_down() {
  SC_SERVICES_DIR="$SVCDIR" "$SCR" kill "$1" >/dev/null 2>&1
  impl_settle rmsc "$1" NOT
}

# expect / expect_nb FILE LINE... - the same convention
# tools/narration-test.sh uses: one trailing blank line for a command that
# exits 0, none for one that does not. Re-measured 19 September 2026 for
# this exact case: the fixed stdout ends in a blank line (exit 0), and the
# single stderr warning line does not.
expect() {
  local f="$1"; shift
  local l; : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
  printf '\n' >> "$f"
}
expect_nb() {
  local f="$1"; shift
  local l; : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
}

# ---------------------------------------------------------------------------
echo "== stage 0: the fixtures prove themselves"
echo
printf '  %-9s %-28s %s\n' verdict case detail
printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
# ---------------------------------------------------------------------------

# (a) SC_SERVICES_DIR / -Dservices.dir WERE READ AT ALL, for BOTH sides.
# Proved from `check`, whose rows are the evidence and are not moved by
# anything this script does - the same shape tools/narration-test.sh's stage
# 0 and stage 4 both use for the same reason.
fixture_ok=1
for short in "$CMDFAIL" "$CMDNOOP" "$CONTROL"; do
  o=$(SC_SERVICES_DIR="$SVCDIR" "$SCR" check "$short" 2>/dev/null)
  case "$o" in
    *"$short"*) ;;
    *) fixture_ok=0 ;;
  esac
done
if [ "$fixture_ok" -eq 1 ]; then
  report PASS staged-rmsc "(fixture) scr sees all three definitions"
  pass=$((pass+1))
else
  report FAIL staged-rmsc "FIXTURE DID NOT TAKE: SC_SERVICES_DIR=$SVCDIR was not read by scr, or a definition failed to load"
  detail "nothing below this line is evidence for anything"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed"
  echo "FAILED: the fixture did not stage"
  exit 1
fi

sc_fixture_ok=1
for short in "$CMDFAIL" "$CMDNOOP" "$CONTROL"; do
  o=$(JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" check "$short" 2>/dev/null)
  case "$o" in
    *"$short"*) ;;
    *) sc_fixture_ok=0 ;;
  esac
done
if [ "$sc_fixture_ok" -eq 1 ]; then
  report PASS staged-sc "(fixture) upstream sees all three definitions"
  pass=$((pass+1))
else
  report FAIL staged-sc "upstream (sc) does not see one or more definitions - stage 2 below cannot run"
  detail "JAVA_TOOL_OPTIONS=-Dservices.dir=$SVCDIR was not honoured by sc, or a definition failed to load"
  failed=$((failed+1))
fi

echo
echo "staged in: $SVCDIR   (ports $PORT_CMDFAIL $PORT_CMDNOOP $PORT_CONTROL)"
echo

# ---------------------------------------------------------------------------
# The core case, run once per scenario. Each scenario is measured through
# BOTH implementations, each against its OWN listener instance (see the
# header for why they cannot share one), and each ends by handing the
# fixture to `scr kill` and confirming it took, whatever happened above it.
# ---------------------------------------------------------------------------

# require_running TAG IMPL SHORT - a precondition, not an assertion about the
# code under test. Reported as FAIL rather than SKIPPED: CLAUDE.md's rule
# that a suite passing because its fixture is absent is worse than one that
# fails applies here too, and a listener that will not come up is a fixture
# defect worth surfacing loudly rather than quietly stepping around.
require_running() {
  local tag="$1" impl="$2" short="$3" got
  got=$(impl_state "$impl" "$short")
  [ "$got" = RUNNING ] && return 0
  report FAIL "$tag" "(precondition) $short via $impl is $got, wanted RUNNING - not run"
  detail "the listener did not bind, or did not settle, before the stop under test"
  failed=$((failed+1))
  return 1
}

# scenario_case TAG SHORT FRIENDLY EXP_OUT EXP_ERR VERDICT_ON_MISMATCH
#
# VERDICT_ON_MISMATCH is FAIL for the rmsc side (this is what the fix is
# supposed to change) and REFDRIFT for the sc side (a mismatch there means
# the recorded reference has moved, not that RMSC regressed) - the same
# distinction tools/narration-test.sh's stage 4 draws between its own
# fail_case and REFDRIFT paths.
#
# THE TWO ASSERTIONS ARE DELIBERATELY SEPARATE, and that is the case's whole
# point. "$label-narration" asks whether the TEXT and EXIT STATUS match.
# "$label-actually-stopped" asks whether the SERVICE IS DOWN. A fix that only
# reworded RMSC's error text, or that started printing the escalation lines
# without actually calling ENDJOB, would pass the first of these once the
# wording lined up and FAIL the second regardless - which is exactly the
# rival CLAUDE.md's rule warns against: "a fix and the break it could have
# been must disagree about at least one case in the suite." Checking the
# state after the call is the one thing a text-only change cannot satisfy.
scenario_case() {
  local tag="$1" short="$2" friendly="$3" exp_out="$4" exp_err="$5"
  local side

  for side in rmsc sc; do
    local label="$tag-$side"
    local verdict_kind=FAIL
    [ "$side" = sc ] && verdict_kind=REFDRIFT

    reset_down "$short"
    run_impl "$side" "$label-start" -- start "$short" >/dev/null 2>&1
    impl_settle "$side" "$short" RUNNING >/dev/null 2>&1

    if ! require_running "$label" "$side" "$short"; then
      reset_down "$short"
      continue
    fi

    run_impl "$side" "$label-stop" -- stop "$short"
    local rc=$?

    local probs=()
    [ "$rc" -eq 0 ] || probs+=("exit $rc, wanted 0")
    if ! diff -u "$exp_out" "$WORK/$label-stop.out" > "$WORK/$label-stop.out.diff" 2>&1; then
      probs+=("stdout is not byte-identical to the expectation (diff: $label-stop.out.diff)")
    fi
    if ! diff -u "$exp_err" "$WORK/$label-stop.err" > "$WORK/$label-stop.err.diff" 2>&1; then
      probs+=("stderr is not byte-identical to the expectation (diff: $label-stop.err.diff)")
    fi

    if [ ${#probs[@]} -eq 0 ]; then
      report PASS "$label-narration" "exit 0, stdout+stderr byte-exact"
      pass=$((pass+1))
    else
      report "$verdict_kind" "$label-narration" ""
      local p; for p in "${probs[@]}"; do detail "$p"; done
      if [ -s "$WORK/$label-stop.out.diff" ]; then
        while IFS= read -r l; do detail "out: $l"; done < "$WORK/$label-stop.out.diff"
      fi
      if [ -s "$WORK/$label-stop.err.diff" ]; then
        while IFS= read -r l; do detail "err: $l"; done < "$WORK/$label-stop.err.diff"
      fi
      if [ "$verdict_kind" = FAIL ]; then failed=$((failed+1)); else refdrift=$((refdrift+1)); fi
    fi

    local st
    st=$(impl_state "$side" "$short")
    if [ "$st" = NOT ]; then
      report PASS "$label-actually-stopped" "$short reads NOT RUNNING after stop"
      pass=$((pass+1))
    else
      report "$verdict_kind" "$label-actually-stopped" "$short still reads $st after stop"
      detail "the reported text/exit status is not enough on its own - the service must actually be down"
      if [ "$verdict_kind" = FAIL ]; then failed=$((failed+1)); else refdrift=$((refdrift+1)); fi
    fi

    reset_down "$short"
    local after
    after=$(impl_state rmsc "$short")
    if [ "$after" != NOT ]; then
      report FAIL "$label-cleanup" "$short still reads $after after 'scr kill' - it should always bring the job down"
      failed=$((failed+1))
    fi
  done
}

# ---------------------------------------------------------------------------
echo "== stage 1: RMSC against the measured family (scenario A, B, control)"
echo
printf '  %-9s %-28s %s\n' verdict case detail
printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
# ---------------------------------------------------------------------------

# THE LITERALS. Transcribed from docs/parity.md's 19 September 2026 capture,
# with each fixture's own short/friendly name substituted in. Re-anchored
# against a live sc in stage 2, below.
p_stop_cmdfail="Performing operation 'STOP' on service '$CMDFAIL'"
p_stop_cmdnoop="Performing operation 'STOP' on service '$CMDNOOP'"
p_stop_control="Performing operation 'STOP' on service '$CONTROL'"
stopping_via_endjob="Stopping via endjob"
s_stopped_cmdfail="Service '$CMDFAIL_F' successfully stopped"
s_stopped_cmdnoop="Service '$CMDNOOP_F' successfully stopped"
s_stopped_control="Service '$CONTROL_F' successfully stopped"
warn_cmdfail="WARNING: Timed out waiting for service '$CMDFAIL_F' to stop. Will try harder"
warn_cmdnoop="WARNING: Timed out waiting for service '$CMDNOOP_F' to stop. Will try harder"

expect     "$WORK/e.cmdfail.out" "$p_stop_cmdfail" "$stopping_via_endjob" "$s_stopped_cmdfail"
expect_nb  "$WORK/e.cmdfail.err" "$warn_cmdfail"

expect     "$WORK/e.cmdnoop.out" "$p_stop_cmdnoop" "$stopping_via_endjob" "$s_stopped_cmdnoop"
expect_nb  "$WORK/e.cmdnoop.err" "$warn_cmdnoop"

# THE CONTROL'S EXPECTATION HAS NO "Stopping via endjob" LINE AND NO WARNING -
# that absence is the whole of what this case exists to prove.
expect     "$WORK/e.control.out" "$p_stop_control" "$s_stopped_control"
: > "$WORK/e.control.err"

# --- scenario A: stop_cmd fails to launch / exits non-zero -----------------
#
# SEPARATING VALUE against today's RMSC: today's stderr is `ERROR: Stop
# command failed for rmscse_cmdfail: Stop command failed with 1:` and exit is
# 253 with the listener left running - none of which matches the expectation
# above, so this case is red today for a specific, named reason (the ERROR
# text and the still-running listener), not a vague mismatch.
scenario_case cmdfail "$CMDFAIL" "$CMDFAIL_F" "$WORK/e.cmdfail.out" "$WORK/e.cmdfail.err"

# --- scenario B: stop_cmd exits 0 and does nothing --------------------------
#
# SEPARATING VALUE against today's RMSC: today's stderr is `ERROR:
# rmscse_cmdnoop did not stop within 5 seconds` and exit is 253, again with
# the listener left running. Scenario A and B disagree with each other on
# stop_cmd's own exit status but must agree on everything downstream of it -
# both are read by RMSC as "the configured stop command did not work", and a
# fix that only handled a non-zero exit (scenario A) and not a stop_cmd that
# silently no-ops (scenario B) would pass one of these and fail the other,
# which is why both are staged rather than one standing in for the other.
scenario_case cmdnoop "$CMDNOOP" "$CMDNOOP_F" "$WORK/e.cmdnoop.out" "$WORK/e.cmdnoop.err"

# --- control: an ordinary, working stop_cmd - must keep passing -------------
#
# SEPARATING VALUE: NO "Stopping via endjob" line and NO warning. This is the
# regression guard named in the brief - it is expected to pass BEFORE any fix
# as well as after, and its purpose is to catch a fix that escalates
# unconditionally rather than only when the configured stop_cmd actually
# failed to bring the service down.
scenario_case control "$CONTROL" "$CONTROL_F" "$WORK/e.control.out" "$WORK/e.control.err"

echo

# ---------------------------------------------------------------------------
echo "== stage 2: upstream reference, re-measured against the same fixtures"
echo "   (a REFDRIFT above means the recorded EXPECTATION has moved, not that"
echo "    RMSC regressed - re-capture before trusting a result either way)"
echo
# ---------------------------------------------------------------------------
# The sc:* rows above (produced by scenario_case's own "sc" pass) already ARE
# stage 2 - each scenario runs both sides together so the listener can be
# reset between them. This banner exists only so the report reads in the
# same shape as tools/narration-test.sh's, where stage 4 is visibly a
# separate pass; here the two are interleaved per scenario and the sc:* rows
# above are what to read.
if [ "$sc_fixture_ok" -ne 1 ]; then
  report SKIPPED sc:reference "upstream could not be driven against the staged definitions - see staged-sc above"
  skipped=$((skipped+1))
fi

echo

# ---------------------------------------------------------------------------
echo "== stage 3: nothing is left running"
echo
printf '  %-9s %-28s %s\n' verdict case detail
printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
# ---------------------------------------------------------------------------

final_ok=1
for short in "$CMDFAIL" "$CMDNOOP" "$CONTROL"; do
  reset_down "$short"
  st=$(impl_state rmsc "$short")
  if [ "$st" != NOT ]; then
    report FAIL "final-state-$short" "reads $st, wanted NOT RUNNING after final cleanup"
    final_ok=0
    failed=$((failed+1))
  fi
done
if [ "$final_ok" -eq 1 ]; then
  report PASS final-state "all three fixtures confirmed NOT RUNNING"
  pass=$((pass+1))
fi

echo
echo "pass=$pass   failed=$failed   reference-drift=$refdrift   skipped=$skipped"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT DOES NOT ASSERT
#
#   THE NO-stop_cmd ESCALATION PATH. Out of scope - see the header. Nothing
#   here stages a job that resists ENDJOB OPTION(*IMMED).
#
#   THE WORDING IN ISOLATION. Every sentence here is also a candidate for
#   qtestsrc/SCOUT.TEST.RPGLE once SCOUT grows a procedure for it, the way
#   the narration family's wording is pinned there rather than here. This
#   file is the only place that can see the STREAM, the EXIT STATUS and
#   whether the JOB ACTUALLY DIED, which is why those three are what it
#   asserts.
#
#   COLOUR. Stdout and stderr are captured redirected throughout, so colour
#   never enters either stream.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: stop does not (yet) escalate to ENDJOB the way upstream does - see the FAIL rows above"
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer says what docs/parity.md records for this finding."
  echo "Re-measure live before trusting a pass or acting on a failure elsewhere."
  exit 1
fi
if [ "$skipped" -ne 0 ]; then
  echo "OK, WITH $skipped SKIPPED CASE(S): a case that could not reach its precondition proves nothing."
  exit 0
fi
echo "OK: stop_cmd failing or no-opping is escalated to ENDJOB and the service actually comes down, matching upstream"
