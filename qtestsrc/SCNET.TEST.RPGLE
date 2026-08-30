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
