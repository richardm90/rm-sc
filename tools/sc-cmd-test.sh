#!/QOpenSys/pkgs/bin/bash
#
# sc-cmd-test.sh - the native `SC` *CMD (QCMDSRC/SC.CMD, CPP SCCMD.PGM.RPGLE),
# the one entry point into RMSC nothing else in this repository ever drives.
# Every other harness here goes through `scr`, the PASE wrapper - a coverage
# audit (30 September 2026) found this was true without exception: zero live
# coverage, zero RPGUnit coverage, for the only interface a genuine green-
# screen/CL caller would ever use.
#
# Runs ON the IBM i box, beside tools/fidelity-gate.sh and the other harnesses.
#
# WHAT "MATCHES" MEANS HERE. There is no upstream native CL command to diff
# against - `SC.CMD` is RMSC's own addition, described in local/plan.md as "a
# *CMD in the rmtools style", not a reproduction of anything Java `sc` has.
# So the question this file asks is not fidelity to upstream, it is internal
# consistency: `SCCMD.PGM.RPGLE`'s own header states the design plainly -
# "Assembles the same command line SCRUN takes from the shell, so both routes
# go through one parser rather than two that could drift apart." This file
# measures whether that is actually true, case by case, against `scr` - the
# already-proven path - as the reference.
#
# WHY THIS NEEDS ITS OWN INVOCATION MACHINERY, not tools/*.sh's usual
# `"$SCR" ...` / `"$SC" ...` pattern. `SC` is a native *CMD; there is no PASE
# binary to exec. It runs through `qsh`'s own `system` built-in (each
# `system` sub-call is its OWN job, and library-list state does not survive
# between them or into a plain PASE `system -kpieO "SC ..."` - measured live,
# not assumed - so every case sets its library list AND runs the command in
# ONE qsh -c block).
#
# NOT AN EBCDIC QUESTION, DESPITE HOW IT LOOKS AT FIRST. A native job's
# stdout IS EBCDIC, and redirecting it with `>` INSIDE the qsh command string
# (`qsh -c "system 'SC ...' > file"`) captures exactly that - confirmed live,
# and decoding it needs the job's own CCSID (this box: DFTCCSID 1146, for
# which this iconv build's nearest table is IBM-285; iconv has no IBM-1146
# and the two tables agree on everything but currency symbols, which nothing
# RMSC prints). But that is NOT what this file does. Redirecting the OUTER
# `qsh -c "..."` call instead (`qsh -c "system 'SC ...'" > file`) captures
# what qsh itself writes to ITS OWN stdout, already translated to the calling
# shell's encoding as qsh echoes the native job's output through - confirmed
# live to match `scr`'s own ASCII/UTF-8 output byte for byte, no decoding
# step needed or wanted. Recorded at this length because the wrong form was
# built first, passed nothing, and every failure traced to one thing: iconv
# decoding text that was never encoded to begin with.
#
# WHY THE CPD000D THREAD-SAFETY DIAGNOSTIC PLAYS NO PART HERE. Invoking `SC`
# by fully qualifying it (`RMSC/SC ...`) from a plain PASE `system()` call -
# a job PASE itself flags as multithreaded - draws
# "CPD000D: Command RMSC/SC not safe for a multithreaded job" onto stdout,
# even with stderr redirected separately. `scr` never hits this: it CALLs
# `SCRUN`, a *PGM, and never invokes `SC` as a *CMD at all - so no real RMSC
# caller reaches this path today. Measured live (30 September 2026) that the
# qsh route used throughout this file - liblist set, `SC` invoked unqualified,
# same as a real native/CL caller with RMSC on their library list would type
# it - does not draw it. Recorded here rather than chased further: worth
# knowing if `SC.CMD` is ever invoked some OTHER way, not a defect in what
# this file measures.
#
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
WORK="${WORK:-/tmp/rmsc-sc-cmd.$$}"

ls -dt /tmp/rmsc-sc-cmd.* 2>/dev/null | tail -n +3 | while read -r stale; do
  owner="${stale##*.}"
  case "$owner" in ''|*[!0-9]*) continue ;; esac
  if kill_err=$(kill -0 "$owner" 2>&1); then continue; fi
  case "$kill_err" in *ermitted*|*EPERM*|*ermission*) continue ;; esac
  rm -rf "$stale" 2>/dev/null
done

setup_fail() { printf '%s\n' "$@" >&2; exit 2; }

[ -x "$SCR" ] || setup_fail \
  "scr is not executable at: $SCR" \
  "" \
  "scr is the reference this file measures SC *CMD against, and this script" \
  "must run ON the IBM i box, from the deploy directory."

