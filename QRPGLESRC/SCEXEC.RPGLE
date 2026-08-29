**free

//==============================================================================
// SCEXEC     - Service operations
//
// Status determination and the operations built on it.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service operations');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCEXEC_D.rpgleinc'
/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCLAUNCH_D.rpgleinc'
/include 'SCLOG_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-pr delay;
  seconds like(INTEGER_t) const;
end-pr;

dcl-pr ignored like(BOOLEAN_t);
  def           likeds(SCDEF_t) const;
  ignore_groups like(SCDEF_NAME_t) const;
end-pr;

dcl-pr stop_one like(BOOLEAN_t);
  def  likeds(SCDEF_t) const;
  kill like(BOOLEAN_t) const;
  err  like(SCEXEC_ERR_t);
end-pr;

//==============================================================================
// SCEXEC_criterion_alive
//==============================================================================

dcl-proc SCEXEC_criterion_alive export;
  dcl-pi *n like(BOOLEAN_t);
    criterion likeds(SCDEF_CRITERION_t) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  select;
    when criterion.kind = SCDEF_CHECK_PORT;
      return SCQRY_port_listening(criterion.port);

    when criterion.kind = SCDEF_CHECK_JOB;
      return (SCQRY_jobs_by_name(criterion.job_name:
                                 criterion.subsystem: jobs) > 0);

    when criterion.kind = SCDEF_CHECK_PGM;
      return (SCQRY_jobs_by_pgm(criterion.program: jobs) > 0);

    other;
      return false;
  endsl;

end-proc;

//==============================================================================
// SCEXEC_status
//==============================================================================

dcl-proc SCEXEC_status export;
  dcl-pi *n like(SCOUT_STATUS_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s i     like(INTEGER_t);
  dcl-s alive like(INTEGER_t) inz(0);

  // A definition with no criteria cannot be checked, so it cannot be running
  if def.criteria_count = 0;
    return SCOUT_NOT_RUNNING;
  endif;

  for i = 1 to def.criteria_count;
    if SCEXEC_criterion_alive(def.criteria(i));
      alive += 1;
    endif;
  endfor;

  select;
    when alive = 0;
      return SCOUT_NOT_RUNNING;
    when alive = def.criteria_count;
      return SCOUT_RUNNING;
    other;
      return SCOUT_PARTIAL;
  endsl;

end-proc;

//==============================================================================
// SCEXEC_jobs
//   Every job satisfying any of the service's criteria
//==============================================================================

dcl-proc SCEXEC_jobs export;
  dcl-pi *n like(INTEGER_t);
    def  likeds(SCDEF_t) const;
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-ds found likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);
  dcl-s k    like(INTEGER_t);
  dcl-s seen like(BOOLEAN_t);

  clear jobs;

  for i = 1 to def.criteria_count;
    clear found;

    select;
      when def.criteria(i).kind = SCDEF_CHECK_PORT;
        SCQRY_jobs_on_port(def.criteria(i).port: found);
      when def.criteria(i).kind = SCDEF_CHECK_JOB;
        SCQRY_jobs_by_name(def.criteria(i).job_name:
                           def.criteria(i).subsystem: found);
      when def.criteria(i).kind = SCDEF_CHECK_PGM;
        SCQRY_jobs_by_pgm(def.criteria(i).program: found);
    endsl;

    // A job satisfying two criteria is still one job
    for j = 1 to found.count;
      seen = false;
      for k = 1 to jobs.count;
        if jobs.name(k) = found.name(j);
          seen = true;
          leave;
        endif;
      endfor;
      if not seen and jobs.count < SCQRY_MAX_JOBS;
        jobs.count += 1;
        jobs.name(jobs.count) = found.name(j);
      endif;
    endfor;
  endfor;

  return jobs.count;

end-proc;

//==============================================================================
// SCEXEC_check
//==============================================================================

dcl-proc SCEXEC_check export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  SCOUT_writeln(SCOUT_check_row(SCEXEC_status(def):
                                def.short_name: def.friendly));

end-proc;

//==============================================================================
// ignored
//   Is this service in a group the caller asked to skip?
//==============================================================================

