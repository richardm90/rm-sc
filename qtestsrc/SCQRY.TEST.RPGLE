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
// 08/09/2026 - RM - run attribute cases; the suite now stages its own job's
//                    run attributes as well as the job
// 08/09/2026 - RM - measurement cases: the identity and timestamp fields on
//                    SCQRY_PERF_t, the lifetime/window I/O split, the new
//                    JVM figures, and SCQRY_job_sample's window
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
//
// AND IT IS TEN CHARACTERS LONG, WHICH IS NOT COSMETIC EITHER. The column the
// system reports it in is ten wide: measured 08/09/2026, a link named
// rmscqrysl0 comes back as all ten characters and one named rmscqrysl01 comes
// back as rmscqrysl0, truncated by the system before anything of ours sees it.
// So ten is the widest value this field can ever have to carry, and a holder a
// character short reads nine of them.
//
// A nine-character name was the fixture until then, and under it no assertion
// anywhere in this suite ever saw the field at its full width. A truncating
// holder is this project's most-repeated defect and it is silent; the run
// attribute cases already assert the widest legal value for the same reason.
dcl-c PGM_LOWER const('rmscqsleep');
dcl-c PGM_UPPER const('RMSCQSLEEP');

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
// THE RUN ATTRIBUTES THIS SUITE SETS ON ITS OWN JOB.
//
// Every attribute assertion below is about a value the SUITE CHOSE, not one
// the machine happened to have - and each one is deliberately NOT the default
// the job would otherwise carry. Measured on this machine, 08/09/2026, on a
// job submitted exactly as start_pgm_job submits this one, read back through
// DSPJOB OPTION(*RUNA) and through QSYS2.ACTIVE_JOB_INFO:
//
//   RUNPTY 50 / TIMESLICE 2000 / PURGE *YES / DFTWAIT 30
//   CPUTIME *NOMAX / MAXTMPSTG *NOMAX / MAXTHD *NOMAX
//
// so a query that returned the defaults, or one that returned nothing and let
// the caller's initialised values stand, would agree with a working one on
// every field if the suite left the job alone. It does not leave it alone.
//
// THE FOUR TEXT FIELDS ARE THE POINT OF THIS. Default wait, maximum CPU time,
// maximum temporary storage and maximum threads hold TEXT because each can be
// either a number or *NOMAX - and on this machine NOTHING has a numeric limit:
// every active job reads *NOMAX for all four untouched. Measured. So a
// procedure that simply wrote '*NOMAX' into those four fields would pass every
// case that could be built from what is already running here.
//
// Giving three of them numbers and leaving MAXTHD at *NOMAX makes the four
// fields disagree with each other: a constant '*NOMAX' fails on three of them,
// and a value that was never converted from the number the API carries fails
// on the fourth, where -1 means *NOMAX and '-1' is not what upstream prints.
//
// MAXTHD is left alone because it CANNOT be set - CHGJOB refuses the keyword
// (CPD0043) and the limit comes from the job's class. Which is why it is the
// one field that still covers the *NOMAX reading in the baseline. The other
// three get *NOMAX put on them and taken off again, in test_job_attrs_nomax,
// which is the only way this suite sees both readings of the same field.
//
// RUNPTY is LOWERED rather than raised. Raising a job's priority needs
// *JOBCTL; 60 is numerically larger than the 50 it starts at, so this works
// for any profile that can submit the job in the first place.
//
// MAXTMPSTG IS 2048 AND THAT NUMBER IS LOAD-BEARING. The limit exists in two
// units - DSPJOB labels the field "Maximum temporary storage in megabytes" and
// prints 2048 for MAXTMPSTG(2048), while the same limit in kilobytes is
// 2097152. Both are plausible, both are round, and nothing else in this suite
// could tell them apart; ATTR_MAXTMPSTG_KB below exists so the case can name
// the wrong answer as well as the right one.
//
// Both numeric limits are caps rather than reservations, so a job that sleeps
// is no more at risk under them than under *NOMAX. The fixture measured 10MB
// and 9ms of CPU, against caps of 2048MB and 9999999ms.
///
dcl-c ATTR_RUNPTY    const(60);            // would otherwise be 50
dcl-c ATTR_TIMESLICE const(1500);          // would otherwise be 2000
dcl-c ATTR_DFTWAIT   const('45');          // would otherwise be 30
dcl-c ATTR_PURGE     const('*NO');         // would otherwise be *YES
dcl-c ATTR_CPUTIME   const('9999999');     // would otherwise be *NOMAX
dcl-c ATTR_MAXTMPSTG const('2048');        // would otherwise be *NOMAX
dcl-c ATTR_MAXTHD    const('*NOMAX');      // cannot be set - see above

// The same limit read in the WRONG UNIT. MAXTMPSTG(2048) is 2048 megabytes
// and 2097152 kilobytes; the source carries both and upstream prints the
// megabyte figure. Named here so the case can assert against it by name
// rather than merely asserting the right answer and hoping.
dcl-c ATTR_MAXTMPSTG_KB const('2097152');

// What PURGE reads when it is set the other way. Its own case sets this,
// reads it back and puts ATTR_PURGE back - so the suite sees the field say
// two different things, which is the only way a constant is ruled out.
dcl-c OTHER_PURGE const('*YES');

// The text every one of the four limit fields carries when the limit is off,
// and what the number underneath it is. -1 is the API's *NOMAX; '-1' is what
// a field that was never converted would read.
dcl-c NOMAX     const('*NOMAX');
dcl-c NOT_NOMAX const('-1');

// The widest value each of these keywords accepts, measured with CHGJOB on
// this machine: DFTWAIT and CPUTIME refuse anything above 9999999 (CPD0085)
// and MAXTMPSTG anything above 2147483647 (CPD0095). Ten characters is
// therefore the widest text any of these fields can ever have to hold, and a
// holder narrower than that truncates. This project has shipped that defect
// three times, so the widest legal value is asserted rather than a
// comfortable one.
dcl-c WIDE_DFTWAIT   const('9999999');
dcl-c WIDE_MAXTMPSTG const('2147483647');

// A storage figure this fixture cannot legitimately reach, in megabytes. The
// staged job is a PASE sleep: it measured 10MB, twice, on two different days,
// and it is capped at ATTR_MAXTMPSTG. The same 10MB read as kilobytes would be
// 10240. So a value above this ceiling is the kilobyte field, not a busy job -
// the same wrong-unit reading the maximum has, in the field that reports use.
dcl-c MB_CEILING const(1000);

// A job name no job can have, for the not-found cases
dcl-c NO_SUCH_JOB const('000000/NOBODY/NOSUCHJOB');

// What a poisoned structure carries before a not-found call. Distinctive
// enough that finding it afterwards is unambiguous.
dcl-c POISON_NUM  const(12345);
dcl-c POISON_TEXT const('ZZPOISON');

// A poison that FITS. job_status is four characters wide, so POISON_TEXT
// cannot be written into it - and a value silently truncated on the way in is
// not a poison, it is a shorter poison that may or may not survive.
dcl-c POISON_SHORT const('ZZZZ');

