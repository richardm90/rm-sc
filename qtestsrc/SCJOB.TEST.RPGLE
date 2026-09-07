**free

//==============================================================================
// SCJOB.TEST - Active job lookup test suite
//
// SCJOB replaces a SQL query with QUSLJOB, so what matters is that it agrees
// with the thing it replaced. Speed is worth nothing if the answer changes.
//
// THE FIXTURE IS A JOB THIS SUITE SUBMITS, NOT ONE THE SYSTEM HAPPENS TO RUN.
//
// It used to be QP0ZSPWP - the spawned PASE job RPGUnit itself runs in, so at
// least one always exists. That is true, and it is not enough: every ssh
// connection to the machine creates another one, so the count moves while the
// suite is running. Two assertions were built on that count holding still
// between two observations, and both failed spuriously and passed on a re-run:
//
//   test_repeated_calls    Expected 14, but was 15
//   test_finds_a_live_job  Expected 21, but was 20
//
// Neither was a defect. A test may only assert the stability of something it
// controls, and this suite controlled nothing about QP0ZSPWP. The cost of
// leaving it is not the failures - it is that a suite which cries wolf gets
// its next failure explained away, and the one after that is the real one.
//
// So setUpSuite submits RMSCJOBT, a job running nothing but a delay, and the
// tests ask about that. Nothing else on the system can start or end it, so
// five calls agreeing about it is a claim about the procedure rather than
// about the machine being quiet. The suite records the FULL qualified name at
// set-up time and asserts that both routes name that job, which is a stronger
// claim than a count and is immune to a second maintainer running the suite at
// the same moment.
//
// The absent-job half was never flaky and is unchanged.
//
// Separately, every cross-check against "the SQL route" now names a subsystem.
// With a blank one SCQRY_jobs_by_name delegates to SCJOB, so the comparisons
// were running a single code path twice - true before this change and not
// something it caused, but the assertions read as though two paths were being
// compared, and now they are.
//
// 30/08/2026 - RM - created
// 07/09/2026 - RM - staged fixture job replaces QP0ZSPWP
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCJOB_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// Ten characters or fewer, so it is a legal job name, and nothing anyone else
// on this system runs
dcl-c FIXTURE_JOB const('RMSCJOBT');

// Long enough that the suite cannot outlive it, short enough that a job leaked
// by a run killed before its teardown goes away on its own
dcl-c FIXTURE_RUNS_FOR const('600');

// THE SUBSYSTEM THE FIXTURE JOB RUNS IN, and it is load-bearing rather than
// decorative.
//
// SCQRY_jobs_by_name with a BLANK subsystem hands the question to SCJOB and
// returns its answer, so a cross-check written with '' compares this module
// with itself and would agree with a defect as readily as with correct code.
// Every comparison in this suite passes this constant instead, which is the
// argument that reaches the other path.
//
// It is the subsystem QUSRNOMAX is allocated to, and set-up PROVES it: the
// wait for the fixture job is made subsystem-qualified, so a machine where
// that jobq belongs elsewhere fails in set-up saying so, rather than the
// cross-checks quietly returning nothing.
dcl-c FIXTURE_SBS const('QUSRWRK');

// Ten characters or fewer, and not a job anyone runs
dcl-c DEAD_JOB const('ZZNOSUCHJ');

// How long to wait for the fixture job to start, and to go away again
dcl-c WAIT_LIMIT const(60);

