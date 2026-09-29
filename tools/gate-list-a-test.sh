#!/QOpenSys/pkgs/bin/bash
#
# gate-list-a-test.sh - proves tools/fidelity-gate.sh's byte-exact stage
# covers `list -a`, not just the default `list`, and covers it BYTE-EXACTLY
# rather than merely set-equally.
#
# docs/parity.md, "Closing Verification step 8": "the gate should compare
# list -a across all services, to hold Verification step 9's discovery
# parity. The two implementations agree on it today, but the gate compares
# the default three, so nothing would catch it if they stopped agreeing."
# The same file elsewhere corrects Verification step 9's own wording: `list
# -a` does not prove subdirectory recursion (upstream does not recurse, and
# RMSC recursing would itself now be a defect) - what it holds is that the
# two sides report the same set of services from the same flat scan.
#
# The default `list` fixture cannot stand in for that: it is three services,
# deliberately small, and says nothing about whether the two sides still
# agree on the FULL set. A regression that drops one service from the full
# listing - the shape a broken or accidentally-bounded directory scan would
# produce - is invisible to a gate that only ever asks for the default three.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh, using the same bash.
# Needs nothing live - no service, no listener, no real sc or scr - because
# what is under test is the GATE'S OWN COVERAGE, not either implementation.
# Same SC/SCR/BASELINE override mechanism tools/gate-granularity-test.sh
# uses, and the same reasoning for using it: the real box's full `list -a` is
# real services this repository must not name (CLAUDE.md, "This repository
# is public"), so the scenario is synthetic and the shape is what is proven,
# not any particular service name.

set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${GATE:-$HERE/fidelity-gate.sh}"
WORK="${WORK:-/tmp/gate-list-a-test.$$}"

# CLEAN UP ON ENTRY AS WELL AS ON EXIT. Every script in tools/ that keeps its
# work directory and names it by PID carries this block - the reasoning is
# written out in full in fidelity-gate.sh, not repeated here. Deliberately
# duplicated rather than shared: change one, change all of them.
ls -dt /tmp/gate-list-a-test.* 2>/dev/null | tail -n +3 | while read -r stale; do
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

# NOT REMOVED ON EXIT - see gate-granularity-test.sh for why: this prints
# "artefacts: $WORK" below, and the entry sweep above is what stops these
# from accumulating rather than a trap here.
mkdir -p "$WORK/bin" "$WORK/baseline"

pass=0; failed=0

report() { printf '  %-9s %-28s %s\n' "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# One fixed default listing ("svc1" only, so stage 1's `list`, `check` and
# `groups` and the no-colour check all pass cleanly on every scenario), the
# DIFF_OPS sweep given exactly the same shape tools/gate-granularity-test.sh
# already calibrated (file/scrunattrs intentionally differ, perfinfo carries
# only its recorded affinity-line/order shape, everything else agrees) so
# that stage 2 stays quiet and out of the way, and one FULL listing that
# differs between the two implementations only by scenario.
#
# fake-sc is never actually called for `list -a`: stage 1 only ever calls
# $SCR against a captured baseline file, the same way it already does for
# `check`/`list`/`groups` - upstream's own `list -a` is baked into
# baseline-list-a.txt below instead, the same relationship the real gate has
# to real captured fixtures. The branch below only guards against "list -a"
# ever reaching the ordinary DIFF_OPS stub, since "list" is not itself a
# DIFF_OPS operation today.
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
if [ "$op" = list ] && [ "$svc" = "-a" ]; then
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

# fake-scr reads GATE_LISTA_SCENARIO from its environment. "clean" is the
# byte-exact match; each other scenario changes exactly ONE thing about it,
# each a different way a byte-exact comparison can be weakened into a
# set-equal one without anyone noticing - the "must disagree" pairing this
# project's CLAUDE.md asks for, times three rather than once:
#
#   clean         list -a matches upstream's full listing exactly.
#   regression    "group_svc" is missing outright - the set itself is wrong,
#                 the shape a broken or accidentally-bounded directory scan
#                 would produce.
#   reorder       the same THREE services, upstream's own set, printed in a
#                 different order. A gate that compared sorted output (or
#                 the SET of lines) would call this identical to clean; a
#                 byte-exact one must not.
#   trailing      clean's own three lines, byte for byte, plus one extra
#                 trailing blank line. The exact class of slip `check`'s own
#                 byte-exact contract exists to catch (docs/parity.md: "a
#                 formatting slip produces an empty-looking screen rather
#                 than an error") - proven measurably reachable here: an
#                 earlier version of this harness compared only clean vs.
#                 regression, and a peer review found a gate weakened to
#                 `cmp <(sort baseline) <(sort actual)` still passed it,
#                 because sorting does not see a trailing blank line either.
cat > "$WORK/bin/fake-scr" <<'FAKE_SCR'
#!/QOpenSys/pkgs/bin/bash
op="$1"; svc="$2"
if [ "$op" = list ] && [ "$svc" = "-a" ]; then
  case "${GATE_LISTA_SCENARIO:-clean}" in
    clean)      printf 'group_svc (Grouped Svc)\nsvc1 (Svc One)\nsvc2 (Svc Two)\n' ;;
    regression) printf 'svc1 (Svc One)\nsvc2 (Svc Two)\n' ;;
    reorder)    printf 'svc1 (Svc One)\nsvc2 (Svc Two)\ngroup_svc (Grouped Svc)\n' ;;
    trailing)   printf 'group_svc (Grouped Svc)\nsvc1 (Svc One)\nsvc2 (Svc Two)\n\n' ;;
  esac
  exit 0
