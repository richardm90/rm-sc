#!/QOpenSys/pkgs/bin/bash
#
# gate-granularity-test.sh - proves tools/fidelity-gate.sh classifies perfinfo
# per RECORDED DIFFERENCE, not per operation.
#
# verification step 8, docs/parity.md "The gate" — tightens `INTENTIONAL` to
# per-recorded-difference for perfinfo. Before that fix, INTENTIONAL
# sanctioned an operation wholesale: perfinfo carries two settled, catalogued
# differences (the four affinity lines upstream prints and RMSC omits, and
# the order of the per-job blocks - see docs/parity.md), and ANY THIRD
# difference in that operation rode along under the same "by design" verdict,
# unreported. This runs the real gate script against synthetic `sc`/`scr`
# stand-ins, standing in for the box's own binaries via the SC/SCR overrides
# the script already documents ("Override any of these to compare a build
# somewhere else"), and checks two things that changed: whether a genuine,
# uncatalogued VALUE difference inside perfinfo still gets through, and
# whether two jobs' figures being swapped between them - a whole-file `sort`
# cannot tell that apart from an accepted re-ordering of the job blocks
# themselves, and an earlier version of the fix made exactly that mistake,
# caught only by review - still gets through.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh, using the same bash.
# Needs nothing live - no service, no listener, no real sc or scr - because
# what is under test is the CLASSIFIER, not either implementation.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${GATE:-$HERE/fidelity-gate.sh}"
WORK="${WORK:-/tmp/gate-granularity-test.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT - the rule fidelity-gate.sh,
# narration-test.sh and colour-test.sh all carry, and the reasoning for it is
# written out in full in fidelity-gate.sh, not repeated here. Deliberately
# duplicated rather than shared: change one, change all of them.
ls -dt /tmp/gate-granularity-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
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

# NOT REMOVED ON EXIT, unlike a script that starts something in the
# background - there is nothing here that outlives the process, so nothing
# needs a trap to reap it. Kept for the same reason fidelity-gate.sh keeps
# its own: this prints "artefacts: $WORK" below, and a directory removed
# before anyone reads that line would make the line a lie. The entry sweep
# above is what stops these from accumulating.
mkdir -p "$WORK/bin" "$WORK/baseline"

pass=0; failed=0

report() { printf '  %-9s %-28s %s\n' "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# One fixed service ("svc1"), one fixed stage-1 shape (identical on both
# sides so stage 1 and the no-colour check pass cleanly and stage 2 is
# reached), and every DIFF_OPS operation OTHER than perfinfo given ONLY
# enough to keep its OWN classification stable and out of the way - this is
# a test of the classifier, not a second copy of the fixture pack, so
# nothing but perfinfo is given anything NEW to disagree about:
#
#   check, loginfo, jobinfo, info   klass=none  - identical both sides, PASS
#   file, scrunattrs                intentional - differ both sides, by design
#
# info moved into the first group 20 September 2026, when its own last
# UNDECIDED item (the relative dir: question) closed and
# tools/fidelity-gate.sh's UNDECIDED list went empty - there is currently no
# real operation this stub can imitate to exercise an "undecided" verdict,
# and inventing a fake UNDECIDED entry in production code just to keep a
# test case would be worse than not having the case.
#
# Without this, a stub returning the same fixed text for every operation
# makes file/scrunattrs each RECLASSIFY - "now matches, remove it from the
# list" - which fails the gate for reasons that have nothing to do with
# perfinfo, and would make a passing run here look like a failing one.
cat > "$WORK/bin/fake-sc" <<'FAKE_SC'
#!/QOpenSys/pkgs/bin/bash
op="$1"; svc="$2"
if [ -z "$svc" ]; then
  case "$op" in
    check)  printf '  RUNNING            | svc1 (Svc One) \n' ;;
    list)   printf 'svc1 (Svc One)\n' ;;
    groups) printf 'svc1\n' ;;
  esac
  exit 0
fi
if [ "$op" != perfinfo ]; then
  printf 'STUB-SC %s %s\n' "$op" "$svc"
  exit 0
