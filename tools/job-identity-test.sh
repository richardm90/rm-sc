#!/QOpenSys/pkgs/bin/bash
#
# job-identity-test.sh - is the job RMSC actually launches the SAME kind of
# job, under the SAME name, owning the service's OWN socket, that upstream
# `sc` launches - for both a batch_mode service and an ordinary (non-batch)
# one?
#
# Runs ON the IBM i box, beside tools/sbmjob-opts-test.sh and the other
# harnesses.
#
# WHY A NEW FILE. docs/parity.md ("Batch services run on a genuinely
# different OS mechanism than upstream's") recorded, found but not yet fixed:
# upstream's batch path never runs SBMJOB at all - it execs a custom native
# helper (`scbash`) directly from the JVM with PASE_FORK_JOBNAME set, so its
# job comes up as one genuine BATCH job for its whole life. RMSC's old batch
# path built a literal `SBMJOB CMD(QSH CMD(...))` string, which MEASURES as
# THREE concurrently-live jobs for the service's whole life - the SBMJOB-named
# job itself (type BCH, runs CMD-QSH, never runs the real program), a QZSHSH
# job, and a QP0ZSPWP job that actually owns the socket - so a caller tracking
# the submitted name is tracking the wrong job. Both the measured batch defect
# and its non-batch twin (a real but different bug: a generic,
# collision-prone job name from PASE's spawn(), which has no mechanism to name
# a job the way fork() does) are fixed by this round of work: batch now
# submits via `SBMJOB CMD(CALL PGM(QP2SHELL2) PARM(...))`, and non-batch now
# goes through a new native helper, RMSC_FORK_HELPER, which calls
# `f_fork400(jobname, 0)` directly. Neither existing harness asks this
# question - sbmjob-opts-test.sh asks whether `sbmjob_jobname`/`sbmjob_opts`
# REACH SBMJOB at all, which is a different and already-answered question;
# jobinfo-test.sh asks about `jobinfo`'s own output SHAPE, not which real OS
# job underlies it.
#
# WHAT IS ASSERTED, PER FIXTURE, AND WHY EACH ONE IS A DISAGREEING CASE
# (CLAUDE.md: "a fix and the break it could have been must disagree about at
# least one case in the suite" - every assertion below is written against
# that rule, not merely against what is true today):
#
#   IDENTITY - the job QSYS2.NETSTAT_JOB_INFO says owns the service's own
#   listening socket (LOCAL_PORT = :port AND REMOTE_PORT = 0 - the exact query
#   docs/parity.md records upstream's own QueryUtils.getListeningJobsByPort
#   uses, and SCQRY_jobs_on_port already uses) is looked up again in
#   QSYS2.ACTIVE_JOB_INFO, by its own qualified JOB_NAME, and ITS
#   JOB_NAME_SHORT must equal the name the service was actually submitted or
#   launched under. Before the fix this disagrees for batch (the socket
#   belongs to QP0ZSPWP, not the SBMJOB-named job) and for non-batch (the
#   socket belongs to whatever generic name spawn() picked, not the service's
#   derived name) - this is the literal defect in both cases, and is the most
#   important assertion in this file.
#
#   TYPE - that same socket-owning job's JOB_TYPE must be BCH for the batch
#   fixture and BCI for the non-batch one - MEASURED, both sides, both
#   correct for their own case (see docs/parity.md; the non-batch case was
#   never wrong about type, only about name - asserted here anyway, since a
#   regression in either direction is still worth catching, and because it is
#   what upstream's own job reads as too). For batch this DOES disagree with
#   the old mechanism: docs/parity.md's own measurement records RMSC's old
#   job reclassifying to type BCI where upstream's (and the fix's) stays BCH.
#
#   ONE JOB, batch only - see "WHAT THIS CANNOT FULLY MEASURE" below. A
#   best-effort check that no extra job bearing one of the generic worker
#   names docs/parity.md and the brief for this work actually measured
#   (QZSHSH, QP0ZSPWP/QP0ZSPWT, QP2SHELL/QP2SHELL2, QSHELL) appears under the
#   same user in the window since this fixture's own start. It is scoped as
#   tightly as this script can manage - by job user and by a start timestamp
#   - but it is NOT the same thing as literally counting every job SBMJOB's
#   descendants created, which this script has no verified SQL path to do;
#   see the caveat below.
#
# WHAT THIS CANNOT FULLY MEASURE, AND WHY IT IS SAID OUT LOUD RATHER THAN
# GUESSED PAST
#
#   The three-jobs-for-one-service defect was originally measured by hand,
#   side by side, with DSPJOB OUTPUT(*PRINT) dumps of each job (docs/
#   parity.md). This script's "one job" check is a SQL proxy for that, not a
#   repeat of it, and it was written without being able to run it against the
#   box (see the implementer's note below) - so two things about it are
#   explicitly NOT verified live: that QSYS2.NETSTAT_JOB_INFO's job-identity
#   column is really named JOB_NAME (matching QSYS2.ACTIVE_JOB_INFO's column
#   of the same name, which IS confirmed - see qtestsrc/SCQRY.TEST.RPGLE's own
#   measured dump), and that the named generic worker jobs really do run
#   under the SAME job user as the service's own submitter on this box. If
#   this check reports a false FAIL, suspect the column name or the user
#   scoping before suspecting the fix.
#
# THE PATH/UNQUALIFIED-BINARY BUG IS NOT HERE. See
# tools/unqualified-binary-test.sh - a separate, unrelated defect found in the
# same investigation, about a bare binary name failing outright on the
# non-batch path's old dispatch.
#
# STAGING, NAMING, CLEANUP - same discipline as every sibling harness here.
# Both fixtures are staged in the REAL, shared services directory
# ($HOME/.sc/services) because that is the only place both implementations
# look. Names carry this script's PID so two runs cannot collide and debris is
# attributable. No client name, path, job name or host belongs in this file or
# in anything it prints - every name below is invented.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
DB2UTIL="${DB2UTIL:-/QOpenSys/pkgs/bin/db2util}"
WORK="${WORK:-/tmp/rmsc-job-identity.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the same block every script here
# that keeps a PID-named work directory carries.
ls -dt /tmp/rmsc-job-identity.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  rm -rf "$stale" 2>/dev/null
done

