#!/QOpenSys/pkgs/bin/bash
#
# load-warning-test.sh - the two things sc says while it is READING DEFINITIONS,
# before any operation has run: which files it refuses to mention, and how it
# spells a criterion that two services might turn out to share.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh, tools/narration-test.sh
# and tools/api-silence-test.sh, and modelled on the last two. It is a shell
# script rather than an iRPGUnit suite for the reason those give: a warning's
# STREAM, its PRESENCE OR ABSENCE at the command line, and the `info` block that
# carries the criterion text all exist only OUTSIDE the ILE job, and iRPGUnit
# runs inside one. `SCCOLL_load_dir` returns no list of the files it skipped and
# `SCEXEC_info` returns nothing at all, so there is no value an in-job assertion
# could read for either.
#
# ITS OTHER HALVES ARE IN qtestsrc/, and it is worth saying which side answers
# what, because between them they cover one defect from two directions:
#
#   SCDEF.TEST    what SCDEF_criterion_text RENDERS for a criterion reached
#                 through check_alive_criteria, which is a returned value
#   SCCOLL.TEST   whether SCCOLL_conflicts DECIDES that two such criteria are
#                 the same one, which is a returned count
#   this script   whether a WARNING reaches the user, on which stream, and what
#                 `sc info` prints - none of which is a value
#
# WHY THIS PACK EXISTS AT ALL. Both rules below were found as DEFECTS by
# tools/gate-fixtures-run.sh on its first ever run, and neither was reachable
# by anything installed on this machine: no service here is named through
# check_alive_criteria, and nobody has left a .rpmnew beside a definition. They
# are written up in docs/messages.md § "Two defects the fixture pack found on
# its first run".
#
# BOTH ARE NOW FIXED, AND THAT IS WHEN THIS FILE BECOMES WORTH MORE, NOT LESS.
# A pack written while a defect is live only has to fail; once the defect is
# closed, what it has to do is fail against the NEXT wrong reading, and the two
# are not the same job. The first version of every rule here was measured
# coarsely enough that the implementation could have been wrong in a way no
# fixture would have shown - a case-sensitive .rpmnew, a trimmed filename, a
# port normalised on both keys. The separating values below are what the
# second, finer measurement added, and each one names the reading it rules out.
#
# BASIS OF EVERY ASSERTION HERE IS `measured`, and measured TWICE: once on
# 4 September against sc 1.7.1, and again on every run, because stage 1 of each
# group compares UPSTREAM to the expectation before comparing RMSC to anything.
# A reference that has drifted is reported as REFDRIFT and is not a defect in
# RMSC. That is the same guard tools/narration-test.sh stage 4 uses, moved to
# the front because here it is cheap: nothing has to be started for it.
#
# THE SEPARATING VALUES, which is what makes this pack worth more than the
# filenames and spellings it happens to contain. Every rule here has a rival
# that fits all the obvious data and is wrong, and each rival is cheaper to
# implement than the truth, which is why it is the one to guard against.
#
#   .rpmsave        Rival: "backup-ish extensions are skipped quietly". Fits
#                   every .rpmnew exactly. Upstream WARNS about .rpmsave, .bak,
#                   .orig, ~, .disabled, .swp and .old, so the real rule is one
#                   specific suppression, not a class of them.
#
#   .YAML.RPMNEW    Rival: a literal, case-sensitive '.rpmnew'. Fits every
#                   lower-case fixture exactly. Upstream lower-cases the name
#                   before testing it.
#
#   x_rpmnew        Rival: '.rpmnew', with the dot. Fits every dotted fixture
#                   exactly. The suffix is six letters and the dot is not part
#                   of it, so bare 'rpmnew' is silent too.
#
#   a trailing      Rival: test the TRIMMED name. Fits every other row in this
#   blank           file, because trimming only ever makes it quieter and every
#                   other row fails by RMSC saying too much. This is the ONLY
#                   fixture in the pack where the wrong implementation is
#                   silent and upstream is not.
#
#   rpmnewx         Rival: "contains rpmnew". The test is endsWith.
#
#   65+ characters  Rival: a rule that stops reading early. Every other fixture
#                   here is short, so none of them could see it.
#
# TWO OF THE THREE DEFECTS FOUND IN THIS RULE WERE ABOUT THE BOUNDARY OF THE
# VALUE, NOT THE LOGIC ON IT, and both were invisible to every fixture chosen
# for what it SPELLS:
#
#   a %trim swallowed a trailing blank, so a name upstream warns about was
#   skipped in silence;
#
#   ends_with took a 64-character parameter where a directory entry is 640, so
#   every name past 64 characters was cut before the rule saw its tail - and a
#   name whose first 64 characters happen to end in 'rpmnew' was then skipped
#   in silence, again against an upstream that warns.
#
# So the next case worth adding here is more likely to be another LENGTH or
# another edge of the value than another spelling. The pack now carries a
# fixture at each: a name with a trailing blank, and names either side of 64
# characters differing only past the cut. Anyone adding to it should ask what
# BOUND a fixture reaches before asking what it spells.
#
#   the DIRECT form Rival: "job names are never upper-cased". Fits the
#                   companion-key measurement perfectly. Upstream DOES
#                   upper-case a job name written straight into check_alive:,
#                   and two services writing one job name in two cases DO
#                   collide there. Without the direct cases a fix could stop
#                   folding altogether and turn a real conflict warning off.
#
#   a leading zero  Rival: "the direct and companion keys are the same key".
#                   The job-name cases show the difference as CASE, which an
#                   implementation might special-case without ever finding the
#                   rule. Ports say the same thing in a different alphabet:
#                   08080 written directly is normalised to 8080 and one
#                   arriving through the companion is kept. Only having both
#                   shows the rule is about WHICH KEY, not about job names.
#
# NOTHING ON THE SYSTEM IS TOUCHED, and nothing is started or stopped. Every
# definition below lives in a work directory reached through SC_SERVICES_DIR
# (RMSC) and -Dservices.dir (upstream), every one of them is dead on purpose,
# and the work directory goes away with the trap. That is why this runs by
# default where tools/narration-test.sh has to argue for itself.
#
# Stdout and stderr are captured to SEPARATE files throughout. Nothing here
# uses `2>&1`. docs/messages.md records what a merged capture cost when
# loginfo's stream difference hid inside one, and both defects here are stderr
# differences sitting behind identical stdout.
#
# Set LOADWARN_DRY=1 to print the staged definitions and exit. Set KEEP=1 to
# leave the work directory behind.
#
set -o pipefail
export QIBM_MULTI_THREADED=Y

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-$(mktemp -d /tmp/rmsc-loadwarn.XXXXXX)}"

cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$WORK"; }
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

# BOTH IMPLEMENTATIONS, OR NOTHING. A missing scr produces empty output from
# every RMSC run, and empty output passes every absence in stage 1 and stage 2
# while failing stage 0 - a shape that reads like a half-fixed defect rather
# than like a broken harness. This was not hypothetical: running a copy of this
# file from another directory resolves DEPLOY to that directory, and the first
# mutation run did exactly that.
for tool in "$SC" "$SCR"; do
  [ -x "$tool" ] && continue
  echo "load-warning-test: $tool is not executable." >&2
  echo "  Set SC= and SCR=, or DEPLOY= to the deploy directory holding scripts/scr." >&2
  exit 2
done

# ---------------------------------------------------------------------------
# The fixture vocabulary
#
# Short names are lower case with an underscore; friendly names are capitalised
# words with spaces; no short name is a substring of any friendly name. That is
# tools/narration-test.sh's convention and it is kept here for the same reason:
# it makes "this name did not appear" a real assertion rather than an accident
# of spelling.
#
# THE JOB NAMES ARE ALL DEAD AND ALL INVENTED. Liveness is never asserted in
# this file - only the text of a criterion and the presence of a warning - so a
# job that does not exist is the right fixture and a real one would only add a
# way for the run to depend on the machine.
# ---------------------------------------------------------------------------
DEADPORT=55951                 # never probed; the control service's criterion
JOB_SHORT=rmsclwdeadjob        # 13 characters, in one case or the other

# EIGHTY CHARACTERS, and the length is the whole point of it. RMSC rendered
# this line from a result 64 wide, so 'JOBNAME:' plus the criterion was cut at
# 72 - which means every value shorter than 65 renders correctly and proves
# nothing. Measured 4 September with three upper-case job names so that only
# length varies: 40 -> 48 rendered, both agree; 64 -> 72, both agree, the exact
# boundary; 80 -> 88, upstream whole and RMSC cut. JOB_MID is the boundary and
# is kept so that a cap which merely MOVED is reported as a moved cap rather
# than as a fixed one.
JOB_MID=RMSCLWAAAAAAAAAABBBBBBBBBBCCCCCCCCCCDDDDDDDDDDEEEEEEEEEEFFFFFFFF
JOB_LONG=RMSCLWAAAAAAAAAABBBBBBBBBBCCCCCCCCCCDDDDDDDDDDEEEEEEEEEEFFFFFFFFFFGGGGGGGGGGHHHH

mkd() { mkdir -p "$WORK/$1"; }

# def DIR SHORTNAME FRIENDLY BODY...
def() {
  local d="$1" s="$2" f="$3"; shift 3
  {
    printf 'name: %s\n' "$f"
    printf 'start_cmd: /QOpenSys/usr/bin/true\n'
    local l; for l in "$@"; do printf '%s\n' "$l"; done
  } > "$WORK/$d/$s.yaml"
}

# A control definition for every directory. Its purpose is stage 0: a warning
# that is absent from a directory nobody read is not evidence of anything, and
# the control's ROW is what shows the directory was read.
control() { def "$1" rmsclw_control 'Control Svc' "check_alive: $DEADPORT"; }

# --- group 1: the filename rule --------------------------------------------
#
# EVERY ONE OF THESE FILES HOLDS THE SAME VALID DEFINITION, so content cannot
# explain any difference in the outcome and only the NAME can. A fixture whose
# rejected files were also malformed would pass against an implementation that
# applied no name rule at all - the argument qtestsrc/SCCOLL.TEST.RPGLE's
# filename block already makes for its own nine files.
mkd names
control names
same_def() { cp "$WORK/names/rmsclw_control.yaml" "$WORK/names/$1"; }

# UPSTREAM'S RULE, measured across thirteen failing filenames on 4 September:
#
#     name.toLowerCase().endsWith("rpmnew")
#
# Three things in it that the obvious reading of '.rpmnew' gets wrong, and one
# group of fixtures for each. An earlier version of this file carried only the
# first group, and every one of its three names satisfies the wrong rule as
# readily as the right one - so it could not have told them apart.
#
# EVERY BASE NAME IS DISTINCT. /tmp on this machine is case-insensitive and
# case-preserving, so two fixtures differing only in case collapse into one
# file: the second overwrites the first, the directory comes out one short, and
# a set comparison against a list that still names both would report the
# missing one as a difference in behaviour. The listing check in stage 1 is
# what would catch it if this convention were ever broken.

# (i) the obvious ones - lower case, introduced by a dot. Three spellings,
#     because the suffix is 'rpmnew' and not '.yaml.rpmnew'.
SILENT_DOTTED=(rmsclw_a.yaml.rpmnew rmsclw_b.yml.rpmnew rmsclw_c.rpmnew)

# (ii) CASE. The comparison is made on a lower-cased copy, so these are silent
#      too. A rule written with a literal '.rpmnew' warns about all three.
SILENT_CASE=(rmsclw_k.YAML.RPMNEW rmsclw_l.RPMnew rmsclw_m.yaml.RpMnEw)

