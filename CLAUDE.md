# RMSC — orientation

RMSC reimplements IBM i Service Commander (`sc`) in RPGLE: an independent implementation, not a
fork, reading the same YAML service definitions from the same places and producing the same
output. Full parity with upstream except cluster mode, `cluster.conf` generation, and therefore
`reload`, which is cluster-only upstream.

**This repository is public.** No client names, client library or program names, and no
infrastructure detail belong in it.

## Three things to know before changing anything

**`check` output is byte-exact, and a slip is silent.** The consumer screen-scrapes it and
drops any row that does not yield three fields, so a formatting mistake makes services vanish
from a screen rather than raising an error. The contract is
`'  ' + %left(status:18) + ' | ' + name + ' (' + desc + ') '`, with `|` at column 22. Colour
must stay off when stdout is not a terminal, for the same reason. Verify by diff against the
captured baselines, never by eye.

**`RMSC.BND` pins `SIGNATURE('RMSC 0.1.0')`, so the *order* of the export list is the
contract.** Add exports at the end. Inserting one in the middle shifts every export after it,
and already-compiled callers reach the wrong procedure — the binder has nothing to complain
about, and seven suites fail with `RNX0115` on code that did not change.

**No new phase of work begins without an explicit go-ahead**, and core decisions that are
not already settled are asked rather than assumed. Finishing a phase early, or finding one
blocked, is still a stop: report and wait rather than rolling into the next.

## Test first

**Write the failing test before the fix, and watch it fail.** Not as ceremony — three defects
here were shipped behind assertions that could not fail, and each was found only when a test
was written that could:

- `SCQRY_jobs_on_port` returned a port's clients as well as its listener for three phases,
  behind `assert((... > 0))` — true for one job or five.
- `SCQRY_jvm_info` was rejected by the database on every call it ever made, behind a test that
  only asked what happened for a job that does not exist.
- `SCNET`'s IPv6 branch was wrong from the day it was written, and no test could reach it.

A red test proves the test can detect the defect. A test written afterwards proves only that it
agrees with the code. Where a fixture is missing, **fail rather than skip** — a suite that
passes because its fixture is absent is worse than one that fails, because it reports success.

Prefer fixtures the suite can rely on rather than ones that happen to be there: port 22 and
`sshd` are present because the suite arrived over SSH, and `SCLIFE.TEST` creates and removes the
service it exercises.

## Build and test

Both run over SSH from the deploy directory. Neither needs `SBMJOB`.

```bash
makei build
```

```bash
# compile then run one suite; parameters mirror .vscode/testing.json
qsh -c "liblist -a RPGUNIT; liblist -a RMSC; liblist -a RMSCT; liblist -a RMTOOLS;
        system \"RUCALLTST TSTPGM(RMSCT/SCQRY) ORDER(*API) DETAIL(*BASIC) OUTPUT(*ALLWAYS)\""
```

QSH is required because each `system` call runs in its own job and loses any library list set
by a previous one. `docs/testing-notes.md` has the traps.

```bash
tools/fidelity-gate.sh      # output parity against upstream sc; run it on the box
```

The gate is byte-exact for `check`, `list` and `groups`, and a live differential for the other
read-only operations. Differences are classified as sanctioned by the plan or still undecided;
it fails when something regresses *and* when something is fixed without the list being updated.

## Where things are

| | |
|---|---|
| `QRPGLESRC/` | the modules; `QPROTOSRC/` holds the matching prototype copybooks |
| `qtestsrc/` | iRPGUnit suites, excluded from `SUBDIRS` so TOBi never builds them |
| `docs/performance.md` | every measurement taken, and how to re-run it |
| `docs/testing-notes.md` | what has cost real time here — read before debugging a test |
| `docs/tobi-binding.md` | build and binding specifics |

`rmtools` is a dependency in two ways with different lifetimes: copybooks at compile time via
`INCDIR`, and modules bound **by copy**, so `RMSC` has no runtime dependency on the `RMTOOLS`
library. It is not publicly available, so third parties cannot currently build this.
