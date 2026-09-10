# The message catalogue — every line RMSC says, and what `sc` says instead

This is the working list for **D2** (message wording). It exists because the wording differences
were being found one at a time, each in the middle of some other piece of work, and each written
down somewhere different — the plan, a fixture header, a comment in
`tools/error-delivery-test.sh`. A difference recorded in three places and fixed in none is how
`reload` came to be described in `docs/parity.md` as something RMSC "rejects with a clear
message" when in fact RMSC does not know the word.

**Every row states its basis.** `measured` means observed side by side against the `sc` 1.7.1
installed on the box. `captured` means upstream's text is held in a local artefact
(`local/baseline-operations.txt`, a probe log) but the two were not run side by side for this
particular row. `unmeasured` means nobody has looked, and the RMSC column is the only column
anyone should trust. Do not promote a row from `unmeasured` by reasoning about it.

`tools/d2-probe.sh` captures every `unmeasured` row in one run. Run it before starting D2.

## The two whole-surface differences

These are not one row each; they change many rows at once, so decide them before the table.

**1. RMSC prefixes every error with `sc: `; upstream appears not to.** `QRPGLESRC/SCRUN.PGM.RPGLE`
writes `'sc: ' + opts.err` on stderr for both the parse and the run failure. Every upstream text
captured so far is bare — `Could not find definition for service 'x'`, not
`sc: Could not find definition…`. The prefix is a survival from the escape-message era, when the
line arrived as `CPF9897: sc: …` and the `sc:` was doing the work of naming the program.

`tools/error-delivery-test.sh` does not pin it: it forbids a **message-id** prefix
(`^[A-Z]{2,4}[0-9]{4}:`) and `sc: ` is not one. So the prefix can be removed or kept without any
assertion changing, which means the decision has to be taken deliberately rather than discovered.

**Measured 3 September**, byte by byte through `cat -A`. Upstream's stderr is bare in every case
probed — the usage block, `Could not find definition for service 'x'`, and
`WARNING: No services are found in group 'x'` all begin at column 1 with no prefix of any kind.
The `sc: ` prefix is RMSC's alone.

**2. RMSC names a service by its short name where upstream names it by its friendly name.**
Upstream's progress line uses the **short** name and its status and error lines use the
**friendly** name; RMSC uses the short name throughout. This is already recorded in
`docs/parity.md` for the narration family and in `tools/error-delivery-test.sh:902` for the
per-member group error, and it applies to the `SCEXEC` failure texts below as well.

*Basis: measured for narration; measured for the group error.*

## Command-line failures

RMSC's text comes from `SCMAIN_parse` and `SCMAIN_run` (`opts.err`), delivered once on stderr by
`SCRUN` with the `sc: ` prefix above. Exit statuses already match and are pinned by
`tools/error-delivery-test.sh`; **only the text is open here.**

| case | RMSC | upstream | basis |
|---|---|---|---|
| unknown service | `Unknown service x` | `Could not find definition for service 'x'` — stderr, exit 253 | measured |
| unknown operation | `Unknown operation x` | `Usage: sc  [options] <operation> <service>` | measured |
| no operation | `No operation given` | the usage block | measured |
| unknown option | `Unknown option --badflag`, and refuses | `WARNING: Argument '--badflag' unrecognized and…`, then carries on with exit 0 | measured |
| operation needs a service | `Operation info needs a service` | the usage block | measured |
| unexpected argument | `Unexpected argument x` | — | unmeasured |
| bad ad-hoc port | `Invalid data for port number or job name criteria for service 'x'` (`SCOUT_invalid_criteria`) | same text | measured |
| path that does not load | `Cannot load <path>: <reason>` | `Invalid configuration for service 'null' from file […]` | measured |
| `--version` | `Unknown option --version`, exit 255 | `Version: 1.7.1` and `Build time: 2023-08-16 02:42:28 (GMT)` on **stdout**, exit 0 | measured |
| `reload` | `Unknown operation reload` | `Performing operation 'RELOAD' on service '<name>'` on stdout, then `ERROR: reload operation requires a cluster with at least two workers defined.` / `Maybe you meant to do a 'restart'?` on stderr | measured |

**RMSC has no usage block at all.** Nothing in `QRPGLESRC/` prints one; three of the rows above
want one, and `-h` (D3) wants it too. Writing it is the largest single item in D2.