dcl-proc ignored;
  dcl-pi *n like(BOOLEAN_t);
    def           likeds(SCDEF_t) const;
    ignore_groups like(SCDEF_NAME_t) const;
  end-pi;

  dcl-s rest  like(SCDEF_NAME_t);
  dcl-s part  like(SCDEF_NAME_t);
  dcl-s comma like(INTEGER_t);

  rest = STRING_lower(%trim(ignore_groups));

  dow %len(rest) > 0;
    comma = %scan(',': rest);
    if comma = 0;
      part = %trim(rest);
      rest = '';
    else;
      part = %trim(%subst(rest: 1: comma - 1));
      rest = %trim(%subst(rest: comma + 1));
    endif;

    if %len(part) > 0 and SCDEF_in_group(def: part);
      return true;
    endif;
  enddo;

  return false;

end-proc;

//==============================================================================
// SCEXEC_check_all
//==============================================================================

dcl-proc SCEXEC_check_all export;
  dcl-pi *n;
    coll          likeds(SCCOLL_t);
    ignore_groups like(SCDEF_NAME_t) const;
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  for i = 1 to SCCOLL_count(coll);
    if SCCOLL_get(coll: i: def) and not ignored(def: ignore_groups);
      SCEXEC_check(def);
    endif;
  endfor;

  // Upstream ends the listing with a blank line
  SCOUT_writeln('');

end-proc;

//==============================================================================
// SCEXEC_list
//==============================================================================

dcl-proc SCEXEC_list export;
  dcl-pi *n;
    coll          likeds(SCCOLL_t);
    ignore_groups like(SCDEF_NAME_t) const;
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  for i = 1 to SCCOLL_count(coll);
    if SCCOLL_get(coll: i: def) and not ignored(def: ignore_groups);
      SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
    endif;
  endfor;

  SCOUT_writeln('');

end-proc;

//==============================================================================
// SCEXEC_groups
//==============================================================================

dcl-proc SCEXEC_groups export;
  dcl-pi *n;
    coll          likeds(SCCOLL_t);
    ignore_groups like(SCDEF_NAME_t) const;
  end-pi;

  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-ds def    likeds(SCDEF_t) inz(*likeds);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);
  dcl-s k    like(INTEGER_t);
  dcl-s seen like(BOOLEAN_t);
  dcl-s swap like(SCDEF_NAME_t);

  // Groups of the services the caller can see. A group that exists only on
  // ignored services is not something they asked about.
  for i = 1 to SCCOLL_count(coll);
    if not SCCOLL_get(coll: i: def) or ignored(def: ignore_groups);
      iter;
    endif;

    for j = 1 to def.group_count;
      seen = false;
      for k = 1 to groups.count;
        if groups.name(k) = def.groups(j);
          seen = true;
          leave;
        endif;
      endfor;
      if not seen and groups.count < SCCOLL_MAX_GROUPS;
        groups.count += 1;
        groups.name(groups.count) = def.groups(j);
      endif;
    endfor;
  endfor;

  // 'system' is built in and is listed even when its members are filtered
  // out. 'all' is built in too but upstream does not list it.
  seen = false;
  for k = 1 to groups.count;
    if groups.name(k) = 'system';
      seen = true;
      leave;
    endif;
  endfor;
  if not seen and groups.count < SCCOLL_MAX_GROUPS;
    groups.count += 1;
    groups.name(groups.count) = 'system';
  endif;

  // Alphabetical, as upstream lists them
  for i = 1 to groups.count - 1;
    for j = i + 1 to groups.count;
      if groups.name(j) < groups.name(i);
        swap = groups.name(i);
        groups.name(i) = groups.name(j);
        groups.name(j) = swap;
      endif;
    endfor;
  endfor;

  for i = 1 to groups.count;
    SCOUT_writeln(groups.name(i));
  endfor;

  SCOUT_writeln('');

end-proc;

//==============================================================================
// delay
//==============================================================================

dcl-proc delay;
  dcl-pi *n;
    seconds like(INTEGER_t) const;
  end-pi;

  dcl-ds qerr likeds(QCMD_ERR_t);

  QCMD_exc('DLYJOB DLY(' + %char(seconds) + ')': qerr);

end-proc;

//==============================================================================
// SCEXEC_start
//   Dependencies first, then poll until alive
//==============================================================================