# (iii) NO DOT. The suffix is 'rpmnew', not '.rpmnew', so a name merely ENDING
#       in those six letters is silent however it got there - after an
#       underscore, after a letter, or on its own with no base name at all.
SILENT_NODOT=(rmsclw_n_rpmnew rmsclw_orpmnew rpmnew)

# Skipped and WARNED ABOUT by upstream. rmsclw_d.yaml.rpmsave is the separating
# value for the extension; the other six are the surrounding evidence that the
# rule is about one suffix rather than about backups.
WARNED=(rmsclw_d.yaml.rpmsave rmsclw_e.yaml.bak rmsclw_f.yaml.orig
        rmsclw_g.yaml~ rmsclw_h.yaml.disabled rmsclw_i.yaml.swp
        rmsclw_j.yaml.old)

# THE TWO EDGE CASES, and the first is the sharpest fixture in this file.
#
#   rmsclw_p.yaml.rpmnew    with a TRAILING BLANK. The name is not trimmed
#                           before the test, so it does not end in rpmnew, so
#                           upstream WARNS. This is the ONLY case in the whole
#                           pack where the wrong implementation is SILENT and
#                           upstream is not - every other row here fails by RMSC
#                           saying too much. A test that only checks "the rpmnew
#                           ones are quiet" can never catch a rule that trims,
#                           because trimming only ever makes it quieter.
#                           It is the same discipline is_yaml keeps, which the
#                           codebase comments on twice.
#
#   rmsclw_q.yaml.rpmnewx   ENDS with, not CONTAINS. Warned about.
WARNED_EDGE=('rmsclw_p.yaml.rpmnew ' rmsclw_q.yaml.rpmnewx)

# (iv) LENGTH. The rule is applied to the WHOLE name, however long it is. Every
#      other fixture in this pack is short enough to fit any plausible buffer,
#      so none of them could see a rule that stopped reading early - and one
#      did. `ends_with` took a 64-character parameter while a directory entry
#      is 640, so every name past 64 characters was cut before the rule saw its
#      tail.
#
#      THE THREE NAMES DIFFER ONLY PAST THE OLD CUT, which is what makes them a
#      separating set rather than three long names:
#
#        rvz + 61x + 'rpmnew'           70 chars. Ends in rpmnew, so silent.
#                                       Cut at 64 it ends in 'x', so a narrow
#                                       parameter WARNS about a file upstream
#                                       will not mention.
#        rvy + 55x + 'rpmnew' + '.bak'  68 chars. Ends in .bak, so WARNED about.
#                                       Cut at 64 it ends in 'rpmnew', so a
#                                       narrow parameter goes SILENT about a
#                                       file upstream warns about. THIS IS THE
#                                       DANGEROUS DIRECTION, and the only other
#                                       fixture here that runs this way is the
#                                       trailing blank.
#        rvw + 62x + '.bak'             69 chars. CONTROL - past the cut and
#                                       warned about either way, so it shows
#                                       the pair above is about what follows
#                                       the cut rather than about length alone.
x61=$(printf 'x%.0s' $(seq 61))
x55=$(printf 'x%.0s' $(seq 55))
x62=$(printf 'x%.0s' $(seq 62))
LONG_SILENT="rvz${x61}rpmnew"
LONG_WARNED="rvy${x55}rpmnew.bak"
LONG_CONTROL="rvw${x62}.bak"

SILENT=("${SILENT_DOTTED[@]}" "${SILENT_CASE[@]}" "${SILENT_NODOT[@]}"
        "$LONG_SILENT")
ALL_WARNED=("${WARNED[@]}" "${WARNED_EDGE[@]}" "$LONG_WARNED" "$LONG_CONTROL")

for n in "${SILENT[@]}" "${ALL_WARNED[@]}"; do same_def "$n"; done

# A second directory holding the control ALONE, so "the .rpmnew files did not
# become services" can be stated as a comparison of two service lists rather
# than as a guess about what they would have been called.
mkd nonames
control nonames

# --- group 2: the criterion, reached two ways -------------------------------
#
# Four directories, each a collection of its own, because each asserts a COUNT
# of conflicts and a shared directory would make every count a count of
# everything else as well.

# (a) COMPANION form, two cases. Upstream keeps each as written, so these are
#     two different criteria and it says nothing.
mkd compcase
control compcase
def compcase rmsclw_lower 'Lower Comp' 'check_alive: jobname' \
    "check_alive_criteria: $JOB_SHORT"
def compcase rmsclw_upper 'Upper Comp' 'check_alive: jobname' \
    "check_alive_criteria: $(echo "$JOB_SHORT" | tr a-z A-Z)"

# (b) DIRECT form, the same two cases. THE RIVAL KILLER: upstream folds these
#     and warns. A fix that simply stopped upper-casing job names would turn
#     this warning off, and this is the only case that would notice.
mkd dircase
control dircase
def dircase rmsclw_dlower 'Lower Direct' "check_alive: $JOB_SHORT"
def dircase rmsclw_dupper 'Upper Direct' \
    "check_alive: $(echo "$JOB_SHORT" | tr a-z A-Z)"

# (c) COMPANION form, ONE spelling written twice. These really do conflict, and
#     upstream quotes the criterion in the warning AS WRITTEN. Without this
#     case, "companion criteria never conflict" would pass (a) and (b) both.
mkd compsame
control compsame
def compsame rmsclw_one 'Same One' 'check_alive: jobname' \
    "check_alive_criteria: $JOB_SHORT"
def compsame rmsclw_two 'Same Two' 'check_alive: jobname' \
    "check_alive_criteria: $JOB_SHORT"

