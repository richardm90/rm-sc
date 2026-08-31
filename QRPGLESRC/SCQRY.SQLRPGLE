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

  exec sql
    DECLARE c_port CURSOR FOR
    SELECT DISTINCT JOB_NAME
      FROM QSYS2.NETSTAT_JOB_INFO
     WHERE LOCAL_PORT = :port_l
       AND JOB_NAME IS NOT NULL;

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
                     SUBSYSTEM_LIST_FILTER  => :sbs_l));

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
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO(JOB_NAME_FILTER => :name_l));

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
  // is what upstream's PGM- criterion means
  exec sql
    DECLARE c_pgm CURSOR FOR
    SELECT JOB_NAME
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) X
     WHERE X.FUNCTION_TYPE = 'PGM'
       AND TRIM(X.FUNCTION) = :pgm_l;

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

  exec sql
    SELECT VARCHAR_FORMAT(JOB_ENTERED_SYSTEM_TIME, 'YYYY-MM-DD HH24:MI:SS')
      INTO :result
      FROM TABLE(QSYS2.JOB_INFO(JOB_STATUS_FILTER => '*ACTIVE',
                                JOB_USER_FILTER   => '*ALL')) X
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

  dcl-s name_l varchar(28);

  clear perf;
  name_l = %trim(job_name);

  exec sql
    SELECT COALESCE(X.ELAPSED_TIME, 0),
           COALESCE(X.THREAD_COUNT, 0),
           COALESCE(X.TEMPORARY_STORAGE, 0),
           COALESCE(X.ELAPSED_CPU_PERCENTAGE, 0),
           COALESCE(X.ELAPSED_TOTAL_DISK_IO_COUNT, 0)
      INTO :perf.elapsed_time, :perf.thread_count, :perf.temp_storage,
           :perf.cpu_percentage, :perf.disk_io_count
      FROM TABLE(QSYS2.ACTIVE_JOB_INFO(JOB_NAME_FILTER => '*ALL')) X
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
           COALESCE(MAXIMUM_HEAP_SIZE, 0),
           COALESCE(IN_USE_HEAP_SIZE, 0),
           COALESCE(GARBAGE_COLLECTIONS, 0)
      INTO :jvm.heap_size, :jvm.max_heap_size,
           :jvm.in_use_heap, :jvm.gc_cycles
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
