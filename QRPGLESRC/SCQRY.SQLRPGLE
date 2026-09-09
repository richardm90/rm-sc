**free

//==============================================================================
// SCQRY      - System queries
//
// Every liveness and reporting query, as embedded SQL.
//
// This is where the larger of the two speed wins lives. The Java
// implementation runs each of these by forking /QOpenSys/pkgs/bin/db2util -
// a new process and a new database connection per query - and a single
// 'check' on a service with two criteria pays that repeatedly. Here each is
// one statement on the connection the job already has.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: System queries');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCQRY_D.rpgleinc'
/include 'SCNET_D.rpgleinc'
/include 'SCJOB_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

exec sql SET OPTION COMMIT = *NONE, CLOSQLCSR = *ENDMOD, DATFMT = *ISO;

//==============================================================================
// QUSRJOBI - job run attributes, for SCQRY_job_attrs
//==============================================================================

// The only non-SQL query in this module, and deliberately so. Upstream gets
// these attributes by scraping DSPJOB OPTION(*RUNA); RMSC does not scrape a
// display command, and docs/parity.md records that decision and the three
// attributes it costs. ACTIVE_JOB_INFO carries most of the rest, but not
// PURGE, so one API call answers what a query plus a second lookup could not.

dcl-pr QUSRJOBI extpgm('QUSRJOBI');
  rcv    char(144) options(*varsize);
  rcvlen like(INTEGER_t) const;
  fmt    char(8) const;
  jobq   char(26) const;
  intid  char(16) const;
  errc   char(272) options(*varsize);
end-pr;

// Format JOBI0150, as documented. The manual's offsets are 0-based and RPG
// positions are 1-based, so every pos() below is its documented offset plus
// one. Each was also confirmed against a live job by setting a distinctive
// value with CHGJOB and finding where it landed, rather than by trusting the
// transcription - which is how the trap below was noticed.
//
// THE TRAP: max_temp_kb (doc 112) and max_temp_mb (doc 128) are THE SAME
// LIMIT in different units, and both read 2147483647 on a job at its default.
// Upstream prints megabytes - DSPJOB's own heading says "Maximum temporary
// storage in megabytes" - so max_temp_mb is the one to read. Taking the other
// would look correct on every job anybody would test it on, and be wrong only
// past 2TB. It is carried here, unused, so that a later reader can see which
// was chosen and why rather than wondering whether the other exists.
dcl-ds JOBI0150_t qualified template;
  run_priority   int(10)  pos(65);
  time_slice     int(10)  pos(69);
  default_wait   int(10)  pos(73);
  purge          char(10) pos(77);
  max_cpu_time   int(10)  pos(105);
  max_temp_kb    int(10)  pos(113);
  thread_count   int(10)  pos(117);
  max_threads    int(10)  pos(121);
  temp_used_mb   uns(10)  pos(125);
  max_temp_mb    int(10)  pos(129);
  peak_temp_mb   uns(10)  pos(133);
  cpu_used_total uns(20)  pos(137);
end-ds;

dcl-ds QUSRJOBI_ERR_t qualified template;
  bytes_provided like(INTEGER_t) inz(0);
  bytes_avail    like(INTEGER_t) inz(0);
  msgid          char(7);
  reserved       char(1);
  data           char(256);
end-ds;

//==============================================================================
// SCQRY_port_listening
//==============================================================================

// The IBM TCP/IP list API answers this in a fraction of the time the SQL
// service takes - measured, the difference is the SQL layer rather than the
// enumeration. The SQL path is kept as a fallback: if the API cannot answer,
// being slow is recoverable, and reporting a running service as down is not.
dcl-proc SCQRY_port_listening export;
  dcl-pi *n like(BOOLEAN_t);
    port like(INTEGER_t) const;
  end-pi;

  dcl-s found int(10) inz(0);
  dcl-s port_l int(10);
  dcl-s rc like(INTEGER_t);

  rc = SCNET_port_listening(port);
  if rc <> SCNET_UNAVAILABLE;
    return (rc = SCNET_LISTENING);
  endif;

  port_l = port;

  exec sql
    SELECT COUNT(*)
      INTO :found
      FROM QSYS2.NETSTAT_INFO
     WHERE TCP_STATE = 'LISTEN'
       AND LOCAL_PORT = :port_l;

  if sqlcode <> 0;
    return false;
  endif;

  return (found > 0);

