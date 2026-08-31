# RMSC Performance Record

Two SQL table functions, replaced.

RMSC reimplements IBM i Service Commander in RPGLE. The project's premise was that removing
the JVM and the `db2util` fork would make it substantially faster. Measured, that premise did
not hold — and what actually closed the gap was replacing two `QSYS2` table functions with the
system APIs underneath them.

| | |
|---|---|
| **System** | IBM i 7.5, 0.25-core shared LPAR |
| **Baseline captured** | 29 August 2026 |
| **Latest figures** | 30 August 2026 |
| **Re-verified** | 31 August 2026 — section 9 |
| **Suites** | 144 cases / 578 assertions |

> Sections 1-8 are from measurements taken and recorded during the work itself. Section 9 is an
> independent re-run made afterwards, on 31 August 2026. Section 10 gives the commands for both.

---

## 1. Where it ended up

| | |
|---|---|
| **Port check** | **540x** — 376,464 µs to 693 µs per call, `NETSTAT_INFO` to `QtocLstNetCnn` |
| **Job lookup** | **19%** — about 125 ms per call, `ACTIVE_JOB_INFO` to `QUSLJOB` |
| **`scr check`, end to end** | **1.59s** median, from ~2.95s as first written |
| **Java `sc check`** | ~3.4s — unchanged throughout, the reference point |

Progression of `check`, all services:

| Stage | Elapsed |
|---|---|
| Java `sc check` — the thing being replaced | 3.49s |
| RMSC, as first written — ILE rewrite alone | 2.95s |
| After `QtocLstNetCnn` — port status via system API | 1.97s |
| After `QUSLJOB` — job lookup via system API | **1.59s** |

The two rewrites that mattered were not language changes. The ILE rewrite on its own bought
about 20%. Replacing the two table functions took `check` from roughly 2.95s to 1.59s.

---

## 2. The baseline

Captured before any RMSC code existed, so the comparison had a fixed reference.

Java `sc check` was timed over SSH with `TIMEFORMAT='%3R'`, so each figure includes the round
trip. Output fixtures for `check`, `list` and `groups` were captured at the same time and
became the byte-exact comparison targets used at every gate since.

| Command | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| `sc check` (all services) | 3.036s | 3.525s | 3.579s |

Three services are displayed by a default `check`. The `groups` fixture lists `system` even
though `check` excludes it via the default `--ignore-groups=system`; both behaviours had to be
reproduced exactly.

### How the baselines were captured

Phase 0, before a line of RMSC existed — so nothing in this project could have influenced what
they record (`$HOST` as set in section 10):

```bash
ssh $HOST "export QIBM_MULTI_THREADED=Y; sc check"  > baseline-check.txt
ssh $HOST "export QIBM_MULTI_THREADED=Y; sc list"   > baseline-list.txt
ssh $HOST "export QIBM_MULTI_THREADED=Y; sc groups" > baseline-groups.txt
ssh $HOST "export QIBM_MULTI_THREADED=Y; TIMEFORMAT='%3R'; time sc check >/dev/null"
```

| File | Captured from | What it pins |
|---|---|---|
| `baseline-check.txt` | `sc check` | **The format-critical one** — `\|` at column 22, three services |
| `baseline-list.txt` | `sc list` | `name (description)` — no status, no leading spaces |
| `baseline-groups.txt` | `sc groups` | Group names only, alphabetical, and it includes `system` |
| `baseline-operations.txt` | `sc info`, `file`, `jobinfo`, `loginfo`, `scrunattrs` | Reference for the operations outside the byte-exact gate |

Two things about these are easy to trip over later.

**They were captured under whichever profile was signed on at the time.** `check`, `list` and
`groups` carry no paths, so they stay directly comparable under any profile.
`baseline-operations.txt` does **not** — `loginfo` prints a log directory under the capturing
user's home, so comparing it against a run under a different profile needs that path
normalised first. This is one reason `tools/fidelity-gate.sh` compares those operations live
against upstream rather than against this file.

**They describe *this* system.** Service names and description lengths differ elsewhere, so
the client's equivalents must be captured separately before any rollout there — a format
assertion derived from one machine's output proves nothing about another's.

---

## 3. The premise, tested

The first full comparison, once RMSC could run every operation.

Each figure is three consecutive runs inside one SSH session, so connection setup is excluded.
Every route was verified to produce the same three service rows before being timed — an
earlier reading of "40x faster" turned out to be a command-not-found returning quickly.