command -v qsh >/dev/null 2>&1 || setup_fail \
  "qsh not found on PATH" \
  "" \
  "SC is a native *CMD - qsh's own 'system' built-in, not a PASE exec, is how" \
  "this file reaches it. See this script's own header for why."

RMSC_LIB="${RMSC_LIB:-RMSC}"
RMSCT_LIB="${RMSCT_LIB:-RMSCT}"
RMTOOLS_LIB="${RMTOOLS_LIB:-RMTOOLS}"

CHK="$(qsh -c "liblist -a $RMSC_LIB; system 'CHKOBJ OBJ($RMSC_LIB/SC) OBJTYPE(*CMD)'" 2>&1)"
echo "$CHK" | grep -q 'CPF9801\|not found' && setup_fail \
  "RMSC/SC (*CMD) not found" \
  "" \
  "$CHK" \
  "" \
  "Build first (makei build) or check RMSC_LIB=$RMSC_LIB is right."

mkdir -p "$WORK" || setup_fail "cannot create work directory $WORK"

pass=0; failed=0

report() {
  local verdict="$1" tag="$2"; shift 2
  printf '  %-9s %-28s %s\n' "$verdict" "$tag" "$*"
}
detail() { printf '  %-9s %-28s   - %s\n' "" "" "$*"; }
heading() {
  printf '  %-9s %-28s %s\n' verdict case detail
  printf '  %-9s %-28s %s\n' --------- ---------------------------- ------
}

# Runs SC through qsh, library list set fresh in the SAME block (see header),
# and reports the qsh job's own exit status - which, for a native CL failure,
# reflects whether SCCMD's throw() escaped. The OUTER redirect (qsh's own
# stdout, not a `>` done inside the command string) is what makes this
# already plain ASCII/UTF-8 - see NOT AN EBCDIC QUESTION above.
sc_native() {  # cmd -> writes $WORK/native.out, $WORK/native.err, sets $NATIVE_RC
  local cmd="$1"
  qsh -c "liblist -a $RMSC_LIB; liblist -a $RMSCT_LIB; liblist -a $RMTOOLS_LIB; system '$cmd'" \
    >"$WORK/native.out" 2>"$WORK/native.err"
  NATIVE_RC=$?
}

# qsh echoes CPC2206 (QTEMP object ownership) chatter and, on a genuine CL
# escape, an extra CPF-prefixed copy of the message and its own diagnostics -
# none of it part of either implementation's real output. Strip lines that
# are qsh/OS noise, not RMSC's, before comparing.
strip_qsh_noise() {
  grep -vE '^(CPC2206|CPI2128|CPD0170|CPD4090): ' "$1"
}

compare_case() {  # tag native_cmd scr_args...
  local tag="$1" native_cmd="$2"; shift 2
  sc_native "$native_cmd"
  strip_qsh_noise "$WORK/native.out" > "$WORK/native.clean.out"
  "$SCR" "$@" > "$WORK/scr.out" 2> "$WORK/scr.err"
  # cmp -s, not diff -q: this box's PASE diff has no -q (confirmed live -
  # "illegal option -- q", exit 2, indistinguishable from a real mismatch
  # unless you go looking - which is exactly what every case in the first
  # version of this file did, uniformly and silently wrong).
  if cmp -s "$WORK/native.clean.out" "$WORK/scr.out"; then
    report PASS "$tag" "MEASURED - SC *CMD's output matches scr's, byte for byte"
    pass=$((pass+1))
  else
    report FAIL "$tag" "diff in $WORK/$tag.diff"
    diff "$WORK/native.clean.out" "$WORK/scr.out" > "$WORK/$tag.diff" 2>&1
    failed=$((failed+1))
  fi
}

echo "== stage 1: the seven read-only operations, against a real service"
echo
heading
compare_case check-mapepire      "SC OPTION(*CHECK) SERVICE(mapepire)"    check mapepire
compare_case info-mapepire       "SC OPTION(*INFO) SERVICE(mapepire)"     info mapepire
compare_case file-mapepire       "SC OPTION(*FILE) SERVICE(mapepire)"     file mapepire
compare_case loginfo-mapepire    "SC OPTION(*LOGINFO) SERVICE(mapepire)"  loginfo mapepire
compare_case jobinfo-mapepire    "SC OPTION(*JOBINFO) SERVICE(mapepire)"  jobinfo mapepire
compare_case scrunattrs-mapepire "SC OPTION(*SCRUNATTRS) SERVICE(mapepire)" scrunattrs mapepire
# perfinfo excluded deliberately - "The job order" (docs/parity.md) already
# established job-block order is Java HashSet iteration on the OTHER
# implementation, unreproducible and irrelevant here since this compares
# RMSC's two entry points against each other, not against Java. RMSC's own
# order is a defined, stable sort (ascending job number) on BOTH paths, so a
# perfinfo case here would be redundant with jobinfo/scrunattrs above, not a
# new question.

