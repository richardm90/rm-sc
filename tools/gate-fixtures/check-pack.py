#!/usr/bin/env python3
"""Guard the fixture pack against the mistakes it is easy to make.

Run it after editing or adding a fixture, and before installing:

    python3 check-pack.py [pack-dir]

Three checks, each of which has already caught a real problem:

  filenames    Upstream loads a file only if its name matches
               ^([a-z\\-_0-9]+)\\.y[a]{0,1}ml$ - lower case only. A name that
               misses is ignored with a warning, except one ending rpmnew which
               is ignored silently. Files that are MEANT to be rejected live in
               isolation/bad-filename and base/rmscgate_rpmnew.yaml.rpmnew; a
               rejected name anywhere else is a fixture that quietly tests
               nothing.

  duplicates   Two definitions sharing one check-alive criterion make upstream
               warn about the conflict on EVERY command, so a duplicate inside
               base/ perturbs every other comparison in the pack and steals the
               one thing isolation/duplicate-criterion exists to show. That
               happened: rmscgate_partial_multi and rmscgate_partial_seq both
               claimed PORT:22. One deliberate duplicate remains in base/ and is
               listed as expected below.

  staging      Every port a fixture needs a listener on is declared in that
               fixture's own header, so the harness and the pack cannot drift.
               This prints the list to stage and the list that must stay dead.

Exits non-zero if anything is wrong, so it can go in front of a gate run.
"""

import os
import re
import sys
import collections

NAME_RX = re.compile(r'^([a-z\-_0-9]+)\.y[a]{0,1}ml$')
PORT_RX = re.compile(r'\b(554[0-6][0-9])\b')

# Deliberate exceptions, each with the reason it is allowed. Anything not named
# here is reported.
ALLOWED_BAD_NAMES = {
    'rmscgate_rpmnew.yaml.rpmnew': 'fixture: the one non-matching name ignored silently',
    'rmscgate_Ignored.yaml':       'fixture: a non-matching name, warned about',
    'rmscgate_backup.yaml.bak':    'fixture: a non-matching extension, warned about',
}
ALLOWED_DUPLICATES = {
    'JOBNAME:QP0ZSPWP': 'rmscgate_job_up + rmscgate_type_jobname - the only job the '
                        'pack can rely on being alive; measured as not tripping '
                        "upstream's conflict warning, which "
                        'isolation/duplicate-criterion-job pins',
}
STAGED_RANGE = range(55430, 55450)


def scalars(path):
    """The check_alive / check_alive_criteria values, without a YAML library."""
    ca, cc, seq = None, None, []
    in_seq = False
    for line in open(path, errors='replace'):
        if line.startswith('#'):
            continue
        if line.startswith('  - ') and in_seq:
            seq.append(line[4:].split('#')[0].strip())
            continue
        in_seq = False
        if line.startswith('check_alive:'):
            v = line.split(':', 1)[1].split('#')[0].strip()
            if v == '':
                in_seq = True
            else:
                ca = v
        elif line.startswith('check_alive_criteria:'):
            cc = line.split(':', 1)[1].split('#')[0].strip()
    return (seq if seq else ca), cc


def criteria(path):
    """Render as upstream would: PORT:<text> or JOBNAME:<upper-cased text>."""
    ca, cc = scalars(path)
    if isinstance(ca, list):
        items = ca
    elif isinstance(ca, str) and ca.lower() in ('port', 'jobname') and cc is not None:
        return ['%s:%s' % (ca.upper(), cc)]
    elif ca is None:
        return []
    else:
        items = [s.strip() for s in ca.split(',')]
    return ['PORT:' + i if i.isdigit() else 'JOBNAME:' + i.upper() for i in items]


def staged_ports(path):
    """Ports the header declares a listener is REQUIRED on."""
    want, active = set(), False
    for line in open(path, errors='replace'):
        if line.startswith('# STAGING'):
            active = 'REQUIRED' in line
            if active:
                want |= {int(p) for p in PORT_RX.findall(line)}
        elif active and line.startswith('#') and not re.match(r'# [A-Z]', line):
            want |= {int(p) for p in PORT_RX.findall(line)}
        elif line.startswith('# ') and re.match(r'# [A-Z]{4,}', line):
            active = False
    return want