///
// WHAT A SLEEPING PASE JOB READS, and where each figure was measured.
//
// Out of band, 08/09/2026, on a job submitted exactly as start_pgm_job
// submits this one - CALL PGM(QP2SHELL) PARM(<a symbolic link to
// /QOpenSys/usr/bin/sleep> '300') JOB(RMSCPRB8) JOBQ(QUSRNOMAX) - read
// through db2util against QSYS2.ACTIVE_JOB_INFO(DETAILED_INFO=>'ALL'):
//
//   JOB_NAME                    442119/CLAUDE/RMSCPRB8
//   JOB_USER                    CLAUDE
//   AUTHORIZATION_NAME          CLAUDE
//   JOB_STATUS                  THDW
//   FUNCTION                    rmscprbsl      <- the LINK's basename, lower
//   FUNCTION_TYPE               PGM
//   JOB_TYPE                    BCH
//   TOTAL_DISK_IO_COUNT         5
//   ELAPSED_TOTAL_DISK_IO_COUNT 0
//   ELAPSED_CPU_PERCENTAGE      0.00
//   ELAPSED_TIME                0.000
//   JOB_ACTIVE_TIME             2026-09-08-14.54.14
//   THREAD_COUNT                1
//
// JOB_STATUS and the two I/O figures were sampled five times over ten seconds
// and did not move: THDW, 5, 0 every time. They are stable because the job
// does nothing, which is the whole reason this fixture is a sleep.
///

// What the staged job's status reads, and what it must NOT read. THDW is the
// job status of a PASE delay; BCH is the JOB_TYPE of the same row, three
// characters, in the same neighbourhood of the same table and the obvious
// column to reach for by mistake.
dcl-c PGM_STATUS  const('THDW');
dcl-c WRONG_STATUS const('BCH');

// The lifetime I/O figure this fixture measured. Asserted as a floor rather
// than a value: starting QP2SHELL and reaching PASE costs I/O and the count
// then stops moving, but five is what one machine did on one day.
dcl-c LIFETIME_IO_FLOOR const(0);

///
// THE SAMPLING WINDOW, and why the bounds are where they are.
//
// Measured out of band on the same fixture, resetting the elapsed statistics
// and reading again after a delay, three times in one connection:
//
//   DLYJOB DLY(1)  ->  ELAPSED_TIME 1.120
//   DLYJOB DLY(2)  ->  ELAPSED_TIME 2.096
//   DLYJOB DLY(4)  ->  ELAPSED_TIME 4.112
//
// so the overhead either side of the wait is about a tenth of a second and
// the window tracks what was asked for. A procedure that ignored the argument
// and read straight away would report a figure near zero and return in
// milliseconds; the bounds below are wide enough that a loaded machine does
// not fail them and narrow enough that such a procedure cannot pass.
///
dcl-c SAMPLE_SECS const(2);
dcl-c SAMPLE_MIN  const(1.5);
dcl-c SAMPLE_MAX  const(4.0);

// The two windows the second sampling case asks for, and what separates them.
// A procedure that always waits the same length - or waits none at all -
// reports the same figure for both, and SPREAD_MIN is what it fails.
dcl-c SHORT_SECS const(1);
dcl-c LONG_SECS  const(4);
dcl-c SHORT_MIN  const(0.5);
dcl-c SHORT_MAX  const(2.5);
dcl-c LONG_MIN   const(3.0);
dcl-c LONG_MAX   const(6.5);
dcl-c SPREAD_MIN const(2.0);

// A wall-clock ceiling on a sampling call, so a procedure that waited far
// longer than it was asked to says so rather than merely being slow
dcl-c SAMPLE_WALL_MAX const(30);

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

// The time the suite reached, formatted the way upstream prints it, taken
// immediately BEFORE the staged job was submitted. The job cannot have gone
// active earlier than this, and cannot have gone active later than now - two
// bounds the suite owns, against a field nothing else here can pin.
dcl-s g_before_start varchar(19);

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

dcl-pr set_job_attrs;
end-pr;

dcl-pr chg_job_attrs;
  keywords varchar(256) const;
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

dcl-pr now_text varchar(19);
end-pr;

dcl-pr jvm_of_qsrvmon like(BOOLEAN_t);
  jvm likeds(SCQRY_JVM_t);
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

  // BEFORE the job is submitted, and after the sweep - which can take a
  // minute if it finds anything. A bound captured before the sweep would be
  // a minute early and would still pass, which is a bound that has stopped
  // bounding.
  g_before_start = now_text();

  start_pgm_job();

  // The staged job's run attributes, moved off their defaults. Done here
  // rather than inside start_pgm_job so that what the suite CHANGES about its
  // fixture is separate from what it takes to stand the fixture up.
  set_job_attrs();

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
// set_job_attrs
//   Put the staged job's run attributes on the values this suite asserts
//
// It ASSERTS, so a machine or a profile where the change is refused fails with
// the command's own message rather than leaving the attribute tests to compare
// a queried default against an expected default and pass.
//
// CALLED TO RESTORE AS WELL AS TO SET. Three cases move a limit, read it and
// call this to put the job back, so the baseline is written once and the
// cases that depart from it say only what they departed to.
//
// Harmless to the rest of the suite: nothing else here reads run priority,
// time slice, purge, default wait or either limit, and a job that sleeps uses
// neither the 9999999ms of CPU nor the 2048MB it is now capped at. The
// measured figures for this fixture are 9ms and 10MB.
//==============================================================================

dcl-proc set_job_attrs;

  chg_job_attrs('RUNPTY(' + %char(ATTR_RUNPTY) + ')' +
                ' TIMESLICE(' + %char(ATTR_TIMESLICE) + ')' +
                ' PURGE(' + ATTR_PURGE + ')' +
                ' DFTWAIT(' + ATTR_DFTWAIT + ')' +
                ' CPUTIME(' + ATTR_CPUTIME + ')' +
                ' MAXTMPSTG(' + ATTR_MAXTMPSTG + ')');

end-proc;

//==============================================================================
// chg_job_attrs
//   CHGJOB the staged job, and fail loudly if the system refuses
//
// Every attribute case depends on the job actually carrying what it was told
// to carry. A CHGJOB that failed silently would leave the case comparing a
// default against a default - which is the shape of test that passes whatever
// the code does.
//==============================================================================

dcl-proc chg_job_attrs;
  dcl-pi *n;
    keywords varchar(256) const;
  end-pi;

  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd varchar(512);
  dcl-s ok  like(BOOLEAN_t);

  cmd = 'CHGJOB JOB(' + %trim(g_pgm_job) + ') ' + %trim(keywords);

  // Result first, message second: built in one expression the operands have
  // no guaranteed evaluation order and the message can be assembled before
  // qerr is filled, losing the message id in the run that needed it.
  ok = QCMD_exc(cmd: qerr);
  assert(ok: 'set the staged job''s run attributes - without this an ' +
             'attribute assertion compares a default against a default, and ' +
             'a query that answered nothing would pass: ' + cmd_text(cmd: qerr));

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
// symbolic link named rmscqsleep. It used to be sshd, which is running whenever
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

