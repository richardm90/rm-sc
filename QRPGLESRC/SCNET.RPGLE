**free

//==============================================================================
// SCNET      - Network status via QtocLstNetCnn
//
// Asks the TCP/IP stack whether anything is listening on a port, instead of
// asking the SQL engine.
//
// The reason is measured, not assumed. QSYS2.NETSTAT_INFO costs about 376ms
// per call on this system - and that is not the enumeration: counting every
// connection, or returning every row and column, costs the same, and PASE
// netstat produces the same data in 75ms including a process fork. The cost
// is the SQL table function layer, and this API skips it.
//
// Two details matter for correctness:
//
//   - NCNN0100 is IPv4 only. A service listening on IPv6 alone would look
//     down, so NCNN0200 is checked too. IPv4 first, because that is the
//     common case and finding it there avoids the second call.
//   - If the API cannot answer, this says so rather than saying "nothing is
//     listening". The caller falls back to SQL. Slow is recoverable;
//     reporting a running service as down is not.
//
// 30/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Network status via QtocLstNetCnn');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCNET_D.rpgleinc'
/include 'SCYAML_D.rpgleinc'
/include 'include/RMSPACE_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// QtocLstNetCnn, from service program QTOCNETSTS. Threadsafe per the API
// documentation.
///

dcl-pr QtocLstNetCnn extproc('QtocLstNetCnn');
  usrspc    char(20)  const;
  format    char(8)   const;
  qualifier char(112) const options(*varsize);
  qual_size int(10)   const;
  qual_fmt  char(8)   const;
  errcode   char(272) options(*varsize);
end-pr;

dcl-c SPACE_LIB  const('QTEMP');
dcl-c SPACE_NAME const('SCNETCNN');

// Documented sizes
dcl-c NCLQ0100_SIZE const(64);
dcl-c NCLQ0200_SIZE const(112);

// TCP state 0 is Listen
dcl-c TCP_STATE_LISTEN const(0);

///
// The user space is created once per activation. Creating it per call would
// give back a good part of what the API saves.
///

dcl-s g_space_ready like(BOOLEAN_t) inz(false);
dcl-s g_error      like(SCYAML_ERROR_t) inz('');

dcl-pr probe like(INTEGER_t);
  port    like(INTEGER_t) const;
  ipv6    like(BOOLEAN_t) const;
end-pr;

//==============================================================================
// SCNET_port_listening
//==============================================================================

dcl-proc SCNET_port_listening export;
  dcl-pi *n like(INTEGER_t);
    port   like(INTEGER_t) const;
    family like(INTEGER_t) const options(*nopass);
  end-pi;

  dcl-s rc like(INTEGER_t);
  dcl-s want like(INTEGER_t) inz(SCNET_FAMILY_ANY);

  if %parms() >= 2;
    want = family;
  endif;

  g_error = '';

  if not g_space_ready;
    SPACE_create(SPACE_LIB: SPACE_NAME: '': 8192: x'00': '*ALL':
                 'RMSC network status': '*YES');
    g_space_ready = true;
  endif;

  if want = SCNET_FAMILY_IPV6;
    return probe(port: true);
  endif;

  // IPv4 first: the common case, and finding it here skips the second call
  rc = probe(port: false);
  if want = SCNET_FAMILY_IPV4;
    return rc;
  endif;

  if rc = SCNET_LISTENING or rc = SCNET_UNAVAILABLE;
    return rc;
  endif;

  return probe(port: true);

end-proc;

//==============================================================================
// probe
//   One address family
//==============================================================================

