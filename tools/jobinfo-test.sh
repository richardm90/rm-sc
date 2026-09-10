#!/QOpenSys/pkgs/bin/bash
#
# jobinfo-test.sh - the SHAPE of `jobinfo`'s output: the header, the four-space
# indent, the bare job name, the not-running text, and the ONE trailing blank
# line per COMMAND.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses,
# and modelled on tools/loginfo-test.sh and tools/colour-test.sh.
#
# COLOUR IS NOT HERE. It is case (8) of tools/colour-test.sh's stage 4, and the
# split is deliberate - see WHY THE COLOUR HALF LIVES SOMEWHERE ELSE below.
# Change one of the two files and read the other.
#
# ---------------------------------------------------------------------------
# WHY A NEW FILE
# ---------------------------------------------------------------------------
#
#   fidelity-gate.sh        DOES compare jobinfo, and unlike loginfo it is not
#                           blinded by its own `2>&1`: everything jobinfo prints
#                           is on stdout, so the merge changes nothing. What the
#                           gate cannot reach is the ONE THING most likely to be
#                           got wrong. It sweeps `<op> <service>` - one named
#                           service per invocation, never a `group:` - and the
#                           trailing blank line is emitted once per COMMAND. On
#                           a single service, once-per-command and once-per-
#                           service produce identical output. The gate would
#                           pass a per-service blank on every service it sweeps.
#
#                           It also normalises `[0-9]{6}/` to `NNNNNN/`, which
#                           collapses two distinct jobs into two identical
#                           lines - so a fix that printed the same job twice
#                           would pass there too. Asserted here instead.
#
#   loginfo-test.sh         Asks WHICH STREAM a line lands on. jobinfo has no
#                           stream question at all - header, jobs and the
#                           not-running text are all on stdout in both
#                           implementations - and every mechanism in that file
#                           exists to serve the stream question: the FOUND=yes/
#                           no stream halves, the log-directory discovery, the
#                           timestamped-versus-untimestamped log staging, the
#                           pinned stopped-service divergence.
#
#                           Its FIXTURE is the harder objection. jobinfo needs a
#                           service with TWO JOBS (see rival 1); loginfo's
#                           running fixture has one listener and one job, and
#                           giving it a second criterion would change which case
#                           its own log staging is measuring. And loginfo stages
#                           into $HOME/.sc/services - the shared, real directory
#                           - because upstream must be able to START its
#                           fixture and write a real log there. Nothing here is
#                           ever started, so this file stages privately instead
#                           and cannot leave debris in a directory the gate
#                           reads. Moving jobinfo into loginfo-test.sh would
#                           take on that risk for no reason.
#
#   colour-test.sh          Owns the colour half, and only that - see below.
#
#   error-delivery-test.sh  Which stream a FAILURE lands on and what the exit
#                           status says. jobinfo exits 0 in every state here.
#
#   narration-test.sh       What start and stop SAY. jobinfo is read-only.
#
#   d2-probe.sh             Asserts nothing, deliberately - it captures upstream
#                           text for a person to paste into docs/messages.md.
#
# ---------------------------------------------------------------------------
# WHY THE COLOUR HALF LIVES SOMEWHERE ELSE
# ---------------------------------------------------------------------------
#
# Rival 5 - colour present through a terminal, absent through a pipe - is
# asserted in tools/colour-test.sh, not here, for three reasons and one of them
# is decisive:
#
#   - That file already owns the instrument. The pseudo-terminal, the
#     SSH_TTY half of upstream's colour gate (a PTY alone is not enough and a
#     probe that only allocated one measured upstream emitting nothing at all),
#     the escape counter, the escape stripper and the "re-measure every constant
#     against upstream each run" discipline are all there and were expensive to
#     get right. Copying them here would leave two files disagreeing the day a
#     colour constant moves.
#
#   - Its fixture already presents a RUNNING, a PARTIAL and a NOT RUNNING
#     service in ONE group, which is exactly what jobinfo's colour needs, so the
#     whole case costs FOUR extra invocations there (one PTY and one pipe per
#     implementation) against a second full staging here.
#
#   - DECISIVE: jobinfo's header is the THIRD instance of a construct that file
#     already pins twice. `list` rows are cyan 36; `info`'s header is the same
#     construct and colour-test.sh case (7) exists because RMSC built it by hand
#     instead of going through the shared row builder. jobinfo's `<short>
#     (<friendly>):` is the same construct again, cyan again. That family
#     belongs in one place; splitting it would mean the next person fixing one
#     of the three never finds the other two.
#
# ---------------------------------------------------------------------------
# WHAT IS BEING TESTED - measured against sc 1.7.1 on 10 September 2026
# ---------------------------------------------------------------------------
#
# Everything is on STDOUT. Exit status is 0 in every state below, from both
# implementations. `<short>` is the short service name, `<friendly>` the `name:`
# field, `<job>` a job in `<number>/<user>/<jobname>` form.
#
#   A. RUNNING, TWO JOBS                          (4 stdout lines)
#      sc   `<short> (<friendly>):`
#           `    <job>`                           four spaces, bare job
#           `    <job>`
#           ``                                    ONE blank line
#      scr  `<short>: <job>`
#           `<short>: <job>`                      no header, no indent, no blank
#
#   B. NOT RUNNING                                (3 stdout lines)
#      sc   `<short> (<friendly>):`
#           `    NO JOB INFO (either not running, or running in kernel task)`
#           ``
#      scr  `<short>: not running`
#
#   C. A GROUP, THREE MEMBERS - one with two jobs, two not running
#      sc   each member's header and detail, then ONE BLANK LINE for the whole
#           COMMAND: 8 stdout lines, exactly one of them blank, and it is last
#      scr  4 lines, no blank
#
#   D. A GROUP THAT MATCHES NOTHING               (1 stdout line)
#      sc   stdout is EXACTLY ONE BLANK LINE; a warning naming the group on
#           stderr; exit 0
#      scr  stdout empty; a warning on stderr; exit 0
#
# THE BRIEF SAID A AND B HAD NO BLANK LINE. They do - measured above, and
# docs/messages.md's 3 September capture already showed one for a single
# running service. The brief's own arithmetic for the group case implied it.
# Nothing here rests on the brief's wording: stage 2 re-takes all four from
# upstream on every run.
#
# ---------------------------------------------------------------------------
# THE RIVALS EACH CASE HAS TO RULE OUT
# ---------------------------------------------------------------------------
#
#   1. THE HEADER, ONCE PER SERVICE - and TWO JOBS is what makes that testable.
#      With ONE job, "a header per service" and "a header per job" produce the
#      SAME two lines and no case can separate them. The running fixture
#      therefore has two criteria on two ports held by this script, and stage 0
#      HARD-FAILS if it does not resolve to exactly two distinct jobs. A run
#      that quietly measured one job would report a pass for the rival it
#      exists to rule out.
#
#      The header is also asserted byte for byte - `<short> (<friendly>):` and
#      not `<friendly> (<short>):`, not `<short>:`, not a trailing space.
#
#   2. THE INDENT AND THE BARE JOB NAME. Four spaces, and the job line must NOT
#      carry the service name any more. Asserted three ways, because "the job
#      number appears" is satisfied by the layout being replaced:
#        - the whole line, byte for byte, against a constructed expectation
#        - the short name appears on NO job line
#        - the job SET matches upstream's, compared as a sorted set
#
#   3. THE NOT-RUNNING TEXT, which is a different string from RMSC's current
#      one and is indented like a job line. Byte-exact, indent included.
#
#   4. PER COMMAND, NOT PER SERVICE. No single named service can separate these
#      - one service, one blank, either way - which is exactly how the same
#      change was got wrong in `loginfo` the day before this was written:
#      measured on one named service, implemented per service, printed two
#      blanks for a two-member group, and caught by review rather than by any
#      test.
#
#      TWO cases here separate it, in opposite directions:
#
#        the group     THREE members, one of them with TWO JOBS. Per service
#                      gives 3 blanks, per job gives 2, per pair gives 2; the
#                      command gives 1. Measured: upstream gives 1.
#        the EMPTY     A group matching NO service at all. Per service gives
#        group         none. Upstream still prints one. This is the direction a
#                      three-member group cannot reach, and it costs no fixture
#                      - only an invented group name.
#
#      A MIXED GROUP, not three members in one state. Two not-running members
#      would go green against a blank wrongly emitted inside the RUNNING branch
#      alone, and three running ones against a blank in the not-running branch.
#      One of each fails whichever branch it came back into. Same argument as
#      loginfo-test.sh's group case, and it applies here for one more reason
#      than it did there: `jobinfo`'s two branches print a DIFFERENT NUMBER of
#      lines, so a per-job blank is a third rival that only a member with two
#      jobs can see.
#
#   5. COLOUR - in tools/colour-test.sh. See above.
#
#   AND ONE THE BRIEF DID NOT LIST, which is cheap and worth having: NOTHING
#   MOVES TO STDERR. `loginfo`'s change - moving its not-found line to stderr -
#   landed the day before this file was written, and "the service is not running
#   so say so on stderr" is the obvious next step for someone working through
#   the same list. Upstream puts NO JOB INFO on stdout. Every case here asserts
#   that no line naming the service under test appears on stderr.
#
# ---------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT ASSERTED
# ---------------------------------------------------------------------------
#
#   THE UNKNOWN-SERVICE MESSAGE. Both implementations exit 253 with empty
#   stdout and one line on stderr, and the WORDING differs - upstream `Could
#   not find definition for service 'x'`, RMSC `sc: Unknown service x`. That is
#   the separately recorded D2 message work and is not part of this change, so
#   nothing here asserts the two match. The exit status and the empty stdout
#   are checked, because those are shape.
#
#   THE ORDER OF THE MEMBERS IN A GROUP. Both implementations happened to
#   print three members alphabetically when this was measured, but upstream's
#   iteration order elsewhere is Java HashSet order over strings - docs/parity.md
#   establishes that for `perfinfo`'s job blocks by predicting its output from
#   String.hashCode - and three names is not evidence of a rule. So the group
#   case takes each member's POSITION from the output under test and asserts
#   each member's BLOCK, the whole command's blank line, and that every stdout
#   line belongs to exactly one block. A change in group order does not fail it;
#   a change in what a member prints does.
#
#   STDERR BEING EMPTY. The brief said it was. It is not, and cannot be: both
#   implementations read $HOME/.sc/services as well as any directory staged for
#   them, and this machine's real directory holds definitions that draw load
#   warnings from both. So "stderr is silent" is unassertable here and the
#   assertion is "no line naming the service under test is on stderr", which is
#   the precise question and does not depend on a warning prefix staying put.
#
#   MULTIPLE SERVICES ON ONE COMMAND LINE. There is no such form to test.
#   Measured: `sc jobinfo a b` warns `Argument 'b' unrecognized and will be
#   ignored` and reports only `a`; `scr jobinfo a b` exits 255 with
#   `sc: Unexpected argument b`. So a `group:` IS the only multi-service
#   command, and "per command" and "per group" cannot be told apart. Do not add
#   a case that tries.
#
# ---------------------------------------------------------------------------
# STAGING - and why it is NOT in $HOME/.sc/services
# ---------------------------------------------------------------------------
#
# loginfo-test.sh stages into the user's real services directory and carries an
# ownership marker, a reaper and a teardown that proves itself through
# `scr list`. It has to: upstream must START its fixture and write a real log,
# and $HOME/.sc/services is the only directory upstream would start it from.
#
# NOTHING HERE IS EVER STARTED. The three fixture services have a `start_cmd`
# of `sleep 30` that binds nothing; the RUNNING one is running because THIS
# SCRIPT holds the two ports its criteria name. That is colour-test.sh's trick
# and it is what lets the definitions live in the work directory instead:
#
#     upstream   JAVA_TOOL_OPTIONS='-Dservices.dir=<dir>'
#     RMSC       SC_SERVICES_DIR=<dir>
#
# Both were confirmed to see the staged definitions, and both ALSO read
# $HOME/.sc/services - which is why the stderr rule above is what it is.
#
# The consequence worth stating: a run killed between staging and teardown
# leaves NOTHING in a shared directory. It can leave two listeners holding
# their ports, and the next run's port check fails loudly on exactly that - the
# self-proof teardown needs, without a `scr list` round trip.
#
# NO SERVICE NAME FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The repository
# is public. All four names - three services and a group - are invented here.
#
# Set KEEP=1 to leave the work directory behind.
# Set JOBINFO_DRY=1 to print the staged definitions and stop.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/rmsc-jobinfo.$$}"

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
ls -dt /tmp/rmsc-jobinfo.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
# Setup. Every failure here is fatal and loud. A run that skipped a case
# because a fixture was missing would report success while testing nothing.
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
  "Upstream is not optional. Stage 0 takes the fixture's JOB SET from it -" \
  "the two-jobs proof that makes the header rival testable - and stage 2" \
  "re-takes every expectation in this file from it, so a run without upstream" \
  "would be comparing RMSC against four transcribed constants nobody checked." \
  "Set SC=<path> if it is installed elsewhere."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "Two listeners give the RUNNING fixture its two jobs, and a third process" \
  "proves the other two ports are free. Neither has a shell equivalent here." \
  "Set PY=<path> if python3 lives elsewhere."

