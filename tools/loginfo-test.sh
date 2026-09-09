#!/QOpenSys/pkgs/bin/bash
#
# loginfo-test.sh - which STREAM the `loginfo` line lands on, what the line
# says when a log is empty, present or absent, and the trailing blank line.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses,
# and modelled on tools/error-delivery-test.sh and tools/sampletime-test.sh.
#
# WHY IT IS A SHELL SCRIPT AND NOT A SUITE
#
# `loginfo` only PRINTS. There is no exported procedure that returns the line,
# no structure a suite could read it out of, and the three things this file
# asks about - which stream, how many lines, what the line says byte for byte -
# only exist OUTSIDE the ILE job. iRPGUnit runs inside one.
#
# WHY IT IS A NEW FILE RATHER THAN CASES ADDED TO AN EXISTING HARNESS
#
#   fidelity-gate.sh        merges stderr into stdout with `2>&1` (see its
#                           DIFF_OPS line), so a line that MOVES between streams
#                           reads as identical to it. That merge is not an
#                           oversight this file could fix by adding a case: it
#                           is how the gate compares volatile output at all.
#                           It is also exactly how this difference came to be
#                           written down for weeks as "one trailing blank line"
#                           - a blank line in an odd place is the only residue a
#                           merged comparison leaves behind.
#
#   error-delivery-test.sh  asks which stream a FAILURE lands on and what the
#                           exit status says about the kind of failure. `loginfo`
#                           exits 0 in every case here, including the one where
#                           nothing is found: this is a REPORT, not an error, and
#                           the not-found line is upstream's ordinary answer.
#                           Nothing in that harness starts a service either -
#                           its state-changing sweep is opt-in for that reason.
#
#   load-warning-test.sh    asks what is said while READING DEFINITIONS, before
#                           any operation runs. It stages YAML through
#                           SC_SERVICES_DIR and touches nothing live. This needs
#                           a definition BOTH implementations can see - so the
#                           staging goes in the shared services directory, and
#                           the service has to be up.
#
#   narration-test.sh       what start and stop SAY. `loginfo` is read-only.
#
#   sampletime-test.sh      the perfinfo sampling window.
#
# WHAT IS BEING TESTED - measured against sc 1.7.1 on 9 September 2026, streams
# kept apart throughout. `<name>` is the short service name.
#
#   A. LOG FOUND, EMPTY
#      sc   stdout: `<name>: <path> (no data)` then a BLANK LINE; stderr silent
#      scr  stdout: `<name>: <path> (0 bytes)`, no blank line; stderr silent
#
#   B. LOG FOUND, NON-EMPTY
#      sc   stdout: `<name>: <path>` then a BLANK LINE - NOTHING after the path
#      scr  stdout: `<name>: <path> (15 bytes)`, no blank line
#
#   C. NO LOG FOUND
#      sc   stdout: a BLANK LINE and nothing else
#           stderr: `<name>: <unknown> (try checking in log directory <dir>)`
#      scr  stdout: that same text, no blank line; stderr silent
#
#   D. A GROUP - one member in the found state, one in the not-found state.
#      Measured 9 September 2026, both implementations byte-identical apart
#      from upstream's timestamp in the path:
#      sc   stdout: `<member>: <path>` then ONE BLANK LINE - one for the whole
#                   COMMAND, not one per member
#           stderr: the not-found line for the other member
#      scr  the same.
#
# Exit status is 0 in every case, both implementations.
#
# So upstream's rule is: the line goes to STDOUT when a log is found and to
# STDERR when it is not, and stdout always ends with exactly one blank line. The
# TEXT already matches byte for byte. What differs is the size suffix, the blank
# line, and the stream.
#
# THE FOUR RIVALS EACH CASE HAS TO RULE OUT, and where each is ruled out
#
#   1. THE SIZE SUFFIX IS TWO CHANGES, NOT ONE. `(0 bytes)` must become
#      `(no data)`, and a NON-EMPTY log must carry NO SUFFIX AT ALL. A fix that
#      only mapped 0 to "no data" passes an empty-log case and still prints
#      `(15 bytes)` on a log with content; one that stripped every suffix passes
#      the non-empty case and prints a bare path for an empty log where upstream
#      says `(no data)`. empty-log and non-empty-log disagree with each other on
#      both of those, which is the whole reason there are two of them.
#
#   2. THE BLANK LINE, in all three cases - including not-found, where it is the
#      ONLY thing on stdout. Asserted as "exactly one blank line and it is the
#      last", so neither losing it nor printing two passes.
#
#   3. THE STREAM, BOTH HALVES. The not-found line must appear on stderr AND
#      must not appear on stdout. A case that only checked stderr would pass an
#      implementation that wrote it to both - and writing it to both is the
#      likelier mistake, because it is what you get by adding a write rather
#      than moving one. The found cases assert the mirror image: on stdout, and
#      NOT on stderr.
#
#   4. NOTHING ELSE MOVED. See the next section.
#
#   5. THE BLANK LINE IS EMITTED ONCE PER COMMAND, NOT ONCE PER SERVICE - and
#      no case above can see the difference, because ON A SINGLE NAMED SERVICE
#      THE TWO PLACEMENTS ARE INDISTINGUISHABLE. One service, one blank line,
#      either way.
#
#      That is not a hypothetical either. The first implementation of this
#      change emitted the blank inside the per-service procedure, and on a
#      two-member group printed two blank lines where upstream prints one. It
#      was found in code review rather than by any test, and it got past the
#      measurement AND this harness for the same reason: every single thing
#      anybody measured named ONE service. The measurement was right; its
#      SCOPE was not.
#
#      So the group case below is the only case in this file that separates the
#      two placements, and it is why a group case exists at all. It deliberately
#      uses a MIXED group - one member whose log is found, one whose is not -
#      rather than two members in the same state, because the blank line has to
#      be right in both code paths. A group of two NOT-FOUND members would go
#      green against a blank line re-introduced in the FOUND path alone: with no
#      found member, that blank never gets printed. The mixed group prints one
#      of each and fails either way round.
#
# WHAT IS DELIBERATELY OUT OF SCOPE, AND HOW THE ASSERTIONS STAY OUT OF ITS WAY
#
# RMSC prints `    spooled file <name> number <n> in <job>` lines after the log
# line. Upstream has a spooled-file path too (`getSpooledFiles`), but WHAT IT
# PRINTS HAS NOT BEEN MEASURED - producing a spooled file owned by the service's
# own job needs a `batch_mode` service, and PASE runs each `system` call in its
# own job. So nothing here asserts agreement with upstream on spooled files.
#
# The temptation is to assert "stdout is exactly two lines", which is the
# strongest form and the wrong one: it would be broken by a spooled-file section
# arriving for this fixture, and would then fail while quoting a line that has
# nothing to do with the log line. So the stdout policy is stated as a SHAPE
# instead:
#
#     line 1 is the log line, byte for byte
#     exactly one blank line, and it is the last
#     every other line is a spooled-file line, and any that appear are NOTEd
#
# That rules out rivals 1-3 without pinning anything about the spooled section,
# and a spooled line appearing shows up in the run output rather than silently.
#
# THE ORDERING IS ASSERTED, and it is asserted by those three clauses together
# rather than by a clause of its own, so it is worth naming. Upstream's blank
# line ends the WHOLE REPORT - it comes after the spooled-file section, not
# after the log line. "Exactly one blank line, and it is the last" says exactly
# that: a spooled line printed AFTER the blank would leave the last line
# non-blank and fail, and a blank line printed after the log line and again at
# the end would be two. So the shape holds whether or not a spooled section
# appears, and if one ever does on this fixture the NOTE row says so and the
# ordering is checked rather than assumed.
#
# BASIS OF EACH ASSERTION - read this before believing a failure
#
#   measured   taken from a side-by-side run against the installed sc 1.7.1, and
#              RE-TAKEN in stage 2 on every run in the SAME fixture states, so
#              the reference cannot go stale underneath stage 1.
#
#   pinned     a place where the two implementations DELIBERATELY DISAGREE and
#              RMSC keeps its own behaviour. A failure here may be the intended
#              change arriving, in which case this script and docs/parity.md
#              need updating together.
#
# THE STOPPED-SERVICE DIVERGENCE, which was not in the brief and is measured
# here for the first time:
#
#   With the service STOPPED and its log file still on disk, upstream reports
#   NO LOG - the case C form, on stderr - while RMSC reports the log exactly as
#   it does for a running service. Upstream's `loginfo` is scoped to the running
#   instance; RMSC's is scoped to the file.
#
# That is pinned rather than asserted either way, because it is a decision
# nobody has taken. It is pinned HERE, in this file, because it is the change
# most likely to be made by accident BY the work this harness exists to guard:
# somebody implementing "the line goes to stderr when no log is found" can
# reasonably also decide a stopped service has no log, and that would be a
# second, unasked-for behaviour change arriving inside the first. The pinned row
# says so instead of accepting it.
#
# STAGING - and why it is done the way it is
#
# The two implementations NAME LOG FILES DIFFERENTLY. Upstream writes
# `<timestamp>.<name>.log`; RMSC writes `<name>.log`. Both in the same
# directory. Measured: upstream ignores the untimestamped file and RMSC ignores
# the timestamped one, so a service started by one implementation leaves the
# OTHER in case C.
#
# That is the trap in staging this at all, and it is silent: a run that started
# the service with `scr` would leave BOTH implementations reporting no log, and
# the comparison would pass having tested nothing. Two things are done about it:
#
#   - the service is STARTED WITH `sc`, never with `scr`, so a broken RMSC start
#     cannot be what puts upstream in case C;
#   - RMSC's log file is STAGED DIRECTLY, so RMSC's case is not a consequence of
#     RMSC's own start either. The fixture stage then PROVES the staging took by
#     requiring `scr loginfo` to name the staged path - and it accepts that on
#     EITHER STREAM, because which stream it lands on is the thing under test.
#     A fixture proof that depended on behaviour the fix will change is the trap
#     error-delivery-test.sh's staged-definitions block documents at length.
#
# NO SERVICE NAME OR PATH FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The
# repository is public. Both fixture services are INVENTED here, carry this
# script's PID so two runs cannot collide and debris is attributable, and are
# removed on the way out. The log directory is DISCOVERED at run time from both
# implementations, which must agree about it.
#
# THE STAGING IS IN THE USER'S REAL SERVICES DIRECTORY, and it has to be: it is
# the only place both implementations look. SC_SERVICES_DIR is RMSC's alone and
# upstream would not see it. So this script writes two files there, refuses to
# start if either name is already taken, and removes them in a trap on every
# exit path - INCLUDING an interrupt, where the trap exits rather than resuming
# into cases whose fixtures it has just deleted. The entry sweep cleans up after
# a run that was killed before its trap could fire, and TEARDOWN PROVES ITSELF:
# a definition still visible to `scr list` afterwards fails the run rather than
# being left for the fidelity gate to find three stages later and report as a
# formatting regression in `check`.
#
# Two rules govern that directory and they are deliberately the same strength.
# Staging will not overwrite a name it did not write; the reaper will not delete
# a file that does not carry this script's marker line, whatever its name says.
# A name alone is not ownership - see MARKER.
#
# Stdout and stderr are captured to SEPARATE files throughout. Nothing here uses
# `2>&1`: which stream the line landed on is the entire question, and it is the
# question a merged capture cannot be asked.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/rmsc-loginfo.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT.
#
# The same block appears in every script in tools/ that keeps its work directory
# and names it by PID. That is the membership rule - a property, not a count,
# and deliberately not "every harness": load-warning-test.sh has never carried
# it and fidelity-gate.sh is not a harness.
#
# Deliberately duplicated rather than shared: each is deployed and run
# standalone, and a shared file would be a dependency that costs more than the
# repetition does. Change one, change all of them.
#
# NEVER DELETE A DIRECTORY SOMETHING IS STILL USING. The name carries the PID
# that made it - WORK defaults to <prefix>.$$ - so ownership needs no
# bookkeeping, only `kill -0` on the suffix. The two most recent are kept so
# "inspect the artefacts" still works for the run that just failed and the one
# before it.
#
# The two failure modes are not symmetrical, and that decides the rule. A
# recycled PID means skipping a delete that could have been made: debris kept.
# Getting it wrong the other way destroys a run in flight. So anything that
# might be alive is left alone, and so is any name whose suffix is not a plain
# number - an overridden WORK= belongs to whoever set it.
ls -dt /tmp/rmsc-loginfo.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in
    ''|*[!0-9]*) continue ;;
  esac
  # `kill -0` fails two ways and they mean opposite things: ESRCH is "no such
  # process", EPERM is "alive, but not yours". Testing only the exit status
  # treats another user's LIVE run as dead and deletes its work directory - the
  # exact failure this block exists to prevent, on a shared box.
  if kill_err=$(kill -0 "$owner" 2>&1); then
    continue
  fi
  case "$kill_err" in
    *ermitted*|*EPERM*|*ermission*) continue ;;
  esac
  rm -rf "$stale" 2>/dev/null
