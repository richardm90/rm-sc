#!/usr/bin/env python3
"""Hold a port open and ignore SIGTERM for a bounded, self-timed period.

docs/parity.md's "stop did not escalate when its own stop_cmd failed" section
left two texts unmeasured on purpose: the no-stop_cmd path's own
ENDJOB(*CNTRLD)-then-ENDJOB(*IMMED) escalation, which needs a job that
survives past the first ENDJOB before it can be observed at all. Measuring
that live means staging something that genuinely resists ENDJOB for a while -
this is that fixture, built only after checking what IBM i actually
guarantees (see "WHY THIS IS SAFE" below), and only after Richard confirmed
going ahead with it on 1 October 2026.

    gate-resist.py --resist 35 65475      # survives 35s regardless of SIGTERM
    gate-resist.py --resist 0 65476       # resists nothing - an ordinary listener

Prints READY once bound, the same convention tools/gate-listen.py uses, for
the same reason: a harness that sleeps-and-hopes instead of waiting for READY
can mistake "hadn't started yet" for "the thing under test is broken".

WHY THIS IS SAFE - researched against IBM i's own documentation before this
file was written, then confirmed live (not just trusted) against this exact
fixture on 1 October 2026:

  ENDJOB OPTION(*CNTRLD) delivers SIGTERM to a job with an established
  handler, and forces the job down by itself once DELAY expires if the
  handler hasn't finished - it does not just give up and leave a job running
  forever.

  ENDJOB OPTION(*IMMED) also delivers SIGTERM to an established handler, but
  bounds how long that handler gets with the QENDJOBLMT system value -
  confirmed on the box this runs against at 120 seconds (the shipped
  default). Past that bound the system forces the job down regardless of what
  the handler does. So "ignore SIGTERM" is never "run forever" - it is bounded
  by a system value this script never has to know the exact value of, as long
  as --resist stays comfortably under it.

  --resist is refused above 90 seconds for exactly that margin, and every
  caller of this script additionally has its own kill -9 as an unconditional
  backstop (SIGKILL cannot be ignored, by any implementation, on any system) -
  the same belt-and-braces tools/stop-escalation-test.sh already relies on for
  its own cleanup.

WHAT WENT WRONG THE FIRST TIME THIS WAS TRIED, AND WHY THE except: pass IS
HERE. A naive version of this script - signal.signal(SIGTERM, lambda *_:
None), then a plain time.sleep(resist) - survived the FIRST SIGTERM
(ENDJOB(*CNTRLD)) exactly as expected, then crashed outright on the SECOND
(ENDJOB(*IMMED)): time.sleep() raised OSError(3456, 'Error 3456 occurred.')
instead of the PEP 475 EINTR auto-retry Linux would give it. That is a PASE
behaviour, not an ENDJOB behaviour - confirmed by sending a plain `kill -TERM`
by hand and watching the identical crash reproduce with no ENDJOB involved at
all. A fixture that crashes on exactly the second signal is indistinguishable
from "ENDJOB actually worked" to anything polling the port, which would have
made this fixture silently prove nothing. Every sleep below is wrapped
accordingly, and the loop re-reads the wall clock rather than trusting the
sleep's return, so any number of interrupted sleeps still adds up to the same
bound.

01/10/2026 - RM - created
"""

import argparse
import signal
import socket
import sys
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('port', type=int)
    ap.add_argument('--resist', type=int, default=10,
                     help='seconds to stay alive regardless of SIGTERM/SIGINT '
                          '(default 10; refused above 90 - see WHY THIS IS SAFE)')
    args = ap.parse_args()

    if args.resist > 90:
        sys.stderr.write(
            'gate-resist: refusing --resist=%d - more than 90s is too close\n'
            'to leave comfortable margin under QENDJOBLMT. Raise the cap in\n'
            'this script deliberately if a longer bound is ever needed.\n'
            % args.resist)
        return 2

    # Ignored, not left at default - the default for both is "terminate",
    # which would defeat the fixture's whole purpose.
    signal.signal(signal.SIGTERM, lambda *_a: None)
    signal.signal(signal.SIGINT, lambda *_a: None)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(('0.0.0.0', args.port))
    except OSError as err:
        sys.stderr.write('gate-resist: cannot bind port %d: %s\n' % (args.port, err))
        return 1
    s.listen(5)
    print('READY', flush=True)

    start = time.time()
    while time.time() - start < args.resist:
        try:
            time.sleep(0.5)
        except Exception:
            # See "WHAT WENT WRONG" above - a second (or third) signal
            # arriving mid-sleep raises here on this platform. Swallowing it
            # and re-checking the wall clock is what makes --resist a true
            # wall-clock bound instead of "however many sleeps completed".
            pass

    s.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