mkdir -p "$WORK/services" || setup_fail "cannot create work directory $WORK"
SVCDIR="$WORK/services"

# ---------------------------------------------------------------------------
# The fixture: three invented services and two invented group names.
#
# TWO is the RUNNING one and it has TWO criteria on two ports this script
# holds, so it resolves to two distinct jobs without anything being started.
# NONE and OFF are checked on ports nothing ever binds.
#
# THE CRITERIA MUST STAY DISTINCT. Two definitions sharing one criterion draw a
# conflicting-definitions warning naming both, on stderr - harmless in itself,
# but it would land in the stream every case here reads for "no line naming the
# service under test".
#
# The short names share no substring with each other or with any friendly name,
# so "the short name appears on no job line" is a real question rather than an
# accident of spelling. Same rule narration-test.sh and colour-test.sh state.
#
# Ports: 65340-65343, chosen clear of every other harness in tools/ (which
# occupy 55951, 59491-59492 and 65350-65372).
# ---------------------------------------------------------------------------
TWO=zzj_pair;  TWO_F='Zulu J Pair'
NONE=zzj_idle; NONE_F='Zulu J Idle'
OFF=zzj_shut;  OFF_F='Zulu J Shut'
GROUP=zzjobinfo
EMPTY_GROUP="zzjobinfo_none_$$"   # deliberately matches no definition anywhere