done

# Without this the PASE side of both implementations behaves differently and
# neither the streams nor the output are comparable.
export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud. A run that skipped a case because
# a fixture was missing would report success while testing nothing.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory - it drives" \
  "the wrapper, and the wrapper calls an ILE program. Set SCR=<path> or" \
  "DEPLOY=<deploy dir> if the build lives somewhere else."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Upstream is not optional here. It STARTS the fixture service - a service" \
  "started by scr leaves upstream reporting no log, and the whole comparison" \
  "would pass having tested nothing - and stage 2 re-takes the reference that" \
  "stage 1's expectations are written against. Set SC=<path> if it is" \
  "installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "The fixture service's start_cmd is a SILENT python listener that binds the" \
  "port it is checked on. It must be silent: sc captures a service's output" \
  "into its log, so anything printed there changes which case the run is in." \
  "Set PY=<path> if python3 lives elsewhere."

SVCDIR="$HOME/.sc/services"
[ -d "$SVCDIR" ] || setup_fail \
  "no services directory at: $SVCDIR" \
  "" \
  "The fixture has to be visible to BOTH implementations, and this is the only" \
  "place both look. SC_SERVICES_DIR is RMSC's own mechanism and upstream would" \
  "not see a definition staged through it."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

# The two invented services. The PID is in the name so two runs cannot collide,
# and so debris from a killed run can be attributed and reaped.
RUN="rmsc_lg_run_$$"     # started, log staged, cases A and B
NONE="rmsc_lg_none_$$"   # never started, no log at all, case C

