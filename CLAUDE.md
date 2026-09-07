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

**`RMSC.BND` pins a `SIGNATURE`, and it guards less than it looks like it guards.** It is
`'RMSC 0.3.0'` today.

*Export order is the part it does cover.* Add exports at the end. Inserting one in the middle
shifts every export after it, and already-compiled callers reach the wrong procedure — the
binder has nothing to complain about, and seven suites fail with `RNX0115` on code that did not
change.

*Shapes are the part it does not.* A structure that crosses the service-program boundary, or an
exported procedure's return type, can change size with the signature untouched — and then a
caller built against the old copybooks binds happily and reads fields at the wrong offsets, or
receives a 160-byte varchar into a 64-byte field. No error, at bind time or at run time.

That is not hypothetical: on 5 September 2026 `SCDEF_t` gained a field, `SCEXEC_EVAL_t` widened
twice, and `SCDEF_criterion_text`'s return went 64 → 160, all under `0.1.0`. Nothing broke,
because everything that binds RMSC lives in this repository and gets rebuilt together — which is
luck, not design.

**So: change a shape that crosses the boundary, bump the signature.** It converts a silent
memory overwrite into a bind-time failure, at the price of forcing a deliberate rebuild. That
price is the point.

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

### The tests are written by someone who cannot see the code. This is not optional.

**Tests are commissioned from a separate test author, and that author must not read
`QRPGLESRC/` or `QPROTOSRC/`** — not with a search, not through another agent, not on the box.
It is given a measured specification and the existing suites, and nothing else.

The obvious reason is the weaker one: a test written against the implementation agrees with the
implementation. The real reason is that **the gap is almost never in the code — it is in what the
implementer thought to ask for.** Whoever writes the fix has already decided which cases matter,
and those are exactly the cases that cannot catch them being wrong.

Measured, on 5 September 2026, all three in one afternoon and all three on freshly written work
rather than anything inherited:

- An ad-hoc port fix removed a conversion instead of guarding it, so **every** `port:N` check
  probed port 0 and `port:22` reported NOT RUNNING against a listening sshd. The full suite
  passed. Every case aimed at that line used `port:-1`, `port:65536` or `port:abc` — values that
  report NOT RUNNING whether the code is right or wrong.
- Widening the criterion type to 128 left two 64-wide holders standing, one of them silencing
  conflict detection entirely past 64 characters. Every fixture in every suite used a short name,
  so no test could tell the two widths apart.
- A guard was tested with a 20-digit value, which its width test refused before any conversion
  was attempted. The test passed, and could not distinguish a working guard from one that never
  ran.

So the rule that follows, and it is the one to apply when writing any case:

> **A fix and the break it could have been must disagree about at least one case in the suite.**
> Cover the working case, not only the failing one. If every case in front of you gives the same
> answer either way, you have not tested the change — you have watched it not crash.

What a separate author is *for* is finding what the brief left out, so its objections are worth
more than its tests. Ours has, in one day: refused to write a case for something unreachable from
a suite rather than write one that passes today; found that a test helper shared the defect under
test, so all four cases would have gone green and proved nothing; noticed a control that asserted
so much it died before reaching the thing it was controlling; and reported that a case it was
asked for could not separate anything, then measured why rather than quietly deleting it.

**Give it the measurement, never the mechanism.** Tell it what upstream does and which rival
reading each case has to rule out. If it asks for an interface it cannot read, paste the
prototype — never the body.

**And know where the wall leaks.** A `RUCRTRPG` listing prints **the whole expanded `/COPY`
source**, plus a cross-reference of field names and widths. Not part of it — all of it. So an
author grepping that listing for anything at all can pull back the copybooks it is forbidden to
read.

This was found twice, both times disclosed unprompted by the author that hit it: first grepping
`RNF[0-9]{4}` for diagnostics, then grepping `created` and matching copybook header comments. The
second correction is the important one, because the first version of this note said "do not grep
for `RNF`", which reads as though some patterns are safe.

**None are. Do not read a compile listing.** Take `COMPILE_RC` from the shell and nothing else;
if a compile fails, bisect the source rather than reading the diagnostic. The wall is a
discipline, not a mechanism, and a discipline survives only on its traps being named accurately.

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

```bash
makei build && BASELINE=<captured-upstream-dir> tools/verify.sh
```

`tools/verify.sh` is the whole of it in one run: thirteen suites, the five harnesses, the gate
and the fixture pack, with a time against each stage and `VERIFY_DONE` at the end. **Run it
before every commit.** Three things about it are worth knowing before you do:

- **Build first, or the suites lie.** They compile and run against whatever `RMSC.SRVPGM`
  is already there, so without a build they report a pass for code that was never tested. A
  stale service program is indistinguishable from a current one at run time, so nothing in the
  run can detect this.
- **It takes the better part of an hour**, and the fixture pack is most of it - about ninety
  `sc` invocations, each starting a JVM. Named stages run a subset while iterating
  (`tools/verify.sh suites gate`), but a partial run is not a verification and the script says
  so in its own output.
- **`BASELINE` is not defaulted.** It points at captured upstream output naming real services,
  so it lives outside this repository; the gate exits 2 with a clear message rather than
  guessing.

## Where things are

| | |
|---|---|
| `QRPGLESRC/` | the modules; `QPROTOSRC/` holds the matching prototype copybooks |
| `qtestsrc/` | iRPGUnit suites, excluded from `SUBDIRS` so TOBi never builds them |
| `docs/performance.md` | every measurement taken, and how to re-run it |
| `docs/parity.md` | where RMSC matches upstream `sc` and where it deliberately does not |
| `docs/testing-notes.md` | what has cost real time here — read before debugging a test |
| `docs/tobi-binding.md` | build and binding specifics |

### Say which numbering you mean

Three independent schemes run in this project, and they collide on every value:

| Scheme | Where | What 8 means there |
|---|---|---|
| **Phases** 0–7 | the plan | Phase 8 does not exist |
| **Verification steps** 1–14 | the plan | the side-by-side operation diff |
| **Sections** 1–10 | `docs/performance.md` | "What is not done" |

Phase 0 also has its own internally numbered steps, which is why a Verification step can say
"Phase 0 server steps 7-12" meaning something else again. Always write **"Verification step N"**
or **"performance.md §N"** in full. A bare "step 8" or "§8" is ambiguous, and has already cost
one round of confusion.

`rmtools` is a dependency in two ways with different lifetimes: copybooks at compile time via
`INCDIR`, and modules bound **by copy**, so `RMSC` has no runtime dependency on the `RMTOOLS`
library. It is not publicly available, so third parties cannot currently build this.
