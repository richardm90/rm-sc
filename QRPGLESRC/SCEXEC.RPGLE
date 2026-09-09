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

  dcl-ds ev likeds(SCEXEC_EVAL_t) inz(*likeds);

  // The bare word, and only the bare word. SCAPI hands this to consumers
  // comparing against SC_PARTIAL, so the counts upstream shows in a check row
  // are added when the row is rendered, not here.
  SCEXEC_evaluate(def: ev);

  // A service whose criteria cannot be used is reported stopped rather than
  // with a blank status. ev.state is deliberately blank in that case so a
  // caller cannot mistake it for a real answer, but this procedure's whole
  // contract is that it returns one of the three words - SCAPI compares its
  // result against a constant, and would match nothing at all.
  if ev.unusable_count > 0;
    return SCOUT_NOT_RUNNING;
  endif;

  return ev.state;

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
    def      likeds(SCDEF_t) const;
    unusable like(BOOLEAN_t) options(*nopass);
  end-pi;

  dcl-ds ev likeds(SCEXEC_EVAL_t) inz(*likeds);

  if %parms() >= 2 and %addr(unusable) <> *null;
    unusable = false;
  endif;

  SCEXEC_evaluate(def: ev);

  // No row at all for a service that cannot be checked - upstream prints the
  // complaint on standard error, in this service's own place in the walk, and
  // carries on with the rest.
  if ev.unusable_count > 0;
    SCOUT_warnln(SCOUT_invalid_criteria(def.friendly: ev.unusable_text));
    if %parms() >= 2 and %addr(unusable) <> *null;
      unusable = true;
    endif;
    return;
  endif;

  // Only a partial service carries counts and a list of what is not running.
  // RUNNING and NOT RUNNING rows are exactly what they have always been.
  if ev.state = SCOUT_PARTIAL;
    SCOUT_writeln(SCOUT_check_row(SCOUT_partial_status(ev.alive: ev.total):
                                  def.short_name: def.friendly:
                                  SCOUT_not_running_suffix(ev.failed_text)));
  else;
    SCOUT_writeln(SCOUT_check_row(ev.state: def.short_name: def.friendly));
  endif;

end-proc;


//==============================================================================
// SCEXEC_check_all
//==============================================================================

dcl-proc SCEXEC_check_all export;
  dcl-pi *n like(INTEGER_t);
    coll          likeds(SCCOLL_t);
    ignore_groups like(SCDEF_NAME_t) const;
    unusable      like(INTEGER_t) options(*nopass);
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s i     like(INTEGER_t);
  dcl-s shown like(INTEGER_t) inz(0);
  dcl-s wrong like(INTEGER_t) inz(0);
  dcl-s bad   like(BOOLEAN_t) inz(false);

  for i = 1 to SCCOLL_count(coll);
    if SCCOLL_get(coll: i: def) and not SCCOLL_in_groups(def: ignore_groups);
      SCEXEC_check(def: bad);
      if bad;
        wrong += 1;
      else;
        shown += 1;
      endif;
    endif;
  endfor;

  // Upstream ends the listing with a blank line - but not when a service
  // could not be checked. Measured: a bare check with one bad definition
  // present ends on the last row, with no blank after it.
  if wrong = 0;
    SCOUT_writeln('');
  endif;

  if %parms() >= 3 and %addr(unusable) <> *null;
    unusable = wrong;
  endif;

  return shown;

end-proc;

//==============================================================================
// SCEXEC_list
//==============================================================================

dcl-proc SCEXEC_list export;
  dcl-pi *n like(INTEGER_t);
    coll          likeds(SCCOLL_t);
    ignore_groups like(SCDEF_NAME_t) const;
    only_group    like(SCDEF_NAME_t) const options(*nopass);
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s i like(INTEGER_t);
  dcl-s shown like(INTEGER_t) inz(0);
  dcl-s only like(SCDEF_NAME_t) inz('');

  if %parms() >= 3 and %addr(only_group) <> *null;
    only = STRING_lower(%trim(only_group));
  endif;

  for i = 1 to SCCOLL_count(coll);
    if not SCCOLL_get(coll: i: def);
      iter;
    endif;

    if %len(only) > 0;
      // Naming a group is asking for it, so the exclusions do not also apply
      if not SCDEF_in_group(def: only);
        iter;
      endif;
    elseif SCCOLL_in_groups(def: ignore_groups);
      iter;
    endif;

    SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
    shown += 1;
  endfor;

  SCOUT_writeln('');

  return shown;