# (e) PORTS. The same direct-versus-companion rule, spelled as a leading zero
#     instead of as a case difference - a port written into check_alive: is
#     NORMALISED and one arriving through check_alive_criteria: is kept
#     VERBATIM. Measured 4 September; docs/parity.md:377 has the rendering
#     half. Four directories, each ruling out a different wrong reading, and a
#     different port number in each so that a fixture leaking between them
#     changes a count rather than passing unnoticed.
mkd portzero
control portzero
def portzero rmsclw_pzero  'Padded Direct' 'check_alive: 08080'
def portzero rmsclw_pplain 'Plain Direct'  'check_alive: 8080'

mkd portcomp
control portcomp
def portcomp rmsclw_czero  'Padded Comp' 'check_alive: port' \
    'check_alive_criteria: 08081'
def portcomp rmsclw_cplain 'Plain Comp'  'check_alive: port' \
    'check_alive_criteria: 8081'

mkd portsame
control portsame
def portsame rmsclw_sone 'Same Port One' 'check_alive: port' \
    'check_alive_criteria: 08082'
def portsame rmsclw_stwo 'Same Port Two' 'check_alive: port' \
    'check_alive_criteria: 08082'

mkd portmix
control portmix
def portmix rmsclw_mdir  'Mixed Direct' 'check_alive: 8083'
def portmix rmsclw_mcomp 'Mixed Comp'   'check_alive: port' \
    'check_alive_criteria: 08083'

# (d) the criterion TEXT on its own, read back through `info`. One service per
#     form, no conflicts wanted here.
mkd text
control text
def text rmsclw_tcomp  'Text Comp'  'check_alive: jobname' \
    "check_alive_criteria: $JOB_SHORT"
def text rmsclw_tdir   'Text Direct' "check_alive: $JOB_SHORT"
def text rmsclw_tmid   'Text Mid'    "check_alive: $JOB_MID"
def text rmsclw_tlong  'Text Long'   "check_alive: $JOB_LONG"
def text rmsclw_tclong 'Text Comp Long' 'check_alive: jobname' \
    "check_alive_criteria: $JOB_LONG"
def text rmsclw_tpzero 'Text Port Padded' 'check_alive: port' \
    'check_alive_criteria: 08084'
def text rmsclw_tpdir  'Text Port Direct' 'check_alive: 08085'

if [ -n "${LOADWARN_DRY:-}" ]; then
  echo "load-warning-test: dry run. Staged under $WORK:"
  for f in "$WORK"/*/*; do echo; echo "--- $f"; cat "$f"; done
  exit 0
fi

# ---------------------------------------------------------------------------
# Running the two implementations
#
# Upstream announces JAVA_TOOL_OPTIONS on its own stderr, which would otherwise
# read as output from the command under test.
# ---------------------------------------------------------------------------
sc_run() {   # TAG DIR -- argv...
  local tag="$1" d="$2"; shift 2; [ "$1" = "--" ] && shift
  JAVA_TOOL_OPTIONS="-Dservices.dir=$WORK/$d" "$SC" "$@" \
    > "$WORK/$tag.sc.out" 2> "$WORK/$tag.sc.raw"
  local rc=$?
  grep -v 'Picked up' "$WORK/$tag.sc.raw" > "$WORK/$tag.sc.err"
  return $rc
}

scr_run() {  # TAG DIR -- argv...
  local tag="$1" d="$2"; shift 2; [ "$1" = "--" ] && shift
  SC_SERVICES_DIR="$WORK/$d" "$SCR" "$@" \
    > "$WORK/$tag.scr.out" 2> "$WORK/$tag.scr.err"
}

both() {     # TAG DIR -- argv...
  local tag="$1" d="$2"; shift 2; [ "$1" = "--" ] && shift
  sc_run  "$tag" "$d" -- "$@"
  scr_run "$tag" "$d" -- "$@"
}

pass=0; failed=0; drift=0

report() { printf '  %-9s %-30s %s\n' "$1" "$2" "${*:3}"; }
detail() { printf '  %-9s %-30s   - %s\n' "" "" "$*"; }
head_row() {
  printf '  %-9s %-30s %s\n' verdict case detail
  printf '  %-9s %-30s %s\n' --------- ------------------------------ ------
}

check_named() {  # TAG NOTE problem...
  local tag="$1" note="$2"; shift 2
  if [ $# -eq 0 ]; then
    report PASS "$tag" "(measured) $note"; pass=$((pass+1)); return 0
  fi
  report FAIL "$tag" "(measured) $note"
  local p; for p in "$@"; do detail "$p"; done
  failed=$((failed+1)); return 1
}

# A drift is NOT a failure of RMSC and is counted apart. It means the sentence
# below no longer describes sc 1.7.1, and every assertion resting on it should
# be re-measured before anyone reads a red row as a defect.
ref_named() {  # TAG NOTE problem...
  local tag="$1" note="$2"; shift 2
  if [ $# -eq 0 ]; then
    report REF "$tag" "upstream still: $note"; return 0
  fi
  report REFDRIFT "$tag" "upstream NO LONGER: $note"
  local p; for p in "$@"; do detail "$p"; done
  drift=$((drift+1)); return 1
}

# The basenames named in "WARNING: Ignoring file: <path>" lines, sorted.
ign_names() {
  sed -n 's/^WARNING: Ignoring file: //p' "$1" 2>/dev/null \
    | sed 's:.*/::' | LC_ALL=C sort
}

# The services a run listed, sorted. `list` prints one row per service and its
# first field is the short name.
svc_names() { awk 'NF && $1 !~ /^WARNING:/ {print $1}' "$1" | LC_ALL=C sort; }

# The conflict criteria a run warned about, sorted. Member ORDER is not read:
# upstream's is Java hash iteration order and is not a contract, which
# qtestsrc/SCCOLL.TEST.RPGLE's conflict header records at length.
cfl_criteria() {
  sed -n "s/^WARNING: the following services all have conflicting definitions for liveliness check '\(.*\)':$/\1/p" \
    "$1" 2>/dev/null | LC_ALL=C sort
}

