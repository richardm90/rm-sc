#!/QOpenSys/pkgs/bin/bash
#
# stop-timeout-test.sh - whether `stop` escalates the way upstream does when a
# service has NO stop_cmd at all and the job genuinely does not go down -
# ENDJOB OPTION(*CNTRLD) first, then ENDJOB OPTION(*IMMED), both exhausted,
# both powerless against a job that is still there.
#
# Modelled closely on tools/stop-escalation-test.sh - same run_impl/impl_state
# /impl_settle/expect/expect_nb/report conventions, same PID-named work
# directory with the same stale-entry cleanup block, same trap shape, same
# QIBM_MULTI_THREADED=Y, same separate stdout/stderr capture discipline - but
# a DIFFERENT, already-closed case. stop-escalation-test.sh covers a service
# WITH a stop_cmd that fails to bring the job down; this covers a service with
# NO stop_cmd at all, where ENDJOB itself is what does not work. Its own
# header says this path is explicitly out of scope for it:
#
#   "The no-stop_cmd ESCALATION PATH ... needs a job that resists ENDJOB
#   OPTION(*IMMED) on a real, shared box ... remains deliberately unattempted
#   without its own decision on scope and safety."
#
# That decision was taken 1 October 2026 (Richard, before tools/gate-resist.py
# was written - see that file's own header for the safety case: ENDJOB
# OPTION(*IMMED) is itself bounded by QENDJOBLMT, confirmed 120s on this box,
# so "ignore SIGTERM" is never "run forever"). This file is what was staged
# once that fixture existed.
#
# THE FINDING THIS SCRIPT IS FOR - measured live, 1 October 2026, with
# tools/gate-resist.py --resist 50 <port> standing in for a job that outlasts
# both ENDJOB attempts, and a service with stop_wait_time: 5 and no stop_cmd
# key at all:
#
#   upstream:  Performing operation 'STOP' on service '<short>'
#              WARNING: Timed out waiting for service '<friendly>' to stop.
#                       Will try harder
#              ERROR: Timed out waiting for service '<friendly>' to stop.
#                     Giving up
#              <one trailing blank line, on stderr, after the ERROR line>
#              exit 253
#              (stdout carries only the progress line - no trailing blank)
#              total wall clock: roughly 28s from the `stop` invocation
#
#   RMSC today: Performing operation 'STOP' on service '<short>'
#               ERROR: <short> did not stop, even immediately
#               <one trailing blank line>
#               exit 253
#               total wall clock: roughly 9s
#
# TWO SEPARATE DEFECTS, and this script is built so a fix for one without the
# other still fails it:
#
#   1. RMSC never prints the WARNING line. Upstream always prints it once the
#      *CNTRLD wait expires, with or without a stop_cmd - this is not a
#      stop_cmd-only behaviour.
#   2. RMSC's final line is worded differently AND names the service by its
#      SHORT name where upstream uses the FRIENDLY name.
#
# A single byte-exact diff against the combined two-line expectation below
# already satisfies "a fix and the break it could have been must disagree
# about at least one case" (CLAUDE.md) without needing two separate cases: a
# fix that adds the WARNING but keeps the wrong final text leaves the diff
# non-empty on the ERROR line and nothing else; a fix that corrects the final
# text but never adds the WARNING leaves the diff non-empty on the missing
# line and nothing else. Either partial fix is still reported FAIL, and the
# diff printed with the failure names exactly which half is still wrong.
#
# WHAT THIS FILE DOES NOT TOUCH. The stop_cmd-present escalation path (a
# configured stop_cmd that fails or no-ops) is tools/stop-escalation-test.sh's
# territory, already fixed and covered there. Nothing here duplicates it:
# neither fixture below carries a stop_cmd key at all - not even
# `stop_cmd: null`, which the fixture pack's own README records as
# indistinguishable from absent; this is the plain ENDJOB-only path, full
# stop.
#
# WHY A DURATION WINDOW, NOT AN EXACT TIME. The measured 9s/28s figures are
# real but not a contract - they depend on internal retry/backoff constants
# neither implementation documents, and the box's own load. What a correct fix
# MUST do is actually wait through at least the *CNTRLD attempt before giving
# up: a "fix" that only reworded the text and returned instantly would still
# be wrong, and a floor at comfortably less than stop_wait_time (5s) plus
# retry overhead catches that. A ceiling comfortably under --resist (50s)
# catches the opposite failure: a result that only looks right because the
# fixture happened to reach the end of its own bounded life before the
# command gave up, rather than because the command's own internal deadline
# fired. Both bounds are deliberately generous - they exist to catch "didn't
# really try" and "got lucky", not to pin an exact number.
#
# WHY "STILL RUNNING" IS THE RIGHT ANSWER HERE, not "NOT RUNNING". Unlike
# stop-escalation-test.sh's scenarios, where the correct outcome is the
# service actually coming down, the correct outcome of THIS scenario is
# correctly REPORTED FAILURE while the job is still alive - that is what
# "Giving up" means, and --resist's window (50s) comfortably outlasts both
# implementations' own give-up point (~28s at the slowest measured) so the
# job is still there to check against. A result that reports failure while
# the job has actually gone, or reports success while it has not, is exactly
# the mismatch this script's separate state assertion exists to catch -
# CLAUDE.md's rule that the reported text and the real state are checked
# apart, because a text-only fix cannot satisfy both at once.
#
# THE TRAP THIS SCRIPT IS BUILT AROUND, from tools/gate-resist.py's own
# measurement: neither `scr kill` nor `sc`'s kill operation reliably brings a
# gate-resist.py job down before its own --resist window elapses - confirmed
# directly, not assumed. So cleanup for the resisting fixture never calls
# either kill operation at all; it goes straight to a `kill -9` sweep matched
# by port number, which works regardless of --resist because SIGKILL cannot
# be ignored by any implementation on any system (gate-resist.py's own header
# makes the same point, and relies on the same backstop for its own safety
# margin under QENDJOBLMT). The ordinary control fixture, which responds to
# ENDJOB normally, still uses the plain scr-kill-and-settle teardown
# stop-escalation-test.sh uses.
#
# THE CONTROL IS ANOTHER NO-stop_cmd SERVICE, not a working stop_cmd (unlike
# stop-escalation-test.sh's control). The question here is not "does a
# configured stop_cmd change what happens" - there isn't one, on either
# fixture - it is "does the ordinary, prompt case on this same code path stay
# clean": no WARNING line, no escalation wording, just the ordinary
# `Service '<friendly>' successfully stopped`. That is what would catch an
# over-eager fix that starts printing the WARNING on every stop rather than
# only when the *CNTRLD wait genuinely expires.
#
# WHY BOTH `sc` AND `scr` RUN EVERY SCENARIO, AND WHY EACH GETS ITS OWN
# FIXTURE INSTANCE. Exactly stop-escalation-test.sh's reasoning: a job does
# not know which implementation started it, so the two sides cannot share one
# instance without the first side's stop changing the precondition for the
# second. Every scenario runs as two fully independent rounds.
#
# BASIS OF EACH ASSERTION
#
#   measured   the exact text and all figures above were captured live on
#              1 October 2026, by the implementer. This script's own stage 2
#              re-measures the upstream side again on every run, so a
#              reference that has moved is reported as REFDRIFT rather than
#              silently trusted - exactly as stop-escalation-test.sh does.
#
# NOTHING NAMES A REAL HOST, CLIENT OR SERVICE. Every short name, friendly
# name and port below is invented for this file, and none is a substring of
# another short name or friendly name - the same discipline
# stop-escalation-test.sh's header explains, for the same reason: it is what
# makes "the line does not carry X" a real assertion.
#
# Stdout and stderr are captured to SEPARATE files throughout - no `2>&1`
# anywhere - for the same reason stop-escalation-test.sh gives at length: a
# merged comparison cannot see a line that moves between streams.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/stop-timeout-test.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the same block tools/stop-escalation-
# test.sh and every other script here that keeps its work directory and names
# it by PID carries, deliberately duplicated rather than shared because each
# of these is deployed and run standalone. Anything that might still be alive
# is left alone, and so is any name whose suffix is not a plain number.
ls -dt /tmp/stop-timeout-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
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

