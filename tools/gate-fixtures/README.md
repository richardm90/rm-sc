# `rmscgate` — the fidelity gate's fixture pack

Service definitions the **repository** owns, so that a comparison between RMSC and upstream
`sc` runs against known input instead of against whatever happens to be defined on the machine
the gate runs on.

`tools/fidelity-gate.sh` discovers its subjects by running `scr list`. That is deliberate — the
script is published and must not name a client's services — but it means coverage is accidental,
moves when the machine does, and cannot reach any form no real service uses. Every difference
`docs/parity.md` records under *"Corrected since this file was written"* was invisible to it:

> All are fixed and match live, on stdout, stderr and exit status. None of them was reachable by
> anything that ran, which is the argument for the fixture pack rather than a footnote to it.

**These files are the tests.** They are test data in the same sense a unit suite's assertions
are, so the same rule applies as everywhere else in this project: each must be able to fail, and
must fail for a nameable reason. Every file carries a header saying what it exercises, what each
implementation is expected to do, **where that expectation comes from**, and what a red result
would mean. Read the header before believing a failure — a wrong expectation and a real defect
look identical in a diff, and the headers exist to separate them.

Nothing here names a real host, a real client, or real infrastructure. Every service name, group
name, job name and port is invented and prefixed `rmscgate`.

---

## How it is installed

Both implementations read a **custom definition directory**, searched last, so the pack
overrides nothing and needs no file placed under `/QOpenSys/etc/sc/services`.

```bash
DIR=/tmp/rmscgate/base          # wherever the pack was copied

# RMSC — environment variable
SC_SERVICES_DIR="$DIR" scr --ignore-globals check

# upstream — JVM system property
JAVA_TOOL_OPTIONS="-Dservices.dir=$DIR" sc --ignore-globals check
```

Both were verified working on the box. `docs/parity.md` records the pairing as **by design**:
ILE has no JVM system properties, so RMSC reads `SC_SERVICES_DIR` instead; the concept and the
search order match, the mechanism differs because it has to.

Three things a harness must get right:

1. **`JAVA_TOOL_OPTIONS` makes the JVM announce itself on stderr.** It prints a line of its own
   before `sc` produces anything. Filter that one line — and filter it by matching it, not by
   dropping the first line of stderr, or a real message goes with it.
2. **Use `--ignore-globals`.** It makes a command see only this pack plus the user directory,
   which is empty on the test profile. Without it every real definition on the machine is in the
   comparison and the pack's rows are lost among them. Note `-a` turns `--ignore-globals` back
   off where the argument appears, as upstream does — so `-a` and `--ignore-globals` together are
   order-dependent, and `-a` alone is not a way to see the pack in isolation.
3. **Copy, do not symlink, and preserve the directory.** `base/` contains a subdirectory named
   `rmscgate_subdir.yaml`, which is itself a fixture. `cp -R` keeps it; anything that flattens or
   follows links destroys the case.
4. **Copy the files in a NON-alphabetical order**, and keep whatever order you choose the same
   between runs:

   ```bash
   ls base | sort -r | while read f; do cp -R "base/$f" "$DIR/"; done
   ```

   Upstream sorts its service list; RMSC returns directory-read order, and on this platform
   directory order follows creation order. Copy the pack alphabetically and the two orders
   coincide, so the difference hides — which is exactly how it survived on the box, where the
   three real definitions happen to come back in alphabetical order. Copying in reverse makes
   `list` and `check` fail loudly if the sort is ever dropped again.

### Never install this pack globally

`rmscgate_group_autostart.yaml` declares the `autostart` group, which on a real system means the
`*SC` TCP server starts it at IPL. The pack is meant to live in a temporary directory for the
duration of a comparison and be reached through `SC_SERVICES_DIR` / `-Dservices.dir`. Do not copy
it into `/QOpenSys/etc/sc/services`. Every `start_cmd` in the pack is `/QOpenSys/usr/bin/true`,
which does nothing and exits 0, so an accident is harmless — but that is a second line of
defence, not the plan.

---

## The naming rule

