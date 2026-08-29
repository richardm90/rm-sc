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