//==============================================================================
// Job run attributes
//
// SCQRY_job_attrs is the data layer under perfinfo, which prints each job's
// ATTRIBUTES alongside its measurements. SCEXEC_perfinfo only prints, so the
// end-to-end proof is the fidelity gate; these cases prove the values it is
// given are the job's own.
//
// WHAT THE EXPECTED VALUES WERE CHECKED AGAINST, out of band, 08/09/2026.
// A job was submitted exactly as start_pgm_job submits this one -
//
//   SBMJOB CMD(CALL PGM(QP2SHELL) PARM('/QOpenSys/usr/bin/sleep' '400'))
//          JOB(RMSCPRB2) JOBQ(QUSRNOMAX)
//
// - then CHGJOB'd with the same keywords set_job_attrs uses and read back two
// independent ways: DSPJOB OPTION(*RUNA) OUTPUT(*PRINT), and db2util against
// QSYS2.ACTIVE_JOB_INFO(DETAILED_INFO=>'ALL'). Both agreed on every field
// both carry:
//
//   RUNPTY 60  TIMESLICE 1500  PURGE *NO  DFTWAIT 45
//   CPUTIME 9999999  CPU used 9
//   MAXTMPSTG 2048  temp used 10  peak 10
//   MAXTHD *NOMAX  threads 1
//
// and the DSPJOB heading is "Maximum temporary storage IN MEGABYTES", which is
// the whole of why test_job_attrs_max_storage_is_megabytes exists.
//
// The same job was then CHGJOB'd DFTWAIT(*NOMAX) CPUTIME(*NOMAX)
// MAXTMPSTG(*NOMAX), and those three read *NOMAX with nothing else moved; then
// DFTWAIT(9999999) MAXTMPSTG(2147483647), which both took; then PURGE(*YES),
// which read *YES. Every value asserted below was seen on a real job before it
// was asked of this one.
//
// WHAT IS ASSERTED EXACTLY AND WHAT IS NOT. The values the suite SET are
// asserted exactly - they are ours. The measurements are not: threads, CPU and
// storage are the machine's to choose moment to moment, so they are asserted
// by relation and by scale rather than by value.
//
// THREE CASES MOVE THE FIXTURE AND PUT IT BACK, and each one restores BEFORE
// it asserts anything. An iRPGUnit assertion escapes the procedure, so a
// failed assertion placed before the restore would leave every later case
// reading a job the suite had changed and not changed back - one real failure
// reported as five. The restore itself asserts, so a fixture that cannot be
// put back says so loudly rather than quietly poisoning what follows.
//==============================================================================

//==============================================================================
// The values the suite set on its own job come back
//
// Each of the four is deliberately not the default the job would carry, so a
// query that read the wrong column, returned the class default, or wrote
// nothing at all disagrees here. A query that got them right agrees. That is
// the pair the case has to separate.
//
// DEFAULT WAIT IS TEXT AND IT IS ASSERTED AS '45', not as 45. It is one of the
// four fields the API hands over as a number with -1 for *NOMAX, so it has the
// same two ways to be wrong the maxima have: never converted, and always
// converted. This case covers the finite direction of it;
// test_job_attrs_nomax covers the other, on the same field.
//==============================================================================

dcl-proc test_job_attrs_scheduling export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);

  assert(SCQRY_job_attrs(g_pgm_job: attrs):
         'the staged job ' + %trim(g_pgm_job) + ' has run attributes - a ' +
         'false return here means every field below is the caller''s ' +
         'initialiser rather than the job''s');

  iEqual(ATTR_RUNPTY: attrs.run_priority:
         'run priority is the 60 the suite set, not the 50 it started at');

  iEqual(ATTR_TIMESLICE: attrs.time_slice:
         'time slice is the 1500 the suite set, not the default 2000');

  aEqualV(ATTR_DFTWAIT: attrs.default_wait:
          'default wait is the 45 the suite set, not the default 30 - and ' +
          'the text "45", not the "*NOMAX" a field converted unconditionally ' +
          'would carry');

  aEqualV(ATTR_PURGE: attrs.purge:
          'eligible for purge is the *NO the suite set, and not the *YES ' +
          'this job would carry if nothing had been asked of the system');

end-proc;

//==============================================================================
// The limit fields hold the job's limits, not a constant
//
// On this machine every active job reports *NOMAX for all four, measured. So a
// procedure that never looked, and simply wrote '*NOMAX' into each, would be
// indistinguishable from a working one against any fixture that was merely
// found rather than staged.
//
// set_job_attrs breaks the tie by giving three of them numbers and leaving the
// fourth alone. A constant '*NOMAX' now fails on three fields; a value that
// was never converted from the number underneath it fails on the fourth,
// where the number is -1 and the text wanted is *NOMAX.
//
// The non-blank assertions are kept as well, and they are the weaker claim:
// they catch a field that was never populated at all, which is a different
// defect from one populated with the wrong thing.
//==============================================================================

dcl-proc test_job_attrs_limits export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);

  assert(SCQRY_job_attrs(g_pgm_job: attrs):
         'the staged job has run attributes');

  assert((%len(%trim(attrs.max_cpu_time)) > 0):
         'maximum CPU time is populated - blank means the query did not ' +
         'reach it, whatever it would have said');
  assert((%len(%trim(attrs.max_temp_storage)) > 0):
         'maximum temporary storage is populated');
  assert((%len(%trim(attrs.max_threads)) > 0):
         'maximum threads is populated');

  aEqualV(ATTR_CPUTIME: attrs.max_cpu_time:
          'maximum CPU time is the 9999999 the suite set - a field that ' +
          'always says *NOMAX passes every other fixture on this machine ' +
          'and fails here');

  aEqualV(ATTR_MAXTHD: attrs.max_threads:
          'maximum threads is still *NOMAX - CHGJOB cannot set it, so it is ' +
          'the one field that fails if the text is instead always a number, ' +
          'and the one that would read "-1" if nothing converted it');

  assert((%trimr(attrs.max_threads) <> NOT_NOMAX):
         'and maximum threads is not the raw -1 the API carries for a limit ' +
         'that is off, got "' + %trim(attrs.max_threads) + '"');

end-proc;

//==============================================================================
// Maximum temporary storage is MEGABYTES
//
// THE MOST VALUABLE CASE IN THIS SET, and the one nothing else can stand in
// for. The limit exists in the source in two units. DSPJOB's heading is
// "Maximum temporary storage in megabytes" and it printed 2048 for the
// MAXTMPSTG(2048) this suite sets; the same limit in kilobytes is 2097152.
//
// Both readings are present, both are plausible, both are round numbers, and
// every other assertion in this suite gives the same answer under either. The
// only thing that separates them is a fixture whose limit is FINITE and an
// assertion that names the unit - which is what this is.
//
// The wrong answer is asserted against by name as well. A failure that reads
// "expected 2048 but was 2097152" says which defect it is; one that reads
// "expected 2048" leaves the reader to work it out.
//==============================================================================

dcl-proc test_job_attrs_max_storage_is_megabytes export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);

  assert(SCQRY_job_attrs(g_pgm_job: attrs):
         'the staged job has run attributes');

  assert((%trimr(attrs.max_temp_storage) <> ATTR_MAXTMPSTG_KB):
         'maximum temporary storage is not the KILOBYTE figure - 2097152 is ' +
         'the same limit in the other unit the source carries, and upstream ' +
         'prints megabytes');

  aEqualV(ATTR_MAXTMPSTG: attrs.max_temp_storage:
          'maximum temporary storage is the 2048 megabytes the suite set');

end-proc;

