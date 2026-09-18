#!/QOpenSys/pkgs/bin/bash
#
# info-test.sh - the SHAPE of `info`'s output: the two decided-to-fix places
# where the blank-line count is wrong, the `Working Directory:` line RMSC
# invents, the unconditional `Batch Mode:` line RMSC omits, the dependency
# block's shape, the `Group:` line being removed, the environment-variables
# block, and the closing separator with its three trailing blanks.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses,
# and modelled on tools/jobinfo-test.sh (for the STRUCTURE-not-full-text
# assertion style) and tools/loginfo-test.sh (for report/PASS/FAIL/REFDRIFT and
# the "stage N" banner comments).
#
# NONE OF THIS IS IMPLEMENTED YET. Every case below is written to FAIL against
# RMSC as it stands, for a NAMED reason - not "diff found something", but
# "blank-lines-after-name=1 (wanted 2)" or the equivalent. It is written before
# the fix, per this project's rule: a red test proves the test can detect the
# defect; a test written afterwards proves only that it agrees with the code.
#
# ---------------------------------------------------------------------------
# WHAT IS BEING TESTED, and WHERE IT COMES FROM
# ---------------------------------------------------------------------------
#
# docs/parity.md, the "info" row under "Differences still undecided", carries
# "DECIDED 18 September 2026: full parity, all eight" plus removing the
# RMSC-only `Group:` line. docs/messages.md's `### info` section has the exact
# measured shape - captured 3 September 2026 against two staged definitions,
# "one carrying dependencies, groups and environment variables, one minimal" -
# reproduced here as the eight numbered differences:
#
#   1. blank lines before the separator:  upstream 2, RMSC 1
#   2. blank lines after the name line:   upstream 2, RMSC 1
#   3. `Working Directory:`               upstream: absent when dir unset
#                                         RMSC: always printed, resolved
#   4. `Batch Mode:` when not batch       upstream: `Batch Mode: <not running
#                                         in batch>`, unconditionally
#                                         RMSC: nothing
#   5. dependencies                       upstream: one header, `Depends on the
#                                         following services:`, then each name
#                                         indented beneath it
#                                         RMSC: `Depends on: <name>` repeated
#   6. groups                             upstream: no line at all, ever
#                                         RMSC: one `Group: <name>` line each -
#                                         DECIDED: remove it, not reshape it
#   7. environment variables              upstream: `Inherits environment
#                                         variables?: <bool>` always, then
#                                         `Custom environment variables:` and
#                                         one indented NAME=value per var when
#                                         any are set
#                                         RMSC: neither line, ever
#   8. closing separator                  upstream: a second 69-dash line, then
#                                         THREE blank lines
#                                         RMSC: nothing - never closed
#
# The BLANK-LINE COUNTS AND THE LITERAL LABEL TEXT ABOVE ARE TREATED AS
# MEASURED CONSTANTS, the same way tools/jobinfo-test.sh hardcodes
# LAYOUT_BLANK=1 and the exact "NO JOB INFO (...)" string rather than deriving
# them fresh each run. What IS derived fresh each run, because it varies and
# must not be guessed at, is: the actual PATH info prints for `dir:`, and
# WHICH FORM (short name? friendly name?) upstream renders a dependency as -
# stage 1 reads that back out of upstream's own capture and compares RMSC's
# entries to it as a SET, rather than assuming an answer. Stage 2 re-verifies
# the hardcoded constants against upstream's live output on every run, exactly
# as tools/jobinfo-test.sh's stage 2 and tools/loginfo-test.sh's stage 2 do -
# so a REFDRIFT means the reference moved, not that RMSC regressed.
#
# ---------------------------------------------------------------------------
# THE FIXTURES, and why there are three
# ---------------------------------------------------------------------------
#
# docs/messages.md's own capture used a pairing "one carrying dependencies,
# groups and environment variables, one minimal" DELIBERATELY - it is how the
# original measurement separated "always differs" (the blank counts, the
# unconditional Batch Mode and Inherits-environment-variables lines, the
# closing separator) from "differs only when the optional sections are
# populated" (dependencies, the environment block's custom-vars half). This
# file keeps that pairing and adds a third:
#
#   FULL      dependencies (TWO of them, not one - see rival 5 below), a
#             group, custom environment variables, NO dir: set.
#   MIN       none of the above, and NO dir: set either.
#   DIRSET    as MIN, but WITH dir: set to an ABSOLUTE path.
#
# DIRSET exists because difference 3 has two directions and only one of them
# is broken. The brief and docs/parity.md agree that when `dir` is unset,
# upstream prints nothing and RMSC invents a resolved path - that is FULL and
# MIN's job. But when `dir` IS set, RMSC's `info` is recorded as ALREADY
# printing `Working Directory: <path>` correctly - this is the direction a fix
# must not regress, and nothing in FULL or MIN can tell a fix that closed the
# gap by making `Working Directory:` disappear ENTIRELY from being one that
# closed it correctly. DIRSET is that control.
#
# An ABSOLUTE path, not a relative one: `tools/gate-fixtures/README.md`
# records that a RELATIVE `dir:` (e.g. `dir: .`) is a SEPARATE, open question -
# upstream shows the raw relative string and RMSC resolves it, and that
# divergence is not one of the eight differences decided here. Using an
# absolute path keeps this file inside the eight and out of that adjacent one.
#
# ---------------------------------------------------------------------------
# THE RIVALS EACH CASE HAS TO RULE OUT
# ---------------------------------------------------------------------------
#
#   1/2/8. THE BLANK COUNTS AND THE CLOSING SEPARATOR ARE CHECKED ON BOTH FULL
#      AND MIN, not just the "everything populated" fixture. A fix that ties
#      the leading/trailing blank printing to whichever branch prints the
#      dependency or environment block - plausible if the blanks are emitted
#      adjacent to those sections rather than unconditionally - would pass on
#      FULL and fail on MIN, or the reverse. Only checking one of the two
#      fixtures could not tell that apart from a fix that got it right
#      everywhere.
#
#   3. WORKING DIRECTORY has three readings and FULL+MIN+DIRSET separate all
#      of them: "never printed" (wrong on DIRSET), "always printed, resolved"
#      (RMSC's CURRENT bug - wrong on FULL and MIN), and "printed only when
#      dir: is set" (the wanted rule - right on all three).
#
#   4. BATCH MODE is asserted on MIN specifically because MIN has nothing else
#      going on. A fix that only prints `Batch Mode:` when some OTHER section
#      is also being printed (a plausible reading of "when not batch" as a
#      trigger condition rather than an unconditional label) would still pass
#      a check aimed only at FULL; MIN is the fixture with no other section to
#      hang it off.
#
#   5. DEPENDENCIES: FULL stages TWO dependencies, not one. With a single
#      dependency, a fix that renamed the label to
#      `Depends on the following services:` but kept printing it ONCE PER
#      DEPENDENCY - collapsing the "shape" fix to a "wording" fix - would look
#      identical to the wanted output: one header line, one indented name.
#      With two dependencies that fix prints the header TWICE, which is
#      asserted directly (`dep_header_count` must be exactly 1), and the
#      un-indented legacy form (`Depends on: <name>`) is checked for directly
#      too, so a fix that renamed the label without indenting still fails.
#      MIN and DIRSET, with no dependencies, are the control that the header
#      is not printed unconditionally.
#
#   6. GROUPS: FULL is a member of a real invented group, so RMSC's CURRENT
#      behaviour (one `Group:` line) has something to print before the fix
#      removes it. Checked as a bare count of zero, not a shape - upstream
#      never had a shape here to imitate; there is nothing to reproduce.
#
#   7. ENVIRONMENT: the "Inherits environment variables?:" line is asserted as
#      present, exactly once, on ALL THREE fixtures - it is upstream's
#      unconditional half, and MIN (nothing else set) is what would catch a
#      fix that only prints it alongside a populated Custom-variables block.
#      Its BOOLEAN VALUE is compared to upstream's own captured value rather
#      than assumed to be `true`, since neither fixture sets
#      `environment_is_inheriting_vars` explicitly and the default is not one
#      of the eight differences under test here. `Custom environment
#      variables:` and its entries are asserted present (matching what was
#      staged, as a set - order is not asserted) on FULL only, and their
#      ABSENCE is asserted on MIN and DIRSET - the control that the block is
#      conditional on there being something to show, not unconditional like
#      its sibling line.
#
# ---------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT ASSERTED
# ---------------------------------------------------------------------------
#
#   THE EXACT TEXT OF `Defined in:`, `Startup Command:`, `Check-alive
#   conditions:` and similar. None of these are among the eight recorded
#   differences and docs/messages.md says "most labels match" already.
#
#   WHICH FORM (short or friendly name) UPSTREAM RENDERS A DEPENDENCY AS.
#   Neither docs/messages.md nor docs/parity.md says, and this file does not
#   guess: it reads upstream's own two entries out of its live capture and
#   compares RMSC's entries to that set, so the case is correct whichever form
#   upstream turns out to use. See "UNCERTAIN, FLAGGED" below.
#
#   RELATIVE `dir:` RESOLUTION. A separate, open question recorded in
#   tools/gate-fixtures/README.md (rmscgate_info_reldir) and not part of the
#   eight decided differences here. DIRSET uses an absolute path on purpose.
#
#   COLOUR. docs/parity.md records `info`'s field-label and rule-line colour
#   as still open, deliberately, because "colouring the body before the
#   content matches would mean doing it twice." Not this file's job.
#
#   THE `Defined in:` PATH'S EXACT VALUE, and anything else that is a path,
#   a timestamp, or otherwise expected to vary. Nothing here reads one.
#
# ---------------------------------------------------------------------------
# STAGING
# ---------------------------------------------------------------------------
#
# Nothing here is ever started - `info` prints CONFIGURATION, and the one
# state-dependent line (`Batch Mode: <not running in batch>`) is upstream's
# text for a service that plainly never got as far as running in batch,
# which every fixture here is by construction. So staging is the cheapest
# kind used in this project: five YAML files in a PRIVATE work directory,
# reached the way tools/jobinfo-test.sh reaches its own -
#
#     upstream   JAVA_TOOL_OPTIONS='-Dservices.dir=<dir>'
#     RMSC       SC_SERVICES_DIR=<dir>
#
# - and never written into $HOME/.sc/services, so a run killed mid-flight
# leaves nothing in a directory the fidelity gate or another harness reads.
#
# NO SERVICE NAME FROM THIS MACHINE IS WRITTEN INTO THIS FILE. The repository
# is public. Every name below is invented here.
#
# ---------------------------------------------------------------------------
# UNCERTAIN, FLAGGED RATHER THAN GUESSED AT SILENTLY
# ---------------------------------------------------------------------------
#
# Two things about the staging mechanism were not settled by anything this
# author was given to read, and are called out here rather than assumed:
#
#   - WHETHER A DEPENDENCY ENTRY IS THE SHORT NAME OR THE FRIENDLY NAME. See
#     above - resolved by reading it back from upstream's own capture rather
#     than by guessing, so this file works either way, but whoever implements
#     the fix should know the entry's IDENTITY is not pinned here, only that
#     RMSC's set matches upstream's set under one header.
#
#   - WHETHER `environment_is_inheriting_vars`'S DEFAULT IS `true` ON BOTH
#     SIDES. `tools/gate-fixtures/base/rmscgate_defaults.yaml` says upstream
#     defaults it to `true`, and this is not one of the eight differences, so
#     it is very likely already agreed - but MIN and DIRSET deliberately leave
#     the key unset and compare RMSC's rendered boolean against upstream's OWN
#     rendered boolean rather than against a hardcoded `true`, so a surprise
#     there is caught as a finding instead of silently assumed away.
#
# Set KEEP=1 to leave the work directory behind. Set INFO_DRY=1 to print the
# staged definitions and stop.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-/tmp/rmsc-info.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT. Same block as every other script in
# tools/ that keeps its work directory and names it by PID - see
# tools/jobinfo-test.sh for the reasoning; deliberately duplicated rather than
# shared, because each of these runs standalone.
ls -dt /tmp/rmsc-info.* 2>/dev/null | tail -n +3 | while read -r stale; do
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
  "Upstream is not optional: it is the reference for every constant in this" \
  "file, and stage 2 re-takes it on every run so a stale assumption is caught" \
  "as REFDRIFT rather than silently trusted. Set SC=<path> if it is installed" \
  "elsewhere."

