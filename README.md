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

**Phase 0 — project setup.** Not yet functional.

## Why

`sc` is slow for two independent reasons:

1. **JVM cold start** on every invocation.
2. **`db2util` fork-per-query** — `QueryUtils.java` runs each of its 11 SQL statements by
   spawning a process and opening a fresh database connection.

An ILE program removes both. The second is the larger and less obvious win: liveness checks
become embedded SQL running in-job on a connection that is already open.

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
