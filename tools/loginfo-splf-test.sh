#!/QOpenSys/pkgs/bin/bash
#
# loginfo-splf-test.sh - what `loginfo` says about a BATCH service's SPOOLED
# FILES: the wording, the ordering against the log-file line, and whether
# finding one suppresses the not-found warning the way a non-empty log
# already does.
#
# Runs ON the IBM i box, beside tools/loginfo-test.sh and the other harnesses.
#
# WHY A NEW FILE RATHER THAN A CASE ADDED TO loginfo-test.sh
#
# loginfo-test.sh's own header says this in so many words: its fixtures are
# never `batch_mode`, so they can never produce a spooled file, and its
# shape-checker (`check_stdout_shape`) deliberately TOLERATES a spooled-file
# line wherever one appears rather than asserting anything about its
# content - because, at the time that file was written, "producing a
# spooled file owned by the service's own job needs a batch_mode service;
# PASE runs each `system` call in its own job" and nobody had solved that
# staging problem yet. It has now been solved (see THE FIXTURE below), so
# this is new coverage, not a gap in loginfo-test.sh - that file's ordinary
# log-reporting scope is untouched, and this file does not duplicate any of
# its four cases.
#
# THE FIXTURE, AND WHY IT IS BUILT THIS WAY
#
# A `batch_mode` service whose start_cmd is:
#
#   /QOpenSys/pkgs/bin/bash -c "cl -sk \"DSPJOB OUTPUT(*PRINT)\" ; exec ..."
#
# `cl` is a PASE bash BUILTIN, not /QOpenSys/usr/bin/system. `-s` suppresses
# echoing the spooled content back to stdout (which would otherwise land in
# the service's own log and change which case this is); `-k` KEEPS the spool
# file instead of deleting it; and `cl` runs in the CURRENT job by default,
# which is the only way the spooled file it leaves behind is genuinely
# attributable to the service's own job rather than to a separate, transient
# one. Plain `system "..."` always takes that second path - see
# docs/testing-notes.md's `qsh`/`system` finding for the general shape of
# that trap, and docs/parity.md's "Batch services run on a genuinely
# different OS mechanism" for why this job's identity is worth being careful
# about at all.
#
# `exec`-ing into tools/gate-listen.py afterwards means the DSPJOB step runs
# exactly once, leaves exactly one real spooled file (`QPDSPJOB`) on disk,
# and the job then keeps running under the listener for the rest of this
# script's measurement - satisfying `check_alive` and giving `loginfo`
# something to read for as long as it needs. Confirmed working, live,
# against both implementations before this file was written - see the
# session transcript referenced in the implementer's brief.
#
# WHAT WAS MEASURED, RE-TAKEN HERE RATHER THAN TRUSTED FROM A TRANSCRIPTION
#
#   upstream (sc), stdout:
#     <short>: DSPSPLF FILE(QPDSPJOB) JOB(<job>) SPLNBR(<n>)
#     <short>: <log file path>
#     <one trailing blank line>
#   upstream, stderr: empty - finding a spooled file suppresses the
#     not-found warning exactly as a non-empty log already does.
#
#   RMSC (scr) TODAY, same fixture, stdout:
#     <short>: <log file path>
#         spooled file QPDSPJOB number 1 in <job>
#     <one trailing blank line>
#   RMSC, stderr: empty (this fixture always has a log too, so the suffix
#     question doesn't arise here).
#
# So RMSC's defect, as this file pins it, is TWO NAMED THINGS, never a vague
# mismatch:
#   (1) WORDING/SHAPE - the spooled-file line does not read
#       '<short>: DSPSPLF FILE(<name>) JOB(<job>) SPLNBR(<n>)'.
#   (2) ORDER - RMSC prints the log line BEFORE the spooled-file line;
#       upstream prints the spooled-file section FIRST.
#
# A fix is correct here when BOTH read right AND the not-found warning stays
# suppressed - the third thing pinned below, by the regression control.
#
# THE CAVEAT THIS FILE IS DELIBERATELY BUILT AROUND
#
# docs/parity.md ("Batch services run on a genuinely different OS mechanism
# than upstream's") records that RMSC's batch job gets reclassified into the
# PASE worker job partway through its life, where upstream's never is - and
# that, as a SEPARATE side effect of that same reclassification, staging
# this exact fixture against upstream can show TWO EXTRA, always-empty,
# perpetually-OPEN `QPRINT` placeholder entries that RMSC's side never
# produces. That is real, reproducible, and not what this file is about - so
# the assertions below are written to survive it either way:
#
#   RMSC:      exactly one real spooled file, ever, in this fixture - so its
#              whole loginfo output is pinned byte-exact (job number and log
#              path normalised to placeholders, the same technique
#              loginfo-test.sh already uses for the log path alone).
#   upstream:  the QPDSPJOB line is required to be PRESENT, correctly
#              formatted, and before the log line; stderr must be empty.
#              Total line count and any extra QPRINT-named lines are NEITHER
#              asserted NOR forbidden - their presence or absence depends on
#              box state this file does not control, and asserting either
#              way would fail for a reason that has nothing to do with this
#              fix.
#
# WHAT ELSE IS DELIBERATELY NOT PINNED
#
#   THE JOB VALUE ITSELF. Which job loginfo names (a reclassified PASE worker
#   for RMSC, a genuine SC_<SHORTNAME>-named BATCH job for upstream) is the
#   subject of the parity.md finding above, not of this file. Both are
#   accepted as long as they are a plausible qualified job name
#   (NNNNNN/user/name) - matching the shape is enough to prove the FIELD is
#   right without re-litigating which job is right.
#
#   SPLNBR for upstream. Measured as 1 when QPDSPJOB is the only spooled file
#   on disk and as high as 3 when the two QPRINT placeholders precede it - so
#   it is read out of the actual line, never assumed.
#
#   INTERLEAVING WITH THE LOG LINE BEYOND "WHICH COMES FIRST". Nothing here
#   asks whether something else could sit between them.
#
# THE REGRESSION CONTROL
#
# An ORDINARY, non-batch service - no `batch_mode`, nothing that could
# produce a spooled file - mirroring tools/loginfo-test.sh's own fixture
# shape (a silent listener behind a port criterion). It exists to prove the
# fix this file is written against does not start inventing a spooled-file
# section for a service that has none; without it, a fix that always printed
# a (possibly empty) spooled-file block would satisfy every assertion above
# and still be wrong for every non-batch service in the fleet.
#
# STAGING, NAMING, CLEANUP - same discipline as loginfo-test.sh
#
# Both fixtures are staged in the REAL, shared services directory
# ($HOME/.sc/services) because that is the only place both implementations
# look; SC_SERVICES_DIR is RMSC's own mechanism and upstream would not see a
# definition staged through it. Names carry this script's PID so two runs
# cannot collide and debris is attributable; a marker comment line identifies
# what this script staged so the reaper never deletes a file it did not
# write. No client name, path, job name or host belongs in this file or in
# anything it prints - every name below is invented.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/rmsc-loginfo-splf.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the same block every script here
# that keeps a PID-named work directory carries. See loginfo-test.sh's own
# copy for the full reasoning; duplicated rather than shared on purpose.
ls -dt /tmp/rmsc-loginfo-splf.* 2>/dev/null | tail -n +3 | while read -r stale; do
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

