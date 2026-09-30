#!/QOpenSys/pkgs/bin/bash
#
# sbmjob-opts-test.sh - does `sbmjob_jobname:` and `sbmjob_opts:` actually
# reach the SBMJOB command, not merely get read out of the definition and
# passed through info's display of it?
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses.
#
# WHY A NEW FILE. A coverage audit (30 September 2026) found these two keys
# had no live coverage at all - qtestsrc/SCEXEC.TEST.RPGLE checks that the
# definition is PARSED, and nothing measured the submitted job against either
# implementation. Neither existing harness is a fit: loginfo-test.sh asks
# where a LOG lands, and jobinfo-test.sh asks about the SHAPE of `jobinfo`'s
# own output - this is neither. It is a question about the job SBMJOB actually
# created, asked directly of the operating system.
#
# WHY SQL, NOT `jobinfo`. The same audit surfaced a real, separate divergence:
# for a service whose listening socket ends up held by a PASE worker job
# (QP0ZSPWT) rather than the job SBMJOB named, RMSC's `jobinfo` reports the
# worker, upstream reports the named job. Reproduced with and without batch
# mode; does not orphan anything on stop; not reproduced with a Java listener
# (mapepire) all session - see local/plan.md's coverage note, dated
# 30 September 2026, for the standing detail. Asking `jobinfo` here would
# make THIS test depend on THAT bug's exact scope, for a question it has
# nothing to do with. QSYS2.ACTIVE_JOB_INFO is asked directly instead - the
# same interface RMSC's own SCJOB module queries (docs/performance.md) - by
# the job name SBMJOB was actually given, which sidesteps port-to-job
# attribution entirely.
#
# ---------------------------------------------------------------------------
# CLEANUP BLOCK - same shape as every sibling harness here.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
DB2UTIL="${DB2UTIL:-/QOpenSys/pkgs/bin/db2util}"
WORK="${WORK:-/tmp/rmsc-sbmjob-opts.$$}"

ls -dt /tmp/rmsc-sbmjob-opts.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
  "Upstream is not optional here - it SUBMITS the fixture, and the whole point" \
  "is comparing what it submits against what RMSC submits."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The fixture's start_cmd is a SILENT python listener; sc captures a" \
  "service's output into its log, so anything printed there changes the case."

[ -x "$DB2UTIL" ] || setup_fail \
  "db2util is not executable at: $DB2UTIL" \
  "" \
  "The only question this file asks - what job did SBMJOB actually create -" \
  "is answered by QSYS2.ACTIVE_JOB_INFO, queried through db2util."

SVCDIR="$HOME/.sc/services"
[ -d "$SVCDIR" ] || setup_fail \
  "no services directory at: $SVCDIR" \
  "" \
  "The fixture has to be visible to BOTH implementations, and this is the" \
  "only place both look."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py"

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

# A real IBM i job name: alphabetic first character, 10 characters, derived
# from the PID so two runs cannot collide and debris can be attributed.
SVC="rmsc_sbop_$$"
JOBNAME="SB$(printf '%08d' "$(( $$ % 100000000 ))")"
PORT=59496
PRIORITY=3   # any legal JOBPTY value; only its TEXT reaching SBMJOB is checked, see below

# NOT ASSERTED HERE: JOBPTY(3)'s numeric effect on RUN_PRIORITY. Measured live
# (30 September 2026) that this box's subsystem routing overrides run priority
# regardless of what SBMJOB was given - sc and scr both land on RUN_PRIORITY
# 50 for the same JOBPTY(3), so the column has no power to tell a working
# sbmjob_opts from a silently dropped one here. What IS asserted instead is
# stronger than it looks: sbmjob_jobname (JOB(...)) and sbmjob_opts are
# appended to the SAME clcmd string and executed in the SAME QCMD_exc call
# (QRPGLESRC/SCLAUNCH.RPGLE) - if the appended sbmjob_opts text were malformed
# or silently dropped in a way that broke the command, SBMJOB would fail
# outright and no job named $JOBNAME would exist at all. A job existing under
# exactly that name IS evidence the whole command, opts included, was
# accepted and executed.
MARKER='# staged by tools/sbmjob-opts-test.sh - a test fixture, safe to remove'

