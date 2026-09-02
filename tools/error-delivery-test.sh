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

# open_n and stale drive the known-open mechanism: a finding reported every run
# without failing the gate, which then fails the gate once it starts passing so
# the classification cannot go stale. THERE ARE NO KNOWN-OPEN FINDINGS AT
# PRESENT - finding 4 was the last one and was promoted to a hard assertion when
# D4 was picked up. The machinery is kept, not dead code by oversight: it is how
# the next unscheduled defect gets reported without blocking the gate.
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
#                  sanctioned for a command that SUCCEEDS: no line that is not a
#                             load warning, and nothing at all if upstream was
#                             silent. Runs upstream to ask. Replaced 'silent'
#                             on the two success cases when D4 moved load
#                             warnings onto stderr - see list-succeeds.
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
    sanctioned)
      # See the long comment at list-succeeds for why the success path can no
      # longer be asked to keep stderr EMPTY, and what is asked instead.
      "$SC" "$@" > "$WORK/sc-diff.$tag.out" 2> "$WORK/sc-diff.$tag.err"
      local sc_n; sc_n=$(count_lines "$WORK/sc-diff.$tag.err")

      # (a) Machine-independent. Load warnings are sanctioned on stderr for a
      # command that succeeded - D4 put them there and upstream does the same.
      # ANY OTHER line is the success path writing where it should not, which is
      # the regression this case has always existed to catch.
      local nonwarn
      nonwarn=$(grep -vE '^[[:space:]]*$' "$e" 2>/dev/null | grep -cvE '^WARNING' || true)
      [ -z "$nonwarn" ] && nonwarn=0
      [ "$nonwarn" -eq 0 ] || problems+=("$nonwarn non-warning line(s) on stderr for a command that succeeded: $(grep -vE '^[[:space:]]*$' "$e" | grep -m1 -vE '^WARNING')")

      # (b) Differential. If upstream had nothing to say on this machine, RMSC
      # saying anything is RMSC's own doing and not the profile's.
      if [ "$sc_n" -eq 0 ] && [ "$n_err" -ne 0 ]; then
        problems+=("upstream's stderr is silent for this command and RMSC's is not ($n_err line(s)): $(head -n 1 "$e")")
      fi

      # Say - loudly - when the case is running in its WEAK form. A green row on
      # a profile that already produces load warnings does not mean what a green
      # row on a clean one means, and a run that does not say so invites the
      # stronger reading. The verdict column is what gets scanned in scrollback,
      # so the qualifier goes THERE and not only in the detail text: WEAKENED
      # sits directly above the PASS it applies to and cannot be read past.
      if [ "$sc_n" -ne 0 ]; then
        report WEAKENED "$tag" "the PASS below is REDUCED - sc wrote $sc_n stderr line(s) here too, so 'nothing upstream would not' could not be checked; extra or reworded RMSC warnings would go unnoticed on this profile"
      fi ;;
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

# SUCCESS - sc 1.7.1: 0.
# stdout policy is deliberately 'any': `list` prints "name (description)" with
# no status column and no bar, so the check-row shape does not apply to it. The
# row assertion belongs on `check`, and the check-service case below carries it.
#
# THIS CASE USED TO ASSERT stderr WAS SILENT, AND CANNOT ANY MORE.
#
# D4 moved load warnings from stdout to stderr, and 57ba0ad added "Ignoring
# file" warnings. So on any profile whose search path holds an ignorable or
# unloadable definition, a perfectly correct `list` now writes to stderr.
# Measured on a populated profile: rc=0 with 5 stderr lines from BOTH
# implementations, byte-identical, e.g.
#
#     WARNING: Ignoring file: /home/<user>/.sc/services/rm-test-noext
#
# RMSC and upstream agree exactly, so this is not a parity defect. The
# assertion had simply stopped describing either implementation and started
# describing the MACHINE - the trap the load-warning case in stage 3 documents
# at length: "a plain assertion would pass on a clean box and fail on a dirty
# one - the machine deciding the verdict, which is the worst kind of test".
#
# Staging cannot rescue it the way it rescues finding 4. The offending files
# live in the user directory, and there is no option that skips it -
# --ignore-globals still reads it.
#
# WHAT THE CASE WAS PROTECTING, AND STILL DOES. check-service's comment puts it
# best: the silent assertion caught "the change going too far the other way -
# an error path rerouted to stderr is no good if the success path starts
# writing there too". That concern is live and survives, restated as "RMSC
# writes nothing upstream would not" rather than "RMSC writes nothing":
#
#   (a) no line on stderr that is not a load warning - machine-independent,
#       and the direct expression of the original concern;
#   (b) if upstream was silent for this command, RMSC must be too.
#
# WHAT IT COSTS, stated plainly rather than glossed. On a profile where
# upstream ALREADY warns, (b) is vacuous and only (a) is in force - so RMSC
# could emit extra or differently-worded WARNING lines and this would pass.
# That is the weak form, and it is weakest on exactly the machines where the
# success path is most likely to regress: a developer's populated box. The run
# says so rather than leaving it to be assumed - a NOTE row marks the case
# reduced whenever upstream itself wrote to stderr, so a green row on a dirty
# profile does not read the same as a green row on a clean one.
#
# The residue - whether RMSC's warnings match upstream's in wording and number
# - is D2's, deliberately: upstream emits two lines per bad file where RMSC
# emits one. Asserting it here would fail for the right reason at the wrong
# time.
assert_case list-succeeds measured 0 any sanctioned -- list

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

