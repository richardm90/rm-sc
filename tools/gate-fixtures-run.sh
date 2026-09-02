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

mkdir -p "$WORK/services" || exit 2

pass=0; differ=0; setup=0; order_only=0

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
  if [ "$so$se$sr" = "samesamesame" ]; then
    pass=$((pass+1))
  else
    differ=$((differ+1))
    printf '  DIFF %-34s stdout=%-5s stderr=%-5s rc=%s\n' "$desc" "$so" "$se" "$sr"
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
echo "pass=$pass  differ=$differ  (of which ordering-only=$order_only)  known-difference lines filtered=$known_hits"
[ "$order_only" -gt 0 ] && cat <<'NOTE'

A stdout figure of 58/0 means the two agree on every line and disagree only on
their sequence. 58/2 means ordering AND two lines that genuinely differ; only
those two are shown, since the other 56 are the same lines in other places.
RMSC returns definitions in directory-read order; upstream sorts them. That is
one defect, counted once per comparison it spoils, and it will keep spoiling
them until it is fixed.
NOTE
echo "artefacts: $WORK (removed on exit; set WORK= to keep them)"
[ "$differ" -eq 0 ] || exit 1
