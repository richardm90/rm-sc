#!/QOpenSys/pkgs/bin/bash
#
# adhoc-name-test.sh - what an AD HOC service is CALLED, and everywhere that
# name comes back out.
#
# An ad-hoc service is one named on the command line by a specifier rather than
# by a definition - `scr check port:22`, `scr check job:QINTER`. It has a name
# and a description like any other service, and both are constructed rather
# than read from a file.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses,
# and modelled on tools/jobinfo-test.sh.
#
# ---------------------------------------------------------------------------
# WHY A NEW FILE
# ---------------------------------------------------------------------------
#
#   fidelity-gate.sh        CANNOT SEE THIS AT ALL, and docs/parity.md says so
#                           in as many words: the gate sweeps `<op> <service>`
#                           over the names `scr list` returns, and an ad-hoc
#                           service has no definition and appears in no `list`.
#                           There is no specifier anywhere in the gate. Widening
#                           it would also mean re-capturing the byte-exact
#                           BASELINE, which lives outside this repository
#                           because it names real services - a large change to
#                           a fixture nobody here can hold, for a question a
#                           live differential answers just as strongly.
#
#   the iRPGUnit suites     Would test the naming procedure and not the naming.
#                           The rule under test is "the ad-hoc service is
#                           CONSTRUCTED with this name", and its whole content
#                           is that SIX different printing surfaces then agree
#                           about it (see below). A unit test reaches one
#                           procedure; the rival it has to rule out is a fix
#                           applied at a printing site, which by construction
#                           looks correct from inside.
#
#   jobinfo-test.sh         Owns `jobinfo`'s LAYOUT - the header construct, the
#                           indent, the bare job line, the blank per command -
#                           over a staged, DEFINED fixture. This file asserts
#                           only WHAT GOES IN the header for an AD HOC service,
#                           and asserts nothing about the lines under it. The
#                           two files touch the same line of output and ask
#                           different questions of it; change one and read the
#                           other.
#
#   loginfo-test.sh         Owns which STREAM `loginfo` prints on and what its
#                           log-directory text says. Same split: this file
#                           asserts the NAME at the front of that line and
#                           takes the rest of it from upstream in the same run.
#
#   colour-test.sh          Owns colour. Nothing here is about colour, and
#                           every capture below is a redirection to a file, so
#                           colour is off in both implementations throughout.
#
# ---------------------------------------------------------------------------
# WHAT IS BEING TESTED - measured against sc 1.7.1 on 10 September 2026
# ---------------------------------------------------------------------------
#
# THE RULE, in full, every form:
#
#   specifier             name                        description
#   port:22               ad_hoc_port_22              Ad hoc service running at port 22
#   port:0                ad_hoc_port_0               Ad hoc service running at port 0
#   port:65535            ad_hoc_port_65535           Ad hoc service running at port 65535
#   job:QINTER            ad_hoc_job_QINTER           Ad hoc service running at job QINTER
#   job:qinter            ad_hoc_job_qinter           Ad hoc service running at job qinter
#   job:QUSRWRK/QINTER    ad_hoc_job_QUSRWRK_QINTER   Ad hoc service running at job QUSRWRK/QINTER
#   job:qusrwrk/qinter    ad_hoc_job_qusrwrk_qinter   Ad hoc service running at job qusrwrk/qinter
#
# RMSC before this change: `port:22 (ad hoc port 22)`, `job:QINTER (ad hoc job
# QINTER)` - and, measured rather than assumed, `job:qinter` came back
# UPPER-CASED as `job:QINTER (ad hoc job QINTER)`. See rival 2.
#
# ---------------------------------------------------------------------------
# THE RIVALS EACH CASE HAS TO RULE OUT
# ---------------------------------------------------------------------------
#
#   1. THE NAME AND THE DESCRIPTION ARE TWO CHANGES. Renaming the service and
#      leaving `ad hoc port 22` behind as the description passes any case that
#      looks only at the name. Every case here asserts BOTH, as whole fields,
#      byte for byte - `Ad hoc service running at port 22`, capital A. Nothing
#      about that wording is derivable from RMSC's current text.
#
#      Stage 1 goes further and asserts the WHOLE `check` ROW, because the row
#      is the byte-exact surface: two leading spaces, the status left-justified
#      in eighteen, ` | `, the name, ` (`, the description, `) `. A name and a
#      description that are individually right inside a row that has lost its
#      trailing space is still a row the consumer mis-parses.
#
#   2. CASE IS PRESERVED, NOT UPPER-CASED. `job:qinter` gives
#      `ad_hoc_job_qinter` and `... at job qinter`. THIS IS NOT HYPOTHETICAL
#      AND IT IS NOT EVEN A RIVAL - it is what RMSC does TODAY: it upper-cases
#      a job name when it builds the check-alive criterion, which is correct
#      and must not change, and the ad-hoc name follows it, which is not. So
#      the lower-case forms are the two cases that separate "the name is built
#      from the specifier" from "the name is built from the criterion", and a
#      fixture using only upper-case input separates nothing.
#
#      `job:qinter` and `job:qusrwrk/qinter` are BOTH here for that reason and
#      neither is redundant: one carries the case question alone, the other
#      carries it together with rival 3.
#
#      THE OTHER HALF OF RIVAL 2 IS PINNED IN STAGE 4. The criterion's
#      upper-casing is not a casualty of this change - it is the REASON the
#      name and the criterion had to become two values - so a suite that
#      watches only the name would not notice the split being undone from the
#      other end, by dropping the upper-casing to make the name come out right.
#      One `info` on a lower-case subsystem-qualified specifier shows both
#      values in one capture, which is the whole of the split in one command.
#
#   3. THE SLASH IS TRANSLATED IN THE NAME AND NOT IN THE DESCRIPTION.
#      `job:QUSRWRK/QINTER` gives name `ad_hoc_job_QUSRWRK_QINTER` and
#      description `... at job QUSRWRK/QINTER`. Build both from one translated
#      string and the description is wrong; build both from the raw string and
#      the name is wrong. ONLY the subsystem-qualified forms can see this, so a
#      suite without them has not tested the rule at all.
#
#   4. IT PROPAGATES - and it propagates further than two operations.
#
#      The brief for this work named `jobinfo` and `loginfo`. Sweeping every
#      read-only operation on 10 September 2026 found SIX surfaces carrying the
#      ad-hoc name, and the four that were not asked for are exactly the ones a
#      fix applied at printing sites would leave behind:
#
#        check       `  <status> | <name> (<desc>) `      byte-exact row
#        jobinfo     `<name> (<desc>):`                   header line
#        info        `<name> (<desc>)`                    header line
#        perfinfo    `<name> (<desc>)`                    header line
#        loginfo     `<name>: <unknown> (try checking...` on STDERR
#        scrunattrs  `<name>: SCOMMANDER_NAME=<name>`     and FRIENDLY_NAME,
#                                                         and the LOGFILE path
#
#      The last is the sharpest, because it is not a printing surface at all -
#      it reads the constructed service's own fields back out. Today it says
#      `SCOMMANDER_NAME=port:22` and `SCOMMANDER_LOGFILE=.../port:22.log`, a
#      log file with a colon in its name.
#
#      Each surface below is given a DIFFERENT specifier, so the propagation
#      cases carry the other rivals too rather than repeating one form five
#      times: `info` takes the slash form, `loginfo` the lower-case form.
#
#   5. `PGM-` IS DELIBERATELY UNCHANGED, and is PINNED rather than compared.
#      Upstream REJECTS `PGM-QZSHSH` - exit 253, `Could not find definition for
#      service 'PGM-QZSHSH'` - where RMSC reports it as an ad-hoc service and
#      exits 0. docs/parity.md records that as Richard's decision. Stage 4
#      pins RMSC's own behaviour so it cannot drift, pins upstream's refusal as
#      a reference, and asserts NOTHING about the two agreeing.
#
#      IT IS A REAL SEPARATION, not a formality: `PGM-` is the third specifier
#      form and it goes through the same construction. A rename that reached it
#      too - `ad_hoc_program_QZSHSH`, say - is a second, unasked-for change
#      arriving inside the first, and this is the only row that would see it.
#
#   AND ONE THE BRIEF DID NOT LIST, which is nearly free and worth having:
#   `port:N` MUST STILL PROBE PORT N. CLAUDE.md records an ad-hoc port fix that
#   removed a conversion instead of guarding it, so every `port:N` check probed
#   port 0 and `port:22` reported NOT RUNNING against a listening sshd - behind
#   a full suite that passed, because every case aimed at it used a port that
#   is NOT RUNNING whether the code is right or wrong. This change edits the
#   same construction site. Stage 0 asserts port:22 is RUNNING and port:0 is
#   NOT RUNNING, in both implementations, and hard-fails if not.
#
#   That row does double duty: with only NOT RUNNING forms, a rename applied
#   inside one status branch would go green everywhere. port:22 is the only
#   case here in the RUNNING branch and it is also the only one `perfinfo` and
#   `scrunattrs` have anything to say about.
#
# ---------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT ASSERTED
# ---------------------------------------------------------------------------
#
#   THE REST OF `info`. Upstream prints 21 lines for an ad-hoc service and RMSC
#   14, and the differences have nothing to do with the name: a leading blank,
#   `Defined in: <ad hoc>` where RMSC leaves it empty, RMSC's extra `Working
#   Directory: .`, upstream's `Batch Mode:`, `Inherits environment variables?:`
#   and closing rule. Only the header line is asserted. Those differences are
#   worth someone's attention and they are not this change; widening this case
#   to the whole of stdout would fail RMSC for four unrelated reasons and
#   report it as an ad-hoc naming defect.
#
#   THE REST OF `perfinfo`. Same reason, and docs/parity.md already lists
#   `perfinfo` as an intentional difference at the gate.
#
#   ANY COMPARISON OF `scrunattrs` AGAINST UPSTREAM. The two print entirely
#   different things there - upstream the running job's environment, RMSC the
#   service's own SCOMMANDER_* variables - and the gate lists it as intentional.
#   So the scrunattrs rows below are DERIVED: they follow from the rule that
#   the service is constructed with this name, and there is no upstream
#   measurement behind them. They are stated as three separate rows so that a
#   deliberate divergence in one shows up on its own line.
#
#   THE `file` OPERATION. Swept and carries no name: upstream prints nothing at
#   all, RMSC prints `Cannot read `. That is the gate's recorded `file`
#   difference and there is nothing about naming in it.
#
#   `list` AND `groups`. An ad-hoc service appears in neither - it exists only
#   for the command that named it - so there is nothing to assert.
#
#   WHETHER A DEFINITION NAMED `ad_hoc_port_22` SHOULD WIN over the ad-hoc
#   reading of `port:22`. Tempting for stage 5, and left alone on purpose:
#   docs/parity.md records that upstream resolves `port:N` to a DEFINED service
#   carrying that port while RMSC always treats it as ad hoc, and calls that
#   difference UNDECIDED. A case there would be asserting an answer nobody has
#   given. Stage 5's staged definitions therefore collide with nothing - no
#   shared name, no shared criterion.
#
#   THE WORDING OF ANY WARNING OR ERROR. That is the separate D2 message work.
#
# ---------------------------------------------------------------------------
# FIXTURE - there isn't one, and that is the point
# ---------------------------------------------------------------------------
#
# Nothing here is staged, started or stopped for the six naming stages. An
# ad-hoc service needs no definition, `port:22` is a live listener because this
# harness arrived over SSH, and any job name that does not exist gives a stable
# NOT RUNNING in both implementations. So there is no fixture to own, nothing
# to leave behind, and no shared directory touched.
#
# Stage 5 is the one exception and it stages into its OWN work directory, shown
# to RMSC through SC_SERVICES_DIR and never to $HOME/.sc/services.
#
# WHICH ACCOUNT. docs/testing-notes.md records that the two accounts on this
# box hold different `$HOME/.sc/services` contents, and that a harness reading
# that directory gives different answers in each. Ad-hoc naming does not come
# from that directory, and stage 5 is the cheap proof: the same row, byte for
# byte, with no services directory, with an empty one, and with one holding a
# valid definition and a deliberately broken one - the shape of the populated
# account. Say which account a run was taken in anyway.
#
# NO SERVICE NAME FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The repository
# is public. `port:22` and `QINTER`/`QUSRWRK` are IBM-supplied; `QZSHSH` is the
# IBM-supplied shell program; stage 5's two definition names are invented here.
#
# Set KEEP=1 to leave the work directory behind.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-/tmp/rmsc-adhoc.$$}"

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
ls -dt /tmp/rmsc-adhoc.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
# because something was missing would report success while testing nothing.
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
  "Upstream is not optional here. Every name and description this file asserts" \
  "is re-taken from upstream in the same run (stage 3), because the table in" \
  "the header is a TRANSCRIPTION and a wrong transcription fails RMSC for" \
  "agreeing with upstream. Set SC=<path> if it is installed elsewhere."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$WORK"; }