//==============================================================================
// The other reading of the same three fields: *NOMAX
//
// The baseline gives three limits numbers and leaves MAXTHD alone, so the
// suite sees *NOMAX only on a field it never touched. That is not enough: a
// field can be right for the finite case and wrong for the other, and MAXTHD
// cannot be moved to show it.
//
// So this case moves the three that CAN be moved, reads them, puts them back,
// and only then asserts. The same three fields that read 45, 9999999 and 2048
// in the cases above must read *NOMAX here - which no constant, in either
// direction, can do, and which a field that was never converted answers '-1'
// to.
//
// Nothing else may move with them. Run priority, time slice and purge are
// asserted unchanged, because a query that reached the wrong job or the wrong
// row would drift on those too and the three limits alone would not show it.
//==============================================================================

dcl-proc test_job_attrs_nomax export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);
  dcl-s found like(BOOLEAN_t) inz(false);

  chg_job_attrs('DFTWAIT(*NOMAX) CPUTIME(*NOMAX) MAXTMPSTG(*NOMAX)');

  found = SCQRY_job_attrs(g_pgm_job: attrs);

  // BEFORE ANY ASSERTION. An assertion escapes the procedure, and the fixture
  // would stay *NOMAX for every case after this one.
  set_job_attrs();

  assert(found: 'the staged job still has run attributes with its limits off');

  aEqualV(NOMAX: attrs.default_wait:
          'default wait reads *NOMAX when the limit is off, not the 45 it ' +
          'reads otherwise and not the "-1" the API carries underneath');
  aEqualV(NOMAX: attrs.max_cpu_time:
          'maximum CPU time reads *NOMAX when the limit is off');
  aEqualV(NOMAX: attrs.max_temp_storage:
          'maximum temporary storage reads *NOMAX when the limit is off');

  iEqual(ATTR_RUNPTY: attrs.run_priority:
         'and run priority did not move with them');
  iEqual(ATTR_TIMESLICE: attrs.time_slice:
         'and time slice did not move with them');
  aEqualV(ATTR_PURGE: attrs.purge:
          'and purge did not move with them');

end-proc;

//==============================================================================
// Purge says both things
//
// Same argument as the case above, for the one text field that is not a limit.
// The baseline sets *NO, which separates it from the *YES this job would
// otherwise carry - but a field hardcoded to '*NO' passes that. Only the field
// reading *YES on a job set to *YES rules that out, and the job has to be put
// back afterwards because every other case expects *NO.
//==============================================================================

dcl-proc test_job_attrs_purge_both_ways export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);
  dcl-s found like(BOOLEAN_t) inz(false);

  chg_job_attrs('PURGE(' + OTHER_PURGE + ')');

  found = SCQRY_job_attrs(g_pgm_job: attrs);

  set_job_attrs();   // before any assertion - see above

  assert(found: 'the staged job has run attributes with purge the other way');

  aEqualV(OTHER_PURGE: attrs.purge:
          'eligible for purge reads *YES on a job set to *YES - with the ' +
          '*NO the other cases assert, that is the field saying two ' +
          'different things rather than one constant');

end-proc;

//==============================================================================
// The widest value each limit can hold survives the trip
//
// A truncating holder is this project's most-repeated defect, and it is silent:
// a field one character too narrow reads 214748364 for 2147483647, which is
// still a plausible number of megabytes.
//
// Measured with CHGJOB on this machine: DFTWAIT and CPUTIME refuse anything
// above 9999999 (CPD0085), MAXTMPSTG anything above 2147483647 (CPD0095). So
// ten characters is the widest text any of these fields can ever have to
// carry, and this case makes it carry exactly that. Nothing in the baseline
// is that wide, so without this case the widest value in the suite is seven
// characters and a nine-character holder would pass everything.
//
// Restores before asserting, for the reason given above.
//==============================================================================

dcl-proc test_job_attrs_widest_values export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);
  dcl-s found like(BOOLEAN_t) inz(false);

  chg_job_attrs('DFTWAIT(' + WIDE_DFTWAIT + ') MAXTMPSTG(' +
                WIDE_MAXTMPSTG + ')');

  found = SCQRY_job_attrs(g_pgm_job: attrs);

  set_job_attrs();   // before any assertion - see above

  assert(found: 'the staged job has run attributes at its widest limits');

  aEqualV(WIDE_MAXTMPSTG: attrs.max_temp_storage:
          'maximum temporary storage carries all ten characters of ' +
          '2147483647 - a holder a character short reads 214748364 here and ' +
          'nowhere else in this suite');

  aEqualV(WIDE_DFTWAIT: attrs.default_wait:
          'default wait carries all seven characters of 9999999');

end-proc;

//==============================================================================
// The measurements are the job's own
//
// These cannot be asserted exactly - they move. What can be asserted is that
// they are populated, that they stand in the relation they must stand in, that
// they are on the SCALE they claim to be on, and that the thread count AGREES
// WITH THE ONE SCQRY_job_perf REPORTS FOR THE SAME JOB.
//
// The cross-check is the part worth having. job_perf is a procedure this suite
// already tests, reaching the same job by a different route, so two answers
// that disagree mean one of them is reading the wrong job or the wrong column -
// which no range assertion on a single answer could show. The job is a PASE
// sleep and its thread count was sampled repeatedly while writing this: 1
// every time. It is not a busy figure that happens to be stable for a moment.
//
// CPU TIME USED IS ASSERTED ONLY TO BE POPULATED, AND THAT IS THE STRONGEST
// CLAIM AVAILABLE - not a gap left for someone to close. The source offers
// exactly two candidate readings of that number and they are THE SAME NUMBER:
// a four-byte field and an eight-byte field carrying the same total, the
// four-byte one documented as valid only below 2,147,483,647. So no rival
// reading differs below 24.8 days of accumulated CPU, which is where the
// narrow field runs out. A microsecond reading is not among the rivals
// because no such field exists to read.
//
// A CPU-burning fixture would separate milliseconds from microseconds. It
// would separate nothing this implementation can actually get wrong, so it is
// not worth building - the case is UNREACHABLE, which is a different thing
// from untested and is recorded here so it is not rediscovered as one.
//
// THE CEILING IS THE UNIT ASSERTION, in the two fields that report use rather
// than limit. Storage is megabytes, the same unit question the maximum has,
// and the fixture measured 10MB - which is 10240 in the other unit. A ceiling
// of 1000MB is far above anything a sleeping PASE job can hold and far below
// what its kilobyte reading would be, so it separates the two without
// asserting a figure the machine owns.
//==============================================================================

dcl-proc test_job_attrs_measurements export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);
  dcl-ds perf  likeds(SCQRY_PERF_t) inz(*likeds);

  assert(SCQRY_job_attrs(g_pgm_job: attrs):
         'the staged job has run attributes');

  assert((attrs.thread_count >= 1):
         'a running job has at least one thread, got ' +
         %char(attrs.thread_count));

  assert(SCQRY_job_perf(g_pgm_job: perf):
         'and job_perf answers for the same job - the independent reading ' +
         'this case compares against');

  iEqual(perf.thread_count: attrs.thread_count:
         'both procedures agree on the staged job''s thread count');

  assert((attrs.temp_storage_used > 0):
         'temporary storage used is populated - this fixture measured 10MB');

  assert((attrs.temp_storage_used < MB_CEILING):
         'and it is megabytes, not kilobytes: a sleeping PASE delay holding ' +
         %char(attrs.temp_storage_used) + ' megabytes is not credible, and ' +
         'the 10MB this fixture holds reads 10240 in the other unit');

  assert((attrs.peak_temp_storage >= attrs.temp_storage_used):
         'peak temporary storage is not below current use: peak ' +
         %char(attrs.peak_temp_storage) + ', current ' +
         %char(attrs.temp_storage_used));

  assert((attrs.peak_temp_storage < MB_CEILING):
         'and peak is on the same scale, got ' +
         %char(attrs.peak_temp_storage));

  // Populated, and no more. Both readings of this number in the source are
  // the same number below 24.8 days of CPU - see the header.
  assert((attrs.cpu_time_used > 0):
         'CPU time used is populated - starting QP2SHELL and reaching PASE ' +
         'costs some, measured at 9ms for this fixture');