echo
echo "== stage 2: the special-value translations (ALL, IGNGRP, COLOURS)"
echo
compare_case list-all        "SC OPTION(*LIST) ALL(*YES)"                     list -a
compare_case check-all       "SC OPTION(*CHECK) ALL(*YES)"                    check -a
compare_case groups-plain    "SC OPTION(*GROUPS)"                             groups
compare_case ignore-groups   "SC OPTION(*CHECK) IGNGRP(oss_common)"           check --ignore-groups=oss_common
compare_case colours-check   "SC OPTION(*CHECK) SERVICE(mapepire) COLOURS(*YES)" --colors check mapepire

echo
echo "== stage 3: SERVICE(*NONE), the special value meaning 'all services'"
echo
compare_case check-no-service "SC OPTION(*CHECK)" check

echo
echo "== stage 4: does throw() actually escape, the one thing unique to this entry point"
echo
heading
# Both measured live (30 September 2026): SCMAIN's own error text is
# identical either route (SCCMD's throw() only adds its own 'sc: ' prefix,
# the same way scr's shell side never adds one) - what is asserted here is
# narrower and SCCMD-specific: does a CL caller actually see a failure. A CL
# program has no exit status to read (SCCMD's own header comment) - MONMSG is
# the interface, which from qsh surfaces as a non-zero job exit, checked here
# rather than message text already covered by tools/error-delivery-test.sh
# for the PASE side.
sc_native "SC OPTION(*CHECK) SERVICE(nosuchservice_rmsc_sc_cmd_test)"
if [ "$NATIVE_RC" -ne 0 ] && grep -q 'CPF9897' "$WORK/native.out" "$WORK/native.err" 2>/dev/null; then
  report PASS unknown-service-escapes "MEASURED - throw() escapes on an unknown service, MONMSG can catch it"
  pass=$((pass+1))
else
  report FAIL unknown-service-escapes "job exit was $NATIVE_RC, wanted non-zero with CPF9897 - see $WORK/native.*"
  failed=$((failed+1))
fi

sc_native "SC OPTION(*INFO)"
if [ "$NATIVE_RC" -ne 0 ] && grep -q 'CPF9897' "$WORK/native.out" "$WORK/native.err" 2>/dev/null; then
  report PASS info-no-service-escapes "MEASURED - throw() escapes when a required service is missing"
  pass=$((pass+1))
else
  report FAIL info-no-service-escapes "job exit was $NATIVE_RC, wanted non-zero with CPF9897 - see $WORK/native.*"
  failed=$((failed+1))
fi

echo
echo "pass=$pass   failed=$failed"
echo "artefacts: $WORK   (native.*/scr.* per case; KEEP=1 to keep them)"
[ -n "${KEEP:-}" ] || rm -rf "$WORK"

# ---------------------------------------------------------------------------
# WHAT THIS CANNOT ASSERT
#
#   start/stop/restart/kill. Excluded for the same reason
#   tools/fidelity-gate.sh excludes them from its own sweep: a suite that
#   takes services down on whatever machine it runs on is not worth having.
#   Their translation (OPTION *START etc. -> the bare word) is not a new
#   question either - it is the same one-character substring operation as
#   every case above, on values RMSC's own SCMAIN.TEST.RPGLE already covers
#   for the string form.
#
#   .scrc / SC_OPTIONS. Deliberately not read by this path at all -
#   docs/parity.md records the decision. Nothing to test here.
#
#   COLOURS(*YES)'s actual ANSI escapes. compare_case's colours-check case
#   asserts SC.CMD's COLOURS(*YES) reaches the SAME code path scr's own
#   explicit --colors argument does (both bypass TTY detection, which is
#   scr's shell-side decision - see scripts/scr's own header comment - not
#   something COLOURS(*YES) or --colors as a typed argument ever consult).
#   Whether the escape codes THEMSELVES are correct is tools/colour-test.sh's
#   question, not this file's.
# ---------------------------------------------------------------------------

if [ "$failed" -ne 0 ]; then
  echo "FAILED: SC *CMD does not agree with scr the way it is designed to"
  exit 1
fi
