#!/QOpenSys/pkgs/bin/bash
#
# fork-helper-test.sh - does native/rmsc_fork_helper.c's deployed binary
# actually behave the way its own header comment documents, including the
# one path no other harness can reach: f_fork400() genuinely FAILING?
#
# Runs ON the IBM i box, beside tools/job-identity-test.sh and the other
# harnesses. Invokes the deployed binary directly
# (/QOpenSys/pkgs/lib/rmsc/native/rmsc_fork_helper) - this is deliberately
# NOT a staged `.sc/services` fixture. tools/job-identity-test.sh and
# tools/unqualified-binary-test.sh already exercise this helper THROUGH
# SCLAUNCH_fork_command, for a different question (job identity, PATH) -
# both only ever drive it down its happy path, because a staged service
# has no way to ask f_fork400() to fail. This file asks the helper
# directly, with its own documented, measured, side-effect-free way to
# force that failure (an out-of-range resourceID, its optional 3rd
# argument - see the helper's own header: resourceID 999999999 fails
# reliably with "Error 3489 occurred"; ulimit -u does not reach
# f_fork400() at all and was tried and rejected before that finding).
#
# THE BUG THIS EXISTS TO CATCH
#
# Before the fix recorded in docs/parity.md ("Non-batch services get an
# unusable, generic job name"), the helper's own check could not tell a
# failed fork apart from a successful one: f_fork400() returns -1 on
# failure, 0 in the child, and a positive pid in the parent, and the old
# code's test was `if (f_fork400(...) != 0) return 0;` - true for BOTH a
# successful parent (whatever positive pid) AND a failed fork (-1), so a
# fork failure took the exact same "return 0" branch as success. A test
# that only ever exercises the happy path - which is all a staged service
# fixture can do, since start_cmd never fails to fork in practice - cannot
# tell the fixed code apart from the bug it replaced. This file forces the
# failure for real and checks the one thing that disagrees.
#
# WHAT IS ASSERTED, AND WHICH ONE IS THE DISAGREEING CASE
# (CLAUDE.md: "a fix and the break it could have been must disagree about
# at least one case in the suite")
#
#   FORCED-FAILURE EXIT CODE - THE CASE THAT MATTERS. Running the helper
#   with an out-of-range resourceID must exit exactly 2 (`forced-fail-exit`
#   below), not 0. Under the OLD, buggy code this is the one assertion in
#   this whole file that would have come out DIFFERENT: f_fork400() still
#   returns -1 for this exact invocation (the failure is in the OS call,
#   not in the helper's own logic), -1 != 0, so the old code took its
#   "parent, nothing more to do" branch and returned 0 - a PASS-shaped exit
#   for a fork that never happened. The fixed code's pid<0 check returns 2
#   instead. Every other assertion in this file (argument-count handling,
#   the happy path's exit 0) is true of both the old and the new code and
#   proves only that nothing else regressed - this is the one case that
#   actually separates them, so it is pinned to the literal value 2, not
#   merely "non-zero".
#
#   FORCED-FAILURE: NO JOB EVER APPEARS - confirms f_fork400() failing
#   really did mean no child exists at all, not a half-forked job left
#   behind; queried from QSYS2.ACTIVE_JOB_INFO, the same source
#   job-identity-test.sh already relies on for job identity.
#
#   FORCED-FAILURE: SOMETHING DIAGNOSTIC ON STDOUT - not pinned to exact
#   wording (the libc message text could vary by OS level - see the
#   helper's own header), just confirmed non-empty and plausibly about the
#   failure. PASE_run_cmd's own caller (SCLAUNCH_start/SCEXEC_start) is
#   what actually surfaces this text to a real error path.
#
#   HAPPY PATH - the exact invocation shape SCLAUNCH_fork_command uses in
#   production (no 3rd argument at all, not resourceID=0 spelled out):
#   exits 0, AND the command given to it actually ran - confirmed two
#   independent ways, not just the exit code: the job appears under the
#   given name in QSYS2.ACTIVE_JOB_INFO, AND the port the command binds
#   becomes connectable. Either alone would leave open the question the
#   old bug's shape raises generally (a "success" exit that does not mean
#   what it says) - both together rule out "job named right, but exec()
#   never actually ran anything" as well as "something is listening on
#   that port already, unrelated to this run".
#
#   BAD ARGUMENT COUNT - 0 and 1 arguments both exit 1. Cheap, already
#   documented in the helper's own header, worth pinning so it cannot
#   silently regress - this path returns before f_fork400() is ever
#   called, so no job-absence check is needed for it.
#
# WHY QSYS2.ACTIVE_JOB_INFO, NOT WRKACTJOB/DSPJOB SCREEN OUTPUT - same
# reasoning and the same column (JOB_NAME_SHORT) tools/job-identity-test.sh
# already measured working for this exact non-batch mechanism; db2util is
# a hard setup dependency here for the same reason it is there.
#
# PKILL DOES NOT EXIST ON THIS BOX - MEASURED, not assumed from the
# sibling harnesses' own (silently-swallowed, `>/dev/null 2>&1`) pkill
# calls: `type pkill` fails under both an interactive shell and this
# script's own `#!/QOpenSys/pkgs/bin/bash` shebang. Cleanup here finds the
# listener by matching `ps -ef` on the port it was given and sends it a
# plain `kill`, falling back on gate-listen.py's own bounded `--seconds`
# lifetime (its own header: "a harness killed between staging and cleanup
# leaks a process that goes away on its own rather than one that waits
# forever") if that fails for any reason.
#
# STAGING, NAMING, CLEANUP - same discipline as every sibling harness here,
# minus the services-directory staging this file has no use for (it never
# goes through `sc`/`scr` at all). Names carry this script's PID so two
# runs cannot collide and debris is attributable. No client name, path,
# job name or host belongs in this file or in anything it prints - every
# name below is invented.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${HELPER:-/QOpenSys/pkgs/lib/rmsc/native/rmsc_fork_helper}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
GL="$HERE/gate-listen.py"
DB2UTIL="${DB2UTIL:-/QOpenSys/pkgs/bin/db2util}"
WORK="${WORK:-/tmp/rmsc-fork-helper.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the same block every script here
# that keeps a PID-named work directory carries.
ls -dt /tmp/rmsc-fork-helper.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  rm -rf "$stale" 2>/dev/null
done