[ -e "$SVCDIR/$SVC.yaml" ] && setup_fail \
  "$SVCDIR/$SVC.yaml already exists." \
  "" \
  "This harness invents that name from its own PID and will not overwrite a" \
  "file it did not write. Remove it if it is debris from a killed run."

teardown() {
  local rc=$?
  "$SC" stop "$SVC" >/dev/null 2>&1 </dev/null
  "$SCR" kill "$SVC" >/dev/null 2>&1 </dev/null
  pkill -f "gate-listen.py.*$PORT" >/dev/null 2>&1
  rm -f "$SVCDIR/$SVC.yaml"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"

  local listing left
  listing=$("$SCR" list 2>/dev/null </dev/null)
  left=$(printf '%s\n' "$listing" | grep -cE "^$SVC " || true)
  [ -z "$left" ] && left=0
  if [ "$left" -ne 0 ]; then
    echo
    echo "TEARDOWN FAILED: $SVC is still visible to '$SCR list'." >&2
    echo "Remove it from $SVCDIR before running the fidelity gate." >&2
    exit 3
  fi
  return $rc
}
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

# Reap a dead run's own debris before staging.
for stale in "$SVCDIR"/rmsc_sbop_*.yaml; do
  [ -e "$stale" ] || continue
  base="${stale##*/}"; base="${base%.yaml}"
  owner="${base##*_}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  [ "$owner" = "$$" ] && continue
  grep -Fq -- "$MARKER" "$stale" 2>/dev/null || continue
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  "$SC" stop "$base" >/dev/null 2>&1 </dev/null
  rm -f "$stale"
done

pass=0; failed=0

report() {
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-28s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-28s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-28s %s\n' verdict case detail
  printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
}

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture"
echo
cat > "$SVCDIR/$SVC.yaml" <<EOF
name: RMSC sbmjob_jobname/sbmjob_opts fixture $SVC
start_cmd: $PY $HERE/gate-listen.py --seconds 30 $PORT
check_alive: $PORT
startup_wait_time: 10
stop_wait_time: 5
batch_mode: true
sbmjob_jobname: $JOBNAME
sbmjob_opts: JOBPTY($PRIORITY)
$MARKER
EOF

echo "== stage 1: does sbmjob_jobname/sbmjob_opts reach the submitted SBMJOB, not just the parser?"
echo
heading

check_submitted_job() {  # impl_label start_bin stop_bin
  local label="$1" start_bin="$2" stop_bin="$3" row name count

  "$start_bin" start "$SVC" > "$WORK/$label.start.out" 2> "$WORK/$label.start.err" </dev/null

  row=$("$DB2UTIL" -o csv \
    "SELECT JOB_NAME_SHORT FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) WHERE JOB_NAME_SHORT = '$JOBNAME'" \
    2>"$WORK/$label.sql.err")
  count=$(printf '%s\n' "$row" | grep -c . || true); [ -z "$count" ] && count=0

  "$stop_bin" stop "$SVC" >/dev/null 2>&1 </dev/null

  if [ "$count" -ne 1 ]; then
    report FAIL "$label-job-exists" "found $count job(s) named $JOBNAME in ACTIVE_JOB_INFO, wanted 1"
    detail "SBMJOB either failed outright or accepted a different name - see \$WORK/$label.start.*"
    failed=$((failed+1))
    return 1
  fi
  report PASS "$label-job-exists" "MEASURED - SBMJOB accepted the whole clcmd, including sbmjob_opts"
  pass=$((pass+1))

  name=$(printf '%s\n' "$row" | cut -d',' -f1 | tr -d '"')

  if [ "$name" = "$JOBNAME" ]; then
    report PASS "$label-jobname" "MEASURED - sbmjob_jobname reached SBMJOB"
    pass=$((pass+1))
  else
    report FAIL "$label-jobname" "job name was '$name', wanted '$JOBNAME'"
    failed=$((failed+1))
  fi
  return 0
}

# upstream first - if it cannot be measured, RMSC's row is not evidence either.
if check_submitted_job sc "$SC" "$SC"; then
  check_submitted_job scr "$SCR" "$SCR"
else
  detail "skipping scr - upstream's own row did not check out"
fi

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (.out/.err/.sql.err captured separately for every case; KEEP=1 to keep them)"

if [ "$failed" -ne 0 ]; then
  echo "FAILED: sbmjob_jobname/sbmjob_opts do not reach SBMJOB the way upstream reports"
  exit 1
fi
