#!/usr/bin/env python3
"""Hold ports open so a port criterion has something to find.

A definition whose check_alive names a port reports NOT RUNNING unless
something is actually listening. The fixture pack needs both answers, so the
harness stages its own listener rather than borrowing a service that happens
to be up: a fixture pointed at somebody else's port passes or fails according
to what that machine is doing, which is the accidental coverage the pack
exists to replace.

    gate-listen.py 55431 55432                 # IPv4, three minutes
    gate-listen.py --seconds 60 55431          # shorter
    gate-listen.py --v6only 55433              # IPv6 ONLY - see below

Prints one line per port, then READY on stdout once every port is bound. Wait
for that line rather than sleeping: a harness that sleeps and hopes reports a
service NOT RUNNING when the listener simply had not started yet, which looks
exactly like a defect in the thing under test.

Exits non-zero, before printing READY, if any port is already in use. That
matters more than it looks. A listener that silently failed to bind would
leave the fixture reporting NOT RUNNING, the comparison would still agree with
upstream - both see nothing listening - and the test would pass while proving
nothing at all. CLAUDE.md records three defects that shipped behind exactly
that shape.

The lifetime is bounded so a harness killed between staging and cleanup leaks
a process that goes away on its own rather than one that waits forever.

--v6only exists for SCNET's IPv6 fallthrough. Nothing on a typical IBM i
listens on IPv6 alone - services bind both families - so the IPv4 probe always
answers first and the fallthrough never runs. docs/testing-notes.md records
that branch being wrong from the day it was written for precisely that reason.
tools/v6listen.py already does this for the unit suite; this does it for a
real definition, so the path is reached through check rather than through a
procedure call.

29/08/2026 - RM - created
"""

import argparse
import socket
import sys
import time


def bind_one(port, v6only):
    """Bind and listen, or explain which port could not be had and why."""
    family = socket.AF_INET6 if v6only else socket.AF_INET
    s = socket.socket(family, socket.SOCK_STREAM)

    # Without IPV6_V6ONLY, binding '::' takes the IPv4 port too and the
    # listener is useless for testing the fallthrough - the IPv4 probe would
    # answer and the IPv6 branch would never run.
    if v6only:
        s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)

    # SO_REUSEADDR, and it is worth being precise about what it does here. It
    # allows binding a port whose previous socket is still in TIME_WAIT - our
    # own last run - and it does NOT allow binding a port something is
    # actively listening on, which still fails. So the guard below survives:
    # a real service on the port is still refused. Without this, a second run
    # within a couple of minutes of the first failed with "Address already in
    # use" while nothing was listening at all, which reads exactly like the
    # thing the guard exists to catch and is not it.
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        s.bind(('::' if v6only else '0.0.0.0', port))
    except OSError as err:
        sys.stderr.write(
            'gate-listen: cannot bind port %d: %s\n'
            '  Something is actively listening there, or the port is reserved.\n'
            '  A fixture pointed at this port would report NOT RUNNING and the\n'
            '  comparison would agree with upstream for the wrong reason.\n'
            % (port, err))
        return None

    s.listen(5)
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('ports', nargs='+', type=int, help='ports to hold open')
    ap.add_argument('--seconds', type=int, default=180,
                    help='how long to hold them (default 180)')
    ap.add_argument('--v6only', action='store_true',
                    help='bind IPv6 only, for the SCNET fallthrough')
    args = ap.parse_args()

    held = []
    for port in args.ports:
        s = bind_one(port, args.v6only)
        if s is None:
            for open_socket in held:
                open_socket.close()
            return 1
        held.append(s)
        print('listening %s on %d' % ('IPv6-only' if args.v6only else 'IPv4',
                                      port), flush=True)

    # The harness waits for this, so it must come after every bind.
    print('READY', flush=True)

    try:
        time.sleep(args.seconds)
    except KeyboardInterrupt:
        pass
    finally:
        for open_socket in held:
            open_socket.close()

    return 0


if __name__ == '__main__':
    sys.exit(main())