dcl-proc SCEXEC_start export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
    err  like(SCEXEC_ERR_t);
  end-pi;

  dcl-ds order likeds(SCCOLL_ORDER_t) inz(*likeds);
  dcl-ds def   likeds(SCDEF_t) inz(*likeds);
  dcl-s i       like(INTEGER_t);
  dcl-s waited  like(INTEGER_t);
  dcl-s lerr    like(SCLAUNCH_ERR_t);

  err = '';

  if not SCCOLL_start_order(coll: name: order);
    err = order.err;
    return false;
  endif;

  for i = 1 to order.count;
    if not SCCOLL_find(coll: order.name(i): def);
      err = 'Unknown service ' + %trim(order.name(i));
      return false;
    endif;

    // Already up, including a dependency started by an earlier request
    if SCEXEC_status(def) = SCOUT_RUNNING;
      iter;
    endif;

    SCLOG_ensure_dir(def);

    if not SCLAUNCH_start(def: SCLOG_path(def): lerr);
      err = 'Could not start ' + %trim(def.short_name) + ': ' + %trim(lerr);
      return false;
    endif;

    // Poll rather than assume. A start command returning zero says the
    // command was launched, not that the service came up.
    waited = 0;
    dow waited < def.startup_wait;
      delay(SCEXEC_START_POLL);
      waited += SCEXEC_START_POLL;
      if SCEXEC_status(def) = SCOUT_RUNNING;
        leave;
      endif;
    enddo;

    if SCEXEC_status(def) <> SCOUT_RUNNING;
      err = %trim(def.short_name) + ' did not start within ' +
            %char(def.startup_wait) + 's';
      return false;
    endif;
  endfor;

  return true;

end-proc;

//==============================================================================
// SCEXEC_stop
//   Dependants first, then the service itself
//==============================================================================

dcl-proc SCEXEC_stop export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
    kill like(BOOLEAN_t) const;
    err  like(SCEXEC_ERR_t);
  end-pi;

  dcl-ds def   likeds(SCDEF_t) inz(*likeds);
  dcl-ds other likeds(SCDEF_t) inz(*likeds);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);
  dcl-s want like(SCDEF_NAME_t);

  err = '';
  want = STRING_lower(%trim(name));

  if not SCCOLL_find(coll: want: def);
    err = 'Unknown service ' + %trim(want);
    return false;
  endif;

  // Anything depending on this must go down first, or it is left running
  // against a service that has gone away.
  for i = 1 to SCCOLL_count(coll);
    if not SCCOLL_get(coll: i: other);
      iter;
    endif;
    for j = 1 to other.dep_count;
      if other.deps(j) = want
         and SCEXEC_status(other) <> SCOUT_NOT_RUNNING;
        if not stop_one(other: kill: err);
          return false;
        endif;
        leave;
      endif;
    endfor;
  endfor;

  return stop_one(def: kill: err);

end-proc;

//==============================================================================
// stop_one
//   stop_cmd if there is one, else ENDJOB, escalating if it does not go
//==============================================================================

dcl-proc stop_one;
  dcl-pi *n like(BOOLEAN_t);
    def  likeds(SCDEF_t) const;
    kill like(BOOLEAN_t) const;
    err  like(SCEXEC_ERR_t);
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s lerr   like(SCLAUNCH_ERR_t);
  dcl-s waited like(INTEGER_t);
  dcl-s i      like(INTEGER_t);
  dcl-s used_stop_cmd like(BOOLEAN_t) inz(false);

  err = '';

  if SCEXEC_status(def) = SCOUT_NOT_RUNNING;
    return true;
  endif;

  // 'kill' means skip the service's own stop command
  if def.has_stop_cmd and not kill;
    used_stop_cmd = true;
    if not SCLAUNCH_run_stop_cmd(def: SCLOG_path(def): lerr);
      err = 'Stop command failed for ' + %trim(def.short_name) +
            ': ' + %trim(lerr);
      return false;
    endif;
  else;
    SCEXEC_jobs(def: jobs);
    for i = 1 to jobs.count;
      SCLAUNCH_endjob(jobs.name(i): def.stop_wait: kill: lerr);
    endfor;
  endif;

  waited = 0;
  dow waited < def.stop_wait;
    delay(SCEXEC_STOP_POLL);
    waited += SCEXEC_STOP_POLL;
    if SCEXEC_status(def) = SCOUT_NOT_RUNNING;
      return true;
    endif;
  enddo;

  if SCEXEC_status(def) = SCOUT_NOT_RUNNING;
    return true;
  endif;

  // Escalate only where upstream does: a service that supplied its own stop
  // command has said how it wants to be stopped, and overriding that could
  // cut short whatever the command was doing.
  if used_stop_cmd;
    err = %trim(def.short_name) + ' did not stop within ' +
          %char(def.stop_wait) + 's';
    return false;
  endif;

  SCEXEC_jobs(def: jobs);
  for i = 1 to jobs.count;
    SCLAUNCH_endjob(jobs.name(i): 0: true: lerr);
  endfor;

  delay(SCEXEC_STOP_POLL);

  if SCEXEC_status(def) <> SCOUT_NOT_RUNNING;
    err = %trim(def.short_name) + ' did not stop, even immediately';
    return false;
  endif;

  return true;