end-proc;

//==============================================================================
// SCQRY_jobs_on_port
//==============================================================================

dcl-proc SCQRY_jobs_on_port export;
  dcl-pi *n like(INTEGER_t);
    port like(INTEGER_t) const;
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s port_l int(10);
  dcl-s job_name varchar(28);

  clear jobs;
  port_l = port;

  // REMOTE_PORT = 0 is the listening socket: a listener has no peer, an
  // established connection does. Without this qualifier every client connected
  // to the port comes back as though it were the service - and SCEXEC_jobs
  // feeds this straight to ENDJOB on stop and kill, so over-matching here ends
  // other people's jobs. Upstream filters the same way (QueryUtils in sc.jar:
  // "where REMOTE_PORT = 0 and LOCAL_PORT = ?").
  exec sql
    DECLARE c_port CURSOR FOR
    SELECT DISTINCT JOB_NAME
      FROM QSYS2.NETSTAT_JOB_INFO
     WHERE LOCAL_PORT = :port_l
       AND REMOTE_PORT = 0
       AND JOB_NAME IS NOT NULL
    -- ORDER BY, and it earns its place twice. It makes the list the caller
    -- gets deterministic rather than whatever order the service happened to
    -- return; and because the fetch loop stops at SCQRY_MAX_JOBS, it also
    -- decides WHICH jobs survive when more match than the array holds - the
    -- lowest-numbered, which are the oldest, rather than an arbitrary subset.
    -- Sorting after the truncation could not have fixed that second part.
     ORDER BY JOB_NAME;

  exec sql OPEN c_port;
  if sqlcode <> 0;
    return 0;
  endif;

  dow true;
    exec sql FETCH c_port INTO :job_name;
    if sqlcode <> 0 or jobs.count >= SCQRY_MAX_JOBS;
      leave;
    endif;
    jobs.count += 1;
    jobs.name(jobs.count) = job_name;
  enddo;

  exec sql CLOSE c_port;

  return jobs.count;

end-proc;

//==============================================================================
// SCQRY_jobs_by_name
//   Filtering happens inside ACTIVE_JOB_INFO, not here
//==============================================================================

dcl-proc SCQRY_jobs_by_name export;
  dcl-pi *n like(INTEGER_t);
    job_name  like(SCQRY_JOBNAME_t) const;
    subsystem like(SCQRY_JOBNAME_t) const;
    jobs      likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s name_l varchar(28);
  dcl-s sbs_l  varchar(28);
  dcl-s found  varchar(28);
  dcl-s rc     like(INTEGER_t);

  clear jobs;
  name_l = %trim(job_name);
  sbs_l  = %trim(subsystem);

  // QUSLJOB filters by job name itself and is far cheaper than the SQL
  // service. It cannot filter by subsystem in this format, so the
  // subsystem-qualified form still goes through SQL below.
  if %len(sbs_l) = 0;
    rc = SCJOB_by_name(name_l: jobs);
    if rc <> SCJOB_UNAVAILABLE;
      return rc;
    endif;
    clear jobs;
  endif;

  if %len(sbs_l) > 0;
    exec sql
      DECLARE c_jobsbs CURSOR FOR
      SELECT JOB_NAME
        FROM TABLE(QSYS2.ACTIVE_JOB_INFO(
                     JOB_NAME_FILTER        => :name_l,
                     SUBSYSTEM_LIST_FILTER  => :sbs_l))
     ORDER BY JOB_NAME;

    exec sql OPEN c_jobsbs;
    if sqlcode <> 0;
      return 0;
    endif;

    dow true;
      exec sql FETCH c_jobsbs INTO :found;
      if sqlcode <> 0 or jobs.count >= SCQRY_MAX_JOBS;
        leave;
      endif;
      jobs.count += 1;
      jobs.name(jobs.count) = found;
    enddo;

    exec sql CLOSE c_jobsbs;
    return jobs.count;
  endif;

  exec sql
    DECLARE c_job CURSOR FOR
    SELECT JOB_NAME
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO(JOB_NAME_FILTER => :name_l))
     ORDER BY JOB_NAME;

  exec sql OPEN c_job;
  if sqlcode <> 0;
    return 0;
  endif;

  dow true;
    exec sql FETCH c_job INTO :found;
    if sqlcode <> 0 or jobs.count >= SCQRY_MAX_JOBS;
      leave;
    endif;
    jobs.count += 1;
    jobs.name(jobs.count) = found;
  enddo;

  exec sql CLOSE c_job;

  return jobs.count;