export QIBM_MULTI_THREADED=Y

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Upstream is not optional here - it is one of the two implementations" \
  "being measured, not a bystander."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "Both fixtures' start_cmd ends by exec-ing into a silent python listener."

[ -x "$DB2UTIL" ] || setup_fail \
  "db2util is not executable at: $DB2UTIL" \
  "" \
  "The only questions this file asks - which job owns the socket, and what" \
  "that job's own name and type are - are answered by QSYS2.NETSTAT_JOB_INFO" \
  "and QSYS2.ACTIVE_JOB_INFO, queried through db2util."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py"

SVCDIR="$HOME/.sc/services"
[ -d "$SVCDIR" ] || setup_fail \
  "no services directory at: $SVCDIR" \
  "" \
  "The fixtures have to be visible to BOTH implementations, and this is the" \
  "only place both look."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

# BATCH fixture: an explicit sbmjob_jobname, same reasoning as
# sbmjob-opts-test.sh - a wholly predictable submitted name removes any
# question about the TRUNCATION rule from this file, which is about identity,
# not about SCLAUNCH_job_name's own derivation (that is pinned directly in
# qtestsrc/SCLAUNCH.TEST.RPGLE).
SVC_B="rmsc_jobid_b_$$"
JOBNAME_B="JB$(printf '%08d' "$(( $$ % 100000000 ))")"
PORT_B=59499

# NON-BATCH fixture: NO sbmjob_jobname - this file measures the DERIVED name,
# because that is the path that was actually broken (a generic, spawn()-
# assigned name), and because it is NOT confirmed here whether upstream's own
# non-batch job-naming mechanism honours sbmjob_jobname at all (RMSC's own
# SCLAUNCH_fork_command reuses SCLAUNCH_job_name "as-is", which does - but
# upstream's side of that specific question is not part of what was measured
# for this round of work, so it is deliberately not relied on). The fixture's
# own short name IS the file's basename, already alphanumeric-only and
# exactly ten characters, so SCLAUNCH_job_name's "strip non-alphanumerics,
# truncate to ten, uppercase" rule is a no-op on it and the expected job name
# is simply its upper-case self - no ambiguity about where a truncation would
# land.
SVC_N="jn$(printf '%08d' "$(( $$ % 100000000 ))")"
PORT_N=59500

