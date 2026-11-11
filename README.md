# rm-sc

Service Commander for IBM i, reimplemented in RPGLE.

A drop-in replacement for [Service Commander](https://github.com/ThePrez/ServiceCommander-IBMi)
(`sc`), which is written in Java. Same YAML service definitions, same command surface, same
output format — without the JVM cold start, and without forking `db2util` for every liveness
query.

| | |
|---|---|
| **Library** | `OBJLIB` at build time (e.g. `RMSC`) — object names cannot contain hyphens |
| **Test library** | The same library, `OBJLIB` |
| **Build** | [TOBi](https://github.com/IBM/tobi) — `makei build` |
| **Tests** | IBM i Testing extension + iRPGUnit |

## Installation

**Prerequisites**

- [TOBi](https://github.com/IBM/tobi) installed on the target IBM i partition.
- A PASE C compiler at `/QOpenSys/pkgs/bin/cc`. One small native helper
  (`native/rmsc_fork_helper.c`) has to be PASE-compiled, not ILE — see
  [`docs/tobi-binding.md`](docs/tobi-binding.md) if you want to know why. The
  [rm-tools](#dependencies) build needs it too, for its own `rmfork` helper.
- `*PUBLIC` `*USE` authority to `QSYS/QCLSTMF`, which the build needs to create binding
  directories and the message file from CL pseudo-source (the default is `*EXCLUDE`):
  `GRTOBJAUT OBJ(QSYS/QCLSTMF) OBJTYPE(*PGM) USER(*PUBLIC) AUT(*USE)`.

**Get the source**

[rm-tools](#dependencies) is a git submodule, so clone with `--recursive` (or run
`git submodule update --init` in an existing clone):

```bash
git clone --recursive https://github.com/richardm90/rm-sc.git
```

**One-time setup, before the first build**

The target library is `OBJLIB`, supplied at build time — [`iproj.json`](iproj.json) sets
`objlib`/`curlib` to `&OBJLIB`, so it's never a literal and never needs editing to build into a
different library. `makei build` does not create it for you — confirmed directly: pointed at a
library that doesn't exist, the build fails outright (`CPFA0A9: Object not found`) rather than
creating it — so create it first, named whatever you're about to pass as `OBJLIB` below (`RMSC`
is the obvious choice, and what the rest of this README assumes):

```bash
system "CRTLIB LIB(RMSC) TEXT('RMSC: Service Commander for IBM i')"
```

The native helpers are deployed outside any library, one directory per release:
`/QOpenSys/opt/rm-sc/<release>/bin/rmsc_fork_helper`, and rm-tools'
`/QOpenSys/opt/rm-tools/<release>/bin/rmfork`. Each build creates its release's own
`<release>/bin`, but only a privileged profile can create the parent directories, so one with
`*ALLOBJ` sets them up once:

```bash
# /QOpenSys/opt does not exist on a new system. If it is missing, create it
# and leave it readable by everyone (it may hold other products' directories).
[ -d /QOpenSys/opt ] || { mkdir /QOpenSys/opt && chmod 755 /QOpenSys/opt; }

# Replace qpgmr with whichever group the profile running `makei build` belongs
# to - it needs write access here to deploy the compiled helpers.
mkdir -p /QOpenSys/opt/rm-sc /QOpenSys/opt/rm-tools
chgrp qpgmr /QOpenSys/opt/rm-sc /QOpenSys/opt/rm-tools
chmod 2775 /QOpenSys/opt/rm-sc /QOpenSys/opt/rm-tools
```

Because each release has its own directory, releases can be installed side by side and each
`RMSC` calls the helper from the release it was built with. A release's directory is not needed
once nothing built from that release is in use; remove it by hand with
`rm -r /QOpenSys/opt/rm-sc/<release>`.

**Build**

```bash
cd rm-sc
makei build -e OBJLIB=RMSC
```

(`OBJLIB` can equally be exported first — `export OBJLIB=RMSC && makei build` — `-e` is just
the one-line form. Leaving it unset entirely fails the build immediately with
`OBJLIB must be defined first in the environment variable.`, rather than silently defaulting
to anything.)

This builds `RMSC/RMSC` (the service program, into whichever library `OBJLIB` named) and the
native `SC` CL command. It also builds rm-tools from the submodule into the same library:
its modules, the `RMTOOLS` binding directory RMSC binds them through, and `RMMSGF`.

**Tests**

The iRPGUnit suites in `tests/` need [iRPGUnit](https://github.com/tools-400/irpgunit)
installed (its `RPGUNIT` library); the build itself does not. They compile into the same library
as the build, as `T`-prefixed service programs (`TSCCOLL` for `SCCOLL.TEST.RPGLE`) - both from the
IBM i Testing extension in VS Code and from the shell, from the repository root:

```bash
tools/verify.sh suites
```

Each suite should report `compile=0` and `Success`, and the run should end `VERDICT OK`. Set
`SRVLIB` if you built into a library other than `RMSC`, or `TSTLIB` to put the suites somewhere
else. `tools/verify.sh` with no arguments is the full verification, including the fidelity gate
against captured upstream output; see [`CLAUDE.md`](CLAUDE.md#build-and-test).

`scr` itself is not built or deployed anywhere — it's the plain bash script at
[`scripts/scr`](scripts/scr), run directly from wherever this repository is checked out
(`scripts/scr check`, or put it on `PATH` yourself). Set `RMSC_LIB` to match whatever you built
`OBJLIB` as, if not `RMSC`.

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

[**rm-tools**](https://github.com/richardm90/rm-tools), a general-purpose RPGLE helper library,
is a git submodule at `deps/rm-tools`, pinned to a release tag. `makei build` builds it as part
of this project (`deps` is first in the root `SUBDIRS`), so there is nothing to install
separately and no `RMTOOLS` library involved. It is consumed two ways with different lifetimes:

- **Copybooks** — needed at **compile time only**, from `deps/rm-tools` on the include path.
- **Modules** — bound **by copy** through the `RMTOOLS` binding directory built into `OBJLIB`,
  so `RMSC` carries no runtime dependency on any rm-tools library. See
  [`docs/tobi-binding.md`](docs/tobi-binding.md).

Keep any other library that holds an `RMTOOLS` binding directory (such as an older, separately
built rmtools) off the build's library list: an unqualified `RMTOOLS` resolves to the first one
found.

To move to a newer rm-tools release:

```bash
git -C deps/rm-tools fetch --tags
git -C deps/rm-tools checkout vX.Y.Z
git add deps/rm-tools && git commit -m "Use rm-tools vX.Y.Z"
```

**Minimum version.** rm-tools v1.0.0 already contains the `PATH_BASENAME_t` widening that RMSC
depends on (from private rmtools 2.0.7). Without it, a service whose file name exceeded 127
characters lost its name entirely and collided with any other such service, and the suites go
red in about ten places across `SCDEF`, `SCCOLL` and `SCLAUNCH` with nothing in the failure
text naming rm-tools as the cause.

## Releasing

The release number appears in the code in one place only: `SCLAUNCH_FORK_HELPER` in
`QPROTOSRC/SCLAUNCH_D.RPGLEINC` (`/QOpenSys/opt/rm-sc/<release>/bin/rmsc_fork_helper`). The build
reads it from there to decide where to deploy the native helper. Update it for every release.

## Licence

[MIT](LICENSE).

Service Commander itself is a separate project, licensed Apache-2.0. This is an independent
reimplementation, not a fork or derivative of its source.
