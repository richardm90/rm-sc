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
| `info` | live differential | **pass** | all eight measured differences matched 18 September 2026; the separate relative-`dir:` question closed 20 September 2026 — see below |
| `jobinfo` | live differential | **pass** | matched 10 September 2026 — header, indent, not-running text, per-command blank line and colour |
| `loginfo` | live differential | **pass** (one item open, not this) | matched 9 September 2026, stopped-service scoping matched 18 September 2026, log-filename scheme matched 19 September 2026 — see below |
| `perfinfo` | live differential | **by design** | two differences, both settled: four affinity lines per job that no API carries, and the order of the job blocks, which upstream draws from a hash and RMSC sorts — see below. The gate checks for exactly these two and nothing else, per-recorded-difference since 19 September 2026 — see "The gate" |
| `start` | not gated | — | state-changing; `SCLIFE.TEST` covers the lifecycle against a service it creates and removes |
| `stop` | not gated | — | as above |
| `kill` | not gated | — | as above |
| `restart` | not gated | — | as above |
| `reload` | n/a | **out of scope** | cluster-only upstream. RMSC does not recognise the verb at all — see below |

Nine of the thirteen operations RMSC accepts are gated. **None are on the gate's `UNDECIDED` list
as of 20 September 2026** — `info`'s relative-`dir:` question was the last one; see
"IMPLEMENTED, 20 September 2026" below. `tools/fidelity-gate.sh` reports "step 8 complete" for
the first time. That is the gate's own list, not every open question about these operations:
`info`'s field-label and rule-line colour is a separate, still-deliberately-open item — see
"Beyond the operations — colour" below — the gate does not check colour at all.

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
  is not — a stray blank line is exactly the class of difference the gate exists to catch. It was
  once described here as "the whole of the `loginfo` divergence", which was wrong twice over: the
  divergence was four things, and a blank line was the only one a merged comparison could show.

The sweep covers five services: the three a default `check` displays, plus two from the `system`
group chosen to reach paths the others never touch — one using the `SBS/JOB` form of
`check_alive`, one using ports only. That second choice is not incidental. It is how the
port-to-job defect was found: every default service carries a job name, so the port-only path
had never run under test.

Verdicts are `by design` (sanctioned below), `undecided` (listed below, awaiting a decision),
`PASS`, or `REGRESSION`. The gate fails when something regresses **and** when something starts
matching without the list being updated, so the classification cannot quietly go stale.

**The verdict used to be classified per operation, not per recorded difference — and that was a
gap.** `perfinfo` is the case that surfaced it: it carries two settled differences (the affinity
lines and the job-block order, below), and a THIRD, unrelated difference in that operation would
have passed the gate silently, because `INTENTIONAL` sanctioned the operation as a whole rather
than the specific rows recorded here.