export QIBM_MULTI_THREADED=Y

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$HELPER" ] || setup_fail \
  "rmsc_fork_helper is not executable at: $HELPER" \
  "" \
  "This is the fixed, deployed path RMSC calls at runtime by convention" \
  "(docs/tobi-binding.md, QRPGLESRC/SCLAUNCH.RPGLE's SCLAUNCH_FORK_HELPER) -" \
  "build and deploy it (makei build) before running this file. Set" \
  "HELPER=<path> if it genuinely lives elsewhere on this box."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The happy-path fixture's command is a silent python listener."

[ -f "$GL" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $GL"

[ -x "$DB2UTIL" ] || setup_fail \
  "db2util is not executable at: $DB2UTIL" \
  "" \
  "Confirming job identity (and job ABSENCE, for the forced-failure case)" \
  "is answered from QSYS2.ACTIVE_JOB_INFO, queried through db2util - the" \
  "same source tools/job-identity-test.sh already relies on."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

# Alphanumeric, uppercase, 10 characters - a job name f_fork400() will
# accept outright, with no truncation/casing question to get in the way of
# what this file actually asks. Two distinct prefixes so the happy-path and
# forced-failure job names can never collide with each other within one run.
JOB_OK="FH$(printf '%08d' "$(( $$ % 100000000 ))")"
JOB_FAIL="FX$(printf '%08d' "$(( $$ % 100000000 ))")"
PORT_OK=59530
PORT_FAIL=59531

port_free() {
  "$PY" - "$1" <<'PYEOF'
import socket, sys
s = socket.socket()
try:
    s.bind(('0.0.0.0', int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
PYEOF
}
for p in "$PORT_OK" "$PORT_FAIL"; do
  port_free "$p" || setup_fail "port $p is already in use - pick a different one or wait"
done

# Best-effort kill of any listener this run started, matched by the port it
# was told to bind - see header, pkill genuinely does not exist on this box.
kill_listener_on() {
  local port="$1" pids
  pids=$(ps -ef 2>/dev/null | grep -F 'gate-listen.py' | grep -F -- "$port" | grep -v grep | awk '{print $2}')
  for p in $pids; do kill "$p" 2>/dev/null; done
}

teardown() {
  local rc=$?
  kill_listener_on "$PORT_OK"
  kill_listener_on "$PORT_FAIL"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
  return $rc
}
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

pass=0; failed=0

report() { local verdict="$1" tag="$2"; shift 2; printf '  %-9s %-24s %s\n' "$verdict" "$tag" "$*"; }
detail() { printf '  %-9s %-24s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-24s %s\n' verdict case detail
  printf '  %-9s %-24s %s\n' --------- ------------------------ ------
}

job_name_for() {  # shortname -> prints the qualified JOB_NAME if one exists, else nothing
  "$DB2UTIL" -o csv \
    "SELECT JOB_NAME FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) WHERE JOB_NAME_SHORT = '$1'" \
    2>/dev/null | tr -d '"' | grep -v '^$'
}

job_type_for() {  # qualified job name -> prints JOB_TYPE
  "$DB2UTIL" -o csv \
    "SELECT JOB_TYPE FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) WHERE JOB_NAME = '$1'" \
    2>/dev/null | tr -d '"' | grep -v '^$'
}

port_connects() {  # port -> 0 if something accepts a connection, 1 otherwise
  "$PY" - "$1" <<'PYEOF'
import socket, sys
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', int(sys.argv[1])))
except Exception:
    sys.exit(1)
finally:
    s.close()
PYEOF
}

poll_until_job() {  # shortname secs -> prints qualified job name once seen, else nothing after timeout
  local short="$1" secs="$2" i found
  for ((i=0; i<secs; i++)); do
    found=$(job_name_for "$short")
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    sleep 1
  done
  printf ''
}

poll_until_port() {  # port secs -> 0 once connectable within timeout, 1 if it never is
  local port="$1" secs="$2" i
  for ((i=0; i<secs; i++)); do
    port_connects "$port" && return 0
    sleep 1
  done
  return 1
}

job_absent_over() {  # shortname secs -> prints the qualified name if one DID appear (so the caller can report it), else nothing
  local short="$1" secs="$2" i found
  for ((i=0; i<secs; i++)); do
    found=$(job_name_for "$short")
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    sleep 1
  done
  printf ''
}

printf 'fork-helper: does rmsc_fork_helper behave exactly as its own header documents, success AND forced failure alike?\n'
printf 'helper: %s\n\n' "$HELPER"

# ---------------------------------------------------------------------------
echo "== stage 1: bad argument count - cheap, already documented, worth pinning"
echo
heading
# ---------------------------------------------------------------------------

"$HELPER" > "$WORK/argc0.out" 2> "$WORK/argc0.err" </dev/null
rc0=$?
if [ "$rc0" -eq 1 ]; then
  report PASS argc-zero "0 arguments exits 1"
  pass=$((pass+1))
else
  report FAIL argc-zero "0 arguments exited $rc0, wanted 1"
  failed=$((failed+1))
fi

"$HELPER" "$JOB_OK" > "$WORK/argc1.out" 2> "$WORK/argc1.err" </dev/null
rc1=$?
if [ "$rc1" -eq 1 ]; then
  report PASS argc-one "1 argument exits 1"
  pass=$((pass+1))
else
  report FAIL argc-one "1 argument exited $rc1, wanted 1"
  failed=$((failed+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 2: the happy path - the exact invocation shape SCLAUNCH_fork_command uses in production"
echo
heading
# ---------------------------------------------------------------------------

CMD_OK="$PY $GL --seconds 25 $PORT_OK"
"$HELPER" "$JOB_OK" "$CMD_OK" > "$WORK/ok.out" 2> "$WORK/ok.err" </dev/null
rc_ok=$?

if [ "$rc_ok" -eq 0 ]; then
  report PASS happy-exit "no 3rd argument (production's own shape) exits 0"
  pass=$((pass+1))
else
  report FAIL happy-exit "exited $rc_ok, wanted 0"
  detail "it said: $(head -n 1 "$WORK/ok.err" "$WORK/ok.out" 2>/dev/null | grep -v '^$' | head -n 1)"
  failed=$((failed+1))
fi

ok_job=$(poll_until_job "$JOB_OK" 10)
if [ -n "$ok_job" ]; then
  report PASS happy-job-identity "the job actually exists, named $JOB_OK ($ok_job) - not merely a 0 exit code"
  pass=$((pass+1))
  ok_type=$(job_type_for "$ok_job")
  if [ "$ok_type" = BCI ]; then
    report PASS happy-job-type "job type is BCI, matching the non-batch fork mechanism"
    pass=$((pass+1))
  else
    report FAIL happy-job-type "job type is '$ok_type', wanted BCI"
    failed=$((failed+1))
  fi
else
  report FAIL happy-job-identity "no job named $JOB_OK ever appeared in QSYS2.ACTIVE_JOB_INFO within 10s"
  detail "a 0 exit code alone does not prove f_fork400() - or exec() - really ran"
  failed=$((failed+1))
fi

if poll_until_port "$PORT_OK" 10; then
  report PASS happy-command-ran "port $PORT_OK is connectable - the child really exec'd into the given command"
  pass=$((pass+1))
else
  report FAIL happy-command-ran "port $PORT_OK never became connectable within 10s"
  detail "the job may exist (exit 127 territory: fork ok, exec failed) without the command ever running"
  failed=$((failed+1))
fi

kill_listener_on "$PORT_OK"

echo
# ---------------------------------------------------------------------------
echo "== stage 3: forced f_fork400() failure (resourceID 999999999) - THE CASE THAT MATTERS, see header"
echo
heading
# ---------------------------------------------------------------------------

CMD_FAIL="$PY $GL --seconds 15 $PORT_FAIL"
"$HELPER" "$JOB_FAIL" "$CMD_FAIL" 999999999 > "$WORK/fail.out" 2> "$WORK/fail.err" </dev/null
rc_fail=$?

# THE DISAGREEING ASSERTION. Under the OLD code this exits 0 (f_fork400()
# genuinely returns -1 here; -1 != 0, so the old "not the child, therefore
# parent success" branch fired). Under the fixed code this is pid<0, so it
# exits 2. If this ever reads 0 again, the old bug is back.
if [ "$rc_fail" -eq 2 ]; then
  report PASS forced-fail-exit "exits exactly 2 - the documented f_fork400()-failed code, NOT 0"
  pass=$((pass+1))
else
  report FAIL forced-fail-exit "exited $rc_fail, wanted exactly 2 - under the OLD code this case exits 0 (see header: 'the case that matters')"
  failed=$((failed+1))
fi

fail_stdout="$(cat "$WORK/fail.out" 2>/dev/null)"
if [ -n "$fail_stdout" ] && printf '%s' "$fail_stdout" | grep -qiE 'fail|error|f_fork400'; then
  report PASS forced-fail-diagnostic "stdout is non-empty and plausibly about the failure: '$fail_stdout'"
  pass=$((pass+1))
else
  report FAIL forced-fail-diagnostic "stdout was '${fail_stdout:-<empty>}' - wanted something non-empty, plausibly mentioning the failure"
  failed=$((failed+1))
fi

leaked_job=$(job_absent_over "$JOB_FAIL" 3)
if [ -z "$leaked_job" ]; then
  report PASS forced-fail-no-job "no job named $JOB_FAIL ever appeared - nothing was created, not even half-formed"
  pass=$((pass+1))
else
  report FAIL forced-fail-no-job "a job named $JOB_FAIL DID appear ($leaked_job) despite the forced f_fork400() failure"
  failed=$((failed+1))
fi

if poll_until_port "$PORT_FAIL" 3; then
  report FAIL forced-fail-no-command "port $PORT_FAIL became connectable - the command ran despite the forced fork failure"
  failed=$((failed+1))
else
  report PASS forced-fail-no-command "port $PORT_FAIL never became connectable - the command never ran"
  pass=$((pass+1))
fi

kill_listener_on "$PORT_FAIL"

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (.out/.err captured separately for every case; KEEP=1 to keep them)"

if [ "$failed" -ne 0 ]; then
  echo "FAILED: see the named reasons above"
  exit 1
fi
echo "OK: rmsc_fork_helper's documented exit codes hold, including the one path only a forced f_fork400() failure can reach"