// The fixture job's full number/user/name, captured once it is running. Tests
// assert that this exact job is what the two routes return.
dcl-s g_fixture like(SCQRY_JOBNAME_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr start_fixture_job;
end-pr;

dcl-pr end_fixture_job;
end-pr;

dcl-pr job_in_list like(BOOLEAN_t);
  jobs likeds(SCQRY_JOBS_t);
  name like(SCQRY_JOBNAME_t) const;
end-pr;

dcl-pr names_of varchar(512);
  jobs likeds(SCQRY_JOBS_t);
end-pr;

dcl-pr is_fixture_job like(BOOLEAN_t);
  name like(SCQRY_JOBNAME_t) const;
end-pr;

dcl-pr cmd_text varchar(512);
  cmd  varchar(256) const;
  qerr likeds(QCMD_ERR_t);
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  // Debris first. A run killed between staging and teardown leaves the job
  // behind, and a second fixture job would make every count in the suite say
  // two where it means one.
  end_fixture_job();
  start_fixture_job();

end-proc;

dcl-proc tearDownSuite export;

  // Unconditionally, whatever the tests did. A suite that leaves a submitted
  // job behind when it fails is worse than no suite.
  end_fixture_job();

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

//==============================================================================
// start_fixture_job
//   Submit the job the suite asserts about, and wait until it is really there
//
// THE FIXTURE PROVES ITSELF. A submitted job that never starts - a held job
// queue, no authority, a subsystem that is not running - would leave every
// test in this suite asking about a job that does not exist, and "no jobs
// found" is exactly what a broken lookup returns too. So this waits for the
// job and FAILS if it never appears, rather than letting the suite run on and
// report a pass for a procedure that answered nothing.
//
// It waits through the SQL route deliberately, and that means passing a real
// subsystem: SCJOB - the API path - is what this suite is testing, and a
// fixture established through the thing under test cannot say whether a
// missing job is a missing job or a broken lookup. A blank subsystem would not
// do it, because that argument is delegated straight back to SCJOB.
//
// Waiting this way also proves FIXTURE_SBS, which the cross-checks depend on.
//==============================================================================

dcl-proc start_fixture_job;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd     varchar(256);
  dcl-s waited  like(INTEGER_t) inz(0);
  dcl-s ok      like(BOOLEAN_t);

  cmd = 'SBMJOB CMD(DLYJOB DLY(' + FIXTURE_RUNS_FOR + ')) JOB(' +
        FIXTURE_JOB + ') JOBQ(QUSRNOMAX)';

  // The result FIRST, the message second. Built in one expression the two
  // operands have no guaranteed evaluation order, so the message can be
  // assembled before qerr is filled - losing the message id in exactly the run
  // that needed it.
  ok = QCMD_exc(cmd: qerr);
  assert(ok: 'fixture job submitted - ' + cmd_text(cmd: qerr));

  dow waited < WAIT_LIMIT;
    if SCQRY_jobs_by_name(FIXTURE_JOB: FIXTURE_SBS: jobs) > 0;
      g_fixture = jobs.name(1);
      leave;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  // On what was STORED, not on a flag. A flag set beside the store is a second
  // thing that has to stay in step, and the tidy-up that puts it inside the
  // loop turns this into an assertion that cannot fire - the suite would then
  // run every test against a blank g_fixture.
  assert((%len(%trimr(g_fixture)) > 0):
         'fixture job ' + FIXTURE_JOB + ' started in subsystem ' +
         FIXTURE_SBS + ' within ' + %char(WAIT_LIMIT) + 's - every ' +
         'assertion in this suite depends on it, so the suite fails rather ' +
         'than reporting nothing found. If this machine runs QUSRNOMAX ' +
         'elsewhere, FIXTURE_SBS is what needs changing');

  // EXACTLY ONE, not merely at least one. A job left on the queue by a run
  // that was killed cannot be swept (end_fixture_job says why), and it shows
  // up here: two jobs of this name going active together would make every
  // count in this suite say two where it means one, and test_job_name_shape
  // compare against whichever the lookup happened to put first. Said plainly
  // here, it is one legible failure instead of a scattering of odd ones.
  SCQRY_jobs_by_name(FIXTURE_JOB: FIXTURE_SBS: jobs);
  iEqual(1: jobs.count:
         'exactly one job named ' + FIXTURE_JOB + ' is active - more than ' +
         'one means an earlier run left one on the job queue: ' +
         names_of(jobs) + '. End the ones that are not this run''s and ' +
         'try again');

end-proc;

//==============================================================================
// end_fixture_job
//   End it AND wait for it to actually go
//
// ENDJOB returns when the request is made, not when the job has ended. The
// same shortcut made SCLIFE.TEST flaky - see docs/testing-notes.md - so this
// polls until the job is really absent and says so if it never is.
//==============================================================================

dcl-proc end_fixture_job;

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
  // So the leftover is DETECTED instead, in start_fixture_job, which fails if more
  // than one job of this name is active. The window that produces one is the
  // fraction of a second between SBMJOB and the job going active on a *NOMAX
  // queue - and if that queue is held, so that the window is wide, this
  // suite's own job does not start either and set-up says so.

  if SCQRY_jobs_by_name(FIXTURE_JOB: '': jobs) = 0;
    return;
  endif;

  for i = 1 to jobs.count;
    // GUARDED. This ENDJOBs whatever a lookup returns, and that lookup is code
    // this project tests rather than trusts - a guard removed here once made a
    // lookup return far more than it should. If it ever returns every active
    // job, an unguarded sweep ends all of them, this suite's own job included.
    if is_fixture_job(jobs.name(i));
      QCMD_exc('ENDJOB JOB(' + %trim(jobs.name(i)) +
               ') OPTION(*IMMED)': qerr);
    endif;
  endfor;

  dow waited < WAIT_LIMIT;
    if SCQRY_jobs_by_name(FIXTURE_JOB: '': jobs) = 0;
      return;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  assert((SCQRY_jobs_by_name(FIXTURE_JOB: '': jobs) = 0):
         'fixture job ' + FIXTURE_JOB + ' did not end within ' +
         %char(WAIT_LIMIT) + 's');

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
// is_fixture_job - is this qualified name one of OUR jobs
//
// number/user/name, so the job name is what follows the last slash. Nothing is
// ended unless that segment is the one this suite submitted.
//==============================================================================

dcl-proc is_fixture_job;
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

  return (%trimr(%subst(name: last + 1)) = FIXTURE_JOB);

end-proc;

//==============================================================================
// names_of - every job in a list, so a failure says which rather than only how
//            many. Plain concatenation, not aEqual - see docs/testing-notes.md
//==============================================================================

dcl-proc names_of;
  dcl-pi *n varchar(512);
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s i like(INTEGER_t);
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
// The API answers rather than falling back
//
// Falling back is not a failure - SQL gives the right answer - but it means
// the API is not being used, which is the whole point.
//==============================================================================

dcl-proc test_api_is_available export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCJOB_by_name(FIXTURE_JOB: jobs) <> SCJOB_UNAVAILABLE):
         'the API answered rather than falling back - ' +
         %trim(SCJOB_last_error()));