**DECIDED 18 September 2026, IMPLEMENTED 19 September 2026: `INTENTIONAL` is tightened to
per-recorded-difference for `perfinfo`.** `tools/fidelity-gate.sh` now strips exactly the two
catalogued shapes — the four affinity lines (present in upstream's output only) and the per-job
block ORDER — from a failing comparison before deciding the verdict. Whatever is left after that
is a residual: uncatalogued, and reported as `REGRESSION` even though `perfinfo` stays on
`INTENTIONAL`, rather than riding along under it.

**The order licence is for job BLOCKS, not for every line.** A first version of this stripped the
affinity lines and then sorted the two WHOLE files, which forgives far more than was ever decided
— it cannot tell a re-ordering of the job blocks from the two jobs' figures being swapped between
them (exactly the defect "The job order" below records as having actually happened: "upstream's
Java figures sit on the first job and RMSC's on the second"), or from the lines WITHIN one block
being printed in the wrong order (which this document already calls a defect in its own right —
see "The order of the sampled block is alphabetical by label" above). A peer review caught this
before it reached a real `perfinfo` defect. The fix treats each `Job:` paragraph — upstream's own
blank-line-delimited block — as one indivisible unit and sorts only THOSE, so a block's internal
line order and its association with its own job survive; only the order the blocks appear in is
forgiven.

`tools/gate-granularity-test.sh` (new) proves this against synthetic `sc`/`scr` stand-ins with
three scenarios sharing one scaffold — the recorded shape alone (`by design`), the recorded shape
plus one value nothing catalogues (`REGRESSION`), and the recorded shape with two jobs' real
values swapped between them and nothing else changed (`REGRESSION` — the case a whole-file sort
would have missed). Confirmed red against the pre-fix classifier (which reported `by design` for
all three) and green after. `file` and `scrunattrs` did not need the same treatment: both are
whole-surface differences by the plan's own words — the entirety of what each verb prints is a
different thing, not a mostly matching operation with a few catalogued exceptions — so there is
nothing more specific than the operation itself to check against.

**A new way for the gate to be red that is not a defect.** `perfinfo` can now fail the whole run
where it previously could not: if the job SET itself differs between the `sc` and `scr`
invocations — a job starting or ending in the gap between them, on a real, live service — that
shows up as a residual and reports `REGRESSION`, because job numbers are normalised but a job's
presence is not. This is a real race, not a defect in either implementation; if it is ever seen,
recognise it as this rather than debugging `perfinfo` itself.

**Which account verification runs under is also unsettled, separately from the differences
themselves.** `list`, `check` and `groups` read `$HOME/.sc/services`. `CLAUDE`'s copy is empty;
Richard's holds four broken, unrelated definitions. A green run under `CLAUDE` is weaker than it
looks — there is nothing there to trip over, so it cannot be told apart from a genuinely strong
run.

**DECIDED 18 September 2026: stage a dedicated fixture under `CLAUDE`'s `$HOME/.sc/services`**
for verification runs, rather than fixing or using Richard's personal account. Not yet done.

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

**`loginfo`** — **matched 9 September 2026.** What it took is worth recording, because this entry
was wrong twice before it was right, in the same way both times.

It was first recorded as "one trailing blank line, nothing else". On 3 September that was
corrected to "not a formatting difference at all: the text matches and the STREAM differs", with
the reasoning that `tools/fidelity-gate.sh` merges stderr into the comparison with `2>&1`, so a
line that moves between streams reads as identical and the only residue is a blank line somewhere
unexpected. **A merged comparison cannot see a stream difference**, and that part stands.

But the correction was itself generalised from one case. Both measurements had been taken on a
service with no log file, where **both implementations fail to find one** — the only state that
could be produced without staging and starting a service. Measured properly, with the streams
apart and a service started for the purpose:

| state | upstream | RMSC before |
|---|---|---|
| log found, empty | stdout `<name>: <path> (no data)` | stdout `<name>: <path> (0 bytes)` |
| log found, has data | stdout `<name>: <path>` — nothing after the path | stdout `<name>: <path> (15 bytes)` |
| no log found | **stderr** `<name>: <unknown> (try checking in log directory <dir>)` | stdout, same text |
| all three | one trailing blank line on stdout | none |

So the rule is **found to stdout, not found to stderr**, not "loginfo goes to stderr"; and the
text did *not* match, which is what the previous entry claimed. Exit status is 0 throughout, both
implementations, in every state.

RMSC now matches all four. `tools/loginfo-test.sh` covers them with the streams kept apart,
because the gate structurally cannot — which is how this stayed mis-recorded for six days.

### An unrelated leak found while these lines were open

`SCCOLL.RPGLE`'s `only_if_executable` test calls `IFS_open_file` inside a boolean condition and
discards the descriptor, leaking one per definition per load. The same defect in
`SCEXEC_loginfo` was fixed with the `loginfo` work because the lines were already being edited;
this one is not, because closing it means restructuring a condition on the definition-loading
path, which feeds the byte-exact operations and wants its own test rather than a drive-by change.

### Three things about `loginfo`, two of them now fixed

**A stopped service whose log is still on disk — MATCHED 18 September 2026.** Upstream reports no
log; RMSC used to report the log regardless. Upstream's `loginfo` is scoped to the *running
instance*, RMSC's was scoped to the *file*.

**DECIDED and IMPLEMENTED 18 September 2026: RMSC now matches upstream.** `SCEXEC_loginfo` fetches
the service's jobs once and only attempts to open the log file when at least one is running;
otherwise it answers exactly as the no-log case does. `tools/loginfo-test.sh`'s stopped-service
case, previously pinned as a known, undecided divergence (asserting only which case each
implementation was in, not the text), now asserts the text and passes — the pass/failed counters
carry it, not the pinned/changed ones. All 78 `SCEXEC` unit cases and the rest of the loginfo
harness (15 other cases) still pass; no regression.

**The log file naming.** Upstream writes `~/.sc/logs/<timestamp>.<svc>.log` and RMSC writes
`~/.sc/logs/<svc>.log`, so neither finds a log written by the other. Pre-existing, recorded in
`docs/messages.md` as a property of `SCLOG_path`.

**DECIDED 18 September 2026: RMSC will switch to upstream's timestamped naming.** The most
invasive item in this decision round — it changes where RMSC writes logs on disk, not just what
it prints.

**MEASURED 19 September 2026, live, on the box.** Three things, none of them obvious from the name
alone:

1. **The exact stamp.** A fresh start's `For details, see log file at:` line and the file actually
   on disk both read `2026-09-19-12.26.22.<short_name>.log` — a fixed 19-character prefix,
   `YYYY-MM-DD-HH.MM.SS`, then a dot, the short name, and `.log`. This is RPG's own `%CHAR(ts:
   *ISO)` shape (`YYYY-MM-DD-HH.MM.SS.uuuuuu`) with the trailing 7-character microseconds cut off —
   convenient, not coincidental: DB2's ISO timestamp format and upstream's own stamp agree on every
   separator.
2. **One file per start, not one file reused.** Stopping and starting the same service twice left
   **two** files on disk, timestamped `12.27.27...` and `12.27.34...`. Nothing deletes the older
   one.
3. **`loginfo` finds the file by scanning, not by remembering.** `sc loginfo`, run as a separate
   process seconds after `sc start`, reported the exact file that start had just created — and
   after the second start above, reported the *newer* of the two files on disk. So there is no
   per-instance state to recover across process invocations: the rule is "the greatest filename
   matching `*.<short_name>.log` in the log directory", full stop. The fixed-width stamp sorts
   lexicographically by time, so "greatest" and "newest" are the same question.

**This makes `SCLOG_path` two different questions wearing one name, and it has to become two
procedures.** A caller *starting* a service needs a fresh path nothing on disk has yet — computed
once per start and threaded through everywhere that attempt needs it (the redirect target, and any
same-attempt re-check, such as the log-detail-on-timeout line). A caller *reading about* a service
(`loginfo`, `stop`'s escalation warning path, `scrunattrs`) needs the latest existing file, or none.
Conflating them either invents a file that started clean has never written, or reads back a
filename the write side never used.

**IMPLEMENTED 19 September 2026: split into `SCLOG_new_path` (fresh, timestamped, one call per
start) and a redefined `SCLOG_path` (scans `SCLOG_dir(def)` for the greatest name matching
`*.<short_name>.log`, returns `''` if none).** `SCLOG_path`'s signature is unchanged — same
parameter, same return type — only its meaning moved, so no `RMSC.BND` signature bump was needed;
`SCLOG_new_path` is appended as a new export. `SCEXEC_start` now computes the path once via
`SCLOG_new_path` and reuses the same local variable for the post-timeout log-detail check, which
used to re-call the old, deterministic `SCLOG_path` and would otherwise now silently re-resolve to
whatever the directory scan finds — usually the very file just written, but the wrong thing to
rely on there.

**One side effect, found live and judged correct rather than fixed.** `scrunattrs` (the RMSC-only
extension showing the `SCOMMANDER_*` variables a start would set) now reports an **empty**
`SCOMMANDER_LOGFILE` for a service RMSC has never started — an ad-hoc probe of `sshd`
(`port:22`) among them — because `SCLOG_path` correctly finds nothing on disk. The old,
deterministic path was never more than a plausible-looking fiction for a file that had never been
written; empty is the honest answer to "what did RMSC start this with" for a service RMSC did not
start. `tools/adhoc-name-test.sh`'s `scrunattrs-logfile` case now asserts the empty value.

**Coverage.** `tools/loginfo-test.sh` gained two stages testing the write side directly (a fresh
`scr start` names a correctly-shaped file; a separate `scr loginfo` finds it; stop-then-restart
leaves two files and the newer is reported) and had its own staging simplified — since both
implementations now discover logs the same way, one staged file serves both sides instead of two.
`tools/narration-test.sh` and `tools/fidelity-gate.sh` needed comment corrections only (both
already matched by SHAPE, not by the static name, once checked closely) except for
`log_reset`/`log_bytes`, two helpers that hardcoded the old static path and would have silently
read 0 bytes for every case built on log growth — found by actually running the suite after the
fix landed, not anticipated in advance. `qtestsrc/SCEXEC.TEST.RPGLE` gained four unit tests
covering `SCLOG_new_path`'s shape and `SCLOG_path`'s empty/newest-wins/exact-suffix-match
behaviour directly, isolated from any live differential.

**Verified 19 September 2026, after a false start.** The first `RUCRTRPG` attempt failed with
`CPF9E18: Attempt made to exceed usage limit for product 5770WDS`, and Richard checked
`WRKLICINF PRDID(5770WDS)`: features 5101/5102/5103 all showed a Usage Limit of `0`, which
briefly looked like the cause. It was not — Richard confirmed the same `CPF9E18` appears in his
own successful compiles and does not stop them, which sent the search to the actual compile
listing rather than the licensing screen. The real fault was `RNF0273: Compiler not able to open
the /COPY or /INCLUDE file` on every one of RMSC's own copybooks, cascading into hundreds of
"name or indicator not defined" errors: `RUCRTRPG` was invoked with a **relative** `INCDIR`
(`'QPROTOSRC' '/prj/rmtools'`, matching `.vscode/testing.json` and `makei build`'s own working
`CRTRPGMOD` calls) but without first `cd`-ing into the deploy directory the way `makei build`
does — so `QPROTOSRC` resolved against the wrong working directory. Adding `cd
/home/CLAUDE/builds/rm-sc` before the `RUCRTRPG` call fixed it outright; `CPF9E18` still prints,
harmlessly, exactly as Richard's own compiles show. `RMSCT/SCEXEC` now compiles clean and **all
81 cases pass** (78 original plus 3 new — two of the four new assertions extended existing test
procedures rather than adding new ones), 573 assertions, 0 failures.

**The spooled-file section.** RMSC prints `    spooled file <name> number <n> in <job>` after the
log line. Upstream has a spooled-file path of its own (`getSpooledFiles`), and **what it prints
has not been measured**: producing a spooled file owned by the service's own job needs a
`batch_mode` fixture, because PASE runs each `system` call in its own job and the spooled file
then belongs to a transient one. Not changed, and not asserted against upstream anywhere.

Two consequences of that, found by review and worth knowing before anyone measures it:

- The spooled loop runs in the **not-found** case too, so for a batch service with spooled files
  and no log, a spooled line becomes the FIRST thing on stdout — the log line having moved to
  stderr. Pre-existing behaviour, but the not-found case's stdout used to carry the log line and
  now carries only the blank, so the spooled line is newly exposed there. Whether upstream lists
  spooled files for a service it reports no log for is part of the same unmeasured question.
- `tools/loginfo-test.sh` tolerates spooled lines from line 2 onward, which does not cover that
  case. It would fail quoting a spooled line rather than anything about the log.

**`jobinfo`** — **matched 10 September 2026.** Five differences, all measured with the streams
apart before anything was written:

| | upstream | RMSC before |
|---|---|---|
| header | `<short> (<friendly>):` once per service | none |
| job line | four-space indent, job name bare | `<short>: <job>` |
| no jobs | `    NO JOB INFO (either not running, or running in kernel task)` | `<short>: not running` |
| trailing blank | one per **command** | none |
| colour | short name cyan `36`; the no-jobs sentence magenta `35` | none |

Two of those were nearly got wrong, and both for the same reason — a rule inferred from the one
case in front of the person inferring it.

**The blank line is per COMMAND, not per service.** A single named service cannot tell them
apart. `loginfo` had exactly this wrong for a day; here it was measured on a group first, and
`tools/jobinfo-test.sh` pins it with a **three**-member group whose running member has **two
jobs** — because `jobinfo`'s branches print different numbers of lines, so *per job* is a third
rival, and the blank counts then separate all four readings: per command 1, per job 2, per pair
2, per service 3.

**The header's cyan is FIXED, not derived from status** — measured at `36` on RUNNING, PARTIAL
and NOT RUNNING within one command. `check` colours those same two fields *by* status, so
reusing its colouring would have looked reasonable and been wrong twice over. The header goes
through `SCOUT_list_row`, which is the third place that construct appears, and
`tools/colour-test.sh` now pins all three together rather than leaving them to drift apart.

**What still differs, by design:** the ORDER of jobs within a service. Upstream's is a
`HashSet` shuffle keyed on job numbers; RMSC sorts ascending — see the job-order section above.
The gate cannot see it, because it normalises job numbers to `NNNNNN`, so `tools/jobinfo-test.sh`
compares the job **set** rather than the output, and says so.

### The `sc: ` prefix and short-versus-friendly naming

Two whole-surface differences, catalogued in full in `docs/messages.md`'s "two whole-surface
differences" section — each touches many rows at once rather than being a single case, which is
why they were tracked separately from the per-row texts.

**The `sc: ` prefix — MATCHED 19 September 2026.** `SCRUN` used to write `'sc: ' + opts.err` on
every stderr line RMSC produced. Measured, 3 September 2026, byte by byte: upstream's stderr is
bare at column 1 in every case probed — the usage block, `Could not find definition for service
'x'`, `WARNING: No services are found in group 'x'`. `tools/error-delivery-test.sh` did not pin
the prefix either way, which is why it sat undecided rather than being caught as a defect.

**DECIDED 18 September 2026, IMPLEMENTED 19 September 2026: dropped.** Both `SCRUN` call sites now
write `opts.err` bare. `tools/error-delivery-test.sh` asserts it directly — two anchored patterns
(`^sc: ` and the bare-colon spelling `^sc:([^ ]|$)`), checked separately so a failure names which
one occurred — inside `assert_case`'s `once`/`warn` branch, which covers every measured usage and
operational failure case, and inside `sweep_no_service`, which covers the five "needs a service"
usage errors on the same delivery path. All 33 cases in the harness pass; the fidelity gate shows
no regression.

**Short-versus-friendly naming.** Upstream's progress line uses a service's **short** name; its
status and error lines use the **friendly** name. **DECIDED 18 September 2026: apply it
everywhere, matching upstream.**

**RE-CHECKED 19 September 2026, and it is narrower than it looked.** Re-measuring live turned up
two things:

- **The narration family and the per-member group error already follow the rule correctly** —
  confirmed again live, byte for byte, including the dependency-wrapped form
  (`SCOUT_err_timeout`/`SCOUT_err_dep_failed`). Nothing to change here; this half was already done
  on 3 September.
- **What looked like the remaining case — `SCEXEC_start`'s `'Could not start ' + short_name + ':
  ' + reason` (line ~471) — is not reachable the way it was assumed to be.** A `start_cmd` that
  does not exist is not a launch failure upstream-side; it is an ordinary timeout, which already
  goes through the correct, friendly-named path. The branch this text belongs to only fires when
  `SCLAUNCH_start` itself fails at the PASE level, a rare condition with no cheap, safe way to
  reproduce live. Left as found, pending a way to trigger it for a proper red-then-green cycle.
- **The other three candidate texts turned out to sit downstream of a real behavioural gap, not a
  naming one** — see "`stop` does not escalate when its own `stop_cmd` fails", above. Rewording
  them now would be polishing text on a code path this project may replace.

So: **the decided rule is fully applied everywhere it is currently measurable.** What remains is
one rare, hard-to-trigger case and three texts blocked on the escalation decision above, not a
wide sweep of call sites.

**`info`** — eight measured differences, listed in full in `docs/messages.md`, **all fixed 18
September 2026.** The two that were shape rather than spelling: upstream prints `Depends on the
following services:` once and indents the list, where RMSC used to repeat a `Depends on:` label
per dependency; and upstream omits `Working Directory:` entirely when `dir` is unset, where RMSC
used to print a resolved one always. RMSC also now prints the environment block and the closing
separator it used to omit, matches upstream's blank-line counts at all three places, and no longer
prints a `Group:` line at all — the one item here that was an RMSC addition with no upstream
counterpart, unlike `PGM-` above, which upstream actively rejects and RMSC deliberately keeps as
an extension.

`tools/info-test.sh` (new 18 September, extended 20 September) pins the shape against staged
definitions — full (two dependencies, a group, custom environment variables, no `dir`), minimal
(nothing set), one with `dir` set to an absolute path as the regression control for the direction
that already worked, and (added 20 September) one with `dir: .` for the relative case, below.

**The separate relative-`dir:` question — DECIDED and IMPLEMENTED 20 September 2026.** Until this
date, the fidelity gate's live differential matched on 4 of the 5 real services swept; the fifth,
`mapepire`, differed on `Defined in:` and a raw-versus-resolved `Working Directory: .` (see
`tools/gate-fixtures/README.md`'s `rmscgate_info_reldir`). Investigating it turned up more than a
display difference — see "A definition's real location, not the symlink's" below, in "Beyond the
operations". The decision: `Working Directory:` now prints `dir:`'s raw value, exactly as
upstream does (`SCEXEC.RPGLE`, the `info` write, changed from `SCDEF_effective_dir(def)` to
`def.dir`); the resolved form is still what `SCDEF_effective_dir` returns for the ACTUAL launch,
via `SCLAUNCH`, which must keep resolving correctly and now does so against the real, symlink-
followed location rather than the raw one. `tools/info-test.sh`'s new `RELDIR` case pins the
display; `qtestsrc/SCDEF.TEST.RPGLE`'s new symlink cases pin the resolution. The fidelity gate now
matches on all 5 real services, `info` moved from `UNDECIDED` to fully matching
(`tools/fidelity-gate.sh` reported `RECLASSIFY` the moment this landed, confirming the list was
right to update), and **Verification step 8 is complete** for the first time — see "Closing
Verification step 8" below.

**`perfinfo`** — the plan looked like it settled this and did not. It calls the operation
*"Improved — drops upstream's optional Python 3 + `ibm_db` dependency, since embedded SQL reads
the `ACTIVE_JOB_INFO` performance columns directly"*. That is a decision about **dependencies**,
not about output, and dropping the dependency never required printing less. Nothing explained
twelve lines where upstream prints sixty-six.

What explains it is that **upstream does not query these attributes at all — it scrapes
`DSPJOB`.** Measured from `sc.jar` on 8 September 2026:
`OperationExecutor$PerfInfoFetcher` calls `QueryUtils.getJobDspJobDotted(job, "*RUNA", logger)`,
which runs `DSPJOB OPTION(*RUNA)` and matches every printed line against one regex —

    ^\s{0,3}([\p{L} 0-9]*[\p{L}0-9])\s*(\. )*:\s+([a-z]+)?\s{0,16}([^\s]+)??$

— then prints each match as `description (keyword): value`. There is no field list anywhere in
upstream; the block is a transcription of whatever that display command happens to print, in its
order. That is also where its oddities come from: `Thread resources affinity (THDRSCAFN): ` has a
trailing space and no value because DSPJOB prints that line with a keyword and no value and the
regex's final group is reluctant, and the `Group:` / `Level:` lines beneath it render without
parentheses and at a deeper indent because they are separate DSPJOB lines carrying no keyword.

### RMSC will not scrape a display command. Richard's decision, 8 September 2026

RMSC reads the attributes from `QUSRJOBI` instead. The output format of `DSPJOB` is IBM's to
change without notice, and a scrape that quietly stops matching is indistinguishable from a job
with no attributes — the exact failure shape this project keeps finding and refusing.

**The cost is three attributes, and it is measured rather than assumed.** `QUSRJOBI` format
`JOBI0150` carries eleven of the fourteen in one call. The three it does not carry are:

| line RMSC omits | what it means |
|---|---|
| `Thread resources affinity (THDRSCAFN):` → `Group:` | whether the job's threads are kept together on one subset of processors and memory, or placed independently |
| `Thread resources affinity (THDRSCAFN):` → `Level:` | how strictly that placement is honoured — a preference (`*NORMAL`) or binding (`*HIGH`) |
| `Resources affinity group (RSCAFNGRP):` | whether the job joins a group so related jobs share processors and memory |

Three attributes, but **four printed lines**: `Thread resources affinity (THDRSCAFN):` prints its
own header line, with a trailing space and no value, before its two indented sub-fields. The gate
(below) strips all four; `docs/messages.md`'s earlier "three lines" count under-counted that
header line and is corrected there.

All twelve `JOBI*` formats were dumped for a live job and searched for printable runs — not for
expected names, so a different spelling would still have been found. None carries them. The
converse could not be staged: **neither `CHGJOB` nor `SBMJOB` accepts `THDRSCAFN` or
`RSCAFNGRP`** (`CPD0043` from both), so a job with a non-default affinity cannot be created
without a job description carrying one. That also constrains the suites — nothing can vary these
values without creating a `*JOBD`.

**Not derived from the job description instead**, though it would have filled the lines: the JOBD
and the system value say what a job *should have inherited*, not what it holds. Printing an
inherited value in a column that reports a job's actual attributes would be a worse answer than
an absent line, because it would be indistinguishable from a measured one.

These three are also the least load-bearing lines of the sixty-six — nothing about whether a
service is healthy depends on processor affinity, and every job on this system holds the default.
That is a reason the gap is tolerable, not a reason it is invisible: it is three lines of
`perfinfo` output that upstream prints and RMSC does not, and the gate must classify it rather
than pass over it.

### `--sampletime` — matched, including a warning RMSC never emitted

Measured against 1.7.1 on 8 September 2026, both implementations, on a live
two-job service. RMSC previously accepted only whole numbers and discarded anything else in
silence, so `--sampletime=2.5` — the form upstream's own help text documents as `x.x` — sampled
for one second and said nothing.

| argument | upstream | RMSC now |
|---|---|---|
| absent | ~1.03s window | same |
| `=2.5` | ~2.56s | same |
| `=0.25` | sub-second | same |
| `=0` | no wait | same |
| `=2.5555` | ~2.61s | same, truncated to three decimals |
| `=0000002.5` | ~2.55s | same |
| `=abc` | `WARNING:` on stderr, then 1s, rc 0 | same, verbatim |
| `=` (empty) | the same warning | same |
| `-q =abc` | nothing on stderr | same |

The warning is upstream's exact wording, names the **whole argument** rather than the value,
appears once however many jobs the service has, and `-q` suppresses it — all measured, not
inferred.

**Two rows diverge deliberately.** For `--sampletime=-1` and for a value too large to hold,
upstream accepts the number and then its own sampling code fails, printing `Unable to retrieve
performance data for job ...` for every job and exiting 0. RMSC clamps a negative window to zero
without a warning (as upstream does not warn either) and refuses an over-large value with the
warning above, falling back to one second. Both still produce a report where upstream produces
error text. Reproducing a crash faithfully is not parity worth having, and it is recorded here
rather than left to be discovered.

**Three abends were written into this one option's parser in a single afternoon** — `MCH1210`
from a guard sized against the wrong type, `RNX0103` from a guard counting characters instead of
the receiver's integer digits, and `RNX0100` from `%SUBST` past the end of a string after the
threshold was relaxed without copying the guard three lines above it. All three were reachable
from the command line, and all three were found by hand rather than by any test, because the
procedure is local to its module and no suite can call it. That is the argument for the harness
coverage that now exists, and it is a better argument than any of the individual fixes.

### The job order — SETTLED 9 September 2026, and there was nothing to reproduce

Comparing label-by-label after the rewrite, the line counts agree exactly once the affinity lines
are allowed for (66 against 58 on a two-job service, four omitted lines per job). But the blocks
are in the **opposite order**, so upstream's Java figures sit on the first job and RMSC's on the
second.

Measured 8 September 2026, three runs each, both stable and consistently opposite:

    upstream   420566  420560
    RMSC       420560  420566

**This is pre-existing and `jobinfo` has always had it** — `scr jobinfo` lists the same two jobs
the same way round. The rewrite did not cause it; it made it visible, because `perfinfo` now
prints enough per job to notice which job you are looking at.

What is measured about the cause, and what is not. The service carries **two** criteria,
`JOBNAME:MAPEPIRE` and `PORT:8076`. The port resolves to one job only (420566); the job name
resolves to both, and `ACTIVE_JOB_INFO` returns them 420560 first — which is exactly RMSC's
order. So RMSC's order is its first criterion's natural order, and upstream's is not. Whether
upstream evaluates the criteria in the other order, sorts, or deduplicates into a structure that
reorders, **has not been established** — only one service on this machine has more than one job,
so there is no case available that separates those hypotheses.

**The fixtures were staged and the question is answered: upstream's order is Java `HashSet`
iteration order over the qualified job-name strings.** Computing `String.hashCode`, HashMap's
spread function and the bucket layout at capacity 16 predicts upstream's output *exactly* on
three independent job sets — a three-job service, a four-job service with two criteria, and the
original two-job one.

Two fixtures were needed because a two-job service cannot separate the candidates. A single
criterion over three jobs killed "upstream sorts": its answer was neither ascending, descending,
nor the database's natural order. A pair of definitions with the same two criteria written in
*opposite* orders killed "upstream evaluates criteria in the other order": both produced
identical output.

**So there is no order to match.** That sequence is a function of the job NUMBERS, which change
every time a service restarts, so it reshuffles on every restart. Reproducing it would mean
reimplementing `String.hashCode` and HashMap's bucket layout to copy a shuffle. This is the same
finding as the conflict-block member order in `7791266`, and it gets the same answer.

**RMSC sorts instead, ascending by job number**, which is a defined order rather than the
incidental one it had before — it was previously whichever criterion appeared first in the YAML,
which is a property of the definition rather than of the jobs. Every job query also carries
`ORDER BY JOB_NAME` now, which matters beyond tidiness: the fetch loop stops at
`SCQRY_MAX_JOBS`, so ordering in the database is what decides *which* jobs survive an overflow —
the lowest-numbered, which are the oldest, rather than an arbitrary subset. Sorting after the
truncation could not have fixed that.

Two limits recorded rather than fixed. Which 32 survive when more than 32 match **across
criteria** is undefined, because the merge fills from each criterion in turn. And the
specification is *ascending job number*, not *oldest first*; those differ after the job-number
counter wraps at 999999.

**It also means `perfinfo` is not "matching except three lines".** It matches except four lines
per job AND the order of the job blocks.

**Read the two paragraphs above as history; both differences are now settled and `perfinfo` is on
`INTENTIONAL`.** The gap they describe — the gate could not see the difference between "matches
except the four affinity lines" and "matches except the four affinity lines *and* an ordering
nobody had explained" — is the one closed 19 September 2026 by making the gate check for the
recorded shape specifically rather than trusting the operation's own membership. See "The gate"
above.

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

## Beyond the operations — `stop` did not escalate when its own `stop_cmd` failed

**Found and FIXED 19 September 2026.** Found by accident — while trying to measure the exact
wording of three
`stop`-path error texts recorded as `unmeasured` (see `docs/messages.md`: `Stop command failed for
<short>: <reason>`, `<short> did not stop within <n> seconds`, `<short> did not stop, even
immediately`). What was measured is not a wording gap. It is a real difference in **behaviour**,
and it is bigger than the three rows it was standing in for.

**A service with its own `stop_cmd`, where that command does not actually bring the service
down.** Measured with a real listener (`tools/gate-listen.py`, self-bounded so nothing outlives
the test regardless of outcome) and a `stop_cmd` that exits non-zero without touching the job:

```
upstream:  Performing operation 'STOP' on service 'zzsf_cmdfail'
           WARNING: Timed out waiting for service 'Zulu Stop Fail CmdFail' to stop. Will try harder
           Stopping via endjob
           Service 'Zulu Stop Fail CmdFail' successfully stopped
           exit 0

RMSC:      Performing operation 'STOP' on service 'zzsf_cmdfail'
           ERROR: Stop command failed for zzsf_cmdfail: Stop command failed with 1:
           exit 253, service still running
```

**Upstream does not treat a failing `stop_cmd` as final.** It warns, escalates to `ENDJOB`
regardless of whether a custom stop command was configured, and succeeds. RMSC gives up
immediately and leaves the service running.

**This contradicted a premise written into `stop_one`** (`QRPGLESRC/SCEXEC.RPGLE`, the comment
beginning "Escalate only where upstream does"): *"a service that supplied its own stop command has
said how it wants to be stopped, and overriding that could cut short whatever the command was
doing."* That reasoning was not what was measured. Upstream overrides it.

**DECIDED and IMPLEMENTED 19 September 2026: `stop_one` now escalates to `ENDJOB` regardless of
whether a `stop_cmd` was configured**, printing `SCOUT_stop_retry`'s warning
(`WARNING: Timed out waiting for service '<friendly>' to stop. Will try harder`, stderr, no
trailing blank) and `Stopping via endjob` (stdout) before falling through to the same final
escalation the no-`stop_cmd` path already used. `stop_cmd`'s own return value is no longer acted
on — "ran" and "worked" are the same question upstream asks only once, at the poll afterward.

`tools/stop-escalation-test.sh` (new) covers both failure shapes — a `stop_cmd` that exits
non-zero, and one that exits 0 and does nothing — against a real, self-bounded listener
(`tools/gate-listen.py`), asserting the narration text/exit status *and*, separately, that the
service is actually down afterward (so a fix that only reworded the message without truly
escalating would still fail). A working `stop_cmd` is also tested as a **regression control**: it
must show neither the warning nor `Stopping via endjob`, catching a fix that escalates
unconditionally rather than only when the configured command actually failed. All 15 checks pass;
`tools/narration-test.sh` (65 checks), the `SCEXEC` unit suite (78 cases) and the fidelity gate
show no regression.

**The two remaining, unmeasured texts stay out of scope, on purpose.** The
"did not stop within `<n>` seconds" and "did not stop, even immediately" texts belong to the
*no-`stop_cmd`* path (`ENDJOB` used directly, with its own `*CNTRLD`-then-`*IMMED` escalation),
which this fix does not touch. Measuring that path's failure/escalation wording live means staging
a job that resists `ENDJOB OPTION(*IMMED)` on a real box — a materially different risk from
anything measured here — and remains deliberately unattempted without its own decision on scope
and safety.

## Beyond the operations — a definition with no `name:` was silently accepted

**Found and FIXED 19 September 2026**, while designing a deliberate fixture for verification step
9 (which account bare `list`/`check`/`groups` should be verified against). `tools/colour-test.sh`
diffs bare `list` and `groups` — no scope filter — against upstream, and `docs/testing-notes.md`
already recorded that this diff behaves differently on Richard's personal account (which carries
four broken definitions) than on `CLAUDE`'s (empty): "the two failures on RICHARD are real". One
of those four was never identified beyond "a definition with no `name:` that RMSC lists and
upstream refuses to load" — closing item 9 meant finding out exactly what that difference is,
since a fixture built to reproduce it needs the real behaviour, not a guess.

**Measured, with a definition carrying a valid `start_cmd` and `check_alive` but no `name:` key at
all:**

```
upstream:  Invalid configuration for service 'zznn_broken' from file [.../zznn_broken.yaml]:
           Required attribute 'name' not specified
           WARNING: Ignoring file due to load errors: .../zznn_broken.yaml
           - never appears in list, check, or groups

RMSC:      zznn_broken (zznn_broken)
           - appears in every listing, friendly name defaulted to the short name
```

**This is the same class of gap already closed for the other two required keys.** `SCDEF_from_doc`
already refuses a definition with no `start_cmd` or no `check_alive` — `def.err = 'Service ' +
short_name + ' has no start_cmd'` / `' has no check_alive'`, reported on stderr, absent from every
listing. `name` was never given the same treatment; the code that read it defaulted an empty
value to the short name instead of asking whether it should have been there at all.

**DECIDED and IMPLEMENTED 19 September 2026: `name` is now required, checked immediately after it
is read** (alongside the `cluster` check, both ahead of the two existing required-key checks at
the end of `SCDEF_from_doc`) **and refused the same way.** The old fallback — defaulting
`def.friendly` to `def.short_name` when empty — is removed as dead code: nothing can reach it once
an empty `name:` is refused up front. `docs/messages.md`'s exact wording for the upstream message
is not matched here — that is D2 wording work, out of scope, same as the two sibling checks were
left when they were first added.

This closes the specific, previously-unidentified difference behind `docs/testing-notes.md`'s "two
failures on RICHARD are real", and gives verification step 9 a fixture whose value does not depend
on anyone's personal, undocumented account: any harness that needs a populated-account scenario
can stage this exact definition, per run, with the same staging-and-cleanup discipline this
project's other harnesses already use.

**IMPLEMENTED, verification step 9 closed 19 September 2026.** `tools/colour-test.sh` now stages
this exact definition (`zzc_noname.yaml`, no `name:`, `start_cmd`/`check_alive` both present) in
its own temporary `SC_SERVICES_DIR`/`-Dservices.dir` fixture directory, alongside its other
invented services — additive, not a replacement for `$HOME/.sc/services`, so it reaches the bare
`list`/`groups` sweep the account's own definitions would, without writing anything into a real
account or needing it to persist between runs. A dedicated `noname-excluded-from-both` assertion
confirms neither implementation lists it, reusing the run's own capture rather than a second live
call. Confirmed to fail for the specific, correct reason against the pre-fix build (RMSC's `list`
names it, upstream's does not) and to pass against the fix — the "must disagree" case CLAUDE.md
asks for.

**Closing this required fixing the required-`name:` check's own collateral damage first.** Making
`name` required broke 89 of `SCDEF.TEST.RPGLE`'s 123 cases outright, and a further ~90 across
`SCCOLL.TEST.RPGLE`, `SCEXEC.TEST.RPGLE` and `SCLAUNCH.TEST.RPGLE` — nearly every fixture in this
project's test suites was written before `name:` was required and omitted it for brevity, since
nothing before this fix cared. Closed by adding a `name:` line to every affected fixture (mechanical
repair, not new test judgment — the fixtures' actual assertions are unchanged) except
`test_short_and_friendly_name`, which specifically asserted the now-removed fallback and was
rewritten to test what it actually still can: filename case-folding, independent of naming. All
five affected suites (`SCDEF` 123, `SCEXEC` 81, `SCCOLL` 87, `SCLAUNCH` 15, plus `SCLIFE`'s 7,
confirmed unaffected after one transient, unrelated failure was retried clean) pass in full.

## Beyond the operations — specifiers

Two differences the gate cannot currently see, because it only exercises defined services.

**Ad-hoc services are named differently, and this is on the `check` path.**
**DECIDED 10 September 2026: RMSC matches upstream.**

```
upstream:    RUNNING            | ad_hoc_port_445 (Ad hoc service running at port 445)
RMSC before: RUNNING            | port:445 (ad hoc port 445)
```

The status column and layout matched; the name and description did not.

**Richard's decision, and the reasoning is the part that generalises: on existing functionality
RMSC aims for parity unless there is a good reason not to, and "ours is better" is not one.**
That is worth stating because RMSC's version *was* arguably better, and the argument for keeping
it was real:

    sc  check ad_hoc_port_22   ->  rc 253, Could not find definition for 'ad_hoc_port_22'
    scr check port:22          ->  rc 0,   RUNNING

Upstream prints a name it will not accept back. RMSC's was round-trippable — a usable handle
where upstream's is a label. It was still the wrong thing to keep: `check` is the byte-exact
surface, the round-trip property serves a consumer that does not exist (the client uses short
names and `group:` only), and an ad-hoc row cannot appear in a bare `check` at all — it only
exists when somebody typed a specifier.

**The measured rule**, taken 10 September 2026 across every form:

| specifier | name | description |
|---|---|---|
| `port:22` | `ad_hoc_port_22` | `Ad hoc service running at port 22` |
| `job:QINTER` | `ad_hoc_job_QINTER` | `Ad hoc service running at job QINTER` |
| `job:qinter` | `ad_hoc_job_qinter` | `... at job qinter` |
| `job:QUSRWRK/QINTER` | `ad_hoc_job_QUSRWRK_QINTER` | `... at job QUSRWRK/QINTER` |

Two things in that table are easy to get wrong and are the reason it is written out in full.
**Case is preserved, not upper-cased** — which is a live rival because RMSC upper-cases a job
name when it builds the criterion, correctly, and the ad-hoc *name* must not follow it. And the
`/` in the subsystem-qualified form becomes `_` **in the name** while staying `/` **in the
description**, so the two cannot be built from one string.

The name propagates: `jobinfo`'s header and `loginfo`'s line both carry it, so this is one
change where the ad-hoc definition is constructed rather than several at the printing sites.

**`PGM-` is deliberately NOT brought into line, and stays an RMSC extension.** Upstream rejects
it outright — `sc check PGM-QZSHSH` exits 253 with `Could not find definition for service
'PGM-QZSHSH'` — where RMSC reports it as an ad-hoc service. Richard's decision: it costs an
upstream user nothing, the plan lists `PGM-` among the criterion forms, and RMSC is expected to
grow beyond upstream in places. Recorded here so it is not later "fixed" into a rejection.

**`port:N` resolves differently — MATCHED 18 September 2026.** Upstream matches the specifier to
a *defined* service when one carries that port as a criterion, and reports it under its real name
with all of that definition's jobs. RMSC used to always treat `port:N` as ad hoc. The plan lists
`port:<n>` as "Ad hoc, no definition needed" but never said whether an existing definition should
win.

**DECIDED and IMPLEMENTED 18 September 2026: RMSC now matches upstream.** `resolve_one` in
`SCMAIN.RPGLE` checks the loaded collection for a definition carrying the requested port before
falling back to `SCMAIN_adhoc` — usable criteria only, so an unusable one (which reads as port 0)
cannot collide with `port:0`, this project's standing ad-hoc control.

**The candidate has to be VISIBLE, not merely loaded, and that took a second pass to get right.**
The first version searched every definition `SCCOLL` had loaded, and it broke live against this
box's real `system_sshd` definition — in the `system` group a bare `check` excludes by default —
which claims port 22 and made `port:22` resolve to it even though upstream, measured the same run,
still answered ad hoc. Upstream's matching respects the same group exclusion `SCEXEC_check_all`
and `SCEXEC_list` apply, so the search now carries the same `SCCOLL_in_groups(...: ignore_groups)`
guard. Found by `tools/adhoc-name-test.sh`'s stage 2 and `scrunattrs` cases turning up
`system_sshd` where an ad-hoc row was expected, on a live run against the real box — not by a case
written in advance, since nothing in this repository can name that definition to test against
directly.

`tools/adhoc-name-test.sh`'s stage 6 covers the collision (a colliding definition wins) and the
non-collision control (an unclaimed port still falls back to ad hoc) — both pass, and the fidelity
gate's live differential confirms it on 5 real services with no regression. Neither half is
client-affecting — the client uses short names and `group:` only.

**The gate itself cannot widen to ad-hoc specifiers — `tools/adhoc-name-test.sh` did instead,
20 September 2026 (Closing Verification step 8, item 3).** `tools/fidelity-gate.sh` sweeps
`<op> <service>` over the names `scr list` returns; an ad-hoc service has no definition and
appears in no `list`, so there is no specifier anywhere in the gate, and widening it would mean
re-capturing its byte-exact `BASELINE` for ad-hoc rows — a fixture that names a live system's
services and lives outside this repository for exactly that reason. `tools/adhoc-name-test.sh`
already had every other piece (both binaries, live capture, the specifier forms), so a new
stage 7 there does the same thing the gate does for named services — a full, byte-for-byte
`stdout`/`stderr` diff — for `check`, `jobinfo`, `info` and `loginfo` (not `file`/`scrunattrs`,
whole-surface intentional divergences regardless of what names the service; not `perfinfo`,
which carries its own settled partial differences the gate already has dedicated handling for),
over three representative specifiers (`port:22`, `job:QINTER`, `job:QUSRWRK/QINTER`).

**It found two real, previously uncatalogued differences, both confined to `info`, both fixed the
same day.** `check`, `jobinfo` and `loginfo` matched upstream byte for byte on every specifier
tested, with no changes needed.

- **`Defined in: <ad hoc>`.** Upstream's literal text for a specifier with no definition file;
  RMSC printed `Defined in: ` with nothing after it, because `def.defined_at` is legitimately
  blank for an ad-hoc definition (only a real file load ever sets it) and `info`'s write
  (`SCEXEC.RPGLE`) never checked for that case. This was not a new finding in the sense of never
  having been looked at — `tools/adhoc-name-test.sh`'s own "WHAT IS DELIBERATELY NOT ASSERTED"
  list named it on 10 September 2026, alongside three other `info` differences that have since
  been fixed by other work (the eight-difference close, 18 September; the relative-`dir:`
  question, 20 September). This is the one that outlived all three, because nothing had ever
  actually asserted it. Fixed by printing `<ad hoc>` when `defined_at` is blank.
- **`Check-alive conditions: ...` case.** Upstream lower-cases an ad-hoc criterion's *value* in
  `info` regardless of how it was typed — measured on both shapes it can take: `job:QINTER`,
  `job:qinter` and `job:QUSRWRK/QINTER` all display as `JOBNAME:qinter` /
  `JOBNAME:qusrwrk/qinter`, and even a non-numeric, unusable port (`port:aBc`) displays as
  `PORT:abc`, lower-cased the same way. A first version of this fix, before peer review, excluded
  `PORT` criteria from the lower-casing on the unmeasured assumption that only JOB criteria were
  affected — `port:aBc` was the one case the original three specifiers could not separate, and
  checking it directly overturned the assumption. RMSC showed the JOB form in the case
  `criterion.raw` is deliberately stored for MATCHING — upper-case, per the ad-hoc naming
  decision above ("Case is preserved, not upper-cased" is about the ad-hoc NAME; the criterion
  used for matching is a different field and is upper-cased on purpose). This is a genuinely new
  finding — `tools/adhoc-name-test.sh` had a stage specifically pinning that the criterion stayed
  upper-cased, but it read that fact back out of `info`'s own display, which is precisely the
  surface that turned out to be wrong. Fixed at the `info` write site only (not
  `SCDEF_criterion_text`, which is shared with `SCCOLL`'s duplicate-criterion detection and
  `SCEXEC_evaluate`'s unusable/failed-criteria text — those were not measured here and are not
  touched): the displayed value is lower-cased when the service is ad hoc and the criterion is
  not `PGM-` — deliberately excluded, and the one shape *not* measured, because upstream refuses
  a `PGM-` specifier outright (see above) and so never renders one at all; a defined service's
  own `check_alive: PGM-X` already renders `JOBNAME:PGM-X` upper-cased specifically so the
  defined and ad-hoc forms of the same program agree with each other, and lower-casing only the
  ad-hoc one would have reopened that self-agreement for a case upstream has no opinion on.
  `criterion.raw` itself is untouched, and matching remains exactly as case-insensitive as before.

`tools/adhoc-name-test.sh`'s own pinned check for "the criterion stays upper-cased" was reading
`info`'s display, so fixing the difference it pinned necessarily changed what it saw — not a
regression in the pin, its observation point going stale. Re-pointed at SELF-consistency rather
than at upstream's answer: the same specifier, typed upper- and lower-case, must get the *same*
status from RMSC either way, whatever that status is — checked directly rather than via whether
a real job happens to be up today, since `job:QUSRWRK/QINTER` measured NOT RUNNING on both
implementations while this was being written, which would have made a "matches upstream's
answer" version of the pin pass regardless of whether case-insensitive matching still worked (the
same shape of gap CLAUDE.md's own `>= 0` example describes — a check that accepts the fallback
value cannot tell "handled" from "defaulted"). A companion row confirms upstream is
case-insensitive here too, so the self-consistency check is provably testing the right thing.
`tools/adhoc-name-test.sh`: 54 cases, 0 failures, 0 pinned-behaviour changes, 0 reference drift.
Confirmed live against the real `sc`/`scr` binaries on all three specifier forms, plus the
`port:aBc` control.

## Beyond the operations — inputs read before an operation starts

Two more, found while correcting discovery. Neither is reachable from anything the gate runs
today, because both are about what happens *before* an operation starts. One is implemented
(`scrc`/`SC_OPTIONS`, below); the other (`services.dir`) already matched.

**`scrc` and `SC_OPTIONS`.** Upstream reads options from `/QOpenSys/etc/sc/conf/scrc`, from
`$HOME/.scrc`, and from the `SC_OPTIONS` environment variable, and prepends them to its argument
list. **The `scr` column below is the PRE-IMPLEMENTATION measurement** — RMSC read none of the
three at the time it was taken. It is kept as the baseline the fix closed, not as the current
state; see "IMPLEMENTED, 19 September 2026" further down for what `scr` does today. Measured
against sc 1.7.1, with a bare `list` showing three services (four output lines, the fourth
blank):

| | `sc` | `scr`, before this was implemented |
|---|---|---|
| `SC_OPTIONS=-a list` | 36 | 4 |
| `list`, with `--ignore-groups=backend` in `$HOME/.scrc` | 35 | 4 |

The second is worth reading twice: the count goes *up*, because an `--ignore-groups` from a
config file replaces the default `system` exclusion rather than adding to it. So a `.scrc`
nobody remembers writing changes which services a bare `check` shows — and changed it for
upstream only, before RMSC read it too. **Was undecided**; the plan did not mention either
mechanism.

**Investigated further, 19 September 2026, to give the undecided item something concrete to
decide against.** The system-wide file (`/QOpenSys/etc/sc/conf/scrc`, owned by `qsys`, affecting
every user on the box) was read but not written to for this — it is shared, and nothing here
justifies changing what every other user on a live box sees. Everything below was measured
through `$HOME/.scrc` and `SC_OPTIONS`, which are safe to change back afterwards and were, every
time.

**The model is one merged argument list, not three separate mechanisms.** All evidence is
consistent with a single rule: the system conf file's lines, then `$HOME/.scrc`'s lines, then
`SC_OPTIONS` (split on whitespace), then the real command line, are concatenated in that order
into one token stream, which is then parsed exactly the way a typed command line would be — same
parser, same option semantics, no special-casing for where a token came from. Measured
consequences, each confirmed live:

- **Last occurrence wins, for anything single-valued, regardless of which source it came in
  from.** `.scrc: --ignore-groups=backend` plus `SC_OPTIONS=--ignore-groups=webserver` excludes
  `webserver` only (`SC_OPTIONS` is later in the stream). Adding an explicit
  `list --ignore-groups=rm-console` on the real command line excludes `rm-console` only — the
  real command line is latest of all. Two lines in the *same* `.scrc`, `-a` then
  `--ignore-groups=backend`, behave exactly like two separate sources in that order: the second
  line wins. Reversing them (`--ignore-groups=backend` then `-a`) reverses the result. `-a` is not
  a standing "show everything" mode — it is sugar for clearing the ignore-groups value, itself
  subject to being overridden by a *later* `--ignore-groups` in the same stream.
- **`SC_OPTIONS` is split on whitespace only — no shell-style quoting is re-parsed.**
  `SC_OPTIONS='--color-scheme="RUNNING:BLUE"'` passes the literal characters `"RUNNING:BLUE"`,
  quote marks included, straight to the option's own value — confirmed by the resulting error
  naming `["RUNNING:BLUE"]`, not `RUNNING:BLUE`. A value containing a space cannot be given
  through `SC_OPTIONS` at all; the conf-file forms do not have this problem, since each line is
  already one token (or is itself further split — not tested, since nothing in the shipped
  example needs it).
- **An unrecognised option is a non-fatal warning, on stderr, exit 0, and identical regardless of
  source**: `WARNING: Argument '--this-is-not-a-real-option=xyz' unrecognized and will be
  ignored`, byte-identical whether the argument came from `.scrc` or was typed directly. This is
  not a `.scrc`-specific mechanism — it is upstream's ordinary unrecognised-argument handling,
  reached because the merged stream is fed through the one parser.
- **It is not scoped to `list`.** `check` honours `-a` from `.scrc` the same way (36 lines,
  matching `list -a`). `groups` does too, and more surprisingly: with `-a` set, `groups` prints
  two MORE group names (`host_servers`, `tcp_servers`) that a bare `groups` never shows at all —
  they exist only among `system`-group services, so with the default exclusion in place they have
  no visible members and do not appear as groups either. One shared filter setting, read by every
  read-only operation measured.
- **A bare word is not rejected as "not an option" — it can hijack the verb itself.** `.scrc`
  containing the single line `list`, with `sc check` typed as the real command, produced `Could
  not find definition for service 'check'`, exit 253 — the wording `check` itself gives for an
  unresolvable name. That means the merged stream was `["list", "check"]`, `list` (arriving
  first, from `.scrc`) was taken as the verb, and the real command word `check` was left over as
  an ordinary positional argument that `list` then tried and failed to resolve as one. **A `.scrc`
  or `SC_OPTIONS` value that is not a flag can silently change which command runs at all**, not
  merely which of its options are set.

**What this means for scoping RMSC's version, if there is to be one.** The flag-level behaviour
(`-a`, `--ignore-groups`, `--sampletime`, `--color-scheme`, applied uniformly with last-wins
precedence across `check`/`list`/`groups`/`info` alike) is what the shipped conf file's own
comments describe and is a bounded, well-understood surface. The verb-hijacking behaviour is not
documented anywhere upstream, is not what anyone editing `.scrc` for "10-second sampling" would
expect or want, and reproducing it faithfully would mean a config file nobody remembers writing
being able to silently redirect what command a user thinks they are running — a materially worse
failure mode than the one already recorded above (a changed *service list*). Whether RMSC
implements the bounded, documented surface, the whole surface including the hijack, or neither,
is Richard's call — this paragraph exists so it is an informed one.

**DECIDED 19 September 2026: the bounded, documented surface — not the system-wide conf file, not
the verb-hijacking behaviour.** RMSC reads `$HOME/.scrc` and `SC_OPTIONS`, merges their contents
ahead of the real command line (`.scrc` then `SC_OPTIONS` then the real argv, same order upstream
uses for these two), and honours `-a`/`--all`, `--ignore-groups` and `--sampletime` with
last-wins precedence, uniformly across `check`/`list`/`groups`/`info` — the three flag shapes
RMSC's own parser already accepts on the command line, nothing more. The system-wide
`/QOpenSys/etc/sc/conf/scrc` is deliberately out of scope — RMSC has no per-box config directory
to read it from even if it wanted to, and the two per-user sources already give this a bounded,
testable surface. A bare word, or a real upstream option RMSC does not implement, is a non-fatal
warning, the same as any other unrecognised argument, and never changes which command runs — the
one piece of measured upstream behaviour this deliberately does NOT reproduce, because
reproducing it would make a config file nobody remembers writing capable of redirecting what a
user thinks they are running.

**`--color-scheme` is explicitly deferred, separately from the rest, 19 September 2026.**
Recognising it here would mean claiming it works; RMSC has no colour-remapping mechanism at all
today, so a `.scrc` spelling it correctly gets the same "unrecognised, ignored" warning as a
typo, until that mechanism exists as its own piece of work. Tracked as a future item, not part of
this one.

**IMPLEMENTED, 19 September 2026.** `SCMAIN_config_prefix` (new, `QRPGLESRC/SCMAIN.RPGLE`) is the
pure filter: given `.scrc`'s raw text and `SC_OPTIONS`'s raw text, it returns the recognised
tokens, `.scrc`'s first, space-joined, ready to prepend to the real command line — exactly the
asymmetry measured above, `.scrc` one argument per LINE (never split further into MULTIPLE
tokens, even on internal whitespace), `SC_OPTIONS` one argument per whitespace-separated word.
`scripts/scr` and `SCRUN` (the PASE entry point) read `$HOME/.scrc` via `SCDIRS_home_dir()` (the
same home-resolution RMSC already uses elsewhere, not `$HOME` itself, which is not reliable in a
batch job) and `SC_OPTIONS` via `ENVVAR_get`, and prepend the filtered result ahead of the typed
command line before `SCMAIN_parse` ever sees any of it — which is what gives the recognised flags
their measured last-wins precedence against whatever was actually typed, for free, from the
existing parser. `SCCMD` (the native `SC` CL command) does not go through this - it calls
`SCMAIN_parse` directly with its own parameters, has no shell environment to read `SC_OPTIONS`
from, and upstream's own `.scrc`/`SC_OPTIONS` mechanism is specific to its shell entry point too.
A length guard (RMSC-only; upstream's strings are unbounded) refuses to combine the two when the
result would not fit in the 1024-character command line, rather than silently truncating one.

**A candidate is recognised only if it carries no embedded space or tab, even when it matches a
shape by prefix — found by peer review before this reached a real command line.** A `.scrc` line
recognised and kept "whole" is handed back to `SCMAIN_parse` as plain text, which retokenises on
whitespace with no idea any of it came from one line; keeping a spaced candidate on the strength
of its prefix only meant it was split apart again one call later. Measured, live, as an actual
near-miss: a `.scrc` containing the single line `--sampletime=5 list`, staged ahead of a typed
`check`, merged into `list check` — `list` is a real operation word, so it became the verb, and
the typed `check` became an ordinary argument to it. That is precisely the upstream
verb-hijacking behaviour this item decided NOT to reproduce, reached through the one path meant
to prevent it. `is_config_flag` now refuses any candidate containing a space or tab outright,
regardless of what it starts with; a value that genuinely needs a space (upstream's own
`--color-scheme` example has one) cannot be represented by RMSC's parser from ANY source, typed
or not, so refusing it here is no narrower than what the command line already allows.

**`SC_OPTIONS` also splits on a TAB, not only the space character** — measured live the same way
the `.scrc` trim needed one for tabs; `SCMAIN_config_prefix` translates a tab to a space before
tokenising `SC_OPTIONS`, rather than widening `next_token`'s own separator, which every other
caller of it still uses only for a real, already-typed command line.

A separate, blind test author (given only the measured rule and `SCMAIN_config_prefix`'s
prototype, not the implementation) wrote the first 15 `iRPGUnit` cases for the pure filter,
including the two-sources asymmetry as a "must disagree" pair. One ambiguity it flagged and
declined to guess at — whether the leading/trailing whitespace trimmed from a `.scrc` line
reaches tabs, not just spaces — was resolved by a further live measurement (a leading tab before
`-a` is still recognised; RPGLE's own `%TRIM` only strips the space character, so a dedicated
trim was needed). A peer review then found the prefix-matching gap above, that the original
"must disagree" pair did not actually exercise it (both its cases happened to agree, since `-a`
is checked by exact equality, not by prefix), and that nothing in the suite held the fix already
made for a `.scrc` file ending in a trailing newline abending (`RNX0100`, a previously-documented
trap in this codebase) — the ordinary shape of a text file, and the shape a `.scrc` written with
`echo` actually takes. Cases for all three were added directly (mechanically pinning already
-measured, already-decided facts, not new interpretation) rather than restarting the blind-review
round trip. `qtestsrc/SCMAIN.TEST.RPGLE`: 54 test cases, 299 assertions, 0 failures. Confirmed
end to end, live, against every scenario measured above — the three-source precedence chain, the
exact `.scrc`-versus-`SC_OPTIONS` whitespace-splitting asymmetry (both the simple case and the
corrected prefix-matching one), the exact warning text, the verb-hijack near-miss now refused,
and the trailing-newline fix — with no regression to the rest of the suite.

**`services.dir` — a custom definition directory.** Upstream takes one from the `services.dir`
JVM system property, searched last so it overrides everything else; confirmed on 1.7.1 by
setting it through `JAVA_TOOL_OPTIONS` and watching a definition outside every standard
directory appear in `sc list`. ILE has no system properties, so RMSC reads `SC_SERVICES_DIR`
instead, and honours it the same way. The concept and the search order match; the mechanism
differs because it has to. **By design**, and recorded here because a reader comparing the two
will otherwise find a property with no counterpart.

## Beyond the operations — a definition's real location, not the symlink's

Found 20 September 2026 while picking up the last piece of Verification step 8: `info`'s
relative-`dir:` question (see above). Looked at first as a display decision — does `Working
Directory:` show the raw `dir:` value or a resolved one — and turned out to also be a real
correctness bug, on a real, currently-installed service.

**The service:** `mapepire`, discovered by RMSC via `/QOpenSys/etc/sc/services/mapepire.yaml`,
which is a **symlink** to the real file at `/QOpenSys/pkgs/lib/mapepire/mapepire.yaml`. That real
file sets `dir: .` and a relative `start_cmd: ../../bin/mapepire`.

**Measured, live, side by side:**

| | upstream | RMSC (before the fix) |
|---|---|---|
| `Defined in:` | `/QOpenSys/pkgs/lib/mapepire/mapepire.yaml` (the real file) | `/QOpenSys/etc/sc/services/mapepire.yaml` (the symlink) |
| `dir: .` resolves against | the real file's directory | the symlink's own directory |

Upstream resolves the symlink before recording where a definition came from; RMSC recorded
wherever it was *discovered* — the directory-walk path, straight off `IFS_readdir`, with nothing
resolving it further. Traced to `SCDEF_from_doc` (`QRPGLESRC/SCDEF.RPGLE`), which set
`def.defined_at` directly from the path it was handed.

**Why this is not cosmetic.** `def.defined_at` feeds two things, not one: `info`'s `Defined in:`
line, and `SCDEF_effective_dir` — which `SCLAUNCH.RPGLE` actually `cd`s into before running
`start_cmd`. For `mapepire`, on this box, RMSC's (wrong) resolution reaches
`/QOpenSys/etc/bin/mapepire` — confirmed live, this path does not exist — where upstream's
correct resolution reaches `/QOpenSys/pkgs/bin/mapepire`, confirmed to exist. A symlinked
definition with a relative `dir:` would fail to start correctly under RMSC as it stood, silently,
until someone tried.

**Fixed by resolving the real path before storing it.** `resolve_symlinks` (new,
`QRPGLESRC/SCDEF.RPGLE`), called from `SCDEF_from_doc` when `def.defined_at` is set. QC2LE (the
ILE C runtime RMSC binds against) has no `realpath()` — `CPD5D02: Definition not found for symbol
'realpath'`, found live trying it — so this is built from `readlink()` instead: a bounded loop
(ten hops, generous for any real chain) that follows one symlink at a time, resolving a relative
target against the link's own directory the same way `SCDEF_effective_dir` already resolves a
relative `dir:`, and stopping the moment `readlink()` fails — which is also exactly what happens
for a path that was never a symlink at all, so that case needs no separate check. A second helper,
`normalize_path`, collapses the `../..` segments a relative `readlink()` target leaves behind
before storing the result, so `Defined in:` matches upstream byte for byte rather than merely
resolving to the same place via IFS traversal.

A separate, blind test author (given the measured defect and `SCDEF_load`/`SCDEF_effective_dir`'s
existing prototypes, never the implementation) wrote three `iRPGUnit` cases, each a direct-load/
symlinked-load pair over the SAME real file: today the pair disagrees on `def.defined_at` and on
`SCDEF_effective_dir(def)` (the bug); after the fix, both must produce the SAME value as the
direct load, for `dir: .`, and for no `dir:` at all. All three pinned values against the real
file's own path, not only against each other, so a fix that made both sides agree on some other,
still-wrong, value would not pass by coincidence. `qtestsrc/SCDEF.TEST.RPGLE`: 126 test cases,
654 assertions, 0 failures.

`tools/info-test.sh`'s new `RELDIR` fixture and the fidelity gate's real `mapepire` sweep both
confirm the display side; the `SCDEF.TEST.RPGLE` cases confirm the side that actually matters for
a running service. **By design once fixed** — not a divergence recorded and left, an actual defect
closed.

**What was actually measured, stated so it is not overclaimed.** `defined_at` feeds four things,
not one: `info`'s `Defined in:`, `SCDEF_effective_dir` (measured, both here and by the new unit
tests), `SCCOLL`'s "Unrecognized attribute" warning, and `SCOMMANDER_DEFINED_AT` (the environment
variable a launched service receives). Only the first two were measured against upstream through
a symlink. `file` is unaffected — confirmed live, `scr file` prints the raw YAML content
regardless (the already-recorded whole-surface divergence, above), never `defined_at` at all. The
other two almost certainly improve for the same reason `Defined in:` does, since upstream
presumably uses one resolved value throughout rather than one per call site, but "almost
certainly" is not "measured" — worth confirming if either is ever the thing actually being
debugged.

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

**Correction, 10 September 2026: "`jobinfo` 2 against 0" is incomplete, and taken literally it is
wrong.** Two escape bytes is the RUNNING case. A **stopped** service emits **four** — the
`NO JOB INFO (…)` sentence wrapped in magenta `35`, the same colour `check` gives NOT RUNNING,
with the four-space indent sitting **outside** the coloured run. A three-member group emits
eight. Found by the test author, who would have failed correct behaviour had it asserted the two.

Same shape as the other measurements corrected on this page: taken on the one state that was in
front of the person taking it, and written down as though it were the rule.

The one that mattered is `info`'s header, `short_name (Friendly)`, which upstream colours **cyan
`36` — exactly as it colours a `list` row**. **Fixed:** `SCEXEC_info` now calls `SCOUT_list_row`
instead of building the same two fields by hand, so the identical construct is coloured
identically, and a byte-sensitive format string is written once rather than twice.

The **rest** of `info`'s colour is deliberately still open — upstream colours its field labels
cyan and its rule lines white `37` — as is `perfinfo`'s 54. Their colour belongs with their
content: `info` alone carries eight measured non-colour differences, two of them shape rather
than spelling, so colouring the body before the content matches would mean doing it twice.

`jobinfo` is **no longer among them.** Its colour landed on 10 September 2026 with its layout,
and the "2 escape bytes" quoted above is the figure the correction earlier on this page retracts
— two is the running case, four is a stopped one, eight a three-member group.
`tools/colour-test.sh` pins all three states. Of the three operations this paragraph once
described as undecided, only `info` still is.

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

1. ~~Decide the four undecided operations above~~ — **decided AND implemented, 18-19 September
   2026.** `info`: full parity on all eight points, plus removing the `Group:` line — done.
   `loginfo`: matches upstream on the two items it had been left deliberately open on
   (stopped-service scoping, log-file naming) — done. `jobinfo` and the affinity half of
   `perfinfo` were already matched. This list item was left saying "none of this is implemented
   yet" for a day after all four had been closed — corrected here rather than left to mislead the
   next reader.
2. ~~Decide the two specifier differences~~ — **decided AND implemented.** `PGM-` stays an RMSC
   extension (unchanged). `port:N` matches an existing definition first, falling back to ad hoc
   only when none carries that port — decided 18 September 2026, implemented the same round.
3. ~~Widen the gate to exercise `port:` and `job:` specifiers~~ — **done, 20 September 2026.**
   `tools/fidelity-gate.sh` itself is still structurally unable to (see "Beyond the operations —
   specifiers", "WHY A NEW FILE" in `tools/adhoc-name-test.sh`, for the reasoning against widening
   it directly — re-capturing its byte-exact `BASELINE` for ad-hoc rows would be a large,
   external-to-this-repo change for a question a live differential answers just as well). The
   widening landed instead as a new stage in `tools/adhoc-name-test.sh`, which already had every
   piece the gate itself would have needed (specifiers, both binaries, live capture) and none of
   the reason not to use them. See "Beyond the operations — specifiers" below for what it found.
4. ~~Remove whatever is settled from the gate's `UNDECIDED` list~~ — **done, 20 September 2026.**
   The per-recorded-difference tightening this depended on landed 19 September (see "The gate"
   above) for the one operation that needed it, `perfinfo`. `info`'s relative-`dir:` question —
   the one thing still on `UNDECIDED` — closed 20 September (see "Beyond the operations — a
   definition's real location, not the symlink's" above); `tools/fidelity-gate.sh`'s `UNDECIDED`
   is now empty, and the gate itself reports **"GATE OK: step 8 complete - every difference is
   intentional and listed"** for the first time.

**All four items in this list are now done.** Verification step 8 is complete both in the sense
`tools/fidelity-gate.sh` checks (every difference on a defined service is intentional and listed)
and in the sense this list tracked separately (ad-hoc specifiers now have the same standing,
live-differential coverage named services always had).

Also decided 18 September 2026: the `sc: ` stderr prefix, **dropped 19 September 2026**.
Short-versus-friendly naming, **re-checked 19 September 2026: already applied everywhere it is
currently measurable** — see "The two whole-surface differences" above; a rare `SCEXEC` case
remains, unreachable in practice. The `stop`-escalation gap found while re-checking that item is
**fixed, 19 September 2026** — see "Beyond the operations" above; its two remaining unmeasured
texts (the no-`stop_cmd` path) stay open, deliberately, pending a safe way to measure them. The
log-filename scheme is **fixed, 19 September 2026** — see "Three things about `loginfo`" above;
its four new unit tests **are compiled and pass in full** — the earlier `RUCRTRPG` failure was
traced to a missing `cd` into the deploy directory before a relative `INCDIR`, not a licensing
issue; `CPF9E18` is harmless noise, confirmed against Richard's own successful compiles. The
decision to stage a dedicated verification fixture under `CLAUDE`'s account rather than Richard's
is **implemented, 19 September 2026** — see "Beyond the operations — a definition with no `name:`
was silently accepted" above for both the fixture and the parity defect that gave it real
substance. `SC_OPTIONS`/`.scrc` is **implemented, 19 September 2026** — see "Beyond the
operations — inputs read before an operation starts" above for the measured model, the decision,
and the fix; the gate granularity item (below) also closed the same day.

Separately, and not part of step 8: the gate should compare `list -a` across all services, to
hold Verification step 9's discovery parity. The two implementations agree on it today, but the
gate compares the default three, so nothing would catch it if they stopped agreeing.
