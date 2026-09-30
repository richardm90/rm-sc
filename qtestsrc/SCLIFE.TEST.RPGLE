**free

//==============================================================================
// SCLIFE.TEST - Service lifecycle test suite
//
// Starts, checks and stops a real service.
//
// Everything else in this project tests start and stop indirectly: SCLAUNCH
// asserts that the command STRING contains nohup and a trailing ampersand, and
// SCEXEC asserts status against services it did not start. Nothing has ever
// verified that a service launched through RMSC actually survives the launcher,
// that the polling notices when it comes up, or that stopping it works.
//
// The service is one this suite creates, submits and ends. That is the
// difference from testing against something already on the system: nothing
// else depends on it, and taking it down harms nobody.
//
// It is submitted to batch deliberately. The job name is then predictable, so
// check_alive can be a job name and the suite needs nothing installed - and it
// is the path the real services on this system actually use.
//
// 30/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCEXEC_D.rpgleinc'
/include 'SCLOG_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// Long enough to be caught running, short enough that a leaked job goes away
dcl-c SERVICE_RUNS_FOR const('120');

// Ten characters, so it is a legal job name and matches what the definition
// asks SBMJOB for
dcl-c TEST_JOB const('RMSCLIFE');

// How long to wait for the test job to go away after ENDJOB
dcl-c WAIT_LIMIT const(30);

dcl-s g_dir like(STMF_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr build_collection;
  coll likeds(SCCOLL_t);
end-pr;

dcl-pr end_test_job;
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  dcl-s y like(STRING_t);
  dcl-s handle like(INTEGER_t);
  dcl-s path like(STMF_t);

  g_dir = '/tmp/rmsc-life-test-' + %trim(psds.current_user);
  IFS_crtdir(g_dir);
  SCOUT_set_colour(false);

  // Nothing from a previous run should be left running
  end_test_job();

  y = 'name: RMSC Lifecycle Test' + LF;
  y += 'start_cmd: /QOpenSys/usr/bin/sleep ' + SERVICE_RUNS_FOR + LF;
  y += 'check_alive: ' + TEST_JOB + LF;
  y += 'batch_mode: true' + LF;
  y += 'sbmjob_jobname: ' + TEST_JOB + LF;
  y += 'sbmjob_opts: JOBQ(QUSRNOMAX)' + LF;
  // Short, so a service that never comes up fails the suite quickly rather
  // than making it look hung
  // Generous, because a busy job queue can take a while. A service that never
  // starts still fails within this rather than hanging the suite.
  y += 'startup_wait_time: 40' + LF;
  y += 'stop_wait_time: 40' + LF;

  path = %trim(g_dir) + '/rmsclife.yaml';
  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: y);
  IFS_close_file(handle);

end-proc;

dcl-proc tearDownSuite export;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  // Unconditionally, whatever the tests did. A suite that leaves a submitted
  // job behind when it fails is worse than no suite.
  end_test_job();

  dir = IFS_opendir(g_dir);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if %len(filename) > 5
         and %subst(filename: %len(filename) - 4) = '.yaml';
        IFS_remove_file(%trim(g_dir) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_dir);
  endif;

end-proc;

//==============================================================================
// Helpers
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

dcl-proc build_collection;
  dcl-pi *n;
    coll likeds(SCCOLL_t);
  end-pi;

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'test definition loaded');

end-proc;

// Ends the job AND waits for it to actually go.
//
// ENDJOB returns as soon as the request is made, not when the job has ended.
// Returning here without waiting made this suite flaky: a test would end the
// job, immediately assert the service was not running, and race a job that was
// still on its way out. A test that passes or fails depending on timing is
// worse than one that fails, because it teaches you to re-run it.
dcl-proc end_test_job;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s i      like(INTEGER_t);
  dcl-s waited like(INTEGER_t) inz(0);

  if SCQRY_jobs_by_name(TEST_JOB: '': jobs) = 0;
    return;
  endif;

  for i = 1 to jobs.count;
    QCMD_exc('ENDJOB JOB(' + %trim(jobs.name(i)) +
             ') OPTION(*IMMED)': qerr);
  endfor;

  dow waited < WAIT_LIMIT;
    if SCQRY_jobs_by_name(TEST_JOB: '': jobs) = 0;
      return;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  // Say so rather than letting a later assertion fail for a reason that has
  // nothing to do with what it is testing
  assert((SCQRY_jobs_by_name(TEST_JOB: '': jobs) = 0):
         'test job ' + TEST_JOB + ' did not end within ' +
         %char(WAIT_LIMIT) + 's');

end-proc;