# EXIT ONLY ONCE. `trap cleanup EXIT INT TERM` is the shape that looks right and
# is not: bash runs the handler on the signal and then CARRIES ON, cleanup fires
# again on EXIT, and the script finishes with STATUS 0 - an interrupted harness
# reporting SUCCESS to verify.sh for stages that never ran. Measured 9 September
# 2026 in colour-test.sh; docs/testing-notes.md carries the account.
on_signal() { trap - EXIT; cleanup; exit 130; }
trap cleanup EXIT
trap on_signal INT TERM

# ===========================================================================
# THE NAMING UNDER TEST, IN ONE PLACE.
#
# Every expectation in this file is built from these two functions and nothing
# else. That is deliberate and it is what makes the run falsifiable in both
# directions: replacing this block with RMSC's CURRENT naming turns stages 1,
# 2, 4 and 5 green against today's build, which is the evidence that the reds
# below are the measured naming difference and not something incidental to the
# harness. The replacement block, for anyone repeating that check, is:
#
#     adhoc_name() {
#       case "$1" in
#         job:*)  printf 'job:%s' "$(printf '%s' "${1#job:}" | tr 'a-z' 'A-Z')" ;;
#         *)      printf '%s' "$1" ;;
#       esac
#     }
#     adhoc_desc() {
#       case "$1" in
#         port:*) printf 'ad hoc port %s' "${1#port:}" ;;
#         job:*)  printf 'ad hoc job %s'  "$(printf '%s' "${1#job:}" | tr 'a-z' 'A-Z')" ;;
#         *)      printf '%s' "$1" ;;
#       esac
#     }
#     NAMING="RMSC's naming before the change"
#
# NOTE THE tr IN adhoc_name, AND WHAT IT MEANS. RMSC's ad-hoc name for a `job:`
# specifier is UPPER-CASED today - `job:qinter` comes back as `job:QINTER` - so
# a control written without it does not reproduce RMSC and the run says so.
#
# TWO THINGS ABOUT THAT CONTROL RUN, and they are findings rather than
# inconveniences:
#
#   - Stage 0's forms-are-distinct guard MUST BE REMOVED for the control, and
#     the reason is the whole point of rivals 2 and 3: under RMSC's current
#     naming the seven forms produce only FIVE distinct names, because the
#     case pairs collapse, and the name and the description are both built
#     from the raw string. That guard asks whether the rule being asserted can
#     separate anything; RMSC's old naming is the implementation that cannot,
#     so it is correctly unsatisfiable there.
#
#   - Stage 3 REFDRIFTs on all ten rows, deliberately: the control asserts a
#     rule upstream does not follow, and stage 3's entire job is to say so.
#     Measured 10 September 2026: failed=0, pinned-changed=0, reference-drift=10.
#
# Keep that copy OUT of the repository - a switch here that flipped the
# expectations would sooner or later be set by someone chasing a green run.
# ===========================================================================
adhoc_name() {  # specifier -> the service's name
  case "$1" in
    port:*) printf 'ad_hoc_port_%s' "${1#port:}" ;;
    job:*)  printf 'ad_hoc_job_%s'  "$(printf '%s' "${1#job:}" | tr '/' '_')" ;;
    *)      printf '%s' "$1" ;;
  esac
}
adhoc_desc() {  # specifier -> the service's description
  case "$1" in
    port:*) printf 'Ad hoc service running at port %s' "${1#port:}" ;;
    job:*)  printf 'Ad hoc service running at job %s'  "${1#job:}" ;;
    *)      printf '%s' "$1" ;;
  esac
}
NAMING='upstream sc 1.7.1'

