#!/QOpenSys/pkgs/bin/bash
#
# gate-fixtures-run.sh - compare the two implementations against definitions
# this repository owns, rather than against whatever happens to be on the box.
#
# tools/fidelity-gate.sh takes its subjects from `scr list`, so its coverage is
# a property of the machine: accidental, unstable, and unable to reach a form
# no real service happens to use. This installs tools/gate-fixtures into a
# directory both implementations read, stages what has to be running, and
# compares them on the same known input.
#
# Nothing on the system is touched. The pack goes in a work directory, is
# reached through SC_SERVICES_DIR (RMSC) and -Dservices.dir (upstream), and
# goes away with the work directory. Listeners are this script's own children,
# bounded, killed on exit.
#
set -o pipefail
export QIBM_MULTI_THREADED=Y

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${DEPLOY:-$(dirname "$HERE")}"
SC="${SC:-/QOpenSys/pkgs/bin/sc}"
SCR="${SCR:-$DEPLOY/scripts/scr}"
PACK="${PACK:-$HERE/gate-fixtures}"
PY="${PY:-/QOpenSys/pkgs/bin/python3}"
WORK="${WORK:-/tmp/gate-fixtures.$$}"

LISTEN_PORTS="55431 55432 55433 55444"
LISTEN_V6="55445"
# Deliberately NOT staged. criteria-comma exists to prove the companion is not
# split on commas, and it can only show that while 55437 and 55438 stay dead.
DEAD_ON_PURPOSE="55437 55438"

pids=""
cleanup() {
  for p in $pids; do kill "$p" 2>/dev/null; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# On the way in as well as out. A run whose ssh session is killed never gets
# to run its trap, and its listeners then hold the ports until their own
# deadline expires - so the next run fails at staging for a reason that has
# nothing to do with the pack. Cleaning up on entry is what makes the harness
# safe to interrupt.
for stale in $(ps -ef 2>/dev/null | grep '[g]ate-listen.py' | awk '{print $2}'); do
  kill "$stale" 2>/dev/null && echo "  cleared a listener left by an earlier run (pid $stale)"
done

# PREFLIGHT, for the same reason tools/fidelity-gate.sh checks BASELINE and
# exits 2 rather than guessing. Without this, a missing or broken `sc` makes
# sc_ return 127 with empty output, EVERY comparison differs with klass=none,
# and the run ends "VERDICT FAILED: fixture-pack" with numbers that read as a
# mass RMSC regression. An environment fault must not be reportable as a
# product defect.
for bin in "$SC" "$SCR"; do
  [ -x "$bin" ] || { echo "PACK CANNOT RUN: $bin is missing or not executable" >&2
                     echo "  This is an environment fault, not a difference." >&2
                     exit 2; }
done

mkdir -p "$WORK/services" || exit 2

# CLASSIFICATION, the same discipline tools/fidelity-gate.sh applies to the
# operations. Until now this harness only COUNTED - "pass=48 differ=6" - and
# whether those were the same six as yesterday was a person reading output.
#
# That is precisely how the conflict-block flap hid: the count moved between 7
# and 8 on identical code for weeks, and nobody could tell because nothing here
# knew what it expected.
#
# So a difference must be on a list, and the check FAILS IN BOTH DIRECTIONS:
#
#     differs + listed      by design / undecided    fine
#     differs + not listed  REGRESSION               fail
#     matches + listed      RECLASSIFY               fail - fix the list
#     matches + not listed  pass                     fine
#
# The second failure is the one that keeps the list honest. Without it a
# difference that gets FIXED leaves a stale entry behind, and the next real
# difference in that case is silently sanctioned by it.
#
# INTENTIONAL is settled by a decision and will not change. UNDECIDED is a
# difference nobody has ruled on yet - it is not sanctioned, it is merely
# known, and the day it is decided its entry moves or goes.
PACK_MIN_COMPARISONS=54

PACK_INTENTIONAL='|isolation:cluster check|isolation:cluster list|'

# Cluster mode is out of scope - Richard, 2 September. Upstream expands a
# cluster: definition into one indented row per backend; RMSC refuses the
# definition and says so on stderr. See docs/parity.md.

PACK_UNDECIDED='|isolation:malformed check|isolation:malformed list|isolation:no-name check|isolation:no-name list|'

# malformed  - both refuse the file; the stderr WORDING differs. Upstream
#              prints the YAML parser's own complaint, RMSC its own. D2.
# no-name    - upstream discards a definition with no `name:` entirely; RMSC
#              keeps it and defaults the description to the short name. A
#              difference in WHICH SERVICES EXIST, not in formatting.

klass_of() {
  case "$PACK_INTENTIONAL" in *"|$1|"*) echo intentional; return ;; esac
  case "$PACK_UNDECIDED"    in *"|$1|"*) echo undecided;   return ;; esac
  echo none
}