PORT_A=65340
PORT_B=65341
PORT_NONE=65342
PORT_OFF=65343

# PROVE EVERY PORT IS FREE BEFORE STAGING, and fail rather than pick another.
# A held PORT_NONE or PORT_OFF makes a NOT RUNNING fixture RUNNING, and case B
# would then demand the NO JOB INFO line from a service that has a job. A held
# PORT_A or PORT_B leaves the RUNNING fixture PARTIAL with one job, which is
# the one state in which rival 1 cannot be tested at all.
#
# SO_REUSEADDR is deliberately not set here, unlike in the listener: the
# question is whether anyone at all holds the port.
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

for p in "$PORT_A" "$PORT_B" "$PORT_NONE" "$PORT_OFF"; do
  port_free "$p" || setup_fail \
    "port $p is already in use" \
    "" \
    "A service checked on it would report a status this fixture did not intend." \
    "Free it, or move the PORT_* values at the top of this script." \
    "" \
    "A previous run killed before its trap fired is the likeliest cause - its" \
    "listeners sleep for ten minutes."
done

cat > "$WORK/listen.py" <<'PYEOF'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", int(sys.argv[1])))
s.listen(5)
time.sleep(600)
PYEOF

mk() {  # short friendly criteria
  {
    printf 'name: %s\n' "$2"
    printf 'start_cmd: /QOpenSys/usr/bin/sleep 30\n'
    printf 'check_alive: %s\n' "$3"
    printf 'startup_wait_time: 2\n'
    printf 'stop_wait_time: 2\n'
    printf 'groups:\n  - %s\n' "$GROUP"
  } > "$SVCDIR/$1.yaml"
}
mk "$TWO"  "$TWO_F"  "$PORT_A, $PORT_B"
mk "$NONE" "$NONE_F" "$PORT_NONE"
mk "$OFF"  "$OFF_F"  "$PORT_OFF"