# INFERRED. A real service on the format-critical path: every stdout line parses
# as a check row, and nothing appears on stderr that upstream would not have put
# there. This is the assertion that catches the change going too far the other
# way - an error path rerouted to stderr is no good if the success path starts
# writing there too.
#
# STDERR IS NOW A DIFFERENTIAL QUESTION, for the reason set out at length above
# list-succeeds: D4 put load warnings on stderr, so a correct `check` writes
# there on any profile holding an ignorable or unloadable definition, and both
# implementations were measured doing it identically. The concern above is
# unchanged; only its expression is. This case's own comment already argued for
# the differential form on the exit status - "Stage 4 compares it against
# upstream instead, which is the honest form of the question" - and the same is
# now true of its stderr.
#
# THE EXIT STATUS IS ASSERTED AGAINST 0, AND THAT IS CORRECT. An earlier version
# of this comment claimed the opposite - that the status was not asserted
# against a fixed number, and that stage 4 compared it instead - while the call
# passed 0 and asserted it like any other. The comment was wrong about the code;
# the code was right about the contract.
#
# MEASURED IN BOTH STATES, so this does not want re-opening: `check <service>`
# exits 0 for both implementations on a clean profile AND on one carrying a
# definition whose criterion cannot be evaluated - the shape that does force 253
# elsewhere, documented at sc:badflag-tolerated in stage 4. Naming a service is
# what saves it: that 253 only arises when a sweep actually evaluates the bad
# definition, and scoping to one service means it never does.
#
# Stage 4's check-service-agrees still compares the two implementations for the
# same service, which remains the right question for a value that depends on
# whether the service happens to be up.
assert_case check-service inferred 0 checkrows sanctioned -- check "$SERVICE"

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

# PROMOTED FROM KNOWN-OPEN TO A HARD ASSERTION. This was finding 4, reported
# every run and not failing the gate. It is now asserted, because the work it
# was waiting on is D4 and D4 is being done: a finding that stays "open" once
# somebody is acting on it stops being information and becomes noise.
#
# Promoting it BEFORE the fix is deliberate. The case's own instruction was to
# promote it "when it starts passing", which would have meant a run in between
# reporting FIXED and failing the gate on staleness - a red that means "the
# bookkeeping is behind", not "the code is wrong". Asserting now means the next
# red is the defect and the one after it is the fix.
#
# WHAT IS WRONG. RMSC loads every definition from disk BEFORE deciding what the
# command was, so a definition that will not load produces
# `WARNING: <name>: <reason>` on STDOUT - a non-row line on the stream a
# column-parsing consumer reads. Measured against sc 1.7.1 today, with a
# definition present that cannot load:
#
#   sc info    (no service named)  exit 255, stdout EMPTY, usage on stderr,
#                                  and no load warnings anywhere
#   scr info                       exit 255, but one line on STDOUT:
#                                  "WARNING: d4_broken: ... has no start_cmd"
#
#   sc list                        0 warning lines on stdout, 2 on stderr
#   scr list                       1 on stdout, 0 on stderr
#
# WHY THE FIXTURE IS STAGED. The behaviour only appears on a system that happens
# to hold a broken definition. A plain assertion would pass on a clean box and
# fail on a dirty one - the machine deciding the verdict, which is the worst
# kind of test. So the broken definition is STAGED, through SC_SERVICES_DIR,
# which parity.md records as RMSC's counterpart to upstream's `services.dir`
# property and as being searched last. Nothing on the system is touched: the
# staged directory lives under $WORK and goes away with the artefacts.
#
# The trap in staging is that it silently fails to take effect and the case then
# passes while testing nothing - the exact failure CLAUDE.md warns about. Both
# cases below therefore prove the warning was produced AT ALL, on either stream,
# and hard-fail as a BROKEN FIXTURE if it was not, before asking which stream it
# landed on. Neither can go green by the staging quietly not working.
#
# WHAT IS DELIBERATELY NOT ASSERTED: the number of warning lines, and their
# wording. Upstream emits two lines per bad file where RMSC emits one, and words
# them differently. That difference is real and it belongs to D2 - asserting it
# here would fail for the right reason at the wrong time, and would have to be
# rewritten by the change that fixes it. So stderr is asserted to carry AT LEAST
# one, never exactly one.
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