derive_job_name() {  # the SAME rule SCLAUNCH_job_name uses when no
                      # sbmjob_jobname is given - see qtestsrc/SCLAUNCH.TEST.
                      # RPGLE's own test_job_name_from_service and the
                      # "DERIVED JOB NAME STILL TRUNCATES" block beside it.
  printf '%s' "$1" | tr -cd 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]' | cut -c1-10
}
EXPECT_N="$(derive_job_name "$SVC_N")"

MARKER='# staged by tools/job-identity-test.sh - a test fixture, safe to remove'

for n in "$SVC_B" "$SVC_N"; do
  [ -e "$SVCDIR/$n.yaml" ] && setup_fail \
    "$SVCDIR/$n.yaml already exists." \
    "" \
    "This harness invents that name from its own PID and will not overwrite" \
    "a file it did not write. Remove it if it is debris from a killed run."
done

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
for p in "$PORT_B" "$PORT_N"; do
  port_free "$p" || setup_fail "port $p is already in use - pick a different one or wait"
done

teardown() {
  local rc=$?
  for s in "$SVC_B" "$SVC_N"; do
    "$SCR" stop "$s" >/dev/null 2>&1 </dev/null
    "$SC"  stop "$s" >/dev/null 2>&1 </dev/null
  done
  pkill -f "gate-listen.py.*$PORT_B" >/dev/null 2>&1
  pkill -f "gate-listen.py.*$PORT_N" >/dev/null 2>&1
  rm -f "$SVCDIR/$SVC_B.yaml" "$SVCDIR/$SVC_N.yaml"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"

  local listing left
  listing=$("$SCR" list 2>/dev/null </dev/null)
  left=$(printf '%s\n' "$listing" | grep -cE "^($SVC_B|$SVC_N) " || true)
  [ -z "$left" ] && left=0
  if [ "$left" -ne 0 ]; then
    echo
    echo "TEARDOWN FAILED: $left of this run's own fixture definition(s) are" >&2
    echo "still visible to '$SCR list'." >&2
    printf '%s\n' "$listing" | grep -E "^($SVC_B|$SVC_N) " | sed 's/^/  /' >&2
    echo "Remove them from $SVCDIR before running the fidelity gate." >&2
    exit 3
  fi
  return $rc
}
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

# Reap debris from a run killed before its trap could fire.
for stale in "$SVCDIR"/rmsc_jobid_b_*.yaml "$SVCDIR"/jn[0-9]*.yaml; do
  [ -e "$stale" ] || continue
  grep -Fq -- "$MARKER" "$stale" 2>/dev/null || continue
  base="${stale##*/}"; base="${base%.yaml}"
  owner="${base##*_}"
  case "$owner" in ''|*[!0-9]*) owner="" ;; esac
  if [ -n "$owner" ]; then
    [ "$owner" = "$$" ] && continue
    if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
    case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  fi
  "$SCR" stop "$base" >/dev/null 2>&1 </dev/null
  "$SC"  stop "$base" >/dev/null 2>&1 </dev/null
  rm -f "$stale"
done

pass=0; failed=0

report() { local verdict="$1" tag="$2"; shift 2; printf '  %-9s %-28s %s\n' "$verdict" "$tag" "$*"; }
detail() { printf '  %-9s %-28s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-28s %s\n' verdict case detail
  printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
}

wait_for_status() {  # bin name want seconds -> prints final status
  local bin="$1" name="$2" want="$3" secs="$4" st=""
  local i
  for ((i=0; i<secs; i++)); do
    st=$("$bin" check "$name" 2>/dev/null </dev/null | grep -F -- "$name" | sed 's/ *|.*//; s/^ *//')
    [ "$st" = "$want" ] && break
    sleep 1
  done
  printf '%s' "$st"
}

