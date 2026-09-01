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

dcl-pr pt_dir like(STMF_t) end-pr;

dcl-pr pt_load_def like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  def     likeds(SCDEF_t);
end-pr;

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

//==============================================================================
// check_alive_criteria is a VALUE COMPANION, not an alias
//
// The plan called it "a deprecated upstream alias, accepted". It is not.
// Upstream uses it only when check_alive names a *type*, and then it supplies
// that type's value. Measured against sc 1.7.1:
//
//   check_alive: port     + check_alive_criteria: 22        -> PORT:22
//   check_alive: jobname  + check_alive_criteria: QP0ZSPWP  -> JOBNAME:QP0ZSPWP
//   check_alive: port     (no criteria)                     -> JOBNAME:PORT
//   check_alive: wibble   + check_alive_criteria: 22        -> JOBNAME:WIBBLE
//   check_alive: 22       + check_alive_criteria: 99999     -> PORT:22
//   check_alive_criteria: 22   (no check_alive)             -> file discarded
//
// So the type form applies only when BOTH keys are present and the first names
// a type. Reading the second as a fallback spelling of the first - which is
// what RMSC did - turns 'check_alive: port' into a search for a job called
// PORT, and a running service reports NOT RUNNING with no error anywhere.
//==============================================================================

dcl-proc test_criteria_companion_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_port.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 8080' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion, not two');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT, not JOB');
  iEqual(8080: def.criteria(1).port: 'value comes from check_alive_criteria');

end-proc;

dcl-proc test_criteria_companion_jobname export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_job.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: MYJOB' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'kind is JOB');
  aEqualV('MYJOB': def.criteria(1).job_name: 'job name from the companion');

end-proc;

//==============================================================================
// The type wins over the shape of the value
//
// 'jobname' with a numeric value stays a job name. Anything that decided the
// kind by looking at the value would call 12345 a port, and then check the
// wrong thing entirely - the same failure as the alias reading, one layer down.
//==============================================================================

dcl-proc test_criteria_companion_type_beats_shape export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_numjob.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: 12345' + LF: def): 'load');

  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'a numeric job name is still a job name');
  aEqualV('12345': def.criteria(1).job_name: 'job name kept verbatim');

end-proc;

//==============================================================================
// The type name is matched without regard to case
//==============================================================================

dcl-proc test_criteria_companion_type_case export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_upper.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: PORT' + LF +
    'check_alive_criteria: 8080' + LF: def): 'load');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'PORT');

  assert(load_fixture('companion_mixed.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: Port' + LF +
    'check_alive_criteria: 8080' + LF: def): 'load');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'Port');

end-proc;

//==============================================================================
// Without the companion, a type name is just a job name
//
// 'check_alive: port' on its own does NOT invalidate the file upstream, and
// does not mean port either. It means a job called PORT.
//==============================================================================

dcl-proc test_criteria_companion_absent export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_none.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'a job called PORT');
  aEqualV('PORT': def.criteria(1).job_name: 'the word itself');

end-proc;

//==============================================================================
// A check_alive that is not a type name ignores the companion
//==============================================================================

dcl-proc test_criteria_companion_not_a_type export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('companion_value.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'check_alive_criteria: 9999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'the companion adds nothing');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind from check_alive');
  iEqual(8080: def.criteria(1).port: 'value from check_alive, not the companion');

end-proc;

//==============================================================================
// The companion alone is not a definition
//
// check_alive is required. Upstream discards a file carrying only
// check_alive_criteria, with two warning lines on stderr; RMSC accepted it as
// though the key were an alias, which is where the misreading started.
//==============================================================================

dcl-proc test_criteria_companion_alone_is_invalid export;

  dcl-ds def likeds(SCDEF_t);

  nEqual(false: load_fixture('companion_alone.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive_criteria: 8080' + LF: def):
    'a file with no check_alive does not load');

  assert((%scan('check_alive': def.err) > 0):
         'and says which key is missing');

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

// BLOCK 1 - paste into qtestsrc/SCDEF.TEST.RPGLE
//
// Needs, at the top of that suite:
//   /include 'SCDEF_D.rpgleinc'
//   /include 'include/RMIFS_D.rpgleinc'
//   /include 'include/RMTOOLS_D.rpgleinc'   // LF, STRING_t, BOOLEAN_t, INTEGER_t
//   /include 'include/PSDS_D.rpgleinc'
// and these prototypes in the global declarations:
//
//   dcl-pr pt_dir like(STMF_t) end-pr;
//   dcl-pr pt_load_def like(BOOLEAN_t);
//     name    like(STMF_t) const;
//     content like(STRING_t) const;
//     def     likeds(SCDEF_t);
//   end-pr;
//==============================================================================