end-proc;

//==============================================================================
// A job that does not exist is reported not found, and nothing is filled in
//
// Both halves, because they are different defects. A procedure that fills the
// structure and then returns false hands a caller that trusts the return value
// nothing, and a caller that trusts the structure a fiction; a procedure that
// returns false correctly and leaves the structure alone is right.
//==============================================================================

dcl-proc test_job_attrs_absent export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);

  nEqual(false: SCQRY_job_attrs(NO_SUCH_JOB: attrs):
         'a job that cannot exist has no run attributes');

  iEqual(0: attrs.run_priority: 'and run priority was not filled in');
  iEqual(0: attrs.time_slice: 'and time slice was not filled in');
  iEqual(0: attrs.thread_count: 'and thread count was not filled in');
  iEqual(0: attrs.cpu_time_used: 'and CPU time used was not filled in');
  iEqual(0: attrs.temp_storage_used: 'and storage used was not filled in');
  iEqual(0: attrs.peak_temp_storage: 'and peak storage was not filled in');

  aEqualV('': attrs.purge: 'and purge was not filled in');
  aEqualV('': attrs.default_wait: 'and default wait was not filled in');
  aEqualV('': attrs.max_cpu_time: 'and maximum CPU time was not filled in');
  aEqualV('': attrs.max_temp_storage:
          'and maximum temporary storage was not filled in');
  aEqualV('': attrs.max_threads: 'and maximum threads was not filled in');

end-proc;

//==============================================================================
// A not-found call CLEARS the structure rather than merely not writing to it
//
// This is a separate case from the one above, and it is the one that can
// actually fail. Passing an already-clear structure and finding it clear
// afterwards is true of a working procedure AND of one that never touches its
// output at all - so on its own it is an assertion that cannot distinguish
// them. Only a structure that arrives dirty can.
//
// It matters here more than it would elsewhere. docs/testing-notes.md opens
// with likeds() not inheriting a template's inz, and the consequence recorded
// there is a caller holding a structure full of stack contents that looks
// plausibly populated. A caller that forgets inz(*likeds), checks the return
// value, and gets false is safe either way. A caller that forgets it and reads
// the fields - which is exactly the mistake that copybook trap produces - gets
// garbage from a procedure that only declines to write, and zeros from one
// that clears.
//
// SO THIS CASE PINS A READING OF THE INTERFACE RATHER THAN OF THE CODE, and it
// is the one interface question in this work I could not settle from the
// specification. "Left as a fresh SCQRY_ATTRS_t" is satisfied by both
// behaviours, because the procedure cannot know what the caller initialised it
// to. If the intended contract is the weaker one, this case is the thing to
// delete - but it should be deleted deliberately, not discovered.
//==============================================================================

dcl-proc test_job_attrs_absent_clears export;

  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);

  attrs.run_priority      = POISON_NUM;
  attrs.time_slice        = POISON_NUM;
  attrs.cpu_time_used     = POISON_NUM;
  attrs.temp_storage_used = POISON_NUM;
  attrs.peak_temp_storage = POISON_NUM;
  attrs.thread_count      = POISON_NUM;
  attrs.purge             = POISON_TEXT;
  attrs.default_wait      = POISON_TEXT;
  attrs.max_cpu_time      = POISON_TEXT;
  attrs.max_temp_storage  = POISON_TEXT;
  attrs.max_threads       = POISON_TEXT;

  nEqual(false: SCQRY_job_attrs(NO_SUCH_JOB: attrs):
         'still not found when the structure arrives dirty');

  assert((attrs.run_priority = 0 and attrs.time_slice = 0 and
          attrs.cpu_time_used = 0 and attrs.temp_storage_used = 0 and
          attrs.peak_temp_storage = 0 and attrs.thread_count = 0):
         'every number is cleared, not left holding what the caller had - ' +
         'run priority ' + %char(attrs.run_priority) + ', time slice ' +
         %char(attrs.time_slice) + ', CPU ' + %char(attrs.cpu_time_used) +
         ', storage ' + %char(attrs.temp_storage_used) + ', peak ' +
         %char(attrs.peak_temp_storage) + ', threads ' +
         %char(attrs.thread_count));

  assert((%len(%trim(attrs.purge)) = 0 and
          %len(%trim(attrs.default_wait)) = 0 and
          %len(%trim(attrs.max_cpu_time)) = 0 and
          %len(%trim(attrs.max_temp_storage)) = 0 and
          %len(%trim(attrs.max_threads)) = 0):
         'and every text field is cleared - purge "' + %trim(attrs.purge) +
         '", default wait "' + %trim(attrs.default_wait) + '", max CPU "' +
         %trim(attrs.max_cpu_time) + '", max storage "' +
         %trim(attrs.max_temp_storage) + '", max threads "' +
         %trim(attrs.max_threads) + '"');

end-proc;
//==============================================================================
// now_text - the time this job has reached, rendered the way upstream prints
//            a timestamp
//
// Built by hand rather than with a format name, because the transformation is
// the thing being asserted elsewhere and writing it out here says exactly what
// it is: the database's own rendering is yyyy-mm-dd-hh.mm.ss, and what has to
// come back is yyyy-mm-dd hh:mm:ss.
//==============================================================================

dcl-proc now_text;
  dcl-pi *n varchar(19);
  end-pi;

  dcl-s t varchar(32);

  t = %char(%timestamp());
  return %subst(t: 1: 10) + ' ' + %xlate('.': ':': %subst(t: 12: 8));

end-proc;

//==============================================================================
// jvm_of_qsrvmon - the JVM figures for whichever QSRVMON job runs a JVM
//
// Several jobs share that name and only one of them runs one, so ask each in
// turn. Fails rather than returning quietly if none is active: a case whose
// fixture is missing proves nothing, which is how two wrong column names
// survived here for three phases.
//==============================================================================

dcl-proc jvm_of_qsrvmon;
  dcl-pi *n like(BOOLEAN_t);
    jvm likeds(SCQRY_JVM_t);
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  assert((SCQRY_jobs_by_name(JVM_JOB: '': jobs) > 0):
         'the ' + JVM_JOB + ' job is active - the fixture this needs');

  for i = 1 to jobs.count;
    if SCQRY_jvm_info(jobs.name(i): jvm);
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// The measurements half of perfinfo
//
// SCQRY_job_perf is the data layer under the block upstream prints after
// "Sampling time (s)". SCEXEC_perfinfo only prints, so the end-to-end proof is
// the fidelity gate; these cases prove the values it is handed are the job's
// own, in the units and the rendering upstream uses.
//
// WHAT THE EXPECTED VALUES WERE CHECKED AGAINST, out of band, 08/09/2026 -
// see the block beside PGM_STATUS above for the figures and the commands.
// Every value asserted below was seen on a real job, submitted the same way
// as this suite's, before it was asked of this one.
//
// WHAT IS ASSERTED EXACTLY AND WHAT IS NOT, on the same principle the run
// attribute cases use. The identity fields are the job's own and stable while
// it sleeps, so they are asserted by value. The counts and the window are the
// machine's to choose, so they are asserted by relation and by bound.
//==============================================================================

