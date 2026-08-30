#!/usr/bin/env python3
"""Hold an IPv6-ONLY listening socket open, so the IPv6 code path can be tested.

Nothing on a typical IBM i listens on IPv6 alone - services bind both families -
so the IPv4 probe in SCNET always answers first and the IPv6 fallthrough never
executes. That is how a real defect survived: the IPv6 qualifier needs binary
nulls where clear leaves blanks, and the API answered with an empty list and no
error, so every IPv6-only service would have looked stopped.

IPV6_V6ONLY is the point of this script. Without it, binding '::' takes the IPv4
port too and the listener is useless for the test.

    python3 v6listen.py 54321 [seconds]

Then, with RMSC on the library list:

    SCNET_port_listening(54321, SCNET_FAMILY_IPV4)  -> 0  not listening
    SCNET_port_listening(54321, SCNET_FAMILY_IPV6)  -> 1  listening
    SCNET_port_listening(54321)                     -> 1  via the fallthrough

Confirm the socket really is IPv6-only first - LOCAL_ADDRESS should be '::' with
no IPv4 row alongside it:

    SELECT LOCAL_ADDRESS, LOCAL_PORT, TCP_STATE
      FROM QSYS2.NETSTAT_INFO WHERE LOCAL_PORT = 54321
"""
import socket
import sys
import time

port = int(sys.argv[1]) if len(sys.argv) > 1 else 54321
seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 180

s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('::', port))
s.listen(5)
print('listening IPv6-only on %d for %ds' % (port, seconds), flush=True)
time.sleep(seconds)
s.close()