end-proc;

//==============================================================================
// SCEXEC_groups
//==============================================================================

dcl-proc SCEXEC_groups export;
  dcl-pi *n like(INTEGER_t);
    coll           likeds(SCCOLL_t);
    ignore_groups  like(SCDEF_NAME_t) const;
    ignore_globals like(BOOLEAN_t) const options(*nopass);
  end-pi;

  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);
  dcl-s seen like(BOOLEAN_t);
  dcl-s skip_builtin like(BOOLEAN_t) inz(false);

  // The distinct groups of the services the caller can see. Asked of the
  // collection rather than gathered again here: two loops building the same
  // list is how this one's sort came to differ from the collection's.
  SCCOLL_groups(coll: groups: ignore_groups);

  // 'system' is built in and is listed even when every one of its members has
  // been filtered out - but NOT when the global directories were skipped,
  // since upstream adds the built-in entry only on the path that read them.
  if %parms() >= 3 and %addr(ignore_globals) <> *null;
    skip_builtin = ignore_globals;
  endif;

  if not skip_builtin;
    seen = false;
    for i = 1 to groups.count;
      if groups.name(i) = 'system';
        seen = true;
        leave;
      endif;
    endfor;

    // Inserted in its place rather than appended and re-sorted: the list came
    // back sorted, and one element does not justify sorting it again.
    if not seen and groups.count < SCCOLL_MAX_GROUPS;
      i = 1;
      dow i <= groups.count and SCCOLL_sorts_before(groups.name(i): 'system');
        i += 1;
      enddo;
      for j = groups.count downto i;
        groups.name(j + 1) = groups.name(j);
      endfor;
      groups.name(i) = 'system';
      groups.count += 1;
    endif;
  endif;

  for i = 1 to groups.count;
    SCOUT_writeln(groups.name(i));
  endfor;

  SCOUT_writeln('');

  // How many rows were printed, as SCEXEC_list and SCEXEC_check_all report.
  // It is what makes this procedure answerable from a test at all - stdout is
  // not reachable from inside the job.
  return groups.count;

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
  dcl-ds ev    likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s i       like(INTEGER_t);
  dcl-s waited  like(INTEGER_t);
  dcl-s lerr    like(SCLAUNCH_ERR_t);
  dcl-s timeout like(SCOUT_LINE_t);
  dcl-s target  like(SCDEF_NAME_t);
  dcl-s was_partial like(BOOLEAN_t) inz(*off);
  dcl-s  log_path  like(STMF_t);
  dcl-ds log_stats likeds(IFS_stats_t);

  err = '';

  if not SCCOLL_start_order(coll: name: order);
    err = order.err;
    narrate_error(err);
    return false;
  endif;

  // The service the caller named is last in the order; everything before it
  // is a dependency being started on the way. Held so a dependency's failure
  // can name the service it was being started FOR, as upstream's does.
  target = order.name(order.count);

  for i = 1 to order.count;
    if not SCCOLL_find(coll: order.name(i): def);
      err = 'Unknown service ' + %trim(order.name(i));
      narrate_error(err);
      return false;
    endif;

    // Announced before it is looked at, not before work is done: upstream
    // prints this even when the dependency is already running and nothing
    // happens. Measured - see docs/messages.md.
    if i < order.count;
      SCOUT_writeln(SCOUT_dep_start(def.short_name: def.friendly));
    endif;

    SCEXEC_evaluate(def: ev);

    // Already up, including a dependency started by an earlier request. Every
    // service in the walk reports its own outcome, not only the named one.
    if ev.state = SCOUT_RUNNING;
      SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_ALREADY_RUNNING));
      iter;
    endif;

    // Half up. On stderr, where the four ordinary states are on stdout - the
    // asymmetry is upstream's and SCOUT_svc_partial exists to keep it.
    was_partial = (ev.state = SCOUT_PARTIAL);
    if was_partial;
      SCOUT_warnln(SCOUT_svc_partial(def.friendly));
    endif;

    SCLOG_ensure_dir(def);

    if not SCLAUNCH_start(def: SCLOG_path(def): lerr);
      err = 'Could not start ' + %trim(def.short_name) + ': ' + %trim(lerr);
      narrate_error(err);
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

    SCEXEC_evaluate(def: ev);

    if ev.state = SCOUT_RUNNING;
      SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_STARTED));
      iter;
    endif;

    // It did not come up. Upstream says how far short it fell before it says
    // it timed out, and the shortfall line reuses the check row's rendering of
    // the criteria rather than making a second one.
    if ev.alive > 0 and ev.alive < ev.total;
      SCOUT_warnln(SCOUT_only_started(def.friendly: ev.alive: ev.total:
                   SCOUT_not_running_suffix(ev.failed_text)));
    endif;

    // Each ERROR on stderr is followed by a blank line - per ERROR, where the
    // blank on stdout is per COMMAND. Measured; the asymmetry is upstream's,
    // and the WARNING above deliberately does NOT get one.
    timeout = SCOUT_err_timeout(def.friendly);
    SCOUT_warnln(timeout);
    SCOUT_warnln('');

    // A dependency that would not start names the service it was needed for,
    // and embeds the whole inner message, its own ERROR: prefix included.
    if i < order.count;
      SCOUT_warnln(SCOUT_err_dep_failed(def.short_name: friendly_of(coll:
                   target): timeout));
      SCOUT_warnln('');
    endif;

    // ONLY when the log file has something in it - there is no point telling
    // anyone to go and read an empty file.
    //
    // THIS GATE WAS WRONG TWICE BEFORE. First it was "any failed start", which
    // upstream contradicted. Then "the service was already partly up", from a
    // probe that started a half-up service repeatedly - but that fixture moved
    // TWO things at once, because the log gained content on the same attempt
    // the service became partial, and both rules fit. Review separated them
    // with a service that never runs and whose start command prints one line:
    // upstream prints the line, and the partial-state rule does not predict it.
    //
    //   never running, start cmd silent    log 0 bytes   no line
    //   never running, start cmd prints    log 40 bytes  LINE
    //   partial,       start cmd silent    log 0 bytes   no line
    //
    // The path RMSC names is its own and carries no timestamp where upstream's
    // does; docs/parity.md records that, and it is a property of SCLOG_path
    // rather than of this line.
    log_path  = SCLOG_path(def);
    log_stats = IFS_stats(log_path);
    if log_stats.st_size > 0;
      SCOUT_writeln(SCOUT_log_detail(log_path));
    endif;

    // Reported here, in upstream's words and on upstream's streams. The
    // message is STILL SET: SCMAIN does not print it, but SCAPI is silent and
    // has nothing but the return value to tell its caller with. Emptying it
    // lost the reason entirely for a bound-call caller, which is the kind of
    // defect that shows up as a program reporting failure and not saying why.
    err = %trim(def.short_name) + ' did not start within ' +
          %char(def.startup_wait) + 's';
    return false;
  endfor;

  return true;