end-proc;

//==============================================================================
// SCEXEC_restart
//==============================================================================

dcl-proc SCEXEC_restart export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
    err  like(SCEXEC_ERR_t);
  end-pi;

  if not SCEXEC_stop(coll: name: false: err);
    return false;
  endif;

  return SCEXEC_start(coll: name: err);

end-proc;

//==============================================================================
// SCEXEC_info
//==============================================================================

dcl-proc SCEXEC_info export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s line like(SCOUT_LINE_t);
  dcl-s i    like(INTEGER_t);

  SCOUT_writeln('');
  SCOUT_writeln('---------------------------------------------------------------------');
  SCOUT_writeln(%trim(def.short_name) + ' (' + %trim(def.friendly) + ')');
  SCOUT_writeln('');
  SCOUT_writeln('Defined in: ' + %trim(def.defined_at));
  SCOUT_writeln('');
  SCOUT_writeln('Working Directory: ' + %trim(SCDEF_effective_dir(def)));
  SCOUT_writeln('');
  SCOUT_writeln('Startup Command: ' + %trim(def.start_cmd));
  SCOUT_writeln('Startup Wait Time (s): ' + %char(def.startup_wait));
  SCOUT_writeln('');

  if def.has_stop_cmd;
    SCOUT_writeln('Shutdown Command: ' + %trim(def.stop_cmd));
  endif;
  SCOUT_writeln('Shutdown Wait Time (s): ' + %char(def.stop_wait));
  SCOUT_writeln('');

  line = 'Check-alive conditions: ';
  for i = 1 to def.criteria_count;
    if i > 1;
      line += ', ';
    endif;
    select;
      when def.criteria(i).kind = SCDEF_CHECK_PORT;
        line += 'PORT:' + %char(def.criteria(i).port);
      when def.criteria(i).kind = SCDEF_CHECK_PGM;
        line += 'PGM:' + %trim(def.criteria(i).program);
      other;
        if %len(%trim(def.criteria(i).subsystem)) > 0;
          line += 'JOBNAME:' + %trim(def.criteria(i).subsystem) + '/' +
                  %trim(def.criteria(i).job_name);
        else;
          line += 'JOBNAME:' + %trim(def.criteria(i).job_name);
        endif;
    endsl;
  endfor;
  SCOUT_writeln(line);

  if def.batch_mode;
    SCOUT_writeln('Batch Mode: <submitted to batch>');
    SCOUT_writeln('    Batch Job Name: ' + %trim(SCLAUNCH_job_name(def)));
    if %len(%trim(def.sbmjob_opts)) > 0;
      SCOUT_writeln('    SBMJOB options: ' + %trim(def.sbmjob_opts));
    endif;
  endif;

  for i = 1 to def.dep_count;
    SCOUT_writeln('Depends on: ' + %trim(def.deps(i)));
  endfor;

  for i = 1 to def.group_count;
    SCOUT_writeln('Group: ' + %trim(def.groups(i)));
  endfor;

  for i = 1 to def.unknown_count;
    SCOUT_writeln('Unrecognised key (ignored): ' + %trim(def.unknown(i)));
  endfor;

end-proc;

//==============================================================================
// SCEXEC_file
//   The definition file as written
//==============================================================================