export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud - a skipped case reports
# success while testing nothing.
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
  "Upstream is not optional here - it is one of the two implementations" \
  "being measured, not a bystander. Set SC=<path> if installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "Both fixtures' start_cmd ends by exec-ing into a silent python listener." \
  "Set PY=<path> if python3 lives elsewhere."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py"

SVCDIR="$HOME/.sc/services"
[ -d "$SVCDIR" ] || setup_fail \
  "no services directory at: $SVCDIR" \
  "" \
  "The fixtures have to be visible to BOTH implementations, and this is the" \
  "only place both look."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

SPLF="rmsc_splf_$$"       # batch_mode, the spooled-file fixture
CTRL="rmsc_splfctrl_$$"   # ordinary, non-batch - the regression control
PORT_SPLF=59497
PORT_CTRL=59498

MARKER='# staged by tools/loginfo-splf-test.sh - a test fixture, safe to remove'

for n in "$SPLF" "$CTRL"; do
  [ -e "$SVCDIR/$n.yaml" ] && setup_fail \
    "$SVCDIR/$n.yaml already exists." \
    "" \
    "This harness invents that name from its own PID and will not overwrite" \
    "a file it did not write. Remove it if it is debris from a killed run."
done

# PORTS MUST BE FREE BEFORE STAGING. A listener that silently failed to bind
# would leave the fixture reporting NOT RUNNING and the whole run would
# measure nothing - see tools/gate-fixtures/README.md's own warning about
# exactly this.
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
for p in "$PORT_SPLF" "$PORT_CTRL"; do
  port_free "$p" || setup_fail "port $p is already in use - pick a different one or wait"
