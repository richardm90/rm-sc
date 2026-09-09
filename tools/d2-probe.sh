#!/QOpenSys/pkgs/bin/bash
#
# d2-probe.sh - capture upstream's exact text for every message docs/messages.md
# marks `unmeasured`.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and error-delivery-test.sh
# and in the same style. It ASSERTS NOTHING. Its whole job is to put upstream's
# bytes on the screen so a person can paste them into docs/messages.md and move
# a row from `unmeasured` to `measured`. A probe that graded itself would need
# an expectation, and the expectation is the thing that does not exist yet.
#
# WHY A SEPARATE SCRIPT
#
# The wording differences were being found one at a time, each in the middle of
# some other piece of work. Every such finding cost a round of staging - a work
# directory, a definition, an invocation - that the next finding then paid for
# again. This pays it once.
#
# WHAT IT DOES NOT DO BY DEFAULT
#
# Nothing state-changing. The narration family (`Performing operation ...`,
# `successfully started`, `is already running`) can only be observed by starting
# and stopping something, so those cases are behind --narrate and stage their own
# service: a definition this script writes, in a group it invents, whose start
# command is a bounded `sleep`. Nothing on the system is touched.
#
# NO SERVICE NAME FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The repository is
# public. Where a probe needs a real running service it DISCOVERS one from
# `sc check` at run time.
#
# Usage:
#   tools/d2-probe.sh                 read-only cases
#   tools/d2-probe.sh --narrate       adds the start/stop cases
#   SC=/path/to/sc tools/d2-probe.sh  override the upstream binary

set -u

SC="${SC:-/QOpenSys/pkgs/bin/sc}"
WORK="${WORK:-$HOME/d2-probe.$$}"
NARRATE=0
[ "${1:-}" = "--narrate" ] && NARRATE=1

[ -x "$SC" ] || { echo "d2-probe: no upstream sc at $SC (set SC=<path>)" >&2; exit 2; }