cfl_members() {
  sed -n 's/^    \([a-z0-9_-]*\) (.*)$/\1/p' "$1" 2>/dev/null | LC_ALL=C sort
}

alive_line() { sed -n 's/^Check-alive conditions: //p' "$1" 2>/dev/null | head -n 1; }

first() { head -n 1 "$1" 2>/dev/null | cut -c1-120; }

printf 'load warnings: the filename sc will not mention, and the criterion two services share\n'
printf 'sc:     %s\n' "$SC"
printf 'scr:    %s\n' "$SCR"
printf 'staged: %s\n\n' "$WORK"

# ===========================================================================
echo "== stage 0: the staging took"
echo
head_row
# ===========================================================================
#
# THE CONTROL'S ROW IS THE EVIDENCE. Every assertion below this line is either
# an absence or a comparison of two nearly-identical runs, and both are
# satisfied by a directory neither implementation ever opened. Nothing else in
# this file could tell the difference.
for d in names nonames compcase dircase compsame \
         portzero portcomp portsame portmix text; do
  both "stage0-$d" "$d" -- list --ignore-globals
  probs=()
  grep -q '^rmsclw_control' "$WORK/stage0-$d.scr.out" \
    || probs+=("RMSC does not list rmsclw_control from $d: $(first "$WORK/stage0-$d.scr.out")")
  grep -q '^rmsclw_control' "$WORK/stage0-$d.sc.out" \
    || probs+=("upstream does not list rmsclw_control from $d: $(first "$WORK/stage0-$d.sc.out")")
  check_named "staged-$d" "both implementations read $WORK/$d" "${probs[@]}"
done

echo
# ===========================================================================
echo "== stage 1: which files sc refuses to mention"
echo
head_row
# ===========================================================================
#
# MEASURED 4 September against sc 1.7.1, thirteen failing filenames in one
# directory. Upstream's rule is
#
#     name.toLowerCase().endsWith("rpmnew")
#
# and each of the groups below separates it from a reading that fits the three
# obvious names and is wrong. The rows are grouped by WHAT THEY DISCRIMINATE
# rather than reported one per filename: a red row should say which reading is
# being followed, and thirteen rows saying "this one differs" would not.

both names-warn names -- list --ignore-globals

ign_names "$WORK/names-warn.sc.err"  > "$WORK/names.sc.ign"
ign_names "$WORK/names-warn.scr.err" > "$WORK/names.scr.ign"

# --- THE FIXTURE PROVES ITSELF FIRST ---------------------------------------
#
# Two of the fixtures cannot be trusted to have reached disk as written, and
# they go wrong in OPPOSITE directions - which is why one check covers both
# rather than each row defending itself:
#
#   the case variants     /tmp here is case-insensitive and case-preserving, so
#                         two names differing only in case collapse into one
#                         file. The missing file then produces no warning, and
#                         "RMSC did not warn about it" PASSES - vacuously,
#                         about a file that is not there. Every base name in
#                         this pack is distinct so that this cannot happen, and
#                         this check is what enforces the convention.
#
#   the trailing blank    if it were trimmed on the way to disk the file would
#                         land as 'rmsclw_p.yaml.rpmnew', which really does end
#                         in rpmnew and really is silent - so the sharpest row
#                         in this file would go RED against an implementation
#                         that is behaving correctly. That is the less
#                         dangerous direction and the more confusing one: a red
#                         row that means "the fixture broke" reads exactly like
#                         a red row that means "RMSC trims the name".
#
# So the directory is read back and compared to the list this file intends,
# byte for byte, before any of it is believed. CLAUDE.md is explicit that a
# suite must not report something it has not established, and the blank-name
# block in qtestsrc/SCCOLL.TEST.RPGLE makes the same argument at length.
{ printf '%s\n' rmsclw_control.yaml "${SILENT[@]}" "${ALL_WARNED[@]}"; } \
  | LC_ALL=C sort > "$WORK/names.want"
# ls -A1, not ls -1. A dotfile is invisible to `ls -1`, so a fixture beginning
# with a dot would be missing from .have, present in .want, and this row would
# fail for a reason that has nothing to do with the directory - or, if one were
# ever added to .want as well, would pass while neither side had looked at it.
# -A rather than -a so that . and .. stay out of the comparison.
ls -A1 "$WORK/names" | LC_ALL=C sort > "$WORK/names.have"

probs=()
if ! cmp -s "$WORK/names.want" "$WORK/names.have"; then
  probs+=("the staged directory is not the one this file describes:")
  while IFS= read -r l; do probs+=("  $l"); done \
    < <(diff "$WORK/names.want" "$WORK/names.have" | grep '^[<>]' | head -6)
  probs+=("a name lost a trailing blank, or two differing only in case collapsed - nothing below is evidence until this is fixed")
fi
check_named fixture-names-intact \
  "all $(( 1 + ${#SILENT[@]} + ${#ALL_WARNED[@]} )) filenames reached disk exactly as written" \
  "${probs[@]}"

# --- the reference, re-measured -------------------------------------------
ref_group() {  # tag note name...
  local tag="$1" note="$2"; shift 2
  local n; probs=()
  for n in "$@"; do
    grep -qx -- "$n" "$WORK/names.sc.ign" \
      && probs+=("upstream now warns about [$n], which it did not on 4 September")
  done
  ref_named "$tag" "$note" "${probs[@]}"
}

ref_group ref-rpmnew-silent "says nothing about a lower-case dotted .rpmnew" \
  "${SILENT_DOTTED[@]}"
ref_group ref-rpmnew-case "ignores case: .YAML.RPMNEW and .RpMnEw are silent too" \
  "${SILENT_CASE[@]}"
ref_group ref-rpmnew-nodot "needs no dot: x_rpmnew, xrpmnew and bare rpmnew are silent" \
  "${SILENT_NODOT[@]}"