fi
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
cat <<'PERF'
Gathering performance information...

---------------------------------------------------------------------
svc1 (Svc One)

Job: 100002/QSYS/JOBB
    Run priority (RUNPTY): 30
    Eligible for purge (PURGE): *NO

Job: 100001/QSYS/JOBA
    Run priority (RUNPTY): 50
    Eligible for purge (PURGE): *YES

---------------------------------------------------------------------
PERF
FAKE_SCR
chmod +x "$WORK/bin/fake-scr"

# check/list/groups baselines are generated from fake-scr itself, the same
# way tools/gate-granularity-test.sh's are - not hand-written literals that
# could drift from the stub silently and fail this suite for a reason that
# has nothing to do with list -a. baseline-list-a.txt cannot be generated the
# same way: it stands in for upstream's OWN capture, fixed regardless of
# which scenario fake-scr (RMSC's stand-in) is given, so it is the one
# literal that must stay a literal.
"$WORK/bin/fake-scr" check  > "$WORK/baseline/baseline-check.txt"
"$WORK/bin/fake-scr" list   > "$WORK/baseline/baseline-list.txt"
"$WORK/bin/fake-scr" groups > "$WORK/baseline/baseline-groups.txt"
printf 'group_svc (Grouped Svc)\nsvc1 (Svc One)\nsvc2 (Svc Two)\n' > "$WORK/baseline/baseline-list-a.txt"

run_gate() {  # scenario
  GATE_LISTA_SCENARIO="$1" SC="$WORK/bin/fake-sc" SCR="$WORK/bin/fake-scr" \
    BASELINE="$WORK/baseline" STEP8_SYSTEM=" " WORK="$WORK/run-$1" \
    "$GATE" 2>&1
}

lista_line() { printf '%s\n' "$1" | grep -E '^  list-a '; }

# --- clean: RMSC's full listing matches upstream's, byte for byte ----------
out_clean="$(run_gate clean)"; rc_clean=$?
lista_clean="$(lista_line "$out_clean")"

if [ "$rc_clean" -eq 0 ] && printf '%s' "$lista_clean" | grep -q 'PASS'; then
  report PASS clean-is-pass "exit 0, list-a: $(printf '%s' "$lista_clean" | sed 's/^ *//')"
  pass=$((pass+1))
else
  report FAIL clean-is-pass "exit $rc_clean, list-a line: '$lista_clean'"
  printf '%s\n' "$out_clean" | sed 's/^/    /'
  failed=$((failed+1))
fi

# assert_caught NAME SCENARIO DESCRIPTION - runs a scenario expected to FAIL
# the gate's list-a comparison, and records it for the disagree checks below.
declare -A OUT=() RC=() LISTA=()
assert_caught() {
  local name="$1" scenario="$2" desc="$3"
  local out rc line
  out="$(run_gate "$scenario")"; rc=$?
  line="$(lista_line "$out")"
  OUT["$scenario"]="$out"; RC["$scenario"]="$rc"; LISTA["$scenario"]="$line"
  if [ "$rc" -ne 0 ] && [ -n "$line" ] && printf '%s' "$line" | grep -q 'FAIL'; then
    report PASS "$name" "exit $rc, list-a: $(printf '%s' "$line" | sed 's/^ *//')"
    pass=$((pass+1))
  else
    report FAIL "$name" "exit $rc, list-a line: '$line' - $desc"
    printf '%s\n' "$out" | sed 's/^/    /'
    failed=$((failed+1))
  fi
}

# --- regression: one service silently missing from RMSC's `list -a` --------
assert_caught regression-is-caught regression \
  "a gate blind to list -a would say nothing here"

# --- reorder: same set, wrong order -----------------------------------------
assert_caught reorder-is-caught reorder \
  "a gate comparing the SET of services rather than the bytes would miss this"

# --- trailing: clean's own bytes plus one extra trailing blank line --------
assert_caught trailing-is-caught trailing \
  "a gate that trimmed or sorted lines before comparing would miss this"

# --- clean must disagree with each of the other three -----------------------
disagree=1
for scenario in regression reorder trailing; do
  if [ "$rc_clean" = "${RC[$scenario]}" ] && [ "$lista_clean" = "${LISTA[$scenario]}" ]; then
    report FAIL scenarios-disagree "clean and $scenario gave THE SAME verdict - the check cannot be telling them apart"
    failed=$((failed+1)); disagree=0
  fi
done
if [ "$disagree" -eq 1 ]; then
  report PASS scenarios-disagree "clean disagrees with regression, reorder and trailing, as it must"
  pass=$((pass+1))
fi

echo
echo "gate-list-a-test: pass=$pass failed=$failed"
echo "artefacts: $WORK"
[ "$failed" -eq 0 ]