pass=0; differ=0; setup=0; order_only=0
bydesign=0; undecided_n=0; unexpected=0; unexpected_list=

# Differences already recorded in docs/parity.md, filtered from BOTH sides so
# they are not reported thirty times over and do not bury what is new. They are
# reported once, at the end, with their count - a filtered difference that
# stops happening is still worth knowing about.
#
#   load warnings   upstream puts them on stderr, RMSC on stdout. Phase D4.
#   unknown keys    upstream warns on stderr every run, RMSC only in `info`.
#
# Nothing else is filtered. In particular whitespace is not, because a stray
# blank line is exactly the class of difference this exists to catch.
known_hits=0
strip_known() {
  before=$(wc -l < "$1")
  grep -vE "^WARNING: Unrecognized attribute |^Invalid configuration for service |^WARNING: Ignoring file due to load errors: |^WARNING: [a-z0-9_-]+: Service .* has no start_cmd" "$1" > "$1.k" 2>/dev/null
  after=$(wc -l < "$1.k")
  [ "$before" -ne "$after" ] && known_hits=$((known_hits + before - after))
  mv "$1.k" "$1"
}

# A conflict-warning block is a SET, and comparing it as a sequence made this
# harness report two different answers on identical code. Measured: three runs
# of the same build gave differ=7, differ=8, differ=7, with two cases flapping
# in and out - `list -a` and `isolation:duplicate-criterion-job list` - each
# showing the same shape, one member moving between position 2 and 3:
#
#     2d1
#     <     system_sshd (System Secure Shell server)
#     3a3
#     >     system_sshd (System Secure Shell server)
#
# Same lines, different order. Upstream builds the block from a hash and its
# member order is not stable even against ITSELF between consecutive runs;
# `7791266` measured that and RMSC deliberately sorts, because a set is the
# only part of it that can be asserted. A two-member block is then a coin toss,
# which is exactly the flap rate seen.
#
# So the members under each header are sorted on both sides before comparing.
# NOTHING IS LOST by that: there is no correct order to detect a departure
# from. What WOULD be lost by leaving it alone is the harness's credibility -
# a differ count that changes on identical input cannot support a claim about
# either implementation, and it is why the pack cannot be wired into the gate,
# which exits non-zero on any difference at all.
#
# Only the indented run directly under a header is touched. The blocks
# themselves keep their positions: whether their ORDER also varies has not been
# measured, and inventing a rule for it before seeing it happen is how a
# harness comes to hide the thing it was built to find. If it does vary, the
# stability runs will say so.
#
# The count is reported for the same reason known_hits is: normalisation that
# silently stops firing - because conflict detection broke, or the wording
# moved - would leave this looking like it still guards something.
CONFLICT_HDR='WARNING: the following services all have conflicting definitions for liveliness check '
conflict_blocks=0
sort_conflict_members() {
  grep -qF "$CONFLICT_HDR" "$1" || return 0
  local out="$1.c" buf="$1.b" inblock=0
  : > "$out"; : > "$buf"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$inblock" = 1 ]; then
      case "$line" in
        [[:space:]]*) printf '%s\n' "$line" >> "$buf"; continue;;
        *) sort "$buf" >> "$out"; : > "$buf"; inblock=0;;
      esac
    fi
    printf '%s\n' "$line" >> "$out"
    case "$line" in
      "$CONFLICT_HDR"*) inblock=1; conflict_blocks=$((conflict_blocks+1));;
    esac
  done < "$1"
  [ "$inblock" = 1 ] && sort "$buf" >> "$out"
  mv "$out" "$1"; rm -f "$buf"
}

# Upstream announces JAVA_TOOL_OPTIONS on stderr, which would otherwise look
# like output from the command under test.
sc_() { JAVA_TOOL_OPTIONS="-Dservices.dir=$WORK/services" "$SC" "$@" 2>"$WORK/j.e.raw"; jrc=$?
        grep -v 'Picked up' "$WORK/j.e.raw" > "$WORK/j.e"; return $jrc; }
scr_() { SC_SERVICES_DIR="$WORK/services" "$SCR" "$@" 2>"$WORK/r.e"; }