end-proc;

//==============================================================================
// SCQRY_jobs_by_pgm
//==============================================================================

dcl-proc SCQRY_jobs_by_pgm export;
  dcl-pi *n like(INTEGER_t);
    program like(SCQRY_JOBNAME_t) const;
    jobs    likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s pgm_l varchar(28);
  dcl-s found varchar(28);

  clear jobs;
  pgm_l = %trim(program);

  // FUNCTION_TYPE 'PGM' means the main thread is running that program, which
  // is what upstream's PGM- criterion means.
  //
  // The comparison is case-insensitive because upstream's is (upper(FUNCTION)
  // in QueryUtils), and live FUNCTION values are genuinely mixed - 'sshd' and
  // 'jFromPASE' sit alongside 'QTOCL2TP'. Comparing raw made PGM-SSHD miss a
  // running sshd, reporting a live service as stopped with no error.
  exec sql
    DECLARE c_pgm CURSOR FOR
    SELECT JOB_NAME
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) X
     WHERE X.FUNCTION_TYPE = 'PGM'
       AND UPPER(TRIM(X.FUNCTION)) = UPPER(:pgm_l)
     ORDER BY JOB_NAME;

  exec sql OPEN c_pgm;
  if sqlcode <> 0;
    return 0;
  endif;

  dow true;
    exec sql FETCH c_pgm INTO :found;
    if sqlcode <> 0 or jobs.count >= SCQRY_MAX_JOBS;
      leave;
    endif;
    jobs.count += 1;
    jobs.name(jobs.count) = found;
  enddo;

  exec sql CLOSE c_pgm;

  return jobs.count;

end-proc;

//==============================================================================
// SCQRY_job_start_time
//==============================================================================

// JOB_USER_FILTER defaults to the CURRENT USER, not to every job. A service
// almost never runs under the profile asking about it - QTCP, QPGMR and
// QSECOFR are all common - so without '*ALL' the lookup silently finds
// nothing and the service looks like it has no start time.
dcl-proc SCQRY_job_start_time export;
  dcl-pi *n like(SCQRY_TIME_t);
    job_name like(SCQRY_JOBNAME_t) const;
  end-pi;

  dcl-s name_l varchar(28);
  dcl-s result varchar(19) inz('');

  name_l = %trim(job_name);

  // No JOB_STATUS_FILTER, matching upstream: a job that has ended still has a
  // start time, and narrowing to *ACTIVE meant asking about one returned
  // nothing. Inert today, because the only caller passes jobs it has just
  // found active - but it was a departure with no reason behind it.
  //
  // The format string is deliberately NOT upstream's 'yyyy-MM-dd-HH24.mi.ss'.
  // Upstream re-formats the value before printing it, so its displayed form is
  // 'YYYY-MM-DD HH24:MI:SS' - matching its SQL here would make the output less
  // like upstream's, not more.
  exec sql
    SELECT VARCHAR_FORMAT(JOB_ENTERED_SYSTEM_TIME, 'YYYY-MM-DD HH24:MI:SS')
      INTO :result
      FROM TABLE(QSYS2.JOB_INFO(JOB_USER_FILTER => '*ALL')) X
     WHERE X.JOB_NAME = :name_l
     FETCH FIRST 1 ROWS ONLY;

  if sqlcode <> 0;
    return '';
  endif;

  return result;

end-proc;

//==============================================================================
// SCQRY_job_perf
//
// Upstream needs an optional Python 3 and ibm_db install for this, because
// db2util handled these columns badly. Embedded SQL reads them directly, so
// the dependency goes away.
//==============================================================================