//------------------------------------------------------------------------------
// pt_dir - a per-user fixture directory, created on demand
//
// Created lazily rather than in setUpSuite so this block can be pasted in
// without editing the suite's existing set-up. Qualified by user because a
// fixed /tmp path belongs to whoever runs the suite first and is created 755,
// so a second user gets read and execute but not write.
//------------------------------------------------------------------------------
dcl-proc pt_dir;
  dcl-pi *n like(STMF_t);
  end-pi;

  dcl-s d like(STMF_t);

  d = '/tmp/rmsc-partial-test-' + %trim(psds.current_user);
  IFS_crtdir(d);          // harmless if it already exists

  return d;

end-proc;

//------------------------------------------------------------------------------
// pt_load_def - write a definition, load it, and remove it again
//
// The fixture is deleted as soon as SCDEF_load has read it, so no test in this
// block leaves state behind and none can depend on a file another test wrote.
// That matters: the suites run under ORDER(*API), not source order.
//
// It asserts rather than returns on a write failure - a suite that cannot
// create its fixture must go red, not quietly test nothing.
//------------------------------------------------------------------------------
dcl-proc pt_load_def;
  dcl-pi *n like(BOOLEAN_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
    def     likeds(SCDEF_t);
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);
  dcl-s ok     like(BOOLEAN_t);

  path = %trim(pt_dir()) + '/' + %trim(name);

  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create fixture ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  ok = SCDEF_load(path: def);

  IFS_remove_file(path);
  IFS_dltdir(pt_dir());   // fails harmlessly if anything else is in there

  return ok;

end-proc;

//==============================================================================
// A port criterion renders PORT:<n>
//
// Captured:
//   PARTIAL (1/2)      | zzsport (Probe zzsport) [not running at -->PORT:55999]
//
// so the port number carries no leading zeros, no padding, and the type name
// is the bare word PORT.
//
// aEqual, not aEqualV: SCDEF_criterion_text returns a value, and
// docs/testing-notes.md records that aEqual's operational descriptors are
// correct for procedure return values and wrong only for varying-length
// ARRAY ELEMENTS. Nothing in this block compares an array element directly.
//==============================================================================

dcl-proc test_criterion_text_port export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptport.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('PORT:55999': SCDEF_criterion_text(def.criteria(1)): 'port criterion');

end-proc;

//==============================================================================
// A plain job name renders JOBNAME:<raw text>
//
// Captured:
//   PARTIAL (1/2)      | zzsjob (Probe zzsjob) [not running at -->JOBNAME:NOSUCHJOB1]
//==============================================================================

dcl-proc test_criterion_text_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptjob.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: NOSUCHJOB1' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('JOBNAME:NOSUCHJOB1': SCDEF_criterion_text(def.criteria(1)):
         'job name criterion');

end-proc;

//==============================================================================
// The SBS/JOB form is part of the job name, not a type of its own
//
// Captured:
//   PARTIAL (1/2)      | zzssbs (Probe zzssbs) [not running at -->JOBNAME:QUSRWRK/NOSUCHJOB2]
//
// The slash form is still JOBNAME:, and the subsystem qualifier survives
// intact. There is no SBS: type upstream, and splitting the value on the
// slash would be a divergence.
//==============================================================================

dcl-proc test_criterion_text_sbs_job export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptsbs.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: QUSRWRK/NOSUCHJOB2' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('JOBNAME:QUSRWRK/NOSUCHJOB2': SCDEF_criterion_text(def.criteria(1)):
         'SBS/JOB criterion keeps the slash form under JOBNAME:');

end-proc;

//==============================================================================
// The PGM- prefix is part of the job name too - there is no PGM: type
//
// Captured:
//   PARTIAL (1/2)      | zzspgm (Probe zzspgm) [not running at -->JOBNAME:PGM-NOSUCHPGM]
//
// This is the one most likely to be got wrong, because RMSC treats PGM- as a
// distinct kind of liveness check internally (SCQRY_jobs_by_pgm). Upstream
// does not name it separately in the suffix: it prints the raw criterion text,
// prefix included, after JOBNAME:.
//==============================================================================

dcl-proc test_criterion_text_pgm_prefix export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptpgm.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: PGM-NOSUCHPGM' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('JOBNAME:PGM-NOSUCHPGM': SCDEF_criterion_text(def.criteria(1)):
         'PGM- criterion is rendered as a job name, prefix and all');

end-proc;

//==============================================================================
// Several criteria render individually, in declaration order
//
// Captured:
//   PARTIAL (1/3)      | zzstwo (Probe two) [not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]
//
// The declared order is what the suffix shows, so criterion N must render as
// itself and not as its neighbour. Each subscript is passed to
// SCDEF_criterion_text and the RESULT compared, so nothing here trips the
// aEqual array-element descriptor bug.
//==============================================================================