def main():
    pack = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    problems = []
    groups = collections.defaultdict(lambda: collections.defaultdict(list))
    stage, dead = collections.defaultdict(set), set()

    for root, dirs, files in os.walk(pack):
        dirs[:] = [d for d in dirs if not d.endswith('.yaml')]   # the subdir fixture
        rel = os.path.relpath(root, pack)
        for f in sorted(files):
            if f in ('README.md', 'check-pack.py'):
                continue
            path = os.path.join(root, f)
            if not NAME_RX.match(f):
                if f not in ALLOWED_BAD_NAMES:
                    problems.append('%s/%s will not be loaded - the filename does '
                                    'not match upstream\'s regex, and it is not one '
                                    'of the fixtures that is meant not to' % (rel, f))
                continue
            if 'malformed' in f:
                continue
            for c in criteria(path):
                groups[rel][c].append(f)
            for p in staged_ports(path):
                stage[p].add('%s/%s' % (rel, f))
            for c in criteria(path):
                if c.startswith('PORT:') and c[5:].isdigit():
                    n = int(c[5:])
                    if n not in staged_ports(path) and n != 22:
                        dead.add(n)

    for rel in sorted(groups):
        # The duplicate-criterion cases exist TO duplicate. For them the check is
        # inverted: a shared criterion is required, and losing it - by an edit
        # that renames one side - would leave a case that quietly tests nothing.
        if 'duplicate-criterion' in rel:
            shared = [c for c, f in groups[rel].items() if len(f) > 1]
            if not shared:
                problems.append('%s: no criterion is shared any more, so the case '
                                'no longer tests a duplicate' % rel)
            else:
                print('%s duplicates on %s, as intended' % (rel, ', '.join(shared)))
            continue
        for c, files in sorted(groups[rel].items()):
            if len(files) > 1 and c not in ALLOWED_DUPLICATES:
                problems.append('%s: %d services share %s (%s) - upstream warns '
                                'about the conflict on every command, so this '
                                'perturbs every other comparison' %
                                (rel, len(files), c, ', '.join(files)))

    print('stage a listener on: %s' %
          (', '.join(str(p) for p in sorted(stage)) or 'nothing'))
    for p in sorted(stage):
        print('    %d  %s' % (p, ', '.join(sorted(stage[p]))))
    # Anything in the staging range that a fixture mentions but does not ask to
    # have staged must stay dead - isolation/criteria-comma's 55437,55438 are
    # exactly that, and staging them would stop it detecting the change it is for.
    for root, dirs, files in os.walk(pack):
        dirs[:] = [d for d in dirs if not d.endswith('.yaml')]
        for f in files:
            if f in ('README.md', 'check-pack.py') or not NAME_RX.match(f):
                continue
            path = os.path.join(root, f)
            body = ''.join(l for l in open(path, errors='replace')
                           if not l.startswith('#'))
            for n in (int(x) for x in PORT_RX.findall(body)):
                if n in STAGED_RANGE and n not in stage:
                    dead.add(n)

    print('\nmust stay dead:     55450-55469 (the known-dead range) in full,')
    print('                    and %s' % ', '.join(str(p) for p in sorted(dead)))
    inrange = sorted(p for p in dead if p in STAGED_RANGE)
    if inrange:
        print('    NOTE inside the staging range, deliberately dead: %s' %
              ', '.join(str(p) for p in inrange))
    print('\nexpected duplicates kept:')
    for c, why in ALLOWED_DUPLICATES.items():
        print('    %-20s %s' % (c, why))

    print()
    if problems:
        for p in problems:
            print('PROBLEM: %s' % p)
        return 1
    print('pack OK: filenames load, no unexpected shared criteria')
    return 0


if __name__ == '__main__':
    sys.exit(main())