**Measured 3 September, and it is one block.** `sc`, `sc nosuchoperation`, `sc info` and `sc -h`
print byte-identical text — 33 lines on **stderr**, exit **255**, stdout empty. `--help` prints it
too. The text is reproduced in full in [the usage block](#the-usage-block-verbatim) below rather
than in this table, because it is what RMSC has to emit character for character.

Two things in it are worth noticing before it is copied. It documents **eleven** operations and
RMSC accepts thirteen: `scrunattrs` and `file` appear nowhere in it, which is consistent with
`docs/parity.md` recording both as deliberate departures. And it does not mention `--version` or
`-h` themselves, though both work.

## Load-time warnings

All on stderr since `1baf1ac`, from `SCCOLL` and `SCMAIN`.

| case | RMSC | upstream | basis |
|---|---|---|---|
| file the filename rule rejects | `WARNING: Ignoring file: <path>` | same | measured |
| unrecognised key | `WARNING: Unrecognized attribute '<k>' in file <path>` | same | measured |
| definition will not load | `WARNING: <name>: <reason>` — one line | two lines: `Invalid configuration for service '<name>' from file […]: <reason>` **and** `WARNING: Ignoring file due to load errors: <path>` | measured |
| liveliness conflict | `WARNING: the following services all have conflicting definitions for liveliness check '<c>':` + indented claimants | same, claimants in a non-deterministic order | measured |
| no services in group | `WARNING: No services are found in group '<g>'` | **the same text**, on stderr, exit 0, with a single blank line on stdout | measured |
| cluster definition | `WARNING: <name>: Service <name> uses cluster mode, which RMSC does not implement` | loads it and expands into backend rows | measured; **RMSC's behaviour is sanctioned** — cluster is out of scope |

**The load-failure row is the one with a `-q` consequence,** and it is why the `-q` divergence
cannot be fixed on its own. Upstream splits one cause into an ERROR line and a WARNING line, and
`-q` removes only the WARNING. RMSC folds both into a single `WARNING:`-prefixed line and so
suppresses the whole thing. Splitting the line the way upstream does fixes the wording and the
`-q` behaviour in one change; fixing `-q` first would mean deciding whether RMSC's single line is
an error or a warning, which is exactly the question the split answers.

## Narration — the family, now implemented

**Measured 3 September** with `tools/d2-probe.sh --narrate`, against a staged service that
genuinely comes up — its start command binds the port it is checked on, so `successfully started`
is the real message and not a timeout misread as one. **All on stdout, exit 0, with one trailing
blank line after each command.**

| observed | upstream |
|---|---|
| progress, every operation | `Performing operation '<VERB>' on service '<short>'` — verb **upper-cased**, **short** name. All four verbs captured verbatim: `START`, `STOP`, `KILL`, `RESTART` |
| started | `Service '<friendly>' successfully started` |
| stopped | `Service '<friendly>' successfully stopped` |
| already up | `Service '<friendly>' is already running` |
| already down | `Service '<friendly>' is already stopped` |
| restart, from up | one `RESTART` progress line, then `successfully stopped`, then `successfully started` |
| restart, from down | one `RESTART` progress line, then **`is already stopped`**, then `successfully started` |
| start-side dependency | `Attempting to start service dependency '<short>' (<friendly>)...` |
| stop-side dependent | `Attempting to stop dependent service '<friendly>'...` |

**The two dependency lines are not symmetrical.** The start side names the service twice, short
then friendly in parentheses; the stop side names it once, friendly only. That is upstream's
behaviour, not a transcription slip, and anyone implementing this from the table above will get it
wrong by making them match.

**`kill` on a stopped service says `is already stopped`,** exactly as `stop` does — it does not
say `ERROR: No running jobs for service '%s'`. Where that message comes from is still `unmeasured`;
it is in the jar's catalogue but nothing probed reaches it.

**Every service in the walk gets its own outcome line, dependencies included.** Starting a service
whose dependency must be started first prints four lines, not two:

    Performing operation 'START' on service 'rmscd2_parent'
    Attempting to start service dependency 'rmscd2_depsvc' (RMSC D2 depsvc)...
    Service 'RMSC D2 depsvc' successfully started
    Service 'RMSC D2 parent' successfully started

So the outcome line belongs to each service the operation touches, not to the one that was named.

**The dependency line is unconditional.** It is printed even when the dependency is already
running and nothing is done:

    Attempting to start service dependency 'rmscd2_depsvc' (RMSC D2 depsvc)...
    Service 'RMSC D2 depsvc' is already running

It announces that a dependency is being *considered*, not that work is being done — which is the
opposite of what the wording suggests, and the reading an implementer would naturally take.

**`restart` has no special case of its own.** It is `stop`'s narration followed by `start`'s,
under one `RESTART` progress line — including the dependency walk, and including `is already
stopped` when there was nothing to stop.

*An earlier capture appeared to show `restart` printing `successfully stopped` for a service that
was down, which would have been a quirk worth copying. It was not: the service was up, because
the `stop` that was supposed to precede the case had silently failed. The re-probe captures
`check` immediately before each `restart` and shows the state the answer belongs to. **A probe
that does not capture its own precondition cannot tell you which question it answered.***

**No narration line carries trailing whitespace.** Worth stating because the `check` row's
trailing space *is* the contract and is documented as such, so house style here pulls the wrong
way. The captures can testify to this: `d2-probe.sh` renders through `cat -A` and strips only the
terminal `$`, so a trailing space survives into the log as a space — and it does, on the `check`
row captured in the same run:

    [  RUNNING            | rmscd2_batch (RMSC D2 batch) ]      <- trailing space present
    [Service 'RMSC D2 narrate' successfully started]            <- none

The control is the point: the method demonstrably shows a trailing space where one exists, so its
absence on every narration line is evidence rather than silence.

**The blank line is per-command on stdout and per-error on stderr**, and the asymmetry is real.
A command's narration ends with exactly one blank line however many services it touched; a group
operation that produced three errors wrote a blank line after **each** of them on stderr.

**`-q` does not suppress narration.** Measured on both `start` and `stop`, in both the
success and the already-in-that-state forms. `-q` is documented as suppressing *warnings*, and
these are not warnings — they go to stdout and they report success.

**The stop-side walk is measured now, with work actually done.** Dependent line, dependent
outcome, then the named service's outcome:

    Performing operation 'STOP' on service 'rmscg_base'
    Attempting to stop dependent service 'RMSC gap user'...
    Service 'RMSC gap user' successfully stopped
    Service 'RMSC gap base' successfully stopped

Until this capture every observation of that line came from a transcript where both services were
already down, so the order was composed rather than measured and "dependents first" could not be
told from "whichever came first in the collection". It can now.

### The fifth state, and three messages nobody had seen

`docs/parity.md` carries `Service '%s' is already partially running…` from the jar's catalogue and
this section did not mention it. Measured 3 September against a service with two criteria, one
satisfiable and one not — and the fifth state is **not** a fifth sibling of the four above:

| line | stream |
|---|---|
| `Service '<friendly>' is already partially running. You may need to restart if this operation fails.` | **stderr** |
| `WARNING: Service '<friendly>' only <n>/<m> started [failed to start --> [not running at -->JOBNAME:X]]` | **stderr** |
| `ERROR: Timed out waiting for service '<friendly>' to start` | stderr |
| `For details, see log file at: <path>` | **stdout** |

The four states in the table above are on stdout; **this one is on stderr**, with a different
shape. An implementation that grew `SCOUT_svc_state` by a fifth constant would put it on the wrong
stream.

`For details, see log file at: <path>` is a **stdout** line that is in no catalogue anyone had
read. It is the reason to probe a failure path rather than only a success path: three of these
four were invisible until a service was made to fail.

**It is not printed on every failure, and the gate is the LOG FILE HAVING CONTENT.**

This took three attempts to get right, and the two wrong ones are worth keeping because they were
wrong in instructive ways.

*First reading — "any failed start prints where to look."* The natural reading of a sentence
offering help after a failure. Contradicted by upstream immediately.

*Second reading — "the service was already partially running."* Measured, apparently carefully,
across three attempts of a half-up service and three of one that never comes up. **The fixture
moved two things at once:** the log gained content on the same attempt the service became partial,
so the partial-state rule and the log-content rule predicted identically on every row. The table
below was recorded as proof that the log file was *not* the gate, and it proved nothing of the
kind — the log existing is not the log having content.

*Third reading, and the measured one.* Review separated them with a service that **never runs**
and whose start command **prints one line** before failing:

| fixture | log file | upstream |
|---|---|---|
| never running, start command silent | 0 bytes | no line |
| never running, start command prints a line | 40 bytes | **the line** |
| half up, start command silent | 0 bytes | **no line** |

Row 2 is the one the partial-state rule cannot explain, and row 3 is the one it wrongly predicts.
There is no point telling anyone to read an empty file, which is what the rule amounts to.

**RMSC's log path carries no timestamp where upstream's does** — `~/.sc/logs/<svc>.log` against
`~/.sc/logs/2026-09-04-13.10.03.<svc>.log`. So this line cannot match upstream byte for byte even
with the gate right. That is a property of `SCLOG_path`, pre-dating all of this, and belongs with
the log-naming divergence rather than here.

**A single-service `start` that fails exits 253**, where a group start exits 0 whatever happens.
Both measured, and **RMSC already matched on both** — checked afterwards by review against a plain
timeout, a partial timeout, a dependency timeout and a failed restart.

**The trailing blank line follows the EXIT STATUS, not the command.** Upstream ends a
state-changing command with one blank line only when it exits 0; a failed single-service command
gets none. Measured by review across five failure scenarios, after a first implementation printed
it on both paths. A group command always exits 0, so it always gets the blank — which is why "one
blank per command" fitted every observation until a failing single-service command was looked
at.

**Bonus, and it settles an open item in the plan.** The same run captured `PARTIAL` live for the
first time:

    PARTIAL (1/2)      | rmscg_part (RMSC gap partial) [not running at -->JOBNAME:ZZNOSUCHJOB]

Exactly the shape the plan predicted from upstream's source — `String.format("PARTIAL (%d/%d)")`
padded to 18, then the `[not running at -->…]` suffix after the trailing space — and exactly what
RMSC does not do, returning a bare `PARTIAL`. This is **on the byte-exact `check` path**. It now
has a reproducible fixture, which is what it never had: no service on the box is ever half up.

**A service made PARTIAL by a FOREIGN process is reported differently.** Found by the tester while
building the log-detail fixtures, and not asserted anywhere — it is recorded here because nothing
else records it.

Where a service is partial because something *not started by sc* holds one of its criteria — a
listener belonging to another program on the port it checks — RMSC prints both
`Service '<f>' is already partially running…` and `WARNING: Service '<f>' only 1/2 started …` on
stderr, and **upstream prints neither**. Where the service is partial because its own earlier
start bound the port, both implementations print both.

So upstream appears to distinguish "half up because of me" from "half up because of something
else", and RMSC does not. Unmeasured beyond that one comparison, and not enough to say what the
rule is — but enough to say there is one.

**Upstream narrates a service it cannot find; RMSC does not.** `sc start <nonexistent>` prints
`Performing operation 'START' on service '<name>'` on stdout before failing. RMSC resolves the
name before it reaches the progress line, so it prints nothing. Found by review, measured, and
left as it is for now: it is harmless to a column-parsing consumer, and the accompanying stderr
difference (`Could not find definition for service 'x'` against RMSC's `sc: Unknown service x`)
is a pre-existing D2 row that should be closed with it rather than separately.

**`batch_mode: true` does not produce the `(asynchronously)` progress variant.** A batch service
starts, checks and stops with exactly the ordinary lines. Wherever that variant comes from, it is
not batch mode alone, and it stays `unmeasured`.

Failures during a group operation, on **stderr**, each followed by a blank line:

    ERROR: Timed out waiting for service '<friendly>' to start
    ERROR: Could not start dependency '<short>' for service '<friendly>': <the nested error verbatim>

The nested form embeds the whole inner message, `ERROR:` prefix included.

**The group operation exits 0 even when a member fails**, which `tools/error-delivery-test.sh`
already pins and warns must not be "fixed". Measured again here.

**Ordering within a group is plain sequence**, one member fully handled before the next begins.
The progress line comes from the dispatcher, the rest from the worker as it walks. Reading stdout
alone makes this look stranger than it is — the failures below were on stderr, and with them put
back the group start reads straight down:

    Performing operation 'START' on service 'rmscd2_dep'
      (stderr: ERROR: Timed out waiting for service 'RMSC D2 dependency' to start)
    Performing operation 'START' on service 'rmscd2_labels'
    Attempting to start service dependency 'rmscd2_dep' (RMSC D2 dependency)...
      (stderr: ERROR: Could not start dependency 'rmscd2_dep' for service 'RMSC D2 labels': …)
    Performing operation 'START' on service 'rmscd2_narrate'
    Service 'RMSC D2 narrate' is already running

*This paragraph first said the progress lines came first and the dependency line arrived out of
turn. That was an artefact of reading the two streams apart, and it is recorded here rather than
quietly deleted because it is the same mistake in miniature that `loginfo` records at scale:
**separating the streams shows you differences a merge hides, and hides orderings a merge shows**.
Neither view is the whole truth.*

A group stop does reach one member twice — once as a dependent of another member, once in its own
right — and says `is already stopped` both times. That one is real:

    Performing operation 'STOP' on service 'rmscd2_dep'
    Attempting to stop dependent service 'RMSC D2 labels'...
    Service 'RMSC D2 labels' is already stopped
    Service 'RMSC D2 dependency' is already stopped
    Performing operation 'STOP' on service 'rmscd2_labels'
    Service 'RMSC D2 labels' is already stopped
    Performing operation 'STOP' on service 'rmscd2_narrate'
    Service 'RMSC D2 narrate' successfully stopped

**Decided 3 September, and implemented.** `tools/error-delivery-test.sh` deliberately asserted
stdout carries no ERROR line rather than asserting stdout is empty, so that neither answer would
have to undo an assertion — and it did not have to. `tools/narration-test.sh` now pins the family
end to end.

RMSC's own failure texts in this area, aligned with the narration in the same change:

| RMSC (`SCEXEC`) | upstream | basis |
|---|---|---|
| `Could not start <short>: <reason>` | `ERROR: Could not start dependency '<short>' for service '<friendly>': <reason>` for the dependency case | measured |
| `<short> did not start within <n> seconds` | `ERROR: Timed out waiting for service '<friendly>' to start` | measured |
| `Stop command failed for <short>: <reason>` | — | unmeasured |
| `<short> did not stop within <n> seconds` | — | unmeasured |
| `<short> did not stop, even immediately` | — | unmeasured |
| `No stop_cmd defined` (`SCLAUNCH`) | — | unmeasured; upstream's `No start command specified for service '%s'` may be unreachable through YAML, since a definition without `start_cmd` is rejected at load time |

## Four defects the fixture pack found on its first run

The pack in `tools/gate-fixtures/` has never been part of any routine verification — it has its
own runner, which nothing calls. Running it found two differences, both on **stderr**, both
repeated on every one of its 54 comparisons, and neither reachable by anything on the machine.
Review then found two more while checking the fixes for those, which is why this section lists
four — only the first two came from the pack's own first run.

**1. A job name reached through `check_alive_criteria:` must NOT be upper-cased.**

    check_alive: jobname
    check_alive_criteria: qp0zspwp

    upstream  Check-alive conditions: JOBNAME:qp0zspwp     <- as written
    RMSC      Check-alive conditions: JOBNAME:QP0ZSPWP     <- upper-cased

Upstream upper-cases a job name given directly as `check_alive: qp0zspwp`, and does **not**
upper-case one arriving through the companion key. RMSC upper-cases both.

The consequence is worse than the rendering. RMSC normalises two differently-spelled criteria onto
one, decides two services claim it, and emits a **conflict warning naming services that do not
conflict** — on every `check`, `list`, `groups` and `info`. Upstream stays silent because to it
the two criteria are different.

This also reconciles with the earlier measurement that job names differing only in case DO
conflict: that was two definitions both using `check_alive:` directly, so both were upper-cased
and genuinely collided.

**2. A name ending `rpmnew` is skipped SILENTLY**, and the rule is

    name.toLowerCase().endsWith("rpmnew")

Measured over thirteen filenames, and **three things about it are not what they look like**. A
first implementation, written from ten filenames, got all three wrong:

| | |
|---|---|
| it is **case-insensitive** | `x.YAML.RPMNEW`, `x.RPMnew`, `x.yaml.RpMnEw` are silent |
| there is **no dot** in it | bare `rpmnew`, `foorpmnew` and `x_rpmnew` are silent too — the suffix is `rpmnew`, not `.rpmnew` |
| the name is **not trimmed** | `x.yaml.rpmnew ` with a trailing blank **warns**, because the blank is part of the name |

Upstream **does** warn about `.rpmsave`, `.bak`, `.orig`, `~`, `.disabled`, `.swp`, `.old`,
`.rpm-new`, `.rpmnew.bak` and `.rpmnewer`. So it is one suppression of a package-manager
artefact, not a general backup-extension rule — guessing from `.rpmnew` alone gives
"backup-ish extensions are quiet", which fits every observation of it and gets `.rpmsave` wrong.

The trailing-blank row is the one worth keeping in mind: it is the only case where a wrong
implementation is **silent where upstream warns**, so a test that only checks "the rpmnew ones are
quiet" cannot catch it.

Both implementations load the identical set of services either way; the difference is only the
warning.

**3. `info` rendered a criterion from the parsed fields rather than from the criterion text**,
and was wrong three ways at once: a job name longer than **ten** characters was truncated,
because a `*JOB` name field holds ten and the criterion text does not; a `PGM-` criterion
rendered as `PGM:x` where upstream says `JOBNAME:PGM-X`; and a port rendered from the converted
number, so a criterion upstream shows as `PORT:abc` would have appeared as `PORT:0`.

Three independent driftings in one duplicated renderer, which is what the note beside
`SCOUT_only_started` predicts about two renderings of one thing in one codebase.

**4. And a truncation hidden behind that truncation.** With `info` fixed, `SCDEF_criterion_text`
turned out to truncate at **56** characters of criterion: its return type was 64 wide and
`'JOBNAME:'` plus a 64-character criterion is 72. The test asserting that a twenty-character job
name "renders whole" sat below both caps and could never have failed.

**Ports follow the same direct-versus-companion rule as job names**, which is the part that was
missed when the job-name rule was found. `check_alive: 08080` renders `PORT:8080` — normalised —
and `check_alive: port` + `check_alive_criteria: 08080` renders `PORT:08080`, verbatim. It matters
beyond the rendering: to upstream a service on `08080` and one on `8080` claim **one** criterion
and conflict, so keeping them distinct means staying silent about a real collision.

## The read-only operations

`check`, `list` and `groups` are byte-exact and are not in this document. The four the gate calls
`undecided` are here.

### `info`

**Measured 3 September** against two staged definitions — one carrying dependencies, groups and
environment variables, one minimal — so every label below was produced rather than inferred. This
supersedes the earlier reading from `local/baseline-operations.txt`, which could not attribute
blank lines because the capture script wrote its own.

The separator is 69 dashes on both sides and most labels match. Eight differences:

| | upstream | RMSC |
|---|---|---|
| blank lines before the separator | **two** | one |
| blank lines after the name line | **two** | one |
| `Working Directory:` | **not printed at all** when `dir` is unset | always printed, resolved |
| `Batch Mode:` when not batch | `Batch Mode: <not running in batch>` | nothing |
| dependencies | `Depends on the following services:` then one indented entry per line | `Depends on: <name>`, one line each |
| groups | not printed | one `Group: <name>` line each |
| environment | `Inherits environment variables?: <bool>` always, then `Custom environment variables:` and one indented `NAME=value` per line when any are set | neither |
| closing separator | a second 69-dash line, then **three** blank lines | nothing — the block is opened and never closed |

Two of those are worse than the "formatting" label suggests. **`Working Directory:` is a line
upstream omits and RMSC invents**, so RMSC prints a line upstream does not for every definition
that does not set `dir` — the common case. And **`Depends on the following services:` is a
different shape**, not a different spelling: upstream prints one header and indents the list,
RMSC repeats a label per dependency.

The full upstream shape, from the staged definition that exercises every branch:

    <blank>
    <blank>
    ---------------------------------------------------------------------
    <short> (<friendly>)
    <blank>
    <blank>
    Defined in: <path>
    <blank>
    Startup Command: <cmd>
    Startup Wait Time (s): <n>
    <blank>
    Shutdown Wait Time (s): <n>
    <blank>
    Check-alive conditions: PORT:<n>
    Batch Mode: <not running in batch>
    <blank>
    Depends on the following services:
        <name>
    <blank>
    Inherits environment variables?: true
    Custom environment variables:
        NAME=value
    ---------------------------------------------------------------------
    <blank>
    <blank>
    <blank>

`Shutdown Command:` is absent when `stop_cmd` is unset, which is what RMSC already does.

### `jobinfo`

A structural difference rather than a wording one. **Measured 3 September.**

    upstream:  <short> (<friendly>):
                   <job 1>
                   <job 2>
               <blank>

    RMSC:      <short>: <job 1>
               <short>: <job 2>

Upstream prints a header naming the service in `short (friendly)` form, indents each job by four,
and ends with a blank line; RMSC repeats the short name on every line, indents nothing and ends
without one. Both on stdout, exit 0.

### `loginfo` — the difference is the STREAM, and it was hidden

`docs/parity.md` records this as "one trailing blank line. One line of code either way." **That is
wrong, and the way it came to be wrong is the interesting part.**

Measured 3 September, with the streams kept apart:

| | upstream | RMSC |
|---|---|---|
| stdout | a single blank line | the whole message |
| stderr | `<name>: <unknown> (try checking in log directory <dir>)` | nothing |

**CORRECTED 9 September 2026 — this was measured on one state and generalised, which is the very
mistake the paragraph below complains about.**

Both readings above were taken on a service with **no log file** — the only state reachable
without staging and starting one, and the state in which *both* implementations fail to find a
log. With a service started for the purpose, upstream prints to **stdout** when it finds one, and
the text does **not** match:

| state | upstream | RMSC before |
|---|---|---|
| log found, empty | stdout `<name>: <path> (no data)` | stdout `<name>: <path> (0 bytes)` |
| log found, has data | stdout `<name>: <path>` — nothing after it | stdout `<name>: <path> (15 bytes)` |
| no log found | stderr, as recorded above | stdout |
| all three | one trailing blank line on stdout | none |

The rule is **found to stdout, not found to stderr**. RMSC matches all four as of 9 September
2026, covered by `tools/loginfo-test.sh` with the streams kept apart — the gate structurally
cannot, which is how this stayed wrong for six days. `docs/parity.md` carries the full account and
the three things deliberately left alone.

`tools/fidelity-gate.sh:135` merges stderr into the comparison with `2>&1`, so a line that moved
from one stream to the other looks identical to the gate — and the only residue is a blank line
in a different place, which is precisely what got written down. **A merged comparison cannot see a
stream difference**, and this is the first measured instance of it hiding one. Everything else the
gate reports as a formatting difference on a stream-merged operation should be re-read with that
in mind.

Which stream is right is not obvious and is a decision, not a defect: this is a *report*, not a
warning, and `-q` has nothing to say about it. But it is upstream's behaviour, and RMSC's whole
premise is that a consumer can parse stdout.

RMSC additionally reports spooled files for a batch service, indented by four. Whether upstream
does is still `unmeasured` — the service probed had none.

### `perfinfo`

**Measured 3 September, and the gap is larger than the line counts suggested.** Upstream prints,
on stdout:

- `Gathering performance information...`, then a blank line
- a 69-dash separator and the `<short> (<friendly>)` header, as `info` does
- **per job**: a `Job: <job>` line, then roughly thirty indented labelled fields
- a closing separator and two blank lines

The fields are not RMSC's fields renamed. Upstream reports the job's *attributes* alongside its
measurements — `Run priority (RUNPTY)`, `Time slice in milliseconds (TIMESLICE)`,
`Eligible for purge (PURGE)`, `Default wait time in seconds (DFTWAIT)`, `Maximum CPU time in
milliseconds (CPUTIME)` with an indented `CPU time used:` beneath it, `Maximum temporary storage
in megabytes (MAXTMPSTG)` with `Temporary storage used:` and `Peak temporary storage used:`,
`Maximum threads (MAXTHD)` with `Threads:`, `Thread resources affinity (THDRSCAFN)` with `Group:`
and `Level:`, `Resources affinity group (RSCAFNGRP)`, `->Sampling time (s)`, `CPU Usage (%)`,
`Current User`, `Disk I/O operations during sampling time`, `Function`, `Job Status`,
`Job active since`, `Malloc'ed Memory estimate (Kb)`, `Total Disk I/O operations`, and seven
`Java …` fields where the job runs a JVM.

RMSC prints five of these under different names and three JVM figures. So closing this is a
**query** change, not a formatting one: it needs the attribute columns as well as the performance
columns. `docs/parity.md` is right that the plan's "drops the Python 3 + `ibm_db` dependency"
never authorised printing less.

#### Settled 8 September 2026 — the mechanism, and three corrections to the above

**Upstream scrapes `DSPJOB OPTION(*RUNA)`.** `docs/parity.md` carries the evidence and Richard's
decision that RMSC will not. The consequence for this section is that the three affinity lines —
`Thread resources affinity (THDRSCAFN)` with `Group:` and `Level:`, and
`Resources affinity group (RSCAFNGRP)` — are **not reachable from QUSRJOBI** and RMSC omits them.
Sixty-three lines where upstream prints sixty-six, recorded as a deliberate departure.

**Correction: this document's claim that upstream "thousands-separates the Java figures" is
wrong**, and the truth is finer. The split is per FIELD, not per type. Measured on a live JVM
service, in the same block:

    Java GC Total Time (ms): 1306          <- no separator
    Java Heap In Use (Kb): 66,730          <- separator
    Total Disk I/O operations: 1860        <- no separator

Separated: `Java Heap Current Size (MB)`, `Java Heap In Use (Kb)`,
`Java Heap Maximum Size (Kb)`, `Java JIT Memory (KB)`, `Java Shared Class Size (Kb)`,
`Malloc'ed Memory estimate (Kb)`. Everything else plain — the two GC figures and both disk I/O
counts included. Every one of those has a value above 999 in the capture, so each is separable
from its rival rather than merely consistent with it.

**`Java Heap Current Size (MB)` is mislabelled by upstream.** The value is kilobytes — 262,144
beside a maximum of 16,777,216 Kb. RMSC reproduces the wrong label verbatim, because parity is
the goal and a consumer may be matching on it.

**The order of the sampled block is alphabetical by label**, because upstream builds it in a
sorted map, and `->Sampling time (s)` sorts first precisely because of the arrow. `Job Status`
precedes `Job active since` for the same reason — uppercase sorts before lowercase. Reordering
these lines is a parity defect even when every value is present.

**The not-running form is eight lines**, byte-confirmed: the header, a blank, the rule, the
`<short> (<friendly>)` title, `NOT RUNNING` with **no blank line before it**, the rule, and two
blank lines.

#### One more line upstream emits and RMSC did not — the sample-time warning

    WARNING: Value specified for sample time argument is not valid: --sampletime=abc

On **stderr**, exit 0, once per invocation however many jobs the service has, suppressed by `-q`,
and it names the **whole argument** rather than just the offending value. Emitted for any value
that is not a number, the empty `--sampletime=` included; upstream then samples for one second.

RMSC now matches this, and `--sampletime` accepts the decimal form upstream documents. Before
this it took whole numbers only and discarded anything else without a word, so the documented
`x.x` spelling sampled for one second and reported that it had. `docs/parity.md` carries the full
measured table and the two rows where RMSC deliberately does not follow upstream into failing.

Two details that will matter when it is written: upstream **thousands-separates** the Java figures
(`262,144`) and not the others, and `->Sampling time (s)` really does carry that arrow.

### `scrunattrs` — settled, and not D2 work

Recorded here only so nobody reopens it. Upstream reports per running job:

    <name>: <job>:
        <unknown>

RMSC reports the `SCOMMANDER_` environment it would build, from `SCLAUNCH_build_env`.
`docs/parity.md` § "Differences that are intentional" records this as a **deliberate choice of
the plan** — *"`scrunattrs` — `SCOMMANDER_*` vars from the running job"* — not a difference to
close.

## The usage block, verbatim

Captured 3 September from `sc` 1.7.1 with `tools/d2-probe.sh`. Byte-identical from `sc`,
`sc <unknown operation>`, `sc <operation with no service>`, `sc -h` and `sc --help`. **On stderr,
exit 255, with stdout empty.** Indentation is spaces throughout; note the **two** spaces after
`sc` on the first line, and that there is no blank line between the operations list and the
`Valid formats` heading where there is one before it.

```
Usage: sc  [options] <operation> <service>

    Valid options include:
        -v: verbose mode
        -q: quiet mode (suppress warnings). Ignored when '-v' is specified
        --disable-colors: disable colored output
        --splf: send output to *SPLF when submitting jobs to batch (instead of log)
        --sampletime=x.x: sampling time(s) when gathering performance info (default is 1)
        --ignore-globals: ignore globally-configured services
        --ignore-groups=x,y,z: ignore services in the specified groups (default is 'system')
        --all/-a: don't ignore any services. Overrides --ignore-globals and --ignore-groups

    Valid operations include:
        start: start the service (and any dependencies)
        stop: stop the service (and dependent services)
        kill: stop the service (and dependent services) forcefully
        restart: restart the service
        check: check status of the service
        info: print configuration info about the service
        jobinfo: print basic performance info about the service
        perfinfo: print basic performance info about the service
        loginfo: get log file info for the service (if running)
        list: print service short name and friendly name
        groups: print an overview of all groups
    Valid formats of the <service(s)> specifier include:
        - the short name of a configured service
        - A special value of "all" to represent all configured services (same as "group:all")
        - A group identifier (e.g. "group:groupname")
        - the path to a YAML file with a service configuration
        - An ad hoc service specification by port (for instance, "port:8080")
        - An ad hoc service specification by job name (for instance, "job:ZOOKEEPER")
        - An ad hoc service specification by subsystem and job name (for instance, "job:QHTTPSVR/ADMIN2")
```

Reproduce it exactly. Every line of it is somebody's expectation.

## What this leaves

Ordered by size rather than by importance:

1. ~~**`perfinfo`**~~ — **done, 8 September 2026.** It was a query change, as this said. RMSC now
   reads the attributes from `QUSRJOBI` and the sampled figures from SQL, and prints sixty-three
   of upstream's sixty-six lines; the three it omits are the affinity values, which no API
   carries. See `docs/parity.md`.
2. **The usage block** — now measured verbatim, 33 lines, wanted by four rows and by D3. Large to
   type, trivial to get right.
3. **`info`** — eight differences, of which two are shape rather than spelling: the dependency
   header, and a `Working Directory:` line RMSC invents for every definition that does not set
   `dir`.
4. ~~**Narration**~~ — **decided and implemented, 3 September 2026.** RMSC narrates. See
   `docs/parity.md`.
5. **The load-failure split into two lines** — fixes the wording and `-q` together.
6. ~~**`loginfo`'s stream**~~ — **done, 9 September 2026.** It was not one line of code: four
   differences, of which the stream was one, plus three items deliberately left open. See
   `docs/parity.md`.
7. ~~**`jobinfo`'s header, indentation and trailing blank line**~~ — **done, 10 September 2026.**
   Five differences, not three: the two above plus the not-running text and the colour, and the
   blank line turned out to be per COMMAND. See `docs/parity.md`.
8. **The command-line texts** — ten one-line changes, each trivial, none urgent, `--version`
   among them.
9. **The `sc: ` prefix, and short-versus-friendly naming** — two decisions that touch many rows.
   The prefix is now measured: upstream has none.

`scrunattrs` and `file` are **not** on this list: both are intentional divergences the plan
chose, recorded in `docs/parity.md`.