compare() {
  desc="$1"; shift
  sc_  "$@" >"$WORK/j.o"; jrc=$?
  scr_ "$@" >"$WORK/r.o"; rrc=$?
  for f in "$WORK/j.o" "$WORK/j.e" "$WORK/r.o" "$WORK/r.e"; do strip_known "$f"; done
  # stderr only. If RMSC ever put a conflict block on stdout - the stream a
  # consumer parses by column - that is a difference this must still report,
  # not one it tidies away.
  for f in "$WORK/j.e" "$WORK/r.e"; do sort_conflict_members "$f"; done
  so=same; se=same; sr=same
  cmp -s "$WORK/j.o" "$WORK/r.o" || so=DIFF
  cmp -s "$WORK/j.e" "$WORK/r.e" || se=DIFF
  [ "$jrc" = "$rrc" ] || sr="sc=$jrc scr=$rrc"
  # Ordering is reported apart from content. RMSC does not sort its service
  # list and upstream does, so while that stands EVERY multi-service
  # comparison differs - and a real content difference underneath would never
  # be seen. Sorting both sides says whether ordering is the whole of it.
  # This is a diagnostic, not a licence: an ordering difference is a real
  # difference and is counted as one.
  # Reported as <lines differing as-is>/<lines differing once both are sorted>.
  # 58/0 is ordering alone. 58/2 is ordering plus two lines that really differ,
  # and those two are what to look at. 2/2 has nothing to do with ordering.
  # A single content difference is enough to stop a sorted comparison matching,
  # so a plain yes/no on ordering reports nothing useful once anything else is
  # wrong - which is exactly the state this pack is in.
  if [ "$so" = DIFF ]; then
    sort "$WORK/j.o" > "$WORK/j.s"; sort "$WORK/r.o" > "$WORK/r.s"
    raw=$(diff "$WORK/j.o" "$WORK/r.o" | grep -c '^[<>]')
    srt=$(diff "$WORK/j.s" "$WORK/r.s" | grep -c '^[<>]')
    so="$raw/$srt"
    [ "$srt" = 0 ] && order_only=$((order_only+1))
  fi
  klass=$(klass_of "$desc")

  if [ "$so$se$sr" = "samesamesame" ]; then
    if [ "$klass" = none ]; then
      pass=$((pass+1))
    else
      # It used to differ and now does not. The entry is stale, and a stale
      # entry sanctions the NEXT difference in this case without anyone
      # deciding to.
      printf '  %-34s RECLASSIFY  now matches - remove it from the %s list\n' \
             "$desc" "$klass"
      unexpected=$((unexpected+1)); unexpected_list+=("RECLASSIFY  $desc")
    fi
  else
    differ=$((differ+1))
    case "$klass" in
      intentional) bydesign=$((bydesign+1)) ;;
      undecided)   undecided_n=$((undecided_n+1)) ;;
      none)        unexpected=$((unexpected+1)); unexpected_list+=("NEW         $desc") ;;
    esac
    printf '  %-4s %-34s stdout=%-5s stderr=%-5s rc=%s\n' \
           "$(case $klass in intentional) echo 'by-d';; undecided) echo 'undc';; *) echo 'NEW!';; esac)" \
           "$desc" "$so" "$se" "$sr"
    if [ "$so" != same ] && [ "${so#*/}" != 0 ]; then
      diff "$WORK/j.s" "$WORK/r.s" | grep '^[<>]' | head -4 | sed 's/^/         /'
    fi
    [ "$se" = DIFF ] && diff "$WORK/j.e" "$WORK/r.e" | head -4 | sed 's/^/         /'
  fi
}

# The pack checks itself before anything is compared: a fixture that cannot
# load, or two that collide, would otherwise produce a difference that looks
# like a defect in the thing under test.
if [ -f "$PACK/check-pack.py" ]; then
  echo "== pack self-check"
  if "$PY" "$PACK/check-pack.py" 2>&1 | sed 's/^/  /'; then :; else
    echo "  the pack is not sound; not comparing anything"
    exit 2
  fi
  echo
fi

echo "== staging"
for p in $DEAD_ON_PURPOSE; do
  if $PY -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',$p)) else 1)"; then :; else
    echo "  SETUP FAILED: port $p must stay dead - criteria-comma cannot detect anything while it answers"
    setup=$((setup+1))
  fi
done
$PY "$HERE/gate-listen.py" --seconds 2400 $LISTEN_PORTS >"$WORK/l.out" 2>"$WORK/l.err" &
pids="$pids $!"
$PY "$HERE/gate-listen.py" --seconds 2400 --v6only $LISTEN_V6 >"$WORK/l6.out" 2>"$WORK/l6.err" &
pids="$pids $!"
for f in "$WORK/l.out" "$WORK/l6.out"; do
  for _ in $(seq 1 60); do grep -q READY "$f" 2>/dev/null && break; sleep 0.25; done
  grep -q READY "$f" || { echo "  SETUP FAILED: listener never ready - $(cat "${f%.out}.err" | head -2)"; setup=$((setup+1)); }