end-proc;

//==============================================================================
// It finds the staged job, and agrees with SQL about it
//
// The count comparison is safe here in a way it was not against QP0ZSPWP:
// nothing on this system can start or end a job called RMSCJOBT while the
// suite is running, so a difference between the two routes is a difference
// between the two routes.
//
// AND THEY REALLY ARE TWO ROUTES, which takes the subsystem argument. Asked
// with a blank subsystem, SCQRY_jobs_by_name delegates to SCJOB and returns
// its answer - so a cross-check written that way runs one code path twice and
// agrees with itself whatever either does. FIXTURE_SBS is what reaches the
// other one.
//
// The name assertions matter more than the count. They say the two routes
// found THE SAME JOB, which a pair of counts that happen to agree does not.
//==============================================================================

dcl-proc test_finds_a_live_job export;

  dcl-ds api likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds sql likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCJOB_by_name(FIXTURE_JOB: api) > 0): 'API found the staged job');
  assert((SCQRY_jobs_by_name(FIXTURE_JOB: FIXTURE_SBS: sql) > 0):
         'so did the SQL route');

  assert(job_in_list(api: g_fixture):
         'the API returned the staged job ' + %trim(g_fixture) +
         ', got: ' + names_of(api));
  assert(job_in_list(sql: g_fixture):
         'so did the SQL route, got: ' + names_of(sql));

  iEqual(sql.count: api.count: 'both routes found the same number');

end-proc;

//==============================================================================
// A job that cannot exist returns nothing, not an error
//==============================================================================

dcl-proc test_absent_job export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCJOB_by_name(DEAD_JOB: jobs): 'no jobs');
  iEqual(0: jobs.count: 'structure agrees');
  iEqual(0: SCQRY_jobs_by_name(DEAD_JOB: FIXTURE_SBS: jobs):
         'and via the SQL route');

end-proc;

//==============================================================================
// Job names come back in the same shape the SQL route produces
//
// Callers pass these straight to ENDJOB, so number/user/name matters.
//==============================================================================

