# Parity with upstream `sc`

RMSC is an independent reimplementation, not a fork, and is meant to be a drop-in replacement.
This is the operation-by-operation record of where it matches upstream, where it does not, and
which of those differences are deliberate.

The measurements live in `performance.md`; this file is only about behaviour.

## What parity means here, and where it is absolute

**The default is that output matches upstream.** The scope is "full parity minus cluster mode /
nginx config generation", and Verification step 8 holds every operation to it: *"Differences must
be intentional and listed."* Nothing here licenses an operation to drift. A difference is not
automatically a defect, but it does have to be justified, and the justification belongs in this
file.

`check`, `list` and `groups` all match byte-for-byte today, and the gate holds all three to it.

**`check` is singled out for its failure mode, not because the others may differ.** The plan
states exactly one hard requirement — *"`check` output must be byte-identical"* — because the
consumer screen-scrapes it and drops any row that does not yield three fields. A slip there
raises no error; it makes services disappear from a screen. The contract is
`'  ' + %left(status:18) + ' | ' + name + ' (' + desc + ') '`, `|` at column 22, and colour off
whenever stdout is not a terminal. That is why it alone gets an acceptance gate — Verification
step 5, and Gate 3 → 4 does not open without it — its own unit suite in `SCOUT`, and a diff
re-run at every phase gate since.

`list` and `groups` carry the same expectation at lower stakes. Nothing catastrophic follows if
they drift, but nothing permits it either, and since they already match there is no reason to
hold them to less. What the plan asks of them *additionally* is discovery parity, in
Verification step 9: that `sc list` and `scr list` report the same ~39 services, proving
subdirectory recursion, and that `sc groups` and `scr groups` agree on the group set.

**Step 9's premise was wrong, and has been corrected.** It describes `list -a` as proving
*subdirectory recursion*. Upstream does not recurse: `YamlServiceDefLoader.loadFromDirectory`
skips directories outright — `if (f.isDirectory()) { continue; }` — and reaches the definitions
shipped under `system/` and `oss_common/` by naming those two paths. RMSC recursed generally,
which found definitions upstream cannot see. That is as much a parity defect as missing some, and
the harder one to notice, since nothing looks absent. RMSC now reads each directory flat.

**The gap step 9 points at is real even so.** `sc list -a` and `scr list -a` agree across all 36
services on this system — checked by hand after discovery was corrected — but the gate still
diffs the default `list`, which shows only the three services a default `check` displays. So the
agreement is held by a manual run, not by anything that runs on its own, and it is easy to
mistake the green result for the stronger claim.

For every operation beyond those three, the standard comes from Verification step 8 in the plan:

> Side-by-side diff for the remaining operations against [five services]. **Differences must be
> intentional and listed.**

So a difference is not a defect by itself. An *unexplained* difference is. This file is the list
that step asks for.

## The operations

| Operation | Gated by | State | Difference |
|---|---|---|---|
| `check` | byte-exact vs captured baseline | **pass** | — |
| `list` | byte-exact vs captured baseline | **pass** | — |
| `groups` | byte-exact vs captured baseline | **pass** | — |
| *(colour off when not a TTY)* | assertion | **pass** | — |
| `file` | live differential | **by design** | upstream prints the definition's *path*; RMSC prints its *contents* |
| `scrunattrs` | live differential | **by design** | upstream lists running jobs and their run attributes; RMSC prints the `SCOMMANDER_*` variables it sets |
| `info` | live differential | **undecided** | omits the environment-variables block and the closing separator, adds a `Group:` line, and shows a resolved working directory rather than the raw one |
| `jobinfo` | live differential | **undecided** | upstream prints a header then indented jobs; RMSC prints one `name: job` line each |
| `loginfo` | live differential | **undecided** | one trailing blank line, nothing else |
| `perfinfo` | live differential | **undecided** | substantially narrower — 12 lines against upstream's 66 |
| `start` | not gated | — | state-changing; `SCLIFE.TEST` covers the lifecycle against a service it creates and removes |
| `stop` | not gated | — | as above |
| `kill` | not gated | — | as above |
| `restart` | not gated | — | as above |
| `reload` | n/a | **out of scope** | cluster-only upstream; RMSC rejects it with a clear message rather than faking one |