| Command | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| `sc check` — Java | 3.673 | 3.412 | 3.376 |
| `scr check` — RMSC | **2.929** | **2.909** | **3.013** |
| `sc list` — Java | 0.573 | 0.885 | 1.018 |
| `scr list` — RMSC | *1.419* | *1.336* | *1.309* |

RMSC won `check` by about 20%. It **lost** `list` — which runs no system queries at all — by
about 50%. That single row is what redirected the project, because it isolated definition
loading as a cost independent of anything the JVM or `db2util` were doing.

---

## 4. Where the time actually went

`list` is pure definition loading. Both implementations parse **39 definitions on every
invocation**, of which a default `check` displays 3 — the other 36 are in the `system` group
and are discarded *after* being read.

| Component | RMSC | Java |
|---|---|---|
| Loading 39 definitions | *~1.3s* | ~0.8s |
| Liveness queries for 3 services | ~1.6s | ~1.6s |

Two conclusions follow, and both contradicted the plan. The JVM cold start is smaller than
assumed. And the `db2util` fork is not what dominates query time — the IBM i services
themselves are. `ACTIVE_JOB_INFO` and `NETSTAT_INFO` cost what they cost, whether reached
through a forked process or embedded SQL in-job.

That is what made the two API replacements worth doing, and it is also why batching the
queries was rejected: it would have made the symptom smaller without touching the cause.

---

## 5. Change one — port status

`QSYS2.NETSTAT_INFO` to `QtocLstNetCnn`, in a new `SCNET` module.

The port check was the single most expensive thing RMSC did: **376 ms per call**, twice the
cost of a job lookup, and `check` makes one per port criterion.

The evidence that the table function — not the enumeration — was the cost came from four
measurements against a table holding 88 connections:

| Query | Elapsed |
|---|---|
| Filtered count, one port | 0.42–0.53s |
| Count of everything | 0.42–0.45s |
| Every row, every column | 0.27–0.55s |
| PASE `netstat -an`, same data, incl. process fork | **0.073–0.110s** |

The filter made no difference and returning everything cost no more, while a forked PASE
process produced the same data five times faster. The time was the SQL table function layer.
`QtocLstNetCnn` asks the TCP/IP stack directly and skips it.

### What changed in the code

| | |
|---|---|
| **API** | `QtocLstNetCnn`, from service program `QTOCNETSTS`; threadsafe per IBM's documentation |
| **Formats** | `NCNN0100` (IPv4), `NCNN0200` (IPv6) |
| **Qualifiers** | `NCLQ0100` / `NCLQ0200` |
| **Mechanism** | Results are returned into a user space and read through the standard generic list header — offset to list data at 125, entry count at 133, entry size at 137, status at 104 — rather than fetched through a cursor |
| **Failure behaviour** | `SCNET_port_listening` returns a distinct third value for "could not answer", and `SCQRY_port_listening` then falls back to the original SQL. Being slow is recoverable; reporting a running service as down is not |

| `SCQRY_port_listening`, per call | Before | After |
|---|---|---|
| Port listening | 376,464 µs | **693 µs** |
| Port not listening | 359,076 µs | **524 µs** |

### The defect this nearly shipped with

`NCNN0100` is IPv4 only, so IPv6 had to be checked too. The IPv6 qualifier's address fields
are declared character but must hold **binary nulls** to mean "every address"; `clear` leaves
them as blanks. The API accepted that and returned an **empty list with no error** — so every
IPv6-only service would have been reported as stopped.

It survived because it was untestable: every service on this system binds both families, so
the IPv4 probe always answered first and the IPv6 path never ran. `SCNET_port_listening` now
takes an optional address family so the suite can exercise each directly, and the tests open
their own IPv6-only socket rather than depending on a listener someone remembered to start.

The fallback earned its place during development too: a malformed user space name made the
API return `TCP84C5` on every call, and RMSC kept working correctly — just at the old speed —
until the cause was found.

---

## 6. Change two — job lookup

`QSYS2.ACTIVE_JOB_INFO` to `QUSLJOB`, in a new `SCJOB` module.

With the port check dealt with, `ACTIVE_JOB_INFO` was the largest remaining cost — about
**177 ms per call, three calls per `check`** — which was essentially all of the remaining time
in the bound-call path.

This one was measured as a true A/B: the service program was rebuilt with the delegation
switched off, timed, then rebuilt with it on and timed again, so both routes ran on the same
system in the same state. Twelve runs each way.

