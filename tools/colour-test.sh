#!/QOpenSys/pkgs/bin/bash
#
# colour-test.sh - what `check`, `list` and `groups` look like ON A TERMINAL,
# and where RMSC's colour differs from upstream's.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh, tools/narration-test.sh
# and tools/error-delivery-test.sh, and modelled on the second of those.
#
# WHY THIS EXISTS, AND WHY IT WAS THOUGHT IMPOSSIBLE. docs/parity.md says of the
# one colour difference it records: "it needs a person looking at a terminal
# rather than a diff - no byte-exact comparison can reach it." That is wrong,
# and the reason it looked true is worth writing down, because it is the whole
# trick this file turns:
#
#   Upstream's colour gate is a static initialiser in
#   com.github.theprez.jcmdutils.StringUtils, and it asks THREE questions:
#
#       System.console() != null
#       AND System.getenv("SSH_TTY") is non-empty
#       AND NOT Boolean.getBoolean("jcmdutils.disablecolors")
#
#   A pseudo-terminal alone satisfies the first and not the second, so a probe
#   that only allocated a PTY measured upstream emitting no escapes at all -
#   which looks exactly like "colour cannot be captured". SSH_TTY has to be set
#   in the child's environment as well. Both are done below, and stage 0 proves
#   upstream really did colour something before any comparison is believed.
#
# RMSC'S GATE IS A DIFFERENT GATE, AND IT IS IN THE SHELL. scripts/scr adds
# --colors when `[ -t 1 ]`; SCOUT_is_tty is a stub that always answers false, so
# RMSC never asks the question itself. The two implementations therefore agree
# on a PTY and on a pipe for different reasons, and the second half of stage 1
# is the only thing pinning that they agree at all.
#
# ITS OTHER HALF IS qtestsrc/SCOUT.TEST.RPGLE, and the split is the same one
# narration-test.sh describes:
#
#   SCOUT.TEST      which bytes a row is made of, with colour forced on by
#                   SCOUT_set_colour - every escape sequence and its position
#   this script     whether a terminal turns colour on at all, whether a pipe
#                   turns it off, and whether the bytes match UPSTREAM's
#
# Neither side can do the other's job. SCOUT_set_colour(true) inside an RPGUnit
# job proves nothing about `[ -t 1 ]`, and no shell can call SCOUT_check_row.
#
# THE FIXTURE FAILURE THAT WOULD MAKE THIS FILE LIE. If the PTY does not take,
# or SSH_TTY does not reach the child, upstream emits no escapes - and RMSC,
# whose own gate would have failed for the same reason, emits none either. The
# byte comparison then PASSES, on two identical uncoloured outputs, and reports
# full colour parity having measured nothing. That is why stage 0 hard-fails
# unless upstream is seen colouring a row, and hard-fails again unless RMSC is
# seen colouring one. Neither is a skip.
#
# A DIFFERENCE THIS FILE MEASURES AND DELIBERATELY DOES NOT ASSERT. The two
# gates do not agree, and the case where they disagree is reachable:
#
#   PTY, SSH_TTY set      upstream colours      RMSC colours
#   PTY, SSH_TTY unset    upstream MONOCHROME   RMSC still colours
#   pipe                  upstream monochrome   RMSC monochrome
#
# Measured 4 September 2026 with `check` through this script's PTY: 12 escape
# bytes from upstream and 6 from RMSC with SSH_TTY set, 0 and 6 with it unset.
# So on a terminal that is not an SSH session - a local PASE shell, a `su`, a
# harness that allocates a PTY of its own - upstream goes monochrome and RMSC
# does not.
#
# DECIDED 5 September 2026: RMSC KEEPS ITS OWN GATE, and the divergence is
# asserted below rather than merely noted. Upstream's SSH_TTY test reads as a
# proxy for "is this interactive" written by someone who only ever ran it over
# ssh - System.console() already answers that question, and the second test only
# removes cases. Matching it would mean RMSC deliberately going monochrome on a
# working console, which is a worse outcome than the divergence.
#
# It cannot touch the byte-exact contract: both implementations go monochrome on
# a pipe, and the consumer redirects. What is at stake is only what a person at a
# non-ssh terminal sees.
#
# So this is now a CHOICE the harness pins, not a gap it tolerates. The case
# below fails if RMSC ever stops colouring without SSH_TTY - which would mean
# someone had "fixed" it towards upstream - and equally if upstream starts.
# docs/parity.md carries it under the deliberate departures.
#
# Set COLOUR_DRY=1 to see the staged definitions without running anything.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/colour-test.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the rule narration-test.sh and
# fidelity-gate.sh both carry. The work directory is kept deliberately so a
# failure can be inspected, a trap does not run if the process is killed, and
# thirty-six abandoned directories accumulated under /tmp last time nobody
# swept. The two most recent are kept; only this script's own are touched.
# NEVER DELETE A DIRECTORY SOMETHING IS STILL USING. The name carries the PID
# that made it - WORK defaults to <prefix>.$$ - so ownership needs no
# bookkeeping, only `kill -0` on the suffix.
#
# Without this, two runs at once leave three directories and the oldest still
# RUNNING one is removed underneath itself. It then fails on missing capture
# files, and it does not fail saying its files vanished - it fails looking like
# a fidelity regression. A harness that reports a defect in the thing under
# test when the fault is its own cleanup is worse than one that leaks debris.
#
# The two failure modes are not symmetrical, which is what decides the rule. A
# recycled PID means skipping a delete that could have been made: debris kept.
# Getting it wrong the other way destroys a run in flight. So anything that
# might be alive is left alone, and so is any name whose suffix is not a plain
# number - an overridden WORK= belongs to whoever set it, and this cannot know
# who that is.
#
# The same block appears in every script in tools/ that keeps its work directory
# and names it by PID. This file already had it right at the top and wrong at the
# bottom, which is worth noticing before writing the next one: the opening line
# above names narration-test.sh and fidelity-gate.sh as the scripts carrying the
# rule - a membership - while this line used to say "all five harnesses", a count
# that was wrong in both directions (load-warning-test.sh is a harness with no
# copy, fidelity-gate.sh has a copy and is not a harness). Prefer the opening
# line's habit.
#
# Deliberately duplicated rather than shared: each is deployed and run
# standalone, and a shared file would be a dependency that costs more than the
# repetition does. Change one, change all of them.
ls -dt /tmp/colour-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in
    ''|*[!0-9]*) continue ;;
  esac
  # `kill -0` fails two ways and they mean opposite things: ESRCH is "no such
  # process", EPERM is "alive, but not yours". Testing only the exit status
  # treats another user's LIVE run as dead and deletes its work directory -
  # the exact failure this block exists to prevent, on a shared box.
  if kill_err=$(kill -0 "$owner" 2>&1); then
    continue
  fi
  case "$kill_err" in
    *ermitted*|*EPERM*|*ermission*) continue ;;
  esac
  rm -rf "$stale" 2>/dev/null