ref_group ref-rpmnew-long "reads the WHOLE name: a 70-character one ending in rpmnew is silent" \
  "$LONG_SILENT"

probs=()
for n in "${ALL_WARNED[@]}"; do
  grep -qx -- "$n" "$WORK/names.sc.ign" \
    || probs+=("upstream no longer warns about [$n]")
done
ref_named ref-others-warned \
  "warns about .rpmsave, six other backups, a trailing blank and rpmnewx" \
  "${probs[@]}"

# --- RMSC against it -------------------------------------------------------
silent_group() {  # tag note name...
  local tag="$1" note="$2"; shift 2
  local n; probs=()
  for n in "$@"; do
    grep -qx -- "$n" "$WORK/names.scr.ign" \
      && probs+=("RMSC prints [WARNING: Ignoring file: $WORK/names/$n]; upstream prints nothing for it")
  done
  check_named "$tag" "$note" "${probs[@]}"
}

silent_group silent-dotted \
  "a lower-case dotted .rpmnew is skipped without a word" "${SILENT_DOTTED[@]}"

# SEPARATING VALUE - rules out a literal, case-sensitive '.rpmnew' test, which
# fits every name in the group above exactly.
silent_group silent-case-varied \
  "and so is one in any case - the test is on a lower-cased copy" \
  "${SILENT_CASE[@]}"

# SEPARATING VALUE - rules out '.rpmnew' with the dot. The suffix is six
# letters, so a name merely ending in them is silent however it got there.
silent_group silent-undotted \
  "and so is one whose rpmnew is not introduced by a dot at all" \
  "${SILENT_NODOT[@]}"

# LENGTH, in the safe direction. A parameter too narrow to hold the name cuts
# it before the rule sees its tail, and this one then ends in 'x'.
silent_group silent-long-name \
  "a 70-character name ending in rpmnew is skipped without a word" \
  "$LONG_SILENT"

# LENGTH, in the DANGEROUS direction, and the second of only two rows in this
# file that run this way. The name ends in .bak and upstream warns about it;
# cut at 64 it ends in 'rpmnew', so a narrow parameter goes quiet about a file
# upstream will not touch. The control beside it is past the cut too and is
# warned about either way, so a red pair says "the tail is being lost" rather
# than "long names are handled differently".
probs=()
grep -qx -- "$LONG_WARNED" "$WORK/names.scr.ign" \
  || probs+=("RMSC says nothing about the 68-character [$LONG_WARNED], and upstream warns about it - its first 64 characters end in rpmnew, so the .bak is being cut off before the rule sees it")
grep -qx -- "$LONG_CONTROL" "$WORK/names.scr.ign" \
  || probs+=("RMSC says nothing about the 69-character control [$LONG_CONTROL] either, so this is about length rather than about what follows the cut")
check_named warned-long-name \
  "a 68-character name ending .bak is warned about, tail and all" "${probs[@]}"

# THE SHARPEST ROW IN THIS FILE, and the only one where the wrong
# implementation is SILENT where upstream WARNS. Everything else here fails by
# RMSC saying too much, so a rule that trimmed the name before testing it would
# be invisible to every other row - trimming only ever makes it quieter.
probs=()
blank_name='rmsclw_p.yaml.rpmnew '
grep -qx -- "$blank_name" "$WORK/names.scr.ign" \
  || probs+=("RMSC says nothing about [$blank_name], and upstream warns about it - the name is being trimmed before the rpmnew test, so a file upstream refuses to touch is being skipped in silence")
check_named warned-trailing-blank \
  "a trailing blank means the name does NOT end in rpmnew, so it is warned about" \
  "${probs[@]}"

# SEPARATING VALUE - rules out "contains rpmnew".
probs=()
grep -qx -- 'rmsclw_q.yaml.rpmnewx' "$WORK/names.scr.ign" \
  || probs+=("RMSC says nothing about rmsclw_q.yaml.rpmnewx - the test is endsWith, not contains")
check_named warned-rpmnewx \
  "rpmnewx does not END in rpmnew, so it is warned about" "${probs[@]}"

# SEPARATING VALUE - a fix reading "quietly skip the backup-ish extensions"
# fits every silent row above and fails here.
probs=()
for n in "${WARNED[@]}"; do
  grep -qx -- "$n" "$WORK/names.scr.ign" \
    || probs+=("RMSC says nothing about $n, and upstream warns about it - the suppression has been made too wide")
done
check_named warned-still-warned \
  ".rpmsave and the other six backups are still warned about" "${probs[@]}"

# --- and the files are skipped either way ----------------------------------
#
# Both implementations LOAD THE IDENTICAL SET of services whatever they say
# about it, so a fix that silenced the warning by starting to accept the file
# would be a much worse defect than the one it closed. The comparison is
# against a directory holding the control alone, so nothing here depends on
# guessing what a wrongly-accepted .rpmnew would have been called.
both names-svc   names   -- list --ignore-globals
both nonames-svc nonames -- list --ignore-globals
svc_names "$WORK/names-svc.scr.out"   > "$WORK/names.scr.svc"
svc_names "$WORK/nonames-svc.scr.out" > "$WORK/nonames.scr.svc"
svc_names "$WORK/names-svc.sc.out"    > "$WORK/names.sc.svc"

probs=()
cmp -s "$WORK/names.scr.svc" "$WORK/nonames.scr.svc" \
  || probs+=("RMSC lists [$(tr '\n' ' ' < "$WORK/names.scr.svc")] where the same directory without the thirteen files lists [$(tr '\n' ' ' < "$WORK/nonames.scr.svc")] - one of them was accepted as a definition")
cmp -s "$WORK/names.sc.svc" "$WORK/names.scr.svc" \
  || probs+=("the two implementations load different services from the same directory: upstream [$(tr '\n' ' ' < "$WORK/names.sc.svc")] RMSC [$(tr '\n' ' ' < "$WORK/names.scr.svc")]")
