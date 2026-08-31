**free

//==============================================================================
// SCJOB.TEST - Active job lookup test suite
//
// SCJOB replaces a SQL query with QUSLJOB, so what matters is that it agrees
// with the thing it replaced. Speed is worth nothing if the answer changes.
//
// 30/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCJOB_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// RPGUnit runs the suite in a spawned PASE job, so at least one exists
dcl-c LIVE_JOB const('QP0ZSPWP');
// Ten characters or fewer, and not a job anyone runs
dcl-c DEAD_JOB const('ZZNOSUCHJ');

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

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
// The API answers rather than falling back
//
// Falling back is not a failure - SQL gives the right answer - but it means
// the API is not being used, which is the whole point.
//==============================================================================

dcl-proc test_api_is_available export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCJOB_by_name(LIVE_JOB: jobs) <> SCJOB_UNAVAILABLE):
         'the API answered rather than falling back - ' +
         %trim(SCJOB_last_error()));

end-proc;

//==============================================================================
// It finds a job that exists, and agrees with SQL on how many
//==============================================================================

dcl-proc test_finds_a_live_job export;

  dcl-ds api likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds sql likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCJOB_by_name(LIVE_JOB: api) > 0): 'API found the job');
  assert((SCQRY_jobs_by_name(LIVE_JOB: '': sql) > 0): 'so did the caller');
  iEqual(sql.count: api.count: 'both routes found the same number');

end-proc;

//==============================================================================
// A job that cannot exist returns nothing, not an error
//==============================================================================

dcl-proc test_absent_job export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCJOB_by_name(DEAD_JOB: jobs): 'no jobs');
  iEqual(0: jobs.count: 'structure agrees');
  iEqual(0: SCQRY_jobs_by_name(DEAD_JOB: '': jobs): 'and via the caller');

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

  assert((SCJOB_by_name(LIVE_JOB: jobs) > 0): 'found');
  name = jobs.name(1);

  slash1 = %scan('/': name);
  assert((slash1 > 1): 'a job number, then a slash');

  slash2 = %scan('/': name: slash1 + 1);
  assert((slash2 > slash1 + 1): 'a user name, then a second slash');

  aEqualV(LIVE_JOB: %subst(name: slash2 + 1):
          'and the job name last');

end-proc;

//==============================================================================
// The two routes name the same jobs, not merely the same number of them
//==============================================================================

dcl-proc test_same_jobs_as_sql export;

  dcl-ds api likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds sql likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);
  dcl-s j like(INTEGER_t);
  dcl-s found like(BOOLEAN_t);

  SCJOB_by_name(LIVE_JOB: api);
  SCQRY_jobs_by_name(LIVE_JOB: '': sql);

  for i = 1 to api.count;
    found = false;
    for j = 1 to sql.count;
      if api.name(i) = sql.name(j);
        found = true;
        leave;
      endif;
    endfor;
    assert(found: 'API job ' + %trim(api.name(i)) +
                  ' also found by the SQL route');
  endfor;

end-proc;

//==============================================================================
// A name too long to be a job name matches nothing
//
// Rather than being truncated to ten characters and matching something else.
//==============================================================================

dcl-proc test_overlong_name export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  iEqual(0: SCJOB_by_name('QP0ZSPWPTOOLONG': jobs):
         'no match for a name that cannot be a job name');

end-proc;

//==============================================================================
// Repeated calls are stable
//
// The user space is reused between calls, so a stale list would show here.
//==============================================================================

dcl-proc test_repeated_calls export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s first like(INTEGER_t);
  dcl-s i like(INTEGER_t);

  first = SCJOB_by_name(LIVE_JOB: jobs);
  assert((first > 0): 'found on the first call');

  for i = 1 to 4;
    iEqual(first: SCJOB_by_name(LIVE_JOB: jobs):
           'call ' + %char(i + 1) + ' agrees');
    iEqual(0: SCJOB_by_name(DEAD_JOB: jobs):
           'and the absent job stays absent on call ' + %char(i + 1));
  endfor;

end-proc;