end-proc;

//==============================================================================
// narrate_error
//   A failure RMSC has no measured upstream wording for
//
// SCEXEC is the ONE place a state-changing failure is reported. SCMAIN prints
// nothing for these operations, so anything not said here is not said at all
// on the command line - and `err` is still returned, because SCAPI is silent
// and has only the return value to read.
//
// ERROR: on stderr followed by a blank line, which is the shape upstream uses
// for the failures it does have wording for.
//==============================================================================

dcl-proc narrate_error;
  dcl-pi *n;
    text like(SCEXEC_ERR_t) const;
  end-pi;

  SCOUT_warnln('ERROR: ' + %trim(text));
  SCOUT_warnln('');

end-proc;

//==============================================================================
// friendly_of
//   The friendly name for a short one, for a message that must use it
//
// The dependency-failure line names the DEPENDENCY by its short name and the
// service it was needed for by its FRIENDLY one, so one message needs both
// kinds of name for two different services. Measured; see docs/messages.md.
//==============================================================================

dcl-proc friendly_of;
  dcl-pi *n like(SCOUT_LINE_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  if SCCOLL_find(coll: name: def);
    return def.friendly;
  endif;

  // Cannot happen on the path that calls this - the walk resolved every name
  // in the order before starting anything - but returning the short name is a
  // readable answer rather than a blank one if it ever does.
  return name;

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
    narrate_error(err);
    return false;
  endif;

  // Anything depending on this must go down first, or it is left running
  // against a service that has gone away.
  for i = 1 to SCCOLL_count(coll);
    if not SCCOLL_get(coll: i: other);
      iter;
    endif;
    for j = 1 to other.dep_count;
      if other.deps(j) = want;
        // Announced and visited whatever state it is in. This used to skip a
        // dependent that was already stopped, which was harmless while
        // nothing was printed - upstream announces it and then says it is
        // already stopped, and stop_one returns immediately for one that is.
        SCOUT_writeln(SCOUT_dep_stop(other.friendly));
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
    SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_ALREADY_STOPPED));
    return true;
  endif;

  // 'kill' means skip the service's own stop command
  if def.has_stop_cmd and not kill;
    used_stop_cmd = true;
    if not SCLAUNCH_run_stop_cmd(def: SCLOG_path(def): lerr);
      err = 'Stop command failed for ' + %trim(def.short_name) +
            ': ' + %trim(lerr);
      narrate_error(err);
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
      SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_STOPPED));
      return true;
    endif;
  enddo;

  if SCEXEC_status(def) = SCOUT_NOT_RUNNING;
    SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_STOPPED));
    return true;
  endif;

  // Escalate only where upstream does: a service that supplied its own stop
  // command has said how it wants to be stopped, and overriding that could
  // cut short whatever the command was doing.
  if used_stop_cmd;
    err = %trim(def.short_name) + ' did not stop within ' +
          %char(def.stop_wait) + 's';
    narrate_error(err);
    return false;
  endif;

  SCEXEC_jobs(def: jobs);
  for i = 1 to jobs.count;
    SCLAUNCH_endjob(jobs.name(i): 0: true: lerr);
  endfor;

  delay(SCEXEC_STOP_POLL);

  if SCEXEC_status(def) <> SCOUT_NOT_RUNNING;
    err = %trim(def.short_name) + ' did not stop, even immediately';
    narrate_error(err);
    return false;
  endif;

  SCOUT_writeln(SCOUT_svc_state(def.friendly: SCOUT_STOPPED));
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
  SCOUT_writeln(SCOUT_RULE);
  // Through SCOUT_list_row rather than built here, and the point is that this
  // IS a list row - the same two fields in the same shape. Upstream colours it
  // cyan 36, the identical colour it gives a `list` row, measured through a
  // pseudo-terminal.
  //
  // Building it by hand meant the same construct was coloured in `list` and
  // plain in `info` from the moment `list` gained colour, and it meant a
  // byte-sensitive format string written out twice - which is how the two
  // come to disagree without anyone editing either on purpose.
  //
  // The rest of `info`'s colour is deliberately NOT done here: upstream also
  // colours its field labels cyan and its rule lines white 37, and `info`
  // still carries eight measured non-colour differences, two of them shape
  // rather than spelling. Colouring the body before its content matches would
  // mean doing it twice.
  SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
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
    // Rendered by the one procedure that knows how, rather than rebuilt here
    // from the parsed fields. Building it here got three things wrong at once:
    // a job name longer than ten characters was TRUNCATED, because *JOB name
    // fields hold ten and the criterion text does not; a PGM- criterion
    // rendered as 'PGM:x' where upstream has no such form and says
    // 'JOBNAME:PGM-X'; and a port rendered from the converted number, so a
    // criterion upstream shows as PORT:abc appeared here as PORT:0.
    line += SCDEF_criterion_text(def.criteria(i));
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

  // Unrecognised keys are reported by the loader now, on stderr, on every
  // invocation - which is what upstream does. Printing them here as well
  // would mean two warnings for one cause, on two streams, and this one was
  // on stdout where a column-parsing consumer reads.

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

