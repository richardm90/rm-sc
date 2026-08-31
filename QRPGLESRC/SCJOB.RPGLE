**free

//==============================================================================
// SCJOB      - Active job lookup via QUSLJOB
//
// Replaces QSYS2.ACTIVE_JOB_INFO for the job-name check, which after the port
// check was replaced is the largest remaining cost - about 177ms per call, and
// check makes one per job criterion.
//
// QUSLJOB filters by job name itself and returns a 56-byte entry per job, so
// it does the same work without materialising a wide SQL result set.
//
// Only the bare job name form is handled, because JOBL0100 cannot filter by
// subsystem. A subsystem-qualified name, or a PGM- criterion, needs JOBL0200
// and its keyed fields: 1906 subsystem description (qualified), 601 function
// name, 602 function type. That is variable-length keyed data rather than a
// fixed record, so for now the caller falls back to SQL for those. On this
// system that is six definitions, all in the system group and none on the
// default check path, plus one PGM- that only_if_executable filters out.
//
// 30/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Active job lookup via QUSLJOB');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCJOB_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'SCYAML_D.rpgleinc'
/include 'include/RMSPACE_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

// QUSLJOB is a program, not a service program procedure
dcl-pr QUSLJOB extpgm('QUSLJOB');
  usrspc   char(20)  const;
  format   char(8)   const;
  jobname  char(26)  const;
  status   char(10)  const;
  errcode  char(272) options(*varsize);
end-pr;

dcl-c SPACE_LIB  const('QTEMP');
dcl-c SPACE_NAME const('SCJOBLST');

dcl-s g_space_ready like(BOOLEAN_t) inz(false);
dcl-s g_error      like(SCYAML_ERROR_t) inz('');

//==============================================================================
// SCJOB_by_name
//==============================================================================

dcl-proc SCJOB_by_name export;
  dcl-pi *n like(INTEGER_t);
    job_name like(SCQRY_JOBNAME_t) const;
    jobs     likeds(SCQRY_JOBS_t);
  end-pi;

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

  // JOBL0100, per QSYSINC/QRPGLESRC(QUSLJOB)
  dcl-ds ent qualified based(p_ent);
    job_name char(10) pos(1);
    user     char(10) pos(11);
    number   char(6)  pos(21);
  end-ds;

  dcl-s p_space  pointer;
  dcl-s p_ent    pointer;
  dcl-s i        like(INTEGER_t);
  dcl-s qualname char(20);
  dcl-s nm       char(10) inz(SPACE_NAME);
  dcl-s lb       char(10) inz(SPACE_LIB);
  dcl-s wanted   char(26);
  dcl-s name10   char(10);

  clear jobs;
  g_error = '';

  // A name longer than ten characters cannot be a job name, so nothing can
  // match it. Saying so beats letting the API truncate and match something
  // else.
  if %len(%trim(job_name)) > 10;
    return 0;
  endif;

  if not g_space_ready;
    SPACE_create(SPACE_LIB: SPACE_NAME: '': 65536: x'00': '*ALL':
                 'RMSC job list': '*YES');
    g_space_ready = true;
  endif;

  // Qualified job name: name(10) + user(10) + number(6)
  name10  = STRING_upper(%trim(job_name));
  wanted  = name10 + '*ALL      ' + '*ALL  ';

  clear errcode;
  errcode.provided = 272;

  // Both halves padded to ten. Concatenating bare constants would give the
  // API a name and library that run into each other - the mistake that cost
  // an afternoon in SCNET.
  qualname = nm + lb;

  QUSLJOB(qualname: 'JOBL0100': wanted: '*ACTIVE': errcode);

  if errcode.available > 0;
    g_error = 'QUSLJOB: ' + errcode.excpid;
    return SCJOB_UNAVAILABLE;
  endif;

  p_space = SPACE_retrieve_pointer(SPACE_LIB: SPACE_NAME);
  if p_space = *null;
    g_error = 'Could not address the user space';
    return SCJOB_UNAVAILABLE;
  endif;

  // 'C' is complete. A partial list would mean answering from incomplete
  // data, which for a liveness check means possibly reporting a service down.
  if hdr.status <> 'C';
    g_error = 'List status ' + hdr.status;
    return SCJOB_UNAVAILABLE;
  endif;

  for i = 1 to hdr.entries;
    if jobs.count >= SCQRY_MAX_JOBS;
      leave;
    endif;
    p_ent = p_space + hdr.off_list + ((i - 1) * hdr.entry_size);
    jobs.count += 1;
    // number/user/name, the same shape ACTIVE_JOB_INFO returns, so callers
    // cannot tell which route produced the answer
    jobs.name(jobs.count) = %trim(ent.number) + '/' +
                            %trim(ent.user) + '/' +
                            %trim(ent.job_name);
  endfor;

  return jobs.count;

end-proc;

//==============================================================================
// SCJOB_last_error
//==============================================================================

dcl-proc SCJOB_last_error export;
  dcl-pi *n like(SCYAML_ERROR_t) end-pi;

  return g_error;

end-proc;
