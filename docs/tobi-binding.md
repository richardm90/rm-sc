# Phase 0 findings — TOBi build and binding

Proven against TOBi 3.3.0 on IBM i 7.5.

## The goal

Bind `rmtools` modules **by copy**, so `RMSC` carries no runtime dependency on the `RMTOOLS`
library and no job calling it needs `RMTOOLS` on its library list.

## Three TOBi constraints

**1. There is no `MODULE =` variable.** TOBi builds the `MODULE()` parameter solely from
`.MODULE` prerequisites:

```make
MODULE($(basename $(filter %.MODULE,$(notdir $^))))
```

An out-of-project module cannot be named there — it would have to be a prerequisite, and TOBi
would then try to build it from source it does not have. A `MODULE =` line is **silently
ignored**: the build fails later at the bind step with unresolved imports, not with a syntax
error, so this is easy to misdiagnose.

**2. `BNDDIR` is a supported per-target variable.** This is the way in, and it turns out to be
better than an explicit module list. In ILE, a binding directory entry that is a **`*MODULE`**
is bound **by copy**; one that is a `*SRVPGM` is bound **by reference**. So a bnddir containing
only `*MODULE` entries gives bind-by-copy — and the binder pulls in only the modules whose
exports are actually referenced, so listing one that goes unused costs nothing.

**3. `CRTBNDRPGFLAGS` has no `BNDDIR` parameter.** A `.PGM.RPGLE` is built with `CRTBNDRPG` and
cannot be pointed at a service program from `Rules.mk`. It must carry `ctl-opt bnddir('...')`
in the source.

## Library-qualify *SRVPGM entries

Use `&O/SCPING`, not `*LIBL/SCPING`. An entry recorded as `*LIBL` makes activation search the
*caller's* library list. Verified with `DSPPGM DETAIL(*SRVPGM)`:

```
 Service
 Program        Library        Activation     Signature
 SCPING         RMSC           *IMMED         E2C3D7C9D5C740F04BF04BF140404040
```

`RMSC`, not `*LIBL` — so RMSC stays callable from a job that knows nothing about it.

## Verification

```
=== BOUND MODULES ===
"RMTOOLS","RMSTRING01"        <- copied in
"RMSC","SCPING"

=== DSPSRVPGM DETAIL(*SRVPGM) ===
QRNXIE, QRNXUTIL, QLEAWI, QLGCASE   <- all QSYS RPG runtime; no RMTOOLS
```

And the empirical test, which is the one that settles it:

```
RMTOOLS entries found: 0
--- CALL RMSC/SCPINGP ---
exit code: 0
RESULT: CALL SUCCEEDED with RMTOOLS off the library list
```

## Consequences for later phases

- `RMSC.SRVPGM` gets `BNDDIR = RMSCDEPS`; `RMSCDEPS` lists the twelve `rmtools` modules.
- `SCMAIN.PGM` needs `ctl-opt bnddir('RMSCPGM')` in its source, and `RMSCPGM.BNDDIR` as a
  `Rules.mk` prerequisite for ordering.
- `RMSCPGM` must library-qualify its `RMSC.SRVPGM` entry.

## Binding a test program

A test suite binding to the service program under test needs **two** binding directories:

```rpgle
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');
```

`RMSCPGM` supplies `RMSC.SRVPGM` for the procedures under test. `RMSCDEPS` is needed
separately whenever the test itself calls `rmtools` procedures — `RMSC.BND` exports only this
project's own symbols, so the `rmtools` code copied into `RMSC.SRVPGM` is deliberately not
reachable from outside it. That restriction is correct; the test just needs its own copy.

## Writing an IFS file in the right CCSID

`IFS_OPEN_TYPE_WRITE` tags the file **CCSID 1208** and opens it `O_CCSID`, which declares
"the bytes handed to `write()` are already in the file's CCSID".

- `IFS_write` does a raw write, so job-CCSID data is stored as EBCDIC **under a UTF-8 tag**.
  Nothing errors. The file looks right to `ls`, reports CCSID 1208, and comes back mangled.
