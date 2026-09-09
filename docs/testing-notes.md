# Testing notes

Things that cost real time on this project. All confirmed on IBM i 7.5 with iRPGUnit 6.0.0.

## `likeds()` does not inherit the template's `inz`

```rpgle
dcl-ds SCCOLL_t qualified template inz;   // inz applies to the TEMPLATE
...
dcl-ds coll likeds(SCCOLL_t);             // NOT initialised
dcl-ds coll likeds(SCCOLL_t) inz(*likeds); // initialised
```

`likeds()` copies the subfield definitions, not the DS-level `inz` keyword. An uninitialised
structure holds whatever was on the stack: varying-length fields carry garbage length prefixes
and any embedded control structure looks plausibly populated.

Here that produced `MCH0601 - Space offset ... outside current limit`, reported against the
**job** (`QP0ZSPWP`), not against any object of ours — a garbage `LIST_t` looked like an
already-created list, so nothing created one, and offsets were computed from a zero row size.

Two defences, and it is worth having both: declare `inz(*likeds)` at the call site, and give
any structure with real setup work an explicit initialiser (`SCCOLL_init`) so the contract does
not depend on the caller remembering.

## `aEqual` misreads varying-length **array elements**

`aEqual` is declared with operational descriptors:

```rpgle
dcl-pr aEqual extproc('aEqual') opdesc;
  expected  char(32565) options(*varsize) const;
  actual    char(32565) options(*varsize) const;
```

so it takes each argument's length from the descriptor. For a varying-length **array element**
inside a data structure the descriptor reports the wrong length — element N is read with
element N−1's length:

| Actual value | `aEqual` sees | Length taken from |
|---|---|---|
| `name(1) = 'db'` | `'db'` ✓ | itself |
| `name(2) = 'api'` | `'ap'` ✗ | element 1 |
| `criteria(2).kind = 'PORT'` | `'POR'` ✗ | element 1 |

**Scalars and procedure return values are fine**, which is why this only appears on subscripts —
and why it hides: element 1 always reads correctly, so a suite that only ever checks the first
element of an array passes while telling you nothing.

It cost twice here. The first time it was misread as a real defect and "fixed" by changing a
field from `varchar` to `char`; the code had been correct all along.

Use `aEqualV` (in each suite) for array elements. It compares with plain RPG — no descriptors —
and still reports both values on failure. `test_varchar_array_elements` in `SCCOLL.TEST` pins
the behaviour.

## A path no test can reach is a path that does not work

`SCNET` checks IPv4 first and falls through to IPv6, because a service listening on IPv6 alone
would otherwise look stopped. The IPv6 branch was written from the documentation, reviewed, and
**wrong**: the qualifier's address fields are declared character but must hold binary nulls to
mean "every address", and `clear` leaves them as blanks. The API accepted that and returned an
empty list **with no error**.

It survived because nothing could observe it. Every service on a typical IBM i binds both
address families, so the IPv4 probe always answered first and the IPv6 code never ran. The
suite compared nine ports against the SQL path and agreed on all nine, without once executing
the broken branch.

Two changes came out of that, and the second matters more than the first:

1. `SCNET_port_listening` takes an optional address family, so each branch can be asked for
   directly rather than only reached by luck of what happens to be listening.
2. `tools/v6listen.py` holds an **IPv6-only** socket open (`IPV6_V6ONLY`, or binding `::` takes
   the IPv4 port too), so the fallthrough itself can be exercised against a real service.

Verified with it, which is the evidence that the fallthrough works rather than merely looks
right:

| port | IPv4 | IPv6 | default |
|---|---|---|---|
| IPv6-only listener | 0 | 1 | **1** — via the fallthrough |
| listens on both | 1 | 1 | 1 |
| nothing listening | 0 | 0 | 0 |

The suite now covers this automatically. `SCNET.TEST` opens its own IPv6-only socket with ILE
`socket`/`setsockopt`/`bind`/`listen`, so the fallthrough runs on every execution with nothing
to install. `tools/v6listen.py` remains for ad-hoc checking.

**Use the ILE socket constants, not the PASE ones.** They differ exactly where it matters:

| | PASE | ILE |
|---|---|---|
| `SO_REUSEADDR` | `0x0004` | **55** |
| `SOL_SOCKET` | `0xffff` | **-1** |
| `IPV6_V6ONLY` | `37` | **100** |

The ILE values are in `QSYSINC/SYS(SOCKET)` and `QSYSINC/NETINET(IN)`, not in `QSYSINC/H`.
`sockaddr_in6` is 28 bytes either way; IBM i uses the BSD form with `sin6_len` first.

The test asserts that IPv4 **cannot** see its own listener before asserting that IPv6 can.
Without that, a listener which quietly bound both families would make the fallthrough test
pass while proving nothing - which is the same failure the test exists to catch.

## Test against a service the suite owns, not one the system owns

Start and stop went untested for three phases on the reasoning that a suite which takes
services down on whatever system it runs on, and leaves them down when it fails, is not worth
having.