//==============================================================================
// The identity fields carry the staged job's identity
//
// Three fields, three different ways to be wrong, and the fixture is chosen so
// each has a named rival rather than only a "not blank".
//
// FUNCTION IS THE STRONGEST OF THEM and it is not an accident. The staged job
// runs a PASE delay through a symbolic link this suite named in LOWER CASE,
// and the system reports the link's basename in the case it was written -
// measured, "rmscprbsl" on the probe job. So the assertion is an exact
// lower-case string the suite chose, and a field that upper-cased what it read
// fails it. That is the same defect the PGM- criterion had, in a different
// procedure, and this is the only place in the suite where a case difference
// in this field could show.
//
// JOB STATUS has a named wrong answer rather than only a right one. THDW is
// what a PASE delay sits in; BCH is the JOB_TYPE on the same row, three
// characters where this is four, and the obvious neighbour to reach for.
//==============================================================================

dcl-proc test_job_perf_identity_fields export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  assert(SCQRY_job_perf(g_pgm_job: perf):
         'the staged job ' + %trim(g_pgm_job) + ' has performance figures - ' +
         'a false return here means every field below is the caller''s ' +
         'initialiser rather than the job''s');
  nEqual(true: perf.found: 'marked found');

  aEqualV(psds.current_user: perf.current_user:
          'current user is the profile the job runs under - SBMJOB ran the ' +
          'staged job under this suite''s own current user');

  aEqualV(PGM_STATUS: perf.job_status:
          'job status is the THDW a PASE delay sits in, and not blank');

  assert((%trimr(perf.job_status) <> WRONG_STATUS):
         'and it is not the job TYPE, the other short code on the same row, ' +
         'got "' + %trim(perf.job_status) + '"');

  aEqualV(PGM_LOWER: perf.job_function:
          'function is the lower-case ' + PGM_LOWER + ' this suite named the ' +
          'link, exactly as the system reports it - an upper-cased copy ' +
          'reads ' + PGM_UPPER + ', which is the defect the PGM- criterion ' +
          'had and which nothing else in this suite would show');

  iEqual(10: %len(%trimr(perf.job_function)):
         'and all ten characters of it survive. Ten is the width of the ' +
         'column the system reports it in - a name of eleven arrives ' +
         'already truncated - so a holder a character short reads "' +
         %subst(PGM_LOWER: 1: 9) + '" here and nowhere else in this suite');

end-proc;

//==============================================================================
// Current user is the profile the job RUNS under, not the one in its name
//
// The staged job cannot separate those two. SBMJOB runs it under the
// submitting job's current user AND names it after the same profile, so
// JOB_USER and the current user are both CLAUDE on the probe job - measured -
// and a field filled from either column agrees.
//
// THE JOB THIS SUITE RUNS IN CAN. Measured on this machine, 08/09/2026: an
// SSH session lands in QP0ZSPWP owned by QSECOFR and swaps to the profile that
// connected, so JOB_USER reads QSECOFR while the current user reads CLAUDE.
// Two columns, two different answers, one job - which is the only shape that
// tells a wrong column from a right one.
//
// The fixture is asserted FIRST and by name. Run from a session where the two
// coincide this case can no longer separate anything, and it says so loudly
// rather than passing and proving less - the same reason PGM_SBS asserts
// which subsystem the staged job is in instead of accepting whatever it finds.
//==============================================================================

dcl-proc test_job_perf_current_user_is_not_the_job_user export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  assert((%trimr(psds.job_user) <> %trimr(psds.current_user)):
         'THE FIXTURE THIS CASE NEEDS: the job running this suite must have ' +
         'a current user different from the user segment of its job name, ' +
         'and here both read "' + %trim(psds.job_user) + '". Over SSH on ' +
         'this machine the suite runs in a job owned by QSECOFR under the ' +
         'profile that connected, which is what makes the two columns ' +
         'tellable apart. From a session where they coincide, nothing in ' +
         'this suite can separate them');

  assert(SCQRY_job_perf(this_job(): perf):
         'the job this suite runs in has performance figures');

  aEqualV(psds.current_user: perf.current_user:
          'current user is the profile the job is RUNNING under (' +
          %trim(psds.current_user) + '), not the user segment of its job ' +
          'name (' + %trim(psds.job_user) + ')');

end-proc;

//==============================================================================
// The active-since timestamp is RENDERED, not passed through
//
// The database hands this over as 2026-09-08-08.14.47 and upstream prints
// 2026-09-08 08:14:47. Both are nineteen characters, both look like a
// timestamp, and a length check cannot tell them apart - which is why the
// separators are asserted one at a time, by position, with the wrong answer
// named.
//
// THE TWO BOUNDS ARE THE OTHER HALF and they do more than they look like they
// do. The staged job went active after this suite captured g_before_start and
// before now, so a constant, a blank and a reading of some other job's clock
// all fail. So does the raw rendering, for a reason worth knowing: the
// database's separator at position 11 is a hyphen and the rendered one is a
// space, and a hyphen sorts ABOVE a space, so the raw form is greater than
// "now" written properly and fails the upper bound as well as the assertion
// aimed at it. Two independent readings of the same defect.
//==============================================================================

dcl-proc test_job_perf_active_since_is_rendered export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);
  dcl-s since varchar(19);
  dcl-s now   varchar(19);

  assert(SCQRY_job_perf(g_pgm_job: perf):
         'the staged job has performance figures');

  since = perf.active_since;
  now   = now_text();

  iEqual(19: %len(%trimr(since)):
         'active since is nineteen characters, got "' + %trim(since) + '"');

  aEqualV(' ': %subst(since: 11: 1):
          'a SPACE separates the date from the time, where the database ' +
          'renders a hyphen - "2026-09-08-08.14.47" is what a value passed ' +
          'straight through reads, and it is not what upstream prints');

  aEqualV(':': %subst(since: 14: 1):
          'a colon separates hours from minutes, where the database renders ' +
          'a full stop');

  aEqualV(':': %subst(since: 17: 1):
          'a colon separates minutes from seconds');

  iEqual(0: %scan('.': since):
         'and there is no full stop anywhere in it - that is the database''s ' +
         'time separator, got "' + %trim(since) + '"');

  assert((since >= g_before_start):
         'the staged job went active no earlier than the moment this suite ' +
         'submitted it: active since "' + %trim(since) + '", suite reached "' +
         %trim(g_before_start) + '"');

  assert((since <= now):
         'and no later than now: active since "' + %trim(since) + '", now "' +
         %trim(now) + '" - a value still carrying the database''s hyphen ' +
         'sorts above a properly rendered now and fails here too');

end-proc;