# ---------------------------------------------------------------------------
# check_job_identity - stage one service under one implementation, assert
# IDENTITY and TYPE, and (batch only) the best-effort ONE-JOB check.
# ---------------------------------------------------------------------------
check_job_identity() {
  local label="$1" start_bin="$2" stop_bin="$3" svc="$4" port="$5" \
        expect_short="$6" expect_type="$7" check_extra="$8"
  local start_ts st sockrow sockcount sockjob detailrow sock_short sock_type \
        sock_user extra extra_count

  start_ts=$(date '+%Y-%m-%d-%H.%M.%S')
  "$start_bin" start "$svc" > "$WORK/$label.start.out" 2> "$WORK/$label.start.err" </dev/null
  st=$(wait_for_status "$start_bin" "$svc" RUNNING 30)
  if [ "$st" != RUNNING ]; then
    report FAIL "$label-start" "left '$svc' $st after 30s, wanted RUNNING"
    detail "it said: $(head -n 1 "$WORK/$label.start.err" 2>/dev/null)"
    failed=$((failed+1))
    return
  fi
  report PASS "$label-start" "started, RUNNING after the wait"
  pass=$((pass+1))

  # NETSTAT_JOB_INFO is a plain view, not a table function - MEASURED:
  # TABLE(QSYS2.NETSTAT_JOB_INFO()) errors "not found" (it's QSYS2.
  # ACTIVE_JOB_INFO, queried below, that genuinely needs the TABLE() form).
  sockrow=$("$DB2UTIL" -o csv \
    "SELECT JOB_NAME FROM QSYS2.NETSTAT_JOB_INFO WHERE LOCAL_PORT = $port AND REMOTE_PORT = 0" \
    2>"$WORK/$label.sock.err")
  sockcount=$(printf '%s\n' "$sockrow" | grep -c . || true); [ -z "$sockcount" ] && sockcount=0
  if [ "$sockcount" -ne 1 ]; then
    report FAIL "$label-socket-owner" "found $sockcount row(s) for port $port in NETSTAT_JOB_INFO, wanted 1"
    detail "cannot assert identity without knowing which job owns the socket"
    failed=$((failed+1))
    "$stop_bin" stop "$svc" >/dev/null 2>&1 </dev/null
    return
  fi
  sockjob=$(printf '%s\n' "$sockrow" | tr -d '"')
  report PASS "$label-socket-owner" "exactly one job owns port $port: $sockjob"
  pass=$((pass+1))

  detailrow=$("$DB2UTIL" -o csv \
    "SELECT JOB_NAME_SHORT, JOB_TYPE, JOB_USER FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) WHERE JOB_NAME = '$sockjob'" \
    2>"$WORK/$label.detail.err")
  sock_short=$(printf '%s\n' "$detailrow" | cut -d',' -f1 | tr -d '"')
  sock_type=$(printf '%s\n' "$detailrow"  | cut -d',' -f2 | tr -d '"')
  sock_user=$(printf '%s\n' "$detailrow"  | cut -d',' -f3 | tr -d '"')

  # IDENTITY - the most important assertion in this file. Disagrees with the
  # old mechanism on both fixtures; see header.
  if [ "$sock_short" = "$expect_short" ]; then
    report PASS "$label-identity" "the job owning the socket ($sockjob) IS the job named/tracked for this service ($expect_short)"
    pass=$((pass+1))
  else
    report FAIL "$label-identity" "the socket-owning job is '$sock_short' ($sockjob), wanted '$expect_short' - this is the split the fix closes"
    failed=$((failed+1))
  fi

  # TYPE
  if [ "$sock_type" = "$expect_type" ]; then
    report PASS "$label-type" "the socket-owning job's type is $expect_type, matching upstream"
    pass=$((pass+1))
  else
    report FAIL "$label-type" "the socket-owning job's type is '$sock_type', wanted '$expect_type'"
    failed=$((failed+1))
  fi

  # ONE JOB - batch only, best-effort (see header caveat).
  if [ "$check_extra" = yes ]; then
    extra=$("$DB2UTIL" -o csv \
      "SELECT JOB_NAME FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) WHERE JOB_USER = '$sock_user' AND JOB_NAME <> '$sockjob' AND JOB_ACTIVE_TIME >= '$start_ts' AND JOB_NAME_SHORT IN ('QZSHSH','QP0ZSPWP','QP0ZSPWT','QP2SHELL','QP2SHELL2','QSHELL')" \
      2>"$WORK/$label.extra.err")
    extra_count=$(printf '%s\n' "$extra" | grep -c . || true); [ -z "$extra_count" ] && extra_count=0
    if [ "$extra_count" -eq 0 ]; then
      report PASS "$label-one-job" "no extra generic worker job seen alongside it (best-effort - see header)"
      pass=$((pass+1))
    else
      report FAIL "$label-one-job" "found $extra_count extra generic worker job(s) under the same user since start: $(printf '%s' "$extra" | tr '\n' ' ')"
      detail "this is exactly the three-jobs-for-one-service split the fix closes, if it is real and not a same-named bystander - see header caveat"
      failed=$((failed+1))
    fi
  fi

  "$stop_bin" stop "$svc" > "$WORK/$label.stop.out" 2> "$WORK/$label.stop.err" </dev/null
  wait_for_status "$start_bin" "$svc" 'NOT RUNNING' 15 >/dev/null
}

