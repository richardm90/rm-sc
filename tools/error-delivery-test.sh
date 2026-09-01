#!/QOpenSys/pkgs/bin/bash
#
# error-delivery-test.sh - how RMSC reports a failure: which stream, how many
# times, with what prefix, and with what exit status.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and in the same style. It
# is deliberately a shell script and not an iRPGUnit suite: exit status and
# stdout/stderr routing only exist OUTSIDE the ILE job, and iRPGUnit runs inside
# one. No assertion in this file is reachable from RPG.
#
# WHY THIS EXISTS
#
# RMSC has reported every failure by signalling an escape message. Two things
# followed, and the second is the dangerous one:
#
#   1. `system` sees an exception, so the shell gets 255 for every error
#      whatever the cause. A caller cannot tell "you typed a verb I do not know"
#      from "that service does not exist".
#
#   2. The message is emitted TWICE - once on stderr carrying a `CPF9897:`
#      prefix, and once on STDOUT with no prefix at all.
#
# Stdout is the format-critical surface. The consumer screen-scrapes `check` by
# column position - status in columns 1-20, name after the bar at column 22,
# description in parentheses - and silently DROPS any row that does not yield
# all three fields. An error line on stdout lands in the middle of that. It does
# not raise anything; it makes services disappear from a screen. This is the
# same failure mode CLAUDE.md and docs/parity.md single `check` out for, arriving
# by a different door: not a formatting slip in a good row, but a line that was
# never a row.
#
# THE CONTRACT BEING TESTED
#
# Errors go to stderr ONLY, ONCE, with NO message-id prefix, and the exit status
# names the KIND of failure:
#
#   255  argument/usage - an unknown operation, no operation at all, an
#        unrecognised option, or an operation given without the service it
#        requires. The command could not be understood.
#   253  operational    - the command was understood and could not be carried
#        out: an unknown service name, a definition that will not load.
#   0    success        - and stderr silent.
#
# 253 and 255 are upstream's values, so where both implementations agree on the
# classification the numbers agree too.
#
# WHAT IS NOT TESTED HERE, ON PURPOSE
#
# Message TEXT is not compared against upstream. RMSC's wording deliberately
# does not match yet; that is separate work. Every assertion below is about
# SHAPE - which stream, how many times, what prefix, what exit status. A test
# that pinned the wording would have to be rewritten by the very change that
# fixes it, and would fail for a reason nobody cares about in the meantime.
#
# BASIS OF EACH ASSERTION - read this before believing a failure
#
#   measured  taken from a side-by-side run against the installed sc 1.7.1. The
#             upstream exit status was observed, not reasoned about. Stage 4
#             re-confirms every one of them on each run, so the reference cannot
#             go stale underneath the expectations in stage 1.
#
#   inferred  follows from the written contract above, not from anything
#             measured against upstream. If one of these fails, ask whether the
#             inference was wrong before assuming the implementation is.
#
#   pinned    a place where the two implementations DELIBERATELY DISAGREE and
#             RMSC keeps its own behaviour for now. Pinned so that a later
#             change to it is visible rather than silent. A failure here is not
#             necessarily a defect - it may be the intended fix arriving, in
#             which case this script and docs/parity.md both need updating.
#
# Stdout and stderr are captured to SEPARATE files throughout. Nothing here uses
# `2>&1`: which stream a message landed on is the entire question.

set -o pipefail

# This script lives at $DEPLOY/tools/, so it finds the deploy directory from its
# own location - the same trick fidelity-gate.sh uses, and for the same reason:
# it assumes nothing about where anyone deploys and keeps a developer's home
# directory out of a published file. Override any of these to test a build
# somewhere else. Nothing that names a machine or a directory gets a default
# that could quietly be wrong.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-/tmp/error-delivery.$$}"

# Opt-in, default off. See the state-ops-require-service case for what it runs
# and why running it is a decision rather than a default.
SWEEP_STATE_CHANGING="${SWEEP_STATE_CHANGING:-}"

# Without this the PASE side of both implementations behaves differently, and
# neither the exit statuses nor the stream routing are comparable.
export QIBM_MULTI_THREADED=Y