Upstream accepts a definition file only if its name matches

```
^([a-z\-_0-9]+)\.y[a]{0,1}ml$
```

**lower case only**, `.yaml` or `.yml`. A name that does not match is **ignored with a warning**,
except one ending `rpmnew`, which is **ignored silently**. Both halves of that are fixtures:
`rmscgate_rpmnew.yaml.rpmnew` in `base/` (silent, so it perturbs nothing) and
`isolation/bad-filename/` (warns, so it does).

The **short name** — what `list` prints and what `check <name>` resolves — is the filename with
the extension removed. The **friendly name** in parentheses is the `name:` key.

---

## What "install in isolation" means

A fixture that changes what *other* services report cannot share a directory with the rest of the
pack. Installed together, it makes every other comparison fail for a reason that has nothing to
do with the fixture being compared — a load warning on every command, an extra row in the middle
of the byte-exact `check` surface, or a failure that takes the whole run down.

So the pack is in two parts:

```
base/                     install as one directory; every file is inert with respect to the others
isolation/<case>/         install ONE of these at a time, as the whole of SC_SERVICES_DIR
```

Each isolation case is its own directory and is installed **alone** — not alongside `base/`.
Most of them ship a copy of `rmscgate_control.yaml`, a deliberately boring service whose only job
is to answer the question that makes the case an isolation case: *what happened to the other
rows?* If the control's row is missing, the case took down the whole run; if it is present, the
damage was confined to the offending definition. That distinction is the finding, and without a
control there is nothing to read it off.

---

## Staging

Some fixtures need something listening. `tools/gate-listen.py` does it, prints `READY` once every
port is bound, and **refuses to bind a port that is already in use** — which matters more than it
looks: a listener that silently failed to bind leaves the fixture reporting NOT RUNNING, both
implementations agree that nothing is there, and the comparison passes while proving nothing.

| Port | Fixture | How |
|---|---|---|
| 55431 | `base/rmscgate_port_up.yaml` | `gate-listen.py 55431` |
| 55432 | `base/rmscgate_type_port.yaml` | `gate-listen.py 55432` |
| 55433 | `base/rmscgate_partial_multi.yaml` | `gate-listen.py 55433` |
| 55444 | `base/rmscgate_adhoc_port.yaml` | `gate-listen.py 55444` |
| 55445 | `base/rmscgate_v6_only.yaml` | `gate-listen.py --v6only 55445` — **IPv6 only** |
| 55443 | `isolation/duplicate-criterion/` (both files) | `gate-listen.py 55443` |

Everything else in the pack expects **nothing listening**, and that is an assertion, not an
absence:

- **55450–55469 is the known-dead range.** Never stage anything in it. A harness should confirm
  before a run that nothing is listening there — bind each port briefly and release it — because
  a stray listener turns a NOT RUNNING expectation into a red result that reads like a defect.
- **55437 and 55438 must also stay dead**, even though they sit inside the staging range. They
  belong to `isolation/criteria-comma/`, whose whole point is that a comma-separated companion
  value is *not* split into two ports. Stage them and the fixture can no longer detect the change
  it exists to detect.

Two fixtures rely on liveness the harness does not stage:

- **Port 22 / `sshd`** — the project's sanctioned "fixture you can rely on": the session arrives
  over SSH, so something is listening. **Exactly one fixture may claim it**, and that is
  `rmscgate_partial_seq`. Two once did, and upstream then warned about the conflicting
  definitions on every single command — see "What the pack has already found" below. Anything
  else needing a live port takes a staged one.
- **Job `QP0ZSPWP`** — the PASE job. Both `sc` and `scr` are launched from PASE, so the command
  being compared is itself running in one. Three base fixtures share that criterion; each says so
  in its header, and says what to check first if one of the three rows is wrong.

---

## Running the pack economically

`check`, `list` and `groups` cover **every** fixture in `base/` in a single invocation each —
one command per implementation, not one per service. The per-service differential operations
(`info`, `file`, `jobinfo`, `loginfo`, `perfinfo`, `scrunattrs`) cost a round trip each, so
running all of them against all 35 base services is over 400 invocations. Pick a subset: the `info`
group below is what the `info` comparison is for, and the rest add nothing to it.