# THE OWNERSHIP MARKER, and why a name is not enough.
#
# Staging refuses to overwrite a definition by exact name. The REAPER below is
# the path that actually DELETES, and it works from a prefix glob - so a name
# alone is a weaker promise than the one staging makes. A user's own file called
# rmsc_lg_run_2024.yaml has an all-digit tail, and PID 2024 is unlikely to be
# alive: it matched every test the reaper made, and would have been stopped and
# deleted by a test run that had never seen it before.
#
# So the reaper requires this line to be INSIDE the file as well. Nothing writes
# it but this script. The two rules are then the same strength: staging will not
# overwrite what it did not write, and the reaper will not delete it either.
#
# It is a YAML comment and both implementations ignore it - which is checked
# rather than assumed, because a marker that broke parsing would break every
# fixture: fixture-definitions loads them through scr and fixture-start starts
# one through sc, so a comment either implementation refused would fail stage 0
# loudly rather than quietly changing what is being tested.
MARKER='# staged by tools/loginfo-test.sh - a test fixture, safe to remove'
PORT_RUN=59491
PORT_NONE=59492

# Both fixtures are also members of one invented group, which costs nothing -
# no third definition and no second service to start - and buys the only case
# in this file that can tell one blank line per COMMAND from one per SERVICE.
#
# THEIR check_alive CRITERIA MUST STAY DISTINCT. Two definitions sharing one
# criterion draw a conflicting-definitions WARNING naming both of them, on
# stderr - harmless in itself, and it would land in the middle of the stream
# this file reads the not-found line off. The ports differ above; keep them
# differing.
GROUP="rmsclg$$"
LOGDIR=""                # discovered below, never assumed

# REFUSE TO CLOBBER. These are invented names in a real directory; if one is
# already taken, something else owns it and overwriting it would be a change to
# somebody's system made by a test.
for n in "$RUN" "$NONE"; do
  [ -e "$SVCDIR/$n.yaml" ] && setup_fail \
    "$SVCDIR/$n.yaml already exists." \
    "" \
    "This harness invents that name from its own PID and will not overwrite a" \
    "file it did not write. Remove it if it is debris from a killed run."
done

# TEARDOWN. Everything staged outside the work directory is removed here, on
# every exit path. The staged definitions live in the user's real services
# directory, so leaving them behind would change what every other harness and
# the fidelity gate sees - not merely leak a temporary file.
teardown() {
  local rc=$?
  "$SC" stop "$RUN" >/dev/null 2>&1 </dev/null
  # The listener, by the work directory PATH rather than by the script name, so
  # a listener belonging to another run of this script is left alone.
  pkill -f "$WORK/listen.py" >/dev/null 2>&1
  rm -f "$SVCDIR/$RUN.yaml" "$SVCDIR/$NONE.yaml"
  if [ -n "$LOGDIR" ] && [ -d "$LOGDIR" ]; then
    rm -f "$LOGDIR/$RUN.log" "$LOGDIR/$NONE.log"
    rm -f "$LOGDIR"/*."$RUN".log "$LOGDIR"/*."$NONE".log
  fi
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"

  # TEARDOWN PROVES ITSELF, AND THE REASON IS THREE STAGES AWAY.
  #
  # verify.sh runs this harness at the `loginfo` stage and the fidelity gate at
  # `gate`. The gate's first stage is a BYTE-EXACT diff of check, list and
  # groups against captured baselines, and its second enumerates its sweep from
  # `scr list`. A fixture definition that survived teardown is two extra
  # services in all three of those: the gate fails, and it fails looking like a
  # formatting regression in `check` - the single most expensive thing to
  # misdiagnose in this repository, and it would be pointing at output that is
  # perfectly correct.
  #
  # So the check is made HERE, on every exit path including an interrupt, and it
  # is made THROUGH `scr list` rather than through `ls`. The filesystem would
  # answer the cheaper question - are the files gone - but the gate does not
  # read the filesystem, it reads a service list, and that is the question worth
  # asking. It costs one run.
  #
  # IT ASKS ABOUT THIS RUN'S OWN TWO NAMES, and only those. "Any rmsc_lg_*" is
  # the broader question and the wrong one: it is not this run's teardown that
  # failed if another file is there. A second instance running concurrently has
  # its own two names visible and is entitled to them, and a stranger's file is
  # the reaper's business, not teardown's - reported below, never fatal, and
  # never deleted. Failing on those would make a green run depend on what else
  # happens to be on the box, which is the machine deciding the verdict.
  local listing left other
  listing=$("$SCR" list 2>/dev/null </dev/null)
  left=$(printf '%s\n' "$listing" | grep -cE "^($RUN|$NONE) " || true)
  [ -z "$left" ] && left=0
  other=$(printf '%s\n' "$listing" | grep -E '^rmsc_lg_' | grep -vE "^($RUN|$NONE) " || true)
  [ -n "$other" ] && {
    echo "NOTE: other rmsc_lg_ definitions are visible and were NOT touched:" >&2
    printf '%s\n' "$other" | sed 's/^/  /' >&2
    echo "  (a concurrent run's, or a file without this script's marker line)" >&2
  }
  if [ "$left" -ne 0 ]; then
    echo
    echo "TEARDOWN FAILED: $left of this run's own fixture definition(s) are" >&2
    echo "still visible to '$SCR list'." >&2
    printf '%s\n' "$listing" | grep -E "^($RUN|$NONE) " | sed 's/^/  /' >&2
    echo "Remove them from $SVCDIR before running the fidelity gate: it diffs" >&2
    echo "check, list and groups byte for byte and would report these as a" >&2
    echo "formatting regression in check." >&2
    exit 3
  fi
  return $rc
}

# EXIT ONLY ONCE, AND DO NOT RESUME INTO A RUN WHOSE FIXTURES ARE GONE.
#
# `trap teardown EXIT INT TERM` is the shape the sibling harnesses use, and on a
# signal bash runs the handler and then CARRIES ON from where it was. For a
# harness whose teardown only removes a /tmp work directory that is untidy; for
# this one it means the definitions and the staged logs are deleted and the
# remaining cases then run against fixtures that no longer exist, reporting
# failures that describe nothing. This one is the first whose teardown deletes
# files in a directory shared with every other harness and with the gate.
#
# So the signal path disarms the EXIT trap and exits, and teardown runs exactly
# once. 130 is the conventional status for an interrupted run.
on_signal() { trap - EXIT; teardown; exit 130; }
trap teardown EXIT
trap on_signal INT TERM

# Reap debris from a run that was killed before its trap could fire. Split from
# the /tmp block above because it needs $SC, which is only known to exist after
# the setup checks. A dead owner's service is STOPPED BEFORE ITS DEFINITION IS
# REMOVED - the other order leaves an orphan listener holding the port with
# nothing left that knows how to stop it.
UNCLAIMED=""
for stale in "$SVCDIR"/rmsc_lg_run_*.yaml "$SVCDIR"/rmsc_lg_none_*.yaml; do
  [ -e "$stale" ] || continue
  base="${stale##*/}"; base="${base%.yaml}"
  owner="${base##*_}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  [ "$owner" = "$$" ] && continue
  # NAME AND PID ARE NOT OWNERSHIP. The marker is - see above. A file that looks
  # like debris and does not carry it is left alone and REPORTED, because
  # something that cannot be attributed should be seen rather than either
  # deleted or silently ignored.
  if ! grep -Fq -- "$MARKER" "$stale" 2>/dev/null; then
    UNCLAIMED="$UNCLAIMED $base"
    continue
  fi
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  "$SC" stop "$base" >/dev/null 2>&1 </dev/null
  rm -f "$stale"