# ---------------------------------------------------------------------------
# Setup. Every one of these failures is fatal and loud. A run that skipped a
# case because a fixture was missing would report success while testing nothing,
# which is worse than failing outright.
# ---------------------------------------------------------------------------

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "This script must run ON the IBM i box, from the deploy directory - it drives" \
  "the wrapper, and the wrapper calls an ILE program. Set SCR=<path> or DEPLOY=" \
  "<deploy dir> if the build lives somewhere else."

[ -x "$SC" ] || setup_fail \
  "upstream sc is not executable at: $SC" \
  "" \
  "Stage 4 re-confirms the upstream exit statuses that stage 1 is written" \
  "against, so the reference cannot drift unnoticed. Running without it would" \
  "leave those expectations unanchored. Set SC=<path> if it is installed" \
  "elsewhere."

# The measured table used /tmp/nosuch.yaml. If something has since created it,
# the case stops testing what it was written to test.
NOSUCH_YAML=/tmp/nosuch.yaml
[ -e "$NOSUCH_YAML" ] && setup_fail \
  "$NOSUCH_YAML exists, so the 'definition that will not load' case would not" \
  "be testing a missing definition. Remove it, or set the case to another path."

# Discovered, never hardcoded: this file is published and must not name a
# client's services. fidelity-gate.sh takes the same line.
SERVICE="${SERVICE:-$("$SCR" list 2>/dev/null | awk 'NF{print $1; exit}')}"
[ -n "$SERVICE" ] || setup_fail \
  "no service name could be read from '$SCR list'." \
  "" \
  "One real, defined service is needed as the success fixture - the happy path" \
  "has to be pinned too, or nothing catches an error message that starts" \
  "appearing on a run that worked. This is a hard failure rather than a skip:" \
  "a suite that passes because its fixture is absent reports success for" \
  "nothing at all."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

pass=0; failed=0; changed=0; refdrift=0; open_n=0; stale=0
declare -a MEASURED_EXITS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# wc -l undercounts a final line with no trailing newline. grep -c '' does not.
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

# The payload of the first stderr line, with any leading message id stripped.
#
# Stripping matters. TODAY the stderr copy is prefixed `CPF9897: ` and the
# stdout copy is not, so an exact-line comparison between the two streams would
# find no duplicate and this script would go green on the bug it exists to
# catch. Comparing the PAYLOAD finds it.
stderr_payload() {
  [ -s "$1" ] || return 1
  head -n 1 "$1" | sed -E 's/^[A-Z]{2,4}[0-9]{4}: //'
}

# A line stdout is allowed to carry from `check`: two spaces, an 18-character
# status, ' | ' with the bar at column 22, and a parenthesised description
# somewhere after the name. Exactly the three fields the consumer requires;
# any other NON-EMPTY line is a row it would silently drop.
CHECK_ROW='^  .{18} \| .*\(.*\)'

# EMPTY LINES ARE EXEMPT, and this is not a loophole - it is upstream's format.
#
# Every `check` ends with a blank line. `SCEXEC_check_all` writes one
# deliberately, docs/parity.md records it as upstream's behaviour, and it is
# inside the captured baselines that fidelity-gate.sh compares byte for byte. A
# `check` that matched nothing prints that blank line and nothing else:
#
#   $ sc  check group:nosuchgroup 2>/dev/null | cat -A
#   $
#   $ scr check group:nosuchgroup 2>/dev/null | cat -A
#   $
#
# The consumer does drop that line - but dropping a blank line is intended,
# whereas dropping a SERVICE ROW is the bug this policy exists to catch. Treating
# the two alike made the empty-group case fail against correct output.
#
# So do NOT 'tighten' this by asserting that a check which matched nothing prints
# empty stdout. It would be asserting the opposite of upstream's format, and it
# would put this script in direct conflict with the byte-exact stage of
# fidelity-gate.sh, which requires the trailing blank to be there.
#
# What that costs, stated plainly: a stray blank line in the MIDDLE of a listing
# is not caught here either, since this exemption cannot tell one blank line from
# another. That is covered, and covered better, by fidelity-gate.sh - its
# byte-exact stage normalises volatile values but deliberately leaves whitespace
# alone, precisely so a stray blank line fails. This policy is aimed at the thing
# a byte-exact diff cannot be aimed at: output from a case that errors, where
# there is no fixture to diff against. Verified by mutation - a mis-columned bar,
# a lost description parenthesis, and an error line among the rows are all still
# caught.
BLANK_LINE='^$'

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-30s %s\n' "$verdict" "$tag" "$*"
}