done

# Job ids seen along the way, cleaned up (best effort) on the way out.
CLEANUP_JOBS=()
LOGDIR=""

# TEARDOWN. Staged definitions live in the real services directory, so
# leaving one behind would change what every other harness and the fidelity
# gate see - not merely leak a temp file. Spooled-file cleanup is best
# effort: DLTSPLF has been observed to warn CPD000D ("not safe for a
# multithreaded job") from an interactive PASE session while the job's
# output still ends up gone, and a spooled file left on a shared box is
# untidy, not a hazard - so a failure here is never fatal to the run.
teardown() {
  local rc=$?
  "$SCR" stop "$SPLF" >/dev/null 2>&1 </dev/null
  "$SC"  stop "$SPLF" >/dev/null 2>&1 </dev/null
  "$SCR" stop "$CTRL" >/dev/null 2>&1 </dev/null
  pkill -f "gate-listen.py.*$PORT_SPLF" >/dev/null 2>&1
  pkill -f "gate-listen.py.*$PORT_CTRL" >/dev/null 2>&1
  rm -f "$SVCDIR/$SPLF.yaml" "$SVCDIR/$CTRL.yaml"
  if [ -n "$LOGDIR" ] && [ -d "$LOGDIR" ]; then
    rm -f "$LOGDIR"/*."$SPLF".log "$LOGDIR"/*."$CTRL".log
  fi
  local j
  for j in "${CLEANUP_JOBS[@]}"; do
    [ -n "$j" ] || continue
    cl -sk "DLTSPLF FILE(QPDSPJOB) JOB($j) SPLNBR(1)" >/dev/null 2>&1
  done
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"

  # TEARDOWN PROVES ITSELF - see loginfo-test.sh for the full reasoning. A
  # definition that survived teardown is an extra row in the fidelity gate's
  # byte-exact check/list/groups surface, and it would fail looking like a
  # formatting regression rather than naming this script's own leak.
  local listing left
  listing=$("$SCR" list 2>/dev/null </dev/null)
  left=$(printf '%s\n' "$listing" | grep -cE "^($SPLF|$CTRL) " || true)
  [ -z "$left" ] && left=0
  if [ "$left" -ne 0 ]; then
    echo
    echo "TEARDOWN FAILED: $left of this run's own fixture definition(s) are" >&2
    echo "still visible to '$SCR list'." >&2
    printf '%s\n' "$listing" | grep -E "^($SPLF|$CTRL) " | sed 's/^/  /' >&2
    echo "Remove them from $SVCDIR before running the fidelity gate." >&2
    exit 3
  fi
  return $rc
}
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

# Reap debris from a run killed before its trap could fire.
for stale in "$SVCDIR"/rmsc_splf_*.yaml "$SVCDIR"/rmsc_splfctrl_*.yaml; do
  [ -e "$stale" ] || continue
  base="${stale##*/}"; base="${base%.yaml}"
  owner="${base##*_}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  [ "$owner" = "$$" ] && continue
  grep -Fq -- "$MARKER" "$stale" 2>/dev/null || continue
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  "$SCR" stop "$base" >/dev/null 2>&1 </dev/null
  "$SC"  stop "$base" >/dev/null 2>&1 </dev/null
  rm -f "$stale"
done

pass=0; failed=0; refdrift=0

report() { local verdict="$1" tag="$2"; shift 2; printf '  %-9s %-20s %s\n' "$verdict" "$tag" "$*"; }
detail() { printf '  %-9s %-20s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-20s %s\n' verdict case detail
  printf '  %-9s %-20s %s\n' --------- -------------------- ------
}
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

# A plausible qualified job name: NNNNNN/user/name. Not pinned as any
# PARTICULAR job - see header, "what else is deliberately not pinned".
JOB_RE='[0-9]{6}/[A-Za-z0-9$#@_.-]+/[A-Za-z0-9$#@_.-]+'