mkdir -p "$WORK/services" || setup_fail "cannot create work directory $WORK"
SVCDIR="$WORK/services"

# ---------------------------------------------------------------------------
# The fixture: three definitions under test, plus two bystander dependencies.
# All five are invented here; none is ever started.
# ---------------------------------------------------------------------------
FULL=zzinfo_full;     FULL_F='Zulu Info Full'
MIN=zzinfo_min;       MIN_F='Zulu Info Min'
DIRSET=zzinfo_dirset; DIRSET_F='Zulu Info Dirset'
DEP1=zzinfo_dep1;     DEP1_F='Zulu Info Dep One'
DEP2=zzinfo_dep2;     DEP2_F='Zulu Info Dep Two'
GROUP=zzinfo_grp
DIRVAL=/QOpenSys

cat > "$SVCDIR/$DEP1.yaml" <<EOF
name: $DEP1_F
start_cmd: /QOpenSys/usr/bin/true
check_alive: zzinfodeaddep1
EOF

cat > "$SVCDIR/$DEP2.yaml" <<EOF
name: $DEP2_F
start_cmd: /QOpenSys/usr/bin/true
check_alive: zzinfodeaddep2
EOF

cat > "$SVCDIR/$FULL.yaml" <<EOF
name: $FULL_F
start_cmd: /QOpenSys/usr/bin/true
check_alive: zzinfodeadfull
startup_wait_time: 11
stop_wait_time: 12
service_dependencies:
- $DEP1
- $DEP2
groups:
- $GROUP
environment_is_inheriting_vars: true
environment_vars:
- ZZINFO_ONE=first
- ZZINFO_TWO=second value with spaces
EOF