# The seven forms, in the order the header table lists them.
SPECS=(
  'port:22'
  'port:0'
  'port:65535'
  'job:QINTER'
  'job:qinter'
  'job:QUSRWRK/QINTER'
  'job:qusrwrk/qinter'
)

# A `check` row, built the way the contract describes it:
#   '  ' + %left(status:18) + ' | ' + name + ' (' + desc + ') '
mkrow() { printf '  %-18s | %s (%s) \n' "$1" "$2" "$3"; }

pass=0; failed=0; changed=0; refdrift=0

report() {  # verdict tag detail...
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-28s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-28s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-28s %s\n' verdict case detail
  printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
}

# wc -l undercounts a final line with no trailing newline. grep -c '' does not.
count_lines() { if [ -s "$1" ]; then grep -c '' "$1"; else echo 0; fi; }
# NON-BLANK lines. Every operation here ends its stdout with one empty line -
# see parse_row - so "stdout is empty" has to mean "stdout says nothing", not
# "stdout is zero bytes".
nonblank() { local n; n=$(grep -c '[^[:space:]]' "$1" 2>/dev/null); [ -n "$n" ] || n=0; echo "$n"; }
mentions() { local n; n=$(grep -Fc -- "$2" "$1" 2>/dev/null); [ -n "$n" ] || n=0; echo "$n"; }

# The three markers a crash leaves. RNX and MCH are matched with their four
# digits so a service description containing the letters cannot match; CEE9901
# is the ILE wrapper the other two arrive inside.
ABEND_RE='CEE9901|RNX[0-9]{4}|MCH[0-9]{4}'

# ---------------------------------------------------------------------------
# A tag safe as a filename, and unique across the seven forms - INCLUDING THE
# TWO PAIRS THAT DIFFER ONLY IN CASE.
#
# /tmp ON THIS MACHINE IS CASE-INSENSITIVE. It is in the root IFS filesystem,
# which preserves case and does not distinguish it, so `sc.job_QINTER.out` and
# `sc.job_qinter.out` ARE THE SAME FILE and the second capture silently
# replaced the first. Measured 10 September 2026:
#
#     echo UPPER > /tmp/t/A_QINTER.out
#     echo lower > /tmp/t/A_qinter.out
#     ls /tmp/t   ->   A_QINTER.out        (one file)
#     cat A_QINTER.out  ->  lower
#
# That is not a small trap for THIS file in particular: rival 2 is entirely
# about a specifier and its lower-case twin, so the two artefacts a case
# harness most needs to keep apart are exactly the two the file system merges.
# It cost the first run of this harness two REFDRIFTs against an upstream that
# was behaving perfectly - stage 3 read `job:qinter`'s capture and compared it
# against `job:QINTER`'s expectation.
#
# THE FIX IS THE POSITION, not the spelling: each form's tag carries its index
# in SPECS, so two tags differ before a case fold can reach them. Anything not
# in SPECS falls back to the plain sanitised form, which is safe because
# nothing else here varies only by case.
#
# ANY HARNESS THAT NAMES AN ARTEFACT AFTER ITS INPUT HAS THIS PROBLEM, and the
# ones that do not are only safe by accident of their fixtures being spelt
# differently. It is not in docs/testing-notes.md.
# ---------------------------------------------------------------------------
declare -A TAG=()
_i=0
for _s in "${SPECS[@]}"; do
  TAG[$_s]="$(printf '%02d' "$_i")_$(printf '%s' "$_s" | tr ':/' '__')"
  _i=$((_i+1))
done
tagof() {
  if [ -n "${TAG[$1]:-}" ]; then printf '%s' "${TAG[$1]}"
  else printf '%s' "$1" | tr ':/' '__'; fi
}

# And the proof that it worked, checked rather than assumed - because the
# failure mode is silent and looks like a difference in the thing under test.
_n=$(for _s in "${SPECS[@]}"; do tagof "$_s"; echo; done | tr 'A-Z' 'a-z' | sort -u | grep -c .)
[ "$_n" -eq "${#SPECS[@]}" ] || setup_fail \
  "the ${#SPECS[@]} forms produce only $_n tags that survive a case fold" \
  "" \
  "/tmp on this machine is case-insensitive, so two artefacts whose names" \
  "differ only in case are ONE file and the second capture replaces the first." \
  "Two of the forms under test differ only in case, so this must hold."

declare -A RC_SAVED=()
# One invocation, streams apart. `< /dev/null` on every one: `system` in PASE
# consumes stdin, and this harness is run from a pipeline by verify.sh.
grab() {  # tag bin arg...
  local tag="$1" bin="$2"; shift 2
  "$bin" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" </dev/null
  RC_SAVED[$tag]=$?
}
grab_env() {  # tag VAR=VAL bin arg...
  local tag="$1" envv="$2" bin="$3"; shift 3
  env "$envv" "$bin" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" </dev/null
  RC_SAVED[$tag]=$?
}