## Check the pack before installing it

```bash
python3 check-pack.py            # from inside the pack directory
```

It verifies that every filename will actually be loaded, that no two definitions in `base/`
share a check-alive criterion, that the two `duplicate-criterion` cases still *do* share one,
and it prints the ports to stage and the ports that must stay dead — read straight out of the
fixture headers, so the harness and the pack cannot drift apart. Exit status is non-zero if
anything is wrong, so it can go in front of a gate run. It exists because the first version of
this pack shipped a collision it would have caught.

---

## Index — `base/` (install together)

### The status surface

| File | Covers | Staging |
|---|---|---|
| `rmscgate_port_up.yaml` | single port criterion, RUNNING, `PORT:55431` | **55431** |
| `rmscgate_port_down.yaml` | same criterion type, nothing listening, NOT RUNNING, no suffix | — |
| `rmscgate_partial_seq.yaml` | genuine `PARTIAL (1/2)` + suffix, from a **sequence** `check_alive` | — |
| `rmscgate_partial_multi.yaml` | `PARTIAL (1/3)` from a **comma-separated** `check_alive`; pins the `, ` separator and the order of two dead criteria in the suffix | **55433** |
| `rmscgate_job_up.yaml` | job criterion, alive; lower-case input rendered `JOBNAME:QP0ZSPWP` | — |
| `rmscgate_job_down.yaml` | job criterion, dead — the pair that stops a stuck lookup passing | — |
| `rmscgate_sbsjob.yaml` | `SBS/JOB` renders as one `JOBNAME:` criterion, slash and all | — |
| `rmscgate_pgm_form.yaml` | `PGM-x` renders as `JOBNAME:PGM-X` — there is **no** `PGM:` form | — |

### Every `check_alive` form and spelling

| File | Covers | Staging |
|---|---|---|
| `rmscgate_word_port.yaml` | `check_alive: port` alone means a **job called PORT** | — |
| `rmscgate_type_port.yaml` | the type-and-value pair; **the pack's highest-consequence fixture** — RMSC is recorded as reading the companion as an alias and reporting a live service as stopped | **55432** |
| `rmscgate_type_jobname.yaml` | the same pairing with the `jobname` type | — |
| `rmscgate_type_case.yaml` | the type word in mixed case, asserted against its own value — the failure signature is `JOBNAME:JOBNAME` | — |
| `rmscgate_criteria_ignored.yaml` | the companion is dropped when `check_alive` is not a type | — |
| `rmscgate_adhoc_port.yaml` | a **defined** service carrying the port a `port:N` specifier asks about — the resolution and ad-hoc-naming differences `docs/parity.md` records and the gate cannot currently see | **55444** |
| `rmscgate_v6_only.yaml` | the IPv6 fallthrough, through a real `check` rather than a procedure call | **55445, v6only** |

### Discovery — what is loaded and what is not

| File | Covers |
|---|---|
| `rmscgate_yml_ext.yml` | the `.yml` half of the extension filter |
| `rmscgate_hyphen-9.yaml` | hyphen and digit in a filename, and resolving that short name |
| `rmscgate_rpmnew.yaml.rpmnew` | the one non-matching name ignored **silently** |
| `rmscgate_subdir.yaml/rmscgate_hidden.yaml` | upstream does **not** recurse; the directory's own name matches the filename regex, so a name test running before the directory test shows up |
| `rmscgate_exec_yes.yaml` | `only_if_executable` satisfied — service present |
| `rmscgate_exec_no.yaml` | `only_if_executable` unsatisfied — service filtered out, silently |

### Parsing and tolerance

