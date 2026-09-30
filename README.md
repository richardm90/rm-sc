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

## Feature coverage

Everything below is measured against a running `sc`, not assumed from its source. `✅` means
covered and verified live; `⚠️` means handled deliberately differently from upstream (on
purpose, not a bug); `❌` means not available in RMSC. Where a `✅` hides a real, sanctioned
difference in behaviour, the note says so and points at
[`docs/parity.md`](docs/parity.md), which is the full record of every place RMSC's output or
behaviour diverges from upstream and why.

### Operations

| Operation | Covered | Notes |
|---|:---:|---|
| `check` (alias `status`) | ✅ | Byte-exact output; tri-state RUNNING / NOT RUNNING / PARTIAL |
| `start` | ✅ | Dependencies started first, recursively |
| `stop` | ✅ | `stop_cmd` if given, else `ENDJOB`; dependants stopped first |
| `restart` | ✅ | |
| `kill` | ✅ | Straight to `ENDJOB`, bypassing `stop_cmd` |
| `info` | ✅ | Formatted definition dump |
| `file` | ✅ | Raw YAML passthrough |
| `list` | ✅ | Short name + friendly name |
| `groups` | ✅ | All groups and members |
| `jobinfo` | ✅ | Active job names |
| `loginfo` | ✅ | Log paths, sizes, spooled files |
| `perfinfo` | ✅ | Improved: no Python/`ibm_db` dependency — reads `ACTIVE_JOB_INFO` directly |
| `scrunattrs` | ✅ | `SCOMMANDER_*` vars from the running job |
| `reload` | ❌ | Cluster-only upstream; rejected with a clear message rather than faked |

### YAML keys

| Key | Covered | Notes |
|---|:---:|---|
| `start_cmd` | ✅ | Required |
| `check_alive` | ✅ | Port, job name, `SBS/JOB`, `PGM-xxx`; comma-separated or a sequence |
| `check_alive_criteria` | ✅ | The value companion when `check_alive` names a type |
| `name` | ✅ | Required, exactly as upstream — a definition without one is refused |
| `dir` | ✅ | Relative paths resolve against the YAML file's own location |
| `stop_cmd` | ✅ | Literal `null` accepted |
| `startup_wait_time` / `stop_wait_time` | ✅ | Default 60 / 45 |
| `log_dir` | ✅ | Custom directory both respected and auto-created if missing |
| `batch_mode` | ✅ | Bare `true` and quoted `'true'` both accepted |
| `sbmjob_jobname` / `sbmjob_opts` | ✅ | Both genuinely reach the submitted `SBMJOB` command |
| `environment_is_inheriting_vars` | ✅ | Default true |
| `environment_vars` | ✅ | `KEY=VALUE` sequence |
| `service_dependencies` | ✅ | Including an empty inline `[]` |
| `groups` | ✅ | Both 0- and 2-indented sequences |
| `only_if_executable` | ✅ | |
| `cluster` | ⚠️ | Parsed and rejected with a clear message — never silently ignored |
| Unknown keys | ⚠️ | Warn under `-v`, never fail |

### Specifiers, flags, and interfaces

| Feature | Covered | Notes |
|---|:---:|---|
| Short name | ✅ | |
| `group:<name>` | ✅ | |
| No service argument → all | ✅ | |
| `all` | ✅ | Same as `group:all` |
| YAML file path (`sc check /path/to/def.yaml`) | ✅ | One sanctioned divergence on a malformed extension — see `docs/parity.md` |
| `port:<n>`, `job:<name>`, `job:<sbs>/<name>`, `PGM-<name>` | ✅ | Ad hoc, no definition needed |
| `--ignore-groups=` | ✅ | Default `system` |
| `-v`, `-q`, `--disable-colors` | ✅ | |
| `--splf` | ✅ | |
| `--sampletime=`, `--ignore-globals`, `-a`/`--all` | ✅ | |
| Colour auto-off when not a TTY | ✅ | See [Compatibility](#compatibility) |
| Global + user definition directories | ✅ | `/QOpenSys/etc/sc/services`, `$HOME/.sc/services` |
| Subdirectory recursion | ⚠️ | Not supported — upstream doesn't recurse either, so this matches rather than gaps |
| Dependency graph + cycle detection | ✅ | |
| Native `SC` CL command | ✅ | New — upstream has no native CL interface at all |
| PASE wrapper `scr` | ✅ | Named `scr`, not `sc`, so both stay callable side by side |
| Bound-call API (`SC_check`, `SC_start`, …) | ✅ | For an ILE caller — see [`QPROTOSRC/SCAPI_D.RPGLEINC`](QPROTOSRC/SCAPI_D.RPGLEINC) |
| Cluster mode / nginx `cluster.conf` generation | ❌ | Out of scope — see [Scope](#scope) |
| Parallel operations | ❌ | Sequential; only mattered for cluster fan-out |
| `sc_install_defaults` equivalent | ❌ | Deliberate — a standalone script, not part of `sc` itself, that already works unmodified against `scr` |
| `*SC` TCP server hook (autostart at IPL) | ❌ | Deliberate — see [Autostart at IPL](#autostart-at-ipl) |

## Dependencies

Requires **`rmtools` 2.0.7 or later**, a general-purpose RPGLE helper library (service
program `RMBASE`), consumed two ways with different lifetimes:

- **Copybooks** — needed at **compile time only**, via `INCDIR`.
- **Modules** — bound **by copy**, so `RMSC` carries no runtime dependency on the `RMTOOLS`
  library and no job calling it needs `RMTOOLS` on its library list. See
  [`docs/tobi-binding.md`](docs/tobi-binding.md).

**Why 2.0.7 specifically.** Before it, `PATH_BASENAME_t` was `varchar(128)`, so a service
whose file name exceeded 127 characters lost its name entirely — `PATH_name` truncated the
name, lost the extension off the end, failed to find the dot and returned an empty string
through a `MONITOR`. Two such services then collided, and one vanished from `check`.

Built against 2.0.6 the suites go red in about ten places across `SCDEF`, `SCCOLL` and
`SCLAUNCH`, and **nothing in the failure text names rmtools as the cause** — the markers that
used to say so were flipped to ordinary assertions when 2.0.7 landed. If you see that
cluster, check the version first.

**`rmtools` is not currently publicly available**, so this repository cannot be built by
third parties as it stands. Publishing it is intended but not yet straightforward.

## Licence

[MIT](LICENSE).

Service Commander itself is a separate project, licensed Apache-2.0. This is an independent
reimplementation, not a fork or derivative of its source.