dcl-proc SCQRY_job_perf export;
  dcl-pi *n like(BOOLEAN_t);
    job_name like(SCQRY_JOBNAME_t) const;
    perf     likeds(SCQRY_PERF_t);
  end-pi;

  dcl-s name_l   varchar(28);
  dcl-s simple_l varchar(28);
  dcl-s i        like(INTEGER_t);

  clear perf;
  name_l = %trim(job_name);

  // ACTIVE_JOB_INFO's JOB_NAME_FILTER takes the simple job name. Passing '*ALL'
  // and filtering in the WHERE makes the table function enumerate every active
  // job on the system to answer one lookup. Upstream filters; so does this.
  simple_l = name_l;
  for i = %len(name_l) downto 1;
    if %subst(name_l: i: 1) = '/';
      simple_l = %subst(name_l: i + 1);
      leave;
    endif;
  endfor;

  // DETAILED_INFO => 'ALL' is REQUIRED, not an optimisation to trim later:
  // JOB_ACTIVE_TIME returns NULL without it. The COALESCE then turns that
  // into an empty string, so the field arrives blank with no error anywhere -
  // which is how it shipped blank the first time. Every other column here is
  // in the base set and reads correctly without it, so nothing else in this
  // query would have shown the omission.
  //
  // JOB_ACTIVE_TIME is rendered in SQL rather than in RPG. The database's own
  // default rendering is '2026-09-08-08.14.47' and upstream prints
  // '2026-09-08 08:14:47' - a space and colons. Passing the raw form through
  // is the obvious mistake here, because both look like timestamps.
  exec sql
    SELECT COALESCE(X.ELAPSED_TIME, 0),
           COALESCE(X.THREAD_COUNT, 0),
           COALESCE(X.TEMPORARY_STORAGE, 0),
           COALESCE(X.ELAPSED_CPU_PERCENTAGE, 0),
           COALESCE(X.ELAPSED_TOTAL_DISK_IO_COUNT, 0),
           COALESCE(X.AUTHORIZATION_NAME, ''),
           COALESCE(X.JOB_STATUS, ''),
           COALESCE(X.FUNCTION, ''),
           COALESCE(X.TOTAL_DISK_IO_COUNT, 0),
           COALESCE(VARCHAR_FORMAT(X.JOB_ACTIVE_TIME,
                                   'YYYY-MM-DD HH24:MI:SS'), '')
      INTO :perf.elapsed_time, :perf.thread_count, :perf.temp_storage,
           :perf.cpu_percentage, :perf.disk_io_count,
           :perf.current_user, :perf.job_status, :perf.job_function,
           :perf.total_disk_io, :perf.active_since
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO(JOB_NAME_FILTER  => :simple_l,
                                       DETAILED_INFO    => 'ALL')) X
     WHERE X.JOB_NAME = :name_l
     FETCH FIRST 1 ROWS ONLY;

  if sqlcode <> 0;
    return false;
  endif;

  perf.job_start = SCQRY_job_start_time(job_name);
  perf.found = true;

  return true;

end-proc;

//==============================================================================
// SCQRY_jvm_info
//==============================================================================

dcl-proc SCQRY_jvm_info export;
  dcl-pi *n like(BOOLEAN_t);
    job_name like(SCQRY_JOBNAME_t) const;
    jvm      likeds(SCQRY_JVM_t);
  end-pi;

  dcl-s name_l varchar(28);

  clear jvm;
  name_l = %trim(job_name);

  exec sql
    SELECT COALESCE(CURRENT_HEAP_SIZE, 0),
           COALESCE(MAX_HEAP_SIZE, 0),
           COALESCE(IN_USE_HEAP_SIZE, 0),
           COALESCE(GC_CYCLE_NUMBER, 0),
           COALESCE(TOTAL_GC_TIME, 0),
           COALESCE(JIT_MEMORY_SIZE, 0),
           COALESCE(SHARED_CLASS_SIZE, 0),
           COALESCE(MALLOC_MEMORY_SIZE, 0)
      INTO :jvm.heap_size, :jvm.max_heap_size,
           :jvm.in_use_heap, :jvm.gc_cycles,
           :jvm.gc_total_time, :jvm.jit_memory,
           :jvm.shared_class, :jvm.malloc_memory
      FROM QSYS2.JVM_INFO
     WHERE JOB_NAME = :name_l
     FETCH FIRST 1 ROWS ONLY;

  if sqlcode <> 0;
    return false;
  endif;

  jvm.found = true;
  return true;

end-proc;

//==============================================================================
// SCQRY_splfs_for_job
//==============================================================================