# Ports the staged fixtures bind - clear of stop-escalation-test.sh's
# 65460-65462 and of every range tools/gate-fixtures/README.md documents.
PORT_TIMEOUT=65480
PORT_CONTROL=65481

# How long the timeout fixture resists SIGTERM/SIGINT. 50s leaves roughly 22s
# of margin past the slowest figure measured for upstream's own give-up
# (~28s), and 40s of margin under gate-resist.py's own 90s refusal cap - see
# the header's "WHY A DURATION WINDOW" section for how this bound is used.
RESIST=50
DUR_FLOOR=4
DUR_CEIL=$((RESIST - 5))

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
  "Stage 2 re-measures the escalation wording live against upstream. Set" \
  "SC=<path> if it is installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The staged fixtures must ACTUALLY COME UP, or every 'stop' below is being" \
  "measured against a service that was never running. Set PY=<path> if" \
  "python3 lives elsewhere."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py" \
  "" \
  "This is the project's sanctioned self-bounded listener - see" \
  "tools/gate-fixtures/README.md. Nothing here writes its own."

[ -f "$HERE/gate-resist.py" ] || setup_fail \
  "tools/gate-resist.py not found beside this script at: $HERE/gate-resist.py" \
  "" \
  "This is the sanctioned fixture for a job that genuinely resists ENDJOB -" \
  "see its own header for why that is safe on this box. Nothing here writes" \
  "its own."