# ---------------------------------------------------------------------------
# parse_row FILE - the consumer's reading of a `check` row.
#
# The consumer screen-scrapes `check` and DROPS any row that does not yield
# three fields, so a row that fails to parse here is not a cosmetic difference -
# it is a service vanishing from a screen. Parsing it the way the consumer does,
# rather than diffing it, is what lets a failure say which of the three fields
# went missing.
#
# THE TRAILING BLANK LINE IS NOT COUNTED AND IS NOT ASSERTED. Measured 10
# September 2026: `check <specifier>` puts the row and then ONE EMPTY LINE on
# stdout, in BOTH implementations - `) \n\n`. That blank is the per-command
# blank tools/jobinfo-test.sh establishes for `jobinfo`, it is nothing to do
# with naming, and it is the same in both, so this file counts NON-BLANK lines
# and takes the row from the first of them. Asserting it here would put a
# second owner on a line that already has one.
#
# It is also the first thing this harness found: the parser was written to
# demand exactly one line of stdout and the whole run stopped in stage 0 on a
# row that was perfectly correct.
#
# Sets ROW, ROW_STATUS (the padded 18), ROW_NAME, ROW_DESC. Returns 1 if stdout
# does not hold exactly one non-blank line, or that line does not parse.
# ---------------------------------------------------------------------------
ROW_RE='^  (.{18}) \| (.*) \((.*)\) $'
parse_row() {
  ROW=''; ROW_STATUS=''; ROW_NAME=''; ROW_DESC=''
  local nb; nb=$(grep -c '[^[:space:]]' "$1" 2>/dev/null); [ -n "$nb" ] || nb=0
  [ "$nb" -eq 1 ] || return 1
  IFS= read -r ROW < "$1"
  [[ "$ROW" =~ $ROW_RE ]] || return 1
  ROW_STATUS="${BASH_REMATCH[1]}"
  ROW_NAME="${BASH_REMATCH[2]}"
  ROW_DESC="${BASH_REMATCH[3]}"
  return 0
}
trim() { local s="$1"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

printf 'adhoc-name: what an ad hoc service is called, and everywhere that name comes back\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" \
  "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'naming asserted: %s\n' "$NAMING"
printf 'account: %s   HOME=%s   $HOME/.sc/services: %s definition(s)\n' \
  "$(id -un 2>/dev/null)" "$HOME" \
  "$(ls -1 "$HOME/.sc/services" 2>/dev/null | grep -c . || echo 0)"
printf 'forms: %s\n\n' "${SPECS[*]}"

# ---------------------------------------------------------------------------
echo "== stage 0: the reference capture, and the two things that make this honest"
echo
heading
# ---------------------------------------------------------------------------

hard_fail() {
  report FAIL "$1" "NOT A USABLE RUN"
  shift
  local p; for p in "$@"; do detail "$p"; done
  detail "nothing below this line would be evidence for anything"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
  echo "FAILED: no usable reference"
  exit 1
}

# Upstream's `check` for all seven forms, taken ONCE here and used twice: for
# the status differential in stage 1 and for the reference re-take in stage 3.
# Seven JVM starts, and they are the bulk of this harness's runtime.
for spec in "${SPECS[@]}"; do
  grab "sc.$(tagof "$spec")" "$SC" check "$spec"
done
report PASS reference-taken "upstream \`check\` captured for all ${#SPECS[@]} forms"
pass=$((pass+1))

# (a) EVERY UPSTREAM ROW PARSES. Stage 1 takes upstream's status from these and
# stage 3 takes its name and description; a capture that did not parse would
# make both of those say something they cannot support.
for spec in "${SPECS[@]}"; do
  t=$(tagof "$spec")
  parse_row "$WORK/sc.$t.out" || hard_fail reference-parses \
    "upstream's row for '$spec' is not one parseable check row" \
    "got: $(head -n 3 "$WORK/sc.$t.out" | tr '\n' '|')"
done
report PASS reference-parses "every upstream row yields three fields"
pass=$((pass+1))

# (b) PORT:22 IS RUNNING AND PORT:0 IS NOT - IN BOTH IMPLEMENTATIONS.
#
# THE ROW THAT MAKES THIS FILE HONEST, and it is a hard failure for two
# separate reasons.
#
# First, coverage: port:22 is the only case in this file in the RUNNING branch.
# With every form NOT RUNNING, a rename applied inside one status branch alone
# would go green everywhere here, and `perfinfo` and `scrunattrs` would have no
# jobs to say anything about.
#
# Second, the regression CLAUDE.md records: an ad-hoc port fix once removed a
# conversion instead of guarding it, so every `port:N` probed port 0 and
# `port:22` reported NOT RUNNING against a listening sshd - behind a full suite
# that passed, because every case aimed at it used a port that is NOT RUNNING
# whether the code is right or wrong. This change edits the same construction
# site. If port:22 and port:0 ever agree, that has happened again, and nothing
# else in this file would notice.
grab scr.pre22 "$SCR" check 'port:22'
grab scr.pre0  "$SCR" check 'port:0'
parse_row "$WORK/scr.pre22.out" || hard_fail live-listener \
  "RMSC's row for port:22 is not one parseable check row" \
  "got: $(head -n 3 "$WORK/scr.pre22.out" | tr '\n' '|')"
scr22=$(trim "$ROW_STATUS")
parse_row "$WORK/scr.pre0.out" || hard_fail live-listener \
  "RMSC's row for port:0 is not one parseable check row"
scr0=$(trim "$ROW_STATUS")
parse_row "$WORK/sc.$(tagof 'port:22').out"; sc22=$(trim "$ROW_STATUS")
parse_row "$WORK/sc.$(tagof 'port:0').out";  sc0=$(trim "$ROW_STATUS")
[ "$sc22" = RUNNING ] && [ "$scr22" = RUNNING ] || hard_fail live-listener \
  "port:22 is not RUNNING (sc: '$sc22', scr: '$scr22')" \
  "this harness arrived over SSH, so sshd is listening on 22 by construction" \
  "if scr alone says NOT RUNNING, the port conversion has been lost again -" \
  "that is the defect CLAUDE.md records, and it is on this change's own path" \
  "with nothing RUNNING, every case here sits in one status branch"
[ "$sc0" = 'NOT RUNNING' ] && [ "$scr0" = 'NOT RUNNING' ] || hard_fail live-listener \
  "port:0 is not NOT RUNNING (sc: '$sc0', scr: '$scr0')" \
  "if port:0 and port:22 agree, the specifier is not reaching the probe"
report PASS both-status-branches "port:22 RUNNING, port:0 NOT RUNNING, in both - rival 6 separable"
pass=$((pass+1))

# (c) THE FORMS DIFFER FROM EACH OTHER UNDER THE RULE.
#
# Cheap, and it is the arithmetic the whole file rests on. The two lower-case
# forms must produce DIFFERENT names from their upper-case twins under the rule
# being asserted (rival 2), and the slash form's name must differ from its
# description (rival 3). If the naming block above were ever edited into
# something that collapsed those, every case would still pass and none would
# separate anything.
n_all=$(for s in "${SPECS[@]}"; do adhoc_name "$s"; echo; done | sort -u | grep -c .)
[ "$n_all" -eq "${#SPECS[@]}" ] || hard_fail forms-are-distinct \
  "the ${#SPECS[@]} forms produce only $n_all distinct names under the rule" \
  "the case-preservation cases cannot separate anything"
sl=$(adhoc_name 'job:QUSRWRK/QINTER'); sd=$(adhoc_desc 'job:QUSRWRK/QINTER')
case "$sl" in *_QUSRWRK_QINTER) ;; *) hard_fail forms-are-distinct \
  "the slash form's name does not translate the slash: '$sl'" ;; esac
case "$sd" in *QUSRWRK/QINTER) ;; *) hard_fail forms-are-distinct \
  "the slash form's description does not keep the slash: '$sd'" ;; esac