dcl-proc SCQRY_splfs_for_job export;
  dcl-pi *n like(INTEGER_t);
    job_name like(SCQRY_JOBNAME_t) const;
    splfs    likeds(SCQRY_SPLFS_t);
  end-pi;

  dcl-s name_l varchar(28);
  dcl-s splf   varchar(10);
  dcl-s number int(10);

  clear splfs;
  name_l = %trim(job_name);

  exec sql
    DECLARE c_splf CURSOR FOR
    SELECT SPOOLED_FILE_NAME, FILE_NUMBER
      FROM QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC
     WHERE JOB_NAME = :name_l
     ORDER BY FILE_NUMBER;

  exec sql OPEN c_splf;
  if sqlcode <> 0;
    return 0;
  endif;

  dow true;
    exec sql FETCH c_splf INTO :splf, :number;
    if sqlcode <> 0 or splfs.count >= SCQRY_MAX_SPLF;
      leave;
    endif;
    splfs.count += 1;
    splfs.name(splfs.count) = splf;
    splfs.file_number(splfs.count) = number;
  enddo;

  exec sql CLOSE c_splf;

  return splfs.count;

end-proc;

//==============================================================================
// SCQRY_job_attrs
//==============================================================================

// -1 is how QUSRJOBI spells *NOMAX. Measured on all four limit fields rather
// than inferred from the one that happened to be *NOMAX by default: setting
// DFTWAIT, CPUTIME and MAXTMPSTG to *NOMAX turned every one of them to -1,
// and ACTIVE_JOB_INFO returns NULL for exactly those three, which is the same
// reading arrived at down a different path.
dcl-proc limit_text;
  dcl-pi *n like(SCQRY_ATTRVAL_t);
    value like(INTEGER_t) const;
  end-pi;

  if value = -1;
    return '*NOMAX';
  endif;

  return %char(value);

end-proc;

// SCQRY_JOBNAME_t is 'number/user/name'; QUSRJOBI wants name(10) user(10)
// number(6) with no separators. Anything that does not split into three
// parts, or whose parts do not fit, returns blanks - the caller then gets a
// false rather than a lookup against a name silently cut to fit.
dcl-proc qualified_name;
  dcl-pi *n char(26);
    job_name like(SCQRY_JOBNAME_t) const;
  end-pi;

  dcl-s work varchar(28);
  dcl-s p1   like(INTEGER_t);
  dcl-s p2   like(INTEGER_t);
  dcl-s num  varchar(28);
  dcl-s usr  varchar(28);
  dcl-s nam  varchar(28);
  // Not `out` - that is the OUT opcode, and the compiler's complaint for it
  // ("Factor 1 operand is not valid") names neither the word nor the reason.
  // docs/testing-notes.md records it; this is the second time it has bitten.
  dcl-s packed char(26);

  work = %trim(job_name);

  p1 = %scan('/': work);
  if p1 = 0;
    return *blanks;
  endif;

  p2 = %scan('/': work: p1 + 1);
  if p2 = 0;
    return *blanks;
  endif;

  num = %subst(work: 1: p1 - 1);
  usr = %subst(work: p1 + 1: p2 - p1 - 1);
  nam = %subst(work: p2 + 1);

  if %len(nam) > 10 or %len(usr) > 10 or %len(num) > 6
     or %len(nam) = 0 or %len(usr) = 0 or %len(num) = 0;
    return *blanks;
  endif;

  packed = *blanks;
  %subst(packed:  1: 10) = nam;
  %subst(packed: 11: 10) = usr;
  %subst(packed: 21:  6) = num;

  return packed;

end-proc;

dcl-proc SCQRY_job_attrs export;
  dcl-pi *n like(BOOLEAN_t);
    job_name like(SCQRY_JOBNAME_t) const;
    attrs    likeds(SCQRY_ATTRS_t);
  end-pi;

  dcl-s  rcv   char(144);
  dcl-s  pJobi pointer;
  dcl-ds jobi  likeds(JOBI0150_t) based(pJobi);
  dcl-s  qual  char(26);
  dcl-ds errc  likeds(QUSRJOBI_ERR_t);

  // Cleared on entry, not on the way out: a caller that ignores the return
  // value and reads the fields must see zeros rather than whatever the
  // structure held before, and likeds() does not inherit the template's inz.
  clear attrs;

  qual = qualified_name(job_name);
  if qual = *blanks;
    return false;
  endif;

  clear rcv;
  clear errc;
  errc.bytes_provided = %size(errc);

  QUSRJOBI(rcv: %size(rcv): 'JOBI0150': qual: *blanks: errc);

  // A non-blank message id is how the API reports a job it cannot find. With
  // bytes_provided set it returns the id rather than signalling an escape
  // message, so there is nothing here to monitor for.
  if errc.msgid <> *blanks;
    return false;
  endif;

  pJobi = %addr(rcv);

  attrs.run_priority      = jobi.run_priority;
  attrs.time_slice        = jobi.time_slice;
  attrs.purge             = %trimr(jobi.purge);
  attrs.default_wait      = limit_text(jobi.default_wait);
  attrs.max_cpu_time      = limit_text(jobi.max_cpu_time);
  attrs.cpu_time_used     = jobi.cpu_used_total;
  attrs.max_temp_storage  = limit_text(jobi.max_temp_mb);
  attrs.temp_storage_used = jobi.temp_used_mb;
  attrs.peak_temp_storage = jobi.peak_temp_mb;
  attrs.max_threads       = limit_text(jobi.max_threads);
  attrs.thread_count      = jobi.thread_count;

  return true;

