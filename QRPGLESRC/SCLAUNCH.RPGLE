**free

//==============================================================================
// SCLAUNCH   - Service launch
//
// Starting a service has one hard requirement: the service must outlive RMSC.
// PASE_run_cmd waits for its child and captures its output, so a command that
// does not fully detach would keep RMSC running for as long as the service
// does. The pattern used here - nohup, all three descriptors redirected,
// backgrounded - was measured before this module was written: without it the
// call blocks for the child's lifetime; with it the call returns at once and
// the process survives the session that started it.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service launch');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCLAUNCH_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'include/RMENVVAR_D.rpgleinc'
/include 'include/RMPASE_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMJOB_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// Variables never passed on to a service.
//
// Upstream's list. These describe the environment RMSC happens to be running
// in - its shell, its library path, the ssh session that invoked it - and
// carrying them into a long-lived service would be wrong or actively harmful.
///

dcl-c ENV_BLOCK_COUNT const(6);
dcl-s g_blocked varchar(20) dim(ENV_BLOCK_COUNT) ctdata perrcd(1);

dcl-pr add_env;
  env   likeds(SCLAUNCH_ENV_t);
  entry like(SCDEF_ENVVAR_t) const;
end-pr;

dcl-pr is_blocked like(BOOLEAN_t);
  name like(SCDEF_ENVVAR_t) const;
end-pr;

dcl-pr single_port like(INTEGER_t);
  def likeds(SCDEF_t) const;
end-pr;

// NAME=VALUE with a legitimately empty VALUE leaves '=' as the last
// character, and taking a substring from beyond it is an error rather than an
// empty string.
dcl-pr env_value like(SCDEF_ENVVAR_t);
  entry like(SCDEF_ENVVAR_t) const;
end-pr;

dcl-pr env_name like(SCDEF_ENVVAR_t);
  entry like(SCDEF_ENVVAR_t) const;
end-pr;

//==============================================================================
// SCLAUNCH_build_env
//==============================================================================

dcl-proc SCLAUNCH_build_env export;
  dcl-pi *n;
    def      likeds(SCDEF_t) const;
    log_file like(STMF_t) const;
    env      likeds(SCLAUNCH_ENV_t);
  end-pi;

  dcl-s i         like(INTEGER_t);
  dcl-s port      like(INTEGER_t);
  dcl-s submitter like(SCDEF_ENVVAR_t);

  clear env;

  // The service's own variables. Inherited variables are not enumerated here:
  // for a non-batch start the shell already has them, and for a batch start
  // SBMJOB CPYENVVAR(*YES) copies this job's. Both honour
  // environment_is_inheriting_vars, which is applied at the point of use.
  for i = 1 to def.envvar_count;
    if not is_blocked(def.envvars(i));
      add_env(env: def.envvars(i));
    endif;
  endfor;

  // PORT and PORT_PLUS_1..8, but only when there is exactly one port
  // criterion - with two, which port would PORT mean?
  port = single_port(def);
  if port > 0;
    add_env(env: 'PORT=' + %char(port));
    for i = 1 to 8;
      add_env(env: 'PORT_PLUS_' + %char(i) + '=' + %char(port + i));
    endfor;
  endif;

  // Metadata upstream exposes, and which scrunattrs reports back
  add_env(env: 'SCOMMANDER_LOGFILE=' + %trim(log_file));
  add_env(env: 'SCOMMANDER_NAME=' + %trim(def.short_name));
  add_env(env: 'SCOMMANDER_FRIENDLY_NAME=' + %trim(def.friendly));
  add_env(env: 'SCOMMANDER_DEFINED_AT=' + %trim(def.defined_at));
  // USER is not set in a batch job, which is where services are started from
  submitter = %trim(ENVVAR_get('USER'));
  if %len(submitter) = 0;
    submitter = %trim(JOB_user());
  endif;
  add_env(env: 'SCOMMANDER_SUBMITTER=' + submitter);

end-proc;

//==============================================================================
// env_name / env_value
//   Split NAME=VALUE, tolerating an empty value
//==============================================================================

dcl-proc env_name;
  dcl-pi *n like(SCDEF_ENVVAR_t);
    entry like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s eq like(INTEGER_t);

  eq = %scan('=': entry);
  if eq < 2;
    return '';
  endif;

  return %subst(entry: 1: eq - 1);

end-proc;

dcl-proc env_value;
  dcl-pi *n like(SCDEF_ENVVAR_t);
    entry like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s eq like(INTEGER_t);

  eq = %scan('=': entry);
  if eq < 1 or eq >= %len(%trimr(entry));
    return '';
  endif;

  return %subst(entry: eq + 1);

end-proc;

//==============================================================================
// single_port
//   The port to publish as $PORT, or zero if that is ambiguous
//==============================================================================