fi
cat <<'PERF'
Gathering performance information...

---------------------------------------------------------------------
svc1 (Svc One)

Job: 100001/QSYS/JOBA
    Run priority (RUNPTY): 50
    Thread resources affinity (THDRSCAFN):
      Group: *NOGROUP
      Level: *NORMAL
    Resources affinity group (RSCAFNGRP): *NO
    Eligible for purge (PURGE): *YES

Job: 100002/QSYS/JOBB
    Run priority (RUNPTY): 30
    Thread resources affinity (THDRSCAFN):
      Group: *NOGROUP
      Level: *NORMAL
    Resources affinity group (RSCAFNGRP): *NO
    Eligible for purge (PURGE): *NO

---------------------------------------------------------------------
PERF
FAKE_SC
chmod +x "$WORK/bin/fake-sc"

# The affinity lines' exact shape - four spaces, THDRSCAFN's trailing space
# and empty value, six-space Group/Level - is measured live against a real
# two-job service, 19 September 2026 (`cat -A`), not assumed: `grep -c` for
# PERFINFO_AFFINITY_LINES against that capture returns 8 - exactly four per
# job - which is also where "four lines per job", not three, comes from.
#
# The two jobs are given DIFFERENT RUNPTY and PURGE values on purpose - a
# fixture where both jobs read the same would let a job/value MIX-UP through
# unnoticed, which is exactly the class of defect this exists to catch.
#
# fake-scr reads PERFINFO_SCENARIO from its environment:
#   clean   - recorded shape only: no affinity lines, job blocks in the
#             OPPOSITE order to fake-sc's (RMSC sorts, upstream does not),
#             every other field identical. Must classify as "by design".
#   defect  - the same, plus ONE value changed that neither recorded
#             difference explains (job A's RUNPTY: 50 -> 99, a field
#             fidelity-gate.sh's own normalise() deliberately never masks,
#             and a number that appears NOWHERE in the upstream side, so it
#             cannot be mistaken for a swap). Must classify as REGRESSION.
#   swap    - no changed VALUES at all: job A is given job B's real RUNPTY
#             and PURGE, and job B is given job A's - the two jobs' figures
#             swapped between them, line for line the same bag upstream
#             printed. This is the case a whole-file `sort` cannot see
#             (docs/parity.md's own recorded history: "upstream's Java
#             figures sit on the first job and RMSC's on the second") and a
#             per-BLOCK sort can. Must classify as REGRESSION.
#
# clean/defect and clean/swap are each a "must disagree" pair: identical
# scaffolding, one thing different, and the gate is required to answer
# differently about them.
cat > "$WORK/bin/fake-scr" <<'FAKE_SCR'
#!/QOpenSys/pkgs/bin/bash
op="$1"; svc="$2"
if [ -z "$svc" ]; then
  case "$op" in
    check)  printf '  RUNNING            | svc1 (Svc One) \n' ;;
    list)   printf 'svc1 (Svc One)\n' ;;
    groups) printf 'svc1\n' ;;
  esac
  exit 0
fi
case "$op" in
  file|scrunattrs) printf 'STUB-SCR-DIFFERENT %s %s\n' "$op" "$svc"; exit 0 ;;
  check|loginfo|jobinfo|info) printf 'STUB-SC %s %s\n' "$op" "$svc"; exit 0 ;;
esac
runpty_a=50; purge_a='*YES'
runpty_b=30; purge_b='*NO'
case "${PERFINFO_SCENARIO:-clean}" in
  defect) runpty_a=99 ;;
  swap)   runpty_a=30; purge_a='*NO'; runpty_b=50; purge_b='*YES' ;;
esac
cat <<PERF
Gathering performance information...

---------------------------------------------------------------------
svc1 (Svc One)

Job: 100002/QSYS/JOBB
    Run priority (RUNPTY): $runpty_b
    Eligible for purge (PURGE): $purge_b

Job: 100001/QSYS/JOBA
    Run priority (RUNPTY): $runpty_a
    Eligible for purge (PURGE): $purge_a

