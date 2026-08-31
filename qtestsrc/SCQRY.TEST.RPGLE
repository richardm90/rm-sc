**free

//==============================================================================
// SCQRY.TEST - System query test suite
//
// These run against live system state, so they assert what is reliably true
// on any IBM i rather than anything specific to one machine. Where a result
// cannot be predicted, the assertion is on the shape of the answer - that the
// query runs, returns a sane count and does not fall over.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCQRY_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// A port nothing should be listening on. Not in the registered range and not
// something an IBM i or an open-source package claims.
dcl-c UNUSED_PORT const(59417);

// SSH. The suite reaches this system over it, so it is listening by
// definition while the tests are running.
dcl-c SSH_PORT const(22);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

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
// A listening port is reported as listening
//==============================================================================

dcl-proc test_port_listening export;

  nEqual(true: SCQRY_port_listening(SSH_PORT):
         'SSH is listening - this suite arrived over it');

end-proc;

dcl-proc test_port_not_listening export;

  nEqual(false: SCQRY_port_listening(UNUSED_PORT):
         'nothing is listening on an unused port');

end-proc;

//==============================================================================
// The job holding a listening socket can be found
//==============================================================================

dcl-proc test_jobs_on_port export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert((SCQRY_jobs_on_port(SSH_PORT: jobs) > 0):
         'a job holds the SSH socket');
  iEqual(jobs.count: SCQRY_jobs_on_port(SSH_PORT: jobs):
         'returned count matches the structure');
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
// SSH is the case that proves it. The suite arrives over port 22, so while it
// runs there is a listening job AND at least one connected session held by a
// different job. More than one job here means client connections are being
// reported as the service.
//
// This is not a cosmetic difference. SCEXEC_jobs is built on this procedure,
// and stop and kill pass its result straight to ENDJOB - so over-matching here
// ends jobs belonging to whoever happens to be connected.
//==============================================================================

dcl-proc test_jobs_on_port_is_listener_only export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s n     like(INTEGER_t);
  dcl-s i     like(INTEGER_t);
  dcl-s names varchar(512) inz('');

  n = SCQRY_jobs_on_port(SSH_PORT: jobs);

  // Name every job returned, so a failure says which ones rather than only
  // how many. Plain concatenation, not aEqual - see docs/testing-notes.md.
  for i = 1 to jobs.count;
    if i > 1;
      names += ', ';
    endif;
    names += %trim(jobs.name(i));
  endfor;

  assert((n >= 1): 'the SSH listener is found');
  assert((n = 1): 'port 22 must resolve to the listening job alone, but ' +
                  %char(n) + ' were returned: ' + %trim(names));

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

  // RPGUnit runs the suite in a spawned PASE job, so at least this one exists
  assert((SCQRY_jobs_by_name('QP0ZSPWP': '': jobs) > 0):
         'the job running this suite is found');
  assert((%len(%trim(jobs.name(1))) > 0): 'job name is populated');

end-proc;

dcl-proc test_jobs_by_name_with_subsystem export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  // Shape only: which subsystem the job runs in varies by system
  assert((SCQRY_jobs_by_name('QP0ZSPWP': 'QUSRWRK': jobs) >= 0):
         'subsystem-qualified lookup runs');
  assert((jobs.count <= SCQRY_MAX_JOBS): 'count stays within the array');

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
// Job detail
//==============================================================================

dcl-proc test_job_start_time export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s  started like(SCQRY_TIME_t);

  if SCQRY_jobs_by_name('QP0ZSPWP': '': jobs) = 0;
    return;
  endif;

  started = SCQRY_job_start_time(jobs.name(1));
  assert((%len(%trim(started)) = 19):
         'start time comes back as YYYY-MM-DD HH:MM:SS');

end-proc;

dcl-proc test_job_start_time_absent export;

  aEqualV('': SCQRY_job_start_time('000000/NOBODY/NOSUCHJOB'):
          'a job that does not exist has no start time');

end-proc;

dcl-proc test_job_perf export;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);

  if SCQRY_jobs_by_name('QP0ZSPWP': '': jobs) = 0;
    return;
  endif;

  assert(SCQRY_job_perf(jobs.name(1): perf): 'performance figures returned');
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
// JVM and spooled files - shape only, since neither is guaranteed to exist
//==============================================================================

dcl-proc test_jvm_info_absent export;

  dcl-ds jvm likeds(SCQRY_JVM_t) inz(*likeds);

  SCQRY_jvm_info('000000/NOBODY/NOSUCHJOB': jvm);
  nEqual(false: jvm.found: 'no JVM for a job that does not exist');

end-proc;

dcl-proc test_splfs_for_job export;

  dcl-ds splfs likeds(SCQRY_SPLFS_t) inz(*likeds);

  iEqual(0: SCQRY_splfs_for_job('000000/NOBODY/NOSUCHJOB': splfs):
         'no spooled files for a job that does not exist');
  assert((splfs.count <= SCQRY_MAX_SPLF): 'count stays within the array');

end-proc;