done
[ "$setup" -ne 0 ] && { echo "staging failed; not comparing anything"; exit 2; }
echo "  listeners up on $LISTEN_PORTS and $LISTEN_V6 (IPv6-only); $DEAD_ON_PURPOSE confirmed dead"

# Copied in REVERSE alphabetical order, deliberately. Directory order follows
# creation order here, so copying alphabetically would make read order and
# sorted order coincide - and the pack's finding that RMSC does not sort would
# hide itself, which is how it stayed hidden on this machine in the first place.
install_base() {
  ( cd "$PACK/base" && ls | sort -r ) | while read -r f; do
      cp -r "$PACK/base/$f" "$WORK/services/"
    done
}
install_base || exit 2
echo "  $(find "$WORK/services" -maxdepth 1 -type f | wc -l) definition files installed, newest-first"

echo
echo "== base pack, whole-collection"
compare "check"  check  --ignore-globals
compare "list"   list   --ignore-globals
compare "groups" groups --ignore-globals
compare "list -a" list -a

echo
echo "== base pack, one service at a time"
for name in $(scr_ list --ignore-globals | grep -v "^WARNING:" | awk 'NF{print $1}'); do
  compare "check $name" check "$name" --ignore-globals
done

echo
echo "== isolation cases"
for case_dir in "$PACK"/isolation/*/; do
  name=$(basename "$case_dir")
  rm -rf "$WORK/services"; mkdir -p "$WORK/services"
  install_base
  cp -r "$case_dir". "$WORK/services/" 2>/dev/null
  compare "isolation:$name check" check --ignore-globals
  compare "isolation:$name list"  list  --ignore-globals
done

echo
# The subject list comes from `scr list`, so a definition that stops loading
# takes its comparison away rather than failing one. Nothing else notices - the
# counts simply get smaller - and this stage now makes an affirmative claim, so
# a shrinking subject list must contradict it.
total=$((pass + differ))
if [ "$total" -lt "$PACK_MIN_COMPARISONS" ]; then
  echo "PACK FAILED: only $total comparisons ran, expected at least $PACK_MIN_COMPARISONS."
  echo "             A fixture stopped loading, so its comparison vanished rather"
  echo "             than failing. That is a defect wearing a smaller number."
  unexpected=$((unexpected+1))
fi

echo "pass=$pass  by design=$bydesign  undecided=$undecided_n  unexpected=$unexpected"
echo "differ=$differ  (of which ordering-only=$order_only)  known-difference lines filtered=$known_hits  conflict blocks set-compared=$conflict_blocks"
[ "$conflict_blocks" -eq 0 ] && echo "NOTE: no conflict block was seen at all - either the fixtures stopped colliding or the warning's wording moved. The set comparison guarded nothing this run."
[ "$order_only" -gt 0 ] && cat <<'NOTE'

A stdout figure of 58/0 means the two agree on every line and disagree only on
their sequence. 58/2 means ordering AND two lines that genuinely differ; only
those two are shown, since the other 56 are the same lines in other places.
RMSC returns definitions in directory-read order; upstream sorts them. That is
one defect, counted once per comparison it spoils, and it will keep spoiling
them until it is fixed.
NOTE
echo "artefacts: $WORK (removed on exit; set WORK= to keep them)"

# EXIT ON `unexpected`, NOT ON `differ`. Six differences are recorded and
# expected; failing on their existence made this harness permanently red, which
# is why verify.sh had to carry it as advisory and why nobody could use its
# status for anything.
#
# Now a green run means "every COMPARISON that differs is one we know about,
# and every one we know about still differs" - the statement the operation gate
# has made all along.
#
# NOTE THE GRANULARITY, because the obvious reading is stronger than the truth.
# Classification is per comparison, and an isolation case compares the whole
# base collection alongside its own fixture. So once a case is listed, a
# difference arising in it for some OTHER reason is folded into the sanctioned
# one and reported green - a defect visible only when a load warning is
# present, say, would hide inside `isolation:malformed check`.
#
# Closing that needs the expected DIFF pinned per listed case, not just the
# case name. Worth doing; not done here, and written down so the claim above is
# not read as more than it is.
if [ "$unexpected" -ne 0 ]; then
  echo "PACK FAILED: $unexpected difference(s) neither sanctioned nor recorded,"
  echo "             or recorded and no longer happening. Both need the list changing."
  # NAMED HERE, not only beside the comparison hundreds of lines above. This
  # stage now decides the run, and verify.sh shows its last few lines - so a
  # failure that does not say WHICH case moved costs a 40-minute re-run to find
  # out. A red result has to be actionable from the log.
  for u in "${unexpected_list[@]}"; do echo "             $u"; done
  exit 1
fi
echo "PACK OK: $bydesign by design, $undecided_n undecided, nothing unexpected"
