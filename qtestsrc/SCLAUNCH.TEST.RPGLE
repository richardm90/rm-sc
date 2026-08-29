**free

//==============================================================================
// SCLAUNCH.TEST - Service launch test suite
//
// Environment assembly and the start command are tested directly, without
// launching anything. Both are worth pinning: an environment that drops $PORT
// breaks any service reading it, and a start command that does not fully
// detach would keep RMSC running for as long as the service does.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCLAUNCH_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCYAML_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-s g_dir like(STMF_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr load_def like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  def     likeds(SCDEF_t);
end-pr;

dcl-pr env_has like(BOOLEAN_t);
  env   likeds(SCLAUNCH_ENV_t) const;
  entry like(SCDEF_ENVVAR_t) const;
end-pr;

dcl-pr remove_fixtures end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-sclaunch-test-' + %trim(psds.current_user);
  IFS_crtdir(g_dir);

end-proc;

dcl-proc tearDownSuite export;

  remove_fixtures();

end-proc;

dcl-proc remove_fixtures;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_dir);
  if dir = *null;
    return;
  endif;

  dow IFS_readdir(dir: filename);
    if %len(filename) > 5
       and %subst(filename: %len(filename) - 4) = '.yaml';
      IFS_remove_file(%trim(g_dir) + '/' + %trim(filename));
    endif;
  enddo;

  IFS_closedir(dir);
  IFS_dltdir(g_dir);
  assert((not IFS_isa_directory(g_dir)):
         'Fixture directory ' + %trim(g_dir) + ' not removed');

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

dcl-proc load_def;
  dcl-pi *n like(BOOLEAN_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
    def     likeds(SCDEF_t);
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);

  path = %trim(g_dir) + '/' + %trim(name);
  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  return SCDEF_load(path: def);

end-proc;

dcl-proc env_has;
  dcl-pi *n like(BOOLEAN_t);
    env   likeds(SCLAUNCH_ENV_t) const;
    entry like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to env.count;
    if %trimr(env.entry(i)) = %trimr(entry);
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// A single port criterion publishes PORT and PORT_PLUS_1..8
//==============================================================================

dcl-proc test_port_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('webproxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/webproxy.log': env);

  nEqual(true: env_has(env: 'PORT=8080'): 'PORT');
  nEqual(true: env_has(env: 'PORT_PLUS_1=8081'): 'PORT_PLUS_1');
  nEqual(true: env_has(env: 'PORT_PLUS_8=8088'): 'PORT_PLUS_8');

end-proc;

//==============================================================================
// Two ports make PORT ambiguous, so it is not published
//==============================================================================