- `IFS_write_utf8` declares its parameter `ccsid(*utf8)`, so RPG converts at the call
  boundary and the bytes on disk really are UTF-8.

Reading is the mirror image: `IFS_OPEN_TYPE_READ` opens with `o_ccsid=<job ccsid>`, so the C
runtime converts from the file's tagged CCSID on the way in. No `STRING_utf8` call is needed
anywhere — the conversion is in the open.

## Copybooks must be listed as prerequisites

TOBi rebuilds a target only when a **named** prerequisite is newer. A module that lists just
its own source will not rebuild when a copybook it includes changes:

```make
SCDEF.MODULE: SCDEF.RPGLE                       # wrong - copybook changes are invisible
SCDEF.MODULE: SCDEF.RPGLE QPROTOSRC/SCDEF_D.RPGLEINC   # right
```

The failure mode is nasty because nothing reports an error. `makei build` says **"Nothing to
be done for 'all'"**, which reads as "already up to date". The service program keeps the old
record layouts while a freshly compiled caller — a test program, say, which the IBM i Testing
extension always recompiles — uses the new ones. Fields are then read at the wrong offsets and
come back as plausible-looking garbage: an integer reading `1077952576` is `0x40404040`, four
EBCDIC blanks being interpreted as a number.

List every copybook a module includes, including indirect ones.

## A non-ILE artifact: `native/rmsc_fork_helper`

Added 4 October 2026, for the non-batch job-naming fix in `docs/parity.md`. `f_fork400()` — the
PASE API that can give a job a specific name, which rmtools' `spawn()`-based `PASE_run_cmd`
cannot — can only be called from a PASE-compiled program. Per IBM's own documentation it cannot
be called from any ILE language, RPG or C alike: ILE C (`CRTCMOD`) is a different machine
environment from PASE, not just a different compiler for the same environment, and has no more
access to `fork400()` than ILE RPG does. So `native/rmsc_fork_helper.c` is genuinely not an ILE
object of any kind — it compiles to a plain IFS executable (XCOFF), not a `*MODULE`/`*PGM`/
`*SRVPGM`, and RMSC calls it at runtime by a fixed absolute path
(`/QOpenSys/pkgs/lib/rmsc/native/rmsc_fork_helper`, matching `SCLAUNCH_FORK_HELPER` in
`QRPGLESRC/SCLAUNCH.RPGLE`), not through the binder at all.

**Build prerequisite, not covered by TOBi's own toolchain**: a PASE C compiler, confirmed as
`/QOpenSys/pkgs/bin/cc` (gcc-6, via the `QOpenSys/pkgs` toolchain) on the box this was built and
tested against. TOBi's own `.C`/`.CPP` → `.MODULE` recipe uses `CRTCMOD`, i.e. ILE C — not this.
Installation instructions need this compiler present before `makei build` will succeed.

**The build mechanics are still ordinary `makei build`, via a custom recipe — four things about
it had to be measured on the box, not assumed from the skill documentation alone:**

```make
RMSC_FORK_HELPER.SRVPGM: rmsc_fork_helper.c
	/QOpenSys/pkgs/bin/cc -o /QOpenSys/pkgs/lib/rmsc/native/rmsc_fork_helper native/rmsc_fork_helper.c
```

(`native/Rules.mk`, in full, comments aside.)

1. **The target's name must carry a real, recognized object-type suffix — a made-up one (the
   documentation's own `.rebuild` sentinel pattern) is rejected outright.** `rmsc_fork_helper.
   rebuild: rmsc_fork_helper.c` fails to parse at all: `Warning: Target 'RMSC_FORK_HELPER.
   REBUILD' is not supported`. TOBi's `RulesMk.__init__` (`src/makei/rules_mk.py`) decomposes
   every rule's source file by extension and, when that extension maps to more than one possible
   object type (`.c` maps to both `.MODULE` and `.PGM`), falls back to the *target's own* suffix
   to disambiguate — and that suffix has to be a real one TOBi knows (`TARGET_GROUPS`), or it
   exits. `.rebuild` is never valid there; `.SRVPGM` is, which is exactly why the skill's own
   worked example (`THIRDPARTY.SRVPGM: $(DEPDIR)/THIRDPARTY.SRVPGM.rebuild`) uses that suffix for
   its custom-recipe target, not for the sentinel.