done

SVCDIR="$WORK/services"

# Three ports, high and contiguous, every one proved free before anything is
# staged. Two are bound by THIS SCRIPT rather than by a service: the fixture has
# to present all three statuses to one `check`, and the only way to have a
# RUNNING service and a PARTIAL service without starting anything is to hold
# their satisfied criteria here. PORT_DOWN is the one nothing ever binds.
PORT_UP=65370
PORT_HALF=65371
PORT_DOWN=65372

export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every failure here is fatal and loud.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory. It also" \
  "tests scripts/scr ITSELF - the \`[ -t 1 ]\` gate on line 22 is where RMSC" \
  "decides about colour - so the wrapper is under test here, not merely used."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Every expectation in this file is a colour CODE, and a code transcribed" \
  "from a capture into a comment is exactly the kind of value that goes stale" \
  "silently. Stage 2 re-measures all of them against upstream on each run, so" \
  "running without upstream would leave them unchecked."

[ -x "$PY" ] || setup_fail \
  "python3 is not executable at: $PY" \
  "" \
  "It is needed twice: to allocate the pseudo-terminal the whole file depends" \
  "on, and to hold the two ports that give the fixture a RUNNING and a PARTIAL" \
  "service. Neither has a shell equivalent here."

mkdir -p "$SVCDIR" || setup_fail "cannot create work directory $SVCDIR"

# ---------------------------------------------------------------------------
# The pseudo-terminal.
#
# NOT NAMED pty.py, AND THAT IS NOT A STYLE CHOICE. Python puts a script's own
# directory at the front of sys.path, so a file called pty.py that does
# `import pty` imports ITSELF, finds no spawn(), and dies with an AttributeError
# that reads like a broken interpreter. An hour went into that once.
#
# stdout AND stderr of the child both land on the master here, so the child is
# run through `sh -c '... 2>FILE'` and stderr is split off inside it. That
# matters more than it looks: upstream's services directory is a JVM property
# and has to be passed through JAVA_TOOL_OPTIONS, which makes the JVM announce
# itself with "Picked up JAVA_TOOL_OPTIONS: ..." on stderr. Merged, that line
# would sit in the middle of the captured stdout and every diff below would be
# about it.
#
# The tty driver turns every LF into CRLF on the way out, so the capture is
# converted back before anything compares it. Only \r\n is touched: a trailing
# SPACE is part of the check contract and must survive untouched.
# ---------------------------------------------------------------------------
cat > "$WORK/ptycap.py" <<'PEOF'
import os, sys, pty

out = sys.argv[1]
argv = sys.argv[2:]
if argv and argv[0] == '--':
    argv = argv[1:]

chunks = []
def reader(fd):
    d = os.read(fd, 65536)
    chunks.append(d)
    return d

pty.spawn(argv, reader)
data = b''.join(chunks).replace(b'\r\n', b'\n')
with open(out, 'wb') as f:
    f.write(data)
PEOF

cat > "$WORK/listen.py" <<'PEOF'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", int(sys.argv[1])))
s.listen(5)
time.sleep(900)
PEOF

# PROVE EVERY PORT IS FREE BEFORE STAGING, and fail rather than pick another.
# The reasoning is narration-test.sh's: a port already held makes the service
# checked on it report the wrong STATUS, and since this file's whole subject is
# which colour goes with which status, every case would then be comparing the
# right bytes against the wrong row and failing believably.
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

for p in "$PORT_UP" "$PORT_HALF" "$PORT_DOWN"; do
  port_free "$p" || setup_fail \
    "port $p is already in use" \
    "" \
    "A service checked on it would report a status this fixture did not intend," \
    "and every colour case would then be asserting the right code against the" \
    "wrong row. Free it, or move the PORT_* values at the top of this script." \
    "" \
    "A previous run killed before its trap fired is the likeliest cause - its" \
    "listeners sleep for fifteen minutes."
done

# ---------------------------------------------------------------------------
# The staged definitions - one per status, all three in one group.
#
# THE THREE STATUSES ARE PRODUCED WITHOUT STARTING ANYTHING. Each has a start
# command of `sleep 30` that binds nothing, and the criteria are satisfied (or
# not) by listeners this script owns. So `check` reports RUNNING, PARTIAL and
# NOT RUNNING on a machine where this script has started no service, and the
# teardown has nothing of its own to stop.
#
# NAMES. Short names are lower case with underscores and share no substring
# with their friendly names, so "the coloured run covers the short name and not
# the description" is a real question rather than an accident of spelling -
# the rule narration-test.sh states at length. They are also the names the
# original measurement used, so a capture pasted into a comment here can be
# compared with one taken by hand.
#
# No real service is named anywhere in this file. fidelity-gate.sh puts the
# reason plainly: this repository is published.
# ---------------------------------------------------------------------------
UP=zzc_up;     UP_F='Zulu C Up'
HALF=zzc_half; HALF_F='Zulu C Half'
DOWN=zzc_down; DOWN_F='Zulu C Down'
GROUP=zzcolour
BADJOB=ZZNOSUCHCOLOURJOB

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
mk "$UP"   "$UP_F"   "$PORT_UP"
mk "$HALF" "$HALF_F" "$PORT_HALF, $BADJOB"
mk "$DOWN" "$DOWN_F" "$PORT_DOWN"

cleanup() {
  local p
  for p in $(ps -ef 2>/dev/null | grep -E "$WORK/listen\.py" | grep -v grep | awk '{print $2}'); do
    kill -9 "$p" 2>/dev/null
  done
  [ -n "${KEEP:-}" ] || rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

if [ -n "${COLOUR_DRY:-}" ]; then
  echo "colour-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

# `disown` so the teardown's kill does not print "Killed" job-control notices
# onto this script's own stderr after the summary line.
"$PY" "$WORK/listen.py" "$PORT_UP"   >/dev/null 2>&1 &
disown
"$PY" "$WORK/listen.py" "$PORT_HALF" >/dev/null 2>&1 &
disown
sleep 2

pass=0; failed=0; refdrift=0

# ---------------------------------------------------------------------------
# The colour codes, once.
#
# TAKEN FROM A CAPTURE, AND RE-MEASURED EVERY RUN. Stage 2 reads the codes back
# out of upstream's own output and compares them with these, so a wrong
# transcription is reported as REFDRIFT against upstream rather than as a
# defect in RMSC. That distinction is narration-test.sh's and it earns its keep:
# the failure of a transcribed constant and the failure of an implementation
# look identical in a report otherwise.
#
# Measured 4 September 2026, sc 1.7.1, through this script's own PTY:
#
#   RUNNING        32   green
#   NOT RUNNING    35   MAGENTA - not 31, which is what RMSC uses today
#   PARTIAL        33   amber
#   list rows      36   cyan, and the SAME 36 for a service that is running,
#                       one that is partial and one that is stopped, so the
#                       list colour is fixed rather than status-derived
#   groups rows    none at all, from either implementation
# ---------------------------------------------------------------------------
C_RUNNING=32
C_NOT=35
C_PARTIAL=33
C_LIST=36
C_RESET=0

e() { printf '\033[%sm' "$1"; }        # one SGR sequence
ESC=$'\033'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-30s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-30s   - %s\n' "" "" "$*"; }

fail_case() {  # tag basis problem...
  local tag="$1" basis="$2"; shift 2
  report FAIL "$tag" "($basis)"
  local p; for p in "$@"; do detail "$p"; done
  failed=$((failed+1))
}

# check_named TAG BASIS NOTE PROBLEM... - a named separating assertion.
check_named() {
  local tag="$1" basis="$2" note="$3"; shift 3
  if [ $# -eq 0 ]; then
    report PASS "$tag" "($basis) $note"
    pass=$((pass+1))
    return 0
  fi
  fail_case "$tag" "$basis" "$@"
  return 1
}

drift_case() {  # tag problem...
  local tag="$1"; shift
  report REFDRIFT "$tag" "(reference) upstream no longer matches this file"
  local p; for p in "$@"; do detail "$p"; done
  detail "the constant at the top of this script is wrong, NOT the implementation"
  refdrift=$((refdrift+1))
}

# WHOLE-LINE, BYTE-EXACT matching. grep -Fx is what makes a trailing space a
# difference, and the check row's trailing space is part of the contract.
has_exact() { grep -Fqx -- "$2" "$1" 2>/dev/null; }

# Escapes stripped, so a capture can be compared with its own uncoloured self.
strip_esc() { "$PY" -c '
import re, sys
d = open(sys.argv[1], "rb").read()
sys.stdout.buffer.write(re.sub(rb"\x1b\[[0-9;]*m", b"", d))' "$1"; }

n_esc() {  # how many ESC bytes in a file
  local n
  n=$("$PY" -c '
import sys
print(open(sys.argv[1], "rb").read().count(b"\x1b"))' "$1" 2>/dev/null)
  [ -n "$n" ] || n=0
  echo "$n"
}

# pty_run TAG -- shell-command    capture stdout through a PTY, stderr to a file
#
# TERM and SSH_TTY are both set. SSH_TTY is the half that a PTY does not supply
# and that upstream's gate insists on; its VALUE is never read, only its
# emptiness, so a plausible path is enough and no real terminal is named.
pty_run() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  TERM=xterm-256color SSH_TTY=/dev/pts/0 \
    "$PY" "$WORK/ptycap.py" "$WORK/$tag.out" -- \
    /QOpenSys/pkgs/bin/bash -c "$* 2> $WORK/$tag.err" >/dev/null 2>&1
}

# pty_run_nossh TAG -- shell-command   a real PTY with SSH_TTY ABSENT.
#
# The two gates disagree here and only here, so this is the instrument for the
# decision recorded in the header: upstream needs SSH_TTY as well as a console
# and goes monochrome without it, RMSC asks `[ -t 1 ]` and colours anyway.
# `env -u` rather than SSH_TTY='' because upstream tests emptiness, so the two
# would be indistinguishable and the case would pass either way.
pty_run_nossh() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  env -u SSH_TTY TERM=xterm-256color \
    "$PY" "$WORK/ptycap.py" "$WORK/$tag.out" -- \
    /QOpenSys/pkgs/bin/bash -c "$* 2> $WORK/$tag.err" >/dev/null 2>&1
}

# pipe_run TAG -- shell-command   the same command with stdout on a PIPE (a
# plain file redirection), which is the case colour must NOT appear in.
pipe_run() {
  local tag="$1"; shift
  [ "$1" = "--" ] && shift
  /QOpenSys/pkgs/bin/bash -c "$*" > "$WORK/$tag.out" 2> "$WORK/$tag.err"
}

SC_ENV="JAVA_TOOL_OPTIONS='-Dservices.dir=$SVCDIR'"
SCR_ENV="SC_SERVICES_DIR='$SVCDIR'"

printf 'colour: what a terminal sees, and where RMSC differs from upstream\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s\n' "$SC"
printf 'staged in: %s   (ports %s %s %s)\n\n' \
  "$SVCDIR" "$PORT_UP" "$PORT_HALF" "$PORT_DOWN"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture proves itself, and the PTY proves itself"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

hard_fail() {
  report FAIL "$1" "FIXTURE DID NOT TAKE"
  shift
  local p; for p in "$@"; do detail "$p"; done
  detail "nothing below this line would be evidence for anything"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed   refdrift=$refdrift"
  echo "FAILED: the fixture did not stage"
  exit 1
}

# (a) THE DEFINITIONS LOADED, AND EACH IS IN THE STATUS ITS CASE NEEDS.
#
# Not "three rows came back" - which status went with which name. Every
# assertion in this file is of the form "this status is this colour", so a
# fixture that produced three rows in the wrong three states would fail every
# case while the implementation was correct.
pipe_run fixture -- "$SCR_ENV \"$SCR\" check group:$GROUP"
for pair in "$UP:RUNNING" "$HALF:PARTIAL (1/2)" "$DOWN:NOT RUNNING"; do
  s="${pair%%:*}"; want="${pair#*:}"
  grep -q "^  $want *| $s (" "$WORK/fixture.out" || hard_fail staged-statuses \
    "$s is not '$want' - the fixture cannot produce the three statuses" \
    "got: $(grep -F " $s (" "$WORK/fixture.out" || echo '(no row at all)')"
done
report PASS staged-statuses "(fixture) $UP RUNNING, $HALF PARTIAL (1/2), $DOWN NOT RUNNING"
pass=$((pass+1))

# (b) THE PTY TAKES, AND UPSTREAM COLOURS THROUGH IT.
#
# THE ONE THAT MAKES THIS FILE HONEST. Without it a PTY that silently did not
# work would leave upstream and RMSC both uncoloured, the diff would pass, and
# the run would report full colour parity having compared nothing.
pty_run sc.check -- "$SC_ENV \"$SC\" check group:$GROUP"
n=$(n_esc "$WORK/sc.check.out")
[ "$n" -gt 0 ] || hard_fail pty-colours-upstream \
  "upstream produced $n escape bytes through the PTY - it should produce several" \
  "either the pseudo-terminal did not take, or SSH_TTY did not reach the child," \
  "or this build of sc has colour compiled out" \
  "with no colour from upstream, EVERY comparison below would pass on two" \
  "identical uncoloured captures and report parity having measured nothing"
report PASS pty-colours-upstream "(fixture) upstream emits $n escape bytes on a terminal"
pass=$((pass+1))

# (c) THE SAME FOR RMSC, WHICH ASKS A DIFFERENT QUESTION.
#
# RMSC's colour comes from `[ -t 1 ]` in scripts/scr, not from anything RMSC
# decides - SCOUT_is_tty is a stub returning false. So this is not the same
# proof twice: it is the only assertion anywhere that the wrapper's gate fires.
pty_run scr.check -- "$SCR_ENV \"$SCR\" check group:$GROUP"
n=$(n_esc "$WORK/scr.check.out")
[ "$n" -gt 0 ] || hard_fail pty-colours-rmsc \
  "RMSC produced $n escape bytes through the PTY" \
  "scripts/scr line 22 adds --colors when [ -t 1 ] - either the PTY did not" \
  "reach it, or the wrapper stopped passing the flag" \
  "every 'RMSC does not colour X' case below would then be true for the wrong" \
  "reason, and would keep passing after the fix"
report PASS pty-colours-rmsc "(fixture) RMSC emits $n escape bytes on a terminal"
pass=$((pass+1))

# (d) THE TWO GATES DIVERGE, AND RMSC'S BEHAVIOUR IS THE DECIDED ONE.
#
# Decided 5 September 2026 - see the header. This is not a defect being
# tolerated, it is a choice being pinned, so it is asserted in BOTH directions:
# upstream must still go monochrome without SSH_TTY, and RMSC must still
# colour. Either half changing is worth knowing about, and the upstream half
# doubles as the check that `env -u` really removed the variable - if it did
# not, upstream would colour and this would fail rather than quietly passing.
pty_run_nossh sc.nossh  -- "$SC_ENV \"$SC\" check group:$GROUP"
pty_run_nossh scr.nossh -- "$SCR_ENV \"$SCR\" check group:$GROUP"
nj=$(n_esc "$WORK/sc.nossh.out")
nr=$(n_esc "$WORK/scr.nossh.out")

probs=()
[ "$nj" -eq 0 ] || probs+=("upstream emitted $nj escape bytes with SSH_TTY unset; it gates on SSH_TTY being non-empty and should emit none - if this changed, the decision below is being made against a gate that no longer exists")
[ "$nr" -gt 0 ] || probs+=("RMSC emitted no escape bytes with SSH_TTY unset; scripts/scr gates on [ -t 1 ] alone, so it should still colour - someone has moved RMSC towards upstream's gate, which is the opposite of what was decided")
check_named gates-diverge-as-decided measured \
  "on a terminal that is not ssh: upstream monochrome ($nj), RMSC coloured ($nr) - RMSC's own gate, kept deliberately" \
  "${probs[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 1: colour OFF - the byte-exact contract, which must not move"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------
#
# CLAUDE.md leads with this and it is the reason this stage comes before the
# interesting one: "`check` output is byte-exact, and a slip is silent. The
# consumer screen-scrapes it and drops any row that does not yield three
# fields... Colour must stay off when stdout is not a terminal, for the same
# reason."
#
# A change that colours the short name is exactly the kind that can leak an
# escape into a piped capture, and the symptom is not an error - it is services
# vanishing from a screen. So the pipe case is asserted twice over: not one
# escape byte anywhere, and byte-identical to upstream's own piped output.

for op in "check group:$GROUP" "list" "groups"; do
  tag="pipe.$(echo "$op" | tr ' :' '__')"
  pipe_run "sc.$tag"  -- "$SC_ENV \"$SC\" $op"
  pipe_run "scr.$tag" -- "$SCR_ENV \"$SCR\" $op"

  probs=()
  n=$(n_esc "$WORK/scr.$tag.out")
  [ "$n" -eq 0 ] || probs+=("RMSC put $n escape byte(s) into a PIPED \`$op\` - a" \
                            "consumer parsing by column would drop these rows")
  n=$(n_esc "$WORK/sc.$tag.out")
  [ "$n" -eq 0 ] || probs+=("upstream put $n escape byte(s) into a piped \`$op\` -" \
                            "that is a reference change, not an RMSC defect")
  if ! diff -u "$WORK/sc.$tag.out" "$WORK/scr.$tag.out" > "$WORK/$tag.diff" 2>&1; then
    probs+=("piped \`$op\` is not byte-identical to upstream")
    while IFS= read -r l; do probs+=("$l"); done < "$WORK/$tag.diff"
  fi
  check_named "no-colour-$(echo "$op" | tr ' :' '__')" measured \
    "piped \`$op\`: zero escapes, byte-identical to upstream" "${probs[@]}"
done

# THE SAME OUTPUT, TWO GATES. The rows a terminal sees must be the rows a pipe
# sees with escapes added and NOTHING else - no re-padding, no moved bar, no
# lost trailing space. Stripping the escapes out of the PTY capture and diffing
# it against the piped capture says that in one comparison, and says it for
# whatever the colour rules turn out to be.
#
# SEPARATING VALUE: the strip is of ESC[...m sequences only, so a change that
# moved a visible byte - a space swallowed by the reset, say - survives the
# strip and shows in the diff. A test that only counted escapes could not see
# it, and neither could one that compared trimmed lines.
for who in sc scr; do
  probs=()
  strip_esc "$WORK/$who.check.out" > "$WORK/$who.check.stripped"
  if ! diff -u "$WORK/$who.pipe.check_group_$GROUP.out" "$WORK/$who.check.stripped" \
        > "$WORK/$who.strip.diff" 2>&1; then
    probs+=("$who: with the escapes removed, the terminal rows are not the piped rows")
    while IFS= read -r l; do probs+=("$l"); done < "$WORK/$who.strip.diff"
  fi
  check_named "colour-adds-only-escapes-$who" measured \
    "$who: colour adds escape sequences and moves no visible byte" "${probs[@]}"
done

echo
# ---------------------------------------------------------------------------
echo "== stage 2: the reference, re-measured rather than trusted"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------
#
# Every code at the top of this file was read off a capture and typed into a
# shell variable. Stage 3 compares RMSC against those variables, so if one of
# them is wrong RMSC is failed for agreeing with upstream. This stage reads the
# codes back out of upstream's live output and says so first.
#
# THE CODE IS EXTRACTED FROM THE ROW IT BELONGS TO, not from the file. Pulling
# "the first colour in the output" would find whichever row sorted first and
# would keep agreeing with itself if upstream changed which status got which
# colour.

pty_run sc.list -- "$SC_ENV \"$SC\" list"
pty_run sc.groups -- "$SC_ENV \"$SC\" groups"

# THE MARKER IS ALWAYS A BARE SHORT NAME, AND THAT IS A CORRECTION.
#
# The obvious marker for a row is something like 'zzc_up (' or 'RUNNING  ', and
# both are wrong here, in opposite ways that each produced a confident wrong
# answer on the first run:
#
#   'RUNNING  '   is a substring of 'NOT RUNNING       ', and NOT RUNNING sorts
#                 first, so asking for the RUNNING row's colour returned the
#                 stopped row's - 35 reported as a drift in the green.
#   'zzc_up ('    stops being contiguous the moment the fix lands: upstream
#                 writes ESC[0m between the name and the space, so the marker
#                 matches nothing and every case reads 'no colour at all'. A
#                 marker that can only be found BEFORE the change is useless
#                 for measuring the change.
#
# A bare short name is contiguous either way, and no staged short name is a
# substring of any other or of any friendly name - the rule the fixture names
# are chosen for.
#
# code_first  FILE MARKER -> the FIRST SGR on the line holding MARKER. On a
#                            check row that is the STATUS colour.
# code_before FILE MARKER -> the LAST SGR before MARKER on that line. On a
#                            check row that is the colour the NAME is in.
#
# Two readings of one line, and they are what separate "the name carries the
# status colour" from "the status is coloured and the name is not": today they
# return 32 and 0 for the same row.
code_at() {  # file marker which(first|before)
  "$PY" -c '
import re, sys
data = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
marker, which = sys.argv[2], sys.argv[3]
for line in data.split("\n"):
    i = line.find(marker)
    if i < 0:
        continue
    if which == "first":
        m = re.search(r"\x1b\[([0-9;]*)m", line)
        print(m.group(1) if m else "")
    else:
        m = None
        for m2 in re.finditer(r"\x1b\[([0-9;]*)m", line[:i]):
            m = m2
        print(m.group(1) if m else "")
    break
' "$1" "$2" "$3"
}
code_first()  { code_at "$1" "$2" first; }
code_before() { code_at "$1" "$2" before; }

ref_check() {  # tag wanted got what
  if [ "$2" = "$3" ]; then
    report PASS "$1" "(reference) upstream $4 is $3, as this file says"
    pass=$((pass+1))
  else
    drift_case "$1" "upstream $4 is now '$3'; this file expects '$2'"
  fi
}

ref_check ref-running   "$C_RUNNING" "$(code_first "$WORK/sc.check.out" "$UP")"    "RUNNING"
ref_check ref-not       "$C_NOT"     "$(code_first "$WORK/sc.check.out" "$DOWN")"  "NOT RUNNING"
ref_check ref-partial   "$C_PARTIAL" "$(code_first "$WORK/sc.check.out" "$HALF")"  "PARTIAL"
ref_check ref-list      "$C_LIST"    "$(code_first "$WORK/sc.list.out" "$UP")"     "the list row"

# The list colour does not follow the status - measured on three services in
# three different states in one run. This is the value that separates "list
# rows are cyan" from "list rows carry the check colour", and nothing in
# SCOUT.TEST can reach it: SCOUT_list_row is not handed a status at all.
probs=()
lu=$(code_first "$WORK/sc.list.out" "$UP")
lh=$(code_first "$WORK/sc.list.out" "$HALF")
ld=$(code_first "$WORK/sc.list.out" "$DOWN")
[ "$lu" = "$C_LIST" ] || probs+=("the RUNNING service's list row is '$lu', not $C_LIST")
[ "$lh" = "$C_LIST" ] || probs+=("the PARTIAL service's list row is '$lh', not $C_LIST")
[ "$ld" = "$C_LIST" ] || probs+=("the stopped service's list row is '$ld', not $C_LIST")
check_named ref-list-is-not-status-derived measured \
  "upstream colours all three states' list rows $C_LIST" "${probs[@]}"

# groups is not coloured by upstream at all. Asserted, because "RMSC matches"
# would otherwise be a claim about an absence nobody had measured.
probs=()
n=$(n_esc "$WORK/sc.groups.out")
[ "$n" -eq 0 ] || probs+=("upstream put $n escape byte(s) into \`groups\` on a terminal")
check_named ref-groups-uncoloured measured \
  "upstream leaves \`groups\` uncoloured even on a terminal" "${probs[@]}"

echo
# ---------------------------------------------------------------------------
echo "== stage 3: RMSC against upstream, on a terminal, byte for byte"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

pty_run scr.list   -- "$SCR_ENV \"$SCR\" list"
pty_run scr.groups -- "$SCR_ENV \"$SCR\" groups"

# The rows, built from the codes rather than pasted, so a corrected constant
# corrects every expectation at once.
#
#   '  ' C status18 R ' | ' C short R ' (' desc ') ' [ C suffix R ]
#
# Note what is OUTSIDE the colour and stays there: the two leading spaces, the
# bar and the spaces round it, the parentheses, the description, and the
# trailing space after ')'. The suffix's leading space is outside too.
row() {  # code status18 short desc suffix
  printf '  %s%s%s | %s%s%s (%s) %s' \
    "$(e "$1")" "$2" "$(e $C_RESET)" \
    "$(e "$1")" "$3" "$(e $C_RESET)" \
    "$4" "$5"
}
SUF="[not running at -->JOBNAME:$BADJOB]"

r_up=$(row   "$C_RUNNING" 'RUNNING           ' "$UP"   "$UP_F"   '')
r_down=$(row "$C_NOT"     'NOT RUNNING       ' "$DOWN" "$DOWN_F" '')
r_half=$(row "$C_PARTIAL" 'PARTIAL (1/2)     ' "$HALF" "$HALF_F" \
             "$(e $C_PARTIAL)$SUF$(e $C_RESET)")

# NOTHING IS ADDED BACK HERE, and the first draft of this file added a space.
# Command substitution strips trailing NEWLINES, not trailing spaces, so
# `row` already returns the check row's trailing space intact - and the
# "correction" made every expectation one byte too long, which the report
# showed as an upstream row that did not exist.

# --- the three rows, each on its own, each against upstream -----------------
#
# BOTH SIDES ARE ASSERTED SEPARATELY: that upstream produced the expected row,
# and that RMSC did. That is what tells a failing case apart from a stale
# reference - and it is why a bare `diff scr sc` is not enough on its own,
# though it is also done below.
for pair in "up:$r_up" "half:$r_half" "down:$r_down"; do
  which="${pair%%:*}"; want="${pair#*:}"
  probs=()
  has_exact "$WORK/sc.check.out" "$want" \
    || probs+=("upstream did not produce this row - the expectation is stale:" \
               "wanted: $(printf '%q' "$want")" \
               "got:    $(printf '%q' "$(grep -F "zzc_$which" "$WORK/sc.check.out" | head -n1)")")
  has_exact "$WORK/scr.check.out" "$want" \
    || probs+=("RMSC did not produce this row:" \
               "wanted: $(printf '%q' "$want")" \
               "got:    $(printf '%q' "$(grep -F "zzc_$which" "$WORK/scr.check.out" | head -n1)")")
  check_named "check-row-$which" measured \
    "the $which row matches upstream byte for byte on a terminal" "${probs[@]}"
done

# --- the whole of check, list and groups ------------------------------------
for op in check list groups; do
  probs=()
  if ! diff -u "$WORK/sc.$op.out" "$WORK/scr.$op.out" > "$WORK/$op.pty.diff" 2>&1; then
    probs+=("\`$op\` on a terminal is not byte-identical to upstream")
    while IFS= read -r l; do probs+=("$(printf '%q' "$l")"); done < "$WORK/$op.pty.diff"
  fi
  check_named "terminal-$op" measured \
    "\`$op\` on a terminal is byte-identical to upstream" "${probs[@]}"
done

echo
# ---------------------------------------------------------------------------
echo "== stage 4: the separating values, one rule at a time"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------
#
# The diffs above already fail if any of these is wrong. They are stated
# separately anyway, because a diff names a LINE and these name a RULE, and
# four rules moved together in the same line for the whole of this change.
#
# NONE OF THESE IS AN ESCAPE COUNT. A count cannot tell "coloured the short
# name" from "coloured the description", and it cannot tell 35 from 31 at all -
# both of those are one escape either way. Each case below names the value that
# separates its rule from the rule next to it.

# (1) NOT RUNNING IS MAGENTA, NOT RED.
#
# SEPARATING VALUE: the digits. RMSC uses 31 today and upstream uses 35, and
# both are a single SGR sequence in the same position with the same length, so
# nothing structural distinguishes them. Asserted in both directions - 35
# present, 31 absent - because an implementation that emitted both would
# satisfy the first alone.
probs=()
got=$(code_first "$WORK/scr.check.out" "$DOWN")
[ "$got" = "$C_NOT" ] || probs+=("RMSC colours NOT RUNNING '$got', upstream $C_NOT (magenta)")
grep -q "${ESC}\[31m" "$WORK/scr.check.out" \
  && probs+=("RMSC still emits ESC[31m somewhere in \`check\` - red is upstream's colour for nothing here")
check_named not-running-is-magenta measured \
  "NOT RUNNING is $C_NOT and 31 appears nowhere" "${probs[@]}"

# (2) THE SHORT NAME IS COLOURED, AND WITH THE STATUS COLOUR.
#
# SEPARATING VALUE: the colour code that immediately precedes the short name,
# per row, with the three rows in three different states. Upstream uses the
# ROW'S status colour, so the three rows disagree with each other - which is
# what separates "the name carries the status colour" from "the name has a
# colour of its own", a rule a single-row test cannot tell apart. `list`'s
# fixed cyan is the live counter-example that makes that a real question.
probs=()
for pair in "$UP:$C_RUNNING" "$HALF:$C_PARTIAL" "$DOWN:$C_NOT"; do
  s="${pair%%:*}"; want="${pair#*:}"
  got=$(code_before "$WORK/scr.check.out" "$s")
  [ "$got" = "$want" ] \
    || probs+=("RMSC: the short name '$s' is preceded by '${got:-nothing}', wanted $want")
done
check_named short-name-takes-status-colour measured \
  "each short name carries its own row's status colour" "${probs[@]}"

# (3) THE DESCRIPTION IS NOT COLOURED, AND NOR ARE THE BRACKETS ROUND IT.
#
# SEPARATING VALUE: ' (' + description + ') ' appears CONTIGUOUSLY. An
# implementation that extended the coloured run from the short name through the
# description would break that substring with a reset and would still satisfy
# every "the name is coloured" assertion above.
#
# THIS ONE PASSES TODAY. It is the guard on the fix rather than the driver of
# it: colouring the name is the easiest place to colour one byte too far.
probs=()
for pair in "$UP_F:$UP" "$HALF_F:$HALF" "$DOWN_F:$DOWN"; do
  f="${pair%%:*}"; s="${pair#*:}"
  grep -qF " ($f) " "$WORK/scr.check.out" \
    || probs+=("RMSC: ' ($f) ' is not contiguous - something coloured the description or a bracket")
  grep -qF " ($f) " "$WORK/sc.check.out" \
    || probs+=("upstream: ' ($f) ' is not contiguous either - the reference has changed")
done
check_named description-stays-uncoloured measured \
  "the description, its brackets and the spaces round them carry no escape" "${probs[@]}"

# (4) THE [not running at -->...] SUFFIX IS COLOURED, AND THE SPACE BEFORE IT
#     IS NOT.
#
# SEPARATING VALUE: the escape sits between the space and the '[', so the
# literal ') ' + ESC + '[' + code + 'm[not running' appears. Asserting only
# that the suffix is coloured would be satisfied by an implementation that
# swallowed the preceding space into the coloured run, which changes where the
# visible text starts on a piped capture the moment the escapes are stripped.
probs=()
grep -qF ") $(e $C_PARTIAL)[not running at -->" "$WORK/scr.check.out" \
  || probs+=("RMSC: the suffix is not wrapped in $C_PARTIAL with the space left outside")
grep -qF ") $(e $C_PARTIAL)[not running at -->" "$WORK/sc.check.out" \
  || probs+=("upstream: the same - the reference has changed")
grep -qF "$SUF$(e $C_RESET)" "$WORK/scr.check.out" \
  || probs+=("RMSC: the suffix is not closed by a reset at end of line")
check_named suffix-is-coloured measured \
  "the suffix is wrapped in $C_PARTIAL, the space before it is not" "${probs[@]}"

# (5) LIST ROWS ARE CYAN, AND ONLY THE SHORT NAME IS.
#
# SEPARATING VALUE: 36 rather than the row's status colour, on three rows whose
# services are in three different states. This is the divergence the original
# brief did not have - it measured `check` only - and it is a fourth rule, not
# a restatement of (2): the same short name is 36 in `list` and 32, 33 or 35 in
# `check`.
probs=()
for pair in "$UP:$UP_F" "$HALF:$HALF_F" "$DOWN:$DOWN_F"; do
  s="${pair%%:*}"; f="${pair#*:}"
  got=$(code_first "$WORK/scr.list.out" "$s")
  [ "$got" = "$C_LIST" ] \
    || probs+=("RMSC: the list row for '$s' is preceded by '${got:-nothing}', wanted $C_LIST")
  grep -qF " ($f)" "$WORK/scr.list.out" \
    || probs+=("RMSC: ' ($f)' is not contiguous in the list row - the description was coloured")
done
check_named list-rows-are-cyan measured \
  "list short names are $C_LIST whatever the service's state; descriptions plain" "${probs[@]}"

# (6) groups STAYS UNCOLOURED.
#
# SEPARATING VALUE: zero escape BYTES, on a terminal, where every other
# operation has some. Upstream measured the same way in stage 2, so this is a
# match rather than an assumption - and it is worth pinning precisely because
# an implementation that put colour behind one global flag would light this up
# too, and nobody would think to look.
probs=()
n=$(n_esc "$WORK/scr.groups.out")
[ "$n" -eq 0 ] || probs+=("RMSC put $n escape byte(s) into \`groups\` on a terminal; upstream puts none")
check_named groups-stays-uncoloured measured \
  "\`groups\` carries no colour on a terminal, from either implementation" "${probs[@]}"

# (7) `info`'S HEADER IS THE SAME CONSTRUCT AS A `list` ROW, AND IS COLOURED
#     THE SAME WAY.
#
# WHY THIS CASE IS HERE AND NOT IN qtestsrc/SCOUT.TEST.RPGLE. What bytes
# SCOUT_list_row produces is already pinned there, coloured and uncoloured,
# down to the position of every escape. What is NOT pinned anywhere is whether
# `info` USES it. SCEXEC_info builds its header line by hand and returns
# nothing - it prints - and an RPGUnit suite cannot capture its own stdout
# (qtestsrc/SCAPIDRV.PGM.RPGLE says so at length and exists because of it). So
# "does info go through the shared row builder" is an end-to-end question by
# nature, and this file is the only instrument here that can ask it.
#
# MEASURED: `info` prints a header line `<short> (<friendly>)` - the same
# construct `list` prints one row per service - and upstream colours it the
# same cyan, through the same PTY, in the same run. RMSC builds it by hand and
# leaves it plain, so since colour was added to `list` rows the identical
# construct is coloured in one place and not the other.
#
# ASSERTED AGAINST THE `list` ROW'S OWN BYTES, NOT AGAINST $C_LIST. The rule is
# "these two are the same construct and must render the same", so the case is
# written as a byte comparison between one implementation's `info` header and
# THAT SAME IMPLEMENTATION'S `list` row for the same service in the same run.
# If the list colour is ever changed, this case keeps meaning what it says
# instead of going red for naming a code that moved.
#
# THE HEADER LINE IS LOCATED BY ITS VISIBLE TEXT AND COMPARED BY ITS RAW BYTES,
# and the two halves are deliberately different. Locating it by the escape-
# stripped text finds it whether it is coloured or not - which is the whole
# point, since today it is not - so the search cannot presuppose the answer.
# It also avoids the trap stage 2 records: `info` prints the short name again
# on its `Defined in:` line, so "the first line containing zzc_up" is not
# reliably the header.
#
# `info` IS NOT ADDED TO STAGE 3's WHOLE-OUTPUT DIFF. docs/messages.md records
# eight differences in `info`'s shape - blank lines, an invented Working
# Directory line, a block that is never closed - so that diff would fail for
# six reasons that have nothing to do with colour and would bury this one.

pty_run  sc.info   -- "$SC_ENV \"$SC\" info $UP"
pty_run  scr.info  -- "$SCR_ENV \"$SCR\" info $UP"
pipe_run sc.infop  -- "$SC_ENV \"$SC\" info $UP"
pipe_run scr.infop -- "$SCR_ENV \"$SCR\" info $UP"

HDR="$UP ($UP_F)"

# find_line FILE OUTFILE VISIBLE - write the RAW bytes of the line whose
# escape-stripped text is exactly VISIBLE. Non-zero when there is no such line,
# which is a finding rather than a silent pass.
find_line() {
  "$PY" -c '
import re, sys
src, dst, want = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(src, "rb").read().decode("utf-8", "replace")
for line in data.split("\n"):
    line = line.rstrip("\r")
    if re.sub(r"\x1b\[[0-9;]*m", "", line) == want:
        open(dst, "wb").write(line.encode("utf-8"))
        sys.exit(0)
sys.exit(1)
' "$1" "$2" "$3"
}
shq() { printf '%q' "$(cat "$1" 2>/dev/null)"; }

# --- the reference, re-measured rather than trusted -------------------------
#
# Stage 2's discipline, applied to this rule: read upstream's own two lines and
# say whether they still agree with each other BEFORE failing RMSC for
# disagreeing. A REFDRIFT here means upstream changed, not that RMSC is wrong.
probs=()
find_line "$WORK/sc.info.out" "$WORK/sc.info.hdr" "$HDR" \
  || probs+=("upstream's \`info\` has no line whose visible text is '$HDR'")
find_line "$WORK/sc.list.out" "$WORK/sc.list.hdr" "$HDR" \
  || probs+=("upstream's \`list\` has no row whose visible text is '$HDR'")
if [ ${#probs[@]} -eq 0 ] && ! cmp -s "$WORK/sc.info.hdr" "$WORK/sc.list.hdr"; then
  probs+=("upstream's info header and list row are no longer the same bytes:" \
          "info: $(shq "$WORK/sc.info.hdr")" \
          "list: $(shq "$WORK/sc.list.hdr")")
fi
if [ ${#probs[@]} -eq 0 ]; then
  report PASS ref-info-header-is-a-list-row \
    "(reference) upstream renders info's header exactly as a list row"
  pass=$((pass+1))
else
  drift_case ref-info-header-is-a-list-row "${probs[@]}"
fi

# --- COLOUR ON: the separating half ----------------------------------------
#
# SEPARATING VALUE: the escapes. Both lines carry the same visible text by
# construction - that is how the header was found - so the ONLY thing this
# comparison can be about is which escape sequences are present and where they
# sit. An assertion that the two lines "say the same thing", or that info
# printed a header at all, would pass today and prove nothing.
probs=()
find_line "$WORK/scr.info.out" "$WORK/scr.info.hdr" "$HDR" \
  || probs+=("RMSC's \`info\` has no line whose visible text is '$HDR' on a terminal")
find_line "$WORK/scr.list.out" "$WORK/scr.list.hdr" "$HDR" \
  || probs+=("RMSC's \`list\` has no row whose visible text is '$HDR' on a terminal")
if [ ${#probs[@]} -eq 0 ] && ! cmp -s "$WORK/scr.info.hdr" "$WORK/scr.list.hdr"; then
  probs+=("RMSC's info header and its own list row are the same construct and" \
          "do not carry the same escapes:" \
          "info: $(shq "$WORK/scr.info.hdr")" \
          "list: $(shq "$WORK/scr.list.hdr")" \
          "the list row goes through SCOUT_list_row; the info header is built" \
          "by hand in SCEXEC_info and never asks for colour")
fi
if [ ${#probs[@]} -eq 0 ] && ! cmp -s "$WORK/scr.info.hdr" "$WORK/sc.info.hdr"; then
  probs+=("RMSC's info header does not match upstream's byte for byte:" \
          "RMSC:     $(shq "$WORK/scr.info.hdr")" \
          "upstream: $(shq "$WORK/sc.info.hdr")")
fi
check_named info-header-is-coloured measured \
  "info's header carries the same escapes as a list row for the same service" \
  "${probs[@]}"

# --- COLOUR OFF: the control ------------------------------------------------
#
# On a pipe neither line may carry an escape, and the two must be byte
# identical for the plainest possible reason - they are the same text. This
# passes today and is the guard on the fix: the header is on `info`'s output,
# which is read by people rather than parsed by column, but colour leaking into
# a piped stream is the failure mode CLAUDE.md opens with and the cheapest
# place for a new call to SCOUT_list_row to introduce it.
probs=()
find_line "$WORK/scr.infop.out" "$WORK/scr.infop.hdr" "$HDR" \
  || probs+=("RMSC's piped \`info\` has no line whose visible text is '$HDR'")
find_line "$WORK/scr.pipe.list.out" "$WORK/scr.pipe.list.hdr" "$HDR" \
  || probs+=("RMSC's piped \`list\` has no row whose visible text is '$HDR'")
if [ ${#probs[@]} -eq 0 ]; then
  cmp -s "$WORK/scr.infop.hdr" "$WORK/scr.pipe.list.hdr" \
    || probs+=("piped, the info header and the list row are not identical:" \
               "info: $(shq "$WORK/scr.infop.hdr")" \
               "list: $(shq "$WORK/scr.pipe.list.hdr")")
  n=$(n_esc "$WORK/scr.infop.out")
  [ "$n" -eq 0 ] || probs+=("RMSC put $n escape byte(s) into a PIPED \`info\`")
fi
n=$(n_esc "$WORK/sc.infop.out")
[ "$n" -eq 0 ] || probs+=("upstream put $n escape byte(s) into a piped \`info\` - the reference has changed")
check_named info-header-plain-on-a-pipe measured \
  "piped, info's header and the list row are identical and carry no escapes" \
  "${probs[@]}"

echo
echo "pass=$pass   failed=$failed   refdrift=$refdrift"
[ -n "${KEEP:-}" ] && echo "artefacts kept in: $WORK"
if [ "$refdrift" -gt 0 ]; then
  echo "REFDRIFT: upstream no longer matches a constant at the top of this script."
  echo "Fix the constant before reading any FAIL below it as an RMSC defect."
fi
[ "$failed" -eq 0 ] || { echo "FAILED"; exit 1; }
[ "$refdrift" -eq 0 ] || exit 3
echo "OK"
exit 0
