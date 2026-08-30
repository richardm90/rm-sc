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

The suite covers each family directly. The fallthrough case needs the listener running, so it
is a documented procedure rather than an automated test - which is a real gap, not a
resolution.