cleanup() {
  local p
  for p in $(ps -ef 2>/dev/null | grep -F "$WORK/listen.py" | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}

# EXIT ONLY ONCE, AND DO NOT RESUME INTO A RUN WHOSE FIXTURES ARE GONE.
#
# `trap cleanup EXIT INT TERM` is the shape that looks right and is not: bash
# runs the handler on the signal and then CARRIES ON, so the remaining cases run
# against listeners cleanup has just killed, cleanup fires again on EXIT, and
# the script finishes with STATUS 0 - an interrupted harness reporting SUCCESS
# to verify.sh for stages that never ran. Measured 9 September 2026 in
# colour-test.sh; docs/testing-notes.md carries the account.
on_signal() { trap - EXIT; cleanup; exit 130; }
trap cleanup EXIT
trap on_signal INT TERM

if [ -n "${JOBINFO_DRY:-}" ]; then
  echo "jobinfo-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

# `disown` so the teardown's kill does not print job-control notices onto this
# script's own stderr after the summary line.
"$PY" "$WORK/listen.py" "$PORT_A" >/dev/null 2>&1 &
disown
"$PY" "$WORK/listen.py" "$PORT_B" >/dev/null 2>&1 &
disown
sleep 2

SC_ENV="JAVA_TOOL_OPTIONS=-Dservices.dir=$SVCDIR"
SCR_ENV="SC_SERVICES_DIR=$SVCDIR"

# ===========================================================================
# THE LAYOUT UNDER TEST, IN ONE PLACE.
#
# Every expectation in this file is built from these five lines and nothing
# else. That is deliberate and it is what makes the run falsifiable in both
# directions: replacing this block with RMSC's CURRENT layout turns the whole
# file green against today's build, which is the evidence that the reds below
# are the four measured differences and not something incidental to the
# fixture. The replacement block, for anyone repeating that check, is:
#
#     layout_header() { :; }
#     layout_job()    { printf '%s: %s\n' "$1" "$2"; }
#     layout_nojob()  { printf '%s: not running\n' "$1"; }
#     LAYOUT_BLANK=0
#     LAYOUT_NAME="RMSC's layout before the change"
#
# Keep that copy OUT of the repository - a switch here that flipped the
# expectations would sooner or later be set by someone chasing a green run.
# ===========================================================================
layout_header() { printf '%s (%s):\n' "$1" "$2"; }   # short friendly
layout_job()    { printf '    %s\n' "$2"; }          # short job  (short unused)
layout_nojob()  { printf '    NO JOB INFO (either not running, or running in kernel task)\n'; }
LAYOUT_BLANK=1                                       # trailing blank per COMMAND
LAYOUT_NAME='upstream sc 1.7.1'

# expect_service SHORT FRIENDLY [JOB...]  - one service's block
expect_service() {
  local s="$1" f="$2"; shift 2
  layout_header "$s" "$f"
  if [ "$#" -eq 0 ]; then
    layout_nojob "$s"
  else
    local j
    for j in "$@"; do layout_job "$s" "$j"; done
  fi
}

pass=0; failed=0; changed=0; refdrift=0

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-22s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-22s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-22s %s\n' verdict case detail
  printf '  %-9s %-22s %s\n' --------- ---------------------- ------
}

# wc -l undercounts a final line with no trailing newline. grep -c '' does not.
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }
n_blank() { local n; n=$(grep -c '^$' "$1" 2>/dev/null); [ -n "$n" ] || n=0; echo "$n"; }
mentions() { local n; n=$(grep -Fc -- "$2" "$1" 2>/dev/null); [ -n "$n" ] || n=0; echo "$n"; }

# The three markers a crash leaves. RNX and MCH are matched with their four
# digits so a service description containing the letters cannot match; CEE9901
# is the ILE wrapper the other two arrive inside.
ABEND_RE='CEE9901|RNX[0-9]{4}|MCH[0-9]{4}'

# A job token, in whatever layout: <6 digits>/<user>/<jobname>. FORMAT-
# INDEPENDENT ON PURPOSE. It finds the jobs in `zzj_pair: 123456/U/N` and in
# `    123456/U/N` alike, so the fixture proof and the job-set comparison keep
# working across the change they exist to guard - the trap loginfo-test.sh's
# staging block documents at length.
JOB_TOKEN='[0-9]{6}/[^/[:space:]]+/[^/[:space:]]+'
jobs_in() { grep -oE "$JOB_TOKEN" "$1" 2>/dev/null | sort -u; }

declare -A RC_SAVED=()
# grab TAG ENV BIN ARG...  - one invocation, streams apart. `< /dev/null` on
# every one: `system` in PASE consumes stdin, and this harness is run from a
# pipeline by verify.sh.
grab() {
  local tag="$1" envv="$2" bin="$3"; shift 3
  env "$envv" "$bin" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" </dev/null
  RC_SAVED[$tag]=$?
}

printf 'jobinfo: the header, the indent, the bare job name and the blank line\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" \
  "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'layout asserted: %s\n' "$LAYOUT_NAME"
printf 'fixtures: %s (2 jobs), %s and %s (not running), group:%s\n\n' \
  "$TWO" "$NONE" "$OFF" "$GROUP"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture. Nothing below is evidence until every row passes"
echo
heading
# ---------------------------------------------------------------------------

hard_fail() {
  report FAIL "$1" "FIXTURE DID NOT TAKE"
  shift
  local p; for p in "$@"; do detail "$p"; done
  detail "nothing below this line would be evidence for anything"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
  echo "FAILED: no usable fixture"
  exit 1
}