dcl-proc single_port;
  dcl-pi *n like(INTEGER_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s i     like(INTEGER_t);
  dcl-s found like(INTEGER_t) inz(0);
  dcl-s count like(INTEGER_t) inz(0);

  for i = 1 to def.criteria_count;
    if def.criteria(i).kind = SCDEF_CHECK_PORT;
      count += 1;
      found = def.criteria(i).port;
    endif;
  endfor;

  if count = 1;
    return found;
  endif;

  return 0;

end-proc;

//==============================================================================
// add_env
//   Append, replacing any earlier entry with the same name
//==============================================================================

dcl-proc add_env;
  dcl-pi *n;
    env   likeds(SCLAUNCH_ENV_t);
    entry like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s name like(SCDEF_ENVVAR_t);
  dcl-s eq   like(INTEGER_t);
  dcl-s i    like(INTEGER_t);

  eq = %scan('=': entry);
  if eq < 2;
    return;
  endif;

  name = %subst(entry: 1: eq);

  for i = 1 to env.count;
    if %len(env.entry(i)) >= %len(name)
       and %subst(env.entry(i): 1: %len(name)) = name;
      env.entry(i) = entry;
      return;
    endif;
  endfor;

  if env.count >= SCLAUNCH_MAX_ENV;
    return;
  endif;

  env.count += 1;
  env.entry(env.count) = entry;

end-proc;

//==============================================================================
// is_blocked
//==============================================================================

dcl-proc is_blocked;
  dcl-pi *n like(BOOLEAN_t);
    name like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s i     like(INTEGER_t);
  dcl-s upper like(SCDEF_ENVVAR_t);

  upper = STRING_upper(%trim(name));

  for i = 1 to ENV_BLOCK_COUNT;
    // Prefix match, so SSH_CLIENT and SSH_CONNECTION go with SSH_
    if %len(upper) >= %len(%trim(g_blocked(i)))
       and %subst(upper: 1: %len(%trim(g_blocked(i)))) = %trim(g_blocked(i));
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// SCLAUNCH_quote
//   Single-quote for the shell, escaping any embedded single quote
//==============================================================================

dcl-proc SCLAUNCH_quote export;
  dcl-pi *n like(SCLAUNCH_CMD_t);
    value like(SCLAUNCH_CMD_t) const;
  end-pi;

  dcl-s q   char(1) inz('''');
  dcl-s esc varchar(4);

  // Built from characters rather than written as a literal: the RPG escaping
  // needed to write '\'' inline is unreadable and easy to get wrong.
  //
  // The shell idiom is to close the quote, emit an escaped quote, and reopen:
  //   don't  ->  'don'\''t'
  esc = q + '\' + q + q;

  return q + STRING_replace(%trim(value): q: esc) + q;

end-proc;

//==============================================================================
// SCLAUNCH_start_command
//   The detached shell command for a non-batch service
//==============================================================================

dcl-proc SCLAUNCH_start_command export;
  dcl-pi *n like(SCLAUNCH_CMD_t);
    def      likeds(SCDEF_t) const;
    log_file like(STMF_t) const;
  end-pi;

  dcl-ds env likeds(SCLAUNCH_ENV_t);
  dcl-s cmd like(SCLAUNCH_CMD_t);
  dcl-s i   like(INTEGER_t);
  dcl-s eq  like(INTEGER_t);

  SCLAUNCH_build_env(def: log_file: env);

  cmd = 'cd ' + SCLAUNCH_quote(SCDEF_effective_dir(def)) + ' && ';

  for i = 1 to env.count;
    cmd += %trim(env_name(env.entry(i))) + '=' +
           SCLAUNCH_quote(env_value(env.entry(i))) + ' ';
  endfor;

  // nohup so a hangup does not take it down, all three descriptors redirected
  // so nothing is left attached to the caller's pipes, and backgrounded so
  // PASE_run_cmd returns instead of waiting for the service to finish.
  cmd += 'nohup ' + %trim(def.start_cmd) +
         ' >> ' + SCLAUNCH_quote(log_file) + ' 2>&1 < /dev/null &';

  return cmd;

end-proc;

//==============================================================================
// SCLAUNCH_job_name
//==============================================================================

dcl-proc SCLAUNCH_job_name export;
  dcl-pi *n like(SCDEF_OBJ_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s work like(SCDEF_ENVVAR_t);
  dcl-s result like(SCDEF_ENVVAR_t);
  dcl-s ch   char(1);
  dcl-s i    like(INTEGER_t);

  if %len(%trim(def.sbmjob_jobname)) > 0;
    return STRING_upper(%trim(def.sbmjob_jobname));
  endif;

  work = STRING_upper(%trim(def.short_name));
  result = '';

  for i = 1 to %len(work);
    ch = %subst(work: i: 1);
    if (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9');
      result += ch;
    endif;
  endfor;

  // A job name cannot start with a digit
  if %len(result) > 0 and %subst(result: 1: 1) >= '0'
     and %subst(result: 1: 1) <= '9';
    result = 'J' + result;
  endif;

  if %len(result) > 10;
    result = %subst(result: 1: 10);
  endif;

  if %len(result) = 0;
    result = 'SCSERVICE';
  endif;

  return result;

end-proc;

//==============================================================================
// SCLAUNCH_start
//==============================================================================

dcl-proc SCLAUNCH_start export;
  dcl-pi *n like(BOOLEAN_t);
    def      likeds(SCDEF_t) const;
    log_file like(STMF_t) const;
    err      like(SCLAUNCH_ERR_t);
  end-pi;

  dcl-ds env  likeds(SCLAUNCH_ENV_t);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd    like(SCLAUNCH_CMD_t);
  dcl-s clcmd  like(QCMD_CMD_t);
  dcl-s stdout like(PASE_IO_t);
  dcl-s rc     like(INTEGER_t);
  dcl-s i      like(INTEGER_t);
  dcl-s eq     like(INTEGER_t);

  err = '';

  if not def.batch_mode;
    cmd = SCLAUNCH_start_command(def: log_file);
    rc = PASE_run_cmd(*omit: cmd: stdout);
    if rc <> PASE_RC_SUCCESS;
      err = 'Start command failed with ' + %char(rc) + ': ' + %trim(stdout);
      return false;
    endif;
    return true;
  endif;

  // Batch. Upstream writes a temporary shell script that shells back to
  // SBMJOB; setting the variables on this job and letting CPYENVVAR(*YES)
  // carry them across does the same thing without the temporary file.
  SCLAUNCH_build_env(def: log_file: env);
  for i = 1 to env.count;
    ENVVAR_put(env_name(env.entry(i)): env_value(env.entry(i)):
               ENVVAR_LEVEL_JOB);
  endfor;

  clcmd = 'SBMJOB CMD(QSH CMD(''cd ' +
          %trim(SCDEF_effective_dir(def)) + ' && ' +
          %trim(def.start_cmd) + ' >> ' + %trim(log_file) + ' 2>&1'')) ' +
          'JOB(' + %trim(SCLAUNCH_job_name(def)) + ') ' +
          'CPYENVVAR(*YES) PRTDEV(*USRPRF) ALWMLTTHD(*YES)';

  if %len(%trim(def.sbmjob_opts)) > 0;
    clcmd += ' ' + %trim(def.sbmjob_opts);
  endif;

  if not QCMD_exc(clcmd: qerr);
    err = 'SBMJOB failed';
    if qerr.count > 0;
      err += ': ' + %trim(qerr.msgs(1).text);
    endif;
    return false;
  endif;

  return true;

end-proc;

//==============================================================================
// SCLAUNCH_run_stop_cmd
//==============================================================================

dcl-proc SCLAUNCH_run_stop_cmd export;
  dcl-pi *n like(BOOLEAN_t);
    def      likeds(SCDEF_t) const;
    log_file like(STMF_t) const;
    err      like(SCLAUNCH_ERR_t);
  end-pi;

  dcl-s cmd    like(SCLAUNCH_CMD_t);
  dcl-s stdout like(PASE_IO_t);
  dcl-s rc     like(INTEGER_t);

  err = '';

  if not def.has_stop_cmd;
    err = 'No stop_cmd defined';
    return false;
  endif;

  // Not detached: a stop command is expected to finish, and its exit status
  // is the answer to whether the service stopped.
  cmd = 'cd ' + SCLAUNCH_quote(SCDEF_effective_dir(def)) + ' && ' +
        %trim(def.stop_cmd) + ' >> ' + SCLAUNCH_quote(log_file) + ' 2>&1';

  rc = PASE_run_cmd(*omit: cmd: stdout);
  if rc <> PASE_RC_SUCCESS;
    err = 'Stop command failed with ' + %char(rc) + ': ' + %trim(stdout);
    return false;
  endif;

  return true;

end-proc;

//==============================================================================
// SCLAUNCH_endjob
//==============================================================================

dcl-proc SCLAUNCH_endjob export;
  dcl-pi *n like(BOOLEAN_t);
    job_name  like(SCQRY_JOBNAME_t) const;
    delay     like(INTEGER_t) const;
    immediate like(BOOLEAN_t) const;
    err       like(SCLAUNCH_ERR_t);
  end-pi;

  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s clcmd like(QCMD_CMD_t);

  err = '';

  clcmd = 'ENDJOB JOB(' + %trim(job_name) + ')';
  if immediate;
    clcmd += ' OPTION(*IMMED)';
  else;
    clcmd += ' OPTION(*CNTRLD) DELAY(' + %char(delay) + ')';
  endif;

  if not QCMD_exc(clcmd: qerr);
    err = 'ENDJOB failed for ' + %trim(job_name);
    if qerr.count > 0;
      err += ': ' + %trim(qerr.msgs(1).text);
    endif;
    return false;
  endif;

  return true;

end-proc;

**CTDATA g_blocked
LIBPATH
LD_LIBRARY_PATH
JAVA_HOME
SSH_
SHELL
SHLVL