check_named skipped-not-loaded \
  "the thirteen files become no service on either side - only the warning differs" \
  "${probs[@]}"

echo
# ===========================================================================
echo "== stage 2: the criterion two services might share"
echo
head_row
# ===========================================================================
#
# MEASURED 4 September. A job name written straight into check_alive: is
# upper-cased by BOTH implementations. One arriving through
# check_alive_criteria: is kept as written by upstream and upper-cased by RMSC,
# so RMSC folds two different criteria onto one, decides two services claim it,
# and warns about a conflict that does not exist.

# --- (a) two spellings that must stay apart ---------------------------------
#
# This was RMSC's defect when the file was written: it folded the companion
# value, decided the two services claimed one criterion, and warned about a
# conflict that did not exist. The row now passes, and it stays because the
# rule it pins is the one every other row in this stage is measured against.
both compcase compcase -- list --ignore-globals

probs=()
[ -s "$WORK/compcase.sc.err" ] \
  && probs+=("upstream is no longer silent here: $(first "$WORK/compcase.sc.err")")
ref_named ref-comp-case-silent \
  "treats two cases of a companion job name as two criteria" "${probs[@]}"

probs=()
cfl_criteria "$WORK/compcase.scr.err" > "$WORK/compcase.scr.cfl"
if [ -s "$WORK/compcase.scr.cfl" ]; then
  probs+=("RMSC warns about [$(tr '\n' ' ' < "$WORK/compcase.scr.cfl")] claimed by [$(cfl_members "$WORK/compcase.scr.err" | tr '\n' ' ')]")
  probs+=("the two services name $JOB_SHORT and its upper-case spelling through check_alive_criteria, and upstream keeps those apart")
fi
check_named comp-case-no-conflict \
  "two cases of a companion job name are two criteria, and neither conflicts" \
  "${probs[@]}"

# --- (b) THE RIVAL KILLER --------------------------------------------------
#
# The same two spellings, written directly. Both implementations must fold them
# and warn. This is the row that stops "never upper-case a job name" being an
# acceptable fix for (a), and docs/messages.md records it as a measurement that
# has to keep passing.
both dircase dircase -- list --ignore-globals

want_direct="JOBNAME:$(echo "$JOB_SHORT" | tr a-z A-Z)"

probs=()
cfl_criteria "$WORK/dircase.sc.err" > "$WORK/dircase.sc.cfl"
grep -qx -- "$want_direct" "$WORK/dircase.sc.cfl" \
  || probs+=("upstream no longer folds two cases of a direct job name; it warned about [$(tr '\n' ' ' < "$WORK/dircase.sc.cfl")]")
ref_named ref-direct-case-folds \
  "folds two cases of a DIRECT job name onto $want_direct" "${probs[@]}"

probs=()
cfl_criteria "$WORK/dircase.scr.err" > "$WORK/dircase.scr.cfl"
grep -qx -- "$want_direct" "$WORK/dircase.scr.cfl" \
  || probs+=("RMSC does not warn about $want_direct; it warned about [$(tr '\n' ' ' < "$WORK/dircase.scr.cfl")]")
cmp -s <(cfl_members "$WORK/dircase.sc.err") <(cfl_members "$WORK/dircase.scr.err") \
  || probs+=("different claimants: upstream [$(cfl_members "$WORK/dircase.sc.err" | tr '\n' ' ')] RMSC [$(cfl_members "$WORK/dircase.scr.err" | tr '\n' ' ')]")
check_named direct-case-conflicts \
  "two cases of a DIRECT job name still collide, and still warn" "${probs[@]}"

# --- (c) a companion criterion that really is shared -----------------------
#
# One spelling, written twice. Without this row, "a companion criterion never
# conflicts with anything" passes (a) and (b) together, and a service silently
# stops being warned about when it genuinely does collide.
both compsame compsame -- list --ignore-globals

want_comp="JOBNAME:$JOB_SHORT"

probs=()
cfl_criteria "$WORK/compsame.sc.err" > "$WORK/compsame.sc.cfl"
grep -qx -- "$want_comp" "$WORK/compsame.sc.cfl" \
  || probs+=("upstream no longer warns about $want_comp; it warned about [$(tr '\n' ' ' < "$WORK/compsame.sc.cfl")]")
ref_named ref-comp-same-conflicts \
  "warns about $want_comp, quoting it as written" "${probs[@]}"

probs=()
cfl_criteria "$WORK/compsame.scr.err" > "$WORK/compsame.scr.cfl"
[ "$(wc -l < "$WORK/compsame.scr.cfl")" = 1 ] \
  || probs+=("RMSC reports $(wc -l < "$WORK/compsame.scr.cfl") conflicting criteria, wanted 1: [$(tr '\n' ' ' < "$WORK/compsame.scr.cfl")]")
grep -qx -- "$want_comp" "$WORK/compsame.scr.cfl" \
  || probs+=("RMSC quotes [$(tr '\n' ' ' < "$WORK/compsame.scr.cfl")] where upstream quotes [$want_comp] - the criterion is folded on the way into the warning")
cmp -s <(cfl_members "$WORK/compsame.sc.err") <(cfl_members "$WORK/compsame.scr.err") \
  || probs+=("different claimants: upstream [$(cfl_members "$WORK/compsame.sc.err" | tr '\n' ' ')] RMSC [$(cfl_members "$WORK/compsame.scr.err" | tr '\n' ' ')]")
check_named comp-same-conflicts \
  "one companion spelling written twice still conflicts, quoted as written" \
  "${probs[@]}"