| File | Covers |
|---|---|
| `rmscgate_unknown_key.yaml` | an unknown key warns under `-v` and never fails |
| `rmscgate_no_startcmd.yaml` | a "required" key absent — needed to `start`, not to `check`. **Inferred, weakest expectation in the pack** |
| `rmscgate_null_stop.yaml` | `stop_cmd: null` is absent, not the string `null` |
| `rmscgate_comments.yaml` | header, whole-line and **trailing** comments — the last of which silently extends a value if mishandled |
| `rmscgate_noeol.yaml` | no trailing newline; the last key must survive. Verify with `tail -c1 … \| od -c` after installing |
| `rmscgate_batch_bare.yaml` | `batch_mode: true` |
| `rmscgate_batch_quoted.yaml` | `batch_mode: 'true'` — must mean the same as the bare form |

### Groups

| File | Covers |
|---|---|
| `rmscgate_group_system.yaml` | the default `--ignore-groups=system`: absent from a bare `check`, present under `-a`. 0-indented sequence |
| `rmscgate_group_alpha.yaml` | ordinary membership of a group whose entire membership the pack owns |
| `rmscgate_group_two.yaml` | two groups, 2-indented sequence — the other shipped indentation |
| `rmscgate_group_autostart.yaml` | a built-in group name that is **not** excluded, so the ignore list cannot have been widened |

### The keys that feed `info`

| File | Covers |
|---|---|
| `rmscgate_info_full.yaml` | every `info`-visible key at once, chosen to reach all four of the `info` differences `docs/parity.md` lists as **undecided** |
| `rmscgate_info_reldir.yaml` | `dir: .` — raw upstream, resolved in RMSC; and resolution against the **file's** location, not the caller's |
| `rmscgate_defaults.yaml` | the smallest legal definition; pins `startup_wait_time` 60, `stop_wait_time` 45, inheriting vars true |
| `rmscgate_deps_empty.yaml` | `service_dependencies: []`, the pack's only YAML flow sequence |
| `rmscgate_deps_one.yaml` | a dependency that resolves, inside the pack. **The one base fixture that is not self-contained** — install `base/` whole |

## Index — `isolation/` (install one at a time, alone)

| Case | Covers | Why it must be alone | Staging |
|---|---|---|---|
| `invalid-port/` | a criterion that loads and cannot be evaluated: `Invalid data for port number or job name criteria…`, stderr, no row, trailing blank suppressed, exit 253 | measured as taking down the whole `check`; the control tells you whether it did | — |
| `criteria-comma/` | the companion value does **not** split on commas, so `55437,55438` is one invalid port — the same failure by a different route | as above | — (**leave 55437/55438 dead**) |
| `no-name/` | a definition with no `name:`. Upstream **discards** it with two stderr lines; RMSC **keeps** it | an extra row on one side lands in the middle of the byte-exact surface | — |
| `bad-filename/` | two non-matching filenames — wrong case, and an editor `.bak` — each warned about | a warning on every command | — |
| `malformed/` | a file that will not parse; upstream warns on stderr, RMSC on **stdout** (open finding 4) | as above, and the RMSC message lands among the `check` rows | — |
| `duplicate-criterion/` | two definitions claiming one **port**: upstream warns, naming both; RMSC does not warn at all (measured). Both should still be RUNNING with the same job under `jobinfo` | measured, not predicted — this warning is what rode along with every comparison when two base fixtures collided | **55443** |
| `duplicate-criterion-job/` | the same duplicate on a **job name**, to settle whether conflict detection covers job criteria at all. Expected silent | if it warns, it warns on every command — and `base/` has a job criterion shared by two fixtures that would then have to be reworked | — |
| `cluster/` | the `cluster:` key — accepted upstream, and required by the plan to be **rejected with a clear message, never silently ignored**, by RMSC | RMSC's rejection message rides along with every command | — |
| `dependency-cycle/` | a two-service cycle; upstream reports the hop list on stderr with 253, RMSC one line on **both** streams with 255 | as above. **When** the cycle is detected has not been measured — see the fixture header | — |

---

## What the pack has already found

On its first run against both implementations, and worth reading as evidence that fixtures
derived from a machine's own definitions cannot substitute for fixtures a repository owns —
none of these was reachable before:

1. **The service list is not sorted.** Upstream sorts alphabetically; RMSC returns
   directory-read order. This is on the byte-exact path, and it passed on the box only because
   the three real definitions there happen to be read in alphabetical order. See installation
   note 4: copy the pack in reverse so this cannot hide again.