# (a) THE DEFINITIONS LOADED, AND EACH IS IN THE STATUS ITS CASE NEEDS.
#
# Not "three rows came back" - which status went with which name. Every case
# below is of the form "a service in THIS state prints THIS", so a fixture that
# produced three rows in the wrong three states would fail every case while the
# implementation was correct.
grab fx.check "$SCR_ENV" "$SCR" check "group:$GROUP"
for pair in "$TWO:RUNNING" "$NONE:NOT RUNNING" "$OFF:NOT RUNNING"; do
  s="${pair%%:*}"; want="${pair#*:}"
  grep -q "^  $want *| $s (" "$WORK/fx.check.out" || hard_fail staged-statuses \
    "$s is not '$want'" \
    "got: $(grep -F " $s (" "$WORK/fx.check.out" || echo '(no row at all)')" \
    "either a port is held by something else, or the definitions did not load"
done
report PASS staged-statuses "$TWO RUNNING, $NONE and $OFF NOT RUNNING"
pass=$((pass+1))

# (b) THE RUNNING FIXTURE HAS EXACTLY TWO DISTINCT JOBS.
#
# THE ONE THAT MAKES THIS FILE HONEST, and the reason it is a hard failure
# rather than a note. With one job, "a header per service" and "a header per
# job" produce the same two lines, and rival 1 - the whole reason the header is
# under test - cannot be separated by any case in this file. A run that
# measured one job would go green having tested the thing it exists to test in
# a form where the answer cannot be wrong.
#
# TAKEN FROM UPSTREAM, which is the reference and does not change, and read
# with the format-independent token regex so it does not presuppose either
# layout.
grab fx.jobs "$SC_ENV" "$SC" jobinfo "$TWO"
FIXTURE_JOBS=$(jobs_in "$WORK/fx.jobs.out")
n_fx=$(printf '%s\n' "$FIXTURE_JOBS" | grep -c '[0-9]' || true)
[ -n "$n_fx" ] || n_fx=0
[ "$n_fx" -eq 2 ] || hard_fail two-distinct-jobs \
  "upstream reports $n_fx distinct job(s) for $TWO, wanted exactly 2" \
  "found: $(printf '%s' "$FIXTURE_JOBS" | tr '\n' ' ')" \
  "with one job, a header per SERVICE and a header per JOB are the same two" \
  "lines, and rival 1 cannot be separated by anything in this file" \
  "the two listeners on ports $PORT_A and $PORT_B did not resolve to two jobs"
report PASS two-distinct-jobs "$TWO resolves to 2 distinct jobs - rival 1 is separable"
pass=$((pass+1))

# (c) THE GROUP HOLDS ALL THREE, AND THE EMPTY GROUP HOLDS NONE.
#
# Without the first, the group case would be asserting against a command that
# matched fewer members than it thinks and would fail saying the blank line was
# wrong. Without the second, the empty-group case would be measuring a group
# that had members - and it is the only case here that can see a blank emitted
# for a command that printed no service at all.
gm=$(grep -cE "^  .* \| ($TWO|$NONE|$OFF) \(" "$WORK/fx.check.out" || true)
[ -n "$gm" ] || gm=0
[ "$gm" -eq 3 ] || hard_fail group-holds-three \
  "group:$GROUP holds $gm of the 3 fixtures" \
  "the group case would be measuring a command that matched something else"
grab fx.empty "$SCR_ENV" "$SCR" check "group:$EMPTY_GROUP"
[ "$(count_lines "$WORK/fx.empty.out")" -le 1 ] || hard_fail empty-group-is-empty \
  "group:$EMPTY_GROUP matches $(count_lines "$WORK/fx.empty.out") row(s) of \`check\`" \
  "it is invented from this script's PID and must match nothing"
report PASS group-membership "group:$GROUP holds all three; group:$EMPTY_GROUP holds none"
pass=$((pass+1))

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the four cases, against $LAYOUT_NAME"
echo
heading
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# assert_stdout TAG BASIS WANTFILE NAME...
#
# The whole of stdout, byte for byte, against a constructed expectation, plus
# the three things a diff alone would not say plainly:
#
#   - exit 0
#   - no line naming any service under test on stderr
#   - a crash reported as a crash rather than as a formatting difference
#
# "STDOUT IS EXACTLY THESE LINES" IS THE STRONGEST FORM AND IT IS THE RIGHT ONE
# HERE, which is worth saying because loginfo-test.sh deliberately does NOT use
# it: `loginfo` has an optional spooled-file section, so pinning its whole
# stdout would fail quoting a line that has nothing to do with the log. jobinfo
# has no optional section in either implementation - measured in four states -
# so there is nothing for a shape policy to protect and every extra line is a
# finding.
# ---------------------------------------------------------------------------
assert_stdout() {
  local tag="$1" basis="$2" want="$3"; shift 3
  local o="$WORK/$tag.out" e="$WORK/$tag.err"
  local problems=() n p

  if grep -qE "$ABEND_RE" "$o" "$e" 2>/dev/null; then
    report FAIL "$tag" "($basis) ABEND: $(grep -hE -m1 "$ABEND_RE" "$o" "$e")"
    detail "artefacts: $tag.out $tag.err"
    failed=$((failed+1))
    return 1
  fi

  [ "${RC_SAVED[$tag]:-1}" -eq 0 ] || \
    problems+=("exit ${RC_SAVED[$tag]}, wanted 0 - jobinfo is a report and succeeds in every state here")

  if ! diff -u "$want" "$o" > "$WORK/$tag.diff" 2>&1; then
    problems+=("stdout is not what $LAYOUT_NAME prints (-want +got):")
    while IFS= read -r p; do problems+=("  $p"); done < "$WORK/$tag.diff"
  fi

  for p in "$@"; do
    n=$(mentions "$e" "$p")
    [ "$n" -eq 0 ] || problems+=("$n stderr line(s) name '$p' - jobinfo prints on STDOUT only: $(grep -F -m1 -- "$p" "$e")")
  done

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) exit 0, $(count_lines "$o") stdout line(s), $(n_blank "$o") blank"
    pass=$((pass+1))
    return 0
  fi
  report FAIL "$tag" "($basis)"
  for p in "${problems[@]}"; do detail "$p"; done
  detail "artefacts: $tag.out $tag.err $tag.diff"
  failed=$((failed+1))
  return 1
}

# ---------------------------------------------------------------------------
# CASE A - RUNNING, TWO JOBS.
#
# Rivals 1 and 2. One header for two jobs; each job line four spaces then the
# bare job; one blank line at the end.
#
# THE JOB LINES ARE BUILT FROM RMSC'S OWN JOB NUMBERS, sorted ascending, and
# that is not circular - it is the only division that keeps two rules in two
# rows. The numbers are read out with the format-independent token regex, so
# what is compared is the LAYOUT round them: indent, order, the absence of the
# service name. WHICH jobs they are is the separate row below, against
# upstream. Build the expectation from upstream's numbers instead and a wrong
# job set fails the layout case, quoting a diff about indentation.
#
# ASCENDING is RMSC's own decided order, not upstream's - see stage 3.
# ---------------------------------------------------------------------------
grab two "$SCR_ENV" "$SCR" jobinfo "$TWO"
mapfile -t TWO_JOBS < <(jobs_in "$WORK/two.out" | sort)
{
  expect_service "$TWO" "$TWO_F" "${TWO_JOBS[@]}"
  [ "$LAYOUT_BLANK" -eq 1 ] && echo
} > "$WORK/two.want"
assert_stdout two measured "$WORK/two.want" "$TWO"