That is sound about *pre-existing* services and wrong about everything else. A service the
suite writes, submits and ends is nobody else's: `SCLIFE.TEST` defines one, starts it through
RMSC, watches it come up, stops it, and checks with the system that the job is really gone.

Until it existed, `SCLAUNCH`'s detach was tested only as a **string** - assertions that the
command contains `nohup`, `2>&1`, `< /dev/null` and a trailing `&` - and nothing had ever
confirmed that a service launched through RMSC survives its launcher, that the start poll
notices, or that `ENDJOB` works.

Two details make it reliable rather than merely present:

- **Batch mode.** The job name is then predictable, so `check_alive` can be a job name and the
  fixture needs nothing installed. It is also the path the real services on this system use.
- **Tear down synchronously.** `ENDJOB` returns when the request is made, not when the job has
  gone. The first version fired it and returned, so a following test asserting "not running"
  raced a job still on its way out - and the suite passed, failed three assertions, then
  passed again. A flaky test is worse than a failing one because it teaches you to re-run
  instead of investigate. The teardown now polls until the job is actually absent and says so
  if it never is. Verified over four consecutive runs, not one.

## An assertion that cannot fail is not a test

`SCQRY_jobs_on_port` returned every job holding a socket on the port, not only the one
listening on it. On port 22 that is the sshd listener plus every connected session - five jobs
where upstream returns one.

There *was* a test. It asserted the wrong thing:

```rpgle
assert((SCQRY_jobs_on_port(SSH_PORT: jobs) > 0): 'a job holds the SSH socket');
```

`> 0` is true whether the answer is one job or five, so it passed while the procedure returned
four jobs too many. The suite reported the shape of the answer and never its value.

It mattered because `SCEXEC_jobs` is built on that procedure, and `stop` and `kill` pass its
result straight to `SCLAUNCH_endjob`. Any profile in the `QPGMR` group inherits `*JOBCTL`,
which grants control over jobs regardless of who owns them - so `scr kill` on a port-based
service would not have been refused for authority. It would have ended other people's
interactive sessions successfully.

The fix is one qualifier, and it is what upstream does (`QueryUtils` in `sc.jar`):

```sql
WHERE LOCAL_PORT = :port_l AND REMOTE_PORT = 0 AND JOB_NAME IS NOT NULL
```

A listening socket has no peer; an established connection does.

The replacement test asserts the count rather than its sign, and names the jobs it got so a
failure says *which* rather than only *how many*. Port 22 is the fixture that needs nothing
installed: the suite arrives over SSH, so there is always a listener plus at least one
connected session held by a different job.

## Running a suite without VS Code

The suites are normally driven by the IBM i Testing extension. Driving one from a shell takes a
single QSH invocation - but three things mislead you on the way there.

**It is the library list, not the job.** `RUCRTRPG` fails with `RNF0273 - Compiler not able to
open the /COPY or /INCLUDE file`, because `/include QINCLUDE,TESTCASE` needs `RPGUNIT` on the
library list. Every `/QOpenSys/usr/bin/system` call runs in *its own job*, taking the library
list from the job description, so a `CHGLIBL` or `ADDLIBLE` in a previous call is already gone.
QSH holds one job for the whole invocation:

```bash
qsh -c "liblist -a RPGUNIT; liblist -a RMSC; liblist -a RMSCT; liblist -a RMTOOLS;
        system \"RUCALLTST TSTPGM(RMSCT/SCQRY) ORDER(*API) DETAIL(*BASIC) OUTPUT(*ALLWAYS)\""
```

Results arrive on stdout - no spooled file to chase. Swap `RUCALLTST` for `RUCRTRPG` with the
parameters in `.vscode/testing.json` to compile first.

**`RUCRTRPG` creates a `*SRVPGM`, not a `*PGM`.** `CHKOBJ ... OBJTYPE(*PGM)` then answers
`CPF9801 - not found` about a build that succeeded, which reads exactly like a compile failure.

**`makei build` needs none of this.** It compiles `.SQLRPGLE` in an ordinary SSH job. The note
that `CRTSQLRPGI` refuses a multithreaded job is about `RUCRTRPG` compiling a `.SQLRPGLE`
*test* source - a different command path - and is not a constraint on the build. Reaching for
`SBMJOB` and `INLLIBL` to work around it costs an afternoon and fixes nothing.

## A staged port is not free twice in a row

A suite that opens a listener, connects to it and accepts the connection leaves
the port in **TIME_WAIT for about two minutes** after it closes. So the second
run of that suite cannot bind, and a fixture written the obvious way replaces
one flaky failure with another — a different one, arriving on the *next* run
rather than under load.

`SO_REUSEADDR` is the fix, and on ILE the constants are not the ones most
references give: `SOL_SOCKET` is **-1** and `SO_REUSEADDR` is **55**.

It permits TIME_WAIT and still refuses a port something is *actively*
listening on, which is the property that matters — verified both ways, because
an option that made the bind always succeed would turn a fixture failure into
a silent pass. `tools/gate-listen.py`'s header records the same reasoning for
the shell side.

## `out` is the OUT opcode

