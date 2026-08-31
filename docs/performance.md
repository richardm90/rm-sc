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
| **Suites** | 144 cases / 578 assertions |

> Every figure here is from measurements already taken and recorded during the work. No new
> timing runs were made to produce this document.

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

All timings from a hosted IBM i 7.5 LPAR, 0.25 shared core. Figures for `check`, `list` and
`groups` were taken only against runs whose output was verified byte-identical to the captured
Java fixtures.
