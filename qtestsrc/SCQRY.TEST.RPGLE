**free

//==============================================================================
// SCQRY.TEST - System query test suite
//
// These run against live system state, so they assert what is reliably true
// on any IBM i rather than anything specific to one machine. Where a result
// cannot be predicted, the assertion is on the shape of the answer - that the
// query runs, returns a sane count and does not fall over.
//
// WHERE A COUNT IS ASSERTED, THE SUITE OWNS WHAT IT IS COUNTING.
//
// Two tests here used to count things the machine owns, and both failed
// spuriously and passed on an immediate re-run:
//
//   test_jobs_by_pgm_case_insensitive   two live sshd queries - Expected 7,
//                                       but was 8
//   test_jobs_on_port_is_listener_only  port 22 must be one job - 2 returned
//
// Neither was a defect. Every ssh connection to this machine forks another
// sshd, and while sshd is forking, the child holds the inherited listening
// socket for a moment - so for that moment TWO jobs have LOCAL_PORT=22 and
// REMOTE_PORT=0. "Exactly one" was a claim about sshd, not about the code, and
// a stronger claim than the code makes. A test may only assert the stability
// of something it controls.
//
// So this suite stages what it counts:
//
//   THE LISTENER  it opens a listening socket of its own on FIX_PORT, then
//                 connects to it and accepts, so the port carries a listener
//                 AND an established connection - the shape port 22 had, under
//                 our control rather than sshd's
//   THE PROGRAM   it submits a job running a PASE delay through a symbolic
//                 link of its own naming, so a job with a distinctive
//                 lower-case FUNCTION exists for the case-insensitivity test
//
// Keeping the connection matters. The defect these tests exist for was
// SCQRY_jobs_on_port returning a port's CLIENTS as well as its listener, and
// a staged listener with nothing connected to it gives that defect nothing to
// get wrong. What separates the two readings is the assertion about the
// CLIENT's port, not the count on FIX_PORT - see the header on
// test_jobs_on_port_is_listener_only, which says plainly what a single-socket
// fixture can and cannot reproduce.
//
// 29/08/2026 - RM - created
// 07/09/2026 - RM - staged listener and staged program replace port 22/sshd
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCQRY_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// A port nothing should be listening on. Not in the registered range and not
// something an IBM i or an open-source package claims.
dcl-c UNUSED_PORT const(59417);

// SSH. The suite reaches this system over it, so it is listening by
// definition while the tests are running. Used only where the assertion is
// "something is listening" - never for a count, which is what made this
// suite flaky.
dcl-c SSH_PORT const(22);

// The port THIS SUITE listens on. Not in the fixture pack's range
// (55431-55469) and nothing on this system claims it; the suite binds it
// itself, so a foreign listener makes set-up fail loudly rather than the suite
// quietly borrowing somebody else's socket.
//
// The port it connects FROM is whatever the system hands out, read back with
// getsockname. A fixed one was tried and is wrong: the connection's local port
// stays in TIME_WAIT for a couple of minutes after the suite ends, so a second
// run inside that window could not bind it and would fail for a reason that
// has nothing to do with the code - which is the flakiness this work exists to
// remove, reintroduced from the other end.
dcl-c FIX_PORT const(55499);

// The IBM i service monitor runs a JVM, so it is the fixture for asserting that
// jvm_info can SUCCEED rather than only that it fails politely.
dcl-c JVM_JOB const('QSRVMON');

// The job this suite submits, and the name the PASE delay runs under. A PASE
// program's FUNCTION is the basename it was started as, in the case it was
// written - so a symbolic link named in lower case gives the case-sensitivity
// check the same shape sshd gave it, on a job nobody else can start or end.
//
// The lower case matters and is not cosmetic. A lookup that upper-cases the
// stored value but not the argument, and one that upper-cases the argument but
// not the stored value, are both wrong; only a fixture whose stored value is
// LOWER case can tell the second one from a working lookup.
dcl-c PGM_JOB   const('RMSCQRYT');
dcl-c PGM_LOWER const('rmscqrysl');
dcl-c PGM_UPPER const('RMSCQRYSL');

// What the staged job runs. Present on every IBM i with PASE installed; if it
// is not, the job ends at once and set-up fails rather than the suite passing
// with nothing staged.
dcl-c PASE_SLEEP const('/QOpenSys/usr/bin/sleep');

// Long enough that the suite cannot outlive it, short enough that a job leaked
// by a run killed before its teardown goes away on its own
dcl-c PGM_RUNS_FOR const('600');

// The subsystem QUSRNOMAX is allocated to, and so the one the staged job runs
// in. A blank subsystem is delegated elsewhere; this is the argument that
// reaches the subsystem-qualified path, which nothing here could otherwise
// reach. A machine that runs QUSRNOMAX elsewhere fails the test below with a
// message saying so.
dcl-c PGM_SBS const('QUSRWRK');

// A subsystem that exists on every IBM i and is not the one the staged job
// runs in. Being the WRONG answer is the whole of its job.
dcl-c OTHER_SBS const('QCTL');