//==============================================================================
// The definition loads and describes what we asked for
//==============================================================================

dcl-proc test_definition_loads export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);

  build_collection(coll);

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found by short name');
  nEqual(true: def.batch_mode: 'submitted to batch');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'a job criterion');

end-proc;

//==============================================================================
// Before starting, it is not running
//
// Establishes the baseline. Without it, a test that finds the service running
// afterwards has not shown that RMSC started it.
//==============================================================================

dcl-proc test_not_running_before_start export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);

  end_test_job();

  build_collection(coll);
  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');

  aEqualV(SCOUT_NOT_RUNNING: SCEXEC_status(def): 'not running yet');

end-proc;

//==============================================================================
// The full lifecycle: start, observe running, stop, observe stopped
//
// This is the test the rest of the suite could not do. It proves the launched
// service outlives the launcher, that polling notices it, and that stopping it
// works - none of which the string assertions in SCLAUNCH.TEST can show.
//==============================================================================

dcl-proc test_start_then_stop export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  build_collection(coll);

  // Start. SCEXEC_start returns only once the service is actually alive, so a
  // true here already means the poll saw it.
  assert(SCEXEC_start(coll: 'rmsclife': false: err):
         'started: ' + %trim(err));

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');
  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'running after start');

  // Stop. No stop_cmd, so this goes through ENDJOB.
  assert(SCEXEC_stop(coll: 'rmsclife': false: err):
         'stopped: ' + %trim(err));

  aEqualV(SCOUT_NOT_RUNNING: SCEXEC_status(def): 'not running after stop');

end-proc;

//==============================================================================
// The job really is gone, not merely reported gone
//
// Asks the system directly rather than trusting the status RMSC just gave.
//==============================================================================

dcl-proc test_job_actually_ended export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  build_collection(coll);

  assert(SCEXEC_start(coll: 'rmsclife': false: err): 'started: ' + %trim(err));
  assert((SCQRY_jobs_by_name(TEST_JOB: '': jobs) > 0):
         'the system can see the job');

  assert(SCEXEC_stop(coll: 'rmsclife': false: err): 'stopped: ' + %trim(err));
  iEqual(0: SCQRY_jobs_by_name(TEST_JOB: '': jobs):
         'the system no longer sees the job');

end-proc;

//==============================================================================
// Starting something already running is not an error
//
// SCEXEC_start skips a service that is already up, which is what makes
// starting a group safe when half of it is running.
//==============================================================================

dcl-proc test_start_when_already_running export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  build_collection(coll);

  assert(SCEXEC_start(coll: 'rmsclife': false: err): 'first start: ' + %trim(err));
  assert(SCEXEC_start(coll: 'rmsclife': false: err): 'second start: ' + %trim(err));

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');
  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'still running');

  assert(SCEXEC_stop(coll: 'rmsclife': false: err): 'stopped: ' + %trim(err));

end-proc;

//==============================================================================
// Stopping something already stopped is not an error either
//==============================================================================

dcl-proc test_stop_when_not_running export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  end_test_job();
  build_collection(coll);

  assert(SCEXEC_stop(coll: 'rmsclife': false: err):
         'stopping something already stopped: ' + %trim(err));

end-proc;

//==============================================================================
// restart leaves it running
//==============================================================================

dcl-proc test_restart export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  build_collection(coll);

  assert(SCEXEC_start(coll: 'rmsclife': false: err): 'started: ' + %trim(err));
  assert(SCEXEC_restart(coll: 'rmsclife': false: err): 'restarted: ' + %trim(err));

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');
  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'running after restart');

  assert(SCEXEC_stop(coll: 'rmsclife': false: err): 'stopped: ' + %trim(err));

end-proc;

//==============================================================================
// --splf suppresses the per-instance log file; without it, one is written
//
// MEASURED live against sc 1.7.1: a normal batch start's launch command ends
// with a ">> <logfile> 2>&1" redirect, and RMSC's batch-start command
// normally writes the started instance's log to a fresh, timestamped file
// under ~/.sc/logs/. --splf ("send output to *SPLF when submitting jobs to
// batch") makes RMSC omit that redirect entirely, so no per-instance log file
// is ever created for that start. Confirmed live with a clean A/B on a real
// service: a normal start left `loginfo` able to find a log path; a --splf
// start left `loginfo` reporting "<unknown> (try checking in log directory
// ...)" - no file existed to find.
//
// This is deliberately a PAIR, per CLAUDE.md's "must disagree" rule: the two
// tests below run the identical staged fixture through SCEXEC_start with only
// the splf argument flipped, and SCLOG_path(def) - the same "scan the log
// directory for this service's newest file" accessor SCEXEC.TEST's "Log file
// location" tests use - must answer DIFFERENTLY for the two: '' when splf is
// true, non-'' when splf is false. A fix that never wires the splf parameter
// through to the launch command (or wires it backwards) would make both
// tests see the same answer, and would fail exactly one half of this pair
// rather than passing both by leaving splf unused altogether.
//==============================================================================