2. **A trailing YAML comment is not stripped.** `rmscgate_comments.yaml` writes
   `name: RMSC gate comments   # a trailing comment after a value`; RMSC carries the comment
   into the description, upstream does not. The description is the parenthesised field the
   consumer parses.
3. **RMSC emits no check-alive conflict warning**, where upstream warns and names every service
   sharing the criterion — now measured on both sides rather than read from upstream's source.

And one fault in the pack itself, fixed: `rmscgate_partial_multi` and `rmscgate_partial_seq`
both claimed `PORT:22`, so upstream's conflict warning fired on **every** comparison from
`base/`, and `isolation/duplicate-criterion` could no longer show anything the base pack was not
already showing. `partial_multi` now uses staged port 55433, port 22 belongs to `partial_seq`
alone, and `check-pack.py` fails the pack if that is ever undone. The mistake was not wasted:
it measured upstream's warning text for free, and that text is now the expectation in
`isolation/duplicate-criterion` rather than a guess.

A related loose end it exposed, now pinned rather than assumed: three base fixtures shared
`JOBNAME:QP0ZSPWP` in that same run and upstream said nothing about them, while warning about
the port collision immediately. That suggests conflict detection covers port criteria and not
job ones — but the three did not all spell the criterion the same way, so the silence has more
than one explanation. `rmscgate_type_case` has been moved off the shared criterion (its
liveness never mattered; asserting its own value is the stronger test), leaving one deliberate
pair, and `isolation/duplicate-criterion-job` now asks the question directly with two identically
spelled definitions. If that case warns, the remaining pair in `base/` has to be reworked.

---

## Basis, and what a red result means

Every header names its basis, in the vocabulary `tools/error-delivery-test.sh` already uses:

| | |
|---|---|
| **measured** | observed side by side against the installed `sc` 1.7.1. A failure is a defect or a moved reference — check the reference before acting. |
| **inferred** | follows from a written contract or from upstream's source as quoted in `docs/parity.md`, not from anything observed. Ask whether the inference was wrong before assuming the implementation is. |
| **chosen** | the pack decides, because nothing settles it — invented group membership, or a plan requirement with no upstream measurement behind it. The expectation is the two implementations agreeing with each other, or the plan's own words. |

Some fixtures are expected to **differ**, and a sudden match is a failure too — the same rule
`tools/fidelity-gate.sh` already applies, which "fails when something regresses **and** when
something is fixed without the list being updated". `rmscgate_type_port`, `no-name/`,
`dependency-cycle/`, `malformed/` and the `info` group all carry recorded differences. If one of
them starts matching, `docs/parity.md` and the plan's key table need updating in the same change
— not a green tick.

## Deliberately not covered

- **YAML 1.1 scalar typing** — `022` as 18, `1_000` as 1000, `+8080` losing its sign.
  `docs/parity.md` records this as a difference **deliberately not being chased**, so no fixture
  depends on it, and every numeric value here is written so that both readers agree: no leading
  zeros, no underscores, no signs.
- **Colour.** Every comparison runs with stdout redirected, so colour is off. The known
  difference — upstream colours the `[not running at -->…]` suffix and RMSC does not — needs a
  person at a terminal, and no fixture can reach it.
- **A status field wide enough to push `|` past column 22.** Upstream pads to 18 without
  truncating, so a four-digit criterion count would overflow the column. Reproducing it needs a
  definition with a thousand criteria; it is in the project's TODO as a quirk to mirror rather
  than fix, and no fixture here attempts it.
- **`scrc` / `SC_OPTIONS`.** Upstream reads both and RMSC reads neither, which changes which
  services a bare `check` shows. That is an input to the *command*, not a service definition, so
  it cannot be expressed in this pack — it needs a harness case of its own.
- **`start` / `stop` / `kill` / `restart`.** Nothing here is meant to be started. The lifecycle
  is covered by `SCLIFE.TEST`, against a service the suite creates and removes.
