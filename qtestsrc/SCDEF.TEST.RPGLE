**free

//==============================================================================
// SCDEF.TEST - Service definition model test suite
//
// Writes its own fixtures, per user, and removes them afterwards - same
// approach as SCYAML.TEST and for the same reasons. The helper is duplicated
// rather than shared: coupling two suites through a common helper costs more
// than thirty lines of repetition.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

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

dcl-pr remove_fixtures end-pr;

dcl-pr load_fixture like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  def     likeds(SCDEF_t);
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-scdef-test-' + %trim(psds.current_user);
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
// Helper
//==============================================================================

dcl-proc load_fixture;
  dcl-pi *n like(BOOLEAN_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
    def     likeds(SCDEF_t);
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);

  path = %trim(g_dir) + '/' + %trim(name);

  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create fixture ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));

  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  return SCDEF_load(path: def);

end-proc;

//==============================================================================
// aEqualV - compare varying-length values
//
// iRPGUnit's aEqual is declared with opdesc and char(32565) options(*varsize),
// so it takes each argument's length from the operational descriptor. For a
// varying-length ARRAY ELEMENT inside a data structure the descriptor reports
// the wrong length - element N is read with element N-1's length, so
// name(2)='api' comes back as 'ap'. Scalars and procedure return values are
// unaffected, which is why this only shows up on array subscripts.
//
// A plain RPG comparison has no descriptor involved and is correct. This wraps
// it so a failure still reports both values.
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
// Upstream's defaults are applied when the keys are absent
//==============================================================================

dcl-proc test_defaults export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('webproxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  iEqual(60: def.startup_wait: 'startup_wait_time defaults to 60');
  iEqual(45: def.stop_wait: 'stop_wait_time defaults to 45');
  nEqual(true: def.inherit_vars: 'inherits environment by default');
  nEqual(false: def.batch_mode: 'not batch by default');
  nEqual(false: def.has_stop_cmd: 'no stop_cmd');

end-proc;

//==============================================================================
// The short name comes from the file name, and the friendly name falls back
// to it so 'check' always has something to print
//==============================================================================

dcl-proc test_short_and_friendly_name export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('WebProxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqual('webproxy': def.short_name: 'short name from file, lower-cased');
  aEqual('webproxy': def.friendly: 'friendly falls back to short name');

end-proc;

dcl-proc test_friendly_name_given export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('wp2.yaml':
    'name: Web Proxy' + LF +
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqual('Web Proxy': def.friendly: 'friendly name used');

end-proc;

//==============================================================================
// Explicit values override the defaults
//==============================================================================

dcl-proc test_explicit_values export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('explicit.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'stop_cmd: /usr/bin/webproxy -s stop' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 30' + LF +
    'stop_wait_time: 15' + LF +
    'batch_mode: ''true''' + LF +
    'environment_is_inheriting_vars: false' + LF +
    'sbmjob_jobname: WEBPROXY' + LF +
    'sbmjob_opts: JOBQ(QUSRNOMAX)' + LF: def): 'load');

  iEqual(30: def.startup_wait: 'startup_wait_time');
  iEqual(15: def.stop_wait: 'stop_wait_time');
  nEqual(true: def.batch_mode: 'quoted true is batch mode');
  nEqual(false: def.inherit_vars: 'inheritance disabled');
  nEqual(true: def.has_stop_cmd: 'stop_cmd present');
  aEqual('/usr/bin/webproxy -s stop': def.stop_cmd: 'stop_cmd');
  aEqual('WEBPROXY': def.sbmjob_jobname: 'sbmjob_jobname');
  aEqual('JOBQ(QUSRNOMAX)': def.sbmjob_opts: 'sbmjob_opts');

end-proc;

//==============================================================================
// A null stop_cmd is the same as none: fall back to ENDJOB
//==============================================================================

dcl-proc test_null_stop_cmd export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('nullstop.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'stop_cmd: null' + LF +
    'check_alive: 8080' + LF: def): 'load');

  nEqual(false: def.has_stop_cmd: 'null stop_cmd is no stop_cmd');

end-proc;

//==============================================================================
// check_alive is classified by shape
//==============================================================================

dcl-proc test_check_alive_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('port.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');
  iEqual(8080: def.criteria(1).port: 'port value');

end-proc;

dcl-proc test_check_alive_job export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('job.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: webproxy' + LF: def): 'load');

  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'kind is JOB');
  aEqualV('WEBPROXY': def.criteria(1).job_name: 'job name upper-cased');
  aEqualV('': def.criteria(1).subsystem: 'no subsystem');

end-proc;

dcl-proc test_check_alive_subsystem_job export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('sbsjob.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: QUSRWRK/WEBPROXY' + LF: def): 'load');

  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'kind is JOB');
  aEqualV('QUSRWRK': def.criteria(1).subsystem: 'subsystem');
  aEqualV('WEBPROXY': def.criteria(1).job_name: 'job name');

end-proc;

dcl-proc test_check_alive_program export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('pgm.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: PGM-WEBPROXY' + LF: def): 'load');

  aEqualV(SCDEF_CHECK_PGM: def.criteria(1).kind: 'kind is PGM');
  aEqualV('WEBPROXY': def.criteria(1).program: 'program name');

end-proc;

//==============================================================================
// A comma-separated check_alive holds several criteria
//==============================================================================