done

pass=0; failed=0; changed=0; refdrift=0

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-24s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-24s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-24s %s\n' verdict case detail
  printf '  %-9s %-24s %s\n' --------- ------------------------ ------
}

# wc -l undercounts a final line with no trailing newline. grep -c '' does not.
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

# The three markers a crash leaves, on either stream. RNX and MCH are matched
# with their four digits so a service description containing the letters cannot
# match; CEE9901 is the ILE wrapper the other two arrive inside.
ABEND_RE='CEE9901|RNX[0-9]{4}|MCH[0-9]{4}'

# A spooled-file line. Tolerated everywhere and asserted nowhere - see WHAT IS
# DELIBERATELY OUT OF SCOPE.
SPOOL_RE='^[[:space:]]+spooled file '

# capture TAG BIN NAME - one loginfo run, streams apart. Sets RC.
#
# `< /dev/null` on every invocation: `system` in PASE consumes stdin, and a
# harness run from a pipeline (verify.sh runs each one into `tail`) would have
# its own input eaten by the first call.
capture() {
  local tag="$1" bin="$2" name="$3"
  "$bin" loginfo "$name" > "$WORK/$tag.out" 2> "$WORK/$tag.err" </dev/null
  RC=$?
}

# ---------------------------------------------------------------------------
# The stdout shape, shared by every case.
#
#   line 1        must equal WANT byte for byte, or - for a not-found case -
#                 must be blank and WANT must appear nowhere on stdout
#   blank lines   exactly one, and it is the last line
#   anything else must be a spooled-file line, and is reported as a NOTE
#
# Stated as a shape rather than "stdout is exactly N lines" so that a
# spooled-file section arriving does not break a case that has nothing to say
# about spooled files. See the header.
# ---------------------------------------------------------------------------
check_stdout_shape() {  # outfile want_line_or_empty  -> echoes problems, one per line
  local o="$1" want="$2"
  local n first nblank last extra rest

  n=$(count_lines "$o")
  if [ "$n" -eq 0 ]; then
    echo "stdout is completely empty - upstream always leaves one blank line here"
    return
  fi

  nblank=$(grep -c '^$' "$o" || true); [ -z "$nblank" ] && nblank=0
  [ "$nblank" -eq 1 ] || echo "$nblank blank line(s) on stdout, wanted exactly one"

  last=$(tail -n 1 "$o")
  [ -z "$last" ] || echo "the last stdout line is not blank: '$last'"

  # WHICH LINES ARE HELD TO THE SPOOLED-FILE EXEMPTION DEPENDS ON THE CASE, and
  # getting that wrong is how the exemption came to have a hole in it.
  #
  # When a log IS found, the log line is line 1 and the exemption applies from
  # line 2 down. When NO log is found the log line is not on stdout at all -
  # it has moved to stderr, which is the whole point - so there is no line 1 to
  # anchor to, and A SPOOLED LINE IS THEN THE FIRST THING ON STDOUT. RMSC's
  # spooled loop runs in the not-found case as well.
  #
  # This used to assert that line 1 was blank in that case, which reintroduced
  # the exact failure the shape policy exists to avoid - a case failing while
  # quoting a spooled line - in the one case where the log line is not on
  # stdout. Latent rather than seen: this fixture is not a batch service and
  # cannot produce a spooled file. Position is the wrong thing to assert here;
  # CONTENT is right. That the not-found line is absent from stdout is asserted
  # by its caller, from the service name, and does not depend on position.
  if [ -n "$want" ]; then
    first=$(head -n 1 "$o")
    [ "$first" = "$want" ] || echo "stdout line 1 is '$first', wanted '$want'"
    rest=$(sed -n '2,$p' "$o")
  else
    rest=$(cat "$o")
  fi

  extra=$(printf '%s\n' "$rest" | grep -vE '^$' | grep -cvE "$SPOOL_RE" || true)
  [ -z "$extra" ] && extra=0
  [ "$extra" -eq 0 ] || \
    echo "$extra unexpected stdout line(s): '$(printf '%s\n' "$rest" | grep -vE '^$' | grep -m1 -vE "$SPOOL_RE")'"
}

# Load warnings are sanctioned on stderr for a command that succeeded - D4 put
# them there and upstream does the same. What is NOT sanctioned is a line about
# the service under test, which is the line this whole file is about. The
# service names are invented and unique to this run, so "lines mentioning the
# name" is a precise filter and does not depend on a warning prefix staying put.
mentions() { grep -Fc -- "$2" "$1" 2>/dev/null || true; }