cat > "$SVCDIR/$MIN.yaml" <<EOF
name: $MIN_F
start_cmd: /QOpenSys/usr/bin/true
check_alive: zzinfodeadmin
EOF

cat > "$SVCDIR/$DIRSET.yaml" <<EOF
name: $DIRSET_F
start_cmd: /QOpenSys/usr/bin/true
check_alive: zzinfodeaddirset
dir: $DIRVAL
EOF

cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$WORK"; }
on_signal() { trap - EXIT; cleanup; exit 130; }
trap cleanup EXIT
trap on_signal INT TERM

if [ -n "${INFO_DRY:-}" ]; then
  echo "info-test: dry run. Staged in $SVCDIR:"
  for f in "$SVCDIR"/*.yaml; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

SC_ENV="JAVA_TOOL_OPTIONS=-Dservices.dir=$SVCDIR"
SCR_ENV="SC_SERVICES_DIR=$SVCDIR"

pass=0; failed=0; refdrift=0

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

# The three markers a crash leaves, on either stream.
ABEND_RE='CEE9901|RNX[0-9]{4}|MCH[0-9]{4}'

declare -A RC_SAVED=()
grab() {  # tag envv bin arg...
  local tag="$1" envv="$2" bin="$3"; shift 3
  env "$envv" "$bin" "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" </dev/null
  RC_SAVED[$tag]=$?
}

verdict_row() {  # verdict_word tag ok_msg problem...
  local v="$1" tag="$2" ok="$3"; shift 3
  if [ "$#" -eq 0 ]; then
    report PASS "$tag" "$ok"
    pass=$((pass+1))
  else
    report "$v" "$tag" ""
    local p; for p in "$@"; do detail "$p"; done
    case "$v" in
      REFDRIFT) refdrift=$((refdrift+1)) ;;
      *)        failed=$((failed+1)) ;;
    esac
  fi
}

hard_fail() {
  report FAIL "$1" "FIXTURE DID NOT TAKE"
  shift
  local p; for p in "$@"; do detail "$p"; done
  detail "nothing below this line would be evidence for anything"
  failed=$((failed+1))
  echo
  echo "pass=$pass   failed=$failed   reference-drift=$refdrift"
  echo "FAILED: no usable fixture"
  exit 1
}

# ---------------------------------------------------------------------------
# Metric extractors. Each is a small, single-purpose function over one
# captured file, in the style of tools/jobinfo-test.sh's count_lines/n_blank.
# ---------------------------------------------------------------------------

leading_blank_count() {
  awk '{ if ($0=="") { n++; next } else { exit } } END { print n+0 }' "$1"
}
first_nonblank_lineno() {
  awk '$0!=""{print NR; exit}' "$1"
}
blank_run_after() {  # file lineno -> contiguous blank lines starting right after lineno
  awk -v start="$2" '
    NR>start { if ($0=="") { n++; next } else { exit } }
    END { print n+0 }
  ' "$1"
}
sep_count() { grep -cE '^-{20,}$' "$1" 2>/dev/null || true; }
last_sep_lineno() { grep -nE '^-{20,}$' "$1" 2>/dev/null | tail -n1 | cut -d: -f1; }
trailing_blank_count() {
  awk '
    { lines[NR]=$0 }
    END { n=0; for (i=NR; i>=1; i--) { if (lines[i]=="") { n++ } else { break } } print n+0 }
  ' "$1"
}

workdir_count() { grep -Fc -- 'Working Directory:' "$1" 2>/dev/null || true; }
workdir_line()  { grep -F  -- 'Working Directory:' "$1" 2>/dev/null | head -n1; }

batchmode_count() { grep -Fc -- 'Batch Mode:' "$1" 2>/dev/null || true; }
batchmode_line()  { grep -F  -- 'Batch Mode:' "$1" 2>/dev/null | head -n1; }

dep_header_count()      { grep -Fc -- 'Depends on the following services:' "$1" 2>/dev/null || true; }
legacy_dep_label_count() { grep -c '^Depends on: ' "$1" 2>/dev/null || true; }
# Terminated by a blank line OR the closing separator, not just a blank line -
# the environment block is the LAST content section in the measured shape, so
# when a definition has no custom variables to force a block after it,
# customvars_entries would otherwise run straight into the dash separator and
# count it as one more "entry". Found live: upstream's own zzinfo_full capture
# reported 3 custom-variable entries instead of 2 before this was added.
dep_entries() {
  awk '
    /^Depends on the following services:$/ { flag=1; next }
    flag && (/^$/ || /^-{20,}$/) { exit }
    flag { sub(/^[ \t]+/,""); print }
  ' "$1"
}
dep_indent_ok() {
  local bad
  bad=$(awk '
    /^Depends on the following services:$/ { flag=1; next }
    flag && (/^$/ || /^-{20,}$/) { exit }
    flag { if ($0 !~ /^    [^ ]/) print "BAD:" $0 }
  ' "$1")
  [ -z "$bad" ] && echo yes || echo no
}

group_line_count() { grep -c '^Group:' "$1" 2>/dev/null || true; }

inherits_count() { grep -Fc -- 'Inherits environment variables?:' "$1" 2>/dev/null || true; }
inherits_line()  { grep -F  -- 'Inherits environment variables?:' "$1" 2>/dev/null | head -n1; }
customvars_header_count() { grep -Fc -- 'Custom environment variables:' "$1" 2>/dev/null || true; }
customvars_entries() {
  awk '
    /^Custom environment variables:$/ { flag=1; next }
    flag && (/^$/ || /^-{20,}$/) { exit }
    flag { sub(/^[ \t]+/,""); print }
  ' "$1"
}
customvars_indent_ok() {
  local bad
  bad=$(awk '
    /^Custom environment variables:$/ { flag=1; next }
    flag && (/^$/ || /^-{20,}$/) { exit }
    flag { if ($0 !~ /^    [^ ]/) print "BAD:" $0 }
  ' "$1")
  [ -z "$bad" ] && echo yes || echo no
}

# spacing_problems FILE - differences 1, 2 and 8 together: the leading blank
# count, that the separator really is what follows them, the blank count
# after the name line, that there are exactly two separators, and that the
# closing one is followed by exactly three blank lines and nothing else.
spacing_problems() {
  local f="$1" lb fnb_no fnb_line ba nsep last_sep total tb after_last
  lb=$(leading_blank_count "$f")
  [ "$lb" -eq 2 ] || echo "blank-lines-before-separator=$lb (wanted 2)"
  fnb_no=$(first_nonblank_lineno "$f")
  if [ -z "$fnb_no" ]; then
    echo "stdout has no non-blank line at all - cannot find the separator"
    return
  fi
  fnb_line=$(sed -n "${fnb_no}p" "$f")
  if [[ ! "$fnb_line" =~ ^-{20,}$ ]]; then
    echo "the first non-blank line is not a dash separator: '$fnb_line'"
  fi
  ba=$(blank_run_after "$f" "$((fnb_no + 1))")
  [ "$ba" -eq 2 ] || echo "blank-lines-after-name=$ba (wanted 2)"
  nsep=$(sep_count "$f")
  [ "$nsep" -eq 2 ] || echo "separator-lines=$nsep (wanted 2: opening and closing)"
  # Only inspect what follows the closing separator once there really IS one
  # distinct from the opening one - with nsep=1 (today's bug: RMSC never
  # closes the block) "last separator" IS the opening one, and everything
  # printed after it would be misreported as trailing content. The row above
  # already names that defect precisely; this block only adds information
  # once there is a genuine closing separator to check.
  if [ "$nsep" -eq 2 ]; then
    last_sep=$(last_sep_lineno "$f")
    total=$(count_lines "$f")
    after_last=$((total - last_sep))
    tb=$(trailing_blank_count "$f")
    [ "$tb" -eq 3 ] || echo "trailing-blank-lines=$tb (wanted 3)"
    if [ "$after_last" -ne "$tb" ]; then
      echo "$((after_last - tb)) non-blank line(s) follow the closing separator"
    fi
  fi
}

# workdir_problems FILE MODE(absent|present) [WANT_LINE]
workdir_problems() {
  local f="$1" mode="$2" want="$3" wc line
  wc=$(workdir_count "$f")
  if [ "$mode" = absent ]; then
    [ "$wc" -eq 0 ] || echo "'Working Directory:' present ($wc time(s)) - wanted none, dir: was never set"
  else
    [ "$wc" -eq 1 ] || echo "'Working Directory:' appears $wc time(s) - wanted exactly once"
    if [ "$wc" -ge 1 ] && [ -n "$want" ]; then
      line=$(workdir_line "$f")
      [ "$line" = "$want" ] || echo "line is '$line', wanted '$want'"
    fi
  fi
}

# batchmode_problems FILE - difference 4, unconditional.
batchmode_problems() {
  local f="$1" bc line
  bc=$(batchmode_count "$f")
  if [ "$bc" -ne 1 ]; then
    echo "'Batch Mode:' appears $bc time(s) - wanted exactly once, unconditionally"
    return
  fi
  line=$(batchmode_line "$f")
  [ "$line" = 'Batch Mode: <not running in batch>' ] || \
    echo "line is '$line', wanted 'Batch Mode: <not running in batch>'"
}

# deps_problems FILE MODE(present|absent) [WANT_ENTRIES_FILE]
deps_problems() {
  local f="$1" mode="$2" want="$3" hc legacy entries indent_ok got_sorted want_sorted
  hc=$(dep_header_count "$f")
  legacy=$(legacy_dep_label_count "$f")
  if [ "$mode" = absent ]; then
    [ "$hc" -eq 0 ] || echo "dependency header present ($hc time(s)) - wanted none, no dependencies staged here"
    [ "$legacy" -eq 0 ] || echo "$legacy legacy 'Depends on: ' line(s) present with no dependencies staged"
    return
  fi
  [ "$hc" -eq 1 ] || echo "dependency header appears $hc time(s) - wanted exactly once (not once per dependency)"
  [ "$legacy" -eq 0 ] || echo "$legacy legacy 'Depends on: ' line(s) also present"
  if [ "$hc" -eq 1 ]; then
    indent_ok=$(dep_indent_ok "$f")
    [ "$indent_ok" = yes ] || echo "one or more dependency entries are not indented exactly 4 spaces"
    got_sorted=$(dep_entries "$f" | sort -u)
    want_sorted=$(sort -u "$want")
    [ "$got_sorted" = "$want_sorted" ] || \
      echo "dependency entries are {$(printf '%s' "$got_sorted" | tr '\n' ',')} - wanted {$(printf '%s' "$want_sorted" | tr '\n' ',')}"
  fi
}

# group_problems FILE - difference 6: removed entirely, not reshaped.
group_problems() {
  local gc
  gc=$(group_line_count "$1")
  [ "$gc" -eq 0 ] || echo "$gc 'Group:' line(s) present - upstream never prints this; decided to remove it entirely"
}

# env_problems FILE MODE(vars-present|vars-absent) [WANT_ENTRIES_FILE]
env_problems() {
  local f="$1" mode="$2" want="$3" ic cc indent_ok got_sorted want_sorted
  ic=$(inherits_count "$f")
  [ "$ic" -eq 1 ] || echo "'Inherits environment variables?:' appears $ic time(s) - wanted exactly once, unconditionally"
  cc=$(customvars_header_count "$f")
  if [ "$mode" = vars-present ]; then
    [ "$cc" -eq 1 ] || echo "'Custom environment variables:' appears $cc time(s) - wanted exactly once"
    if [ "$cc" -eq 1 ]; then
      indent_ok=$(customvars_indent_ok "$f")
      [ "$indent_ok" = yes ] || echo "one or more custom environment entries are not indented exactly 4 spaces"
      got_sorted=$(customvars_entries "$f" | sort -u)
      want_sorted=$(sort -u "$want")
      [ "$got_sorted" = "$want_sorted" ] || \
        echo "custom environment entries are {$(printf '%s' "$got_sorted" | tr '\n' ',')} - wanted {$(printf '%s' "$want_sorted" | tr '\n' ',')}"
    fi
  else
    [ "$cc" -eq 0 ] || echo "'Custom environment variables:' present ($cc time(s)) - wanted none, no custom vars staged here"
  fi
}

printf 'info: blank-line counts, Working Directory, Batch Mode, dependencies,\n'
printf '      groups, environment variables, and the closing separator\n'
printf 'scr: %s\n' "$SCR"
printf 'sc:  %s (%s)\n' "$SC" \
  "$("$SC" --version 2>/dev/null </dev/null | head -n 1 || echo 'version unknown')"
printf 'fixtures: %s (deps+group+env, no dir), %s (nothing set, no dir), %s (dir set)\n\n' \
  "$FULL" "$MIN" "$DIRSET"

# ---------------------------------------------------------------------------
echo "== stage 0: the fixture. Nothing below is evidence until every row passes"
echo
heading
# ---------------------------------------------------------------------------

# (a) EVERY DEFINITION LOADS.
fail_load=()
for pair in "$FULL:$FULL_F" "$MIN:$MIN_F" "$DIRSET:$DIRSET_F" "$DEP1:$DEP1_F" "$DEP2:$DEP2_F"; do
  n="${pair%%:*}"
  grab "chk.$n" "$SCR_ENV" "$SCR" check "$n"
  grep -qE "^  NOT RUNNING *\| $n \(" "$WORK/chk.$n.out" || fail_load+=("$n did not load as NOT RUNNING: $(cat "$WORK/chk.$n.out")")
done
if [ ${#fail_load[@]} -ne 0 ]; then
  hard_fail fixture-definitions "${fail_load[@]}"
fi
report PASS fixture-definitions "all five staged definitions load"
pass=$((pass+1))

# (b) THE GROUP HOLDS ONLY $FULL - so the group-removal case (6) has something
# real to prove RMSC no longer prints a line for.
grab chk.group "$SCR_ENV" "$SCR" check "group:$GROUP"
gm=$(grep -cE "\| ($FULL|$MIN|$DIRSET|$DEP1|$DEP2) \(" "$WORK/chk.group.out" 2>/dev/null || true)
[ -n "$gm" ] || gm=0
if [ "$gm" -ne 1 ] || ! grep -qF -- "$FULL (" "$WORK/chk.group.out"; then
  hard_fail group-membership \
    "group:$GROUP holds $gm of the fixtures under test, wanted exactly $FULL and no other" \
    "got: $(cat "$WORK/chk.group.out")"
fi
report PASS group-membership "group:$GROUP holds only $FULL"
pass=$((pass+1))

# (c) CAPTURE ALL SIX `info` RUNS - streams apart, before any assertion reads
# them, and check for a crash before trusting anything below.
grab scr.full   "$SCR_ENV" "$SCR" info "$FULL"
grab sc.full    "$SC_ENV"  "$SC"  info "$FULL"
grab scr.min    "$SCR_ENV" "$SCR" info "$MIN"
grab sc.min     "$SC_ENV"  "$SC"  info "$MIN"
grab scr.dirset "$SCR_ENV" "$SCR" info "$DIRSET"
grab sc.dirset  "$SC_ENV"  "$SC"  info "$DIRSET"

abend=()
for tag in scr.full sc.full scr.min sc.min scr.dirset sc.dirset; do
  if grep -qE "$ABEND_RE" "$WORK/$tag.out" "$WORK/$tag.err" 2>/dev/null; then
    abend+=("$tag: $(grep -hE -m1 "$ABEND_RE" "$WORK/$tag.out" "$WORK/$tag.err")")
  fi
  [ "${RC_SAVED[$tag]:-1}" -eq 0 ] || abend+=("$tag exited ${RC_SAVED[$tag]}, wanted 0")
done
if [ ${#abend[@]} -ne 0 ]; then
  hard_fail captures "${abend[@]}"
fi
report PASS captures "all six 'info' runs completed, exit 0, no abend"
pass=$((pass+1))

# (d) UPSTREAM ITSELF REACHES EVERY BRANCH THIS FILE IS BUILT TO CHECK. If it
# does not, nothing below would be testing what it claims to - the same
# argument as tools/jobinfo-test.sh's "two-distinct-jobs" hard fail.
branch=()
[ "$(dep_header_count "$WORK/sc.full.out")" -eq 1 ] || branch+=("upstream's own $FULL capture has no single dependency header - dep_header_count=$(dep_header_count "$WORK/sc.full.out")")
[ "$(dep_entries "$WORK/sc.full.out" | grep -c '.')" -eq 2 ] || branch+=("upstream's own $FULL capture does not list 2 dependency entries")
[ "$(workdir_count "$WORK/sc.full.out")" -eq 0 ] || branch+=("upstream's own $FULL capture (dir: unset) prints 'Working Directory:' - the omission cannot be exercised")
[ "$(workdir_count "$WORK/sc.min.out")" -eq 0 ] || branch+=("upstream's own $MIN capture (dir: unset) prints 'Working Directory:'")
[ "$(workdir_count "$WORK/sc.dirset.out")" -ge 1 ] || branch+=("upstream's own $DIRSET capture (dir: set) does not print 'Working Directory:' at all")
[ "$(customvars_header_count "$WORK/sc.full.out")" -eq 1 ] || branch+=("upstream's own $FULL capture has no single 'Custom environment variables:' header")
[ "$(customvars_entries "$WORK/sc.full.out" | grep -c '.')" -eq 2 ] || branch+=("upstream's own $FULL capture does not list 2 custom environment entries")
[ "$(customvars_header_count "$WORK/sc.min.out")" -eq 0 ] || branch+=("upstream's own $MIN capture prints a 'Custom environment variables:' header with nothing staged")
[ "$(inherits_count "$WORK/sc.full.out")" -eq 1 ] && [ "$(inherits_count "$WORK/sc.min.out")" -eq 1 ] && [ "$(inherits_count "$WORK/sc.dirset.out")" -eq 1 ] || \
  branch+=("upstream does not print 'Inherits environment variables?:' on all three captures")
[ "$(batchmode_count "$WORK/sc.full.out")" -eq 1 ] || branch+=("upstream's own $FULL capture does not print 'Batch Mode:'")
if [ ${#branch[@]} -ne 0 ]; then
  hard_fail upstream-reaches-every-branch "${branch[@]}"
fi
report PASS upstream-reaches-every-branch "dependencies, dir, custom vars, inherits-vars and batch mode all present in upstream's own captures"
pass=$((pass+1))

# Build the two "want" files used by the dependency and environment set
# comparisons below, from upstream's OWN capture - never assumed.
dep_entries "$WORK/sc.full.out" > "$WORK/full.dep.want"
printf 'ZZINFO_ONE=first\nZZINFO_TWO=second value with spaces\n' > "$WORK/full.env.want"
DIRSET_WANT_LINE=$(workdir_line "$WORK/sc.dirset.out")

echo
# ---------------------------------------------------------------------------
echo "== stage 1: the eight differences, against RMSC"
echo
heading
# ---------------------------------------------------------------------------

# 1/2/8 - spacing, on FULL and MIN (rival: blanks tied to an optional section)
mapfile -t P < <(spacing_problems "$WORK/scr.full.out")
verdict_row FAIL spacing-full "2 blanks before separator, 2 after the name, closing separator + 3 trailing blanks" "${P[@]}"
mapfile -t P < <(spacing_problems "$WORK/scr.min.out")
verdict_row FAIL spacing-min "as above, with nothing else staged" "${P[@]}"

# 3 - Working Directory, all three directions
mapfile -t P < <(workdir_problems "$WORK/scr.full.out" absent)
verdict_row FAIL workdir-full "no 'Working Directory:' line - dir: was never set" "${P[@]}"
mapfile -t P < <(workdir_problems "$WORK/scr.min.out" absent)
verdict_row FAIL workdir-min "no 'Working Directory:' line - dir: was never set" "${P[@]}"
mapfile -t P < <(workdir_problems "$WORK/scr.dirset.out" present "$DIRSET_WANT_LINE")
verdict_row FAIL workdir-dirset "'Working Directory:' present and matches upstream - the direction that must not regress" "${P[@]}"

# 4 - Batch Mode, unconditional (the key case is MIN, nothing else staged)
mapfile -t P < <(batchmode_problems "$WORK/scr.min.out")
verdict_row FAIL batchmode-min "'Batch Mode: <not running in batch>' present with nothing else staged" "${P[@]}"
mapfile -t P < <(batchmode_problems "$WORK/scr.full.out")
verdict_row FAIL batchmode-full "same, alongside the other sections" "${P[@]}"

# 5 - dependencies: shape on FULL (two of them), absence on MIN and DIRSET
mapfile -t P < <(deps_problems "$WORK/scr.full.out" present "$WORK/full.dep.want")
verdict_row FAIL deps-shape-full "one header, both dependencies indented beneath it, no legacy per-dependency label" "${P[@]}"
mapfile -t P < <(deps_problems "$WORK/scr.min.out" absent)
verdict_row FAIL deps-absent-min "no dependency header - none staged" "${P[@]}"
mapfile -t P < <(deps_problems "$WORK/scr.dirset.out" absent)
verdict_row FAIL deps-absent-dirset "no dependency header - none staged" "${P[@]}"

# 6 - groups: removed entirely. FULL is the fixture with something to remove.
mapfile -t P < <(group_problems "$WORK/scr.full.out")
verdict_row FAIL group-line-removed-full "no 'Group:' line, even though $FULL is a member of group:$GROUP" "${P[@]}"

# 7 - environment: Inherits-vars unconditional (min proves it), custom vars
# conditional (full has them, min and dirset must not)
mapfile -t P < <(env_problems "$WORK/scr.min.out" vars-absent)
verdict_row FAIL env-min "'Inherits environment variables?:' present, 'Custom environment variables:' absent - nothing staged" "${P[@]}"
mapfile -t P < <(env_problems "$WORK/scr.full.out" vars-present "$WORK/full.env.want")
verdict_row FAIL env-full "'Inherits environment variables?:' present, both custom variables indented beneath their own header" "${P[@]}"
mapfile -t P < <(env_problems "$WORK/scr.dirset.out" vars-absent)
verdict_row FAIL env-dirset "'Inherits environment variables?:' present, 'Custom environment variables:' absent - nothing staged" "${P[@]}"

# The boolean VALUE of 'Inherits environment variables?:' is compared to
# upstream's own value rather than assumed - see "UNCERTAIN, FLAGGED" above.
for tag in full min dirset; do
  s_line=$(inherits_line "$WORK/scr.$tag.out")
  c_line=$(inherits_line "$WORK/sc.$tag.out")
  if [ "$s_line" = "$c_line" ] && [ -n "$c_line" ]; then
    report PASS "env-inherits-value-$tag" "RMSC agrees with upstream: '$c_line'"
    pass=$((pass+1))
  else
    report FAIL "env-inherits-value-$tag" ""
    detail "RMSC: '$s_line'"
    detail "upstream: '$c_line'"
    failed=$((failed+1))
  fi
done

echo
# ---------------------------------------------------------------------------
echo "== stage 2: upstream reference, re-checked against the same hardcoded"
echo "   constants stage 1 used (a REFDRIFT means the reference moved, not"
echo "   that RMSC regressed)"
echo
heading
# ---------------------------------------------------------------------------
#
# EVERY CONSTANT STAGE 1 ASSERTS AGAINST - the blank counts, the closing
# separator and its three blanks, the literal Batch Mode sentence, the
# dependency header text and its 4-space indent, the environment header texts
# - IS A TRANSCRIPTION from docs/messages.md's 3 September 2026 capture. This
# stage re-runs the same checks against upstream's OWN output, captured
# fresh in stage 0(c) of THIS run, so a stale transcription is caught here
# rather than silently failing RMSC for having correctly matched a version of
# upstream that no longer exists.

mapfile -t P < <(spacing_problems "$WORK/sc.full.out")
verdict_row REFDRIFT sc:spacing-full "as recorded" "${P[@]}"
mapfile -t P < <(spacing_problems "$WORK/sc.min.out")
verdict_row REFDRIFT sc:spacing-min "as recorded" "${P[@]}"

mapfile -t P < <(workdir_problems "$WORK/sc.full.out" absent)
verdict_row REFDRIFT sc:workdir-full "as recorded" "${P[@]}"
mapfile -t P < <(workdir_problems "$WORK/sc.min.out" absent)
verdict_row REFDRIFT sc:workdir-min "as recorded" "${P[@]}"
mapfile -t P < <(workdir_problems "$WORK/sc.dirset.out" present)
verdict_row REFDRIFT sc:workdir-dirset "as recorded" "${P[@]}"

mapfile -t P < <(batchmode_problems "$WORK/sc.min.out")
verdict_row REFDRIFT sc:batchmode-min "as recorded" "${P[@]}"

mapfile -t P < <(deps_problems "$WORK/sc.full.out" present "$WORK/full.dep.want")
verdict_row REFDRIFT sc:deps-shape-full "as recorded" "${P[@]}"

# env_problems' vars-present branch compares against a WANT file built from
# RMSC's own configured values, which is exactly what upstream is staged with
# too - both sides read the same YAML - so it is a fair reference check.
mapfile -t P < <(env_problems "$WORK/sc.min.out" vars-absent)
verdict_row REFDRIFT sc:env-min "as recorded" "${P[@]}"
mapfile -t P < <(env_problems "$WORK/sc.full.out" vars-present "$WORK/full.env.want")
verdict_row REFDRIFT sc:env-full "as recorded" "${P[@]}"

echo
echo "pass=$pass   failed=$failed   reference-drift=$refdrift"
echo "artefacts: $WORK   (.out and .err per case; KEEP=1 to keep them)"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT, and where it would have to be done instead
#
#   COLOUR of info's field labels and rule lines - deliberately still open in
#   docs/parity.md, and not part of the eight differences this file covers.
#
#   RELATIVE dir: RESOLUTION - tools/gate-fixtures/README.md's
#   rmscgate_info_reldir, a separate open question. DIRSET here is absolute.
#
#   WHICH IDENTITY FORM (short/friendly) A DEPENDENCY ENTRY USES - resolved by
#   reading it back from upstream's own capture rather than pinned here.
#
#   A DEPENDENCY THAT DOES NOT RESOLVE, OR A DEPENDENCY CYCLE - out of scope
#   for a formatting/shape harness; `info` does not evaluate dependencies.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: info does not print what upstream prints"
  exit 1
fi
if [ "$refdrift" -ne 0 ]; then
  echo "REFERENCE DRIFT: upstream sc no longer behaves as docs/messages.md records."
  echo "Stage 1's expectations rest on that table - re-take it before trusting a"
  echo "pass or acting on a failure."
  exit 1
fi
echo "OK: blank-line counts, Working Directory, Batch Mode, dependencies, groups,"
echo "    environment variables and the closing separator all match upstream"