# THE JOB SET, against upstream, as a SORTED SET.
#
# Compared as a set and not in order on purpose: docs/parity.md records that
# upstream's job order is Java HashSet iteration order over the job-number
# strings and reshuffles on every restart, where RMSC sorts ascending. Measured
# here on 10 September 2026, two runs minutes apart, upstream gave the same two
# jobs first ascending and then descending. There is no order there to match.
#
# SEPARATING VALUE: this is the row that a layout comparison cannot make. The
# whole-stdout diff above is built from RMSC's own numbers, so it would pass an
# implementation that listed the wrong two jobs, or the same job twice - which
# the fidelity gate would also pass, because it normalises every job number to
# NNNNNN/ before diffing.
sc_set=$(jobs_in "$WORK/fx.jobs.out")
scr_set=$(printf '%s\n' "${TWO_JOBS[@]}" | sort -u)
if [ "$sc_set" = "$scr_set" ]; then
  report PASS two-job-set "(measured) the same 2 jobs upstream names, as a set"
  pass=$((pass+1))
else
  report FAIL two-job-set "(measured) RMSC and upstream do not name the same jobs"
  detail "upstream: $(printf '%s' "$sc_set" | tr '\n' ' ')"
  detail "RMSC:     $(printf '%s' "$scr_set" | tr '\n' ' ')"
  detail "the layout case above is built from RMSC's own numbers and cannot see this"
  failed=$((failed+1))
fi

# THE SHORT NAME IS ON NO JOB LINE.
#
# SEPARATING VALUE: stated separately from the byte diff because it is the rival
# the brief names, and the diff would report it as "line 2 differs". A case
# asserting only that the job NUMBER appears would pass the layout being
# replaced; this one fails the moment `<short>: ` survives anywhere on a job
# line.
#
# THE WANTED ANSWER IS ASKED OF THE LAYOUT BLOCK rather than hard-coded, so
# that this row moves with the block like every other expectation here. That is
# not cosmetic: it is what lets the whole file be pointed at RMSC's CURRENT
# layout and go green, which is the control that says the reds above are the
# measured differences and not something incidental to the fixture. A row
# hard-coded to the target would stay red in that control and the control would
# prove less.
if layout_job "$TWO" '111111/AAA/BBB' | grep -Fq -- "$TWO"; then
  LAYOUT_JOB_HAS_NAME=1
else
  LAYOUT_JOB_HAS_NAME=0
fi
onjob=$(grep -cE "$JOB_TOKEN" "$WORK/two.out" || true); [ -n "$onjob" ] || onjob=0
named=$(grep -E "$JOB_TOKEN" "$WORK/two.out" | grep -Fc -- "$TWO" || true)
[ -n "$named" ] || named=0
if [ "$LAYOUT_JOB_HAS_NAME" -eq 0 ]; then
  want_named=0; rule="no job line carries the service name"
else
  want_named=$onjob; rule="every job line carries the service name"
fi
if [ "$named" -eq "$want_named" ]; then
  report PASS bare-job-lines "(measured) $rule"
  pass=$((pass+1))
else
  report FAIL bare-job-lines "(measured) $named of $onjob job line(s) carry '$TWO', wanted $want_named"
  detail "got: $(grep -E "$JOB_TOKEN" "$WORK/two.out" | head -n 1)"
  detail "upstream prints the job alone, indented four spaces, once the header names the service"
  failed=$((failed+1))
fi

# ---------------------------------------------------------------------------
# CASE B - NOT RUNNING.
#
# Rival 3, and the header again in a state where there is no job to hang it on.
# The NO JOB INFO text is indented like a job line and is a different string
# from RMSC's `not running`, so this case fails today for two reasons and both
# are in the diff.
# ---------------------------------------------------------------------------
grab none "$SCR_ENV" "$SCR" jobinfo "$NONE"
{
  expect_service "$NONE" "$NONE_F"
  [ "$LAYOUT_BLANK" -eq 1 ] && echo
} > "$WORK/none.want"
assert_stdout none measured "$WORK/none.want" "$NONE"

# ---------------------------------------------------------------------------
# CASE C - THE GROUP. Rival 4, and the only case here that can see it.
#
# THREE MEMBERS, MIXED: one with two jobs and two not running. The counting is
# what does the work:
#
#     per COMMAND (correct)   1 blank
#     per SERVICE             3 blanks
#     per JOB                 2 blanks
#     per PAIR of services    2 blanks
#
# Every case above names one service, where all four of those produce one blank
# and nothing can be told apart. Two members would separate per-service but not
# per-job; three in the same state would separate neither a blank wrongly left
# in the branch they are not in.
#
# MEMBER ORDER IS TAKEN FROM THE OUTPUT UNDER TEST, not asserted - see WHAT IS
# DELIBERATELY NOT ASSERTED. Each member's block is built and then ordered by
# where that member's name first appears in RMSC's own stdout, so a change in
# group order does not fail this case while a change in what a member prints
# does. A member that appears nowhere sorts last and shows in the diff as an
# absent block, which is the right way for that to fail.
# ---------------------------------------------------------------------------
grab group "$SCR_ENV" "$SCR" jobinfo "group:$GROUP"

first_at() {  # file short -> line number of first mention, or 999999
  local n
  n=$(grep -n -F -m1 -- "$2" "$1" 2>/dev/null | cut -d: -f1)
  [ -n "$n" ] || n=999999
  echo "$n"
}
{
  for entry in \
    "$(first_at "$WORK/group.out" "$TWO"):$TWO" \
    "$(first_at "$WORK/group.out" "$NONE"):$NONE" \
    "$(first_at "$WORK/group.out" "$OFF"):$OFF"
  do echo "$entry"; done
} | sort -t: -k1,1n | cut -d: -f2 > "$WORK/group.order"