// How long to wait for the staged job to start, and to go away again
dcl-c WAIT_LIMIT const(60);

///
// Socket calls, so the suite can stage a listener and a client of its own.
//
// The constants are the ILE ones from QSYSINC, not the PASE ones - see
// docs/testing-notes.md, where they differ exactly where it matters.
///

dcl-pr c_socket int(10) extproc('socket');
  domain   int(10) value;
  type     int(10) value;
  protocol int(10) value;
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

dcl-pr c_connect int(10) extproc('connect');
  fd      int(10) value;
  addr    pointer value;
  addrlen int(10) value;
end-pr;

dcl-pr c_accept int(10) extproc('accept');
  fd      int(10) value;
  addr    pointer value;
  addrlen pointer value;
end-pr;

dcl-pr c_setsockopt int(10) extproc('setsockopt');
  fd      int(10) value;
  level   int(10) value;
  optname int(10) value;
  optval  pointer value;
  optlen  int(10) value;
end-pr;

dcl-pr c_getsockname int(10) extproc('getsockname');
  fd      int(10) value;
  addr    pointer value;
  addrlen pointer value;
end-pr;

dcl-pr c_close int(10) extproc('close');
  fd int(10) value;
end-pr;

dcl-c AF_INET     const(2);
dcl-c SOCK_STREAM const(1);

// The ILE values, not the PASE ones - see docs/testing-notes.md
dcl-c SOL_SOCKET   const(-1);
dcl-c SO_REUSEADDR const(55);

// 127.0.0.1, so the staged connection never leaves the machine
dcl-c LOOPBACK const(2130706433);

// The three sockets that make up the port fixture, held for the whole suite:
// the listener, the client connected to it, and the server side of that
// connection. Held open rather than opened per test so that a test which fails
// cannot leave a socket behind and make the next one fail for the wrong reason.
dcl-s g_listen_fd int(10) inz(-1);
dcl-s g_client_fd int(10) inz(-1);
dcl-s g_accept_fd int(10) inz(-1);

// The port the staged connection was given at its own end. Read back rather
// than chosen, and asserted about: a port carrying a connected socket and no
// listener is not a port anything is serving on.
dcl-s g_client_port like(INTEGER_t) inz(0);

// The staged job's full number/user/name, captured once it is running
dcl-s g_pgm_job like(SCQRY_JOBNAME_t);

// Where the symbolic link lives. Per user, so two people on one machine do not
// fight over the same path.
dcl-s g_dir varchar(256);
dcl-s g_lnk varchar(256);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr open_listener int(10);
  port like(INTEGER_t) const;
end-pr;

dcl-pr open_client int(10);
  remote_port like(INTEGER_t) const;
end-pr;

dcl-pr local_port_of like(INTEGER_t);
  fd int(10) const;
end-pr;

dcl-pr accept_one int(10);
  fd int(10) const;
end-pr;

dcl-pr start_pgm_job;
end-pr;

dcl-pr end_pgm_job;
end-pr;

dcl-pr job_in_list like(BOOLEAN_t);
  jobs likeds(SCQRY_JOBS_t);
  name like(SCQRY_JOBNAME_t) const;
end-pr;

dcl-pr names_of varchar(512);
  jobs likeds(SCQRY_JOBS_t);
end-pr;

dcl-pr is_staged_job like(BOOLEAN_t);
  name like(SCQRY_JOBNAME_t) const;
end-pr;

dcl-pr cmd_text varchar(512);
  cmd  varchar(256) const;
  qerr likeds(QCMD_ERR_t);
end-pr;

dcl-pr this_job varchar(64);
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-qry-fixture-' + %trim(psds.current_user);
  g_lnk = %trim(g_dir) + '/' + PGM_LOWER;

  // Debris from a run that was killed before its teardown. The harnesses all
  // sweep on entry as well as exit for the same reason.
  end_pgm_job();
  start_pgm_job();

  // THE PORT FIXTURE. Listener, then a client connected to it, then accept -
  // so the port carries both a listening socket and an established one, which
  // is the whole point of it.
  g_listen_fd = open_listener(FIX_PORT);
  assert((g_listen_fd >= 0):
         'staged a listener on port ' + %char(FIX_PORT) + ', rc ' +
         %char(g_listen_fd) + ' - a negative rc means the port could not be ' +
         'had, and every port assertion in this suite would otherwise pass ' +
         'against nothing');

  g_client_fd = open_client(FIX_PORT);
  assert((g_client_fd >= 0):
         'connected to it, rc ' + %char(g_client_fd));

  g_client_port = local_port_of(g_client_fd);
  assert((g_client_port > 0):
         'read back the port the connection was given at its own end, got ' +
         %char(g_client_port));

  g_accept_fd = accept_one(g_listen_fd);
  assert((g_accept_fd >= 0):
         'accepted the connection, rc ' + %char(g_accept_fd) +
         ' - without it the port carries no established socket and the ' +
         'listener-only test cannot fail');

