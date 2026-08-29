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

## Where the real win is

The one measurement that is dramatic is not in this table, because it is not a shell
invocation at all. Every route above pays for a process, a job, and a full definition load.
A caller already inside an ILE job — a green-screen program calling the service program
directly — pays none of that.

That is the case the bound-call API is for, and it is where a consumer refreshing a subfile
several times a minute would actually notice.

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
2. **Batch the port checks.** `check` currently issues one `NETSTAT_INFO` query per port
   criterion. One query returning all listening ports would collapse them into one.
3. **Cache parsed definitions**, keyed on file modification time. The most complex option and
   the one most likely to be wrong in a way nobody notices.

None of these changes behaviour, and none is needed for correctness.