// Upstream builds this block by scraping DSPJOB OPTION(*RUNA) and printing
// whatever matched, then appending a set of sampled figures sorted by label.
// RMSC reads the same values from QUSRJOBI and SQL - docs/parity.md carries
// the decision and the three affinity lines it costs.
//
// The ORDER below is not a choice. Upstream's sampled figures come out of a
// sorted map, so they appear alphabetically by label, and the arrow on
// '->Sampling time' is what makes it sort first. Reordering these lines is a
// parity defect even though every value is still present.

// %char of a packed field with decimals drops the leading zero, so a CPU
// figure of zero renders '.00' where upstream prints '0.00'. That was live in
// the old perfinfo output.
dcl-proc decimal_text;
  dcl-pi *n like(SCOUT_LINE_t);
    text like(SCOUT_LINE_t) const;
  end-pi;

  if %len(text) > 0 and %subst(text: 1: 1) = '.';
    return '0' + text;
  endif;
  if %len(text) > 1 and %subst(text: 1: 2) = '-.';
    return '-0' + %subst(text: 2);
  endif;

  return text;

end-proc;

dcl-proc field_line;
  dcl-pi *n like(SCOUT_LINE_t);
    label like(SCOUT_LINE_t) const;
    value like(SCOUT_LINE_t) const;
  end-pi;

  // Four spaces, and SIX for the figures nested under a limit - the callers
  // that want six prefix two more rather than this taking an indent level,
  // because there are exactly three of them and a parameter would invite a
  // fourth.
  //
  // Every line RMSC prints here carries a value. Upstream has one that does
  // not - `Thread resources affinity (THDRSCAFN): ` with a trailing space and
  // nothing after it - but that is one of the three lines RMSC omits, so the
  // empty-value shape never arises. If those three ever become reachable,
  // this is where the trailing space has to come back.
  return '    ' + %trimr(label) + ': ' + %trimr(value);