report PASS forms-are-distinct "${#SPECS[@]} distinct names; slash translated in the name, kept in the description"
pass=$((pass+1))

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the \`check\` row, every form, against $NAMING"
echo
heading
# ---------------------------------------------------------------------------
#
# THE WHOLE ROW, BYTE FOR BYTE, plus the three things a diff alone would not
# say plainly: which of the three fields is wrong, that `|` is at column 22,
# and that the row is on stdout and not on stderr.
#
# THE STATUS IN THE CONSTRUCTED ROW IS RMSC'S OWN, taken from the row under
# test. That is not circular - it is the only division that keeps two rules in
# two rows. What the byte comparison then measures is the LAYOUT and the two
# NAME fields round that status; whether the status is RIGHT is the separate
# row below it, against upstream. Build the expectation from upstream's status
# instead and a status divergence fails the naming case, quoting a diff about
# a description.

check_case() {  # specifier
  local spec="$1" tag; tag=$(tagof "$spec")
  local want_name want_desc problems=() n sc_status=''
  want_name=$(adhoc_name "$spec")
  want_desc=$(adhoc_desc "$spec")

  grab "scr.$tag" "$SCR" check "$spec"
  local o="$WORK/scr.$tag.out" e="$WORK/scr.$tag.err"

  if grep -qE "$ABEND_RE" "$o" "$e" 2>/dev/null; then
    report FAIL "$spec" "ABEND: $(grep -hE -m1 "$ABEND_RE" "$o" "$e")"
    detail "artefacts: scr.$tag.out scr.$tag.err"
    failed=$((failed+1))
    return 1
  fi

  [ "${RC_SAVED[scr.$tag]:-1}" -eq 0 ] || \
    problems+=("exit ${RC_SAVED[scr.$tag]}, wanted 0 - an ad hoc check is a report and succeeds")

  if ! parse_row "$o"; then
    problems+=("stdout is not ONE row yielding three fields - the consumer would drop it")
    problems+=("  got $(count_lines "$o") line(s): $(head -n 3 "$o" | tr '\n' '|')")
  else
    [ "${ROW:21:1}" = '|' ] || \
      problems+=("the '|' is at column $(( $(printf '%s' "$ROW" | grep -bo '|' | head -1 | cut -d: -f1) + 1 )), not 22")
    [ "$ROW_NAME" = "$want_name" ] || \
      problems+=("name is '$ROW_NAME', wanted '$want_name'")
    [ "$ROW_DESC" = "$want_desc" ] || \
      problems+=("description is '$ROW_DESC', wanted '$want_desc'")
    mkrow "$(trim "$ROW_STATUS")" "$want_name" "$want_desc" > "$WORK/scr.$tag.want"
    printf '%s\n' "$ROW" > "$WORK/scr.$tag.got"
    if ! diff -u "$WORK/scr.$tag.want" "$WORK/scr.$tag.got" > "$WORK/scr.$tag.diff" 2>&1; then
      problems+=("the row is not byte-exact (-want +got):")
      while IFS= read -r p; do problems+=("  $p"); done < "$WORK/scr.$tag.diff"
    fi
    # THE STATUS, against upstream, as its own row's worth of evidence. The
    # comparison above cannot see this: it is built from RMSC's own status.
    parse_row "$WORK/sc.$tag.out" && sc_status="$ROW_STATUS"
    parse_row "$o"
    [ "$ROW_STATUS" = "$sc_status" ] || \
      problems+=("status is '$(trim "$ROW_STATUS")' where upstream says '$(trim "$sc_status")'")
  fi

  # THE ROW IS ON STDOUT. `loginfo` moved its not-found line to stderr the week
  # this was written, and "it is only an ad hoc service, say so on stderr" is
  # the obvious next step for someone working through the same list. It would
  # take the row off the screen the consumer scrapes.
  for n in "$spec" "$want_name"; do
    [ "$(mentions "$e" "$n")" -eq 0 ] || \
      problems+=("stderr names '$n' - the check row belongs on STDOUT: $(grep -F -m1 -- "$n" "$e")")
  done

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$spec" "$want_name ($want_desc)"
    pass=$((pass+1))
    return 0
  fi
  report FAIL "$spec" "the row is not what $NAMING prints"
  local p; for p in "${problems[@]}"; do detail "$p"; done
  detail "artefacts: scr.$tag.out scr.$tag.err"
  failed=$((failed+1))
  return 1
}

# port:22    rival 1, and the only RUNNING form
# port:0     rival 1, and the low boundary
# port:65535 rival 1, and the high boundary
# job:QINTER rival 1 in the job form
# job:qinter RIVAL 2 - case preserved, not upper-cased
# job:QUSRWRK/QINTER  RIVAL 3 - slash translated in the name, kept in the description
# job:qusrwrk/qinter  RIVALS 2 AND 3 together
for spec in "${SPECS[@]}"; do check_case "$spec"; done

echo
# ---------------------------------------------------------------------------
echo "== stage 2: rival 4 - it is the service's NAME, so five more surfaces carry it"
echo
heading
# ---------------------------------------------------------------------------
#
# A fix applied where `check` prints its row, rather than where the ad-hoc
# service is CONSTRUCTED, passes every case in stage 1 and fails every case
# here. That is the whole content of this stage.
#
# A DIFFERENT SPECIFIER PER SURFACE, so these carry the other rivals too:
#   jobinfo     port:22             the RUNNING branch
#   info        job:QUSRWRK/QINTER  rival 3, away from `check`
#   perfinfo    port:22             needs a running service to have jobs
#   loginfo     job:qinter          rival 2, away from `check`
#   scrunattrs  port:22             the constructed fields, read back out

# header_case TAG OP SPEC MATCHER - a `<name> (<desc>)` header line.
#
# WANTED is asked of the naming block, never hard-coded, so this stage moves
# with the block like everything else - which is what lets the whole file be
# pointed at RMSC's CURRENT naming and go green. A row hard-coded to the target
# would stay red in that control and the control would prove less.
header_case() {  # tag op spec suffix
  local tag="$1" op="$2" spec="$3" suffix="$4"
  local want problems=() n
  want="$(adhoc_name "$spec") ($(adhoc_desc "$spec"))$suffix"
  grab "$tag" "$SCR" "$op" "$spec"
  local o="$WORK/$tag.out" e="$WORK/$tag.err"

  if grep -qE "$ABEND_RE" "$o" "$e" 2>/dev/null; then
    report FAIL "$tag" "ABEND: $(grep -hE -m1 "$ABEND_RE" "$o" "$e")"
    failed=$((failed+1)); return 1
  fi
  [ "${RC_SAVED[$tag]:-1}" -eq 0 ] || \
    problems+=("exit ${RC_SAVED[$tag]}, wanted 0")

  n=$(grep -Fxc -- "$want" "$o" 2>/dev/null); [ -n "$n" ] || n=0
  if [ "$n" -ne 1 ]; then
    problems+=("$n stdout line(s) are exactly '$want', wanted 1")
    problems+=("  got: $(grep -n '(' "$o" | head -n 3 | tr '\n' '|')")
  fi

  # THE RAW SPECIFIER APPEARS NOWHERE ON STDOUT - the direct reading of "the
  # fix was applied at the printing site". GATED on the rule actually renaming
  # the service, so that the control described at the naming block still goes
  # green: under RMSC's current naming the specifier IS the name and this
  # question is meaningless.
  if [ "$(adhoc_name "$spec")" != "$spec" ]; then
    n=$(mentions "$o" "$spec")
    [ "$n" -eq 0 ] || \
      problems+=("$n stdout line(s) still carry the raw specifier '$spec': $(grep -F -m1 -- "$spec" "$o")")
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    report PASS "$tag" "$want"
    pass=$((pass+1)); return 0
  fi
  report FAIL "$tag" "($op $spec)"
  local p; for p in "${problems[@]}"; do detail "$p"; done
  detail "artefacts: $tag.out $tag.err"
  failed=$((failed+1)); return 1
}

# jobinfo. THE HEADER ONLY. The lines under it - the indent, the bare job name,
# the blank per command, and which jobs a port resolves to - are
# tools/jobinfo-test.sh's, over a staged fixture it controls. Measured here on
# 10 September 2026, upstream and RMSC named a DIFFERENT NUMBER OF JOBS for
# port:22, which is a real difference and is not this one; a case that compared
# the whole of stdout would report it as an ad-hoc naming defect.
header_case jobinfo-header  jobinfo  'port:22'            ':'

# info. THE HEADER ONLY - see WHAT IS DELIBERATELY NOT ASSERTED. The slash form,
# so this row carries rival 3 somewhere other than `check`.
header_case info-header     info     'job:QUSRWRK/QINTER' ''

# perfinfo. THE HEADER ONLY. port:22 because perfinfo reports per job.
header_case perfinfo-header perfinfo 'port:22'            ''

# loginfo. ON STDERR, in BOTH implementations - measured, and the reason this is
# not a header_case. The lower-case form, so this row carries rival 2 somewhere
# other than `check`.
#
# TWO ROWS, because they answer different questions and only the first is this
# change's: the NAME at the front of the line, and then whether the REST of the
# line matches upstream byte for byte.
#
# THE SECOND ROW STRIPS EACH SIDE'S OWN NAME PREFIX before comparing, rather
# than diffing the two lines whole. That is what keeps the two questions apart:
# a whole-line diff is red today for the naming difference, would stay red under
# the control described at the naming block, and so could not be read as saying
# anything about the rest of the line. Stripped, it is green today, green under
# the control, and green after the change - and if it ever fails on its own, the
# finding is in loginfo's TEXT, which belongs to tools/loginfo-test.sh.
LOG_SPEC='job:qinter'
LOG_NAME=$(adhoc_name "$LOG_SPEC")
grab scr.loginfo "$SCR" loginfo "$LOG_SPEC"
grab sc.loginfo  "$SC"  loginfo "$LOG_SPEC"
lp=()
[ "${RC_SAVED[scr.loginfo]:-1}" -eq 0 ] || lp+=("exit ${RC_SAVED[scr.loginfo]}, wanted 0")
nl=$(count_lines "$WORK/scr.loginfo.err")
[ "$nl" -eq 1 ] || lp+=("$nl stderr line(s), wanted 1")
lline=$(head -n 1 "$WORK/scr.loginfo.err")
case "$lline" in
  "$LOG_NAME: "*) ;;
  *) lp+=("the line does not begin '$LOG_NAME: '") ; lp+=("  got: $lline") ;;
esac
if [ ${#lp[@]} -eq 0 ]; then
  report PASS loginfo-name "(stderr) $LOG_NAME: ..."
  pass=$((pass+1))
else
  report FAIL loginfo-name "($LOG_SPEC)"
  for p in "${lp[@]}"; do detail "$p"; done
  detail "artefacts: scr.loginfo.err sc.loginfo.err"
  failed=$((failed+1))
fi

sed 's/^[^ ]*: //' "$WORK/sc.loginfo.err"  > "$WORK/loginfo.sc.rest"
sed 's/^[^ ]*: //' "$WORK/scr.loginfo.err" > "$WORK/loginfo.scr.rest"
if diff -u "$WORK/loginfo.sc.rest" "$WORK/loginfo.scr.rest" > "$WORK/loginfo.diff" 2>&1; then
  report PASS loginfo-rest-of-line "past the name, the line matches upstream byte for byte"
  pass=$((pass+1))
else
  report FAIL loginfo-rest-of-line "RMSC and upstream disagree about the line past the name"
  while IFS= read -r p; do detail "$p"; done < "$WORK/loginfo.diff"
  detail "the NAME is this change; anything else here is loginfo's own text"
  detail "and belongs to tools/loginfo-test.sh"
  failed=$((failed+1))
fi

# scrunattrs. NOT A PRINTING SURFACE - it reads the constructed service's own
# fields back out, which is the purest form of rival 4. DERIVED, not measured
# against upstream: the two implementations print entirely different things
# here and the gate lists the difference as intentional, so there is no
# upstream row to compare. Three separate rows, so that a deliberate divergence
# in one shows on its own line rather than sinking the case.
RUN_SPEC='port:22'
RUN_NAME=$(adhoc_name "$RUN_SPEC")
RUN_DESC=$(adhoc_desc "$RUN_SPEC")
grab scr.attrs "$SCR" scrunattrs "$RUN_SPEC"
A="$WORK/scr.attrs.out"

nl=$(count_lines "$A")
nn=$(grep -c "^$RUN_NAME: " "$A" 2>/dev/null); [ -n "$nn" ] || nn=0
if [ "$nl" -gt 0 ] && [ "$nn" -eq "$nl" ]; then
  report PASS scrunattrs-prefix "all $nl line(s) are prefixed '$RUN_NAME: '"
  pass=$((pass+1))
else
  report FAIL scrunattrs-prefix "$nn of $nl line(s) carry the service name as their prefix"
  detail "got: $(head -n 1 "$A")"
  detail "RMSC's own layout is '<name>: VAR=VALUE', so the prefix IS the service name"
  failed=$((failed+1))
fi

if grep -Fq "SCOMMANDER_NAME=$RUN_NAME" "$A" && \
   grep -Fq "SCOMMANDER_FRIENDLY_NAME=$RUN_DESC" "$A"; then
  report PASS scrunattrs-env "SCOMMANDER_NAME and SCOMMANDER_FRIENDLY_NAME follow"
  pass=$((pass+1))
else
  report FAIL scrunattrs-env "the constructed service's own fields did not follow"
  detail "wanted SCOMMANDER_NAME=$RUN_NAME"
  detail "wanted SCOMMANDER_FRIENDLY_NAME=$RUN_DESC"
  detail "got: $(grep -F 'SCOMMANDER_NAME=' "$A" | head -n 1)"
  detail "got: $(grep -F 'SCOMMANDER_FRIENDLY_NAME=' "$A" | head -n 1)"
  detail "a fix at the printing sites leaves these behind - they are not printed"
  failed=$((failed+1))
fi

# THE LOG FILE PATH, which is derived from the name and is the one consequence
# of this change that touches the file system. Before it, RMSC's ad-hoc log
# file is `<dir>/port:22.log` - a colon in a file name.
if grep -Eq "SCOMMANDER_LOGFILE=.*/${RUN_NAME}\.log$" "$A"; then
  report PASS scrunattrs-logfile "the log file is named for the service: $RUN_NAME.log"
  pass=$((pass+1))
else
  report FAIL scrunattrs-logfile "the log file is not named '$RUN_NAME.log'"
  detail "got: $(grep -F 'SCOMMANDER_LOGFILE=' "$A" | head -n 1)"
  detail "derived, not measured against upstream - see the header"
  failed=$((failed+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 3: upstream reference, re-taken this run"
echo "   (stage 1 and 2's expectations are only as good as this table; a"
echo "    REFDRIFT means the reference moved, not that RMSC regressed)"
echo
heading
# ---------------------------------------------------------------------------
#
# EVERY EXPECTATION ABOVE IS A TRANSCRIPTION - a table typed from a capture -
# and a wrong transcription fails RMSC for agreeing with upstream. So upstream's
# rows, captured in stage 0, are put through the SAME naming block.
#
# THIS IS THE ROW THAT WOULD HAVE CAUGHT A MIS-TRANSCRIBED RULE. It is worth
# noting which way it points: if upstream and the block disagree, the block is
# wrong until someone shows otherwise, because upstream is the specification.
for spec in "${SPECS[@]}"; do
  t=$(tagof "$spec")
  want_name=$(adhoc_name "$spec"); want_desc=$(adhoc_desc "$spec")
  why=""
  [ "${RC_SAVED[sc.$t]:-1}" -eq 0 ] || why="$why exit=${RC_SAVED[sc.$t]}(wanted 0)"
  if parse_row "$WORK/sc.$t.out"; then
    [ "$ROW_NAME" = "$want_name" ] || why="$why name='$ROW_NAME'(wanted '$want_name')"
    [ "$ROW_DESC" = "$want_desc" ] || why="$why desc='$ROW_DESC'(wanted '$want_desc')"
  else
    why="$why row-does-not-parse"
  fi
  if [ -z "$why" ]; then
    report PASS "sc:$spec" "as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$spec" "$why"
    detail "the rule in this file's header no longer describes upstream"
    refdrift=$((refdrift+1))
  fi
done

# The propagation surfaces, from upstream, in the same forms stage 2 used.
# Three more JVM starts and they are what make stage 2's headers a comparison
# rather than four more transcriptions.
for pair in "jobinfo:port:22::" "info:job:QUSRWRK/QINTER::" "perfinfo:port:22::"; do
  op="${pair%%:*}"; rest="${pair#*:}"; spec="${rest%::}"
  want="$(adhoc_name "$spec") ($(adhoc_desc "$spec"))"
  [ "$op" = jobinfo ] && want="$want:"
  grab "scref.$op" "$SC" "$op" "$spec"
  n=$(grep -Fxc -- "$want" "$WORK/scref.$op.out" 2>/dev/null); [ -n "$n" ] || n=0
  if [ "$n" -eq 1 ]; then
    report PASS "sc:$op" "header as recorded"
    pass=$((pass+1))
  else
    report REFDRIFT "sc:$op" "$n upstream line(s) are exactly '$want', wanted 1"
    detail "got: $(grep -n '(' "$WORK/scref.$op.out" | head -n 3 | tr '\n' '|')"
    refdrift=$((refdrift+1))
  fi
done

echo
# ---------------------------------------------------------------------------
echo "== stage 4: a decided difference, pinned so a change to it is visible"
echo
heading
# ---------------------------------------------------------------------------

# PINNED - `PGM-` IS AN RMSC EXTENSION AND IS NOT BROUGHT INTO LINE.
#
#   upstream sc:  REFUSES it. exit 253, `Could not find definition for service
#                 'PGM-QZSHSH'`, empty stdout.
#   RMSC:         reports it as an ad-hoc service, exit 0,
#                 `PGM-QZSHSH (ad hoc program QZSHSH)`.
#
# docs/parity.md records Richard's decision to keep it. The risk this row guards
# is specific and is not remote: `PGM-` is the third specifier form and goes
# through the same construction as `port:` and `job:`. Somebody bringing the
# ad-hoc NAMING to upstream's may reasonably bring `PGM-` with it - which would
# be a second, unasked-for change arriving inside the first - or, going the
# other way, may make RMSC refuse it. Nothing else in this file would see
# either.
#
# NOTHING HERE ASSERTS THE TWO MATCH. They deliberately do not.
PGM_SPEC='PGM-QZSHSH'
PGM_NAME='PGM-QZSHSH'
PGM_DESC='ad hoc program QZSHSH'
grab scr.pgm "$SCR" check "$PGM_SPEC"
p_why=""
[ "${RC_SAVED[scr.pgm]:-1}" -eq 0 ] || p_why="$p_why exit=${RC_SAVED[scr.pgm]}(wanted 0)"
if parse_row "$WORK/scr.pgm.out"; then
  [ "$ROW_NAME" = "$PGM_NAME" ] || p_why="$p_why name='$ROW_NAME'"
  [ "$ROW_DESC" = "$PGM_DESC" ] || p_why="$p_why desc='$ROW_DESC'"