dcl-proc SCEXEC_file export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s handle pointer;
  dcl-s line   like(STRING_t);

  handle = IFS_fopen(def.defined_at: IFS_OPEN_TYPE_READ);
  if handle = *null;
    SCOUT_writeln('Cannot read ' + %trim(def.defined_at));
    return;
  endif;

  dow IFS_fgets(handle: line);
    SCOUT_writeln(%trimr(line));
  enddo;

  IFS_fclose(handle);

end-proc;

//==============================================================================
// SCEXEC_jobinfo
//==============================================================================

dcl-proc SCEXEC_jobinfo export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  if SCEXEC_jobs(def: jobs) = 0;
    SCOUT_writeln(%trim(def.short_name) + ': not running');
    return;
  endif;

  for i = 1 to jobs.count;
    SCOUT_writeln(%trim(def.short_name) + ': ' + %trim(jobs.name(i)));
  endfor;

end-proc;

//==============================================================================
// SCEXEC_loginfo
//==============================================================================

dcl-proc SCEXEC_loginfo export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-ds jobs  likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds splfs likeds(SCQRY_SPLFS_t) inz(*likeds);
  dcl-ds stats likeds(IFS_stats_t);
  dcl-s path like(STMF_t);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);

  path = SCLOG_path(def);

  if IFS_open_file(path: IFS_OPEN_TYPE_READ) >= 0;
    stats = IFS_stats(path);
    SCOUT_writeln(%trim(def.short_name) + ': ' + %trim(path) +
                  ' (' + %char(stats.st_size) + ' bytes)');
  else;
    SCOUT_writeln(%trim(def.short_name) + ': <unknown> (try checking in ' +
                  'log directory ' + %trim(SCLOG_dir(def)) + ')');
  endif;

  // A batch service writes to a spooled file rather than, or as well as, the
  // log - so report those too or half the output is invisible.
  SCEXEC_jobs(def: jobs);
  for i = 1 to jobs.count;
    if SCQRY_splfs_for_job(jobs.name(i): splfs) > 0;
      for j = 1 to splfs.count;
        SCOUT_writeln('    spooled file ' + %trim(splfs.name(j)) +
                      ' number ' + %char(splfs.file_number(j)) +
                      ' in ' + %trim(jobs.name(i)));
      endfor;
    endif;
  endfor;

end-proc;

//==============================================================================
// SCEXEC_perfinfo
//==============================================================================

dcl-proc SCEXEC_perfinfo export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds perf likeds(SCQRY_PERF_t) inz(*likeds);
  dcl-ds jvm  likeds(SCQRY_JVM_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  if SCEXEC_jobs(def: jobs) = 0;
    SCOUT_writeln(%trim(def.short_name) + ': not running');
    return;
  endif;

  for i = 1 to jobs.count;
    SCOUT_writeln(%trim(def.short_name) + ': ' + %trim(jobs.name(i)));

    if SCQRY_job_perf(jobs.name(i): perf);
      SCOUT_writeln('    started: ' + %trim(perf.job_start));
      SCOUT_writeln('    threads: ' + %char(perf.thread_count));
      SCOUT_writeln('    temporary storage (MB): ' + %char(perf.temp_storage));
      SCOUT_writeln('    CPU %: ' + %char(perf.cpu_percentage));
      SCOUT_writeln('    disk I/O: ' + %char(perf.disk_io_count));
    endif;

    // Only services that run one, which is why it is not an error to have none
    if SCQRY_jvm_info(jobs.name(i): jvm);
      SCOUT_writeln('    JVM heap in use: ' + %char(jvm.in_use_heap));
      SCOUT_writeln('    JVM heap max: ' + %char(jvm.max_heap_size));
      SCOUT_writeln('    JVM collections: ' + %char(jvm.gc_cycles));
    endif;
  endfor;

end-proc;

//==============================================================================
// SCEXEC_scrunattrs
//   The SCOMMANDER_ variables a running service was started with
//==============================================================================

dcl-proc SCEXEC_scrunattrs export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  SCLAUNCH_build_env(def: SCLOG_path(def): env);

  for i = 1 to env.count;
    if %len(env.entry(i)) > 11
       and %subst(env.entry(i): 1: 11) = 'SCOMMANDER_';
      SCOUT_writeln(%trim(def.short_name) + ': ' + %trim(env.entry(i)));
    endif;
  endfor;

end-proc;