end-proc;

dcl-proc SCEXEC_perfinfo export;
  dcl-pi *n;
    def     likeds(SCDEF_t) const;
    seconds like(SCQRY_SECS_t) const;
  end-pi;

  dcl-ds jobs  likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds perf  likeds(SCQRY_PERF_t) inz(*likeds);
  dcl-ds jvm   likeds(SCQRY_JVM_t) inz(*likeds);
  dcl-ds attrs likeds(SCQRY_ATTRS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  SCOUT_writeln('Gathering performance information...');
  SCOUT_writeln('');
  SCOUT_writeln(SCOUT_RULE);
  SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));

  if SCEXEC_jobs(def: jobs) = 0;
    // Measured: NOT RUNNING sits directly under the title with no blank line
    // between, and the whole thing is eight lines.
    SCOUT_writeln('NOT RUNNING');
    SCOUT_writeln(SCOUT_RULE);
    SCOUT_writeln('');
    SCOUT_writeln('');
    return;
  endif;

  SCOUT_writeln('');

  for i = 1 to jobs.count;
    SCOUT_writeln('Job: ' + %trim(jobs.name(i)));

    if SCQRY_job_attrs(jobs.name(i): attrs);
      SCOUT_writeln(field_line('Run priority (RUNPTY)':
                               %char(attrs.run_priority)));
      SCOUT_writeln(field_line('Time slice in milliseconds (TIMESLICE)':
                               %char(attrs.time_slice)));
      SCOUT_writeln(field_line('Eligible for purge (PURGE)':
                               attrs.purge));
      SCOUT_writeln(field_line('Default wait time in seconds (DFTWAIT)':
                               attrs.default_wait));
      SCOUT_writeln(field_line('Maximum CPU time in milliseconds (CPUTIME)':
                               attrs.max_cpu_time));
      SCOUT_writeln('  ' + field_line('CPU time used':
                               %char(attrs.cpu_time_used)));
      SCOUT_writeln(field_line(
                    'Maximum temporary storage in megabytes (MAXTMPSTG)':
                               attrs.max_temp_storage));
      SCOUT_writeln('  ' + field_line('Temporary storage used':
                               %char(attrs.temp_storage_used)));
      SCOUT_writeln('  ' + field_line('Peak temporary storage used':
                               %char(attrs.peak_temp_storage)));
      SCOUT_writeln(field_line('Maximum threads (MAXTHD)':
                               attrs.max_threads));
      SCOUT_writeln('  ' + field_line('Threads':
                               %char(attrs.thread_count)));
    endif;

    // Only services that run one, which is why finding none is not an error.
    clear jvm;
    SCQRY_jvm_info(jobs.name(i): jvm);

    if SCQRY_job_sample(jobs.name(i): seconds: perf);
      SCOUT_writeln(field_line('->Sampling time (s)':
                    decimal_text(%char(perf.sample_seconds))));
      SCOUT_writeln(field_line('CPU Usage (%)':
                    decimal_text(%char(perf.cpu_percentage))));
      SCOUT_writeln(field_line('Current User': perf.current_user));
      SCOUT_writeln(field_line('Disk I/O operations during sampling time':
                    %char(perf.disk_io_count)));
      SCOUT_writeln(field_line('Function': perf.job_function));

      // Alphabetical by label, which is what puts the Java block here rather
      // than at the end. Separators on the memory figures only - measured;
      // 'Java GC Total Time (ms): 1306' beside 'Java Heap In Use (Kb):
      // 66,730' is the pair that settles it.
      if jvm.found;
        SCOUT_writeln(field_line('Java GC Cycle Number':
                      %char(jvm.gc_cycles)));
        SCOUT_writeln(field_line('Java GC Total Time (ms)':
                      %char(jvm.gc_total_time)));
        SCOUT_writeln(field_line('Java Heap Current Size (MB)':
                      SCOUT_thousands(jvm.heap_size)));
        SCOUT_writeln(field_line('Java Heap In Use (Kb)':
                      SCOUT_thousands(jvm.in_use_heap)));
        SCOUT_writeln(field_line('Java Heap Maximum Size (Kb)':
                      SCOUT_thousands(jvm.max_heap_size)));
        SCOUT_writeln(field_line('Java JIT Memory (KB)':
                      SCOUT_thousands(jvm.jit_memory)));
        SCOUT_writeln(field_line('Java Shared Class Size (Kb)':
                      SCOUT_thousands(jvm.shared_class)));
      endif;

      SCOUT_writeln(field_line('Job Status': perf.job_status));
      SCOUT_writeln(field_line('Job active since': perf.active_since));

      if jvm.found;
        SCOUT_writeln(field_line('Malloc''ed Memory estimate (Kb)':
                      SCOUT_thousands(jvm.malloc_memory)));
      endif;

      SCOUT_writeln(field_line('Total Disk I/O operations':
                    %char(perf.total_disk_io)));
    endif;

    SCOUT_writeln('');
  endfor;

  SCOUT_writeln(SCOUT_RULE);
  SCOUT_writeln('');
  SCOUT_writeln('');

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