# Clean up on entry as well as exit: a trap does not run if the process is
# killed, so assume the last run left something.
#
# Removing the work directory is not enough. The narration cases START services,
# and a started listener outlives the directory its definition came from - it
# holds its port until its own sleep expires. The next run then fails to bind,
# the fixture reports NOT RUNNING, and the capture is of a service that never
# came up. Killing by the work-directory path rather than by the script name
# means a listener belonging to some other work is left alone.
kill_listeners() {
  local d="$1" p
  for p in $(ps -ef 2>/dev/null | grep -F "$d/listen.py" | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
}
cleanup() { kill_listeners "$WORK"; rm -rf "$WORK"; }
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

# BEFORE $WORK IS CREATED, and skipping $WORK by name even so.
#
# The first version of this swept AFTER mkdir, and the glob matched $WORK
# itself - so the script deleted its own directory, announced it as debris from
# an earlier run, and then reported "stdout: empty / stderr: empty" for every
# single case. A probe that measures nothing and says upstream is silent is
# worse than one that crashes, and this one had no way to notice: it captures
# absence, and absence is what a missing directory produces.
for stale in "$HOME"/d2-probe.*; do
  [ -d "$stale" ] || continue
  [ "$stale" = "$WORK" ] && continue
  echo "d2-probe: removing debris from an earlier run: $stale"
  kill_listeners "$stale"
  rm -rf "$stale"
done

mkdir -p "$WORK/services" || exit 2

# A capture that cannot write is a capture that reports nothing. Prove the
# directory is usable before any case runs, rather than letting every one of
# them report an empty upstream.
if ! ( : > "$WORK/.writable" ) 2>/dev/null; then
  echo "d2-probe: cannot write to $WORK - refusing to report on captures that" >&2
  echo "d2-probe: would all come back empty" >&2
  exit 2
fi
rm -f "$WORK/.writable"

# Upstream announces JAVA_TOOL_OPTIONS on stderr, which would otherwise read as
# output from the command under test.
sc_() { JAVA_TOOL_OPTIONS="-Dservices.dir=$WORK/services" "$SC" "$@" \
          >"$WORK/o" 2>"$WORK/e.raw"; rc=$?
        grep -v 'Picked up' "$WORK/e.raw" > "$WORK/e"; return $rc; }

# Every capture is shown with `cat -A` and the trailing $ stripped, so a trailing
# space or a tab is visible. A blank line matters here: three of the open
# questions in docs/messages.md are about how many there are.
show() { sed 's/\$$//' | cat -n | sed 's/^/    /'; }

probe() {
  local label="$1"; shift
  echo
  echo "=============================================================="
  echo "== $label"
  echo "==   \$ sc $*"
  sc_ "$@"; local rc=$?
  echo "== exit $rc"
  if [ -s "$WORK/o" ]; then echo "== stdout"; cat -A "$WORK/o" | show; else echo "== stdout: empty"; fi
  if [ -s "$WORK/e" ]; then echo "== stderr"; cat -A "$WORK/e" | show; else echo "== stderr: empty"; fi
}

echo "d2-probe: $SC"
echo "d2-probe: staging in $WORK (removed on exit)"

# --------------------------------------------------------------------------
# 1. The usage block, and whether stderr carries a prefix.
#
# docs/messages.md § "The two whole-surface differences" turns on this: RMSC
# writes `sc: <text>` and every upstream text captured so far is bare. `cat -A`
# is what settles it - a prefix is invisible in a summary and obvious in the
# bytes.
# --------------------------------------------------------------------------
probe "usage - no arguments at all"
probe "usage - unknown operation"          nosuchoperation
probe "usage - operation with no service"  info
probe "usage - -h"                         -h
probe "usage - --help"                     --help
probe "version"                            --version
probe "prefix - unknown service"           check rmsc_no_such_service_probe

# --------------------------------------------------------------------------
# 2. `info` labels for keys the box's own definitions do not use, and the
#    blank-line rhythm.
#
# local/baseline-operations.txt was taken through a capture script that writes
# its own blank lines around each command, so a blank next to a section boundary
# cannot be attributed. Run alone, every blank line below belongs to sc.
# --------------------------------------------------------------------------
cat > "$WORK/services/rmscd2_dep.yaml" <<'YEOF'
name: RMSC D2 dependency
start_cmd: /QOpenSys/pkgs/bin/sleep 30
check_alive: 65432
startup_wait_time: 5
stop_wait_time: 5
groups:
  - rmscd2
YEOF

cat > "$WORK/services/rmscd2_labels.yaml" <<'YEOF'
name: RMSC D2 labels
start_cmd: /QOpenSys/pkgs/bin/sleep 30
check_alive: 65433
startup_wait_time: 5
stop_wait_time: 5
service_dependencies:
  - rmscd2_dep
groups:
  - rmscd2
  - rmscd2_second
environment_vars:
  - RMSC_D2_PROBE=1
environment_is_inheriting_vars: true
YEOF

probe "info - dependency, group and environment labels" info rmscd2_labels
probe "info - a minimal definition, for the defaults"   info rmscd2_dep

# --------------------------------------------------------------------------
# 3. An empty group, and a group that does not exist.
#
# RMSC says `WARNING: No services are found in group '<g>'`. What upstream says,
# and on which stream, is unmeasured.
# --------------------------------------------------------------------------
probe "empty group - check"  check "group:rmsc_no_such_group_probe"
probe "empty group - list"   list  "group:rmsc_no_such_group_probe"

# --------------------------------------------------------------------------
# 4. The per-job operations, against a service that is genuinely running.
#
# Discovered rather than named, both because the repository is public and
# because a hardcoded name is coverage that leaves when the service does. If
# nothing is running these are skipped and SAY SO - a probe that silently
# captured nothing would look like a service with no jobs.
# --------------------------------------------------------------------------
RUNNING=$("$SC" check 2>/dev/null | awk -F'|' '/^  RUNNING /{print $2; exit}' \
          | sed 's/^ *//; s/ (.*//')

if [ -n "$RUNNING" ]; then
  echo; echo "d2-probe: per-job cases against the running service '$RUNNING'"
  probe "jobinfo"     jobinfo    "$RUNNING"
  # loginfo differs from RMSC by one TRAILING BLANK LINE, which is why this is
  # captured through `cat -A` like everything else: a summary cannot show it.
  probe "loginfo"     loginfo    "$RUNNING"
  probe "perfinfo"    perfinfo   "$RUNNING"
  # scrunattrs is NOT probed. docs/parity.md records RMSC's meaning of the verb
  # as a deliberate choice of the plan rather than a difference to close, so
  # upstream's text for it would be captured and then not used.
else
  echo
  echo "d2-probe: SKIPPED jobinfo/loginfo/perfinfo - nothing is"
  echo "d2-probe: running, so there would be no job to describe. These four"
  echo "d2-probe: three rows stay unmeasured; re-run when a service is up."
fi

# --------------------------------------------------------------------------
# 5. Narration. Opt-in, because it starts and stops something.
#
# The service is one this script writes, in a group it invents, running a
# bounded sleep. The sequence is chosen to reach every member of the family in
# docs/messages.md § Narration:
#
#   start   -> progress, outcome
#   start   -> the no-op form, while it is still up
#   stop    -> progress, outcome
#   stop    -> the no-op form, now that it is down
#   start on a definition with no start_cmd -> the refusal
#   kill  on a definition that is not running -> the other refusal
# --------------------------------------------------------------------------
if [ "$NARRATE" = 1 ]; then
  # THE SERVICE MUST ACTUALLY COME UP, or every case below captures the timeout
  # message and none of them captures the family this is here for. A bare
  # `sleep` with a port criterion can never satisfy that criterion, so the start
  # command binds the port it is checked on.
  cat > "$WORK/listen.py" <<'PEOF'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", int(sys.argv[1])))
s.listen(5)
time.sleep(300)
PEOF

  cat > "$WORK/services/rmscd2_narrate.yaml" <<YEOF
name: RMSC D2 narrate
start_cmd: /QOpenSys/pkgs/bin/python3 $WORK/listen.py 65434
check_alive: 65434
startup_wait_time: 15
stop_wait_time: 5
groups:
  - rmscd2
YEOF

  echo; echo "d2-probe: narration cases - this STARTS and STOPS a staged service"

  # PROVE THE SERVICE CAN COME UP before reading anything into the captures. If
  # it cannot - python missing, port taken - every case below still produces
  # output, and that output would be upstream's timeout wording captured under
  # the heading `successfully started`. A probe cannot detect that for itself;
  # this is the one place it has to look.
  sc_ start rmscd2_narrate
  sc_ check rmscd2_narrate
  if grep -q '^  RUNNING' "$WORK/o"; then
    echo "d2-probe: staged service is RUNNING - the captures below are the real family"
  else
    echo "d2-probe: *** WARNING: the staged service did not come up. ***"
    echo "d2-probe: *** The narration captures below will be upstream's TIMEOUT   ***"
    echo "d2-probe: *** wording, not its success wording. Do not paste them into  ***"
    echo "d2-probe: *** docs/messages.md as the outcome or no-op family.          ***"
    cat -A "$WORK/o" | show
  fi

  probe "narrate - start again, while it is up"   start   rmscd2_narrate
  probe "narrate - stop"                          stop    rmscd2_narrate
  probe "narrate - stop again, now that it is down" stop  rmscd2_narrate
  probe "narrate - kill, nothing running"         kill    rmscd2_narrate
  probe "narrate - start, from down"              start   rmscd2_narrate
  probe "narrate - restart"                       restart rmscd2_narrate
  probe "narrate - group start"                   start   "group:rmscd2"
  probe "narrate - group stop"                    stop    "group:rmscd2"

  # ------------------------------------------------------------------------
  # The four cases the implementation needs and the run above did not reach.
  #
  # Every one of them is a branch RMSC will have to take, and each would
  # otherwise be written from a guess about what upstream "probably" does:
  #
  #   - a dependency that STARTS SUCCESSFULLY. The run above only reached a
  #     dependency that timed out, so what a working dependency prints - and
  #     whether it gets an outcome line of its own - is unknown.
  #   - a dependency that is ALREADY RUNNING. Is the `Attempting to start
  #     service dependency` line printed anyway, or only when work is done?
  #   - `restart` on a service that is DOWN. The run above restarted one that
  #     was up.
  #   - a BATCH service, which is where the `(asynchronously)` variant of the
  #     progress line lives. Nothing has ever produced it.
  # ------------------------------------------------------------------------
  cat > "$WORK/services/rmscd2_depsvc.yaml" <<YEOF
name: RMSC D2 depsvc
start_cmd: /QOpenSys/pkgs/bin/python3 $WORK/listen.py 65440
check_alive: 65440
startup_wait_time: 15
stop_wait_time: 5
YEOF

  cat > "$WORK/services/rmscd2_parent.yaml" <<YEOF
name: RMSC D2 parent
start_cmd: /QOpenSys/pkgs/bin/python3 $WORK/listen.py 65441
check_alive: 65441
startup_wait_time: 15
stop_wait_time: 5
service_dependencies:
  - rmscd2_depsvc
YEOF

  cat > "$WORK/services/rmscd2_batch.yaml" <<YEOF
name: RMSC D2 batch
start_cmd: /QOpenSys/pkgs/bin/python3 $WORK/listen.py 65442
check_alive: 65442
batch_mode: true
sbmjob_jobname: RMSCD2BAT
startup_wait_time: 15
stop_wait_time: 5
YEOF

  # From a known-down state, so the dependency really is started by this call.
  "$SC" stop rmscd2_parent  >/dev/null 2>&1
  "$SC" stop rmscd2_depsvc  >/dev/null 2>&1
  probe "deps - start a parent whose dependency must be started"  start rmscd2_parent
  probe "deps - start it again, dependency already up"            start rmscd2_parent

  # Parent down, dependency still up: does the dependency line appear when
  # there is nothing for it to do?
  "$SC" stop rmscd2_parent >/dev/null 2>&1
  probe "deps - start a parent whose dependency is already running" start rmscd2_parent

  "$SC" stop rmscd2_parent  >/dev/null 2>&1
  "$SC" stop rmscd2_depsvc  >/dev/null 2>&1
  probe "restart - on a service that is down"  restart rmscd2_parent
  "$SC" stop rmscd2_parent  >/dev/null 2>&1
  "$SC" stop rmscd2_depsvc  >/dev/null 2>&1

  probe "batch - start a service submitted to batch"  start rmscd2_batch
  probe "batch - check it"                            check rmscd2_batch
  probe "batch - stop it"                             stop  rmscd2_batch
  "$SC" stop rmscd2_batch >/dev/null 2>&1

  # `No start command specified for service '%s'` is NOT probed. A definition
  # with no start_cmd is rejected at load time by upstream - `Required attribute
  # 'start_cmd' not specified` - so the message may not be reachable through a
  # YAML file at all. Where it comes from is unmeasured and stays that way.

  # Left down. The listener sleeps 300 seconds and no longer, so nothing
  # outlives this script even if it is killed before here.
  "$SC" stop rmscd2_narrate >/dev/null 2>&1
else
  echo
  echo "d2-probe: SKIPPED the narration cases. They start and stop a staged"
  echo "d2-probe: service, so they are opt-in: re-run with --narrate."
fi

echo
echo "d2-probe: done. Paste what is above into docs/messages.md and move each"
echo "d2-probe: row it answers from 'unmeasured' to 'measured'."
