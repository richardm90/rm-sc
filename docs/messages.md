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

## Narration — the family RMSC does not have

**Measured 3 September** with `tools/d2-probe.sh --narrate`, against a staged service that
genuinely comes up — its start command binds the port it is checked on, so `successfully started`
is the real message and not a timeout misread as one. **All on stdout, exit 0, with one trailing
blank line after each command.**

| observed | upstream |
|---|---|
| progress, every operation | `Performing operation 'START' on service '<short>'` — verb **upper-cased**, **short** name |
| started | `Service '<friendly>' successfully started` |
| stopped | `Service '<friendly>' successfully stopped` |
| already up | `Service '<friendly>' is already running` |
| already down | `Service '<friendly>' is already stopped` |
| restart | one progress line, then `successfully stopped`, then `successfully started` |
| start-side dependency | `Attempting to start service dependency '<short>' (<friendly>)...` |
| stop-side dependent | `Attempting to stop dependent service '<friendly>'...` |

**The two dependency lines are not symmetrical.** The start side names the service twice, short
then friendly in parentheses; the stop side names it once, friendly only. That is upstream's
behaviour, not a transcription slip, and anyone implementing this from the table above will get it
wrong by making them match.

**`kill` on a stopped service says `is already stopped`,** exactly as `stop` does — it does not
say `ERROR: No running jobs for service '%s'`. Where that message comes from is still `unmeasured`;
it is in the jar's catalogue but nothing probed reaches it.

Failures during a group operation, on **stderr**, each followed by a blank line:

    ERROR: Timed out waiting for service '<friendly>' to start
    ERROR: Could not start dependency '<short>' for service '<friendly>': <the nested error verbatim>

The nested form embeds the whole inner message, `ERROR:` prefix included.

**The group operation exits 0 even when a member fails**, which `tools/error-delivery-test.sh`
already pins and warns must not be "fixed". Measured again here.

**Ordering within a group is worth reading twice.** A group start printed its progress lines for
every member first, and the dependency line arrived *after* the progress line of the service that
needed it:

    Performing operation 'START' on service 'rmscd2_dep'
    Performing operation 'START' on service 'rmscd2_labels'
    Attempting to start service dependency 'rmscd2_dep' (RMSC D2 dependency)...
    Performing operation 'START' on service 'rmscd2_narrate'
    Service 'RMSC D2 narrate' is already running

A group stop reached one member twice — once as a dependent of another member, once in its own
right — and said `is already stopped` both times. Neither of these is something a reasonable
implementation would arrive at independently, so both need copying rather than deriving.

**This is still a decision, not a defect list.** It is recorded as undecided in `docs/parity.md`,
and `tools/error-delivery-test.sh` deliberately asserts stdout carries no ERROR line rather than
asserting stdout is empty, so neither answer has to undo an assertion.

RMSC's own failure texts in this area, which would need aligning at the same time:

| RMSC (`SCEXEC`) | upstream | basis |
|---|---|---|
| `Could not start <short>: <reason>` | `ERROR: Could not start dependency '<short>' for service '<friendly>': <reason>` for the dependency case | measured |
| `<short> did not start within <n> seconds` | `ERROR: Timed out waiting for service '<friendly>' to start` | measured |
| `Stop command failed for <short>: <reason>` | — | unmeasured |
| `<short> did not stop within <n> seconds` | — | unmeasured |
| `<short> did not stop, even immediately` | — | unmeasured |
| `No stop_cmd defined` (`SCLAUNCH`) | — | unmeasured; upstream's `No start command specified for service '%s'` may be unreachable through YAML, since a definition without `start_cmd` is rejected at load time |

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

The **text matches exactly**. It is on the other stream.

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

1. **`perfinfo`** — the largest by far, and the only one that is not a text change. Upstream
   reports the job's *attributes* beside its measurements; RMSC queries neither. A query change.
2. **The usage block** — now measured verbatim, 33 lines, wanted by four rows and by D3. Large to
   type, trivial to get right.
3. **`info`** — eight differences, of which two are shape rather than spelling: the dependency
   header, and a `Working Directory:` line RMSC invents for every definition that does not set
   `dir`.
4. **Narration** — a decision of Richard's; ten-odd new lines on stdout if yes.
5. **The load-failure split into two lines** — fixes the wording and `-q` together.
6. **`loginfo`'s stream** — one line of code, and a decision about which stream a *report* belongs
   on.
7. **`jobinfo`'s header, indentation and trailing blank line** — shape.
8. **The command-line texts** — ten one-line changes, each trivial, none urgent, `--version`
   among them.
9. **The `sc: ` prefix, and short-versus-friendly naming** — two decisions that touch many rows.
   The prefix is now measured: upstream has none.

`scrunattrs` and `file` are **not** on this list: both are intentional divergences the plan
chose, recorded in `docs/parity.md`.