# assert_case TAG BASIS EXPECTED_EXIT STDOUT_POLICY STDERR_POLICY -- argv...
#
#   STDOUT_POLICY  empty      nothing at all on stdout
#                  checkrows  every NON-EMPTY line must parse as a check row;
#                             blank lines are upstream's format (see CHECK_ROW)
#                  any        stdout is not this case's subject
#   STDERR_POLICY  silent     nothing at all on stderr
#                  once       a message, exactly one copy of it, none on stdout
#                  warn       at least one line, same duplication rules as 'once'
#
# Both message policies also require that no line on stderr carries a message-id
# prefix - `CPF9897:` or any other escape leaking through.
assert_case() {
  local tag="$1" basis="$2" want_rc="$3" out_pol="$4" err_pol="$5"; shift 5
  [ "$1" = "--" ] && shift
  local o="$WORK/$tag.out" e="$WORK/$tag.err"
  local rc rc_ok=1 problems=()

  "$SCR" "$@" > "$o" 2> "$e"
  rc=$?

  [ "$basis" = measured ] && MEASURED_EXITS+=("$rc")

  [ "$rc" -eq "$want_rc" ] || { rc_ok=0; problems+=("exit $rc, wanted $want_rc"); }

  case "$out_pol" in
    empty)
      if [ -s "$o" ]; then
        problems+=("stdout not empty ($(count_lines "$o") line(s)): $(head -n 1 "$o")")
      fi ;;
    checkrows)
      # Blank lines are dropped from consideration, not from the output: see the
      # note at CHECK_ROW for why a trailing blank is correct. Everything that
      # survives that filter is held strictly to the row shape.
      local bad
      bad=$(grep -vE "$BLANK_LINE" "$o" 2>/dev/null | grep -cvE "$CHECK_ROW" || true)
      [ -z "$bad" ] && bad=0
      if [ "$bad" -ne 0 ]; then
        problems+=("$bad non-empty stdout line(s) a column-parsing consumer would drop: '$(grep -vE "$BLANK_LINE" "$o" | grep -m1 -vE "$CHECK_ROW")'")
      fi ;;
  esac

  local n_err; n_err=$(count_lines "$e")
  case "$err_pol" in
    silent)
      [ "$n_err" -eq 0 ] || problems+=("stderr not silent on success ($n_err line(s)): $(head -n 1 "$e")") ;;
    once|warn)
      if [ "$n_err" -eq 0 ]; then
        problems+=("nothing on stderr - the failure was reported somewhere else, or not at all")
      else
        local ids; ids=$(grep -cE '^[A-Z]{2,4}[0-9]{4}:' "$e")
        [ "$ids" -eq 0 ] || problems+=("$ids stderr line(s) carry a message-id prefix: $(grep -m1 -oE '^[A-Z]{2,4}[0-9]{4}:' "$e")")

        local msg; msg=$(stderr_payload "$e")
        if [ -n "$msg" ]; then
          # The duplicate the consumer actually chokes on.
          local on_out; on_out=$(grep -Fc -- "$msg" "$o" 2>/dev/null || true)
          [ -z "$on_out" ] && on_out=0
          [ "$on_out" -eq 0 ] || problems+=("the error text also appears on STDOUT ($on_out line(s)) - this is the row-dropping bug")

          local on_err; on_err=$(grep -Fc -- "$msg" "$e")
          [ "$on_err" -eq 1 ] || problems+=("the error text appears $on_err times on stderr, wanted once")
        fi

        if [ "$err_pol" = once ] && [ "$n_err" -ne 1 ]; then
          # Informational, not a verdict. A usage failure may legitimately print
          # a usage block alongside the message, so a line count above one is
          # not by itself wrong - which is exactly why "emitted once" is tested
          # by counting copies of the MESSAGE above, not by counting lines here.
          report NOTE "$tag" "stderr is $n_err lines (see the copy count above for singleness)"
        fi
      fi ;;
  esac

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) exit $rc"
    pass=$((pass+1))
    return 0
  fi

  # A pinned case is CHANGED only when the EXIT STATUS moved - that is the thing
  # being held still. Its stream discipline is not pinned, it is required, so a
  # breach there is an ordinary contract failure however the case is classified.
  if [ "$basis" = pinned ] && [ "$rc_ok" -eq 0 ]; then
    report CHANGED "$tag" "RMSC's pinned exit status moved - see the comment above this case"
    changed=$((changed+1))
  else
    report FAIL "$tag" "($basis)"
    failed=$((failed+1))
  fi
  local p; for p in "${problems[@]}"; do printf '  %-9s %-30s   - %s\n' "" "" "$p"; done
  printf '  %-9s %-30s   artefacts: %s.out %s.err\n' "" "" "$tag" "$tag"
  return 1
}