dcl-proc test_start_without_splf_writes_a_log export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);
  dcl-s logPath like(STMF_t);

  build_collection(coll);

  // Same reason as the with-splf sibling below: SCLOG_path finds the
  // newest matching name, not necessarily one THIS call wrote, so a
  // leftover from an earlier test in the same run could make this pass
  // vacuously even if this specific start wrote nothing. Not reachable by
  // anything in this suite today (every splf=true call site cleans up
  // after itself), but free to close off rather than leave implicit.
  assert(SCCOLL_find(coll: 'rmsclife': def): 'found before start');
  clear_existing_logs(def);

  // splf = false: the ordinary path, same as every other start in this
  // suite. Named separately from test_start_then_stop because what is under
  // test here is the LOG FILE it leaves behind, not the running state.
  assert(SCEXEC_start(coll: 'rmsclife': false: err):
         'started without --splf: ' + %trim(err));

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');
  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'running after start');

  logPath = SCLOG_path(def);
  assert((%trim(logPath) <> ''):
         'ordinary start (splf off): SCLOG_path should find a log file ' +
         'written for this instance - the case --splf must differ from');

  assert(SCEXEC_stop(coll: 'rmsclife': false: err): 'stopped: ' + %trim(err));

  // Leave no more behind than the test itself created.
  if %trim(logPath) <> '';
    IFS_remove_file(logPath);
  endif;

end-proc;

dcl-proc test_start_with_splf_writes_no_log export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err like(SCEXEC_ERR_t);

  build_collection(coll);

  // Diagnosed empirically (29 September 2026, real box, job-log inspection
  // of the actual submitted SBMJOB command): SCLOG_path finds "the newest
  // matching name", not "a file THIS call created" (SCLOG.RPGLE says so
  // directly). Every OTHER test in this suite that starts 'rmsclife' -
  // test_start_then_stop, test_restart, etc. - leaves its own log file
  // behind; none of them clean up after themselves the way this test and
  // its without-splf sibling do. So without this, a leftover from an
  // EARLIER test in the same run can be found here and mistaken for
  // evidence that THIS start wrote one - confirmed live: the with-splf
  // job's own SBMJOB command genuinely carried no redirect, and the
  // assertion still failed against a stale file from test_restart.
  // Clearing every existing rmsclife log first makes "SCLOG_path finds
  // one" mean only one thing again.
  assert(SCCOLL_find(coll: 'rmsclife': def): 'found before start');
  clear_existing_logs(def);

  // splf = true: this is the case that must disagree with the test above.
  assert(SCEXEC_start(coll: 'rmsclife': true: err):
         'started with --splf: ' + %trim(err));

  assert(SCCOLL_find(coll: 'rmsclife': def): 'found');
  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'running after start');

  aEqualV('': SCLOG_path(def):
          'MEASURED live against sc 1.7.1 - --splf omits the log redirect ' +
          'from the batch-start command, so no log file is written for ' +
          'this instance and SCLOG_path must find none');

  assert(SCEXEC_stop(coll: 'rmsclife': false: err): 'stopped: ' + %trim(err));

end-proc;

//------------------------------------------------------------------------------
// clear_existing_logs - remove every log file SCLOG_path could find for def,
// not just the one most recent. Mirrors SCLOG_path's own directory scan
// (SCLOG.RPGLE) so "no matching file exists" and "SCLOG_path returns ''"
// stay the same statement.
//------------------------------------------------------------------------------

dcl-proc clear_existing_logs;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s dir      like(STMF_t);
  dcl-s handle   pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s suffix   like(STMF_t);
  dcl-s want_len like(INTEGER_t);

  dir = SCLOG_dir(def);
  handle = IFS_opendir(dir);
  if handle = *null;
    return;
  endif;

  suffix = '.' + %trim(def.short_name) + '.log';
  want_len = 19 + %len(%trim(suffix));

  dow IFS_readdir(handle: filename);
    if %len(%trim(filename)) = want_len
       and %subst(filename: 20: %len(%trim(suffix))) = %trim(suffix);
      IFS_remove_file(%trim(dir) + '/' + %trim(filename));
    endif;
  enddo;

  IFS_closedir(handle);

end-proc;