printf 'loginfo: the spooled-file section for a batch service - wording, order, suppression\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'fixtures: %s (batch_mode, one real QPDSPJOB spooled file), %s (ordinary, no spooled files)\n\n' "$SPLF" "$CTRL"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixtures stage, both implementations agree on the log directory"
echo
heading
# ---------------------------------------------------------------------------

# THE SPLF DEFINITION. The quoting here is exactly the recipe confirmed
# working live: `cl -sk "DSPJOB OUTPUT(*PRINT)"` inside a double-quoted
# `bash -c` argument. This heredoc is UNQUOTED (so $PY/$HERE/$PORT_SPLF
# expand), and unquoted heredocs do not treat `\"` specially - it passes
# through byte for byte, which is what the YAML needs to carry.
cat > "$SVCDIR/$SPLF.yaml" <<EOF
$MARKER
name: RMSC loginfo spooled-file fixture $SPLF
start_cmd: /QOpenSys/pkgs/bin/bash -c "cl -sk \"DSPJOB OUTPUT(*PRINT)\" ; exec $PY $HERE/gate-listen.py --seconds 90 $PORT_SPLF"
check_alive: $PORT_SPLF
batch_mode: true
startup_wait_time: 20
stop_wait_time: 10
EOF

# THE CONTROL DEFINITION. Ordinary, non-batch, mirrors loginfo-test.sh's own
# RUN fixture shape (a listener behind a port criterion) - nothing here can
# ever produce a spooled file.
cat > "$SVCDIR/$CTRL.yaml" <<EOF
$MARKER
name: RMSC loginfo spooled-file regression control $CTRL
start_cmd: $PY $HERE/gate-listen.py --seconds 60 $PORT_CTRL
check_alive: $PORT_CTRL
startup_wait_time: 20
stop_wait_time: 5
EOF

# (a) BOTH DEFINITIONS LOAD, AND NEITHER IS ALREADY RUNNING.
fx=()
for pair in "$SPLF:$PORT_SPLF" "$CTRL:$PORT_CTRL"; do
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
  echo; echo "pass=$pass   failed=$failed   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
report PASS fixture-definitions "both staged definitions load and neither is running"
pass=$((pass+1))

# (b) THE LOG DIRECTORY, DISCOVERED FROM BOTH IMPLEMENTATIONS - via the
# not-found line on the control service, which is defined but not yet
# started (case C in loginfo-test.sh's vocabulary).
"$SC"  loginfo "$CTRL" > "$WORK/dir.sc.out"  2> "$WORK/dir.sc.err"  </dev/null
"$SCR" loginfo "$CTRL" > "$WORK/dir.scr.out" 2> "$WORK/dir.scr.err" </dev/null
dir_of() { cat "$@" 2>/dev/null | grep -F -- 'try checking in log directory' \
             | sed -e 's/.*try checking in log directory //' -e 's/)[[:space:]]*$//' | head -n 1; }
SC_LOGDIR=$(dir_of "$WORK/dir.sc.out" "$WORK/dir.sc.err")
SCR_LOGDIR=$(dir_of "$WORK/dir.scr.out" "$WORK/dir.scr.err")

if [ -z "$SC_LOGDIR" ] || [ -z "$SCR_LOGDIR" ] || [ "$SC_LOGDIR" != "$SCR_LOGDIR" ]; then
  report FAIL fixture-logdir "the two implementations do not agree on a log directory"
  detail "sc:  '${SC_LOGDIR:-<nothing found>}'"
  detail "scr: '${SCR_LOGDIR:-<nothing found>}'"
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
LOGDIR="$SC_LOGDIR"
report PASS fixture-logdir "both name the same log directory"
pass=$((pass+1))

wait_for_status() {  # bin name want seconds -> prints final status
  local bin="$1" name="$2" want="$3" secs="$4" st=""
  local i
  for ((i=0; i<secs; i++)); do
    st=$("$SCR" check "$name" 2>/dev/null </dev/null | grep -F -- "$name" | sed 's/ *|.*//; s/^ *//')
    [ "$st" = "$want" ] && break
    sleep 1
  done
  printf '%s' "$st"
}