dcl-proc probe;
  dcl-pi *n like(INTEGER_t);
    port like(INTEGER_t) const;
    ipv6 like(BOOLEAN_t) const;
  end-pi;

  // NCLQ0100 - IPv4 connection list qualifier
  dcl-ds q4 qualified len(NCLQ0100_SIZE);
    cnn_type char(10) pos(1);
    req_type char(10) pos(11);
    reserved char(12) pos(21);
    addr_lo  int(10)  pos(33);
    addr_hi  int(10)  pos(37);
    port_lo  int(10)  pos(41);
    port_hi  int(10)  pos(45);
    raddr_lo int(10)  pos(49);
    raddr_hi int(10)  pos(53);
    rport_lo int(10)  pos(57);
    rport_hi int(10)  pos(61);
  end-ds;

  // NCLQ0200 - IPv6. The address fields are character but hold binary, and
  // all-nulls means "every address".
  dcl-ds q6 qualified len(NCLQ0200_SIZE);
    cnn_type char(10) pos(1);
    req_type char(10) pos(11);
    reserved char(12) pos(21);
    addr_lo  char(16) pos(33);
    addr_hi  char(16) pos(49);
    port_lo  int(10)  pos(65);
    port_hi  int(10)  pos(69);
    raddr_lo char(16) pos(73);
    raddr_hi char(16) pos(89);
    rport_lo int(10)  pos(105);
    rport_hi int(10)  pos(109);
  end-ds;

  dcl-ds errcode qualified len(272);
    provided  int(10) pos(1);
    available int(10) pos(5);
    excpid    char(7) pos(9);
  end-ds;

  // Standard generic list header
  dcl-ds hdr qualified based(p_space);
    status     char(1) pos(104);
    off_list   int(10) pos(125);
    entries    int(10) pos(133);
    entry_size int(10) pos(137);
  end-ds;

  dcl-ds e4 qualified based(p_ent);
    local_port int(10) pos(45);
    tcp_state  int(10) pos(49);
  end-ds;

  dcl-ds e6 qualified based(p_ent);
    local_port int(10) pos(133);
    tcp_state  int(10) pos(137);
  end-ds;

  dcl-s p_space pointer;
  dcl-s p_ent   pointer;
  dcl-s i       like(INTEGER_t);
  dcl-s qualname char(20);
  dcl-s nm char(10) inz(SPACE_NAME);
  dcl-s lb char(10) inz(SPACE_LIB);

  // The API wants the name in positions 1-10 and the library in 11-20, so both
  // halves must be padded to ten. Concatenating the bare constants gives
  // 'SCNETCNNQTEMP', which the API reads as a name of SCNETCNNQT in library
  // EMP - and reports only as TCP84C5, 'error providing list information'.
  qualname = nm + lb;

  clear errcode;
  errcode.provided = 272;

  if ipv6;
    clear q6;
    q6.cnn_type = '*TCP';
    q6.req_type = '*SUBSET';
    q6.port_lo  = port;
    q6.port_hi  = 0;

    // The address fields must be BINARY NULLS to mean "every address". They
    // are declared character, and clear leaves them as blanks - which the API
    // accepts and answers with an empty list, no error. Every IPv6-only
    // service would have looked stopped.
    q6.addr_lo  = *ALLx'00';
    q6.addr_hi  = *ALLx'00';
    q6.raddr_lo = *ALLx'00';
    q6.raddr_hi = *ALLx'00';
    QtocLstNetCnn(qualname: 'NCNN0200': q6: NCLQ0200_SIZE: 'NCLQ0200': errcode);
  else;
    clear q4;
    q4.cnn_type = '*TCP';
    q4.req_type = '*SUBSET';
    q4.port_lo  = port;
    q4.port_hi  = 0;
    QtocLstNetCnn(qualname: 'NCNN0100': q4: NCLQ0100_SIZE: 'NCLQ0100': errcode);
  endif;

  if errcode.available > 0;
    g_error = 'QtocLstNetCnn: ' + errcode.excpid;
    return SCNET_UNAVAILABLE;
  endif;

  p_space = SPACE_retrieve_pointer(SPACE_LIB: SPACE_NAME);
  if p_space = *null;
    g_error = 'Could not address the user space';
    return SCNET_UNAVAILABLE;
  endif;

  // 'C' is complete. Anything else means the list is partial or invalid, and
  // acting on a partial list would mean answering from incomplete data.
  if hdr.status <> 'C';
    g_error = 'List status ' + hdr.status;
    return SCNET_UNAVAILABLE;
  endif;

  for i = 1 to hdr.entries;
    p_ent = p_space + hdr.off_list + ((i - 1) * hdr.entry_size);
    if ipv6;
      if e6.local_port = port and e6.tcp_state = TCP_STATE_LISTEN;
        return SCNET_LISTENING;
      endif;
    else;
      if e4.local_port = port and e4.tcp_state = TCP_STATE_LISTEN;
        return SCNET_LISTENING;
      endif;
    endif;
  endfor;

  return SCNET_NOT_LISTENING;

end-proc;

//==============================================================================
// SCNET_last_error
//==============================================================================

dcl-proc SCNET_last_error export;
  dcl-pi *n like(SCYAML_ERROR_t) end-pi;

  return g_error;

end-proc;