| `scr check` | Min | Median | Max |
|---|---|---|---|
| `ACTIVE_JOB_INFO` | 1.85s | 1.97s | 2.06s |
| `QUSLJOB` | **1.43s** | **1.59s** | **1.92s** |

About **0.38s, or 19%** — roughly 125 ms per lookup. Real, and the ranges barely overlap, but
a long way short of the 540x the port change gave. The reason is structural: `QUSLJOB` still
builds a user space and the generic list header still has to be walked, whereas
`QtocLstNetCnn` answers a much narrower question.

### What changed in the code

| | |
|---|---|
| **API** | `QUSLJOB`, format `JOBL0100`, 56-byte entries |
| **Entry layout** | job name 1–10, user 11–20, number 21–26 |
| **Filtering** | The qualified job name is a 26-character field — name, then `*ALL` for user, then `*ALL` for number — with status `*ACTIVE`. The API filters by name itself, so nothing is filtered in RPG |
| **Authority** | `*JOBCTL`, inherited via the group profile |
| **Failure behaviour** | Returns `SCJOB_UNAVAILABLE` (-1), and `SCQRY_jobs_by_name` falls through to the original SQL — the same pattern as the port check |
| **Verification** | `SCJOB.TEST` asserts the two routes name the *same jobs*, not merely the same number of them. A wrong offset here returns a plausible wrong answer, not an error |

**Only the bare job-name form uses the API.** `JOBL0100` cannot filter by subsystem, so
`SBS/JOB` stays on SQL, and so does the `PGM-` criterion. That still covers the whole hot
path: all three services on a default `check` use bare names, the six subsystem-qualified
definitions are all in the `system` group, and the single `PGM-` definition is filtered out by
`only_if_executable`.

Both could move later using `JOBL0200`'s keyed fields — key **1906** subsystem description
(qualified), **601** function name, **602** function type. That means parsing variable-length
keyed data rather than a fixed record, for paths that are rarely exercised, so it is not
obviously worth it.

### The mistake this change caused

`RMSC.BND` pins `SIGNATURE('RMSC 0.1.0')`. Adding the two new exports in the **middle** of the
export list broke seven of the eleven test suites — every test in them failing with `RNX0115`,
on code that had not changed.

With a fixed signature the binder has nothing to complain about, but inserting an export
shifts every export after it by one position, and already-compiled callers then reach the
wrong procedure. The order of that list is the contract. The exports now go at the end, and
the file says so — nothing else made it visible until it bit.

---

## 7. The bound-call API

Measured separately, because it removes costs the command line cannot.

The API was expected to be dramatically faster, on the reasoning that a caller already inside
a job pays for no process, no job and no definition load. The first version was not: it called
`SCCOLL_load` on every call and re-read all 39 definitions.

| `SC_check_all` | Per call |
|---|---|
| Reloading definitions each time | 2.64s |
| Definitions cached for the activation | 1.78s |
| …then after `QtocLstNetCnn` | **0.76s** |
| Java `sc check` via PASE | ~3.4s |

Twenty calls in one job took 35.7s, so the marginal cost really is flat — the first call pays
for the load and the rest do not. Live status is deliberately **not** cached: every call
re-queries the system, because that is the question being asked. `SC_refresh()` drops the
cached definitions when a file has changed.

The stronger argument for the API was never speed. It is that the consumer stops parsing text
by column position, so a format change can no longer make services silently disappear from a
screen.

---

## 8. What is not done

With both API replacements in, **definition loading is the dominant cost again** — and it is
the one place RMSC is measurably slower than Java. A default `check` parses 39 definitions to
display 3, so skipping the ignored groups during discovery would avoid roughly 90% of the
parsing.

The care is in the exceptions rather than the idea:

- `group:` and `-a` still need every definition, so the filter cannot be unconditional.
- Dependency resolution can reach an excluded service, since an ignored service can be a
  dependency of a visible one.
- `groups` derives its answer from definitions the filter would drop.

The risk is not being slower — it is quietly showing a *different set of services*. Any
attempt has to re-run the byte-exact `check`, `list` and `groups` comparisons against the
captured fixtures.

Two other options were considered and set aside. Batching the queries was rejected as hiding
the problem rather than solving it. Caching parsed definitions on file modification time is
the most complex option and the one most likely to be wrong in a way nobody notices.

One further API is identified but not needed yet. `QtocRtvNetCnnDta` is the right call for
finding which jobs hold a connection, which is what `stop` and `jobinfo` need — but it is not
on the `check` path, so it buys nothing against the figures above.