//==============================================================================
// SCEXEC_evaluate
//==============================================================================

dcl-proc SCEXEC_evaluate export;
  dcl-pi *n;
    def likeds(SCDEF_t) const;
    ev  likeds(SCEXEC_EVAL_t);
  end-pi;

  dcl-s i like(INTEGER_t);

  clear ev;

  // Settled before anything is probed. Usability is a property of the text,
  // not of the machine, so a definition naming a port that is not a number
  // asks the system nothing at all - and every count stays zero, rather than
  // holding a half-finished answer that reads like a real one.
  for i = 1 to def.criteria_count;
    if not SCDEF_criterion_usable(def.criteria(i));
      ev.unusable_count += 1;
      if ev.unusable_index = 0;
        ev.unusable_index = i;
        ev.unusable_text  = SCDEF_criterion_text(def.criteria(i));
      endif;
    endif;
  endfor;

  if ev.unusable_count > 0;
    // state is left BLANK deliberately - see SCEXEC_D. A caller that reads it
    // without reading unusable_count gets something obviously wrong instead of
    // a plausible NOT RUNNING.
    return;
  endif;

  ev.total = def.criteria_count;

  // Each criterion is probed exactly once. They are live port and job
  // lookups, and check runs them for every service on the system.
  for i = 1 to def.criteria_count;
    if SCEXEC_criterion_alive(def.criteria(i));
      ev.alive += 1;
      iter;
    endif;

    ev.failed_count += 1;
    ev.failed(ev.failed_count) = SCDEF_criterion_text(def.criteria(i));
    if ev.failed_count > 1;
      ev.failed_text += ', ';
    endif;
    ev.failed_text += %trim(ev.failed(ev.failed_count));
  endfor;

  select;
    // A definition with no criteria cannot be checked, so it cannot be running
    when def.criteria_count = 0 or ev.alive = 0;
      ev.state = SCOUT_NOT_RUNNING;
    when ev.alive = def.criteria_count;
      ev.state = SCOUT_RUNNING;
    other;
      ev.state = SCOUT_PARTIAL;
  endsl;

end-proc;