mkdir -p "$SVCDIR" || setup_fail "cannot create work directory $SVCDIR"

# PROVE EVERY PORT IS FREE BEFORE STAGING ANYTHING - see stop-escalation-
# test.sh for why this matters more than it looks: a fixture checked on a
# port something else already holds reports RUNNING before this script has
# started anything, and every case downstream fails for a reason that has
# nothing to do with escalation.
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
for p in "$PORT_TIMEOUT" "$PORT_CONTROL"; do
  port_free "$p" || setup_fail \
    "port $p is already in use, so a fixture checked on it would report" \
    "RUNNING before this script had started anything." \
    "" \
    "A previous run of this script killed before its trap could fire is the" \
    "likeliest cause - check for a leftover gate-resist.py or gate-listen.py."
done

# ---------------------------------------------------------------------------
# The staged definitions. Two services, neither with a stop_cmd key at all -
# that absence is the whole point, and neither started automatically - no
# group, no autostart - for the same reason CLAUDE.md gives about a public
# repository.
#
#   rmscst_resistor   Hotel Seven Standoff   gate-resist.py --resist 50 - the
#                     job that genuinely does not go down within either
#                     ENDJOB attempt
#   rmscst_tapper     India Eight Prompt     ordinary gate-listen.py - the
#                     regression control: same no-stop_cmd path, but stops
#                     promptly
#
# No short name is a substring of any friendly name or of another short name,
# and no friendly name of another - stop-escalation-test.sh's header explains
# at length why that discipline is what makes "the line does not carry X" a
# real assertion.
# ---------------------------------------------------------------------------
TIMEOUT=rmscst_resistor; TIMEOUT_F='Hotel Seven Standoff'
CONTROL=rmscst_tapper;   CONTROL_F='India Eight Prompt'