---

## 9. Re-verified, 31 August 2026

An independent re-run of the headline figures against the deployed build, using the commands in
section 10. Nothing here changes a conclusion above. It establishes that they still hold, shows
where the numbers have moved since, and retracts one observation that did not survive contact
with a third sample.

### Confirmed first

| | |
|---|---|
| **Build under test** | `SCNET` 2026-08-30-12.19.04, `SCQRY` 14.04.16, `SCJOB` 14.17.08, bound into `RMSC.SRVPGM` — both API replacements present in the objects actually being timed |
| **Output fidelity** | `check`, `list` and `groups` byte-identical to the captured Java fixtures |
| **Colour** | 0 ANSI escapes with stdout not a terminal |

### Three samples

Twelve runs each, `QIBM_MULTI_THREADED=Y`, same LPAR.

| `scr check` — RMSC | Min | Median | Max |
|---|---|---|---|
| Recorded, section 6 | 1.43s | **1.59s** | 1.92s |
| Sample A | 1.53s | 1.62s | 3.05s |
| Sample B | 1.48s | 1.645s | 1.83s |
| Sample C | 0.86s | 1.40s | 2.34s |

| `sc check` — Java | Min | Median | Max |
|---|---|---|---|
| Recorded, sections 2-3 | — | **~3.4s** | — |
| Sample A | 3.70s | 3.98s | 4.46s |
| Sample B | 3.63s | 4.115s | 17.66s |
| Sample C | 4.05s | 4.425s | 5.23s |

RMSC reproduces its recorded figure in all three samples. Java does not — it is consistently
slower than when it was baselined on 29 August, by roughly 0.6 to 1.0s.

**This matters for how the comparison is quoted.** Measured today the ratio is 2.5x to 3.2x,
against the 2.19x in section 1. The difference is Java having got slower, not RMSC having got
faster, so **section 1's figure remains the honest one**. A single twelve-run sample on a
0.25-core shared LPAR moves 20% either way; no ratio quoted from one sample is worth defending.

### Sample C in full

Sample C interleaved the two routes so both met identical system conditions, and kept every run
rather than a summary. It is recorded in full because the summaries are what misled the first
attempt.

| Round | `scr check` | `sc check` |
|---|---|---|
| 1 | 0.86 | 5.23 |
| 2 | 1.44 | 4.48 |
| 3 | 1.66 | 4.78 |
| 4 | 1.38 | 4.80 |
| 5 | 1.40 | 4.64 |
| 6 | 1.39 | 4.86 |
| 7 | **2.34** | 4.36 |
| 8 | 1.40 | 4.35 |
| 9 | 1.42 | 4.34 |
| 10 | 1.72 | 4.37 |
| 11 | 1.39 | 4.07 |
| 12 | 1.37 | 4.05 |

| | Min | Median | Max | Mean | Max/median |
|---|---|---|---|---|---|
| `scr check` | 0.86s | 1.40s | 2.34s | 1.48s | 1.67x |
| `sc check` | 4.05s | 4.425s | 5.23s | 4.53s | 1.18x |

### The decomposition holds

Sample B timed `list` alongside `check`, which separates definition loading from liveness
without needing an in-process harness:

| | Median |
|---|---|
| `scr list` — definition loading only | 1.38s |
| `scr check` — loading plus liveness for 3 services | 1.645s |
| **Liveness for 3 services, by subtraction** | **~0.27s** |

Against roughly 1.6s in section 4, before `QtocLstNetCnn` and `QUSLJOB`. That is the two API
replacements showing up end to end, independently of the per-call microsecond figures in
sections 5 and 6.

It also settles section 8 with a number: definition loading is **84% of a default `check`**, and
is the only place left with material headroom.

### An observation that did not survive

Samples A and B each contained one Java run several times its median — 17.66s against 4.115s in
sample B. Two samples agreeing made it look like a property of the JVM, and it was nearly
recorded as one: an argument that RMSC's worst case matters more than its median for a
screen-refresh workload.