end-proc;

dcl-proc tearDownSuite export;

  dcl-ds qerr likeds(QCMD_ERR_t);

  // Unconditionally, whatever the tests did
  // The CLIENT first, deliberately. Whichever end closes first holds the
  // connection in TIME_WAIT afterwards, and the client's port is one the
  // system handed out - so FIX_PORT is left clean for the next run rather than
  // spending two minutes unbindable.
  if g_client_fd >= 0;
    c_close(g_client_fd);
  endif;
  if g_accept_fd >= 0;
    c_close(g_accept_fd);
  endif;
  if g_listen_fd >= 0;
    c_close(g_listen_fd);
  endif;

  end_pgm_job();

  QCMD_exc('RMVLNK OBJLNK(''' + %trim(g_lnk) + ''')': qerr);
  QCMD_exc('RMVDIR DIR(''' + %trim(g_dir) + ''')': qerr);

end-proc;

//==============================================================================
// start_pgm_job
//   Submit a job running a PASE delay under a name of our own
//
// QP2SHELL runs the PASE program IN THE SUBMITTED JOB rather than spawning a
// new one, so the job name is ours to choose and the program name the system
// reports is the link's basename. That gives both fixtures at once: a job
// nobody else can start or end, and a lower-case FUNCTION to ask about.
//
// THE FIXTURE PROVES ITSELF. It waits for the job to exist and then for the
// program to be the one running in it, and FAILS if either never happens. A
// job that never started and a lookup that returns nothing look identical
// from a test's point of view, which is exactly how a suite comes to report
// success for a procedure that answered nothing.
//
// The second wait accepts EITHER spelling. Waiting only for the lower-case one
// would make a lookup that is broken in one direction fail here, in set-up,
// where the message would blame the fixture rather than the lookup.
//==============================================================================

dcl-proc start_pgm_job;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s waited like(INTEGER_t) inz(0);
  dcl-s ready  like(BOOLEAN_t) inz(false);
  dcl-s cmd    varchar(256);
  dcl-s ok     like(BOOLEAN_t);

  // Sweep, then stage. MKDIR and RMVLNK are allowed to fail - they are only
  // there so a leftover link or directory does not stop ADDLNK, which is the
  // one that has to work.
  QCMD_exc('RMVLNK OBJLNK(''' + %trim(g_lnk) + ''')': qerr);
  QCMD_exc('MKDIR DIR(''' + %trim(g_dir) + ''')': qerr);

  // The result is taken FIRST and the message built afterwards. Built in the
  // same expression, the two operands have no guaranteed evaluation order, so
  // the message can be assembled before qerr is filled - losing the message id
  // in exactly the run that needed it. These suites fail hard when a fixture
  // is missing, so this message is the whole diagnostic.
  cmd = 'ADDLNK OBJ(''' + PASE_SLEEP + ''') NEWLNK(''' + %trim(g_lnk) +
        ''') LNKTYPE(*SYMBOLIC)';
  ok  = QCMD_exc(cmd: qerr);
  assert(ok: 'staged the ' + PGM_LOWER + ' link to ' + PASE_SLEEP + ' - ' +
             cmd_text(cmd: qerr));

  cmd = 'SBMJOB CMD(CALL PGM(QP2SHELL) PARM(''' + %trim(g_lnk) + ''' ''' +
        PGM_RUNS_FOR + ''')) JOB(' + PGM_JOB + ') JOBQ(QUSRNOMAX)';
  ok  = QCMD_exc(cmd: qerr);
  assert(ok: 'submitted the staged job ' + PGM_JOB + ' - ' +
             cmd_text(cmd: qerr));

  dow waited < WAIT_LIMIT;
    if SCQRY_jobs_by_name(PGM_JOB: '': jobs) > 0;
      g_pgm_job = jobs.name(1);
      leave;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  assert((%len(%trim(g_pgm_job)) > 0):
         'staged job ' + PGM_JOB + ' started within ' + %char(WAIT_LIMIT) +
         's - every job assertion in this suite depends on it');

  // EXACTLY ONE, not merely at least one. A job left on the queue by a run
  // that was killed cannot be swept (end_pgm_job says why), and it shows up
  // here: two jobs of this name going active together would make the case
  // test's lists say two where they mean one. Said plainly here, it is one
  // legible failure instead of a scattering of odd ones.
  SCQRY_jobs_by_name(PGM_JOB: '': jobs);
  iEqual(1: jobs.count:
         'exactly one job named ' + PGM_JOB + ' is active - more than one ' +
         'means an earlier run left one on the job queue: ' + names_of(jobs) +
         '. End the ones that are not this run''s and try again');

  // Now wait for QP2SHELL to have reached the program. The job exists before
  // that happens, so without this wait the case test could ask before there
  // was anything to find.
  waited = 0;
  dow waited < WAIT_LIMIT;
    SCQRY_jobs_by_pgm(PGM_LOWER: jobs);
    if job_in_list(jobs: g_pgm_job);
      ready = true;
      leave;
    endif;
    SCQRY_jobs_by_pgm(PGM_UPPER: jobs);
    if job_in_list(jobs: g_pgm_job);
      ready = true;
      leave;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  assert(ready: 'staged job ' + %trim(g_pgm_job) + ' is running ' + PGM_LOWER +
                ' within ' + %char(WAIT_LIMIT) + 's - either the fixture ' +
                'never reached the program or no spelling of the name finds it');

end-proc;

//==============================================================================
// end_pgm_job
//   End it AND wait for it to actually go
//
// ENDJOB returns when the request is made, not when the job has ended - the
// same shortcut made SCLIFE.TEST flaky. See docs/testing-notes.md.
//==============================================================================

dcl-proc end_pgm_job;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s i      like(INTEGER_t);
  dcl-s waited like(INTEGER_t) inz(0);

  // A JOB STILL ON THE QUEUE IS INVISIBLE TO AN ACTIVE-JOB LOOKUP, and it
  // cannot be swept from here. The obvious remedy - ENDJOB by name, unadorned,
  // which does reach a queued job - was tried and MEASURED NOT TO WORK: every
  // fixture job this suite has ever ended still exists as a completed job
  // while its job log is pending, so the name is never unique and the command
  // is refused with CPF0906 "A duplicate job named ... was found", twenty
  // times over on the machine this was tested on. Ending it needs the job
  // NUMBER, which only a lookup that shows queued jobs could give, and that is
  // not something this suite has.
  //
  // So the leftover is DETECTED instead, in start_pgm_job, which fails if more
  // than one job of this name is active. The window that produces one is the
  // fraction of a second between SBMJOB and the job going active on a *NOMAX
  // queue - and if that queue is held, so that the window is wide, this
  // suite's own job does not start either and set-up says so.

  if SCQRY_jobs_by_name(PGM_JOB: '': jobs) = 0;
    return;
  endif;

  for i = 1 to jobs.count;
    // GUARDED. This ENDJOBs whatever a lookup returns, and that lookup is code
    // this project tests rather than trusts - a guard removed here once made a
    // lookup return far more than it should. If it ever returns every active
    // job, an unguarded sweep ends all of them, this suite's own job included.
    if is_staged_job(jobs.name(i));
      QCMD_exc('ENDJOB JOB(' + %trim(jobs.name(i)) +
               ') OPTION(*IMMED)': qerr);
    endif;
  endfor;

  dow waited < WAIT_LIMIT;
    if SCQRY_jobs_by_name(PGM_JOB: '': jobs) = 0;
      return;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  assert((SCQRY_jobs_by_name(PGM_JOB: '': jobs) = 0):
         'staged job ' + PGM_JOB + ' did not end within ' +
         %char(WAIT_LIMIT) + 's');

end-proc;

//==============================================================================
// The three socket helpers
//
// SO_REUSEADDR, and it is worth being precise about what it does here, because
// the guard this suite needs survives it. It allows binding a port whose last
// connection is still in TIME_WAIT - our own previous run - and it does NOT
// allow binding a port something is actively listening on, which still fails.
// So a foreign listener on FIX_PORT still makes set-up say so, which is what
// must happen: the suite cannot claim "exactly one job" about a port it does
// not own. tools/gate-listen.py's header records the same reasoning for its
// own port, and it was measured here too - without this, a second run inside
// two minutes of the first could not bind.
//==============================================================================

dcl-proc open_listener;
  dcl-pi *n int(10);
    port like(INTEGER_t) const;
  end-pi;

  // 16 bytes, per QSYSINC. sin_len then sin_family, IBM i's BSD style.
  dcl-ds addr qualified len(16);
    sin_len    uns(3)  pos(1);
    sin_family uns(3)  pos(2);
    sin_port   uns(5)  pos(3);
    sin_addr   uns(10) pos(5);
    sin_zero   char(8) pos(9);
  end-ds;

  dcl-s fd  int(10);
  dcl-s rc  int(10);
  dcl-s one int(10) inz(1);

  fd = c_socket(AF_INET: SOCK_STREAM: 0);
  if fd < 0;
    return -1;
  endif;

  rc = c_setsockopt(fd: SOL_SOCKET: SO_REUSEADDR: %addr(one): %size(one));
  if rc < 0;
    c_close(fd);
    return -4;
  endif;

  clear addr;
  addr.sin_len    = 16;
  addr.sin_family = AF_INET;
  addr.sin_port   = port;
  addr.sin_addr   = 0;              // every interface

  rc = c_bind(fd: %addr(addr): 16);
  if rc < 0;
    c_close(fd);
    return -2;
  endif;

  rc = c_listen(fd: 5);
  if rc < 0;
    c_close(fd);
    return -3;
  endif;

  return fd;

end-proc;

//==============================================================================
// open_client - a socket connected to a port of ours, from wherever
//
// It does NOT bind a chosen local port. The system hands one out on connect
// and local_port_of reads it back, which is what test_jobs_on_port_is_
// listener_only asks about: a port carrying a connected socket and nothing
// listening. A chosen port would be the same port every run, and the last
// run's connection holds it in TIME_WAIT.
//
// connect() completes without anyone having called accept() - the kernel
// finishes the handshake into the listen backlog - so this does not deadlock
// against a listener in the same job.
//==============================================================================

dcl-proc open_client;
  dcl-pi *n int(10);
    remote_port like(INTEGER_t) const;
  end-pi;

  dcl-ds peer qualified len(16);
    sin_len    uns(3)  pos(1);
    sin_family uns(3)  pos(2);
    sin_port   uns(5)  pos(3);
    sin_addr   uns(10) pos(5);
    sin_zero   char(8) pos(9);
  end-ds;

  dcl-s fd int(10);
  dcl-s rc int(10);

  fd = c_socket(AF_INET: SOCK_STREAM: 0);
  if fd < 0;
    return -1;
  endif;

  clear peer;
  peer.sin_len    = 16;
  peer.sin_family = AF_INET;
  peer.sin_port   = remote_port;
  peer.sin_addr   = LOOPBACK;

  rc = c_connect(fd: %addr(peer): 16);
  if rc < 0;
    c_close(fd);
    return -3;
  endif;

  return fd;

end-proc;

//==============================================================================
// local_port_of - the port this socket holds at its own end
//==============================================================================

dcl-proc local_port_of;
  dcl-pi *n like(INTEGER_t);
    fd int(10) const;
  end-pi;

  dcl-ds addr qualified len(16);
    sin_len    uns(3)  pos(1);
    sin_family uns(3)  pos(2);
    sin_port   uns(5)  pos(3);
    sin_addr   uns(10) pos(5);
    sin_zero   char(8) pos(9);
  end-ds;

  dcl-s addrlen int(10) inz(16);

  clear addr;
  if c_getsockname(fd: %addr(addr): %addr(addrlen)) < 0;
    return 0;
  endif;

  return addr.sin_port;

end-proc;

dcl-proc accept_one;
  dcl-pi *n int(10);
    fd int(10) const;
  end-pi;

  dcl-ds addr qualified len(16);
    sin_len    uns(3)  pos(1);
    sin_family uns(3)  pos(2);
    sin_port   uns(5)  pos(3);
    sin_addr   uns(10) pos(5);
    sin_zero   char(8) pos(9);
  end-ds;

  dcl-s addrlen int(10) inz(16);

  clear addr;
  return c_accept(fd: %addr(addr): %addr(addrlen));

end-proc;

//==============================================================================
// aEqualV - see docs/testing-notes.md
//==============================================================================

dcl-proc aEqualV;
  dcl-pi *n;
    expected varchar(512) const;
    actual   varchar(512) const;
    fieldName varchar(64) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(fieldName) + ': expected "' + %trim(expected) +
         '" but was "' + %trim(actual) + '"');

end-proc;

//==============================================================================
// job_in_list - is this exact qualified job name in the list
//==============================================================================

dcl-proc job_in_list;
  dcl-pi *n like(BOOLEAN_t);
    jobs likeds(SCQRY_JOBS_t);
    name like(SCQRY_JOBNAME_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to jobs.count;
    if %trimr(jobs.name(i)) = %trimr(name);
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// is_staged_job - is this qualified name one of OUR jobs
//
// number/user/name, so the job name is what follows the last slash. Nothing is
// ended unless that segment is the one this suite submitted.
//==============================================================================

dcl-proc is_staged_job;
  dcl-pi *n like(BOOLEAN_t);
    name like(SCQRY_JOBNAME_t) const;
  end-pi;

  dcl-s slash like(INTEGER_t);
  dcl-s last  like(INTEGER_t) inz(0);

  slash = %scan('/': name);
  dow slash > 0;
    last  = slash;
    slash = %scan('/': name: slash + 1);
  enddo;

  if last = 0;
    return false;
  endif;

  return (%trimr(%subst(name: last + 1)) = PGM_JOB);

end-proc;

//==============================================================================
// cmd_text - what the command said when it would not run
//==============================================================================

dcl-proc cmd_text;
  dcl-pi *n varchar(512);
    cmd  varchar(256) const;
    qerr likeds(QCMD_ERR_t);
  end-pi;

  if qerr.count = 0;
    return %trim(cmd);
  endif;

  return %trim(cmd) + ' : ' + %trim(qerr.msgs(1).msgid) + ' ' +
         %trim(qerr.msgs(1).text);

end-proc;

//==============================================================================
// names_of - every job in a list, so a failure says which rather than only how
//            many. Plain concatenation, not aEqual - see docs/testing-notes.md
//==============================================================================

dcl-proc names_of;
  dcl-pi *n varchar(512);
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s list varchar(512) inz('');

  for i = 1 to jobs.count;
    if i > 1;
      list += ', ';
    endif;
    list += %trim(jobs.name(i));
  endfor;

  if list = '';
    return '(none)';
  endif;

  return list;

end-proc;

//==============================================================================
// this_job - the job the suite is running in, as number/user/name
//
// The staged listener is in THIS job, so the port test can say which job it
// expects rather than only how many.
//==============================================================================

dcl-proc this_job;
  dcl-pi *n varchar(64);
  end-pi;

  return %trim(%editc(psds.job_number: 'X')) + '/' +
         %trim(psds.job_user) + '/' +
         %trim(psds.job_name);

end-proc;

//==============================================================================
// A listening port is reported as listening
//==============================================================================

dcl-proc test_port_listening export;

  nEqual(true: SCQRY_port_listening(SSH_PORT):
         'SSH is listening - this suite arrived over it');

  nEqual(true: SCQRY_port_listening(FIX_PORT):
         'and so is the listener this suite staged on port ' +
         %char(FIX_PORT));

end-proc;

dcl-proc test_port_not_listening export;

  nEqual(false: SCQRY_port_listening(UNUSED_PORT):
         'nothing is listening on an unused port');

end-proc;

//==============================================================================
// A port carrying only a connected socket is not a listening port
//
// The client end of the staged connection holds a port for the whole suite,
// and nothing is listening there. A probe that asked only "is there a socket
// with this local port" would say true.
//==============================================================================

dcl-proc test_connected_port_is_not_listening export;

  assert((g_client_fd >= 0):
         'the staged client socket is open - without it this test asks ' +
         'about a port with nothing on it at all and cannot fail');

  nEqual(false: SCQRY_port_listening(g_client_port):
         'port ' + %char(g_client_port) + ' carries a connected socket, ' +
         'not a listening one');

end-proc;

//==============================================================================
// The job holding a listening socket can be found
//==============================================================================

dcl-proc test_jobs_on_port export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s n like(INTEGER_t);

  // One call, not two. The old version compared the count from one call with
  // the structure filled by another, which is two observations of a live
  // system and cannot be relied on to agree.
  n = SCQRY_jobs_on_port(FIX_PORT: jobs);

  assert((n > 0): 'a job holds the staged socket on port ' + %char(FIX_PORT));
  iEqual(n: jobs.count: 'returned count matches the structure');
  assert((%len(%trim(jobs.name(1))) > 0): 'job name is populated');

end-proc;

//==============================================================================
// A port resolves to the job LISTENING on it, not to its clients
//
// Every job holding a socket on a port satisfies LOCAL_PORT = n. Only the
// listener has no remote peer, so only the listener has REMOTE_PORT = 0.
// Without that qualifier an established connection is returned as though it
// were the service.
//
// This is not a cosmetic difference. SCEXEC_jobs is built on this procedure,
// and stop and kill pass its result straight to ENDJOB - so over-matching here
// ends jobs belonging to whoever happens to be connected.
//
// WHICH ASSERTION HERE ACTUALLY SEPARATES THE TWO READINGS, because it is not
// the obvious one and the difference is worth being exact about.
//
// Three sockets are open while this runs:
//
//   FIX_PORT      listening, no peer            <- the only right answer
//   FIX_PORT      the accepted server end       <- a second row on FIX_PORT
//   client port   the client end, connected     <- a row on the client's port
//
// THE COUNT ON FIX_PORT DOES NOT DISCRIMINATE, and cannot be made to. The
// procedure returns DISTINCT job names, and the listener and the accepted end
// are held by the same job - this one - so both rows collapse to one name and
// dropping the qualifier still returns 1. Nor can the fixture be rearranged to
// fix that: the accepted end belongs to whichever job called accept(), so both
// rows stay in one job however the client is arranged. Two distinct jobs on
// one local port needs the OS to fork, which is what sshd does and what a
// suite cannot stage. The count assertion is kept as a regression guard on the
// shape of the answer, and it is honest about being no more than that.
//
// THE CLIENT PORT IS WHAT SEPARATES THEM. Nothing listens there; the only row
// carrying it is a connected socket. Drop REMOTE_PORT = 0 and that row matches
// and the procedure returns one job for a port no job is serving. That is the
// defect, stated exactly, and this is the assertion that fails on it.
//
// It used to be port 22, where the count DID discriminate, because sshd forks
// a child per connection and the children are separate jobs. That is also why
// it was flaky: the count was then a claim about sshd, and it duly failed when
// a second connection was opening and parent and child both held the listening
// socket. The count coverage that is lost here is real, and it is lost to
// something a suite cannot own.
//==============================================================================

dcl-proc test_jobs_on_port_is_listener_only export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s n     like(INTEGER_t);

  // The fixture, asserted through a different procedure than the one under
  // test, so "nothing found" cannot be mistaken for "nothing staged"
  nEqual(true: SCQRY_port_listening(FIX_PORT):
         'the staged listener is up on port ' + %char(FIX_PORT));
  assert((g_accept_fd >= 0):
         'and something is connected to it - otherwise a procedure that ' +
         'returns clients as well as listeners would pass this test');

  n = SCQRY_jobs_on_port(FIX_PORT: jobs);

  // A regression guard on the shape of the answer, not the discriminating
  // assertion - see the header. Both of this port's rows are held by this job
  // and collapse to one name either way.
  assert((n >= 1): 'the staged listener is found');
  assert((n = 1): 'port ' + %char(FIX_PORT) + ' must resolve to the ' +
                  'listening job alone, but ' + %char(n) +
                  ' were returned: ' + names_of(jobs));

  aEqualV(this_job(): jobs.name(1):
          'and it is the job holding the listening socket');

  // THIS is the one that fails if the REMOTE_PORT qualifier goes. Nothing
  // listens on the client's port, so no job serves it, however many sockets
  // carry it as their local port.
  n = SCQRY_jobs_on_port(g_client_port: jobs);
  iEqual(0: n: 'port ' + %char(g_client_port) + ' carries a connected ' +
               'socket and no listener, so no job serves it - got: ' +
               names_of(jobs));

end-proc;

dcl-proc test_jobs_on_unused_port export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCQRY_jobs_on_port(UNUSED_PORT: jobs): 'no jobs on an unused port');
  iEqual(0: jobs.count: 'structure agrees');

end-proc;

//==============================================================================
// Job lookup by name
//==============================================================================

dcl-proc test_jobs_by_name_absent export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCQRY_jobs_by_name('ZZNOSUCH': '': jobs):
         'a job name that cannot exist returns nothing');

end-proc;

dcl-proc test_jobs_by_name_present export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCQRY_jobs_by_name(PGM_JOB: '': jobs) > 0):
         'the staged job is found');
  assert(job_in_list(jobs: g_pgm_job):
         'and it is ' + %trim(g_pgm_job) + ', got: ' + names_of(jobs));

end-proc;

//==============================================================================
// The subsystem qualifier selects, rather than merely being accepted
//
// This asked for a count >= 0 and called it a shape check, which is true of
// any answer including none - a qualifier that was ignored, and one that
// matched nothing, both passed. The staged job makes a real pair available:
// the subsystem it runs in must find it, and a subsystem it does not run in
// must not.
//==============================================================================

dcl-proc test_jobs_by_name_with_subsystem export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCQRY_jobs_by_name(PGM_JOB: PGM_SBS: jobs) > 0):
         'the staged job is found in ' + PGM_SBS +
         ' - if this machine runs QUSRNOMAX elsewhere, PGM_SBS is what ' +
         'needs changing');
  assert(job_in_list(jobs: g_pgm_job):
         'and it is ' + %trim(g_pgm_job) + ', got: ' + names_of(jobs));
  assert((jobs.count <= SCQRY_MAX_JOBS): 'count stays within the array');

  iEqual(0: SCQRY_jobs_by_name(PGM_JOB: OTHER_SBS: jobs):
         'and not found in ' + OTHER_SBS + ', which it does not run in');

end-proc;

//==============================================================================
// Job lookup by program
//==============================================================================

dcl-proc test_jobs_by_pgm export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCQRY_jobs_by_pgm('ZZNOSUCHP': jobs):
         'a program that cannot be running returns nothing');
  assert((SCQRY_jobs_by_pgm('QCMD': jobs) >= 0): 'a real program name runs');

end-proc;

//==============================================================================
// The PGM- criterion matches regardless of case, as upstream does
//
// Upstream compares upper(FUNCTION) against its argument upper-cased, so
// PGM-sshd and PGM-SSHD both match. RMSC compared the raw value, making the
// criterion case-sensitive - a definition written in the other case would
// silently never match, and a running service would be reported as stopped.
//
// THE FIXTURE IS A JOB THIS SUITE SUBMITTED, running a PASE delay through a
// symbolic link named rmscqrysl. It used to be sshd, which is running whenever
// the suite arrives over ssh - true, but the COUNT of sshd jobs moves as
// connections come and go, and comparing two live counts failed with
// "Expected 7, but was 8".
//
// So the assertion is that the SAME staged job comes back under both
// spellings, which is what case-insensitivity means and is not a claim about
// how busy the machine is. If a change made the lookup case-sensitive, one of
// the two lists would not contain it - the link's name is lower case, so
// neither an argument-only nor a stored-value-only upper-casing survives.
//==============================================================================

dcl-proc test_jobs_by_pgm_case_insensitive export;

  dcl-ds jobs_lc likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds jobs_uc likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s n_lc like(INTEGER_t);
  dcl-s n_uc like(INTEGER_t);

  n_lc = SCQRY_jobs_by_pgm(PGM_LOWER: jobs_lc);
  n_uc = SCQRY_jobs_by_pgm(PGM_UPPER: jobs_uc);

  assert((n_lc > 0): 'the staged job is found under ' + PGM_LOWER +
                     ' - the spelling the system itself reports');
  assert(job_in_list(jobs_lc: g_pgm_job):
         'and it is ' + %trim(g_pgm_job) + ', got: ' + names_of(jobs_lc));

  assert((n_uc > 0): 'the same job is found under ' + PGM_UPPER);
  assert(job_in_list(jobs_uc: g_pgm_job):
         'the SAME job ' + %trim(g_pgm_job) +
         ' is found whichever case the criterion is written in, got: ' +
         names_of(jobs_uc));

end-proc;

//==============================================================================
// Job detail
//
// These ask about the staged job rather than returning early when a job cannot
// be found. A test that skips when its fixture is missing reports success for
// a procedure it never called - see CLAUDE.md.
//==============================================================================

dcl-proc test_job_start_time export;

  dcl-s started like(SCQRY_TIME_t);

  started = SCQRY_job_start_time(g_pgm_job);
  assert((%len(%trim(started)) = 19):
         'start time comes back as YYYY-MM-DD HH:MM:SS, got "' +
         %trim(started) + '"');

end-proc;

dcl-proc test_job_start_time_absent export;

  aEqualV('': SCQRY_job_start_time('000000/NOBODY/NOSUCHJOB'):
          'a job that does not exist has no start time');

end-proc;

dcl-proc test_job_perf export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  assert(SCQRY_job_perf(g_pgm_job: perf): 'performance figures returned');
  nEqual(true: perf.found: 'marked found');
  assert((perf.thread_count > 0): 'an active job has at least one thread');

end-proc;

dcl-proc test_job_perf_absent export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  // A job that does not exist yields nothing, and must not be reported found
  SCQRY_job_perf('000000/NOBODY/NOSUCHJOB': perf);
  nEqual(false: perf.found: 'not marked found');

end-proc;

//==============================================================================
// JVM and spooled files
//==============================================================================

dcl-proc test_jvm_info_absent export;

  dcl-ds jvm likeds(SCQRY_JVM_t) inz(*likeds);

  SCQRY_jvm_info('000000/NOBODY/NOSUCHJOB': jvm);
  nEqual(false: jvm.found: 'no JVM for a job that does not exist');

end-proc;

//==============================================================================
// jvm_info must be able to SUCCEED, not only to fail politely
//
// This suite previously asked only what happened for a job that does not
// exist, on the grounds that a JVM is not guaranteed to be running. That
// passes whether the query works or is rejected outright - and it was being
// rejected outright, on two column names that do not exist in QSYS2.JVM_INFO.
// A procedure that can never return a row needs a test that says so.
//==============================================================================

dcl-proc test_jvm_info_present export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds jvm  likeds(SCQRY_JVM_t) inz(*likeds);
  dcl-s i     like(INTEGER_t);

  // Absent fixture fails rather than passing quietly. A test whose fixture is
  // missing proves nothing, which is exactly how the wrong columns survived.
  assert((SCQRY_jobs_by_name(JVM_JOB: '': jobs) > 0):
         'the ' + JVM_JOB + ' job is active - the fixture this test needs');

  // Several jobs share that name and only one of them runs a JVM, so ask each
  // in turn rather than assuming the first.
  for i = 1 to jobs.count;
    if SCQRY_jvm_info(jobs.name(i): jvm);
      leave;
    endif;
  endfor;

  nEqual(true: jvm.found:
         'jvm_info answers for the ' + JVM_JOB + ' job that runs a JVM');
  assert((jvm.heap_size > 0):
         'heap size is populated, not left at zero by a rejected query');
  assert((jvm.max_heap_size > 0):
         'max heap size is populated - one of the two columns that was wrong');

end-proc;

dcl-proc test_splfs_for_job export;

  dcl-ds splfs likeds(SCQRY_SPLFS_t) inz(*likeds);

  iEqual(0: SCQRY_splfs_for_job('000000/NOBODY/NOSUCHJOB': splfs):
         'no spooled files for a job that does not exist');
  assert((splfs.count <= SCQRY_MAX_SPLF): 'count stays within the array');

end-proc;

//==============================================================================
// The teardown guard only ever matches OUR job
//
// end_pgm_job ENDJOBs what a lookup returns, and that lookup is code this
// project tests rather than trusts. This pins the guard that stands between a
// lookup which over-matches and a suite that ends other people's jobs -
// including the one it is running in.
//==============================================================================

dcl-proc test_teardown_guard export;

  nEqual(true: is_staged_job('123456/SOMEONE/' + PGM_JOB):
         'our own job, whoever submitted it');
  nEqual(true: is_staged_job(g_pgm_job): 'and the one actually staged');

  nEqual(false: is_staged_job('123456/QSECOFR/QP0ZSPWP'):
         'not the job this suite runs in');
  nEqual(false: is_staged_job('123456/QSYS/QINTER'):
         'not a subsystem monitor');
  nEqual(false: is_staged_job(PGM_JOB):
         'not an unqualified name, which has no job-name segment to trust');
  nEqual(false: is_staged_job('123456/USER/' + PGM_JOB + 'X'):
         'not a longer name that starts the same way');

end-proc;