# A SECOND broken definition, broken a different way. The one above fails in
# the PARSER; this one parses cleanly and fails VALIDATION, because start_cmd
# is required and absent. Both produce a load warning and they reach it by
# different code paths, so a fix that routes one to stderr and not the other is
# visible rather than half-credited.
#
# It is also the exact condition the D4 measurements were taken under - "a
# definition present that cannot load (no start_cmd)" - so the assertions below
# are made against the same shape upstream was observed with, not a cousin.
D4_NAME=rmsc_d4_nostart
printf 'name: D4 no start\ncheck_alive: 59401\n' \
  > "$BROKEN_DIR/$D4_NAME.yaml"

# BOTH RUNS FIRST, THEN THE STAGING PROOF, THEN THE ASSERTIONS. The order is
# not tidiness: the proof has to come from a command that reads the disk, and
# `info` is the command being asserted NOT to read it.
SC_SERVICES_DIR="$BROKEN_DIR" "$SCR" info \
  > "$WORK/load-warning.out" 2> "$WORK/load-warning.err"
lw_rc=$?

SC_SERVICES_DIR="$BROKEN_DIR" "$SCR" list \
  > "$WORK/load-warning-list.out" 2> "$WORK/load-warning-list.err"

# staged_warnings FILE - lines that are a LOAD WARNING about a staged
# definition: the name and the word WARNING on the same line.
#
# THE NAME ALONE IS NOT ENOUGH, and "match the name" is the obvious thing to
# write, so here is why it is wrong. `list` prints a successfully loaded
# definition's short name as an ordinary stdout row. If a staged file ever
# stopped being broken - a parser change that accepts the malformed one, or
# start_cmd ceasing to be required - a name-only guard would see that row,
# count it as evidence the staging worked, and report the fixture healthy.
# D4(2) would then fail with "load warning on STDOUT" while quoting a line that
# is not a warning at all. The run would still be red, so nothing passes while
# testing nothing; the cost is a misdiagnosed headline with the real evidence
# printed just underneath it, which is exactly the kind of failure that wastes
# an afternoon.
#
# Requiring WARNING keeps the guard invariant under the change it has to
# survive. The warning text is byte-identical before and after this fix - only
# the stream moves - and it survives D2 too, since upstream's two-line form
# still carries WARNING on the line naming the file.
#
# CONTRAST WITH THE GROUP GUARD in D4(3), which proves membership from the
# stdout rows of `check group:` and is right to. The same shape is safe there
# and unsafe here, and the difference is worth naming: whether the command's
# ORDINARY OUTPUT can be mistaken for the evidence. For `check group:` the rows
# ARE the evidence and nothing in D4 moves them. For `list` the rows are
# bystanders that happen to contain the same string the evidence does.
staged_warnings() {
  grep -E -- "$BROKEN_NAME|$D4_NAME" "$1" 2>/dev/null | grep 'WARNING' || true
}

ll_out=$(staged_warnings "$WORK/load-warning-list.out" | grep -c '' || true)
ll_err=$(staged_warnings "$WORK/load-warning-list.err" | grep -c '' || true)
[ -z "$ll_out" ] && ll_out=0
[ -z "$ll_err" ] && ll_err=0