# assert_case TAG BASIS FOUND NAME WANT
#
#   FOUND=yes  the line belongs on STDOUT, exactly once, and NOT on stderr
#   FOUND=no   the line belongs on STDERR, exactly once, and NOT on stdout,
#              and stdout carries the blank line alone
#
# Reads $WORK/$TAG.out and .err, captured earlier in the right fixture state.
assert_case() {
  local tag="$1" basis="$2" found="$3" name="$4" want="$5"
  local o="$WORK/$tag.out" e="$WORK/$tag.err"
  local problems=() on_out on_err spool p

  # First, and reported first: a crash is not a formatting difference.
  if grep -qE "$ABEND_RE" "$o" "$e" 2>/dev/null; then
    report FAIL "$tag" "($basis) ABEND: $(grep -hE -m1 "$ABEND_RE" "$o" "$e")"
    detail "artefacts: $tag.out $tag.err"
    failed=$((failed+1))
    return 1
  fi

  [ "${RC_SAVED[$tag]:-0}" -eq 0 ] || problems+=("exit ${RC_SAVED[$tag]}, wanted 0 - loginfo is a report and succeeds in every case")

  on_out=$(mentions "$o" "$name"); [ -z "$on_out" ] && on_out=0
  on_err=$(mentions "$e" "$name"); [ -z "$on_err" ] && on_err=0

  if [ "$found" = yes ]; then
    while IFS= read -r p; do [ -n "$p" ] && problems+=("$p"); done < <(check_stdout_shape "$o" "$want")
    # BOTH HALVES OF THE STREAM QUESTION. One line naming the service on stdout,
    # and none on stderr - an implementation that wrote to both would satisfy
    # either half alone.
    [ "$on_out" -eq 1 ] || problems+=("$on_out stdout line(s) name the service, wanted exactly one")
    [ "$on_err" -eq 0 ] || problems+=("the log line is ALSO on stderr ($on_err line(s)): $(grep -F -m1 -- "$name" "$e")")
  else
    while IFS= read -r p; do [ -n "$p" ] && problems+=("$p"); done < <(check_stdout_shape "$o" "")
    [ "$on_out" -eq 0 ] || problems+=("the not-found line is on STDOUT ($on_out line(s)) - upstream puts it on stderr and leaves stdout blank")
    if [ "$on_err" -eq 0 ]; then
      problems+=("nothing on stderr names the service - the not-found line was reported somewhere else, or not at all")
    elif [ "$on_err" -ne 1 ]; then
      problems+=("the not-found line appears $on_err times on stderr, wanted once")
    else
      local got; got=$(grep -F -m1 -- "$name" "$e")
      [ "$got" = "$want" ] || problems+=("stderr line is '$got', wanted '$want'")
    fi
  fi

  spool=$(grep -cE "$SPOOL_RE" "$o" 2>/dev/null || true); [ -z "$spool" ] && spool=0
  [ "$spool" -eq 0 ] || \
    report NOTE "$tag" "$spool spooled-file line(s) on stdout - tolerated, asserted nowhere, and out of scope for this work"

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) exit ${RC_SAVED[$tag]}, $(count_lines "$o") stdout line(s)"
    pass=$((pass+1))
    return 0
  fi

  if [ "$basis" = pinned ]; then
    report CHANGED "$tag" "RMSC's pinned behaviour moved - see the comment above this case"
    changed=$((changed+1))
  else
    report FAIL "$tag" "($basis)"
    failed=$((failed+1))
  fi
  for p in "${problems[@]}"; do detail "$p"; done
  detail "artefacts: $tag.out $tag.err"
  return 1
}

declare -A RC_SAVED=()
grab() {  # tag bin name
  capture "$1" "$2" "$3"
  RC_SAVED[$1]=$RC
}

printf 'loginfo: which stream the line lands on, what it says, and the blank line\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'fixtures: %s (started, log staged), %s (never started)\n\n' "$RUN" "$NONE"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture. Nothing below is evidence until every row here passes"
echo
heading
# ---------------------------------------------------------------------------

# The silent listener. SILENCE IS LOAD-BEARING: `sc` captures a service's output
# into its log, so a listener that printed anything would put case A - the EMPTY
# log - into case B, and upstream would additionally emit "For details, see log
# file at:", which has cost this project a run of false failures before.
cat > "$WORK/listen.py" <<'PYEOF'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1])))
s.listen(5)
time.sleep(900)
PYEOF

write_def() {  # short port
  cat > "$SVCDIR/$1.yaml" <<EOF
$MARKER
name: RMSC loginfo fixture $1
start_cmd: $PY $WORK/listen.py $2
check_alive: $2
startup_wait_time: 20
stop_wait_time: 5
groups:
- $GROUP
EOF
}
write_def "$RUN" "$PORT_RUN"
write_def "$NONE" "$PORT_NONE"

# (a) BOTH DEFINITIONS LOAD, AND NEITHER IS ALREADY RUNNING.
#
# Two things at once, and both are needed. If a definition did not load, every
# case below would be asking about a service that does not exist. If a service
# were already RUNNING before this script started it, something else holds the
# port - and the case-C service must not be running at all, because a service
# somebody else started may well have a log.
fx=()
for pair in "$RUN:$PORT_RUN" "$NONE:$PORT_NONE"; do
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
  detail "staged in $SVCDIR - they are removed on exit"
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed   pinned-changed=0   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
report PASS fixture-definitions "both staged definitions load and neither is running"
pass=$((pass+1))
[ -n "$UNCLAIMED" ] && report NOTE fixture-definitions \
  "left alone - no marker line, so not this harness's to delete:$UNCLAIMED"

# (b) THE LOG DIRECTORY, DISCOVERED FROM BOTH IMPLEMENTATIONS.
#
# Never hardcoded: this file is published and a developer's home directory does
# not belong in it. Both implementations name the directory in their not-found
# line, and they must AGREE about it - if they did not, no file could be staged
# where both would look, and the three cases below would be comparing two
# different questions.
#
# RMSC's copy is looked for on EITHER STREAM. Which stream it lands on is the
# thing under test, so a fixture step that expected one would stop working the
# day the fix lands - the trap error-delivery-test.sh's staged-definitions block
# documents at length.
"$SC"  loginfo "$NONE" > "$WORK/dir.sc.out"  2> "$WORK/dir.sc.err"  </dev/null
"$SCR" loginfo "$NONE" > "$WORK/dir.scr.out" 2> "$WORK/dir.scr.err" </dev/null
dir_of() { cat "$@" 2>/dev/null | grep -F -- 'try checking in log directory' \
             | sed -e 's/.*try checking in log directory //' -e 's/)[[:space:]]*$//' | head -n 1; }
SC_LOGDIR=$(dir_of "$WORK/dir.sc.out" "$WORK/dir.sc.err")
SCR_LOGDIR=$(dir_of "$WORK/dir.scr.out" "$WORK/dir.scr.err")

if [ -z "$SC_LOGDIR" ] || [ -z "$SCR_LOGDIR" ] || [ "$SC_LOGDIR" != "$SCR_LOGDIR" ]; then
  report FAIL fixture-logdir "the two implementations do not agree on a log directory"
  detail "sc:  '${SC_LOGDIR:-<nothing found>}'"
  detail "scr: '${SCR_LOGDIR:-<nothing found>}'"
  detail "nothing can be staged where both would look, so no case below would be comparable"
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed   pinned-changed=0   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
LOGDIR="$SC_LOGDIR"
report PASS fixture-logdir "both name the same log directory"
pass=$((pass+1))