{
  printf 'name: %s\n' "$TIMEOUT_F"
  printf 'start_cmd: %s %s/gate-resist.py --resist %s %s\n' "$PY" "$HERE" "$RESIST" "$PORT_TIMEOUT"
  printf 'check_alive: %s\n' "$PORT_TIMEOUT"
  printf 'startup_wait_time: 15\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$TIMEOUT.yaml"

{
  printf 'name: %s\n' "$CONTROL_F"
  printf 'start_cmd: %s %s/gate-listen.py --seconds 45 %s\n' "$PY" "$HERE" "$PORT_CONTROL"
  printf 'check_alive: %s\n' "$PORT_CONTROL"
  printf 'startup_wait_time: 15\n'
  printf 'stop_wait_time: 5\n'
} > "$SVCDIR/$CONTROL.yaml"

# ---------------------------------------------------------------------------
# Teardown.
# ---------------------------------------------------------------------------

# kill_stray_resistor - the ONLY cleanup the timeout fixture gets. No `scr
# kill` / `sc kill` call precedes it: the header's TRAP section records that
# neither reliably brings a gate-resist.py job down before --resist elapses,
# confirmed directly, so calling either first would only add latency for no
# benefit. kill -9 works regardless of --resist because SIGKILL cannot be
# ignored, by any implementation, on any system.
kill_stray_resistor() {
  local p
  for p in $(ps -ef 2>/dev/null | grep -F 'gate-resist.py' | grep -F "$PORT_TIMEOUT" \
             | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}

# reset_resist SHORT - brings the timeout fixture down unconditionally and
# waits for the port to actually clear, so the next round starts clean.
reset_resist() {
  local short="$1" i
  kill_stray_resistor
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(impl_state rmsc "$short")" = NOT ] && return 0
    sleep 1
  done
  return 1
}

# kill_stray_control / reset_down - the ordinary teardown stop-escalation-
# test.sh uses, for the fixture that is expected to respond to ENDJOB
# normally.
kill_stray_control() {
  local p
  for p in $(ps -ef 2>/dev/null | grep -F 'gate-listen.py' | grep -F "$PORT_CONTROL" \
             | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}
reset_down() {
  SC_SERVICES_DIR="$SVCDIR" "$SCR" kill "$1" >/dev/null 2>&1
  impl_settle rmsc "$1" NOT
}

cleanup() {
  SC_SERVICES_DIR="$SVCDIR" "$SCR" kill "$CONTROL" >/dev/null 2>&1
  kill_stray_control
  kill_stray_resistor
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}
# See tools/stop-escalation-test.sh / docs/testing-notes.md ("An interrupted
# harness reports SUCCESS") for why EXIT is disarmed inside the handler
# rather than trapped alongside INT/TERM.
on_signal() {
  trap - EXIT
  cleanup
  exit 130
}
trap cleanup EXIT
trap on_signal INT TERM

if [ -n "${STOPTO_DRY:-}" ]; then
  echo "stop-timeout-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
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

# expect / expect_nb FILE LINE... - same convention as stop-escalation-
# test.sh: one trailing blank line for a stream whose last line is a
# "terminal" one (a success line, or an ERROR giving up), none otherwise.
# Re-measured 1 October 2026 for this exact case: stdout ends with the bare
# progress line and NO trailing blank when the command fails this way;
# stderr's single trailing blank follows the ERROR line, not the WARNING.
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

# require_running TAG IMPL SHORT - a precondition, not an assertion about the
# code under test. Reported as FAIL rather than SKIPPED, per CLAUDE.md.
require_running() {
  local tag="$1" impl="$2" short="$3" got
  got=$(impl_state "$impl" "$short")
  [ "$got" = RUNNING ] && return 0
  report FAIL "$tag" "(precondition) $short via $impl is $got, wanted RUNNING - not run"
  detail "the fixture did not bind, or did not settle, before the stop under test"
  failed=$((failed+1))
  return 1
}

# ---------------------------------------------------------------------------
echo "== stage 0: the fixtures prove themselves"
echo
printf '  %-9s %-28s %s\n' verdict case detail
printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
# ---------------------------------------------------------------------------

fixture_ok=1
for short in "$TIMEOUT" "$CONTROL"; do
  o=$(SC_SERVICES_DIR="$SVCDIR" "$SCR" check "$short" 2>/dev/null)
  case "$o" in
    *"$short"*) ;;
    *) fixture_ok=0 ;;
  esac
done
if [ "$fixture_ok" -eq 1 ]; then
  report PASS staged-rmsc "(fixture) scr sees both definitions"
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
for short in "$TIMEOUT" "$CONTROL"; do
  o=$(JAVA_TOOL_OPTIONS="-Dservices.dir=$SVCDIR" "$SC" check "$short" 2>/dev/null)
  case "$o" in
    *"$short"*) ;;
    *) sc_fixture_ok=0 ;;
  esac
done
if [ "$sc_fixture_ok" -eq 1 ]; then
  report PASS staged-sc "(fixture) upstream sees both definitions"
  pass=$((pass+1))
else
  report FAIL staged-sc "upstream (sc) does not see one or more definitions - stage 2 below cannot run"
  detail "JAVA_TOOL_OPTIONS=-Dservices.dir=$SVCDIR was not honoured by sc, or a definition failed to load"
  failed=$((failed+1))
fi

echo
echo "staged in: $SVCDIR   (ports $PORT_TIMEOUT $PORT_CONTROL, --resist $RESIST)"
echo

