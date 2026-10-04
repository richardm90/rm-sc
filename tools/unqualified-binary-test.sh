#!/QOpenSys/pkgs/bin/bash
#
# unqualified-binary-test.sh - a `start_cmd` that names a PASE-package binary
# by its bare name (e.g. `python3`), not its full path (e.g.
# `/QOpenSys/pkgs/bin/python3`), must still start - measured, it did not,
# for a non-batch service, before this round of work.
#
# Runs ON the IBM i box, beside tools/job-identity-test.sh and the other
# harnesses.
#
# WHY A NEW FILE, AND WHY IT IS SEPARATE FROM tools/job-identity-test.sh.
# This is a different, SEPARATE bug from the job-identity one, found in the
# same investigation but with a different mechanism and a different fix
# surface: RMSC's old non-batch path ran `start_cmd` directly through
# PASE_run_cmd's spawn() call, under a shell whose PATH does not include
# `/QOpenSys/pkgs/bin` - so a bare `python3` (or any other PASE-package
# binary named without its full path) was never found, and the service
# failed to start outright. Upstream never has this problem, because it
# always execs via `bash`, which does have that PATH by default. The fix for
# this round of work happens to carry the same benefit as a side effect: the
# new non-batch path execs via RMSC_FORK_HELPER's own `bash -c`, which
# inherits bash's wider PATH.
#
# WHAT IS ASSERTED, AND WHY IT IS THE SERVICE'S OWN CONFIRMATION OF BEING
# ALIVE, NOT MERELY "A JOB WAS SUBMITTED WITHOUT ERROR". SBMJOB and
# PASE_run_cmd alike can report success for a command that goes on to fail
# immediately once actually running - a bare binary that cannot be found is
# exactly that shape of failure, so the only assertion worth making is
# whether `check_alive`'s own port criterion ever reports RUNNING. A fixture
# that only checked the start command's own exit status would pass under the
# very defect this file exists to catch.
#
# THREE FIXTURES, NOT ONE:
#
#   bare (non-batch)     start_cmd names python3 by its bare name. THE CASE
#                        THIS FILE EXISTS FOR - measured broken before this
#                        round of work, on the non-batch path specifically.
#
#   qualified (non-batch) THE REGRESSION CONTROL. Identical in every other
#                        respect, but start_cmd names python3 by its full
#                        path. It exists to rule out "the harness itself is
#                        broken" (a dead port-polling loop, a bad PY path,
#                        a port already in use) as the explanation for a
#                        failure on the bare fixture - without it, a FAIL on
#                        bare proves nothing specific.
#
#   bare (batch_mode)    THE SAME BARE NAME, but batch_mode: true. Included
#                        for coverage since the fix's SBMJOB command also now
#                        execs via bash (CALL PGM(QP2SHELL2) PARM('.../bash'
#                        '-c' ...)) - but whether the OLD batch path (SBMJOB
#                        CMD(QSH CMD(...))) had this same bug was never
#                        actually measured for this round of work (QSH's own
#                        default PATH was not checked), so this fixture is
#                        coverage for the FIX, not a confirmed regression
#                        case for the defect - see the note printed with its
#                        result.
#
# UPSTREAM IS RUN FIRST ON THE BARE FIXTURE, as a fixture-validity check in
# the same spirit as tools/sbmjob-opts-test.sh's "upstream first - if it
# cannot be measured, RMSC's row is not evidence either": if upstream itself
# cannot start a bare `python3`, this fixture is not exercising the bug this
# file is about, and RMSC's own result is not meaningful evidence either way.
#
# STAGING, NAMING, CLEANUP - same discipline as every sibling harness here.
# Fixtures are staged in the REAL, shared services directory
# ($HOME/.sc/services) because that is the only place both implementations
# look. Names carry this script's PID so two runs cannot collide and debris
# is attributable. No client name, path, job name or host belongs in this
# file or in anything it prints - every name below is invented.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/rmsc-unqualified-bin.$$}"

ls -dt /tmp/rmsc-unqualified-bin.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
  "Upstream runs the bare fixture FIRST, as a fixture-validity check - see" \
  "this script's own header."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "Needed to resolve the full path the qualified-path control fixture uses" \
  "(the bare fixtures deliberately do NOT use \$PY - they name python3 by" \
  "its bare name, which is the whole point)."