# sweep_no_service TAG BASIS OPS...
#
# Every operation that REQUIRES a service, invoked without one. Aggregated into
# a single row rather than one case per operation: they are ten instances of one
# behaviour, and ten near-identical PASS lines would bury the one that broke
# ranks. A failure names the operation and what was wrong with it, so nothing is
# lost by the aggregation.
sweep_no_service() {
  local tag="$1" basis="$2"; shift 2
  local op rc n=0 msg why bad=()

  for op in "$@"; do
    local o="$WORK/$tag.$op.out" e="$WORK/$tag.$op.err"
    "$SCR" "$op" > "$o" 2> "$e"
    rc=$?
    n=$((n+1))
    why=""

    [ "$rc" -eq 255 ] || why="$why exit=$rc(wanted 255)"
    if [ -s "$o" ]; then why="$why stdout=$(count_lines "$o")line(s)"; fi
    if [ ! -s "$e" ]; then why="$why nothing-on-stderr"; fi
    if grep -qE '^[A-Z]{2,4}[0-9]{4}:' "$e" 2>/dev/null; then why="$why message-id-prefix"; fi

    msg=$(stderr_payload "$e")
    if [ -n "$msg" ]; then
      if grep -Fq -- "$msg" "$o" 2>/dev/null; then why="$why text-also-on-stdout"; fi
      [ "$(grep -Fc -- "$msg" "$e")" -eq 1 ] || why="$why not-once-on-stderr"
    fi

    [ -n "$why" ] && bad+=("$op:$why")
  done

  if [ ${#bad[@]} -eq 0 ]; then
    report PASS "$tag" "($basis) $n operations, all exit 255, message on stderr only"
    pass=$((pass+1))
    return 0
  fi
  report FAIL "$tag" "($basis) $((${#bad[@]})) of $n operations"
  local b; for b in "${bad[@]}"; do printf '  %-9s %-30s   - %s\n' "" "" "$b"; done
  failed=$((failed+1))
  return 1
}

# confirm_upstream TAG EXPECTED_EXIT -- argv...
# Re-measure what sc does, so the "measured" basis above stays true.
confirm_upstream() {
  local tag="$1" want="$2"; shift 2
  [ "$1" = "--" ] && shift
  local rc
  "$SC" "$@" > "$WORK/sc.$tag.out" 2> "$WORK/sc.$tag.err"
  rc=$?
  if [ "$rc" -eq "$want" ]; then
    report PASS "sc:$tag" "exit $rc as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$tag" "sc exits $rc, the recorded reference says $want"
    refdrift=$((refdrift+1))
  fi
}

printf 'error delivery: which stream, how many times, what exit status\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" "$("$SC" --version 2>/dev/null | head -n 1 || echo 'version unknown')"
printf 'fixture service: %s\n\n' "$SERVICE"

# ---------------------------------------------------------------------------
echo "== stage 1: the contract, on cases measured against sc 1.7.1"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

# OPERATIONAL - the command was understood, the service does not exist.
# sc 1.7.1: 253. This is the headline case from the bug report: today it gives
# 255, the text on stderr carries a CPF9897 prefix, and a second unprefixed copy
# lands on stdout in the middle of what a consumer parses by column.
assert_case unknown-service measured 253 empty once -- check nosuchservice

# USAGE - no such operation. sc 1.7.1: 255.
assert_case unknown-operation measured 255 empty once -- wibble

# USAGE - no operation at all. sc 1.7.1: 255.
# The wrapper pads the argument string to 1024 characters, so RMSC receives
# blanks rather than a zero-length string; "no operation" has to be recognised
# from that, which is why it is worth a case of its own rather than folding it
# into the unknown-operation one above.
assert_case no-operation measured 255 empty once --

# OPERATIONAL - a definition that cannot be loaded. sc 1.7.1: 253.
# Same classification as an unknown service and a different code path to it,
# which is the point: both must land on 253, not one on 253 and one on 255.
assert_case unloadable-definition measured 253 empty once -- check "$NOSUCH_YAML"

# USAGE - an operation given without the service it requires. sc 1.7.1: 255,
# with `Usage: sc  [options] <operation> <service>` on stderr.
#
# This is the single riskiest line in the change this script guards, and it is
# the one nothing else covers. It USED to exit 255 by accident of the old design
# - everything did - and now exits 255 by DECISION, having been reclassified
# from operational to usage. The status did not move, so no regression test
# built on comparing before and after can see it, and the parse-surface unit
# suite cannot reach exit status at all. If the classification were ever revised
# to 253 on the reasoning that "the service is missing, like an unknown service
# is missing", nothing but this case would notice. Upstream is unambiguous that
# it is usage: it answers with its usage line.
#
# If this fails on 'stdout not empty' with a WARNING line, that is finding 4 and
# not this case's subject - see load-warning-stream in stage 3, which stages the
# same condition deliberately. The empty-stdout assertion is kept strict here
# anyway: a WARNING on stdout is a real defect wherever it comes from, and this
# case has no business quietly tolerating it.
assert_case info-no-service measured 255 empty once -- info

# The same invocation across every OTHER operation that requires a service.
# Measured identical on the box, so this is one behaviour, not ten - hence one
# aggregated row. What it defends is that the check is not attached to
# operations one at a time, where a new operation can quietly be added without.
#
# The four state-changing operations are held back to an opt-in below.
sweep_no_service ops-require-service measured file jobinfo loginfo perfinfo scrunattrs

# start, stop, restart and kill, with NO service named.
#
# fidelity-gate.sh excludes these operations on the grounds that a suite which
# takes services down on whatever machine it runs on is not worth having, and
# that reasoning holds - but it is about operations given a service to act on.
# With no service named there is nothing to act on, and all four were measured
# at 255 on the box before being written down here.
#
# They are nonetheless the four where a MISSING usage check would be worst: an
# argument-handling slip that let `kill` through with no service named is the
# one defect in this area that could take a system down, and the only way to
# know it has not happened is to run it. That is a decision for whoever runs the
# gate rather than a default, so it is opt-in - and reported when it is off,
# never silently skipped.
if [ -n "$SWEEP_STATE_CHANGING" ]; then
  sweep_no_service state-ops-require-service measured start stop restart kill
else
  report SKIPPED state-ops-require-service \
    "start/stop/restart/kill not run - opt in with SWEEP_STATE_CHANGING=1"
fi

# SUCCESS - sc 1.7.1: 0, and by the contract stderr is silent.
# stdout policy is deliberately 'any': `list` prints "name (description)" with
# no status column and no bar, so the check-row shape does not apply to it. The
# row assertion belongs on `check`, and the check-service case below carries it.
assert_case list-succeeds measured 0 any silent -- list

# SUCCESS WITH A WARNING - an empty named group. sc 1.7.1: 0, warning on stderr.
# Note what this case pins that no other one does: stderr carrying something is
# NOT by itself a failure signal. A warning and an error are told apart by the
# exit status, not by which stream they arrived on. parity.md records this as
# recently fixed - it used to raise an error and exit 255 - so it is exactly the
# behaviour worth holding still.
#
# Its stdout is not empty and must not be asserted to be: a check that matched
# nothing still prints the trailing blank line every check prints. Confirmed
# byte for byte against upstream on the box - both emit exactly one empty line.
assert_case empty-group measured 0 checkrows warn -- check group:nosuchgroup

echo
# ---------------------------------------------------------------------------
echo "== stage 2: the contract, on cases INFERRED from it rather than measured"
echo "   (upstream's status for these was not observed; the expectation comes"
echo "    from the written contract, so weigh a failure accordingly)"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

# INFERRED. A real service on the format-critical path: exit 0, stderr silent,
# and every stdout line parses as a check row. This is the assertion that
# catches the change going too far the other way - an error path rerouted to
# stderr is no good if the success path starts writing there too.
#
# The exit status is NOT asserted against a fixed number here. Whether upstream
# `check` returns non-zero when a service is merely stopped was not measured,
# and hardcoding 0 would make this case fail on a stopped service for a reason
# that has nothing to do with error delivery. Stage 4 compares it against
# upstream instead, which is the honest form of the question.
assert_case check-service inferred 0 checkrows silent -- check "$SERVICE"

# INFERRED. A malformed definition is "understood but cannot be carried out",
# so it is operational: 253, not 255. Different code path again - the file is
# found and read, and fails in the parser rather than in the open.
BADYAML="$WORK/malformed.yaml"
printf 'name: broken\n  bad_indent: [unclosed\n\tliteral tab: yes\n' > "$BADYAML"
assert_case malformed-definition inferred 253 empty once -- check "$BADYAML"

# INFERRED. The two exit values must actually be DIFFERENTIATED. Every
# assertion above could pass individually while the implementation still
# collapsed everything onto one code, if the expectations themselves were
# wrong - so assert the property directly: the measured cases produced both.
have253=0; have255=0; have0=0
for rc in "${MEASURED_EXITS[@]}"; do
  case "$rc" in 253) have253=1 ;; 255) have255=1 ;; 0) have0=1 ;; esac
