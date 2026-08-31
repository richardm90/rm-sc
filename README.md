# rm-sc

Service Commander for IBM i, reimplemented in RPGLE.

A drop-in replacement for [Service Commander](https://github.com/ThePrez/ServiceCommander-IBMi)
(`sc`), which is written in Java. Same YAML service definitions, same command surface, same
output format — without the JVM cold start, and without forking `db2util` for every liveness
query.

| | |
|---|---|
| **Library** | `RMSC` — object names cannot contain hyphens |
| **Test library** | `RMSCT` |
| **Build** | [TOBi](https://github.com/IBM/tobi) — `makei build` |
| **Tests** | IBM i Testing extension + iRPGUnit |

## Status

**Working.** 144 test cases, 578 assertions across 11 suites. `check`, `list` and `groups` are byte-identical
to the Java implementation.

| Module | Does |
|---|---|
| `SCYAML` | Reads the YAML subset service definitions use |
| `SCDEF` | Types a definition and applies upstream's defaults |
| `SCDIRS` | Resolves the definition search path |
| `SCCOLL` | Discovery, groups, dependency order with cycle detection |
| `SCQRY` | Liveness and reporting queries, as embedded SQL |
| `SCNET` | Port status via the TCP/IP list API, ~540x faster than the SQL service |
| `SCJOB` | Active job lookup via `QUSLJOB`, ~125ms per call faster than the SQL service |
| `SCOUT` | Output formatting, byte-identical to upstream |
| `SCLOG` | Log file location |
| `SCLAUNCH` | Starting, stopping, environment assembly |
| `SCEXEC` | Status determination and the twelve operations |
| `SCMAIN` | Command line parsing and dispatch |
| `SCAPI` | Bound-call API for ILE callers |

Usable three ways: the `scr` shell wrapper, the `SC` CL command, and — for an ILE caller that
wants values rather than text to parse — the bound-call API in
[`QPROTOSRC/SCAPI_D.RPGLEINC`](QPROTOSRC/SCAPI_D.RPGLEINC).

## Why

`sc` was assumed to be slow for two reasons:

1. **JVM cold start** on every invocation.
2. **`db2util` fork-per-query** — `QueryUtils.java` runs each of its 11 SQL statements by
   spawning a process and opening a fresh database connection.

An ILE program removes both — and measured, that bought only about 20%, with `list` actually
*slower* than Java. Neither assumption survived contact with a stopwatch: the JVM start is
smaller than expected, and the fork is not what dominates a liveness query. The IBM i SQL
table functions are. Filtering `NETSTAT_INFO` to one port cost the same as returning every row
of it, while PASE `netstat` returned the same data, process fork included, five times faster.

What actually made RMSC fast was replacing those table functions with the system APIs
underneath them — `QtocLstNetCnn` for port status, `QUSLJOB` for job lookup. `scr check` now
runs in about 1.6s against Java's ~3.4s.

The measurements, including the ones that disproved the original premise, are in
[`docs/performance.md`](docs/performance.md).

## Compatibility

`check` output is **byte-for-byte identical** to upstream. This is deliberate and load-bearing:
`sc`'s output is a de facto interface, and consumers parse it by column position.

```
  RUNNING            | webproxy (Web Proxy)
```

| Element | Rule |
|---|---|
| Leading | exactly two spaces |
| Status | columns 3–20, left-justified, padded to width 18 |
| Separator | space at column 21, `|` at column **22**, space at column 23 |
| Name | column 24 to the space before `(` |
| Description | between `(` and the last `)` |
| Trailing | one space after `)` |

Equivalently `'  ' + %left(status:18) + ' | ' + name + ' (' + desc + ') '`.

Colour is suppressed when stdout is not a TTY, for the same reason — ANSI escapes would land
inside the status columns and corrupt them.

`fixtures/` holds reference captures in this layout for the format tests.

## Autostart at IPL

RMSC does **not** hook into `STRTCPSVR`. Starting services at IPL stays with the Java
implementation, deliberately.

The `*SC` TCP server hardcodes the path to the Java `sc` inside a QSYS-owned program, so
repointing it means either modifying a program the package installed — which a package update
would silently revert — or registering a parallel server special value. Both are possible;
neither earns its risk. RMSC's speed advantage is worth nothing at IPL, where the work runs
once, unattended, with nobody waiting, and the failure mode is a service not coming back after
a restart.

## Scope

Full parity with upstream **except** cluster mode and nginx `cluster.conf` generation, and
therefore `reload`, which is cluster-only upstream. Running nginx as an ordinary managed
service is unaffected — that is a normal service definition, not cluster mode.

## Dependencies

Requires **`rmtools`**, a general-purpose RPGLE helper library (service program `RMBASE`),
consumed two ways with different lifetimes:

- **Copybooks** — needed at **compile time only**, via `INCDIR`.
- **Modules** — bound **by copy**, so `RMSC` carries no runtime dependency on the `RMTOOLS`
  library and no job calling it needs `RMTOOLS` on its library list. See
  [`docs/tobi-binding.md`](docs/tobi-binding.md).

**`rmtools` is not currently publicly available**, so this repository cannot be built by
third parties as it stands. Publishing it is intended but not yet straightforward.

## Licence

[MIT](LICENSE).

Service Commander itself is a separate project, licensed Apache-2.0. This is an independent
reimplementation, not a fork or derivative of its source.