dcl-proc test_criterion_text_each_of_several export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptmulti.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55997,55998,NOSUCHJOB3' + LF: def): 'load');

  iEqual(3: def.criteria_count: 'three criteria');
  aEqual('PORT:55997':          SCDEF_criterion_text(def.criteria(1)): 'first');
  aEqual('PORT:55998':          SCDEF_criterion_text(def.criteria(2)): 'second');
  aEqual('JOBNAME:NOSUCHJOB3':  SCDEF_criterion_text(def.criteria(3)): 'third');

end-proc;

//==============================================================================
// INFERRED - the criterion text is reproduced in the case it was written in
//
// Every job name in the captures was already upper case, so none of them
// showed what happens to a lower-case one. Probed on the box afterwards:
//
//   check_alive: lowercasejob     -> [not running at -->JOBNAME:LOWERCASEJOB]
//   check_alive: qusrwrk/lowjob   -> [not running at -->JOBNAME:QUSRWRK/LOWJOB]
//   check_alive: pgm-lowpgm       -> [not running at -->JOBNAME:PGM-LOWPGM]
//   check_alive: '  PADDED  '     -> [not running at -->JOBNAME:PADDED]
//
// Upstream upper-cases and trims the criterion as it parses it, so the suffix
// never shows the case anyone wrote. SCDEF stores the raw text trimmed but NOT
// folded - it upper-cases only the split-out subsystem and job_name fields -
// so rendering straight from raw would diverge on any lower-case definition,
// and nothing on this box defines one.
//==============================================================================

dcl-proc test_criterion_text_upper_cases_job export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptcase.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: PGM-nosuchpgm' + LF: def): 'load');

  aEqual('JOBNAME:PGM-NOSUCHPGM': SCDEF_criterion_text(def.criteria(1)):
         'criterion text is upper-cased, as upstream renders it');

end-proc;

//##############################################################################
//##                                                                          ##
//##  BLOCK C - paste into qtestsrc/SCDEF.TEST.RPGLE                          ##
//##                                                                          ##
//##############################################################################
//
// Two small things the message depends on. They are in SCDEF because
// SCDEF_criterion_text is, and because part 1 of the proposal is a change to
// what SCDEF_load stores.
//
// REUSES load_fixture, already in that suite.
//==============================================================================

//==============================================================================
// The text survives the load, and no number is invented
//
// MEASURED indirectly and strongly: sc info prints "Check-alive conditions:
// PORT:abc" for this definition and exits 0. So upstream keeps the text, and
// has no number for it.
//
// .port is asserted 0 rather than left unasserted because a load that quietly
// stored SOME number would make the criterion look usable to any code that
// checks the field instead of the text - which is how a wrong port gets
// probed with nothing to say so.
//==============================================================================

dcl-proc test_unusable_port_keeps_its_text export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('badport.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def):
    'the definition loads - sc list and sc info are unaffected by one');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind:
          'still a PORT criterion - the type came from check_alive, not ' +
          'from the shape of the value');
  aEqualV('abc': def.criteria(1).raw: 'the text is kept as written');
  iEqual(0: def.criteria(1).port: 'and no number was invented for it');

end-proc;

//==============================================================================
// SCDEF_criterion_text renders the criterion's TEXT - always
//
// MEASURED against sc 1.7.1, 'check_alive: port' with each value, read back
// through sc info:
//
//   criteria=08080   ->  PORT:08080
//   criteria=8080    ->  PORT:8080
//   criteria= 8080   ->  PORT:8080
//   criteria=-1      ->  PORT:-1
//   criteria=abc     ->  PORT:abc
//
// THE RULE IS "ITS TEXT, ALWAYS", not "its text when it cannot be parsed".
// An earlier version of this test had the second rule and expected
// PORT:8080 from 08080. That rule fitted every piece of evidence available
// at the time - PORT:abc has no number to print, so both rules explain it -
// and was still wrong. 08080 is the input that tells them apart, because it
// is the only one where the text and the number differ while both exist.
//
// The distinction is not academic. Under the wrong rule an implementation
// renders from .port whenever .port is set, which is correct for every value
// anybody would normally write and wrong for a leading zero, a value that
// only appears in somebody's YAML months later. Stating the rule as it
// actually is stops the next person reasoning from a rule that merely fits.
//
// A CONSEQUENCE WORTH KNOWING: rendering reads .raw, so a criterion BUILT IN
// CODE rather than parsed renders as 'PORT:' with nothing after it unless
// whoever builds it sets .raw. The ad-hoc 'port:445' specifier is the path
// where that would show, and docs/parity.md already records ad-hoc naming as
// a live difference on the byte-exact check path - so it is worth a look
// while this is being implemented. It is not asserted here because this
// suite tests what SCDEF_load produces, and nothing in it builds a criterion
// by hand.
//
// aEqual and not aEqualV: SCDEF_criterion_text returns a value, and a
// procedure result carries a correct operational descriptor - the array
// element problem in docs/testing-notes.md does not arise.
//==============================================================================