else
  p_why="$p_why row-does-not-parse"
fi
if [ -z "$p_why" ]; then
  report PASS pgm-extension-kept "(pinned) $PGM_NAME ($PGM_DESC), exit 0 - RMSC's own"
  pass=$((pass+1))
else
  report CHANGED pgm-extension-kept "(pinned)$p_why"
  detail "RMSC's PGM- extension has moved. Upstream REFUSES this specifier, so"
  detail "there is nothing here to be brought into line with."
  detail "If that was intended, update this case and docs/parity.md together."
  changed=$((changed+1))
fi

# UPSTREAM'S REFUSAL, as the reference behind the row above. Shape only: the
# WORDING is the separate D2 message work and is not compared.
grab sc.pgm "$SC" check "$PGM_SPEC"
u_why=""
[ "${RC_SAVED[sc.pgm]}" -eq 253 ] || u_why="$u_why sc-exit=${RC_SAVED[sc.pgm]}(wanted 253)"
[ "$(nonblank "$WORK/sc.pgm.out")" -eq 0 ] || u_why="$u_why sc-stdout-not-empty"
if [ -z "$u_why" ]; then
  report PASS "sc:$PGM_SPEC" "refused: exit 253, empty stdout - wording NOT compared"
  pass=$((pass+1))
else
  report REFDRIFT "sc:$PGM_SPEC" "$u_why"
  detail "upstream no longer refuses PGM-; the pinned row above rests on it doing so"
  refdrift=$((refdrift+1))
