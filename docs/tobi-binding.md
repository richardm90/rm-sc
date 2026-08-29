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