end-proc;

//==============================================================================
// SCQRY_job_sample
//==============================================================================

dcl-proc SCQRY_job_sample export;
  dcl-pi *n like(BOOLEAN_t);
    job_name like(SCQRY_JOBNAME_t) const;
    seconds  like(SCQRY_SECS_t) const;
    perf     likeds(SCQRY_PERF_t);
  end-pi;

  dcl-pr c_sleep uns(10) extproc('sleep');
    secs uns(10) value;
  end-pr;

  // usleep takes microseconds and is only ever handed the FRACTIONAL part
  // here, so it is never given a value at or above one million - which is
  // where its behaviour stops being portable.
  dcl-pr c_usleep int(10) extproc('usleep');
    micros uns(10) value;
  end-pr;

  dcl-s name_l   varchar(28);
  dcl-s simple_l varchar(28);
  dcl-s i        like(INTEGER_t);
  dcl-s hit      like(INTEGER_t);
  dcl-s whole_s  like(INTEGER_t);
  dcl-s frac_us  like(INTEGER_t);
  dcl-s window   like(SCQRY_SECS_t);
  dcl-s t0       timestamp;
  dcl-s t1       timestamp;

  clear perf;
  name_l = %trim(job_name);

  simple_l = name_l;
  for i = %len(name_l) downto 1;
    if %subst(name_l: i: 1) = '/';
      simple_l = %subst(name_l: i + 1);
      leave;
    endif;
  endfor;

  // Zero is a legitimate request and means "do not wait" - measured against
  // upstream, which accepts --sampletime=0 and reports a window of the
  // overhead alone. A NEGATIVE value is clamped to the same thing rather than
  // refused; docs/parity.md records what upstream does with one instead.
  window = seconds;
  if window < 0;
    window = 0;
  endif;

  whole_s = %int(window);
  frac_us = %int((window - whole_s) * 1000000);

  // RESET_STATISTICS zeroes the ELAPSED_ counters for this connection, so
  // what SCQRY_job_perf reads afterwards describes the window rather than
  // whatever period they had been accumulating over. Without it those
  // columns are a lifetime average, which for a service that has been up for
  // weeks is not a measurement of anything anybody asked about.
  exec sql
    SELECT COUNT(*)
      INTO :hit
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO(RESET_STATISTICS => 'YES',
                                       JOB_NAME_FILTER  => :simple_l)) X
     WHERE X.JOB_NAME = :name_l;

  if sqlcode <> 0 or hit = 0;
    return false;
  endif;

  t0 = %timestamp();
  if whole_s > 0;
    c_sleep(whole_s);
  endif;
  if frac_us > 0;
    c_usleep(frac_us);
  endif;
  t1 = %timestamp();

  if not SCQRY_job_perf(job_name: perf);
    return false;
  endif;

  // The window ACTUALLY measured, not the one asked for. They differ by the
  // scheduling slop either side of the sleep, and reporting the requested
  // figure would make the number a restatement of the input rather than an
  // observation.
  // RPG's *MSECONDS duration code is MICROseconds, not milliseconds - there
  // is no millisecond code. Dividing by 1000 here gave a figure 1000x too
  // large, and it was caught only because the suite asserts a RANGE: a
  // 2-second window reported 2030.076, which a "populated and greater than
  // zero" assertion would have accepted without complaint.
  //
  // %dec first, so the division is decimal. Integer / integer would truncate
  // the window to a whole second and leave three decimals of zeros looking
  // like a measurement.
  perf.sample_seconds = %dec(%diff(t1: t0: *MSECONDS): 15: 3) / 1000000;

  return true;

end-proc;