# --- (d) THE SAME RULE, IN PORTS -------------------------------------------
#
# MEASURED 4 September. A port written into check_alive: is NORMALISED and one
# arriving through check_alive_criteria: is kept VERBATIM, which is the
# job-name rule in a different alphabet. docs/parity.md:377 has the rendering
# half; qtestsrc/SCCOLL.TEST.RPGLE has the four conflict counts.
#
# THESE ROWS RUN THE OTHER WAY ROUND. Every job-name row above guards against
# RMSC INVENTING a warning; portzero guards against it LOSING one - two
# services really do collide on 8080, and an implementation that kept the
# direct text verbatim would say nothing about it. A missing warning is the
# harder direction to notice, because nothing looks wrong.

port_case() {  # tag dir want-criterion|'' note
  local tag="$1" d="$2" want="$3" note="$4"
  both "$d" "$d" -- list --ignore-globals
  cfl_criteria "$WORK/$d.sc.err"  > "$WORK/$d.sc.cfl"
  cfl_criteria "$WORK/$d.scr.err" > "$WORK/$d.scr.cfl"

  probs=()
  if [ -n "$want" ]; then
    grep -qx -- "$want" "$WORK/$d.sc.cfl" \
      || probs+=("upstream no longer warns about $want; it warned about [$(tr '\n' ' ' < "$WORK/$d.sc.cfl")]")
  else
    [ -s "$WORK/$d.sc.cfl" ] \
      && probs+=("upstream is no longer silent here: it warned about [$(tr '\n' ' ' < "$WORK/$d.sc.cfl")]")
  fi
  ref_named "ref-$tag" "$note" "${probs[@]}"

  probs=()
  if ! cmp -s "$WORK/$d.sc.cfl" "$WORK/$d.scr.cfl"; then
    probs+=("upstream warns about [$(tr '\n' ' ' < "$WORK/$d.sc.cfl")]")
    probs+=("RMSC     warns about [$(tr '\n' ' ' < "$WORK/$d.scr.cfl")]")
  fi
  cmp -s <(cfl_members "$WORK/$d.sc.err") <(cfl_members "$WORK/$d.scr.err") \
    || probs+=("different claimants: upstream [$(cfl_members "$WORK/$d.sc.err" | tr '\n' ' ')] RMSC [$(cfl_members "$WORK/$d.scr.err" | tr '\n' ' ')]")
  check_named "$tag" "$note" "${probs[@]}"
}

port_case port-zero-padded portzero 'PORT:8080' \
  '08080 and 8080 written DIRECTLY are one criterion, reported normalised'
port_case port-companion-padding portcomp '' \
  '08081 and 8081 through the COMPANION key are two criteria, and silent'
port_case port-companion-same portsame 'PORT:08082' \
  'one companion spelling written twice conflicts, padding intact'
port_case port-direct-and-companion portmix '' \
  'a normalised direct port and a verbatim companion one do not meet'

echo
# ===========================================================================
echo "== stage 3: the criterion text, read back through info"
echo
head_row
# ===========================================================================
#
# `info` differs from upstream in eight other ways, all recorded in
# docs/messages.md § info, so the WHOLE BLOCK cannot be compared yet. Only the
# 'Check-alive conditions:' line is read here, and it is compared to upstream's
# same line rather than to a literal, so these rows close automatically when
# the rendering does and cannot go stale in the meantime.
#
# THE LONG NAMES ARE NOT DECORATION, and the length they are is the whole of
# what they say. Measured on 4 September, and NOT part of either defect the
# fixture pack reported: the criterion is carried in a result 64 characters
# wide, so 'JOBNAME:' plus the criterion is cut at 72 - in the DIRECT form as
# much as the companion one.
#
#     40 characters  ->  48 rendered   both sides agree
#     64 characters  ->  72 rendered   both sides agree - the exact boundary
#     80 characters  ->  88 rendered   upstream whole, RMSC cut at 72
#
# THE BOUNDARY CASE IS WHY tmid IS HERE. A cap that merely MOVED - to 72, or to
# any other convenient width - would pass a test carrying only the 80 while
# still being a cap, and a test carrying only the 64 could never fail at all.
# The pair says where the edge is, which is what a red row has to say if it is
# to be acted on.
#
# THIS IS THE MISTAKE THE FIRST VERSION OF THIS FILE MADE, and it is worth
# naming because it looked like coverage. Its long names were seventeen and
# eighteen characters - shorter than every cap this code has ever had - so they
# could not fail, and they were written against a truncation at ten that had
# already been fixed a layer up. A value chosen to be 'long' is not a value
# chosen to cross a boundary.
#
# THE PORT ROWS carry the direct-versus-companion rule into `info`: 08084
# through the companion renders PORT:08084 and 08085 written directly renders
# PORT:8085. They are the rendering half of the conflict counts in stage 2.
for s in rmsclw_tcomp rmsclw_tdir rmsclw_tmid rmsclw_tlong rmsclw_tclong \
         rmsclw_tpzero rmsclw_tpdir; do
  both "info-$s" text -- info "$s"
  u=$(alive_line "$WORK/info-$s.sc.out")
  r=$(alive_line "$WORK/info-$s.scr.out")
  probs=()
  if [ -z "$u" ]; then
    probs+=("upstream printed no Check-alive line for $s - the fixture, not RMSC, is what failed")
  elif [ "$u" != "$r" ]; then
    probs+=("upstream [$u]")
    probs+=("RMSC     [${r:-<no Check-alive line>}]")
  fi
  check_named "info-${s#rmsclw_}" \
    "the Check-alive line matches upstream byte for byte" "${probs[@]}"
done

echo
printf 'pass=%s  failed=%s  refdrift=%s\n' "$pass" "$failed" "$drift"
if [ "$drift" -ne 0 ]; then
  echo
  echo "REFDRIFT means sc 1.7.1 no longer behaves as this file says it did on"
  echo "4 September. Re-measure before reading any FAIL above as a defect: the"
  echo "expectations here were taken from that machine on that day."
fi
[ -n "${KEEP:-}" ] && echo "artefacts kept in $WORK"
[ "$failed" -eq 0 ] && [ "$drift" -eq 0 ]
