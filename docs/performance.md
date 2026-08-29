# Performance, measured

The premise for this project was that RMSC would be substantially faster than the Java
implementation, for two reasons: no JVM cold start, and no `db2util` fork per SQL query.

**Measured, that premise does not hold.** RMSC is faster, but by around 20%, not multiples.

## The numbers

IBM i 7.5, 0.25-core shared LPAR. Each figure is three consecutive runs inside one SSH
session, so connection setup is excluded. Every route was verified to produce the same three
service rows before being timed — an earlier reading of "40x faster" turned out to be a
command-not-found returning quickly.

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| `sc check` (Java) | 3.673 | 3.412 | 3.376 |
| `scr check` (RMSC) | **2.929** | **2.909** | **3.013** |
| `sc list` (Java) | **0.573** | **0.885** | **1.018** |
| `scr list` (RMSC) | 1.419 | 1.336 | 1.309 |

RMSC wins `check` by about 20%. It **loses** `list` — which does no system queries at all —
by about 50%.

## Why

`list` is pure definition loading, and RMSC is slower at it than Java. Both parse **39
definitions on every invocation**, of which a default `check` displays 3: the other 36 are in
the `system` group and are filtered out *after* being read.

Subtracting, on this system:

- loading 39 definitions: roughly **1.3s** for RMSC, **0.8s** for Java
- the liveness queries for 3 services: roughly **1.6s** for both

So the JVM cold start is smaller than assumed, and the `db2util` fork is not what dominates
the query time — the IBM i services themselves are. `ACTIVE_JOB_INFO` and `NETSTAT_INFO` cost
what they cost, whether reached through a forked process or embedded SQL.

## The bound-call API, measured

The API was expected to be dramatically faster, on the reasoning that a caller already inside
a job pays for no process, no job and no definition load. Measured, it is faster, but the
first version of it was not: it called `SCCOLL_load` on every call and re-read all 39
definitions, costing **2.64s per call** — no better than running the command.

Caching the definitions for the life of the activation is what makes the API worth using:

| | per call |
|---|---|
| `SC_check_all`, reloading definitions each time | 2.64s |
| `SC_check_all`, definitions cached | **1.78s** |
| Java `sc check` via PASE | ~3.4s |

Twenty calls in one job take 35.7s, so the marginal cost really is flat — the first call pays
for the load, the rest do not.

Live status is deliberately **not** cached. Every call re-queries the system, because that is
the question being asked. `SC_refresh()` drops the cached definitions when a file has changed.

So against today's 3.4s, the API is about **1.9x** — real, but not the order of magnitude
predicted before measuring. The saving is not mostly the JVM: removing the process, the job
and the definition re-read gets 3.4s down to 1.8s, and the remaining 1.8s is the IBM i
services themselves.

The stronger argument for the API is not speed. It is that the consumer stops parsing text by
column position, and a format change stops being able to make services silently disappear.

## What would make the command line faster

Not yet done, and worth deciding on rather than assuming:

1. **Do not parse definitions that are about to be filtered out.** A default `check` reads 39
   and shows 3. Skipping the ignored groups during discovery would avoid roughly 90% of the
   parsing, and definition loading is where RMSC is slower than Java — so this is the largest
   single saving available. **Scheduled for investigation after the bound-call API.**

   The care is in the exceptions rather than the idea: `group:` and `-a` still need
   everything; dependency resolution can reach an excluded service, since an ignored service
   can be a dependency of a visible one; and `groups` derives its answer from definitions the
   filter would drop. The risk is not being slower — it is quietly showing a different set of
   services, so the byte-exact `check`, `list` and `groups` diffs have to be re-run.
2. **Batch the queries.** `check` issues one query per criterion — six round trips for three
   services with two criteria each. One `NETSTAT_INFO` returning all listening ports and one
   `ACTIVE_JOB_INFO` returning all matching jobs, filtered in memory, would collapse those
   into two. **Now the largest remaining cost**: after caching definitions, the whole of the
   bound call's 1.78s is these queries.
3. **Cache parsed definitions**, keyed on file modification time. The most complex option and
   the one most likely to be wrong in a way nobody notices.

None of these changes behaviour, and none is needed for correctness.
