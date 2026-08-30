**free

//==============================================================================
// SCNET.TEST - Network status API test suite
//
// SCNET replaces a SQL query with a direct system API, so the assertions that
// matter are that it agrees with the thing it replaced. Speed is not worth
// anything if the answer changes.
//
// 30/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCNET_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

///
// Socket calls, so the suite can create an IPv6-only listener of its own.
//
// The constants are the ILE ones from QSYSINC, not the PASE ones - they
// differ where it matters. SO_REUSEADDR is 55 here and 0x0004 in PASE,
// SOL_SOCKET is -1 and not 0xffff, and IPV6_V6ONLY is 100 and not 37.
///

dcl-pr c_socket int(10) extproc('socket');
  domain   int(10) value;
  type     int(10) value;
  protocol int(10) value;
end-pr;

dcl-pr c_setsockopt int(10) extproc('setsockopt');
  fd      int(10) value;
  level   int(10) value;
  optname int(10) value;
  optval  pointer value;
  optlen  int(10) value;
end-pr;

dcl-pr c_bind int(10) extproc('bind');
  fd      int(10) value;
  addr    pointer value;
  addrlen int(10) value;
end-pr;

dcl-pr c_listen int(10) extproc('listen');
  fd      int(10) value;
  backlog int(10) value;
end-pr;

dcl-pr c_close int(10) extproc('close');
  fd int(10) value;
end-pr;

dcl-c AF_INET6      const(24);
dcl-c SOCK_STREAM   const(1);
dcl-c IPPROTO_IPV6  const(41);
dcl-c IPV6_V6ONLY   const(100);

// A port nothing on this system claims
dcl-c V6_TEST_PORT const(54321);

dcl-pr open_v6_listener int(10);
  port like(INTEGER_t) const;
end-pr;

// SSH. The suite reaches this system over it, so it is listening.
dcl-c SSH_PORT const(22);
// Nothing listens here
dcl-c UNUSED_PORT const(59417);

//==============================================================================
// The API answers, rather than falling back
//
// A fallback is not a failure - the SQL path still gives the right answer -
// but it means the API is not being used, and the whole point is that it is.
//==============================================================================

dcl-proc test_api_is_available export;

  dcl-s rc like(INTEGER_t);

  rc = SCNET_port_listening(SSH_PORT);

  assert((rc <> SCNET_UNAVAILABLE):
         'the API answered rather than falling back - ' +
         %trim(SCNET_last_error()));

end-proc;

//==============================================================================
// It agrees with the SQL query it replaced
//==============================================================================

dcl-proc test_agrees_on_listening_port export;

  nEqual(true: SCQRY_port_listening(SSH_PORT): 'SSH reported listening');
  iEqual(SCNET_LISTENING: SCNET_port_listening(SSH_PORT): 'and by the API');

end-proc;

dcl-proc test_agrees_on_dead_port export;

  nEqual(false: SCQRY_port_listening(UNUSED_PORT): 'unused port not listening');
  iEqual(SCNET_NOT_LISTENING: SCNET_port_listening(UNUSED_PORT):
         'and by the API');

end-proc;

//==============================================================================
// A spread of ports, checked against the SQL path
//
// This is the assertion that would catch a wrong field offset: a layout error
// does not raise anything, it just returns a plausible wrong answer.
//==============================================================================

dcl-proc test_agrees_across_many_ports export;

  dcl-s ports int(10) dim(9);
  dcl-s i     like(INTEGER_t);
  dcl-s api   like(BOOLEAN_t);
  dcl-s sql   like(BOOLEAN_t);

  ports(1) = 21;
  ports(2) = 22;
  ports(3) = 23;
  ports(4) = 80;
  ports(5) = 443;
  ports(6) = 992;
  ports(7) = 2001;
  ports(8) = 8076;
  ports(9) = 59417;

  for i = 1 to %elem(ports);
    api = (SCNET_port_listening(ports(i)) = SCNET_LISTENING);
    sql = SCQRY_port_listening(ports(i));
    nEqual(sql: api: 'port ' + %char(ports(i)) + ' agrees with SQL');
  endfor;

end-proc;

//==============================================================================
// Repeated calls are stable
//
// The user space is reused across calls rather than recreated, so a stale
// result would show up here.
//==============================================================================

dcl-proc test_repeated_calls_stable export;

  dcl-s i like(INTEGER_t);

  for i = 1 to 5;
    iEqual(SCNET_LISTENING: SCNET_port_listening(SSH_PORT):
           'call ' + %char(i) + ' still sees SSH');
    iEqual(SCNET_NOT_LISTENING: SCNET_port_listening(UNUSED_PORT):
           'call ' + %char(i) + ' still sees the unused port as free');
  endfor;

end-proc;

//==============================================================================
// A port outside the valid range does not report something listening
//==============================================================================

dcl-proc test_out_of_range_port export;

  assert((SCNET_port_listening(0) <> SCNET_LISTENING):
         'port 0 is not listening');

end-proc;

//==============================================================================
// Each address family works on its own
//
// These exist because the default path short circuits: services here bind both
// families, so the IPv4 probe always answers first and the IPv6 code would
// never run. It was in fact broken - the IPv6 qualifier needs binary nulls to
// mean "every address", and blanks give an empty list with no error - and no
// test could have caught it without asking for that family directly.
//==============================================================================