# (c) START IT, WITH `sc`.
#
# Never with scr. Upstream reports a log only for a service it started - it
# reads the timestamped file it wrote itself, and ignores RMSC's untimestamped
# one - so a service started by scr would leave upstream in case C and the
# comparison would pass having tested nothing.
"$SC" start "$RUN" > "$WORK/start.out" 2> "$WORK/start.err" </dev/null
start_rc=$?

# WAIT FOR THE LISTENER rather than hoping the start command's return meant it.
waited=0
while [ "$waited" -lt 30 ]; do
  "$SCR" check "$RUN" 2>/dev/null </dev/null | grep -qE '^  RUNNING .*'"$RUN" && break
  sleep 1; waited=$((waited+1))
done
st=$("$SCR" check "$RUN" 2>/dev/null </dev/null | grep -F -- "$RUN" | sed 's/ *|.*//; s/^ *//')
if [ "$start_rc" -ne 0 ] || [ "$st" != RUNNING ]; then
  report FAIL fixture-start "sc start exited $start_rc and the service is '$st' after ${waited}s"
  detail "the listener never bound port $PORT_RUN, or the start failed"
  detail "start said: $(head -n 1 "$WORK/start.err" 2>/dev/null)"
  failed=$((failed+1))
  echo; echo "pass=$pass   failed=$failed   pinned-changed=0   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi
report PASS fixture-start "started by sc, RUNNING after ${waited}s"
pass=$((pass+1))