: > "$WORK/group.want"
while IFS= read -r m; do
  case "$m" in
    "$TWO")  expect_service "$TWO"  "$TWO_F" "${TWO_JOBS[@]}" ;;
    "$NONE") expect_service "$NONE" "$NONE_F" ;;
    "$OFF")  expect_service "$OFF"  "$OFF_F" ;;
  esac
done < "$WORK/group.order" >> "$WORK/group.want"
[ "$LAYOUT_BLANK" -eq 1 ] && echo >> "$WORK/group.want"

assert_stdout group measured "$WORK/group.want" "$TWO" "$NONE" "$OFF"

# The blank count on its own, named, because the diff above reports it as a
# missing or extra line at some position and this is the rule that matters.
gb=$(n_blank "$WORK/group.out")
gwant=$LAYOUT_BLANK
if [ "$gb" -eq "$gwant" ]; then
  report PASS group-blank-per-command \
    "(measured) $gb blank line(s) for a 3-member command - per COMMAND, not per service or per job"
  pass=$((pass+1))
else
  report FAIL group-blank-per-command "(measured) $gb blank line(s), wanted $gwant"
  detail "3 would mean it is emitted per SERVICE; 2, per JOB or per PAIR"
  detail "no single-service case in this file can tell those apart - this one can"
  failed=$((failed+1))
fi

# ---------------------------------------------------------------------------
# CASE D - A GROUP THAT MATCHES NOTHING.
#
# The other direction of rival 4, and the one a three-member group cannot
# reach. Upstream prints ONE BLANK LINE and nothing else: the blank belongs to
# the COMMAND, and it is emitted even though no service was printed. An
# implementation that emitted it after the last service - which passes every
# other case in this file - prints nothing here.
#
# THE WARNING IS NOT ASSERTED. Both implementations put a line naming the group
# on stderr and the wording differs; that is the D2 message work. What is
# asserted is stdout and the exit status.
# ---------------------------------------------------------------------------
grab empty "$SCR_ENV" "$SCR" jobinfo "group:$EMPTY_GROUP"
{ [ "$LAYOUT_BLANK" -eq 1 ] && echo; } > "$WORK/empty.want"
assert_stdout empty measured "$WORK/empty.want"

echo
# ---------------------------------------------------------------------------
echo "== stage 2: upstream reference, re-taken in the same fixture states"
echo "   (stage 1's expectations are only as good as this table; a REFDRIFT"
echo "    means the reference moved, not that RMSC regressed)"
echo
heading
# ---------------------------------------------------------------------------
#
# EVERY EXPECTATION IN STAGE 1 IS A TRANSCRIPTION - five lines of layout typed
# from a capture - and a wrong transcription fails RMSC for agreeing with
# upstream. So upstream is run through the SAME expectation builder, in the
# SAME fixture states, in this run.
#
# It is not a byte diff of the two implementations. Two things legitimately
# differ and neither is a defect: the job ORDER within a service (upstream
# HashSet, RMSC ascending - stage 3) and, for a group, the member order if
# upstream's ever stops being alphabetical. So upstream's capture is compared
# against the same constructed blocks, ordered by upstream's own output.

sc_ref() {  # tag wantfile
  local tag="$1" want="$2" why=""
  [ "${RC_SAVED[$tag]:-1}" -eq 0 ] || why="$why exit=${RC_SAVED[$tag]}(wanted 0)"
  if ! diff -u "$want" "$WORK/$tag.out" > "$WORK/$tag.diff" 2>&1; then
    why="$why stdout-differs"
  fi
  if [ -z "$why" ]; then
    report PASS "sc:${tag#sc.}" "as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:${tag#sc.}" "$why"
    while IFS= read -r l; do detail "  $l"; done < "$WORK/$tag.diff"
    detail "artefacts: $tag.out $tag.err $tag.diff"
    refdrift=$((refdrift+1))
  fi
}

# Case A. Upstream's own capture was already taken in stage 0 as fx.jobs; it is
# re-used rather than re-run, which saves a JVM start and measures the same
# thing. Its job lines are built from upstream's OWN order, since that order is
# not something this file asserts.
mapfile -t SC_TWO_JOBS < <(grep -oE "$JOB_TOKEN" "$WORK/fx.jobs.out")
{
  expect_service "$TWO" "$TWO_F" "${SC_TWO_JOBS[@]}"
  [ "$LAYOUT_BLANK" -eq 1 ] && echo
} > "$WORK/fx.jobs.want"
sc_ref fx.jobs "$WORK/fx.jobs.want"

grab sc.none "$SC_ENV" "$SC" jobinfo "$NONE"
{
  expect_service "$NONE" "$NONE_F"
  [ "$LAYOUT_BLANK" -eq 1 ] && echo
} > "$WORK/sc.none.want"
sc_ref sc.none "$WORK/sc.none.want"

grab sc.group "$SC_ENV" "$SC" jobinfo "group:$GROUP"
mapfile -t SC_GRP_JOBS < <(grep -oE "$JOB_TOKEN" "$WORK/sc.group.out")
{
  for entry in \
    "$(first_at "$WORK/sc.group.out" "$TWO"):$TWO" \
    "$(first_at "$WORK/sc.group.out" "$NONE"):$NONE" \
    "$(first_at "$WORK/sc.group.out" "$OFF"):$OFF"
  do echo "$entry"; done
} | sort -t: -k1,1n | cut -d: -f2 > "$WORK/sc.group.order"
: > "$WORK/sc.group.want"
while IFS= read -r m; do
  case "$m" in
    "$TWO")  expect_service "$TWO"  "$TWO_F" "${SC_GRP_JOBS[@]}" ;;
    "$NONE") expect_service "$NONE" "$NONE_F" ;;
    "$OFF")  expect_service "$OFF"  "$OFF_F" ;;
  esac
done < "$WORK/sc.group.order" >> "$WORK/sc.group.want"
[ "$LAYOUT_BLANK" -eq 1 ] && echo >> "$WORK/sc.group.want"
sc_ref sc.group "$WORK/sc.group.want"