dcl-proc test_no_port_when_ambiguous export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);
  dcl-s  i   like(INTEGER_t);
  dcl-s  found like(BOOLEAN_t) inz(false);

  assert(load_def('twoports.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080,8081' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  for i = 1 to env.count;
    if %len(env.entry(i)) >= 5
       and %subst(env.entry(i): 1: 5) = 'PORT=';
      found = true;
    endif;
  endfor;

  nEqual(false: found: 'no PORT when two ports are declared');

end-proc;

//==============================================================================
// A job-name criterion is not a port, so PORT is not published
//==============================================================================

dcl-proc test_no_port_for_job_criterion export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);
  dcl-s  i   like(INTEGER_t);
  dcl-s  found like(BOOLEAN_t) inz(false);

  assert(load_def('jobonly.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: WEBPROXY' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  for i = 1 to env.count;
    if %len(env.entry(i)) >= 5
       and %subst(env.entry(i): 1: 5) = 'PORT=';
      found = true;
    endif;
  endfor;

  nEqual(false: found: 'no PORT for a job-name criterion');

end-proc;

//==============================================================================
// The SCOMMANDER_ metadata upstream exposes
//==============================================================================

dcl-proc test_scommander_metadata export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('meta.yaml':
    'name: Web Proxy' + LF +
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/meta.log': env);

  nEqual(true: env_has(env: 'SCOMMANDER_LOGFILE=/tmp/meta.log'): 'logfile');
  nEqual(true: env_has(env: 'SCOMMANDER_NAME=meta'): 'short name');
  nEqual(true: env_has(env: 'SCOMMANDER_FRIENDLY_NAME=Web Proxy'): 'friendly name');
  nEqual(true: env_has(env: 'SCOMMANDER_DEFINED_AT=' + %trim(g_dir) +
                            '/meta.yaml'): 'defined at');

end-proc;

//==============================================================================
// A service's own variables are carried through verbatim
//==============================================================================

dcl-proc test_service_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('vars.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- PATH=/QOpenSys/pkgs/bin:/usr/bin' + LF +
    '- LOGLEVEL=debug' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  nEqual(true: env_has(env: 'PATH=/QOpenSys/pkgs/bin:/usr/bin'):
         'colons in a value are preserved');
  nEqual(true: env_has(env: 'LOGLEVEL=debug'): 'second variable');

end-proc;

//==============================================================================
// Variables that describe RMSC's own environment are not passed on
//==============================================================================

dcl-proc test_blocked_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('blocked.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- SHELL=/QOpenSys/pkgs/bin/bash' + LF +
    '- SSH_CLIENT=10.0.0.1 22' + LF +
    '- JAVA_HOME=/QOpenSys/pkgs/lib/jvm' + LF +
    '- LOGLEVEL=debug' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  nEqual(false: env_has(env: 'SHELL=/QOpenSys/pkgs/bin/bash'): 'SHELL dropped');
  nEqual(false: env_has(env: 'SSH_CLIENT=10.0.0.1 22'):
         'SSH_ prefix dropped');
  nEqual(false: env_has(env: 'JAVA_HOME=/QOpenSys/pkgs/lib/jvm'):
         'JAVA_HOME dropped');
  nEqual(true: env_has(env: 'LOGLEVEL=debug'): 'others kept');

end-proc;

//==============================================================================
// The start command detaches
//
// This is the assertion that matters most in this module. Without every part
// of it, RMSC would block for the lifetime of the service it just started.
//==============================================================================

dcl-proc test_start_command_detaches export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd like(SCLAUNCH_CMD_t);

  assert(load_def('detach.yaml':
    'start_cmd: /usr/bin/webproxy --serve' + LF +
    'check_alive: 8080' + LF: def): 'load');

  cmd = SCLAUNCH_start_command(def: '/tmp/detach.log');

  assert((%scan('nohup ': cmd) > 0): 'nohup, so a hangup does not kill it');
  assert((%scan('2>&1': cmd) > 0): 'stderr redirected');
  assert((%scan('< /dev/null': cmd) > 0):
         'stdin detached, or the child holds the caller pipe open');
  aEqualV('&': %subst(cmd: %len(cmd): 1):
          'backgrounded, so the caller returns instead of waiting');
  assert((%scan('/usr/bin/webproxy --serve': cmd) > 0):
         'the command itself is intact');

end-proc;

//==============================================================================
// The start command runs in the service's working directory
//==============================================================================

dcl-proc test_start_command_working_directory export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd like(SCLAUNCH_CMD_t);

  assert(load_def('wd.yaml':
    'start_cmd: ./webproxy' + LF +
    'check_alive: 8080' + LF +
    'dir: /QOpenSys/opt/webproxy' + LF: def): 'load');

  cmd = SCLAUNCH_start_command(def: '/tmp/x.log');

  assert((%scan('cd ''/QOpenSys/opt/webproxy''': cmd) > 0):
         'changes to the working directory first');

end-proc;

//==============================================================================
// Shell quoting
//==============================================================================

dcl-proc test_quoting export;

  aEqualV('''plain''': SCLAUNCH_quote('plain'): 'simple value');
  aEqualV('''has space''': SCLAUNCH_quote('has space'): 'value with a space');
  assert((%scan('\''': SCLAUNCH_quote('it''s')) > 0):
         'an embedded single quote is escaped');

end-proc;

//==============================================================================
// Batch job name derivation
//==============================================================================

dcl-proc test_job_name_from_service export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('web-proxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqualV('WEBPROXY': SCLAUNCH_job_name(def):
          'non-alphanumerics removed, upper-cased');

end-proc;

dcl-proc test_job_name_truncated export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('a-very-long-service-name.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqualV('AVERYLONGS': SCLAUNCH_job_name(def): 'truncated to ten');

end-proc;

dcl-proc test_job_name_explicit export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('explicit.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF +
    'sbmjob_jobname: WEBPROXY' + LF: def): 'load');

  aEqualV('WEBPROXY': SCLAUNCH_job_name(def): 'sbmjob_jobname wins');

end-proc;