# (d) UPSTREAM'S OWN LOG EXISTS AND IS EMPTY, and RMSC's is staged empty beside
# it. Case A is "log found, EMPTY" for BOTH implementations, and an upstream log
# with content in it would silently make the upstream half of case A into case B.
SC_LOG=$(ls -1t "$LOGDIR"/*."$RUN".log 2>/dev/null | head -n 1)
SCR_LOG="$LOGDIR/$RUN.log"
: > "$SCR_LOG"

if [ -z "$SC_LOG" ]; then
  report FAIL fixture-logs "sc started the service and wrote no log file for it"
  detail "looked for $LOGDIR/*.$RUN.log"
  failed=$((failed+1))
elif [ -s "$SC_LOG" ]; then
  report FAIL fixture-logs "upstream's log is not empty ($(wc -c < "$SC_LOG") bytes) - case A would not be the empty case"
  detail "the start command must be SILENT; sc captures a service's output into its log"
  detail "it said: $(head -n 1 "$SC_LOG")"
  failed=$((failed+1))
else
  report PASS fixture-logs "upstream's log is empty, RMSC's staged empty beside it"
  pass=$((pass+1))
fi

# (e) THE STAGING TOOK - RMSC IS IN CASE A AND NOT IN CASE C.
#
# Accepted on EITHER STREAM: which stream the line lands on is the thing under
# test, so a proof that required stdout would stop working the day the fix
# lands, and would then report a working fixture as an absent one.
"$SCR" loginfo "$RUN" > "$WORK/proof.out" 2> "$WORK/proof.err" </dev/null
if cat "$WORK/proof.out" "$WORK/proof.err" | grep -Fq -- "$SCR_LOG"; then
  report PASS fixture-staging "scr names the staged log - it is in the found case, not the not-found one"
  pass=$((pass+1))
else
  report FAIL fixture-staging "FIXTURE DID NOT TAKE: scr does not name $SCR_LOG"
  detail "it said: $(cat "$WORK/proof.out" "$WORK/proof.err" | grep -F -- "$RUN" | head -n 1)"
  detail "RMSC's log naming has changed, or it looks somewhere else - restage before believing anything below"
  detail "every case below would be measuring the NOT-FOUND path while claiming to measure the found one"
  failed=$((failed+1))
fi

# (f) THE GROUP HOLDS BOTH MEMBERS.
#
# Without this, `loginfo group:` could match nothing and the group case would be
# asserting against an empty run. It could not go green that way - it demands a
# found line on stdout and would fail - but it would fail saying the blank line
# was wrong, quoting output that has nothing to do with the blank line, and
# whoever read it would go looking in the wrong place. The proof comes from
# `check group:`, whose ROWS are the evidence and are not moved by anything
# this file tests.
gm=$("$SCR" check "group:$GROUP" 2>/dev/null </dev/null | grep -cE "$RUN|$NONE" || true)
[ -z "$gm" ] && gm=0
if [ "$gm" -eq 2 ]; then
  report PASS fixture-group "group:$GROUP holds both fixtures"
  pass=$((pass+1))
else
  report FAIL fixture-group "group:$GROUP holds $gm of the 2 fixtures"
  detail "the group case would be measuring a command that matched nothing"
  failed=$((failed+1))
fi

if [ "$failed" -ne 0 ]; then
  echo; echo "pass=$pass   failed=$failed   pinned-changed=0   reference-drift=0"
  echo "FAILED: no usable fixture"
  exit 1
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the four cases, measured against sc 1.7.1"
echo
heading
# ---------------------------------------------------------------------------

# CASE A - LOG FOUND, EMPTY. `(no data)`, not `(0 bytes)`, then the blank line.
#
# Half of rival 1. On its own it would be satisfied by a fix that mapped an
# empty log to "no data" and left `(15 bytes)` on every other log, which is why
# non-empty-log below exists and asserts the opposite thing.
grab empty-log "$SCR" "$RUN"
grab sc.empty-log "$SC" "$RUN"
assert_case empty-log measured yes "$RUN" "$RUN: $SCR_LOG (no data)"

# CASE B - LOG FOUND, WITH CONTENT. NOTHING after the path.
#
# The other half of rival 1, and the case a "fix the suffix" change is most
# likely to miss: upstream does not print a size here at all, so the suffix is
# not corrected, it is removed. Written into BOTH log files so both
# implementations are in the same case - upstream reads its own timestamped
# file and would otherwise still be in case A.
printf 'hello from log\n' > "$SCR_LOG"
printf 'hello from log\n' > "$SC_LOG"
if [ ! -s "$SCR_LOG" ] || [ ! -s "$SC_LOG" ]; then
  report FAIL non-empty-log "FIXTURE: could not put content in both log files"
  detail "case B would be case A, and would demand a suffix upstream does not print"
  failed=$((failed+1))
else
  grab non-empty-log "$SCR" "$RUN"
  grab sc.non-empty-log "$SC" "$RUN"
  assert_case non-empty-log measured yes "$RUN" "$RUN: $SCR_LOG"
fi

# CASE C - NO LOG AT ALL. The line moves to STDERR and stdout keeps the blank
# line, which is then the only thing on it.
#
# Rivals 2 and 3 together, and this is where they bite hardest: the blank line
# is the ENTIRE stdout, so losing it leaves stdout empty rather than merely
# short, and an implementation that wrote the line to both streams satisfies
# the stderr half while still breaking the consumer that reads stdout.
grab no-log "$SCR" "$NONE"
grab sc.no-log "$SC" "$NONE"
assert_case no-log measured no "$NONE" \
  "$NONE: <unknown> (try checking in log directory $LOGDIR)"

# CASE D - A GROUP, AND THE ONLY CASE HERE THAT CAN SEE RIVAL 5.
#
# ONE BLANK LINE FOR THE WHOLE COMMAND, not one per member. Every case above
# names a single service, and on a single service one-per-command and
# one-per-service produce the same output - so all three would stay green
# across a change that was wrong in both directions, and one of them was: the
# blank was first emitted inside the per-service procedure and printed twice
# for a two-member group.
#
# The group is MIXED on purpose - $RUN is in the found state (its log still
# holds case B's content) and $NONE has no log at all. Two members in the same
# state would be weaker: with no found member, a blank line wrongly re-added to
# the FOUND path never gets printed and the case goes green anyway. One of each
# fails whichever path the extra blank came back into.
#
# It also asserts the STREAMS stay separated across a group, which is a
# different question from asserting it for one service: the found member's line
# on stdout and NOT on stderr, the not-found member's on stderr and NOT on
# stdout, in one command that does both at once.
#
# No service is started for this and none is stopped. It reuses the two fixtures
# already staged, so it costs one scr run and one sc run.
grab group "$SCR" "group:$GROUP"
grab sc.group "$SC" "group:$GROUP"

gprob=()
while IFS= read -r p; do [ -n "$p" ] && gprob+=("$p"); done \
  < <(check_stdout_shape "$WORK/group.out" "$RUN: $SCR_LOG")
[ "${RC_SAVED[group]:-1}" -eq 0 ] || gprob+=("exit ${RC_SAVED[group]}, wanted 0")

g_run_out=$(mentions "$WORK/group.out" "$RUN");   [ -z "$g_run_out" ] && g_run_out=0
g_run_err=$(mentions "$WORK/group.err" "$RUN");   [ -z "$g_run_err" ] && g_run_err=0
g_none_out=$(mentions "$WORK/group.out" "$NONE"); [ -z "$g_none_out" ] && g_none_out=0
g_none_err=$(mentions "$WORK/group.err" "$NONE"); [ -z "$g_none_err" ] && g_none_err=0

[ "$g_run_out" -eq 1 ] || gprob+=("the found member appears $g_run_out time(s) on stdout, wanted once")
[ "$g_run_err" -eq 0 ] || gprob+=("the found member is on STDERR too: $(grep -F -m1 -- "$RUN" "$WORK/group.err")")
[ "$g_none_out" -eq 0 ] || gprob+=("the not-found member is on STDOUT: $(grep -F -m1 -- "$NONE" "$WORK/group.out")")
if [ "$g_none_err" -ne 1 ]; then
  gprob+=("the not-found member appears $g_none_err time(s) on stderr, wanted once")
else
  gline=$(grep -F -m1 -- "$NONE" "$WORK/group.err")
  [ "$gline" = "$NONE: <unknown> (try checking in log directory $LOGDIR)" ] || \
    gprob+=("stderr line is '$gline', wanted the not-found line for $NONE")
fi

if [ ${#gprob[@]} -eq 0 ]; then
  report PASS group "(measured) one blank line for a 2-member command, streams separated"
  pass=$((pass+1))
else
  report FAIL group "(measured) the blank line or the streams are wrong for a GROUP"
  for p in "${gprob[@]}"; do detail "$p"; done
  detail "TWO blank lines here and one everywhere else means it is emitted per SERVICE, not per COMMAND"
  detail "a warning line naming a fixture would mean the two staged criteria have collided - they must differ"
  detail "artefacts: group.out group.err"
  failed=$((failed+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 2: upstream reference, re-taken in the same fixture states"
echo "   (stage 1's expectations are only as good as this table; a REFDRIFT"
echo "    means the reference moved, not that RMSC regressed)"
echo
heading
# ---------------------------------------------------------------------------

# The paths differ between implementations by upstream's timestamp, so the
# comparison is made with the path normalised out. Everything else - the name,
# the colon, the suffix or its absence, the blank line, the stream - is compared
# as it stands.
norm() { sed -e "s#$LOGDIR/[^ ]*\.log#<LOG>#" "$@"; }

sc_ref() {  # tag found want_normalised
  local tag="$1" found="$2" want="$3"
  local o="$WORK/$tag.out" e="$WORK/$tag.err" why="" line n nblank
  [ "${RC_SAVED[$tag]:-1}" -eq 0 ] || why="$why exit=${RC_SAVED[$tag]}(wanted 0)"
  n=$(count_lines "$o")
  nblank=$(grep -c '^$' "$o" || true); [ -z "$nblank" ] && nblank=0
  [ "$nblank" -eq 1 ] || why="$why blank-lines=$nblank(wanted 1)"
  [ -z "$(tail -n 1 "$o")" ] || why="$why last-line-not-blank"
  if [ "$found" = yes ]; then
    line=$(norm "$o" | head -n 1)
    [ "$line" = "$want" ] || why="$why stdout='$line'(wanted '$want')"
    [ "$n" -eq 2 ] || why="$why stdout-lines=$n(wanted 2)"
  else
    line=$(norm "$e" | grep -F -- 'try checking in log directory' | head -n 1)
    [ "$line" = "$want" ] || why="$why stderr='$line'(wanted '$want')"
    [ "$n" -eq 1 ] || why="$why stdout-lines=$n(wanted 1, the blank line alone)"
    grep -Fq -- 'try checking' "$o" 2>/dev/null && why="$why also-on-stdout"
  fi
  if [ -z "$why" ]; then
    report PASS "sc:${tag#sc.}" "as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:${tag#sc.}" "$why"
    detail "artefacts: $tag.out $tag.err"
    refdrift=$((refdrift+1))
  fi
}

sc_ref sc.empty-log     yes "$RUN: <LOG> (no data)"
sc_ref sc.non-empty-log yes "$RUN: <LOG>"
sc_ref sc.no-log        no  "$NONE: <unknown> (try checking in log directory $LOGDIR)"

# THE GROUP, which sc_ref cannot express: it is the one command whose answer
# spans BOTH streams at once, and sc_ref asks about one of them. Upstream's
# stdout is the found member's line and ONE blank - the whole point - and its
# stderr carries the other member's not-found line.
g_why=""
[ "${RC_SAVED[sc.group]:-1}" -eq 0 ] || g_why="$g_why exit=${RC_SAVED[sc.group]}(wanted 0)"
sg_n=$(count_lines "$WORK/sc.group.out")
sg_blank=$(grep -c '^$' "$WORK/sc.group.out" || true); [ -z "$sg_blank" ] && sg_blank=0
sg_line=$(norm "$WORK/sc.group.out" | head -n 1)
[ "$sg_blank" -eq 1 ] || g_why="$g_why blank-lines=$sg_blank(wanted 1 for the whole command)"
[ "$sg_n" -eq 2 ] || g_why="$g_why stdout-lines=$sg_n(wanted 2)"
[ "$sg_line" = "$RUN: <LOG>" ] || g_why="$g_why stdout='$sg_line'(wanted '$RUN: <LOG>')"
[ "$(mentions "$WORK/sc.group.err" "$NONE")" -eq 1 ] || \
  g_why="$g_why not-found-on-stderr=$(mentions "$WORK/sc.group.err" "$NONE")(wanted 1)"
[ "$(mentions "$WORK/sc.group.out" "$NONE")" -eq 0 ] || g_why="$g_why not-found-also-on-stdout"
if [ -z "$g_why" ]; then
  report PASS "sc:group" "one blank line for a 2-member command, as recorded"
  pass=$((pass+1))
else
  report REFDRIFT "sc:group" "$g_why"
  detail "the group case in stage 1 is written against this row - re-take it before acting on a failure"
  detail "artefacts: sc.group.out sc.group.err"
  refdrift=$((refdrift+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 3: a known difference, pinned so a change to it is visible"
echo
heading
# ---------------------------------------------------------------------------

# PINNED - A STOPPED SERVICE WHOSE LOG IS STILL ON DISK.
#
#   upstream sc:  reports NO LOG. The case C form, on stderr, with the blank
#                 line on stdout - upstream's loginfo is scoped to the running
#                 instance.
#   RMSC:         reports the log exactly as it does for a running service -
#                 RMSC's is scoped to the file.
#
# Measured 9 September 2026 and not previously recorded anywhere. Neither is
# asserted to be right: it is a decision nobody has taken.
#
# IT IS PINNED HERE because it is the change most likely to be made BY ACCIDENT
# by the work this file guards. Somebody implementing "the line goes to stderr
# when no log is found" may reasonably also decide that a stopped service has no
# log - a second, unasked-for behaviour change arriving inside the first. This
# row says so rather than letting it through.
#
# THE TEXT IS NOT ASSERTED, only WHICH CASE each implementation is in. The text
# is what the rest of this file is about and is expected to change; the case
# each implementation is in is not.
"$SC" stop "$RUN" > "$WORK/stop.out" 2> "$WORK/stop.err" </dev/null
stopped=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  st=$("$SCR" check "$RUN" 2>/dev/null </dev/null | grep -F -- "$RUN" | sed 's/ *|.*//; s/^ *//')
  [ "$st" = 'NOT RUNNING' ] && { stopped=yes; break; }
  sleep 1
done

if [ -z "$stopped" ]; then
  report FAIL stopped-service "FIXTURE: the service did not stop (still '$st')"
  detail "the pinned comparison needs it down; nothing is concluded about the divergence"
  failed=$((failed+1))
else
  grab stopped.scr "$SCR" "$RUN"
  grab stopped.sc  "$SC"  "$RUN"
  s_scr=$(cat "$WORK/stopped.scr.out" "$WORK/stopped.scr.err" | grep -Fc -- "$SCR_LOG" || true)
  [ -z "$s_scr" ] && s_scr=0
  s_sc=$(grep -Fc -- 'try checking in log directory' "$WORK/stopped.sc.err" 2>/dev/null || true)
  [ -z "$s_sc" ] && s_sc=0
  if [ "$s_scr" -ge 1 ] && [ "$s_sc" -ge 1 ]; then
    report PASS stopped-service "(pinned) RMSC still reports the log, upstream reports none"
    pass=$((pass+1))
  else
    report CHANGED stopped-service "(pinned) scr names the log $s_scr time(s), sc reports not-found $s_sc time(s)"
    detail "one of them has changed which case it is in for a stopped service"
    detail "if that was intended, update this case and docs/parity.md together"
    detail "artefacts: stopped.scr.out stopped.scr.err stopped.sc.out stopped.sc.err"
    changed=$((changed+1))
  fi
fi

echo
echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out and .err captured separately for every case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and where it would have to be done instead
#
#   THE SPOOLED-FILE SECTION. Producing a spooled file owned by the SERVICE's
#   job needs a batch_mode service; PASE runs each `system` call in its own job,
#   so a file staged from here belongs to a transient job instead. Upstream's
#   own spooled output is therefore unmeasured, and nothing here asserts
#   agreement with it. Spooled lines are tolerated on stdout and NOTEd when they
#   appear. Closing this needs a batch_mode fixture, not a change to this file.
#
#   INTERLEAVING. The streams are captured separately on purpose, so the
#   relative order of the log line and anything else is thrown away.
#
#   WHETHER THE BLANK LINE IS THE SAME BLANK LINE upstream prints. Both are one
#   empty line at the end of stdout; nothing distinguishes them, and nothing
#   needs to.
#
#   A SERVICE WITH SEVERAL LOGS. Upstream keeps one timestamped file per start
#   and this fixture starts once. Which of several a stopped-and-restarted
#   service would report is not asked here.
#
#   THE BLANK LINE BEYOND TWO MEMBERS, AND BEYOND ONE SHAPE OF GROUP. The group
#   case pins one blank line for a command naming TWO services, one found and
#   one not. That is what separates per-command from per-service, and it is not
#   the same as pinning it for every group: a blank emitted once per PAIR, or
#   once per found member where there happens to be one, would pass here. A
#   three-member group would separate those, and is not run - the cost is
#   another definition and the return is small next to the one-versus-two
#   distinction that has actually been got wrong.
#
#   GROUP ORDER. Which member's line comes first is not asserted. There is one
#   line on each stream in this fixture, so there is no order to get wrong here
#   - but that is a property of the fixture, not something this file checks.
#
# AND ONE THING NOT TO "FIX" ON THE STRENGTH OF THE USAGE TEXT
#
#   Upstream's own usage block reads `loginfo: get log file info for the service
#   (if running)`. THAT PARENTHESIS IS NOT A PRECONDITION IN EITHER
#   IMPLEMENTATION, and both were measured answering for a service that has
#   NEVER BEEN STARTED - it is the case-C fixture here, and both produce the
#   ordinary not-found line and exit 0. Nothing refuses the operation on the
#   grounds that the service is down.
#
#   What "if running" describes, as far as anything measured here shows, is
#   upstream's SCOPE and not its precondition: see the pinned stopped-service
#   case above, where upstream reports no log for a service that is down even
#   though the file is still on disk. So do not read the usage string as a rule
#   and do not reword RMSC's to match one; the rule it looks like it states does
#   not exist.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: loginfo does not report where and how upstream reports"
  exit 1
fi
if [ "$changed" -ne 0 ]; then
  echo "PINNED BEHAVIOUR CHANGED: $changed known difference(s) moved."
  echo "If that was intended, update this script and docs/parity.md together."
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer behaves as recorded."
  echo "Stage 1's expectations rest on that table - re-take it before trusting a"
  echo "pass or acting on a failure."
  exit 1
fi
echo "OK: the log line is on the right stream, says the right thing, and stdout ends with one blank line"