Nine of the thirteen operations RMSC accepts are gated. Four are undecided, and that is what
keeps Verification step 8 open.

## The gate

`tools/fidelity-gate.sh`, run on the box — a per-command `ssh` round trip turns a full sweep
into minutes.

```bash
scp tools/fidelity-gate.sh $HOST:$DEPLOY/tools/
ssh $HOST "BASELINE=<captures> $DEPLOY/tools/fidelity-gate.sh"
```

`BASELINE` is required and has no default. The captured Java output is not in this repository —
it names a live system's services — so the gate has to be told where it lives. The tracked
`fixtures/` directory is not a substitute: it holds the same layout with invented names,
describing a different machine, and a gate that quietly diffed against it would report a
mismatch that reads like a formatting defect. Unset, the gate says so and exits 2.

Two stages, deliberately different:

- **Byte-exact** — `check`, `list`, `groups`, plus the no-colour assertion, against the captured
  Java baselines. See `performance.md` §2 for how those were captured and what each pins.
- **Live differential** — the remaining read-only operations are run through *both*
  implementations on the spot and compared to each other. Nothing is captured for these: they
  embed job numbers, timestamps and storage counters that differ between two runs seconds apart,
  so a stored fixture would rot almost immediately. Only those values are normalised. Whitespace
  is not — a stray blank line is exactly the class of difference the gate exists to catch, and
  is the whole of the `loginfo` divergence.

The sweep covers five services: the three a default `check` displays, plus two from the `system`
group chosen to reach paths the others never touch — one using the `SBS/JOB` form of
`check_alive`, one using ports only. That second choice is not incidental. It is how the
port-to-job defect was found: every default service carries a job name, so the port-only path
had never run under test.

Verdicts are `by design` (sanctioned below), `undecided` (listed below, awaiting a decision),
`PASS`, or `REGRESSION`. The gate fails when something regresses **and** when something starts
matching without the list being updated, so the classification cannot quietly go stale.

## Differences that are intentional

Both are specified by the plan, in the plan's own words.