A local variable named `out` will not compile: `out = x;` at statement start
parses as the RPG **OUT** opcode. The diagnostic does not say so in terms that
lead anywhere useful.

This is the second instance of the same trap — `other` is the OTHER opcode and
cost a rename across a suite earlier in the project. The general form is worth
holding: **a short, obvious English word for a local is a coin flip against the
opcode table.** `list`, `result`, `rows` are safe; `out`, `other`, `in`, `eval`,
`call`, `return`, `test` are not.

Found while fixing the flaky query suites, by bisecting probe sources — not by
reading the compile listing, which CLAUDE.md now forbids outright.

**Third instance, 8 September 2026, and this time the note above already
existed.** `SCQRY_job_attrs` used `out` for the packed job name it was
building; the whole service program build failed on one module with

    RNF5008  Factor 1 operand is not valid; defaults to blanks.
    RNF7260  The Factor 2 operand *BLANKS is not valid ...

which names neither the word nor the reason, and points at the line *after*
the declaration. Two things are worth keeping from it. The diagnostic sends
you looking at the assignment's right-hand side — `*BLANKS` — when the fault
is entirely on the left. And the cost was not the rename but the isolation:
the failure arrives from `makei` as one failed object with an expanded-source
line number that maps to the SQL precompiler's temporary member, so it cannot
be read back to a line in the file you edited.

**The technique that resolved it in one compile** is worth reusing for any
`SQLRPGLE` failure: lift the new declarations and procedures into a standalone
`.rpgle` in a scratch directory, compile it with `CRTRPGMOD` against the same
`INCDIR`, and read *those* diagnostics, which carry real line numbers in a file
you control. It also separates "my RPG is wrong" from "the SQL precompiler
dislikes this", which the combined build cannot tell you. Note `CRTRPGMOD` has
no `RPGPPOPT` keyword (`CPD0043`), and an isolation file carrying its own
`ctl-opt` will draw a harmless `RNF1302` against the one in `RMCOMP_H`.

**Fourth instance, the same day, in `SCOUT.RPGLE`** — the test author named a
local accumulator `out` in a helper it had copied the shape of from
`strip_sgr`, three procedures away. `strip_sgr` carries a comment saying not
to use that name and why. The author, who may not read `QRPGLESRC/`, resolved
it from `COMPILE_RC` alone by bisecting its own source, and then repeated the
warning inside its own procedure rather than relying on the existing one.

That last decision is the point, and it is a better statement of the rule than
the two above it. **A warning only works where the mistake gets made.** Nobody
reads a neighbouring procedure's comments before naming a local variable, so a
note attached to the one procedure that already got it right protects nothing.
Twice in one file in one day, from opposite sides of the wall, with the
warning already present both times.

## iRPGUnit truncates your failure message at 64 characters

`iEqual`, `nEqual` and `aEqual` declare `fieldName varchar(64)` with **no
`*varsize`**, in iRPGUnit's own `QINCLUDE,TESTCASE`. So the message you pass is
silently cut at 64, and **no width chosen in this repository can change it**.

Measured on the box, 8 September 2026: a 120-character value passed to a
`varchar(64) const` parameter arrives 64 long with no diagnostic; `opdesc` on
the prototype does not change that; the same value passed to `varchar(200)`
arrives whole.

Surveyed at the time - 72 call sites across SCDEF, SCCOLL and SCLAUNCH carry
messages longer than 64, the longest 243 characters. Every one of them has been
losing its reasoning at the point it was needed.

**THE RULE THAT FOLLOWS.** When the reasoning rides on `iEqual` or `nEqual`,
the point must fit in the **first 64 characters** - front-load it, and put the
elaboration after. When it cannot, use `assert()`, whose `msgIfFalse` is
`varchar(16384)`, or a local helper this repository owns.

Local helpers CAN be widened and have been: `sl_equal` and `aEqualV` are now
`varchar(500)`, sized to the longest message that reaches them today (271) with
the framework's own 16384 as the ceiling downstream. `tr_stored`, `tr_equal`
and `sk_assert_order` are 200 and nothing exceeds it.

**Why this matters more than it looks.** A truncated assertion still passes and
still fails correctly - only the explanation is lost, and only at the moment
someone is reading it to find out what broke. It is the same defect as every
other silent truncation in this project, in the one place designed to explain
the others. It was found while widening a helper's message parameter in the
suites that exist to prove nothing is truncated at 64.

## The PASE `system` utility eats the rest of your script

Reported by the test author on 8 September 2026, after it cost three round
trips. In a script fed over stdin —

    ssh host 'bash -s' <<EOF
      system "CHGJOB ..."
      ...everything after this line silently vanishes...
    EOF

— the first `system` call **consumes stdin**, so the remainder of the script is
swallowed as that command's input and never runs. Redirect every call:
`system "..." < /dev/null`.

It matters because of how it fails: no error, no output, and the commands that
did not run leave no trace. That is indistinguishable from a connection
problem, which is the most expensive diagnosis to be wrong about on this box —
the project has already lost time to a dead IP looking exactly like a slow
boot.