dcl-proc test_ipv4_family_directly export;

  iEqual(SCNET_LISTENING:
         SCNET_port_listening(SSH_PORT: SCNET_FAMILY_IPV4):
         'SSH found over IPv4');
  iEqual(SCNET_NOT_LISTENING:
         SCNET_port_listening(UNUSED_PORT: SCNET_FAMILY_IPV4):
         'unused port not found over IPv4');

end-proc;

dcl-proc test_ipv6_family_directly export;

  iEqual(SCNET_LISTENING:
         SCNET_port_listening(SSH_PORT: SCNET_FAMILY_IPV6):
         'SSH found over IPv6');
  iEqual(SCNET_NOT_LISTENING:
         SCNET_port_listening(UNUSED_PORT: SCNET_FAMILY_IPV6):
         'unused port not found over IPv6');

end-proc;

//==============================================================================
// The default finds a service on either family
//==============================================================================

dcl-proc test_any_family_agrees export;

  dcl-s v4 like(INTEGER_t);
  dcl-s v6 like(INTEGER_t);
  dcl-s any like(INTEGER_t);

  v4  = SCNET_port_listening(SSH_PORT: SCNET_FAMILY_IPV4);
  v6  = SCNET_port_listening(SSH_PORT: SCNET_FAMILY_IPV6);
  any = SCNET_port_listening(SSH_PORT);

  assert((v4 = SCNET_LISTENING or v6 = SCNET_LISTENING):
         'at least one family sees SSH');
  iEqual(SCNET_LISTENING: any: 'and the default agrees');

end-proc;

//==============================================================================
// open_v6_listener
//   An IPv6-ONLY listening socket, held open by the caller
//
// IPV6_V6ONLY is the whole point. Without it, binding the unspecified address
// takes the IPv4 port too, and the listener proves nothing about the IPv6
// path - which is the path that was broken.
//==============================================================================

dcl-proc open_v6_listener;
  dcl-pi *n int(10);
    port like(INTEGER_t) const;
  end-pi;

  // 28 bytes, per QSYSINC. sin6_len then sin6_family, IBM i's BSD style.
  dcl-ds addr qualified len(28);
    sin6_len      uns(3)  pos(1);
    sin6_family   uns(3)  pos(2);
    sin6_port     uns(5)  pos(3);
    sin6_flowinfo uns(10) pos(5);
    sin6_addr     char(16) pos(9);
    sin6_scope    uns(10) pos(25);
  end-ds;

  dcl-s fd  int(10);
  dcl-s one int(10) inz(1);
  dcl-s rc  int(10);

  fd = c_socket(AF_INET6: SOCK_STREAM: 0);
  if fd < 0;
    return -1;
  endif;

  rc = c_setsockopt(fd: IPPROTO_IPV6: IPV6_V6ONLY: %addr(one): %size(one));
  if rc < 0;
    c_close(fd);
    return -2;
  endif;

  clear addr;
  addr.sin6_len    = 28;
  addr.sin6_family = AF_INET6;
  addr.sin6_port   = port;
  addr.sin6_addr   = *ALLx'00';   // the unspecified address, every interface

  rc = c_bind(fd: %addr(addr): 28);
  if rc < 0;
    c_close(fd);
    return -3;
  endif;

  rc = c_listen(fd: 5);
  if rc < 0;
    c_close(fd);
    return -4;
  endif;

  return fd;

end-proc;

//==============================================================================
// The fallthrough: IPv4 finds nothing, IPv6 finds it
//
// This is the case IPv6 support exists for, and until the suite could create
// an IPv6-only listener it had never run - every service on a normal system
// binds both families, so the IPv4 probe always answered first. That is how
// the binary-nulls defect survived.
//==============================================================================

dcl-proc test_ipv6_only_service_is_found export;

  dcl-s fd int(10);

  fd = open_v6_listener(V6_TEST_PORT);
  assert((fd >= 0): 'opened an IPv6-only listener, rc ' + %char(fd));

  monitor;
    // IPv4 must NOT see it - if it does, the listener is not IPv6-only and
    // the rest of this test proves nothing
    iEqual(SCNET_NOT_LISTENING:
           SCNET_port_listening(V6_TEST_PORT: SCNET_FAMILY_IPV4):
           'not visible over IPv4, so the listener really is IPv6-only');

    iEqual(SCNET_LISTENING:
           SCNET_port_listening(V6_TEST_PORT: SCNET_FAMILY_IPV6):
           'visible over IPv6');

    // The default must find it, which it can only do by falling through
    iEqual(SCNET_LISTENING:
           SCNET_port_listening(V6_TEST_PORT):
           'found by the default, via the IPv4-miss to IPv6 fallthrough');

    // And the public entry point agrees
    nEqual(true: SCQRY_port_listening(V6_TEST_PORT):
           'SCQRY agrees');
  on-error;
    c_close(fd);
    return;
  endmon;

  c_close(fd);

end-proc;

//==============================================================================
// Once the listener closes, the port reads as free again
//
// Guards against a cached or stale answer inside SCNET, which reuses its user
// space across calls.
//==============================================================================

dcl-proc test_port_free_after_listener_closes export;

  dcl-s fd int(10);

  fd = open_v6_listener(V6_TEST_PORT);
  assert((fd >= 0): 'opened listener, rc ' + %char(fd));

  iEqual(SCNET_LISTENING: SCNET_port_listening(V6_TEST_PORT):
         'listening while open');

  c_close(fd);

  iEqual(SCNET_NOT_LISTENING: SCNET_port_listening(V6_TEST_PORT):
         'not listening once closed');

end-proc;