dcl-proc test_check_alive_comma_separated export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('multi.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: webproxy,8080' + LF: def): 'load');

  iEqual(2: def.criteria_count: 'two criteria');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'first is a job');
  aEqualV('WEBPROXY': def.criteria(1).job_name: 'job name');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(2).kind: 'second is a port');
  iEqual(8080: def.criteria(2).port: 'port');

end-proc;

//==============================================================================
// check_alive may also be a sequence
//==============================================================================

dcl-proc test_check_alive_sequence export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('seq.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive:' + LF +
    '- webproxy' + LF +
    '- 8080' + LF: def): 'load');

  iEqual(2: def.criteria_count: 'two criteria');
  aEqualV('WEBPROXY': def.criteria(1).job_name: 'job name');
  iEqual(8080: def.criteria(2).port: 'port');

end-proc;

//==============================================================================
// The deprecated spelling still works
//==============================================================================

dcl-proc test_check_alive_criteria_alias export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('alias.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive_criteria: 8080' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'alias accepted');
  iEqual(8080: def.criteria(1).port: 'port');

end-proc;

//==============================================================================
// Sequences are loaded, and names normalised to lower case
//==============================================================================

dcl-proc test_sequences export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('seqs.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- PATH=/QOpenSys/pkgs/bin:/usr/bin' + LF +
    '- LOGLEVEL=debug' + LF +
    'service_dependencies:' + LF +
    '- JobRunner' + LF +
    'groups:' + LF +
    '  - Web' + LF +
    '  - autostart' + LF: def): 'load');

  iEqual(2: def.envvar_count: 'two env vars');
  aEqual('PATH=/QOpenSys/pkgs/bin:/usr/bin': def.envvars(1): 'env var kept verbatim');
  iEqual(1: def.dep_count: 'one dependency');
  aEqualV('jobrunner': def.deps(1): 'dependency lower-cased');
  iEqual(2: def.group_count: 'two groups');
  aEqualV('web': def.groups(1): 'group lower-cased');

end-proc;

//==============================================================================
// Group membership, including the implicit 'all'
//==============================================================================

dcl-proc test_group_membership export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('groups.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- web' + LF: def): 'load');

  nEqual(true: SCDEF_in_group(def: 'web'): 'in its own group');
  nEqual(true: SCDEF_in_group(def: 'WEB'): 'group match is case-insensitive');
  nEqual(true: SCDEF_in_group(def: 'all'): 'every service is in all');
  nEqual(false: SCDEF_in_group(def: 'system'): 'not in system');

end-proc;

//==============================================================================
// An unrecognised key is recorded, not fatal
//
// A key added upstream must not stop a definition loading.
//==============================================================================

dcl-proc test_unknown_key_is_not_fatal export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('unknown.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'some_future_key: 42' + LF: def): 'load succeeds');

  iEqual(1: def.unknown_count: 'one unknown key');
  aEqualV('some_future_key': def.unknown(1): 'recorded by name');

end-proc;

//==============================================================================
// A cluster definition is refused, not half-honoured
//
// Starting one backend where the author asked for several would be worse
// than refusing outright.
//==============================================================================

dcl-proc test_cluster_is_rejected export;

  dcl-ds def likeds(SCDEF_t);

  nEqual(false: load_fixture('cluster.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'cluster: 8081,8082' + LF: def): 'load fails');

  nEqual(true: def.is_cluster: 'flagged as cluster');
  assert((%scan('cluster': def.err) > 0): 'error mentions cluster');

end-proc;

//==============================================================================
// The two keys upstream requires
//==============================================================================

dcl-proc test_start_cmd_required export;

  dcl-ds def likeds(SCDEF_t);

  nEqual(false: load_fixture('nostart.yaml':
    'check_alive: 8080' + LF: def): 'load fails');
  assert((%scan('start_cmd': def.err) > 0): 'error names start_cmd');

end-proc;

dcl-proc test_check_alive_required export;

  dcl-ds def likeds(SCDEF_t);

  nEqual(false: load_fixture('nocheck.yaml':
    'start_cmd: /usr/bin/webproxy' + LF: def): 'load fails');
  assert((%scan('check_alive': def.err) > 0): 'error names check_alive');

end-proc;

//==============================================================================
// A non-numeric wait time falls back to the default rather than failing
//==============================================================================

dcl-proc test_bad_wait_time_falls_back export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('badwait.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: soon' + LF: def): 'load still succeeds');

  iEqual(60: def.startup_wait: 'falls back to the default');

end-proc;

//==============================================================================
// The effective working directory
//==============================================================================

dcl-proc test_effective_dir_absolute export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirabs.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'dir: /QOpenSys/opt/webproxy' + LF: def): 'load');

  aEqual('/QOpenSys/opt/webproxy': SCDEF_effective_dir(def): 'absolute dir stands alone');

end-proc;

dcl-proc test_effective_dir_relative export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirrel.yaml':
    'start_cmd: ../../bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'dir: .' + LF: def): 'load');

  aEqual(%trim(g_dir) + '/.': SCDEF_effective_dir(def):
         'relative dir resolves against the definition file');

end-proc;

dcl-proc test_effective_dir_absent export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirnone.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqual(%trim(g_dir): SCDEF_effective_dir(def):
         'no dir means the definition file directory');

end-proc;