[ -f "$HERE/gate-listen.py" ] || setup_fail \
  "tools/gate-listen.py not found beside this script at: $HERE/gate-listen.py"

SVCDIR="$HOME/.sc/services"
[ -d "$SVCDIR" ] || setup_fail \
  "no services directory at: $SVCDIR" \
  "" \
  "The fixtures have to be visible to BOTH implementations, and this is the" \
  "only place both look."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

SVC_BARE_NB="rmsc_unqbin_nb_$$"
SVC_QUAL_NB="rmsc_unqbin_q_$$"
SVC_BARE_B="rmsc_unqbin_b_$$"
PORT_BARE_NB=59501
PORT_QUAL_NB=59502
PORT_BARE_B=59503

MARKER='# staged by tools/unqualified-binary-test.sh - a test fixture, safe to remove'

for n in "$SVC_BARE_NB" "$SVC_QUAL_NB" "$SVC_BARE_B"; do
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
for p in "$PORT_BARE_NB" "$PORT_QUAL_NB" "$PORT_BARE_B"; do
  port_free "$p" || setup_fail "port $p is already in use - pick a different one or wait"
done

teardown() {
  local rc=$?
  for s in "$SVC_BARE_NB" "$SVC_QUAL_NB" "$SVC_BARE_B"; do
    "$SCR" stop "$s" >/dev/null 2>&1 </dev/null
    "$SC"  stop "$s" >/dev/null 2>&1 </dev/null
  done
  pkill -f "gate-listen.py.*$PORT_BARE_NB" >/dev/null 2>&1
  pkill -f "gate-listen.py.*$PORT_QUAL_NB" >/dev/null 2>&1
  pkill -f "gate-listen.py.*$PORT_BARE_B"  >/dev/null 2>&1
  rm -f "$SVCDIR/$SVC_BARE_NB.yaml" "$SVCDIR/$SVC_QUAL_NB.yaml" "$SVCDIR/$SVC_BARE_B.yaml"
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"

  local listing left
  listing=$("$SCR" list 2>/dev/null </dev/null)
  left=$(printf '%s\n' "$listing" | grep -cE "^($SVC_BARE_NB|$SVC_QUAL_NB|$SVC_BARE_B) " || true)
  [ -z "$left" ] && left=0
  if [ "$left" -ne 0 ]; then
    echo
    echo "TEARDOWN FAILED: $left of this run's own fixture definition(s) are" >&2
    echo "still visible to '$SCR list'." >&2
    printf '%s\n' "$listing" | grep -E "^($SVC_BARE_NB|$SVC_QUAL_NB|$SVC_BARE_B) " | sed 's/^/  /' >&2
    echo "Remove them from $SVCDIR before running the fidelity gate." >&2
    exit 3
  fi
  return $rc
}
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

for stale in "$SVCDIR"/rmsc_unqbin_*.yaml; do
  [ -e "$stale" ] || continue
  grep -Fq -- "$MARKER" "$stale" 2>/dev/null || continue
  base="${stale##*/}"; base="${base%.yaml}"
  owner="${base##*_}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  [ "$owner" = "$$" ] && continue
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  "$SCR" stop "$base" >/dev/null 2>&1 </dev/null
  "$SC"  stop "$base" >/dev/null 2>&1 </dev/null
  rm -f "$stale"
done

pass=0; failed=0