//==============================================================================
// The lifetime I/O count is not the sampled one
//
// Two counts, both plausible, and on a busy job they differ by orders of
// magnitude. On this one they differ the other way round and that is what
// makes it a fixture: the staged job sleeps, so its WINDOW count is zero while
// its LIFETIME count is not - measured, 0 against 5, sampled five times over
// ten seconds without moving.
//
// Five is a small number to hang a case on and it is enough, because the
// assertion is a relation and not a value: whichever way round the two fields
// were filled from one column, they come back equal, and equal is what this
// rules out. A busier fixture would give a bigger gap and no more information.
//
// SAMPLE SECONDS IS ASSERTED TO BE ZERO HERE, and that pins a reading of the
// interface rather than of the code. job_perf takes no sample, so the window
// it measured is none - measured, the elapsed timer reads 0.000 for a call
// that did not reset it. If the intended contract is instead that job_perf
// leaves the field alone whatever the caller had, this assertion is the thing
// to delete, and it should be deleted deliberately rather than discovered.
//==============================================================================

dcl-proc test_job_perf_lifetime_io_is_not_the_window export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  assert(SCQRY_job_perf(g_pgm_job: perf):
         'the staged job has performance figures');

  assert((perf.total_disk_io > LIFETIME_IO_FLOOR):
         'total disk I/O is the job''s WHOLE HISTORY and is not zero - ' +
         'starting QP2SHELL and reaching PASE costs I/O, measured at 5 for ' +
         'this fixture, got ' + %char(perf.total_disk_io));

  assert((perf.disk_io_count < perf.total_disk_io):
         'and the sampled figure is the smaller of the two: this job has ' +
         'done nothing since anyone asked, so its window count sits at or ' +
         'near zero while its lifetime count does not. Sampled ' +
         %char(perf.disk_io_count) + ' against a lifetime of ' +
         %char(perf.total_disk_io) + ' - two equal figures mean one field ' +
         'was filled from the other''s column');

  assert((perf.sample_seconds = 0):
         'and job_perf opened no window, so the seconds it sampled are ' +
         'none - got ' + %char(perf.sample_seconds));

end-proc;

//==============================================================================
// A job that does not exist fills nothing in, even over a dirty structure
//
// Same argument as test_job_attrs_absent_clears, which says it at length: a
// structure that arrives clear and leaves clear is true of a working procedure
// AND of one that never touches its output, so only a poisoned one can tell
// them apart. The existing test_job_perf_absent covers the return value; this
// covers what the caller is left holding.
//==============================================================================

dcl-proc test_job_perf_absent_clears export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  perf.thread_count   = POISON_NUM;
  perf.cpu_percentage = POISON_NUM;
  perf.disk_io_count  = POISON_NUM;
  perf.total_disk_io  = POISON_NUM;
  perf.sample_seconds = POISON_NUM;
  perf.current_user   = POISON_TEXT;
  perf.job_status     = POISON_SHORT;
  perf.job_function   = POISON_TEXT;
  perf.active_since   = POISON_TEXT;

  SCQRY_job_perf(NO_SUCH_JOB: perf);

  nEqual(false: perf.found:
         'not marked found when the structure arrives dirty');

  assert((perf.thread_count = 0 and perf.cpu_percentage = 0 and
          perf.disk_io_count = 0 and perf.total_disk_io = 0 and
          perf.sample_seconds = 0):
         'every number is cleared, not left holding what the caller had - ' +
         'threads ' + %char(perf.thread_count) + ', CPU% ' +
         %char(perf.cpu_percentage) + ', sampled I/O ' +
         %char(perf.disk_io_count) + ', lifetime I/O ' +
         %char(perf.total_disk_io) + ', window ' +
         %char(perf.sample_seconds));

  assert((%len(%trim(perf.current_user)) = 0 and
          %len(%trim(perf.job_status)) = 0 and
          %len(%trim(perf.job_function)) = 0 and
          %len(%trim(perf.active_since)) = 0):
         'and every text field is cleared - current user "' +
         %trim(perf.current_user) + '", status "' + %trim(perf.job_status) +
         '", function "' + %trim(perf.job_function) + '", active since "' +
         %trim(perf.active_since) + '"');

end-proc;

//==============================================================================
// Sampling opens a real window
//
// THE ONE CASE THAT CANNOT BE FAKED BY READING FASTER. A procedure that
// ignored its seconds argument and read straight away would fill every other
// field correctly and return in milliseconds, and every assertion in this
// suite except this one would agree with it.
//
// So it is asserted twice over, from two independent clocks: the WALL time the
// call took, measured here with a timestamp either side, and the window the
// call REPORTS. A non-sampling implementation fails both - it returns at once,
// and it reports a figure near zero.
//
// Measured out of band on this fixture: a two second window reads 2.096, the
// overhead either side being about a tenth of a second. The bounds are 1.5 and
// 4.0, wide enough that a loaded machine does not fail them and narrow enough
// that a call which never waited cannot pass.
//
// EVERYTHING JOB_PERF FILLS, THIS FILLS TOO, and the rest of the case says so.
// A sampling procedure that returned only the sampled figures would leave a
// caller with a found flag and no identity, and nothing else here would ask.
//==============================================================================

dcl-proc test_job_sample_measures_a_window export;

  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);
  dcl-s t0   timestamp;
  dcl-s wall like(INTEGER_t);
  dcl-s ok   like(BOOLEAN_t);

  t0   = %timestamp();
  ok   = SCQRY_job_sample(g_pgm_job: SAMPLE_SECS: perf);
  wall = %diff(%timestamp(): t0: *seconds);

  assert(ok: 'sampling the staged job over ' + %char(SAMPLE_SECS) +
             ' seconds answers');
  nEqual(true: perf.found: 'marked found');

  assert((wall >= SAMPLE_SECS - 1):
         'AND IT ACTUALLY WAITED. ' + %char(SAMPLE_SECS) + ' seconds were ' +
         'asked for and the call came back after ' + %char(wall) + ' - a ' +
         'procedure that read straight away returns in milliseconds and ' +
         'reports a window it never opened');

  assert((wall <= SAMPLE_WALL_MAX):
         'and it did not wait far longer than it was asked to, ' +
         %char(wall) + 's');

  assert((perf.sample_seconds >= SAMPLE_MIN):
         'the window it REPORTS is the one it measured, at least 1.5s - got ' +
         %char(perf.sample_seconds) + ', where near zero is what a call that ' +
         'did not sample comes back with');

  assert((perf.sample_seconds <= SAMPLE_MAX):
         'and no more than 4.0s - a two second window measured 2.096 on ' +
         'this fixture, got ' + %char(perf.sample_seconds));

  assert((perf.thread_count > 0):
         'a sample fills the thread count as well, got ' +
         %char(perf.thread_count));
  aEqualV(psds.current_user: perf.current_user:
          'and the current user');
  aEqualV(PGM_LOWER: perf.job_function:
          'and the function, still in the case the system reports it');
  aEqualV(PGM_STATUS: perf.job_status:
          'and the job status');
  iEqual(19: %len(%trimr(perf.active_since)):
         'and the rendered time the job went active, got "' +
         %trim(perf.active_since) + '"');
  aEqualV(' ': %subst(perf.active_since: 11: 1):
          'rendered the same way a sample as it is without one');

  assert((perf.total_disk_io > LIFETIME_IO_FLOOR):
         'and the LIFETIME I/O figure survives the sample - it is not the ' +
         'window and sampling must not overwrite it with one, got ' +
         %char(perf.total_disk_io));

  assert((perf.disk_io_count < perf.total_disk_io):
         'while the WINDOW figure is what this job did in ' +
         %char(SAMPLE_SECS) + ' seconds of doing nothing: sampled ' +
         %char(perf.disk_io_count) + ' against a lifetime of ' +
         %char(perf.total_disk_io));