---------------------------------------------------------------------
PERF
FAKE_SCR
chmod +x "$WORK/bin/fake-scr"

"$WORK/bin/fake-scr" check  > "$WORK/baseline/baseline-check.txt"
"$WORK/bin/fake-scr" list   > "$WORK/baseline/baseline-list.txt"
"$WORK/bin/fake-scr" groups > "$WORK/baseline/baseline-groups.txt"

run_gate() {  # scenario
  PERFINFO_SCENARIO="$1" SC="$WORK/bin/fake-sc" SCR="$WORK/bin/fake-scr" \
    BASELINE="$WORK/baseline" STEP8_SYSTEM=" " WORK="$WORK/run-$1" \
    "$GATE" 2>&1
}

# --- clean: the recorded shape, and nothing else -----------------------
out_clean="$(run_gate clean)"; rc_clean=$?
perf_line_clean="$(printf '%s\n' "$out_clean" | grep -E '^  perfinfo ')"

if [ "$rc_clean" -eq 0 ] && printf '%s' "$perf_line_clean" | grep -q 'by design'; then
  report PASS clean-is-by-design "exit 0, perfinfo: $(printf '%s' "$perf_line_clean" | sed 's/^ *//')"
  pass=$((pass+1))
else
  report FAIL clean-is-by-design "exit $rc_clean, perfinfo line: '$perf_line_clean'"
  printf '%s\n' "$out_clean" | sed 's/^/    /'
  failed=$((failed+1))
fi

# --- defect: the recorded shape, plus one line nothing catalogues -------
out_defect="$(run_gate defect)"; rc_defect=$?
perf_line_defect="$(printf '%s\n' "$out_defect" | grep -E '^  perfinfo ')"

if [ "$rc_defect" -ne 0 ] && printf '%s' "$perf_line_defect" | grep -q 'REGRESSION'; then
  report PASS defect-is-regression "exit $rc_defect, perfinfo: $(printf '%s' "$perf_line_defect" | sed 's/^ *//')"
  pass=$((pass+1))
else
  report FAIL defect-is-regression "exit $rc_defect, perfinfo line: '$perf_line_defect'"
  printf '%s\n' "$out_defect" | sed 's/^/    /'
  failed=$((failed+1))
fi

# --- swap: no changed VALUES, just the two jobs' figures on the wrong job -
out_swap="$(run_gate swap)"; rc_swap=$?
perf_line_swap="$(printf '%s\n' "$out_swap" | grep -E '^  perfinfo ')"

if [ "$rc_swap" -ne 0 ] && printf '%s' "$perf_line_swap" | grep -q 'REGRESSION'; then
  report PASS swap-is-regression "exit $rc_swap, perfinfo: $(printf '%s' "$perf_line_swap" | sed 's/^ *//')"
  pass=$((pass+1))
else
  report FAIL swap-is-regression "exit $rc_swap, perfinfo line: '$perf_line_swap' - a whole-file sort would pass this"
  printf '%s\n' "$out_swap" | sed 's/^/    /'
  failed=$((failed+1))
fi

# --- clean must disagree with EACH of the other two ----------------------
disagree=1
if [ "$rc_clean" = "$rc_defect" ] && [ "$perf_line_clean" = "$perf_line_defect" ]; then
  report FAIL scenarios-disagree "clean and defect gave THE SAME verdict - the check cannot be telling them apart"
  failed=$((failed+1)); disagree=0
fi
if [ "$rc_clean" = "$rc_swap" ] && [ "$perf_line_clean" = "$perf_line_swap" ]; then
  report FAIL scenarios-disagree "clean and swap gave THE SAME verdict - the check cannot be telling them apart"
  failed=$((failed+1)); disagree=0
fi
if [ "$disagree" -eq 1 ]; then
  report PASS scenarios-disagree "clean disagrees with both defect and swap, as it must"
  pass=$((pass+1))
fi

echo
echo "gate-granularity-test: pass=$pass failed=$failed"
echo "artefacts: $WORK"
[ "$failed" -eq 0 ]