# STAGING PROOF, shared by both D4 cases below.
#
# A FIXTURE-INTEGRITY CHECK MUST NOT DEPEND ON BEHAVIOUR THE FIX WILL CHANGE.
# That is the general lesson here and it is worth more than the case itself.
#
# The first version of this proved staging from the `info` run: a warning about
# the broken definition on one stream or the other. That was sound while RMSC
# loaded the disk before deciding what the command was - and the whole point of
# D4(1) is that it must STOP doing so. With the fix in place `info` never loads,
# so it never warns, and the guard read "no warning" and concluded the staging
# had failed. The guard's premise was destroyed by the fix succeeding: it became
# unable to tell a working fixture from an absent one, which is the exact trap
# it was written to avoid, one level up.
#
# So the proof comes from `list` instead - a command that reads the disk under
# every version of this behaviour, and must warn either way. What changes with
# the fix is WHICH STREAM the warning lands on, so a proof that accepts it on
# EITHER is invariant under the fix. That is the property to look for: not "does
# this observe something true today", but "does it observe something the change
# under test cannot move".
#
# It costs nothing extra. The `list` run was already being made for D4(2); it
# only had to happen before the assertion that depends on it rather than after.
#
# What counts as evidence is narrower than it looks - see staged_warnings
# above, which requires the word WARNING and not merely the definition's name.
if [ "$ll_out" -eq 0 ] && [ "$ll_err" -eq 0 ]; then
  staging_ok=0
  report FAIL staged-definitions \
    "FIXTURE DID NOT TAKE: list warned about neither staged definition"
  printf '  %-9s %-30s   - %s\n' "" "" "SC_SERVICES_DIR=$BROKEN_DIR was not read, or both files parsed and validated cleanly"
  printf '  %-9s %-30s   - %s\n' "" "" "the two D4 cases below are not evidence until this works"
  failed=$((failed+1))
else
  staging_ok=1
  report PASS staged-definitions \
    "(fixture) list warns about the staged definitions - stdout $ll_out, stderr $ll_err"
  pass=$((pass+1))
fi

# Hard assertion either way: a load warning must not change the classification.
if [ "$lw_rc" -eq 255 ]; then
  report PASS load-warning-exit "(measured) still exit 255 with a broken definition on disk"
  pass=$((pass+1))
else
  report FAIL load-warning-exit "(measured) exit $lw_rc with a broken definition on disk, wanted 255"
  failed=$((failed+1))
fi

# D4(1) - A USAGE FAILURE IS DECIDED BEFORE ANYTHING IS READ FROM DISK.
#
# `info` with no service named is a usage failure. Upstream answers it from the
# arguments alone: exit 255, usage block on stderr, and stdout COMPLETELY EMPTY
# however much broken YAML is lying about on disk. RMSC reached the same exit
# status, having first loaded everything and warned on stdout about a definition
# belonging to a command that never ran.
#
# The property asserted is the strong one - stdout empty, not merely free of
# warnings. That is what the existing info-no-service case asserts on a clean
# box; this one asserts it with a broken definition deliberately in the way.
#
# Its fixture guard is the staged-definitions proof above, NOT anything read
# from this run. See the note there for why that distinction matters.
if [ "$staging_ok" -eq 0 ]; then
  report SKIPPED usage-stdout-clean "staged-definitions failed - see above"
else
  lw_lines=$(count_lines "$WORK/load-warning.out")
  if [ "$lw_lines" -eq 0 ]; then
    report PASS usage-stdout-clean \
      "(measured) stdout empty for a usage failure, with broken YAML on disk"
    pass=$((pass+1))
  else
    report FAIL usage-stdout-clean \
      "(measured) $lw_lines line(s) on STDOUT for a command that never ran"
    printf '  %-9s %-30s   - %s\n' "" "" "first line: $(head -n 1 "$WORK/load-warning.out")"
    printf '  %-9s %-30s   - %s\n' "" "" "upstream decides usage from the arguments and reads nothing"
    printf '  %-9s %-30s   - %s\n' "" "" "artefacts: load-warning.out load-warning.err"
    failed=$((failed+1))
  fi
fi

# D4(2) - LOAD WARNINGS GO TO STDERR.
#
# The same staged definitions through `list`, which is a command that SUCCEEDS.
# That is the difference from the case above: there, stdout must be empty
# because nothing ran; here stdout legitimately carries the service listing and
# the question is only whether a warning is mixed into it.
#
# So this counts lines mentioning the broken definitions rather than counting
# lines. A definition that will not load is not listed, so any stdout line
# naming one is a warning that has landed on the wrong stream.
#
# The COUNT on stderr is not asserted, only that there is at least one. Upstream
# emits two lines per bad file where RMSC emits one, and words them differently;
# that difference is real and belongs to D2. Asserting it here would fail for
# the right reason at the wrong time.
if [ "$staging_ok" -eq 0 ]; then
  report SKIPPED load-warning-stream "staged-definitions failed - see above"