dcl-proc test_criterion_text_unusable_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('badporttext.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load');
  aEqual('PORT:abc': SCDEF_criterion_text(def.criteria(1)):
         'an unusable port renders its text - there is no number to render');

  assert(load_fixture('goodporttext.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 55999' + LF: def): 'load');
  aEqual('PORT:55999': SCDEF_criterion_text(def.criteria(1)):
         'a usable one is unchanged - this is the captured form');

  assert(load_fixture('zeroporttext.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 08080' + LF: def): 'load');
  aEqual('PORT:08080': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - the leading zero survives, so it is the text being ' +
         'rendered and not the parsed number');

  assert(load_fixture('negporttext.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: -1' + LF: def): 'load');
  aEqual('PORT:-1': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - and the sign survives too');

  assert(load_fixture('spaceporttext.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria:  8080' + LF: def): 'load');
  aEqual('PORT:8080': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - surrounding space does NOT survive. Note this is an ' +
         'unquoted scalar, which YAML trims before RMSC sees it, so it ' +
         'does not by itself prove the store trims as well');

end-proc;

//##############################################################################
//##                                                                          ##
//##  WHAT NO TEST ABOVE CAN COVER                                            ##
//##                                                                          ##
//##############################################################################
//
// Four parts of the measured behaviour are outside the ILE job, and iRPGUnit
// runs inside one. They need cases in tools/error-delivery-test.sh, which
// exists for precisely this - "exit status and stdout/stderr routing only
// exist OUTSIDE the ILE job... No assertion in this file is reachable from
// RPG."
//
// Not written here, as asked. What they need:
//
// 1. A FIXTURE, which none of the existing cases needs. Every case in that
//    script today drives whatever is already installed; this one needs a
//    definition written into a directory both implementations read, used, and
//    removed again - with the removal in a trap so an interrupted run does
//    not leave a broken definition behind for everybody's 'sc check'. It has
//    to be invented-named (the repo is public) and it has to be visible to a
//    DEFAULT check, so no groups. Two more alongside it, sorting before and
//    after it, so "the walk continued" is observable.
//
// 2. STREAM AND COUNT, per the script's existing method - stdout and stderr
//    to SEPARATE files, never 2>&1:
//      - stderr holds EXACTLY ONE line for the bad service, with NO message-id
//        prefix. stderr_payload() already strips one, which is what catches
//        the CPF9897 duplication this script was written for.
//      - stdout holds NO row naming the bad service, and DOES hold a row for
//        each of the other two. The CHECK_ROW pattern is already there.
//      - Both implementations, compared to each other: the message text is
//        MEASURED here, unlike every other case in that script, so this is
//        one of the few places the wording can legitimately be diffed rather
//        than only its shape.
//
// 3. POSITION. The stderr line falls in the bad service's SORT POSITION in
//    the walk, which no in-job test can see because the two streams are
//    interleaved only once they leave the job. It needs the two streams
//    merged in order - the one place 2>&1 is correct, and it deserves a
//    comment saying why, since the script's header forbids it everywhere
//    else - and then the merged output compared line for line against
//    upstream's.
//
// 4. EXIT STATUS AND THE MISSING BLANK LINE.
//      - 253, the script's "operational" class, for a bare check with a bad
//        service present, and 253 again for 'check <badservice>' named
//        directly, where stdout is completely EMPTY.
//      - The trailing blank line that ends every check is ABSENT when this
//        happens. That one needs care: the script's BLANK_LINE exemption
//        exists because a check matching nothing prints a blank line and
//        nothing else, and its comment warns explicitly against tightening
//        it. This is the opposite assertion - a blank that must NOT be there
//        - and it should be written as a byte comparison of the whole stdout
//        against upstream's, not as a rule about blank lines, or the two
//        expectations will collide.
//      - Both re-confirmed against sc 1.7.1 in the script's stage 4, so the
//        253 does not go stale underneath the expectation.
//
// One more, for tools/fidelity-gate.sh rather than the error script: its
// byte-exact 'check' stage never sees a bad definition, because it runs
// against what is installed. If the fixture above is made reusable, the gate
// can diff a full check WITH a bad service present - which is the only test
// that would catch the row, the message, the ordering and the missing blank
// line all at once, in the form the consumer actually receives them.