newest_log() { ls -1t "$LOGDIR"/*."$1".log 2>/dev/null | head -n 1; }

echo
# ---------------------------------------------------------------------------
echo "== stage 1: RMSC (scr) against the current, unmodified build"
echo
heading
# ---------------------------------------------------------------------------

"$SCR" start "$SPLF" > "$WORK/scr.start.out" 2> "$WORK/scr.start.err" </dev/null
scr_st=$(wait_for_status "$SCR" "$SPLF" RUNNING 30)
if [ "$scr_st" != RUNNING ]; then
  report FAIL fixture-start-scr "scr start left $SPLF '$scr_st' after 30s, wanted RUNNING"
  detail "it said: $(head -n 1 "$WORK/scr.start.err" 2>/dev/null)"
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
report PASS fixture-start-scr "started by scr, RUNNING after the wait"
pass=$((pass+1))

SCR_LOG=$(newest_log "$SPLF")
"$SCR" loginfo "$SPLF" > "$WORK/scr.loginfo.out" 2> "$WORK/scr.loginfo.err" </dev/null
scr_rc=$?

# FIXTURE VALIDITY, before trusting anything about WORDING. If neither the
# old nor the new spelling of a spooled-file line appears at all, the
# cl -sk DSPJOB staging step did not take - that is a FIXTURE problem, not
# the defect this file exists to pin, and reporting it as a format mismatch
# would send the next reader looking in the wrong place.
if ! grep -Eq 'QPDSPJOB' "$WORK/scr.loginfo.out"; then
  report FAIL fixture-splf-scr "FIXTURE: scr loginfo never mentions QPDSPJOB at all"
  detail "stdout: $(cat "$WORK/scr.loginfo.out")"
  detail "the cl -sk DSPJOB staging step did not leave a spooled file RMSC can see"
  failed=$((failed+1))
else
  report PASS fixture-splf-scr "the staged spooled file is visible to scr loginfo in some form"
  pass=$((pass+1))

  # Extract the job however it is currently spelled, for cleanup and for
  # building the normalised comparison below.
  scr_job=$(grep -oE "$JOB_RE" "$WORK/scr.loginfo.out" | head -n 1)
  [ -n "$scr_job" ] && CLEANUP_JOBS+=("$scr_job")

  o="$WORK/scr.loginfo.out"; e="$WORK/scr.loginfo.err"
  problems=()

  [ "$scr_rc" -eq 0 ] || problems+=("exit $scr_rc, wanted 0")
  [ -s "$e" ] && problems+=("stderr is not empty: $(head -n 1 "$e")")

  nblank=$(grep -c '^$' "$o" || true); [ -z "$nblank" ] && nblank=0
  [ "$nblank" -eq 1 ] || problems+=("$nblank blank line(s) on stdout, wanted exactly one")
  last=$(tail -n 1 "$o"); [ -z "$last" ] || problems+=("the last stdout line is not blank: '$last'")

  dspsplf_line=$(grep -nE "^${SPLF}: DSPSPLF FILE\(QPDSPJOB\) JOB\(${JOB_RE}\) SPLNBR\(1\)\$" "$o" | head -n 1)
  log_line=$(grep -nF -- "$SCR_LOG" "$o" | head -n 1)
  spool_any_line=$(grep -nE '^([[:space:]]+spooled file QPDSPJOB|'"${SPLF}"': DSPSPLF FILE\(QPDSPJOB\))' "$o" | head -n 1)

  if [ -z "$dspsplf_line" ]; then
    got=$(grep -E '^([[:space:]]+spooled file|'"${SPLF}"': DSPSPLF)' "$o" | head -n 1)
    problems+=("WORDING/SHAPE: spooled-file line reads '${got:-<none found>}', wanted '${SPLF}: DSPSPLF FILE(QPDSPJOB) JOB(<job>) SPLNBR(1)'")
  fi

  if [ -z "$log_line" ]; then
    problems+=("the log line naming $SCR_LOG is missing from stdout entirely")
  elif [ -n "$dspsplf_line" ]; then
    dn="${dspsplf_line%%:*}"; ln="${log_line%%:*}"
    [ "$dn" -lt "$ln" ] || problems+=("ORDER: the log line (row $ln) is not after the spooled-file line (row $dn) - upstream prints the spooled-file section FIRST")
  elif [ -n "$spool_any_line" ]; then
    sn="${spool_any_line%%:*}"; ln="${log_line%%:*}"
    if [ "$sn" -gt "$ln" ]; then
      problems+=("ORDER: the log line (row $ln) comes BEFORE the spooled-file line (row $sn) - upstream prints the spooled-file section first")
    fi
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS splf-rmsc "(measured) wording, order and suppression all match the fixed target"
    pass=$((pass+1))
  else
    report FAIL splf-rmsc "(measured) RMSC's spooled-file section does not match upstream's shape"
    for p in "${problems[@]}"; do detail "$p"; done
    detail "artefacts: scr.loginfo.out scr.loginfo.err"
    failed=$((failed+1))
  fi
fi

"$SCR" stop "$SPLF" > "$WORK/scr.stop.out" 2> "$WORK/scr.stop.err" </dev/null
wait_for_status "$SCR" "$SPLF" 'NOT RUNNING' 15 >/dev/null

echo
# ---------------------------------------------------------------------------
echo "== stage 2: upstream (sc) reference, re-taken live rather than trusted"
echo
heading
# ---------------------------------------------------------------------------

"$SC" start "$SPLF" > "$WORK/sc.start.out" 2> "$WORK/sc.start.err" </dev/null
sc_st=$(wait_for_status "$SC" "$SPLF" RUNNING 30)
if [ "$sc_st" != RUNNING ]; then
  report FAIL fixture-start-sc "sc start left $SPLF '$sc_st' after 30s, wanted RUNNING"
  detail "it said: $(head -n 1 "$WORK/sc.start.err" 2>/dev/null)"
  failed=$((failed+1))
else
  report PASS fixture-start-sc "started by sc, RUNNING after the wait"
  pass=$((pass+1))

  SC_LOG=$(newest_log "$SPLF")
  "$SC" loginfo "$SPLF" > "$WORK/sc.loginfo.out" 2> "$WORK/sc.loginfo.err" </dev/null
  sc_rc=$?

  if ! grep -Eq 'QPDSPJOB' "$WORK/sc.loginfo.out"; then
    report FAIL fixture-splf-sc "FIXTURE: sc loginfo never mentions QPDSPJOB at all"
    detail "stdout: $(cat "$WORK/sc.loginfo.out")"
    detail "either the recipe no longer stages a real spooled file for upstream, or upstream's own behaviour moved - re-check by hand before trusting this as REFDRIFT"
    failed=$((failed+1))
  else
    report PASS fixture-splf-sc "the staged spooled file is visible to sc loginfo"
    pass=$((pass+1))

    sc_job=$(grep -oE "$JOB_RE" "$WORK/sc.loginfo.out" | head -n 1)
    [ -n "$sc_job" ] && CLEANUP_JOBS+=("$sc_job")

    o="$WORK/sc.loginfo.out"; e="$WORK/sc.loginfo.err"
    why=""

    [ "$sc_rc" -eq 0 ] || why="$why exit=$sc_rc(wanted 0)"
    [ -s "$e" ] && why="$why stderr-not-empty='$(head -n 1 "$e")'"

    last=$(tail -n 1 "$o"); [ -z "$last" ] || why="$why last-line-not-blank='$last'"

    # The QPDSPJOB-specific line - any SPLNBR, see header ("SPLNBR for
    # upstream" - 1 when it is the only spooled file, higher when the two
    # QPRINT placeholders precede it).
    dspsplf_line=$(grep -nE "^${SPLF}: DSPSPLF FILE\(QPDSPJOB\) JOB\(${JOB_RE}\) SPLNBR\([0-9]+\)\$" "$o" | head -n 1)
    log_line=$(grep -nF -- "$SC_LOG" "$o" | head -n 1)

    if [ -z "$dspsplf_line" ]; then
      why="$why no-QPDSPJOB-line-matching-expected-shape"
    fi
    if [ -z "$log_line" ]; then
      why="$why log-line-missing"
    elif [ -n "$dspsplf_line" ]; then
      dn="${dspsplf_line%%:*}"; ln="${log_line%%:*}"
      [ "$dn" -lt "$ln" ] || why="$why order-wrong(QPDSPJOB-row=$dn,log-row=$ln)"
    fi

    if [ -z "$why" ]; then
      report PASS splf-upstream "the QPDSPJOB line is present, correctly formatted, before the log line; stderr is empty"
      pass=$((pass+1))
    else
      report REFDRIFT splf-upstream "$why"
      detail "a REFDRIFT here means upstream's live behaviour no longer matches what was measured for this brief - re-check by hand before trusting RMSC's target"
      detail "artefacts: sc.loginfo.out sc.loginfo.err"
      refdrift=$((refdrift+1))
    fi

    # Explicitly NOT asserted: total stdout line count, and whether extra
    # QPRINT-named lines appear. See header - that depends on box state this
    # file does not control and is a separate, already-recorded finding.
    qprint_n=$(grep -cE "FILE\(QPRINT\)" "$o" || true); [ -z "$qprint_n" ] && qprint_n=0
    if [ "$qprint_n" -gt 0 ]; then
      report NOTE splf-upstream-qprint "$qprint_n extra QPRINT placeholder line(s) seen - expected sometimes, tolerated always, not asserted"
    fi
  fi

  "$SC" stop "$SPLF" > "$WORK/sc.stop.out" 2> "$WORK/sc.stop.err" </dev/null
  wait_for_status "$SCR" "$SPLF" 'NOT RUNNING' 15 >/dev/null
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 3: regression control - an ordinary service invents no spooled-file lines"
echo
heading
# ---------------------------------------------------------------------------

"$SCR" start "$CTRL" > "$WORK/ctrl.start.out" 2> "$WORK/ctrl.start.err" </dev/null
ctrl_st=$(wait_for_status "$SCR" "$CTRL" RUNNING 30)
if [ "$ctrl_st" != RUNNING ]; then
  report FAIL fixture-start-ctrl "scr start left $CTRL '$ctrl_st' after 30s, wanted RUNNING"
  detail "it said: $(head -n 1 "$WORK/ctrl.start.err" 2>/dev/null)"
  failed=$((failed+1))
else
  report PASS fixture-start-ctrl "the control started, RUNNING after the wait"
  pass=$((pass+1))

  "$SCR" loginfo "$CTRL" > "$WORK/ctrl.loginfo.out" 2> "$WORK/ctrl.loginfo.err" </dev/null
  ctrl_rc=$?
  o="$WORK/ctrl.loginfo.out"; e="$WORK/ctrl.loginfo.err"
  cproblems=()

  [ "$ctrl_rc" -eq 0 ] || cproblems+=("exit $ctrl_rc, wanted 0")
  if grep -Eq 'spooled file|DSPSPLF|QPDSPJOB|QPRINT' "$o" "$e" 2>/dev/null; then
    cproblems+=("a spooled-file line was invented for a service with no spooled files: $(grep -E 'spooled file|DSPSPLF|QPDSPJOB|QPRINT' "$o" "$e" | head -n 1)")
  fi

  if [ ${#cproblems[@]} -eq 0 ]; then
    report PASS control "no spooled-file line appears for an ordinary service - the fix does not over-fire"
    pass=$((pass+1))
  else
    report FAIL control "the fix invents spooled-file content where none exists"
    for p in "${cproblems[@]}"; do detail "$p"; done
    detail "artefacts: ctrl.loginfo.out ctrl.loginfo.err"
    failed=$((failed+1))
  fi

  "$SCR" stop "$CTRL" > "$WORK/ctrl.stop.out" 2> "$WORK/ctrl.stop.err" </dev/null
  wait_for_status "$SCR" "$CTRL" 'NOT RUNNING' 15 >/dev/null
fi

echo
echo "pass=$pass   failed=$failed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and why
#
#   WHICH JOB IS NAMED. See "what else is deliberately not pinned" above -
#   that is docs/parity.md's own open, bigger finding, not this file's.
#
#   TOTAL LINE COUNT OR EXTRA QPRINT LINES ON UPSTREAM'S SIDE. Same section.
#
#   INTERLEAVING BEYOND "WHICH SECTION COMES FIRST". Streams are captured
#   whole (not interleaved with each other - stderr is checked only for
#   emptiness/non-emptiness here, never for ordering against stdout).
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: see the named reasons above"
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer behaves as recorded in this file's header."
  echo "Re-take the measurement by hand before trusting RMSC's target against it."
  exit 1
fi
echo "OK: the spooled-file section reads, and is ordered, the way upstream's is"