2. **It must NOT be listed as a prerequisite of `RMSC.SRVPGM`, or anything else.** Any
   `.SRVPGM`-suffixed prerequisite of a service-program target gets automatically added to
   `CRTSRVPGM`'s `BNDSRVPGM()` parameter — the same mechanism that derives `MODULE()` from
   `.MODULE` prerequisites (see "Two names that are not what you expect" in
   `tobi-rules-mk.md`). Listing `RMSC_FORK_HELPER.SRVPGM` there makes `RMSC.SRVPGM`'s build try
   to bind against it as a real service program, which fails — it isn't one. Leaving it off
   entirely works: `makei build`'s own top-level `all` target already reaches every object TOBi's
   parser recorded against a recognized suffix, across every `SUBDIRS` directory, with nothing
   else needing to reference it.
3. **A plain `Rules.mk` variable (`FOO = ...`, referenced as `$(FOO)`) does not survive into a
   custom recipe's commands** — it silently expands to empty (`cc -o  rmsc_fork_helper.c`, a
   missing argument, not an error at parse time). The deploy path is written literally instead.
4. **A custom recipe's commands run from the project root, not from the `Rules.mk` directory
   that defines them** — unlike a generated recipe, which TOBi prefixes itself. The source has
   to be named with its directory (`native/rmsc_fork_helper.c`), not bare, or `cc` reports it
   missing.
5. **`makei build`'s own "Build Successful!" banner can be wrong when a custom recipe's
   command actually fails.** MEASURED directly: a real `cc` compile error (a header conflict,
   unrelated to this point) produced `make: Target 'all' not remade because of errors.` —
   buried in the middle of the output, easy to miss if anything is piped through `tail` — and
   `make -k`'s own "keep going past one failure" semantics meant every *other* object still
   built, so the run still ended with `Objects: 0 failed N succeed N total` / `Build
   Successful!`, with the custom-recipe target itself simply not counted either way and the
   stale binary from the previous successful build silently left in place. Caught here only by
   independently checking the deployed binary's own timestamp/checksum after the "successful"
   build — which is the actual lesson: **for this target specifically, the build banner is not
   sufficient evidence it rebuilt; check the deployed file directly.** `grep` the full output
   for `Target 'all' not remade` rather than trusting the final line, or diff the binary's
   mtime/checksum against the source's.

`/QOpenSys/pkgs/lib/rmsc/native/` itself is **not** created by this build, deliberately — it's
owned by `qsys`, matching upstream's own `/QOpenSys/pkgs/lib/sc/native/` (same `drwxr-sr-x`
shape), and a `mkdir -p` inside the recipe just fails loudly (`Permission denied`) rather than
quietly creating a new system directory from an unprivileged build. A privileged profile creates
it once, during installation, before the first `makei build`:

```bash
mkdir -p /QOpenSys/pkgs/lib/rmsc/native
chown qsys:0 /QOpenSys/pkgs/lib/rmsc /QOpenSys/pkgs/lib/rmsc/native
chmod 2755 /QOpenSys/pkgs/lib/rmsc /QOpenSys/pkgs/lib/rmsc/native
chgrp qpgmr /QOpenSys/pkgs/lib/rmsc/native
chmod 2775 /QOpenSys/pkgs/lib/rmsc/native
```

(the first three lines match upstream's read/execute-for-everyone shape exactly; the last two
additionally grant write to `qpgmr` — the group the profile that actually runs `makei build`
belongs to on this box, measured directly rather than assumed, since granting write to group `0`
alone did nothing for a profile whose own group isn't `0`. A different box may need a different
group named here — the requirement is "whichever group the building profile belongs to", not
`qpgmr` specifically.)