elif [ "$ll_out" -gt 0 ]; then
  report FAIL load-warning-stream \
    "(measured) load warning on STDOUT ($ll_out line(s)) during a successful list"
  printf '  %-9s %-30s   - %s\n' "" "" "first line: $(staged_warnings "$WORK/load-warning-list.out" | head -n 1)"
  printf '  %-9s %-30s   - %s\n' "" "" "upstream puts these on stderr; a column-parsing consumer reads stdout"
  printf '  %-9s %-30s   - %s\n' "" "" "artefacts: load-warning-list.out load-warning-list.err"
  failed=$((failed+1))
else
  report PASS load-warning-stream \
    "(measured) $ll_err load warning line(s), stderr only - was finding 4"
  pass=$((pass+1))
fi

# D4(3) - PER-MEMBER ERRORS FROM A GROUP OPERATION GO TO STDERR.
#
# Two definitions in a group of their own, whose start_cmd is /QOpenSys/usr/bin/
# false. They load, they fail to start, and startup_wait_time: 2 makes them fail
# quickly rather than holding the run for the default 60 seconds each.
#
# WHY THIS ONE RUNS BY DEFAULT WHERE THE STATE-CHANGING SWEEP DOES NOT. That
# sweep is opt-in because `stop`, `restart` and `kill` act on whatever real
# services the machine has. This acts only on two definitions this script has
# just written, in a group it invented, whose start command exits non-zero
# immediately. Nothing on the system is started, nothing is stopped, and there
# is nothing left running afterwards to clean up. The risk that made the sweep
# opt-in is not present here.
#
# EXIT 0 IS CORRECT AND MUST NOT BE "FIXED". Upstream exits 0 from a group start
# even when EVERY member fails, and RMSC already matches it. It looks like a
# defect and is not; the plan records it as a trap. Asserting 0 pins the half
# that is right, so that a well-meaning change to the half that is wrong does
# not take it with it.
#
# THE WORDING IS NOT ASSERTED. Upstream names the service by its FRIENDLY name
# where RMSC uses the short name - another D2 item. Only the ERROR: prefix is
# matched, which both produce.
#
# STDOUT IS ASSERTED FREE OF ERROR LINES, NOT EMPTY, and the distinction is
# load-bearing. Upstream also prints "Performing operation 'START' on service
# 'x'" to stdout per member and RMSC prints nothing. WHETHER RMSC SHOULD GAIN
# THOSE LINES IS OUTSTANDING WITH RICHARD AND IS NOT DECIDED HERE. Asserting an
# empty stdout would silently settle it in the negative and would then have to
# be undone; asserting only the absence of ERROR lines is true under either
# answer. Do not read the absence of an assertion here as a decision.
GROUP_DIR="$WORK/staged-group"
D4_GROUP=rmscd4grp
mkdir -p "$GROUP_DIR"
for m in one two; do
  printf 'name: Fail %s\nstart_cmd: /QOpenSys/usr/bin/false\ncheck_alive: 594%s\nstartup_wait_time: 2\ngroups:\n- %s\n' \
    "$m" "$([ "$m" = one ] && echo 11 || echo 12)" "$D4_GROUP" \
    > "$GROUP_DIR/d4_fail$m.yaml"
done

if [ ! -x /QOpenSys/usr/bin/false ]; then
  report FAIL group-member-error-stream \
    "FIXTURE UNAVAILABLE: /QOpenSys/usr/bin/false is not executable"
  printf '  %-9s %-30s   - %s\n' "" "" "the staged services need a command that fails immediately"
  failed=$((failed+1))