report() { local verdict="$1" tag="$2"; shift 2; printf '  %-9s %-24s %s\n' "$verdict" "$tag" "$*"; }
detail() { printf '  %-9s %-24s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-24s %s\n' verdict case detail
  printf '  %-9s %-24s %s\n' --------- ------------------------ ------
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

# check_starts label bin svc timeout -> PASS/FAIL on reaching RUNNING
check_starts() {
  local label="$1" bin="$2" svc="$3" secs="$4" st
  "$bin" start "$svc" > "$WORK/$label.start.out" 2> "$WORK/$label.start.err" </dev/null
  st=$(wait_for_status "$bin" "$svc" RUNNING "$secs")
  if [ "$st" = RUNNING ]; then
    report PASS "$label" "RUNNING within ${secs}s - the service's own confirmation of being alive"
    pass=$((pass+1))
  else
    report FAIL "$label" "left '$svc' '$st' after ${secs}s, wanted RUNNING"
    detail "start said: $(head -n 1 "$WORK/$label.start.err" 2>/dev/null || true)"
    detail "a bare PASE-package binary name is not found under this path's" \
      "dispatch, or something else is wrong - artefacts: $label.start.*"
    failed=$((failed+1))
  fi
  "$bin" stop "$svc" >/dev/null 2>&1 </dev/null
  wait_for_status "$bin" "$svc" 'NOT RUNNING' 15 >/dev/null
  [ "$st" = RUNNING ]
}

printf 'unqualified-binary: does a bare PASE-package binary name in start_cmd actually start?\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'fixtures: %s (non-batch, bare), %s (non-batch, qualified - control), %s (batch_mode, bare)\n\n' \
  "$SVC_BARE_NB" "$SVC_QUAL_NB" "$SVC_BARE_B"

echo "== stage 0: the fixtures"
echo
cat > "$SVCDIR/$SVC_BARE_NB.yaml" <<EOF
$MARKER
name: RMSC unqualified-binary fixture $SVC_BARE_NB (non-batch, bare python3)
start_cmd: python3 $HERE/gate-listen.py --seconds 45 $PORT_BARE_NB
check_alive: $PORT_BARE_NB
startup_wait_time: 20
stop_wait_time: 5
EOF
cat > "$SVCDIR/$SVC_QUAL_NB.yaml" <<EOF
$MARKER
name: RMSC unqualified-binary REGRESSION CONTROL $SVC_QUAL_NB (non-batch, full path)
start_cmd: $PY $HERE/gate-listen.py --seconds 45 $PORT_QUAL_NB
check_alive: $PORT_QUAL_NB
startup_wait_time: 20
stop_wait_time: 5
EOF
cat > "$SVCDIR/$SVC_BARE_B.yaml" <<EOF
$MARKER
name: RMSC unqualified-binary fixture $SVC_BARE_B (batch_mode, bare python3)
start_cmd: python3 $HERE/gate-listen.py --seconds 45 $PORT_BARE_B
check_alive: $PORT_BARE_B
batch_mode: true
startup_wait_time: 25
stop_wait_time: 10
EOF

fx=()
for pair in "$SVC_BARE_NB:$PORT_BARE_NB" "$SVC_QUAL_NB:$PORT_QUAL_NB" "$SVC_BARE_B:$PORT_BARE_B"; do
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
report PASS fixture-definitions "all three staged definitions load and none is running"
pass=$((pass+1))

echo
echo "== stage 1: upstream, on the bare non-batch fixture - a fixture-validity check, not the thing under test"
echo
heading
if check_starts sc-bare-nonbatch "$SC" "$SVC_BARE_NB" 25; then
  sc_bare_ok=1
else
  sc_bare_ok=0
  detail "upstream itself could not start a bare python3 - this fixture is" \
    "not exercising the bug this file is about; re-check PATH/python3" \
    "availability before trusting anything below as evidence either way"
fi

echo
echo "== stage 2: RMSC, non-batch - THE CASE THIS FILE EXISTS FOR"
echo
heading
check_starts scr-bare-nonbatch "$SCR" "$SVC_BARE_NB" 25

echo
echo "== stage 3: RMSC, non-batch, qualified path - THE REGRESSION CONTROL"
echo
heading
check_starts scr-qualified-nonbatch "$SCR" "$SVC_QUAL_NB" 25
detail "if this one fails, suspect the harness (port, gate-listen.py, the" \
  "polling loop) before suspecting the unqualified-binary fix - it proves" \
  "nothing about bare names"

echo
echo "== stage 4: RMSC, batch_mode, bare python3 - coverage for the fix, not a confirmed pre-fix regression case (see header)"
echo
heading
check_starts scr-bare-batch "$SCR" "$SVC_BARE_B" 30

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (.out/.err captured separately for every case; KEEP=1 to keep them)"

if [ "$sc_bare_ok" -eq 0 ]; then
  echo "FIXTURE PROBLEM: upstream could not start the bare fixture either - see stage 1"
  exit 2
fi
if [ "$failed" -ne 0 ]; then
  echo "FAILED: see the named reasons above"
  exit 1
fi
echo "OK: a bare PASE-package binary name in start_cmd starts successfully"