grab sc.empty "$SC_ENV" "$SC" jobinfo "group:$EMPTY_GROUP"
{ [ "$LAYOUT_BLANK" -eq 1 ] && echo; } > "$WORK/sc.empty.want"
sc_ref sc.empty "$WORK/sc.empty.want"

# THE UNKNOWN SERVICE, as SHAPE only. Not the wording - that is the D2 message
# work and the two deliberately differ today. What is worth pinning is that
# both refuse the same way: empty stdout, one line on stderr, exit 253. A
# change here would mean the not-found path had started printing on stdout,
# which is the blank line's business.
grab sc.unknown  "$SC_ENV"  "$SC"  jobinfo "zzj_no_such_$$"
grab scr.unknown "$SCR_ENV" "$SCR" jobinfo "zzj_no_such_$$"
u_why=""
[ "${RC_SAVED[sc.unknown]}" -eq 253 ]  || u_why="$u_why sc-exit=${RC_SAVED[sc.unknown]}(wanted 253)"
[ "${RC_SAVED[scr.unknown]}" -eq 253 ] || u_why="$u_why scr-exit=${RC_SAVED[scr.unknown]}(wanted 253)"
[ "$(count_lines "$WORK/sc.unknown.out")" -eq 0 ]  || u_why="$u_why sc-stdout-not-empty"
[ "$(count_lines "$WORK/scr.unknown.out")" -eq 0 ] || u_why="$u_why scr-stdout-not-empty"
if [ -z "$u_why" ]; then
  report PASS unknown-service-shape "(measured) both: empty stdout, exit 253 - wording NOT asserted"
  pass=$((pass+1))
else
  report FAIL unknown-service-shape "$u_why"
  detail "the WORDING is the separate D2 item and is deliberately not compared"
  detail "this row is about shape: nothing on stdout, and the same refusal status"
  failed=$((failed+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 3: a decided difference, pinned so a change to it is visible"
echo
heading
# ---------------------------------------------------------------------------

# PINNED - THE ORDER OF THE JOB LINES WITHIN A SERVICE.
#
#   upstream sc:  Java HashSet iteration order over the job-name strings. It is
#                 a function of the job numbers, so it reshuffles on every
#                 restart. docs/parity.md establishes this for `perfinfo` by
#                 predicting upstream's output from String.hashCode, and records
#                 that `jobinfo` has always shared it.
#   RMSC:         ascending by job number.
#
# RMSC's is the decided behaviour: there is no order in upstream's to match.
# The risk this row guards is specific - somebody bringing jobinfo's LAYOUT to
# upstream's may reasonably bring its ORDER too, and that would be a second,
# unasked-for change arriving inside the first.
#
# WHAT THIS ROW CAN AND CANNOT SEPARATE, MEASURED EACH RUN. With two jobs,
# upstream's order is ascending about half the time. When it is, this case
# cannot tell "RMSC sorts ascending" from "RMSC copied upstream" - so the run
# SAYS which case it was in rather than claiming a separation it did not make.
# Both were seen on 10 September 2026, minutes apart, on this same fixture.
asc=$(printf '%s\n' "${TWO_JOBS[@]}" | sort)
got=$(printf '%s\n' "${TWO_JOBS[@]}")
sc_order=$(printf '%s\n' "${SC_TWO_JOBS[@]}")
if [ "$got" = "$asc" ]; then
  if [ "$sc_order" = "$asc" ]; then
    report PASS job-order-ascending \
      "(pinned) RMSC ascending - but upstream was ascending too this run, so this row separated nothing"
  else
    report PASS job-order-ascending \
      "(pinned) RMSC ascending where upstream was not - RMSC's own order, kept deliberately"
  fi
  pass=$((pass+1))
else
  report CHANGED job-order-ascending "(pinned) RMSC's job order is no longer ascending"
  detail "RMSC:     $(printf '%s' "$got" | tr '\n' ' ')"
  detail "upstream: $(printf '%s' "$sc_order" | tr '\n' ' ')"
  detail "if RMSC now matches upstream, someone has adopted a HashSet order that reshuffles"
  detail "if that was intended, update this case and docs/parity.md together"
  changed=$((changed+1))
fi

echo
echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out, .err and .diff per case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and where it would have to be done instead
#
#   COLOUR. tools/colour-test.sh stage 4 case (8). It needs a pseudo-terminal
#   and SSH_TTY in the child's environment, both of which live there.
#
#   THE ORDER OF THE MEMBERS IN A GROUP. Taken from the output under test, not
#   asserted - see the header. Settling it needs upstream's iteration order
#   established the way docs/parity.md established it for perfinfo, which is a
#   bytecode question and not a test one.
#
#   A SERVICE RUNNING IN A KERNEL TASK, which upstream's not-running text names
#   as the other reason for NO JOB INFO. Nothing here can stage one, so the two
#   halves of that sentence are asserted as one string and only the
#   not-running half is ever exercised.
#
#   WHETHER THE BLANK LINE IS THE SAME BLANK LINE upstream prints. Both are one
#   empty line at the end of stdout; nothing distinguishes them.
#
#   A GROUP LARGER THAN THREE, OR ONE WITH TWO MULTI-JOB MEMBERS. Three
#   members, one of them with two jobs, separates per-command from per-service,
#   per-job and per-pair. A blank emitted once per THREE services would pass -
#   that is the next rival out, and it is contrived enough not to be worth a
#   fourth definition.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: jobinfo does not print what upstream prints"
  exit 1
fi
if [ "$changed" -ne 0 ]; then
  echo "PINNED BEHAVIOUR CHANGED: $changed decided difference(s) moved."
  echo "If that was intended, update this script and docs/parity.md together."
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer behaves as recorded."
  echo "Stage 1's expectations rest on that table - re-take it before trusting a"
  echo "pass or acting on a failure."
  exit 1
fi
echo "OK: header, indent, bare job names, and one blank line per command"