printf 'job-identity: does the job RMSC launches own its own socket, under the name it was launched with?\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'fixtures: %s (batch_mode, sbmjob_jobname=%s), %s (non-batch, derived name=%s)\n\n' \
  "$SVC_B" "$JOBNAME_B" "$SVC_N" "$EXPECT_N"

echo "== stage 0: the fixtures"
echo
cat > "$SVCDIR/$SVC_B.yaml" <<EOF
$MARKER
name: RMSC job-identity fixture $SVC_B (batch)
start_cmd: $PY $HERE/gate-listen.py --seconds 60 $PORT_B
check_alive: $PORT_B
batch_mode: true
sbmjob_jobname: $JOBNAME_B
startup_wait_time: 20
stop_wait_time: 10
EOF
cat > "$SVCDIR/$SVC_N.yaml" <<EOF
$MARKER
name: RMSC job-identity fixture $SVC_N (non-batch)
start_cmd: $PY $HERE/gate-listen.py --seconds 60 $PORT_N
check_alive: $PORT_N
startup_wait_time: 15
stop_wait_time: 5
EOF

fx=()
for pair in "$SVC_B:$PORT_B" "$SVC_N:$PORT_N"; do
  n="${pair%%:*}"; p="${pair#*:}"
  st=$("$SCR" check "$n" 2>/dev/null </dev/null | grep -F -- "$n" | sed 's/ *|.*//; s/^ *//')
  case "$st" in
    'NOT RUNNING') ;;
    '')            fx+=("$n did not load - '$SCR check $n' shows no row for it") ;;
    *)             fx+=("$n is already $st before anything started it - port $p is held by something else") ;;
  esac
done
if [ ${#fx[@]} -ne 0 ]; then
  report FAIL fixture-definitions "the staged definitions are not usable"
  for p in "${fx[@]}"; do detail "$p"; done
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed"
  echo "FAILED: no usable fixture"
  exit 1
fi
report PASS fixture-definitions "both staged definitions load and neither is running"
pass=$((pass+1))

echo
echo "== stage 1: batch_mode - the single most important case, since this is the literal defect that was found"
echo
heading
check_job_identity sc-batch  "$SC"  "$SC"  "$SVC_B" "$PORT_B" "$JOBNAME_B" BCH yes
check_job_identity scr-batch "$SCR" "$SCR" "$SVC_B" "$PORT_B" "$JOBNAME_B" BCH yes

echo
echo "== stage 2: non-batch - the generic-job-name bug, and its PASE_run_cmd/f_fork400 twin"
echo
heading
check_job_identity sc-nonbatch  "$SC"  "$SC"  "$SVC_N" "$PORT_N" "$EXPECT_N" BCI no
check_job_identity scr-nonbatch "$SCR" "$SCR" "$SVC_N" "$PORT_N" "$EXPECT_N" BCI no

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (.out/.err captured separately for every case; KEEP=1 to keep them)"

if [ "$failed" -ne 0 ]; then
  echo "FAILED: see the named reasons above"
  exit 1
fi
echo "OK: the job each implementation actually launches owns its own socket, under the name it was launched with, for both batch and non-batch"