done
if [ "$have253" -eq 1 ] && [ "$have255" -eq 1 ] && [ "$have0" -eq 1 ]; then
  report PASS codes-differentiated "(inferred) 0, 253 and 255 all observed"
  pass=$((pass+1))
else
  report FAIL codes-differentiated \
    "(inferred) failures are not being told apart: saw [${MEASURED_EXITS[*]}]"
  failed=$((failed+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 3: known differences and open findings, pinned so a change is visible"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

# KNOWN DIFFERENCE, and RMSC keeps its own behaviour for now.
#
#   upstream sc:  warns about the unrecognised option and CARRIES ON, exit 0.
#   RMSC:         refuses, exit 255.
#
# Neither is asserted to be right here. RMSC's side is pinned so that if it ever
# starts tolerating unknown flags - deliberately or otherwise - this says so
# instead of the change passing unnoticed. A CHANGED verdict may well be the
# intended fix arriving: update this case and docs/parity.md together.
#
# The stream and duplication rules still apply. Being a usage failure does not
# license the message onto stdout.
assert_case badflag-pinned pinned 255 empty once -- check --badflag

# KNOWN DIFFERENCE, same terms.
#
#   upstream sc:  prints a version, exit 0.
#   RMSC:         does not know the flag, exit 255.
#
# Worth pinning rather than ignoring: --version is what a packaging script or a
# health check reaches for first, so if it is ever implemented that is a
# user-visible change and should not arrive silently.
assert_case version-pinned pinned 255 empty once -- --version

# KNOWN-OPEN FINDING - a real defect, not a sanctioned difference, and not yet
# scheduled. Reported every run; does NOT fail the gate.
#
# RMSC decides the missing-service case AFTER loading every definition from
# disk, so a definition that will not load produces `WARNING: <name>: <reason>`
# on STDOUT before the usage failure - a non-row line on the stream a
# column-parsing consumer reads, for a command that never ran. Upstream writes
# its load warnings to stderr.
#
# Why this is not simply asserted: it only appears on a system that happens to
# hold a broken definition. A plain assertion would pass on a clean box and fail
# on a dirty one - the machine deciding the verdict, which is the worst kind of
# test. So the broken definition is STAGED, through SC_SERVICES_DIR, which
# parity.md records as RMSC's counterpart to upstream's `services.dir` property
# and as being searched last. Nothing on the system is touched: the staged
# directory lives under $WORK and goes away with the artefacts.
#
# The trap in staging a fixture is that it silently fails to take effect and the
# case then passes while testing nothing - the exact failure CLAUDE.md warns
# about. So the case first proves the warning was produced AT ALL, on either
# stream, and calls the fixture broken if it was not. Only then does it ask
# which stream it landed on.
#
# Upstream is not run here for comparison. Its mechanism is a JVM property
# rather than an environment variable, and setting it through JAVA_TOOL_OPTIONS
# makes the JVM announce itself on stderr - polluting the very stream under
# examination. The coordinator measured upstream's behaviour directly instead.
BROKEN_DIR="$WORK/staged-services"
BROKEN_NAME=rmsc_gate_broken
mkdir -p "$BROKEN_DIR"
printf 'name: %s\ncheck_alive: [unclosed\n\tbad: \x27tab and quote\n' \
  "$BROKEN_NAME" > "$BROKEN_DIR/$BROKEN_NAME.yaml"

SC_SERVICES_DIR="$BROKEN_DIR" "$SCR" info \
  > "$WORK/load-warning.out" 2> "$WORK/load-warning.err"
lw_rc=$?
lw_out=$(grep -Fc -- "$BROKEN_NAME" "$WORK/load-warning.out" 2>/dev/null || true)
lw_err=$(grep -Fc -- "$BROKEN_NAME" "$WORK/load-warning.err" 2>/dev/null || true)
[ -z "$lw_out" ] && lw_out=0
[ -z "$lw_err" ] && lw_err=0

# Hard assertion either way: a load warning must not change the classification.
if [ "$lw_rc" -eq 255 ]; then
  report PASS load-warning-exit "(measured) still exit 255 with a broken definition on disk"
  pass=$((pass+1))
else
  report FAIL load-warning-exit "(measured) exit $lw_rc with a broken definition on disk, wanted 255"
  failed=$((failed+1))
fi

if [ "$lw_out" -eq 0 ] && [ "$lw_err" -eq 0 ]; then
  # Not a pass. The staged definition never reached the loader, so the case
  # below proved nothing at all, and saying so is the whole point.
  report FAIL load-warning-stream \
    "FIXTURE DID NOT TAKE: no warning about $BROKEN_NAME on either stream"
  printf '  %-9s %-30s   - %s\n' "" "" "SC_SERVICES_DIR=$BROKEN_DIR was not read, or the file parsed cleanly"
  printf '  %-9s %-30s   - %s\n' "" "" "this case cannot report on finding 4 until the fixture works"
  failed=$((failed+1))
elif [ "$lw_out" -gt 0 ]; then
  report OPEN load-warning-stream \
    "finding 4: load warning on STDOUT ($lw_out line(s)) for a command that never ran"
  printf '  %-9s %-30s   - %s\n' "" "" "upstream writes load warnings to stderr; a column-parsing consumer reads this"
  printf '  %-9s %-30s   - %s\n' "" "" "known and open - not failing the gate; artefacts: load-warning.out"
  open_n=$((open_n+1))
else
  report FIXED load-warning-stream \
    "load warning now on stderr only - finding 4 looks fixed"
  printf '  %-9s %-30s   - %s\n' "" "" "promote this to a hard assertion and drop it from the known-open list"
  stale=$((stale+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 4: upstream reference, re-confirmed"
echo "   (the 'measured' expectations above are only as good as this table;"
echo "    a REFDRIFT means the reference moved, not that RMSC regressed)"
echo
printf '  %-9s %-30s %s\n' verdict case detail
printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
# ---------------------------------------------------------------------------

confirm_upstream unknown-service       253 -- check nosuchservice
confirm_upstream unknown-operation     255 -- wibble
confirm_upstream no-operation          255 --
confirm_upstream unloadable-definition 253 -- check "$NOSUCH_YAML"
confirm_upstream info-no-service       255 -- info
confirm_upstream list-succeeds           0 -- list
confirm_upstream empty-group             0 -- check group:nosuchgroup
confirm_upstream badflag-tolerated       0 -- check --badflag
confirm_upstream version-flag            0 -- --version

# The differential the check-service case defers to: whatever upstream makes of
# a real service, RMSC should make the same. This is the only exit status here
# compared implementation-to-implementation rather than against a number, and it
# is the right form for a value that depends on whether the service is up.
"$SC"  check "$SERVICE" > "$WORK/sc.check-service.out"  2> "$WORK/sc.check-service.err"; sc_rc=$?
"$SCR" check "$SERVICE" > "$WORK/scr.check-service.out" 2> "$WORK/scr.check-service.err"; scr_rc=$?
if [ "$sc_rc" -eq "$scr_rc" ]; then
  report PASS check-service-agrees "both exit $sc_rc for a real service"
  pass=$((pass+1))
else
  report FAIL check-service-agrees "sc exits $sc_rc, scr exits $scr_rc for the same service"
  failed=$((failed+1))
fi

echo
echo "pass=$pass   failed=$failed   pinned-changed=$changed   known-open=$open_n   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out and .err captured separately for every case)"

# ---------------------------------------------------------------------------
# WHAT A SHELL SCRIPT CANNOT ASSERT, and where it would have to be done instead
#
#   Whether an escape message is still SIGNALLED. This script sees the outcome,
#   not the mechanism. RMSC could keep signalling CPF9897 and have something
#   downstream tidy the streams, and every assertion here would pass while the
#   joblog filled with escapes. That needs the joblog - QMHRCVPM from ILE, or
#   DSPJOBLOG against the job the wrapper ran in - not a shell.
#
#   Where the exit status is DECIDED. The wrapper execs `system`, so what the
#   shell reads is `system`'s status. Whether 253 came from RMSC choosing it or
#   from something mapping an exception onto it is invisible from out here.
#
#   INTERLEAVING. The streams are captured separately, on purpose, which throws
#   the relative order away. A consumer reading a merged stream could still see
#   an error land between two rows. Testing that needs a second run through a
#   pty or a merged capture, and it is a different question from this one -
#   worth its own case if a consumer ever reads them merged.
#
#   The TTY path. Everything here runs with stdout redirected, so the wrapper
#   never appends --colors. How errors are delivered when stdout IS a terminal
#   is not reached; parity.md already notes that the colour differences need a
#   person at a terminal rather than a diff.
#
#   MESSAGE TEXT against upstream, deliberately - see the header.
#
#   Whether stderr is UNBUFFERED relative to stdout within one run, and whether
#   a long-running check flushes rows before it fails. Both are timing
#   properties; a redirected capture cannot see either.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: error delivery does not match the contract"
  exit 1
fi
if [ "$changed" -ne 0 ]; then
  echo "PINNED BEHAVIOUR CHANGED: $changed known difference(s) moved."
  echo "If that was intended, update this script and docs/parity.md together."
  exit 1
fi
if [ "$stale" -ne 0 ]; then
  echo "KNOWN-OPEN FINDING LOOKS FIXED: $stale of them."
  echo "This fails on purpose, the way fidelity-gate.sh fails when something starts"
  echo "matching: a classification that can go stale unnoticed is worth nothing."
  echo "Promote the case to a hard assertion and remove it from the known-open list."
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer classifies as recorded."
  echo "The 'measured' expectations in stage 1 rest on that table - re-take it"
  echo "before trusting a pass or acting on a failure."
  exit 1
fi
if [ "$open_n" -ne 0 ]; then
  echo "OK, WITH $open_n KNOWN-OPEN FINDING(S): the contract holds everywhere it is"
  echo "settled; see the OPEN row(s) above for what is not."
  exit 0
fi
echo "OK: errors go to stderr only, once, unprefixed, with a status that names the kind"