**`file` — "Raw YAML passthrough".** The Risks section depends on this behaviour: *"`scr file
<svc>` prints the raw file so the source of truth stays inspectable"*. Printing the path
instead, as upstream does, would remove a documented safeguard against YAML drift.

**`scrunattrs` — "`SCOMMANDER_*` vars from the running job".** That is what RMSC emits. Upstream
reports something different under the same verb; the plan chose this meaning deliberately.

## Differences still undecided

None of these is on the `check` path, so none affects a figure in `performance.md` or the
byte-exact gate. That is also why they went unnoticed until the gate was widened past the three
operations that are.

**`loginfo`** — one trailing blank line. One line of code either way.

**`jobinfo`** — a layout difference only, since the job *set* was corrected. Upstream prints a
header then indented jobs; RMSC prints one `name: job` line each.

**`info`** — the largest of the formatting cases. RMSC omits the `Inherits environment
variables?` and `Custom environment variables:` block and the closing separator, adds a `Group:`
line upstream does not print, and resolves the working directory rather than showing the raw
value. The `Defined in:` path also differs, but harmlessly — both resolve to byte-identical
copies of the same file.

**`perfinfo`** — the only one where the plan looks like it settles the matter and does not. It
calls the operation *"Improved — drops upstream's optional Python 3 + `ibm_db` dependency, since
embedded SQL reads the `ACTIVE_JOB_INFO` performance columns directly"*. That is a decision about
**dependencies**, not about output. Dropping the dependency never required printing less:
`QSYS2.JVM_INFO` and `QSYS2.ACTIVE_JOB_INFO` are both reachable from embedded SQL, and Phase 2
of the plan asked for *"every `QueryUtils` query as embedded SQL"*. Nothing explains twelve lines
where upstream prints sixty-six, so the narrower output is undocumented rather than designed.

## Beyond the operations — RMSC does not narrate

Upstream reports what it is doing while it does it. RMSC is silent. This affects every
**state-changing** operation - `start`, `stop`, `kill`, `restart` - for a single service and for
a group alike; the read-only operations narrate on neither side.

Measured against sc 1.7.1 with one definition, same command both sides:

    $ sc  start rmprog_one          $ scr start rmprog_one
    Performing operation 'START'    (nothing)
      on service 'rmprog_one'

    $ sc  stop rmprog_one           $ scr stop rmprog_one
    Performing operation 'STOP'     (nothing)
      on service 'rmprog_one'
    Service 'Prog one' is
      already stopped

So `scr stop x` succeeds while appearing to do nothing at all.

The family, taken from the message catalogue in `sc.jar` and wider than the two lines above:

| kind | upstream, on stdout |
|---|---|
| progress | `Performing operation '%s' on service '%s'`, and an `(asynchronously)` variant |
| outcome | `Service '%s' successfully started` / `successfully stopped` |
| no-op | `Service '%s' is already running` / `is already stopped` |
| partial | `Service '%s' is already partially running. You may need to restart if this operation fails.` |
| dependency | `Attempting to stop dependent service '%s'...` |
| refusal | `No start command specified for service '%s'`, `ERROR: No running jobs for service '%s'` |

Note which name each uses: the progress line names the service by its **short** name, the status
lines by its **friendly** name. Measured, not inferred.

**This is undecided rather than intentional.** Nothing in the plan asks for silence, and no
reason has been recorded for it - RMSC simply never implemented the narration. It is written down
here because a divergence with no stated reason is the kind this document exists to catch.

The cost of closing it is that these are new lines on **stdout**, which the consumer parses by
column position. They do not yield three fields, so a parser that drops malformed rows is
unaffected - but that is a property of the consumer, not of the output, and is worth confirming
before the lines are added.

## Beyond the operations — specifiers

Two differences the gate cannot currently see, because it only exercises defined services.

**Ad-hoc services are named differently, and this is on the `check` path:**

```
upstream:    RUNNING            | ad_hoc_port_445 (Ad hoc service running at port 445)
RMSC:        RUNNING            | port:445 (ad hoc port 445)
```

The status column and layout match; the name and description do not. `check` is the byte-exact
surface, so this matters more than any of the four above — it simply is not reached by a gate
that runs bare `check` against three defined services.

**`port:N` resolves differently.** Upstream matches the specifier to a *defined* service when
one carries that port as a criterion, and reports it under its real name with all of that
definition's jobs. RMSC always treats `port:N` as ad hoc. The plan lists `port:<n>` as "Ad hoc,
no definition needed" but does not say whether an existing definition should win.

Neither is client-affecting — the client uses short names and `group:` only — but the first is on
the format-critical path.

## Beyond the operations — inputs RMSC does not read

Two more, found while correcting discovery. Neither is reachable from anything the gate runs
today, because both are about what happens *before* an operation starts.

**`scrc` and `SC_OPTIONS`.** Upstream reads options from `/QOpenSys/etc/sc/conf/scrc`, from
`$HOME/.scrc`, and from the `SC_OPTIONS` environment variable, and prepends them to its argument
list. RMSC reads none of the three. Measured against sc 1.7.1, with a bare `list` showing four
services:

| | `sc` | `scr` |
|---|---|---|
| `SC_OPTIONS=-a list` | 36 | 4 |
| `list`, with `--ignore-groups=backend` in `$HOME/.scrc` | 35 | 4 |

The second is worth reading twice: the count goes *up*, because an `--ignore-groups` from a
config file replaces the default `system` exclusion rather than adding to it. So a `.scrc`
nobody remembers writing changes which services a bare `check` shows — and changes it for
upstream only. **Undecided**; the plan does not mention either mechanism.

**`services.dir` — a custom definition directory.** Upstream takes one from the `services.dir`
JVM system property, searched last so it overrides everything else; confirmed on 1.7.1 by
setting it through `JAVA_TOOL_OPTIONS` and watching a definition outside every standard
directory appear in `sc list`. ILE has no system properties, so RMSC reads `SC_SERVICES_DIR`
instead, and honours it the same way. The concept and the search order match; the mechanism
differs because it has to. **By design**, and recorded here because a reader comparing the two
will otherwise find a property with no counterpart.

## Beyond the operations — colour

`check` output is compared with colour off, since colour is suppressed whenever stdout is not a
terminal and every comparison here runs that way. One difference is known to hide there:
upstream wraps a partial service's `[not running at -->…]` suffix in its warning colour, and RMSC
leaves that text uncoloured. The status field itself is coloured by both. **Undecided**, and it
needs a person looking at a terminal rather than a diff — no byte-exact comparison can reach it.

## Beyond the operations — how YAML types a scalar

A criterion's value is rendered by whatever the **YAML reader** made of it, not by anything
either implementation decides afterwards. Upstream's reader follows YAML 1.1, measured against
sc 1.7.1 with `check_alive: port` and the value as `check_alive_criteria`:

| written | renders as | why |
|---|---|---|
| `022` | `PORT:18` | a leading zero means octal |
| `0755` | `PORT:493` | octal again |
| `'022'` | `PORT:022` | quoted, so it stays a string |
| `08080` | `PORT:08080` | invalid octal, so it stays a string |
| `1_000` | `PORT:1000` | YAML 1.1 digit separator |
| `+8080` | `PORT:8080` | typed as an integer, so the sign is gone |

The two ways of writing a criterion also disagree with each other: plain `check_alive: 08080`
renders `PORT:8080`, where the type-and-value form renders `PORT:08080` — the first parses the
string and prints the number, the second prints what the reader produced.

RMSC's `SCYAML` does none of this. It reads a scalar as text, so `check_alive: 022` means port
22 here and port 18 upstream.

**Not being chased, deliberately.** Matching it means implementing YAML 1.1 scalar typing —
octal, digit separators, sign handling — so that a definition reading `022` is understood as 18.
That is a large change to the parser whose entire value is agreeing with upstream about
definitions nobody writes on purpose, and every one of them is a service that would fail to
start either way, since port 18 is not where anybody's service is listening. Recorded here so
the difference is known rather than discovered.

Worth knowing if a definition ever does carry one: quoting the value (`'022'`) makes both
implementations treat it as text, and is the portable way to write it.

## Corrected since this file was written

The ground under several statements above has moved. What changed, so a reader is not comparing
against a state that no longer exists:

- **Discovery.** RMSC read directories recursively and let an *earlier* definition win over a
  later one of the same name — so a global definition beat a user's copy, the opposite of what a
  user directory is for. It now reads flat, in upstream's order, later winning.
- **`--ignore-globals`** was parsed into a field nothing read. Making it work exposed three more
  differences, none of them reachable before: an empty result printed nothing where upstream
  warns on stderr and exits 0; a named empty group raised an error and exited 255; and `groups
  --ignore-globals` listed a built-in `system` group upstream adds only when it read the globals.
- **`-a`** now turns `--ignore-globals` back off where the argument appears, as upstream does.
- **`list group:NAME`** printed nothing at all.
- **`PARTIAL`** printed a bare word where upstream prints `PARTIAL (2/3)` and names the criteria
  that are not running. This one was on the byte-exact `check` path.

All are fixed and match live, on stdout, stderr and exit status. None of them was reachable by
anything that ran, which is the argument for the fixture pack rather than a footnote to it.

## Closing Verification step 8

1. Decide the four undecided operations above: fix to match upstream, or record the reason not
   to, here.
2. Decide the two specifier differences.
3. Widen the gate to exercise `port:` and `job:` specifiers, so the ad-hoc naming difference is
   covered by something that runs rather than by this paragraph.
4. Remove whatever is settled from the gate's `UNDECIDED` list. It will then report step 8
   complete, and fail if any of it silently changes afterwards.

Separately, and not part of step 8: the gate should compare `list -a` across all services, to
hold Verification step 9's discovery parity. The two implementations agree on it today, but the
gate compares the default three, so nothing would catch it if they stopped agreeing.