else
  # PROVE THE STAGING TOOK before starting anything. If SC_SERVICES_DIR were not
  # read, 'start group:...' would match nothing, print no ERROR, and the
  # assertions below would pass on an empty run - the fixture failure that looks
  # exactly like success. A check first says the group exists and has both
  # members in it.
  SC_SERVICES_DIR="$GROUP_DIR" "$SCR" check "group:$D4_GROUP" \
    > "$WORK/group-check.out" 2> "$WORK/group-check.err"
  gm=$(grep -c 'd4_fail' "$WORK/group-check.out" 2>/dev/null || true)
  [ -z "$gm" ] && gm=0

  if [ "$gm" -ne 2 ]; then
    report FAIL group-member-error-stream \
      "FIXTURE DID NOT TAKE: group:$D4_GROUP has $gm member(s) on check, wanted 2"
    printf '  %-9s %-30s   - %s\n' "" "" "SC_SERVICES_DIR=$GROUP_DIR was not read, or the definitions did not load"
    printf '  %-9s %-30s   - %s\n' "" "" "artefacts: group-check.out group-check.err"
    failed=$((failed+1))
  else
    SC_SERVICES_DIR="$GROUP_DIR" "$SCR" start "group:$D4_GROUP" \
      > "$WORK/group-start.out" 2> "$WORK/group-start.err"
    gs_rc=$?
    gs_out=$(grep -c 'ERROR' "$WORK/group-start.out" 2>/dev/null || true)
    gs_err=$(grep -c 'ERROR' "$WORK/group-start.err" 2>/dev/null || true)
    [ -z "$gs_out" ] && gs_out=0
    [ -z "$gs_err" ] && gs_err=0

    gproblems=()
    [ "$gs_rc" -eq 0 ] || gproblems+=("exit $gs_rc, wanted 0 - upstream exits 0 here too, see the comment")
    [ "$gs_err" -ge 1 ] || gproblems+=("no ERROR line on stderr - the failures were reported somewhere else, or not at all")
    [ "$gs_out" -eq 0 ] || gproblems+=("$gs_out ERROR line(s) on STDOUT: $(grep -m1 'ERROR' "$WORK/group-start.out")")

    if [ ${#gproblems[@]} -eq 0 ]; then
      report PASS group-member-error-stream \
        "(measured) exit 0, $gs_err ERROR line(s) on stderr, none on stdout"
      pass=$((pass+1))
    else
      report FAIL group-member-error-stream "(measured)"
      for gp in "${gproblems[@]}"; do printf '  %-9s %-30s   - %s\n' "" "" "$gp"; done
      printf '  %-9s %-30s   - %s\n' "" "" "artefacts: group-start.out group-start.err"
      failed=$((failed+1))
    fi
  fi
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
confirm_upstream version-flag            0 -- --version

# BADFLAG - a RELATION, not a fixed number, and the reason is worth recording
# because the mechanism is not the obvious one.
#
# This row used to read `confirm_upstream badflag-tolerated 0`. On a populated
# profile upstream exits 253 here, so the reference described the machine rather
# than upstream - the same fault the two success cases in stage 1 were carrying,
# and it fails the whole run through REFDRIFT.
#
# WHAT ACTUALLY FORCES 253, measured with each shape staged alone in the user
# directory. It is NOT an unloadable definition, which was the first guess and
# is wrong:
#
#     unloadable (no start_cmd)        sc=0    scr=0
#     UNUSABLE CRITERION (port: abc)   sc=253  scr=253    <- this one
#     malformed YAML                   sc=0    scr=0
#     nothing staged                   sc=0    scr=0
#
# So it takes a definition that LOADS and whose criterion cannot be evaluated.
# A profile carrying one alongside some unloadable files looks as though the
# unloadable files caused it, and they did not.
#
# That also explains why empty-group and check-service keep their hardcoded 0
# and are not fragile: both scope to a group or a service that has no unusable
# criterion, and the 253 only arises when a sweep actually evaluates the bad
# definition. Measured at 0 in both states. Do not "fix" them to match this.
#
# THE RELATION. What this row exists to record is that upstream does not treat
# an unrecognised flag as a usage failure - it warns and carries on. Expressed
# as "the flag changes nothing", which holds in both states: 0 and 0 on a clean
# profile, 253 and 253 on a populated one.
#
# RMSC still exits 255 here, against upstream's tolerate-and-continue. That is
# the known D3 difference, already recorded, held by badflag-pinned in stage 3,
# and NOT to be fixed here.
"$SC" check --badflag > "$WORK/sc.badflag.out"     2> "$WORK/sc.badflag.err";     sc_flag_rc=$?
"$SC" check           > "$WORK/sc.plaincheck.out"  2> "$WORK/sc.plaincheck.err";  sc_plain_rc=$?
if [ "$sc_flag_rc" -eq "$sc_plain_rc" ]; then
  report PASS sc:badflag-tolerated "the flag changes nothing: both exit $sc_flag_rc"
  pass=$((pass+1))
else
  report REFDRIFT sc:badflag-tolerated \
    "sc exits $sc_flag_rc with --badflag but $sc_plain_rc without it - it is no longer merely tolerating the flag"
  refdrift=$((refdrift+1))
fi

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