# ---------------------------------------------------------------------------
# THE LITERALS. Captured live 1 October 2026, re-anchored against a live sc
# in stage 2 below via the sc:* rows scenario functions produce.
# ---------------------------------------------------------------------------
p_stop_timeout="Performing operation 'STOP' on service '$TIMEOUT'"
warn_timeout="WARNING: Timed out waiting for service '$TIMEOUT_F' to stop. Will try harder"
err_timeout="ERROR: Timed out waiting for service '$TIMEOUT_F' to stop. Giving up"

p_stop_control="Performing operation 'STOP' on service '$CONTROL'"
s_stopped_control="Service '$CONTROL_F' successfully stopped"

expect_nb "$WORK/e.timeout.out" "$p_stop_timeout"
expect    "$WORK/e.timeout.err" "$warn_timeout" "$err_timeout"

expect "$WORK/e.control.out" "$p_stop_control" "$s_stopped_control"
: > "$WORK/e.control.err"

# ---------------------------------------------------------------------------
# timeout_case - the core scenario. Each side gets its own fresh instance of
# the resisting fixture (see header for why they cannot share one), and each
# round's three assertions - narration, duration, still-resisting - are kept
# deliberately separate, the same way stop-escalation-test.sh keeps narration
# and actually-stopped separate: a fix that only reworded the text, or that
# returned without really waiting, or that somehow brought the job down while
# still reporting failure, would pass some of these and fail others.
# ---------------------------------------------------------------------------
timeout_case() {
  local tag=timeout short="$TIMEOUT"
  local exp_out="$WORK/e.timeout.out" exp_err="$WORK/e.timeout.err"
  local side

  for side in rmsc sc; do
    local label="$tag-$side"
    local verdict_kind=FAIL
    [ "$side" = sc ] && verdict_kind=REFDRIFT

    reset_resist "$short"
    run_impl "$side" "$label-start" -- start "$short" >/dev/null 2>&1
    impl_settle "$side" "$short" RUNNING >/dev/null 2>&1

    if ! require_running "$label" "$side" "$short"; then
      reset_resist "$short"
      continue
    fi

    local t0 t1 elapsed
    t0=$(date +%s)
    run_impl "$side" "$label-stop" -- stop "$short"
    local rc=$?
    t1=$(date +%s)
    elapsed=$((t1 - t0))

    local probs=()
    [ "$rc" -eq 253 ] || probs+=("exit $rc, wanted 253")
    if ! diff -u "$exp_out" "$WORK/$label-stop.out" > "$WORK/$label-stop.out.diff" 2>&1; then
      probs+=("stdout is not byte-identical to the expectation (diff: $label-stop.out.diff)")
    fi
    if ! diff -u "$exp_err" "$WORK/$label-stop.err" > "$WORK/$label-stop.err.diff" 2>&1; then
      probs+=("stderr is not byte-identical to the expectation (diff: $label-stop.err.diff)")
    fi

    if [ ${#probs[@]} -eq 0 ]; then
      report PASS "$label-narration" "exit 253, stdout+stderr byte-exact"
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

    # Duration window - see header "WHY A DURATION WINDOW, NOT AN EXACT TIME".
    if [ "$elapsed" -ge "$DUR_FLOOR" ] && [ "$elapsed" -le "$DUR_CEIL" ]; then
      report PASS "$label-duration" "stop took ${elapsed}s (within ${DUR_FLOOR}-${DUR_CEIL}s)"
      pass=$((pass+1))
    else
      report "$verdict_kind" "$label-duration" "stop took ${elapsed}s, wanted ${DUR_FLOOR}-${DUR_CEIL}s"
      if [ "$elapsed" -lt "$DUR_FLOOR" ]; then
        detail "too fast to have genuinely waited through the *CNTRLD attempt"
      else
        detail "too slow - suspiciously close to --resist=$RESIST; may have returned only because the fixture reached its own bound, not because the command's own deadline fired"
      fi
      if [ "$verdict_kind" = FAIL ]; then failed=$((failed+1)); else refdrift=$((refdrift+1)); fi
    fi

    # Still resisting - see header "WHY STILL RUNNING IS THE RIGHT ANSWER HERE".
    local st
    st=$(impl_state "$side" "$short")
    if [ "$st" = RUNNING ]; then
      report PASS "$label-still-resisting" "$short reads RUNNING after the failed stop, as it must while --resist holds"
      pass=$((pass+1))
    else
      report "$verdict_kind" "$label-still-resisting" "$short reads $st after the failed stop, wanted RUNNING"
      detail "a reported failure is not enough on its own - the job must actually still be there"
      if [ "$verdict_kind" = FAIL ]; then failed=$((failed+1)); else refdrift=$((refdrift+1)); fi
    fi

    reset_resist "$short"
  done
}

# ---------------------------------------------------------------------------
# control_case - the regression guard. Same no-stop_cmd path, ordinary
# prompt stop: no WARNING, no escalation wording, must keep passing before
# and after any fix.
# ---------------------------------------------------------------------------
control_case() {
  local short="$CONTROL"
  local exp_out="$WORK/e.control.out" exp_err="$WORK/e.control.err"
  local side

  for side in rmsc sc; do
    local label="control-$side"
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
  done
}

# ---------------------------------------------------------------------------
echo "== stage 1: RMSC against the measured no-stop_cmd timeout, and the control"
echo
printf '  %-9s %-28s %s\n' verdict case detail
printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
# ---------------------------------------------------------------------------

# SEPARATING VALUE against today's RMSC: today's stderr is a single line,
# `ERROR: rmscst_resistor did not stop, even immediately`, with no WARNING
# before it, exit 253, duration ~9s - none of which matches the expectation
# above, so this case is red today for a specific, named reason (the missing
# WARNING and the wrong final text/name), not a vague mismatch.
timeout_case

# SEPARATING VALUE: must keep passing both before and after any fix - it is
# the guard against a fix that starts escalating/warning unconditionally.
control_case

echo

# ---------------------------------------------------------------------------
echo "== stage 2: upstream reference, re-measured against the same fixtures"
echo "   (a REFDRIFT above means the recorded EXPECTATION has moved, not that"
echo "    RMSC regressed - re-capture before trusting a result either way)"
echo
# ---------------------------------------------------------------------------
# The sc:* rows above (produced by timeout_case/control_case's own "sc" pass)
# already ARE stage 2 - each scenario runs both sides together so the
# fixture can be reset between them. This banner exists only so the report
# reads in the same shape as tools/stop-escalation-test.sh's.
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

reset_resist "$TIMEOUT"
st=$(impl_state rmsc "$TIMEOUT")
if [ "$st" != NOT ]; then
  report FAIL "final-state-$TIMEOUT" "reads $st, wanted NOT RUNNING after final cleanup"
  final_ok=0
  failed=$((failed+1))
fi

reset_down "$CONTROL"
st=$(impl_state rmsc "$CONTROL")
if [ "$st" != NOT ]; then
  report FAIL "final-state-$CONTROL" "reads $st, wanted NOT RUNNING after final cleanup"
  final_ok=0
  failed=$((failed+1))
fi

if [ "$final_ok" -eq 1 ]; then
  report PASS final-state "both fixtures confirmed NOT RUNNING"
  pass=$((pass+1))
fi

echo
echo "pass=$pass   failed=$failed   reference-drift=$refdrift   skipped=$skipped"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT DOES NOT ASSERT
#
#   THE stop_cmd-PRESENT ESCALATION PATH. tools/stop-escalation-test.sh's
#   territory - out of scope here on purpose, see the header.
#
#   THE WORDING IN ISOLATION. A candidate for qtestsrc/SCOUT.TEST.RPGLE once
#   SCOUT grows a procedure for it, same as the narration family. This file
#   is the only place that can see the STREAM, the EXIT STATUS, the WALL
#   CLOCK and whether the JOB ACTUALLY SURVIVED, which is why those four are
#   what it asserts.
#
#   COLOUR. Stdout and stderr are captured redirected throughout, so colour
#   never enters either stream.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: stop does not (yet) escalate/report the no-stop_cmd timeout the way upstream does - see the FAIL rows above"
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer says what this file's header records for this finding."
  echo "Re-measure live before trusting a pass or acting on a failure elsewhere."
  exit 1
fi
if [ "$skipped" -ne 0 ]; then
  echo "OK, WITH $skipped SKIPPED CASE(S): a case that could not reach its precondition proves nothing."
  exit 0
fi
echo "OK: the no-stop_cmd timeout is reported the way upstream does, and the control stays clean"
