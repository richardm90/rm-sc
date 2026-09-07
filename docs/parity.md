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
| `reload` | n/a | **out of scope** | cluster-only upstream. RMSC does not recognise the verb at all — see below |

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

The first two are specified by the plan, in the plan's own words. The third was decided by
Richard on 5 September 2026 and is the only one here that is not.

**`file` — "Raw YAML passthrough".** The Risks section depends on this behaviour: *"`scr file
<svc>` prints the raw file so the source of truth stays inspectable"*. Printing the path
instead, as upstream does, would remove a documented safeguard against YAML drift.

**`scrunattrs` — "`SCOMMANDER_*` vars from the running job".** That is what RMSC emits. Upstream
reports something different under the same verb; the plan chose this meaning deliberately.

**An out-of-range wait time invalidates the definition; upstream silently wraps it.**
`startup_wait_time` and `stop_wait_time` outside a 32-bit signed integer are refused by RMSC, and
the service does not load. Upstream parses as a long and casts to int, so the value survives as
something else entirely. Measured, 5 September 2026:

| value | upstream | RMSC |
|---|---|---|
| `2147483647` | 2147483647 | 2147483647 — agree |
| `2147483648` | **-2147483648** | definition refused |
| `4294967296` | **0** | definition refused |
| `99999999999999` | **276447231** | definition refused |
| `-2147483648` | -2147483648 | -2147483648 — agree |
| `-2147483649` | **2147483647** (wraps, sign flips) | definition refused |
| `-99999999999999` | **-276447231** | definition refused |
| `abc` | definition refused | definition refused — agree |
| `-5`, `0`, `30` | as written | as written — agree |

Upstream wraps symmetrically at both ends, so the divergence is one rule and not two.

**Richard's decision, and the reasoning, because the reasoning is the part that generalises:**

> A definition that is not valid should not be listed to stdout. That model already exists. It
> does get reported, via stderr rather than stdout. That is different to `sc` in this case, but
> `sc` is just wrong here.

So this is **not an exception carved out for one attribute** — it is an instance of a rule RMSC
already applies. A definition with no `start_cmd`, no `check_alive`, malformed YAML, `cluster:`,
or too many criteria is refused and reported on stderr today. An unusable wait time joins them.
Carving out an exception would be the departure, not this.

Nobody writes `4294967296` on purpose, so it is a mistake. Upstream turning it into a
**zero-second** startup wait is the concrete harm: `start` gives up immediately on a service that
was coming up fine, and the operator debugs a phantom startup failure instead of reading a
message that names the attribute.

**What is genuinely different here, stated so nobody has to rediscover it.** For every OTHER
rejection cause, upstream refuses too — both implementations lose the row together and a consumer
moving between them sees the same thing. An out-of-range wait time is the ONE input for which
RMSC drops a service that `sc` keeps. It leaves `check`, `list` and `groups` alike, and the
warning is on a stream a screen-scraping consumer does not read.

Neighbouring definitions in the same directory are unaffected — measured on both sides.

Two things about it are *not* divergences and should not be "fixed" into one:

- **`abc` is parity.** Upstream refuses it too, with the same exit status per operation — `info`
  and `check` on the named service exit 253, `list` exits 0 and simply drops it. RMSC matches on
  all three. RMSC used to substitute the default here, justified in a code comment by a premise
  nobody had measured.
- **Negative values inside the range are accepted**, by both. RMSC used to substitute the default
  for every negative wait time, because its digit scan started at the sign; that was a
  pre-existing divergence and this change closes it.

**A YAML scalar longer than 1024 characters invalidates the definition; upstream has no limit.**
Same rule and same reasoning as the wait time above — RMSC refuses what it cannot represent
rather than quietly using a wrong value. Measured, 5 September 2026, `start_cmd`:

| length | upstream | RMSC |
|---|---|---|
| 1023 | loads | loads — agree |
| 1024 | loads | loads — agree |
| 1025 | loads | **refused**: `Value for 'start_cmd' at line 3 is longer than 1024 characters` |
| 1031 | loads | refused |

Upstream is Java and its strings are unbounded, so it has no equivalent limit and never will.

**Why this one is worth more than it looks.** Until today the excess was silently cut, and for
`start_cmd` that meant RMSC **ran a command nobody wrote**. Nothing detected it: the definition
loaded, the service listed, the count of criteria was right, and a truncated command line is
often still a valid one. The only symptom would have been a service doing something subtly
different from what its file says.

It was found by a test fixture tripping over this cap while aiming at a different one — the
fifth in a chain where each was invisible until the one above it was widened (`info`'s 10, the
rendering's 56, the storage's 64, the check row's 1024, and this).

Both paths that can exceed the width are guarded — `key: value` and a block sequence item — and
the message names the key and the line, because a file may carry several long values and the
excess is by definition invisible in the loaded value.

**Four more things RMSC refuses that upstream accepts.** All measured 6 September 2026, all
instances of the same rule — RMSC refuses what it cannot represent rather than quietly doing
something different from what was asked — and all recorded here because the gate is documented to
fail when behaviour changes without this list moving.

| input | upstream | RMSC |
|---|---|---|
| `sbmjob_jobname` longer than 10 | keeps all 20 and lets `SBMJOB` reject it at start time | **definition refused** |
| `--ignore-groups=` value over 512 characters | no limit | **usage error, exit 255** |
| `--sampletime=` value over 512 characters | no limit | **usage error, exit 255** |
| a YAML key over 128 characters | warns `Unrecognized attribute` and loads | recorded as an unrecognised attribute under its first 128 characters; **the service still loads** |

The first three cost a row: a refused definition has no line in `check`, and the two option
errors stop the command. That is the cost this project accepts knowingly — see the wait-time
entry above for the reasoning, which is Richard's and applies unchanged.

**Why `sbmjob_jobname` is a refusal rather than a widening**, since it is the odd one out: ten is
a real external limit, an IBM i job name, not an arbitrary holder width. A longer value is
*invalid*, not merely long. What it did before was worse than either — a 1024-wide scalar into a
10-wide field, so `sbmjob_jobname: THISNAMEISWAYTOOLONG` submitted the job as `THISNAMEIS`, a
name the author never wrote. The **derived** name, used when the key is absent, still truncates
to ten on purpose: the author did not choose it, so cutting it to fit is reasonable.

**The fourth is the one that changed direction after review.** A long key first refused the whole
definition, which made a service vanish where upstream lists it. It is now recorded as an
unrecognised attribute — the service loads, the typo is still reported, and RMSC matches
upstream. Refusing was over-reach.

**And one parity defect fixed rather than added:** `--ignore-groups=` with an EMPTY value clears
the default `system` exclusion upstream — measured, 36 rows against 4 for a bare `list`. RMSC
rejected it outright with `Unknown option --ignore-groups=`, because the parse tested for a value
*longer* than the option name and the empty form is exactly its length. Now accepted, and the two
agree.

## Differences still undecided

The exact texts, and what is measured versus merely captured, are in **`docs/messages.md`** — the
D2 catalogue. This section says which differences exist and why they are still open; that one says
what upstream's bytes actually are.

None of these is on the `check` path, so none affects a figure in `performance.md` or the
byte-exact gate. That is also why they went unnoticed until the gate was widened past the three
operations that are.

**`loginfo`** — **not a formatting difference at all: the text matches and the STREAM differs.**
Upstream writes `<name>: <unknown> (try checking in log directory <dir>)` to **stderr** and leaves
a single blank line on stdout; RMSC writes the whole thing to stdout. Measured 3 September.

This was recorded here as "one trailing blank line" until then, and the reason is worth keeping:
`tools/fidelity-gate.sh:135` merges stderr into the comparison with `2>&1`, so a line that moves
between streams reads as identical and the only residue is a blank line somewhere unexpected. **A
merged comparison cannot see a stream difference.** Every formatting difference this document
records for a stream-merged operation should be re-read with that in mind.

**`jobinfo`** — a layout difference only, since the job *set* was corrected. Upstream prints a
header then indented jobs; RMSC prints one `name: job` line each.

**`info`** — eight measured differences, listed in full in `docs/messages.md`. The two that are
shape rather than spelling: upstream prints `Depends on the following services:` once and indents
the list where RMSC repeats a `Depends on:` label per dependency, and upstream omits
`Working Directory:` entirely when `dir` is unset where RMSC prints a resolved one always. RMSC
also omits the environment block and the closing separator, prints a `Group:` line upstream does
not, and differs in blank-line counts at three places.

**`perfinfo`** — the only one where the plan looks like it settles the matter and does not. It
calls the operation *"Improved — drops upstream's optional Python 3 + `ibm_db` dependency, since
embedded SQL reads the `ACTIVE_JOB_INFO` performance columns directly"*. That is a decision about
**dependencies**, not about output. Dropping the dependency never required printing less:
`QSYS2.JVM_INFO` and `QSYS2.ACTIVE_JOB_INFO` are both reachable from embedded SQL, and Phase 2
of the plan asked for *"every `QueryUtils` query as embedded SQL"*. Nothing explains twelve lines
where upstream prints sixty-six, so the narrower output is undocumented rather than designed.

## Beyond the operations — a quoted `on` in `enabled:`

RMSC reproduces upstream's `enabled:` rule exactly, including its oddities - the `y` prefix test,
`on` being case-sensitive where `true` and `yes` are not, and an unrecognised value disabling the
service. One corner it cannot reach:

    enabled: 'on'      upstream: HIDDEN     RMSC: visible
    enabled: "on"      upstream: HIDDEN     RMSC: visible

Quoting suppresses YAML's boolean resolution, so upstream sees the plain string `on`, which
satisfies none of its string tests and disables the service. Bare `on` resolves to a real boolean
and enables it. Every other quoted spelling agrees between the two, because `'y'`, `'yes'`,
`'true'` and `'1'` all satisfy a string test that acts on the text regardless.

**Why this is sanctioned rather than fixed.** `SCYAML`'s `unquote` discards whether a scalar was
quoted, so by the time the `enabled` test runs, `on` and `'on'` are the same string. Reproducing
it means carrying quotedness through the parser - a real change to `SCYAML_DOC_t` and every value
that passes through it - for one spelling of one value of one key, where the bare form is what
anybody would actually write.

The divergence is in the safe direction: RMSC **shows** a service upstream hides. The opposite
would be far worse, and was in fact the defect this rule was first implemented with - a `yes`
equality test rather than a `y` prefix test, which hid `enabled: yeah` and `enabled: yep`.

## Beyond the operations — narration, CLOSED 3 September

**Read this section as history.** It records the divergence as it stood, and the decision and its
outcome are at the foot of it. RMSC narrates now.

Upstream reports what it is doing while it does it. RMSC was silent. This affected every
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

**DECIDED 3 September, AND IMPLEMENTED. RMSC narrates.** It was undecided rather than
intentional — nothing in the plan asked for silence and no reason was ever recorded for it; RMSC
simply never implemented it. Richard's standing principle settled it: the output should be the
same as upstream's unless there is a very good reason, and there was none.

The measured family is in `docs/messages.md` § "Narration" — every text, which name each line
uses, which stream each goes to, the order they appear in, the trailing blank line, and the fact
that `-q` does **not** suppress any of it. `tools/narration-test.sh` pins it end to end, and the
wording is pinned separately by `qtestsrc/SCOUT.TEST.RPGLE` because the nine `SCOUT` procedures
return their line rather than printing it.

**The section above, describing RMSC as silent, is what this looked like before the work.** It is
left standing because the comparison is the useful part: RMSC was silent for no recorded reason,
and it took writing the divergence down to notice that nobody had ever chosen it.

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

`check` is compared with colour off, because colour is suppressed whenever stdout is not a
terminal and every comparison here runs that way. **Colour-off output is the contract and does not
change**; everything below is about what a person at a terminal sees.

This section said for weeks that the difference "needs a person looking at a terminal rather than
a diff — no byte-exact comparison can reach it." **That was wrong, and it is worth recording why
it was believable.** Colour is invisible through a pipe, so the obvious instrument cannot see it
and the obvious conclusion is that no instrument can. The right instrument is a pseudo-terminal,
which captures the escape sequences as bytes and compares them exactly — better evidence than an
eye, because it catches a wrong shade that "looks about right" would pass.

**Upstream's gate**, read from the bytecode of `com.github.theprez.jcmdutils.StringUtils`:

    System.console() != null  AND  System.getenv("SSH_TTY") non-empty
                              AND  NOT Boolean.getBoolean("jcmdutils.disablecolors")

So upstream colours over **ssh with a tty** and not on a local console, and a PTY alone is not
enough to reproduce it — `SSH_TTY` must be set too. A first probe that set only the PTY saw zero
escapes and suggested upstream never colours at all, which is the opposite of the truth.

**The reporting operations are a different matter, and one of them is now internally
inconsistent.** Measured escape bytes, upstream against RMSC: `info` 20 against 0, `perfinfo` 54
against 0, `jobinfo` 2 against 0; `loginfo` and the usage block are 0 on both sides. Upstream
colours `info`'s field labels cyan and its rule lines white `37`.

The one that mattered is `info`'s header, `short_name (Friendly)`, which upstream colours **cyan
`36` — exactly as it colours a `list` row**. **Fixed:** `SCEXEC_info` now calls `SCOUT_list_row`
instead of building the same two fields by hand, so the identical construct is coloured
identically, and a byte-sensitive format string is written once rather than twice.

The **rest** of `info`'s colour is deliberately still open — upstream colours its field labels
cyan and its rule lines white `37` — and so are `jobinfo`'s 2 escape bytes and `perfinfo`'s 54.
All three operations remain `undecided` in the gate, and their colour belongs with their content:
`info` alone carries eight measured non-colour differences, two of them shape rather than
spelling, so colouring the body before the content matches would mean doing it twice.

**RMSC's gate is in the shell, not in RPG, and RMSC's rule is deliberately not upstream's.**
`scripts/scr` adds `--colors` when `[ -t 1 ]`; `SCOUT_is_tty` is a stub returning false, so RMSC
never detects a terminal itself. That division is defensible — the test is one token in shell and
awkward in ILE.

The rules are differently shaped, and **this is now a decided departure rather than an unexamined
gap** (5 September 2026). Measured through `tools/colour-test.sh`'s pseudo-terminal:

| | upstream | RMSC |
|---|---|---|
| PTY, `SSH_TTY` set | 12 escape bytes | 6 — agree |
| PTY, `SSH_TTY` unset | **0 — monochrome** | **6 — still coloured** |
| pipe | 0 | 0 — agree |

The disagreement is exactly one case: a terminal that is not an ssh session — a local PASE shell,
a `su` that drops `SSH_TTY`, a harness allocating its own PTY.

**Why RMSC keeps its own rule.** Upstream's gate is `System.console() != null` **and** `SSH_TTY`
non-empty **and** not `-Djcmdutils.disablecolors`. The first test already answers "is this
interactive"; the second only removes cases, and reads as a proxy written by someone who ran it
solely over ssh. Matching it would mean RMSC deliberately going monochrome on a working console.

**It cannot touch the byte-exact contract.** Both implementations go monochrome on a pipe, and the
consumer redirects, so nothing that screen-scrapes `check` can see this. What is at stake is only
what a person at a non-ssh terminal sees.

`tools/colour-test.sh` stage 0 asserts it in **both** directions — upstream must still go
monochrome without `SSH_TTY`, RMSC must still colour — so a change on either side is reported
rather than silently absorbed. The upstream half doubles as proof the variable was really removed:
if it were not, upstream would colour and the case would fail rather than quietly pass.

**Four differences were measured through a PTY, and all four are CLOSED.** RMSC now matches
upstream byte for byte on `check`, `list` and `groups`, on a terminal and through a pipe:

| | upstream | RMSC before | RMSC now |
|---|---|---|---|
| `RUNNING` | green `32` | green `32` | matches |
| `PARTIAL` | amber `33` | amber `33` | matches |
| `NOT RUNNING` | magenta `35` | red `31` | **magenta `35`** |
| the service's short name, on a `check` row | the status colour | not coloured | **the status colour** |
| the `[not running at -->…]` suffix | the status colour | not coloured | **the status colour** |
| the short name on a `list` row | cyan `36`, fixed | not coloured | **cyan `36`, fixed** |
| `groups` | no colour at all | no colour | matches — measured on both sides, not assumed |

Upstream's row is `'  '` + colour + padded status + reset + `' | '` + colour + short name + reset
+ `' ('` + description + `') '` + colour + suffix + reset. The description is not coloured, and
the parentheses and spaces sit outside the escapes — so stripping the escapes from a coloured row
yields the uncoloured row byte for byte, which is what keeps the columns a consumer parses by
exactly where they were.

`list`'s cyan is **fixed rather than status-derived**: one listing covering a running, a partial
and a stopped service showed `36` on every short name, and `SCOUT_list_row` is not handed a status
at all, so it could not vary even by accident.

**Colour off is unchanged and remains the contract.** `tools/colour-test.sh` stage 1 exists to say
so, and the gate's byte-exact comparison covers it from the other side.

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