dcl-proc test_job_name_shape export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s name  like(SCQRY_JOBNAME_t);
  dcl-s slash1 like(INTEGER_t);
  dcl-s slash2 like(INTEGER_t);

  assert((SCJOB_by_name(FIXTURE_JOB: jobs) > 0): 'found');
  name = jobs.name(1);

  slash1 = %scan('/': name);
  assert((slash1 > 1): 'a job number, then a slash');

  slash2 = %scan('/': name: slash1 + 1);
  assert((slash2 > slash1 + 1): 'a user name, then a second slash');

  aEqualV(FIXTURE_JOB: %subst(name: slash2 + 1):
          'and the job name last');

  // The whole thing, against what the SQL route said at set-up time
  aEqualV(g_fixture: name: 'the same qualified name as the SQL route');

end-proc;

//==============================================================================
// The two routes name the same jobs, not merely the same number of them
//
// Subsystem-qualified, for the reason given on test_finds_a_live_job: without
// it the "SQL route" is SCJOB again and this compares the API with itself.
//==============================================================================

dcl-proc test_same_jobs_as_sql export;

  dcl-ds api likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds sql likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  SCJOB_by_name(FIXTURE_JOB: api);
  SCQRY_jobs_by_name(FIXTURE_JOB: FIXTURE_SBS: sql);

  assert((api.count > 0): 'the API returned the staged job to compare');

  for i = 1 to api.count;
    assert(job_in_list(sql: api.name(i)):
           'API job ' + %trim(api.name(i)) +
           ' also found by the SQL route, which returned ' + names_of(sql));
  endfor;

end-proc;

//==============================================================================
// A name too long to be a job name matches nothing
//
// Rather than being truncated to ten characters and matching something else.
// RMSCJOBT is running, so a lookup that truncated would find it - which is
// what makes this case able to fail.
//==============================================================================

dcl-proc test_overlong_name export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCJOB_by_name('RMSCJOBTTOOLONG': jobs):
         'no match for a name that cannot be a job name');

end-proc;

//==============================================================================
// Repeated calls are stable
//
// The user space is reused between calls, so a stale list would show here.
//
// Against a job the suite submitted this is a claim about the procedure being
// deterministic. Against QP0ZSPWP it was a claim about nobody connecting to
// the machine for the duration of five calls, which is not something this
// suite can promise - and it duly failed with "Expected 14, but was 15".
//==============================================================================

dcl-proc test_repeated_calls export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s first like(INTEGER_t);
  dcl-s i like(INTEGER_t);

  first = SCJOB_by_name(FIXTURE_JOB: jobs);
  assert((first > 0): 'found on the first call');

  for i = 1 to 4;
    iEqual(first: SCJOB_by_name(FIXTURE_JOB: jobs):
           'call ' + %char(i + 1) + ' agrees');
    assert(job_in_list(jobs: g_fixture):
           'call ' + %char(i + 1) + ' still names ' + %trim(g_fixture) +
           ', got: ' + names_of(jobs));
    iEqual(0: SCJOB_by_name(DEAD_JOB: jobs):
           'and the absent job stays absent on call ' + %char(i + 1));
  endfor;

end-proc;

//==============================================================================
// The teardown guard only ever matches OUR job
//
// end_fixture_job ENDJOBs what a lookup returns, and that lookup is code this
// project tests rather than trusts. This pins the guard that stands between a
// lookup which over-matches and a suite that ends other people's jobs -
// including the one it is running in.
//==============================================================================

dcl-proc test_teardown_guard export;

  nEqual(true: is_fixture_job('123456/SOMEONE/' + FIXTURE_JOB):
         'our own job, whoever submitted it');
  nEqual(true: is_fixture_job(g_fixture): 'and the one actually staged');

  nEqual(false: is_fixture_job('123456/QSECOFR/QP0ZSPWP'):
         'not the job this suite runs in');
  nEqual(false: is_fixture_job('123456/QSYS/QINTER'):
         'not a subsystem monitor');
  nEqual(false: is_fixture_job(FIXTURE_JOB):
         'not an unqualified name, which has no job-name segment to trust');
  nEqual(false: is_fixture_job('123456/USER/' + FIXTURE_JOB + 'X'):
         'not a longer name that starts the same way');

end-proc;