Sample C, which interleaved the routes rather than running them in blocks, showed the reverse.
Java had the *tighter* spread of the two (max/median 1.18x against RMSC's 1.67x) and the outlier
was RMSC's 2.34s. The excursions belong to the shared LPAR and land on whichever route happens
to be running when one occurs. No claim about relative consistency is made, and the earlier one
is withdrawn.

The methodological point is worth keeping: running two routes in separate blocks makes system
noise look like a property of whichever route drew the bad interval. Interleave them.

### Not re-verified

The A/B in section 6 was **not** re-run. It requires rebuilding the service program both ways,
and 5770-WDS is off on this system, with the ILE compiler licence at usage limit 0 under a grace
period expiring 31 October 2026. The 19% therefore still rests on its original measurement. What
this section establishes is narrower: the build currently deployed still performs at the figure
that measurement produced.

---

## 10. Reproducing these figures

Set these once. The host and the deploy directory are deliberately not recorded here.

```bash
HOST=<user>@<your-ibmi>
DEPLOY=<the deploy directory on that system>   # where the project is built
BASELINE=<directory holding the captured Java output>   # section 2; not published here
```

Everything below assumes `QIBM_MULTI_THREADED=Y`. Without it the PASE side of `sc` and `scr`
behaves differently, and the figures are not comparable.

### First: prove the output before trusting any timing

A faster run that prints the wrong thing is worthless, and this has already caught one false
result — an early "40x faster" reading turned out to be a command-not-found returning
quickly. Always diff before timing.

```bash
for f in check list groups; do
  ssh $HOST "export QIBM_MULTI_THREADED=Y; $DEPLOY/scripts/scr $f" > /tmp/now-$f.txt
  diff $BASELINE/baseline-$f.txt /tmp/now-$f.txt && echo "$f: byte-identical"
done
```

Note *which* baselines that diffs against. `$BASELINE` holds the **real** captures described
in section 2, taken from the live system and not published with this repository. The tracked
`fixtures/` directory holds same-layout equivalents with invented service names, so the format
tests can live in a public repo — they describe a different machine and will not match a live
run. Diffing against those instead is a trap that costs an afternoon, because the output looks
plausibly wrong rather than obviously so. `tools/fidelity-gate.sh` takes the same directory as
its own `BASELINE`, and fails rather than skipping if it finds nothing there.

Confirm colour stays off when stdout is not a terminal, because ANSI escapes would corrupt the
status columns:

```bash
ssh $HOST "export QIBM_MULTI_THREADED=Y; $DEPLOY/scripts/scr check | cat -A | grep -c '\^\['"
# must print 0
```

### The full gate - every read-only operation

The diff above covers `check`, `list` and `groups`: the operations with captured fixtures, and
the ones the byte-exact acceptance criterion is written against. They are 3 of the 13 operations
RMSC accepts.

`tools/fidelity-gate.sh` covers the rest. It runs on the box, because a per-command `ssh` round
trip turns a full sweep into minutes:

```bash
scp tools/fidelity-gate.sh $HOST:$DEPLOY/tools/
ssh $HOST "$DEPLOY/tools/fidelity-gate.sh"
```

Two stages, deliberately different:

- **Byte-exact** - `check`, `list`, `groups`, plus a check that no ANSI escape reaches a
  non-terminal stream, compared against the captured Java fixtures.
- **Live differential** - `info`, `file`, `loginfo`, `jobinfo`, `scrunattrs` and `perfinfo` are
  run through *both* implementations on the spot and compared to each other. Nothing is captured
  for these: they embed job numbers, timestamps and storage counters that differ between any two
  runs seconds apart, so a stored fixture would rot almost immediately. Only those values are
  normalised - whitespace is not, because a stray blank line is exactly the class of difference
  the gate exists to catch.

`start`, `stop`, `kill` and `restart` are not gated. They change system state, and `SCLIFE.TEST`
already covers the lifecycle against a service it creates and removes itself.

The gate passes when reality matches the divergence list recorded in the script. It fails when
something regresses **and** when something is fixed without the list being updated, so the list
cannot quietly drift out of date.

#### Recorded state, 31 August 2026

| Operation | Result | Divergence |
|---|---|---|
| `check`, `list`, `groups` | **pass** | byte-identical to the captured fixtures |
| `loginfo` | differs | one trailing blank line, nothing else |
| `jobinfo` | differs | `sc` prints a header then indented jobs; RMSC one `name: job` line each |
| `scrunattrs` | differs | different meaning - `sc` lists running jobs and their run attributes, RMSC prints the `SCOMMANDER_*` variables it sets |
| `file` | differs | different meaning - `sc` prints the definition's *path*, RMSC prints its *contents* |
| `info` | differs | omits the environment-variables block and the closing separator, adds a `Group:` line, resolves `Defined in:` to a different but byte-identical copy of the file, and shows a resolved working directory rather than the raw one |
| `perfinfo` | differs | substantially incomplete - 66 lines from `sc`, 12 from RMSC |

Smallest first: `loginfo` is one line, `jobinfo` is a formatting change, `perfinfo` is real work.
None of the six is on the `check` path, so none affects any figure in this document - which is
why they went unnoticed until the gate was widened past the three operations that are.

### Java baseline

```bash
ssh $HOST "export QIBM_MULTI_THREADED=Y; TIMEFORMAT='%3R'; time /QOpenSys/pkgs/bin/sc check >/dev/null"
```

### RMSC end to end, with a distribution rather than one number

The LPAR is shared, so a single run is noise. Twelve runs and a median is what the figures in
sections 1 and 6 are built from.

```bash
ssh $HOST "
export QIBM_MULTI_THREADED=Y
for i in \$(seq 1 12); do
  /usr/bin/time -p $DEPLOY/scripts/scr check 2>&1 >/dev/null | awk '/real/{print \$2}'
done | sort -n | awk '{a[NR]=\$1} END{printf \"n=%d min=%s median=%s max=%s\n\", NR, a[1], (a[int((NR+1)/2)]+a[int(NR/2+1)])/2, a[NR]}'"
```

Swap `check` for `list` to reproduce the definition-loading comparison in section 3.

### Isolating one change — the A/B used in section 6

Rather than comparing against a remembered number, build both routes and time them in the
same session. `SCQRY_jobs_by_name` delegates to the API only when no subsystem is given, so
forcing that guard false sends everything back through SQL.

```bash
# Route A - force the SQL path
ssh $HOST "cd $DEPLOY && \
  cp QRPGLESRC/SCQRY.SQLRPGLE /tmp/SCQRY.orig && \
  sed -i 's|^  if %len(sbs_l) = 0;\$|  if 1 = 0;|' QRPGLESRC/SCQRY.SQLRPGLE && \
  /QOpenSys/pkgs/bin/makei build"
#   ... time it with the loop above ...

# Route B - restore and rebuild
ssh $HOST "cd $DEPLOY && cp /tmp/SCQRY.orig QRPGLESRC/SCQRY.SQLRPGLE && /QOpenSys/pkgs/bin/makei build"
#   ... time it again ...
```

Re-run the byte-exact diffs after restoring, and re-run the suites: the service program is
rebuilt twice here, and a stale test object against a changed export list fails in ways that
look nothing like a build problem.

### SQL-level diagnosis — how section 5 was argued

The point of these four is that they disagree with the obvious explanation. If filtering to
one port costs the same as counting everything, the cost is not the enumeration.

```bash
ssh $HOST "db2util -o csv \"SELECT COUNT(*) FROM QSYS2.NETSTAT_INFO WHERE LOCAL_PORT = 8076 AND TCP_STATE = 'LISTEN'\""
ssh $HOST "db2util -o csv \"SELECT COUNT(*) FROM QSYS2.NETSTAT_INFO\""
ssh $HOST "db2util -o csv \"SELECT * FROM QSYS2.NETSTAT_INFO\""
ssh $HOST "export QIBM_MULTI_THREADED=Y; TIMEFORMAT='%3R'; time netstat -an >/dev/null"
```

Time each with `TIMEFORMAT='%3R'` as above. Note that `db2util` startup is included, which is
the honest comparison against PASE `netstat` — that also pays for a process.

### The per-call microsecond figures

The µs figures in sections 5 and 6 — 376,464 µs to 693 µs, and 177 ms per job lookup — are
**not reproducible from the shell**, and no command here will produce them. They came from a
throwaway in-process harness that called the procedure in a loop inside one job and divided
by the iteration count, which is the only way to see a single procedure's cost without the
process, the job and the definition load swamping it. That harness was deleted rather than
kept, on the grounds that a benchmark nobody runs is a benchmark nobody maintains.

To measure a procedure again, write a `.TEST.RPGLE` suite that brackets a loop with
`%timestamp()` and reports through an assertion message. Two constraints will bite: an
iRPGUnit test written as `.SQLRPGLE` cannot be compiled from an SSH job, because the SQL path
calls `CRTSQLRPGI` and that refuses a multithreaded job — submit it to batch or use the VS
Code Test Explorer — and a plain `.RPGLE` test has no such problem.

---

All timings from a hosted IBM i 7.5 LPAR, 0.25 shared core. Figures for `check`, `list` and
`groups` were taken only against runs whose output was verified byte-identical to the captured
Java fixtures.