fi

# PINNED - THE CHECK-ALIVE CRITERION IS STILL UPPER-CASED, AND THE NAME IS NOT.
#
#   upstream sc:  `JOBNAME:qusrwrk/qinter` - the specifier, as typed.
#   RMSC:         `JOBNAME:QUSRWRK/QINTER` - upper-cased, and correct.
#
# THE OTHER HALF OF RIVAL 2, and the half a suite watching only the name cannot
# see. Before this change RMSC built the ad-hoc name FROM the upper-cased
# criterion, which is why `job:qinter` came back as `job:QINTER`. The fix made
# them two values. There are two ways to undo that and only one of them is
# visible from stage 1:
#
#   the name follows the criterion again   stage 1 goes red. Covered.
#   the criterion follows the NAME instead - the upper-casing dropped so that
#                                          the name comes out right - and every
#                                          case in stage 1 STAYS GREEN while a
#                                          job criterion silently stops matching.
#
# ONE CAPTURE, TWO VALUES, and it has to be a LOWER-CASE, SUBSYSTEM-QUALIFIED
# specifier: with upper-case input the two values are the same string and this
# row separates nothing at all.
#
# PINNED rather than compared: upper-casing the criterion is RMSC's own decided
# behaviour and upstream does not do it. The reference row below is what makes
# that a difference rather than a coincidence.
CRIT_SPEC='job:qusrwrk/qinter'
CRIT_UPPER="JOBNAME:$(printf '%s' "${CRIT_SPEC#job:}" | tr 'a-z' 'A-Z')"
CRIT_HDR="$(adhoc_name "$CRIT_SPEC") ($(adhoc_desc "$CRIT_SPEC"))"
grab scr.crit "$SCR" info "$CRIT_SPEC"
c_why=""
grep -Fq "$CRIT_UPPER" "$WORK/scr.crit.out" || c_why="$c_why criterion-no-longer-upper-cased"
grep -Fxq "$CRIT_HDR"  "$WORK/scr.crit.out" || c_why="$c_why name-no-longer-preserved"
if [ -z "$c_why" ]; then
  report PASS criterion-still-upper "(pinned) $CRIT_UPPER, under the name $(adhoc_name "$CRIT_SPEC")"
  pass=$((pass+1))
else
  report CHANGED criterion-still-upper "(pinned)$c_why"
  detail "wanted the criterion '$CRIT_UPPER' and the header '$CRIT_HDR'"
  detail "got: $(grep -i 'check-alive' "$WORK/scr.crit.out" | head -n 1)"
  detail "got: $(grep -F '(' "$WORK/scr.crit.out" | head -n 1)"
  detail "the name and the criterion are two values on purpose. If the criterion"
  detail "has stopped being upper-cased, a job criterion has silently stopped"
  detail "matching and every case in stage 1 is still green."
  detail "If that was intended, update this case and docs/parity.md together."
  changed=$((changed+1))
fi

# UPSTREAM'S CRITERION, as the reference behind the row above. Without it, an
# upstream that started upper-casing too would leave the pin passing while the
# difference it pins had quietly gone away.
grab sc.crit "$SC" info "$CRIT_SPEC"
CRIT_RAW="JOBNAME:${CRIT_SPEC#job:}"
if grep -Fq "$CRIT_RAW" "$WORK/sc.crit.out"; then
  report PASS "sc:criterion" "upstream leaves it as typed: $CRIT_RAW"
  pass=$((pass+1))
else
  report REFDRIFT "sc:criterion" "upstream's criterion is not '$CRIT_RAW'"
  detail "got: $(grep -i 'check-alive' "$WORK/sc.crit.out" | head -n 1)"
  detail "the row above pins RMSC's upper-casing as a DIFFERENCE from upstream"
  refdrift=$((refdrift+1))
fi

echo
# ---------------------------------------------------------------------------
echo "== stage 5: the name does not come from the definition store"
echo
heading
# ---------------------------------------------------------------------------
#
# THE ACCOUNT QUESTION, answered rather than assumed. docs/testing-notes.md
# records that the two accounts on this box hold different $HOME/.sc/services
# contents - one empty, one with four deliberately broken definitions - and
# that a harness reading that directory gives different answers in each, with
# the green run on the empty account being the weaker result.
#
# Ad-hoc naming should be insensitive to it: the service is constructed from
# the specifier and there is no definition to read. This stage is the cheap
# proof of the half that can be proved from either account - the same row, byte
# for byte, with no services directory, with an EMPTY one, and with one holding
# a valid definition AND a deliberately broken one, which is the shape of the
# populated account.
#
# WHAT IT CANNOT PROVE, stated plainly: SC_SERVICES_DIR ADDS a directory, it
# does not replace $HOME/.sc/services, so this cannot show the empty direction
# from a populated account. Overriding HOME does not help either - measured 10
# September 2026, neither implementation honours it for discovery. Say which
# account a run was taken in.
#
# NOTHING STAGED HERE COLLIDES with the specifiers under test - no shared name,
# no criterion on port 22 - because upstream resolves `port:N` to a DEFINED
# service carrying that port while RMSC always treats it as ad hoc, and
# docs/parity.md calls that difference UNDECIDED. A collision case would be
# asserting an answer nobody has given.
mkdir -p "$WORK/svc-empty" "$WORK/svc-full"
{
  printf 'name: Zulu Ad Hoc Bystander\n'
  printf 'start_cmd: /QOpenSys/usr/bin/sleep 30\n'
  printf 'check_alive: 65330\n'
  printf 'startup_wait_time: 2\n'
} > "$WORK/svc-full/zzah_bystander.yaml"
printf 'this is not: [valid yaml at all\n  - broken\n' > "$WORK/svc-full/zzah_broken.yaml"

for spec in 'port:22' 'job:qinter'; do
  t=$(tagof "$spec")
  grab_env "dir.empty.$t" "SC_SERVICES_DIR=$WORK/svc-empty" "$SCR" check "$spec"
  grab_env "dir.full.$t"  "SC_SERVICES_DIR=$WORK/svc-full"  "$SCR" check "$spec"
  d_why=""
  cmp -s "$WORK/scr.$t.out" "$WORK/dir.empty.$t.out" || d_why="$d_why empty-dir-differs"
  cmp -s "$WORK/scr.$t.out" "$WORK/dir.full.$t.out"  || d_why="$d_why populated-dir-differs"
  if [ -z "$d_why" ]; then
    report PASS "store-blind:$spec" "same row with no, empty and populated services dir"
    pass=$((pass+1))
  else
    report FAIL "store-blind:$spec" "$d_why"
    detail "none: $(head -n 1 "$WORK/scr.$t.out")"
    detail "empty:$(head -n 1 "$WORK/dir.empty.$t.out")"
    detail "full: $(head -n 1 "$WORK/dir.full.$t.out")"
    detail "an ad hoc service has no definition; its name must not depend on one"
    failed=$((failed+1))
  fi
done

echo
echo "pass=$pass   failed=$failed   pinned-changed=$changed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out, .err and .diff per case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and where it would have to be done instead
#
#   THE `start`/`stop` NARRATION for an ad-hoc service. It names the service
#   too, and starting one would run its start_cmd - which for an ad-hoc service
#   is empty. tools/narration-test.sh owns that surface over a fixture it
#   creates and removes; nothing here starts anything.
#
#   A LOG FILE ACTUALLY APPEARING under the new name. `loginfo` says
#   `<unknown>` for an ad-hoc service that has never been started by sc, and
#   this harness never starts one. The LOGFILE path is asserted as the
#   constructed service's own field instead.
#
#   COLOUR on any of these lines. tools/colour-test.sh owns the instrument. The
#   `<name> (<desc>)` header construct is already pinned there for `list` and
#   `info`; if the ad-hoc header ever renders differently it would be a fourth
#   instance of the same family and belongs beside the other three.
#
#   WHETHER A DEFINITION SHOULD WIN over `port:N`. Undecided - see stage 5.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: ad hoc services are not named the way upstream names them"
  exit 1
fi
if [ "$changed" -ne 0 ]; then
  echo "PINNED BEHAVIOUR CHANGED: $changed decided difference(s) moved."
  echo "If that was intended, update this script and docs/parity.md together."
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer names ad hoc services as recorded."
  echo "Every expectation here rests on that table - re-take it before trusting a"
  echo "pass or acting on a failure."
  exit 1
fi
echo "OK: name and description on every form, and on all six surfaces that carry them"