end-proc;

//==============================================================================
// The window is the one that was asked for
//
// The case above rules out a procedure that never waits. This rules out one
// that always waits the same length - a hardcoded delay, or a window measured
// from something other than the argument - which the case above cannot,
// because a fixed two seconds passes every one of its bounds.
//
// Two windows, one short and one long, three seconds apart. Measured out of
// band: one second reads 1.120 and four reads 4.112. A single fixed figure
// cannot land inside both ranges, and cannot put three seconds between them.
//
// It costs five seconds of suite time and there is no cheaper shape: the
// smallest pair that separates a fixed window from a real one still has to
// contain two real windows.
//==============================================================================

dcl-proc test_job_sample_honours_the_seconds_asked_for export;

  dcl-ds short_perf likeds(SCQRY_PERF_t) inz(*likeds);
  dcl-ds long_perf  likeds(SCQRY_PERF_t) inz(*likeds);

  assert(SCQRY_job_sample(g_pgm_job: SHORT_SECS: short_perf):
         'a one second sample of the staged job answers');
  assert(SCQRY_job_sample(g_pgm_job: LONG_SECS: long_perf):
         'and a four second one');

  assert((short_perf.sample_seconds >= SHORT_MIN and
          short_perf.sample_seconds <= SHORT_MAX):
         'the one second window reports between 0.5s and 2.5s - measured ' +
         '1.120, got ' + %char(short_perf.sample_seconds));

  assert((long_perf.sample_seconds >= LONG_MIN and
          long_perf.sample_seconds <= LONG_MAX):
         'the four second window reports between 3.0s and 6.5s - measured ' +
         '4.112, got ' + %char(long_perf.sample_seconds));

  assert((long_perf.sample_seconds - short_perf.sample_seconds >= SPREAD_MIN):
         'AND THE TWO DISAGREE BY AT LEAST TWO SECONDS. This is what a fixed ' +
         'window cannot do in either direction: a procedure that always ' +
         'waits the same time, or none at all, reports the same figure for ' +
         'both. One second read ' + %char(short_perf.sample_seconds) +
         ', four seconds read ' + %char(long_perf.sample_seconds));

end-proc;

//==============================================================================
// The JVM figures perfinfo prints after the heap
//
// Four new numbers on a structure this suite already proves can be filled.
// Three of them are asserted as populated and as distinct from their
// neighbours; the fourth cannot be, and the case says which and why rather
// than asserting something that a never-written field would also satisfy.
//
// Measured out of band, 08/09/2026, against QSYS2.JVM_INFO - all three JVMs
// running on this machine:
//
//   QSRVMON     GC 203ms / 34 cycles   JIT 264192  shared 0  malloc 305155
//   QTOCRUNPRX  GC 390ms / 19 cycles   JIT  10240  shared 0  malloc  85740
//   the third   GC 1844ms / 2 cycles   JIT 264192  shared 0  malloc 349508
//
// and the third of those is the job upstream's own capture was taken from -
// its JIT and malloc figures are the 264192 and 349508 upstream printed.
//==============================================================================

dcl-proc test_jvm_info_new_figures export;

  dcl-ds jvm likeds(SCQRY_JVM_t) inz(*likeds);

  assert(jvm_of_qsrvmon(jvm):
         'a ' + JVM_JOB + ' job runs a JVM - the fixture this case needs');

  assert((jvm.gc_cycles > 0):
         'it has collected at least once, so neither GC figure is ' +
         'legitimately zero - got ' + %char(jvm.gc_cycles) + ' cycles');

  assert((jvm.gc_total_time > 0):
         'GC total time is populated, in milliseconds - measured 203ms over ' +
         '34 cycles here, got ' + %char(jvm.gc_total_time));

  assert((jvm.gc_total_time <> jvm.gc_cycles):
         'and it is a different number from the cycle count beside it - two ' +
         'equal figures mean both fields came from one column, both ' +
         'reading ' + %char(jvm.gc_cycles));

  assert((jvm.jit_memory > 0):
         'JIT memory is populated, in kilobytes - measured 264192, got ' +
         %char(jvm.jit_memory));

  assert((jvm.malloc_memory > 0):
         'malloc''ed memory is populated, in kilobytes - measured 305155, ' +
         'got ' + %char(jvm.malloc_memory));

  assert((jvm.jit_memory <> jvm.malloc_memory):
         'and the two are different numbers rather than one column read ' +
         'twice, both reading ' + %char(jvm.jit_memory));

  // SHARED CLASS SIZE IS THE ONE THIS CANNOT PIN, and saying so is the point.
  // Every JVM on this machine reports 0 for it - all three, measured - so
  // "shared class is zero" and "shared class was never written" are the same
  // observation and no fixture available here separates them. What is left is
  // the mix-up: a field wired to a neighbour's column carries a neighbour's
  // value, and that this does catch.
  assert((jvm.shared_class <> jvm.jit_memory and
          jvm.shared_class <> jvm.malloc_memory and
          jvm.shared_class <> jvm.gc_total_time):
         'shared class size is not one of its neighbours'' values - it ' +
         'reads ' + %char(jvm.shared_class) + ' against JIT ' +
         %char(jvm.jit_memory) + ', malloc ' + %char(jvm.malloc_memory) +
         ', GC time ' + %char(jvm.gc_total_time));

end-proc;

//==============================================================================
// A job that runs no JVM leaves the JVM figures alone
//
// The existing absent case asks about a job that does not exist. This asks
// about one that DOES - the staged PASE delay, which is live, findable and
// running no JVM - so a lookup that answered for any active job says true here
// and false there.
//
// Poisoned, for the reason test_job_attrs_absent_clears sets out: a structure
// that arrives clear and leaves clear cannot tell a procedure that cleared it
// from one that never touched it.
//==============================================================================

dcl-proc test_jvm_info_non_jvm_job export;

  dcl-ds jvm likeds(SCQRY_JVM_t) inz(*likeds);

  jvm.gc_total_time = POISON_NUM;
  jvm.jit_memory    = POISON_NUM;
  jvm.shared_class  = POISON_NUM;
  jvm.malloc_memory = POISON_NUM;

  nEqual(false: SCQRY_jvm_info(g_pgm_job: jvm):
         'the staged job runs a PASE delay and no JVM, so there is no JVM ' +
         'row for it - and unlike the not-found case this job exists, so a ' +
         'lookup that answered for any live job would say true here');

  nEqual(false: jvm.found: 'and it is not marked found');

  assert((jvm.gc_total_time = 0 and jvm.jit_memory = 0 and
          jvm.shared_class = 0 and jvm.malloc_memory = 0):
         'and none of the four new figures was left holding what the caller ' +
         'had: GC time ' + %char(jvm.gc_total_time) + ', JIT ' +
         %char(jvm.jit_memory) + ', shared class ' +
         %char(jvm.shared_class) + ', malloc ' + %char(jvm.malloc_memory));

end-proc;
