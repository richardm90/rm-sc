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

// Scalar-length block - see SCALAR LENGTH at the foot of this suite
dcl-pr sl_value varchar(2048);
  tag varchar(16) const;
  len like(INTEGER_t) const;
end-pr;

dcl-pr sl_criteria varchar(2048);
  last_len like(INTEGER_t) const;
end-pr;

dcl-pr sl_equal;
  expected varchar(2048) const;
  actual   varchar(2048) const;
  ctx      varchar(64) const;
end-pr;

dcl-pr sl_tail varchar(64);
  v varchar(2048) const;
end-pr;

// Sequence-item length block - see SEQUENCE ITEM LENGTH at the foot of this
// suite
dcl-pr si_item varchar(2048);
  tag varchar(16) const;
  len like(INTEGER_t) const;
end-pr;

// Quoted-value block - see A QUOTED VALUE IS MEASURED BY WHAT IT STORES at the
// foot of this suite. APOS is one apostrophe character; it is written out
// rather than spelled inline because four consecutive quotes in the middle of
// a concatenation is unreadable and easy to miscount.
dcl-c APOS const('''');

dcl-pr qa_value varchar(2048);
  tag varchar(16) const;
  len like(INTEGER_t) const;
end-pr;

dcl-pr qa_doubled varchar(2100);
  v varchar(2048) const;
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
// THE DIRECT FORM DECIDES PORT-OR-JOB BY WHETHER THE VALUE PARSES, NOT BY
// WHETHER IT IS ALL DIGITS
//
// MEASURED against sc 1.7.1, staged definitions read back through sc info,
// with no companion key present - the DIRECT form:
//
//   check_alive: 22                 ->  PORT:22
//   check_alive: 2147483647         ->  PORT:2147483647
//   check_alive: 4294967296         ->  JOBNAME:4294967296
//   check_alive: 99999999999999     ->  JOBNAME:99999999999999
//
// All four LOAD, all four report NOT RUNNING, all four exit 0, and nothing
// reaches stderr for any of them.
//
// THE RULE: in the direct form a value is a PORT only if it is all digits AND
// the number fits a 32-bit signed integer. Anything else is a JOB NAME. That
// is the same parseInt reading the companion form already follows, one layer
// out: upstream tries to read the scalar as a port, and when the read fails
// it falls back to treating the whole thing as a name. It does not fall back
// to crashing.
//
// THE RIVAL IS "ALL DIGITS MEANS A PORT", which is what RMSC does today - and
// having decided that, it converts the text and abends on the way (MCH1210).
// 2147483647 and 4294967296 are what separate the two readings: adjacent in
// magnitude, one apart in kind, and identical in shape. Any rule that gets
// BOTH right is the real rule; a test built from small port numbers agrees
// with both readings and proves nothing at all. They are therefore split
// across two procedures rather than combined into one, so that the abend on
// the second - an ERROR in iRPGUnit, not a failure - cannot take the first
// case's evidence down with it.
//
// NO VALUE HERE IS QUOTED, AND NONE NEEDS TO BE. The header note on YAML
// typing applies to leading zeros, underscores and leading plus signs; these
// four are plain unsigned decimal digits, which YAML 1.1 and RMSC read the
// same way. 2147483647 and 4294967296 differ only in that the second exceeds
// a 32-bit integer, which is the whole point.
//
// Both halves of the outcome are asserted, because they can fail apart: .kind
// says which classification was made, and SCDEF_criterion_text says what the
// definition will RENDER - the measured form above - and a criterion classed
// correctly but rendered from the wrong field would be invisible to .kind
// alone.
//==============================================================================

dcl-proc test_direct_small_number_is_a_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dir22.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 22' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');
  iEqual(22: def.criteria(1).port: 'port value');
  aEqual('PORT:22': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - sc info renders PORT:22');

end-proc;

//------------------------------------------------------------------------------
// The largest value that still parses. One below the boundary, and the half of
// the separating pair that must stay a PORT.
//
// MEASURED: sc info renders PORT:2147483647.
//
// If this one goes red it is not the defect this block is about - it would
// mean .port is narrower than a 32-bit signed integer, which is a different
// finding and should be reported as one rather than folded into the rule.
//------------------------------------------------------------------------------

dcl-proc test_direct_int_max_is_a_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirmax.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 2147483647' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind:
          'int max still parses, so it is still a PORT');
  iEqual(2147483647: def.criteria(1).port: 'the value survives whole');
  aEqual('PORT:2147483647': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - sc info renders PORT:2147483647');

end-proc;

//------------------------------------------------------------------------------
// One step over the boundary, and the classification changes.
//
// MEASURED: sc info renders JOBNAME:4294967296, exit 0, stderr empty.
//
// THE SEPARATING CASE. It is all digits, so the rival reading calls it a port
// and then has to convert 4294967296 into a field that cannot hold it - which
// is where RMSC ends the job with MCH1210 today. Expect an ERROR rather than a
// failure until that is fixed.
//
// .job_name is asserted after .kind, and separately, because a truncating
// name field would fail the second assertion for a reason that has nothing to
// do with the classification - and that would itself be worth knowing.
//------------------------------------------------------------------------------

dcl-proc test_direct_over_int_max_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirover.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 4294967296' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'it does not parse as a port, so it is a JOB NAME - all digits ' +
          'is not enough');
  aEqualV('4294967296': def.criteria(1).job_name:
          'and the name is the digits themselves');
  aEqual('JOBNAME:4294967296': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - sc info renders JOBNAME:4294967296');

end-proc;

//------------------------------------------------------------------------------
// Far over the boundary - wide enough that no plausible port field could hold
// it, so this one cannot be explained away as a field-width accident.
//
// MEASURED: sc info renders JOBNAME:99999999999999, exit 0, stderr empty.
//------------------------------------------------------------------------------

dcl-proc test_direct_long_digits_are_a_job_name export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('dirlong.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 99999999999999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'a JOB NAME');
  aEqual('JOBNAME:99999999999999': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - sc info renders JOBNAME:99999999999999');

end-proc;

//------------------------------------------------------------------------------
// THE CONTROL - the COMPANION form is not touched by any of this
//
// A CONTROL, NOT A DRIVER: it passes today and must keep passing. The direct
// form's fix is a change to how a bare scalar is CLASSIFIED, and the companion
// form's classification comes from the type name instead - so a fix that
// reached into the shared value-handling would break this without breaking
// anything above it.
//
// MEASURED, companion form, same value:
//
//   check_alive: port + check_alive_criteria: 4294967296  ->  PORT:4294967296
//
// so the value that is a JOB NAME in the direct form is still a PORT here, and
// still renders verbatim. It is an UNUSABLE port - nothing can be asked about
// it, and `check` says so and exits 253 - which is asserted where the rest of
// the unusable family lives, in qtestsrc/SCEXEC.TEST.RPGLE. What is asserted
// here is the half SCDEF owns: the kind, the text kept as written, and no
// number invented for it.
//------------------------------------------------------------------------------

dcl-proc test_companion_over_int_max_is_still_a_port export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('compover.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 4294967296' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind:
          'the type name decides, and it says PORT - the same value is a ' +
          'JOB NAME in the direct form');
  aEqualV('4294967296': def.criteria(1).raw: 'the text is kept as written');
  iEqual(0: def.criteria(1).port: 'and no number was invented for it');
  aEqual('PORT:4294967296': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - sc info renders PORT:4294967296, verbatim');

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
// MEASURED - a trailing comma in check_alive loads, with one criterion
//
//   check_alive: rmscrevq1,
//
// abends RMSC (RNX0100). Upstream loads the definition and reports the service
// NOT RUNNING, so the empty element after the comma is absent rather than a
// second, blank criterion.
//
// This is the one of its family that reaches RMSC from a definition FILE
// rather than from a command line, which makes it the likeliest of the set to
// be met in real use - and one service written this way stops the entire walk,
// not just itself.
//
// criteria_count is asserted before criteria(1) is read. A blank second
// criterion is the natural wrong answer here, and reading only the first
// criterion would not notice one.
//==============================================================================

dcl-proc test_check_alive_trailing_comma export;

  dcl-ds def likeds(SCDEF_t);

  assert(load_fixture('trailcomma.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: rmscrevq1,' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion, not two');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'kind is JOB');
  aEqualV('RMSCREVQ1': def.criteria(1).job_name: 'job name, upper-cased');

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
//##  THE COMPANION KEY IS NOT UPPER-CASED                                    ##
//##                                                                          ##
//##############################################################################
//
// MEASURED 4 September against sc 1.7.1, and found by
// tools/gate-fixtures-run.sh on its first ever run - nothing installed on this
// machine names a job through check_alive_criteria, so nothing here could have
// reached it. Written up in docs/messages.md § "Two defects the fixture pack
// found on its first run".
//
//     check_alive: jobname
//     check_alive_criteria: qp0zspwp
//
//     upstream   Check-alive conditions: JOBNAME:qp0zspwp     <- as written
//     RMSC       Check-alive conditions: JOBNAME:QP0ZSPWP     <- upper-cased
//
// THE RENDERING IS THE SMALLER HALF. Because RMSC folds the text, two services
// spelling one job name differently become one criterion, RMSC decides they
// both claim it, and it prints a conflict warning naming services that do not
// conflict - on check, list, groups and info alike. Upstream is silent, because
// to it the two criteria are different. SCCOLL.TEST's compcase case is the
// other half of this; the warning itself is in tools/load-warning-test.sh.
//
// THE SEPARATING VALUE IS THE DIRECT FORM, and it is the reason
// test_criterion_text_direct_job_still_folds below is written out again rather
// than left to test_criterion_text_upper_cases_job:
//
//     RIVAL RULE   "a job name is rendered as written"
//     fits         every companion measurement, exactly
//     wrong        upstream DOES upper-case a job name written straight into
//                  check_alive:, and two services writing one job name in two
//                  cases DO collide there - measured, and recorded in
//                  test_conflicts_case_insensitive in SCCOLL.TEST, which must
//                  keep passing while this is fixed
//
// So the rule is not about job names. It is about WHERE THE VALUE CAME FROM: a
// value that came from check_alive: is folded, one that came from
// check_alive_criteria: is not. Any fix that cannot tell those apart at
// rendering time is fixing the wrong thing, and the two procedures below are
// what say so.
//==============================================================================

dcl-proc test_criterion_text_companion_job_as_written export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptcompjob.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: rmscdefcompjob' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'kind is JOB');
  aEqual('JOBNAME:rmscdefcompjob': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - a job name reached through check_alive_criteria is ' +
         'rendered in the case it was written in');

  // Mixed case, so that a fix which lower-cased instead of upper-casing is
  // caught as well. Nothing here would tell the two apart with an all-lower
  // fixture, and "fold the other way" is the cheapest wrong fix there is.
  assert(pt_load_def('ptcompmix.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: RmScDeFmIxEd' + LF: def): 'load');

  aEqual('JOBNAME:RmScDeFmIxEd': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - mixed case survives intact, so the text is reproduced ' +
         'rather than folded either way');

end-proc;

//==============================================================================
// THE SAME RULE APPLIES TO PORTS, and it is the same rule, not an analogy
//
// MEASURED 4 September against sc 1.7.1, and already recorded at
// docs/parity.md:377. A port written straight into check_alive: is NORMALISED;
// one arriving through check_alive_criteria: is kept VERBATIM:
//
//     check_alive: 08080                                  ->  PORT:8080
//     check_alive: port / check_alive_criteria: 08080      ->  PORT:08080
//
// So the distinction the companion tests above draw for job names is not about
// case, and not about job names. It is about WHICH KEY THE VALUE CAME THROUGH,
// and it shows up in whatever way that type of value can be spelled two ways -
// as case for a job name, and as a leading zero for a port.
//
// THE COMPANION HALF IS ALREADY PINNED, by
// test_criterion_text_unusable_port's 08080 row further down, which was
// measured before any of this. The DIRECT half was not pinned anywhere, and
// that is the gap this closes: with only the companion row, "a port renders
// its text" fits everything and is wrong.
//
// THE CONSEQUENCE IS A MISSING WARNING, not a cosmetic one, and it runs the
// opposite way to the job-name defect. Two services on 08080 and 8080 claim
// ONE criterion upstream and are reported as conflicting; an implementation
// that kept the direct text verbatim would keep them apart and say nothing
// about a collision that is real. test_conflicts_port_zero_padded in
// SCCOLL.TEST is that half.
//
// A LEADING ZERO IS THE SEPARATING VALUE, for the reason
// test_criterion_text_unusable_port already sets out at length: it is the only
// input where the text and the parsed number differ while both exist. 8080
// alone cannot tell "render the text" from "render the number" apart.
//==============================================================================

dcl-proc test_criterion_text_direct_port_normalises export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptdirzero.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 08080' + LF: def): 'load');

  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'a PORT criterion');
  aEqual('PORT:8080': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - a port written into check_alive is NORMALISED, so the ' +
         'leading zero goes; the companion form keeps it, and that is the ' +
         'whole difference between the two keys');

  // The companion, immediately alongside, so the pair reads as one statement
  // rather than as two facts in different parts of the file. Duplicating the
  // 08080 row from test_criterion_text_unusable_port is deliberate: that test
  // is about a criterion that cannot be USED and this one is about which key
  // a value arrived through, and a reader of either should not have to find
  // the other to see the contrast.
  assert(pt_load_def('ptcompzero.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 08080' + LF: def): 'load');

  aEqual('PORT:08080': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - and the companion keeps it verbatim');

end-proc;

//==============================================================================
// THE RIVAL KILLER - the direct form still folds
//
// MEASURED 4 September, the same run: 'check_alive: rmsccjdeadjob' rendered
// JOBNAME:RMSCCJDEADJOB, and two services writing that name in two cases
// produced one conflict warning from upstream.
//
// This passes today. It is here for the direction the companion tests cannot
// cover: a fix that simply stopped upper-casing would satisfy every assertion
// above and would turn off a warning upstream really does print.
//==============================================================================

dcl-proc test_criterion_text_direct_job_still_folds export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptdirjob.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: rmscdefdirjob' + LF: def): 'load');

  aEqual('JOBNAME:RMSCDEFDIRJOB': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - a job name written into check_alive is still folded');

  assert(pt_load_def('ptdirmix.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: RmScDeFdIrEcT' + LF: def): 'load');

  aEqual('JOBNAME:RMSCDEFDIRECT': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - and mixed case is folded there too, which is what makes ' +
         'two spellings of one name a single criterion');

end-proc;

//==============================================================================
// The companion keeps the SHAPE of the value as well as its case
//
// MEASURED 4 September, one service per row, read back through sc info:
//
//     qusrwrk/rmsccmsbsjob    -> JOBNAME:qusrwrk/rmsccmsbsjob
//     pgm-rmsccmpgm           -> JOBNAME:pgm-rmsccmpgm
//     rmsccmseqa,rmsccmseqb   -> JOBNAME:rmsccmseqa,rmsccmseqb
//
// The third row is the one worth having. The companion is NOT split on commas
// - it is one criterion whose text happens to contain one - which is what
// tools/gate-fixtures/isolation/criteria-comma exists to prove out of process,
// and it is asserted here as a COUNT so that a splitter is caught by something
// other than the rendered text. A splitter would render 'JOBNAME:rmsccmseqa'
// for criterion 1 and look almost right.
//
// The first two matter for a smaller reason: the subsystem qualifier and the
// PGM- prefix are the two places where RMSC splits the value up internally,
// and a fix that reassembled the text from the split-out parts would lose the
// case exactly where it is hardest to notice.
//==============================================================================

dcl-proc test_criterion_text_companion_job_shapes export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptcompsbs.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: qusrwrk/rmscdefsbsjob' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('JOBNAME:qusrwrk/rmscdefsbsjob':
         SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - the SBS/JOB form keeps its case on both sides of the ' +
         'slash');

  assert(pt_load_def('ptcomppgm.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: pgm-rmscdefpgm' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqual('JOBNAME:pgm-rmscdefpgm': SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - the PGM- prefix is part of the text and is not folded ' +
         'either');

  assert(pt_load_def('ptcompcomma.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: rmscdefseqa,rmscdefseqb' + LF: def): 'load');

  iEqual(1: def.criteria_count:
         'MEASURED - the companion is ONE criterion, comma and all; it is ' +
         'check_alive that splits on commas, not check_alive_criteria');
  aEqual('JOBNAME:rmscdefseqa,rmscdefseqb':
         SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - and the whole of it is rendered');

end-proc;

//==============================================================================
// The text is rendered in FULL - the criterion is not cut at 64 characters
//
// A THIRD DEFECT, found while measuring the first two on 4 September and not
// part of either. The criterion is carried in a result 64 characters wide, so
// 'JOBNAME:' plus the criterion is cut at 72 - in the DIRECT form as much as
// the companion one, and on the `info` line as much as here.
//
// THE LENGTH HAS TO BE PAST 72 RENDERED CHARACTERS, and the first version of
// this test got that wrong in a way worth recording, because the mistake is
// not obvious and the test looked like coverage while covering nothing.
//
// It was written with twenty- and twenty-three-character job names. Both are
// comfortably below every cap this code has ever had, so it could not fail -
// and it was written against a truncation that had ALREADY BEEN FIXED one
// layer up. A test written after a fix agrees with the code by construction;
// what makes it worth keeping is a value that would have caught the defect,
// and neither of those was one.
//
// THERE HAVE BEEN TWO CAPS, in two different fields, and the difference is
// what a boundary case is for. The first was 56 characters of criterion, from
// a RESULT type 64 wide carrying 'JOBNAME:' as well; that type is now 128. The
// one still measured below is 64 characters of criterion - 72 rendered - which
// is not that field at all but the width the text is STORED in. Widening one
// and not the other is exactly the near-fix that a test carrying a single long
// value reports as "still broken" when what it should report is "the edge
// moved, and here is where it is now".
//
// Measured on 4 September against sc 1.7.1 with three upper-case job names, so
// that only LENGTH varies:
//
//     40 characters  ->  48 rendered   both sides agree
//     64 characters  ->  72 rendered   both sides agree - the exact boundary
//     80 characters  ->  88 rendered   upstream whole, RMSC cut at 72
//
// AND THE EDGE HAS MOVED ONCE SINCE, WHICH IS THE POINT OF SAYING WHERE IT IS.
// SCDEF_CRIT_t is now 128 and a cap survives at exactly that. Re-measured the
// same way:
//
//    118 characters  -> 126 rendered   both sides agree
//    120 characters  -> 128 rendered   both sides agree
//    128 characters  -> 136 rendered   both sides agree - the edge now
//    130 characters  -> 138 upstream, 136 RMSC - cut back to 128
//
// THE 130 IS DELIBERATELY NOT ASSERTED. 128 characters is a LIMIT rather than
// a defect: a *JOB name is 10, an SBS/JOB 21 and a PGM- form 14, so nothing a
// definition can legitimately carry comes within a factor of five of it. A
// test pinning the cut would go red the day somebody widened the field, which
// is the wrong direction to fail in. What is asserted is the side that must
// hold - everything up to 128 survives whole - and the measurement above is
// recorded so the edge is known rather than rediscovered a third time.
//
// So 64 is the largest value that proves nothing, and it is kept below as the
// boundary case: a cap that moved to 72 would pass it and fail the 80. A test
// carrying only the 80 would go red without saying where the edge is.
//
// BOTH VALUES ARE WRITTEN UPPER CASE, INCLUDING THE COMPANION ONE, and that is
// deliberate rather than careless. This row is about LENGTH, and an upper-case
// companion value renders identically whether the folding rule above is
// applied or not - so it stays green through that change and keeps saying only
// the one thing it is for. A lower-case value here would go red for the wrong
// reason and would have to be re-read every time the other rule moved.
//==============================================================================

dcl-proc test_criterion_text_job_not_truncated export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  j64  varchar(256);
  dcl-s  j80  varchar(256);
  dcl-s  j128 varchar(256);

  // Built rather than written out, so the length is stated once and cannot
  // drift from the comment when somebody reflows a literal.
  j64 = 'RMSCDEF' + 'AAAAAAAAAABBBBBBBBBBCCCCCCCCCC' +
                    'DDDDDDDDDDEEEEEEEEEEFFFFFFF';
  j80 = j64 + 'FFFGGGGGGGGGGHHH';

  iEqual(64: %len(j64): 'the boundary value really is 64 characters');
  iEqual(80: %len(j80): 'and the value past it really is 80');

  assert(pt_load_def('ptlong64.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + j64 + LF: def): 'load');

  aEqual('JOBNAME:' + j64: SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - 64 characters render as 72, the exact boundary the old ' +
         '64-wide result could still hold');

  assert(pt_load_def('ptlong80.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + j80 + LF: def): 'load');

  aEqual('JOBNAME:' + j80: SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - and 80 characters render as 88, which no 64- or ' +
         '72-wide result can hold');

  assert(pt_load_def('ptlong80c.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: ' + j80 + LF: def): 'load');

  aEqual('JOBNAME:' + j80: SCDEF_criterion_text(def.criteria(1)):
         'and the companion path is no shorter than the direct one');

  // THE EDGE AS IT STANDS. j64 twice is 128 characters, which is exactly the
  // width of SCDEF_CRIT_t - so this is the largest criterion that survives,
  // and the cheapest possible statement of where the limit sits.
  j128 = j64 + j64;
  iEqual(128: %len(j128): 'the edge value really is 128 characters');

  assert(pt_load_def('ptlong128.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + j128 + LF: def): 'load');

  aEqual('JOBNAME:' + j128: SCDEF_criterion_text(def.criteria(1)):
         'MEASURED - 128 characters render as 136, whole. Past this the ' +
         'value is cut, which is a limit and not a defect - see the header');

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

//##############################################################################
//##                                                                          ##
//##  A 19-DIGIT DIRECT CRITERION STILL ABENDS                                ##
//##                                                                          ##
//##############################################################################
//
// test_direct_over_int_max_is_a_job_name, further up, established the rule:
// upstream treats any all-digit value that does not fit a 32-bit integer as a
// JOB NAME, not a port.
//
//   MEASURED, sc 1.7.1, same box, same day:
//     check_alive: 2147483647   ->  PORT:2147483647
//     check_alive: 4294967296   ->  JOBNAME:4294967296
//
// The fix for that added a guard: values longer than 19 digits are refused
// before they are converted, on the premise that 19 digits always fit. THE
// PREMISE IS FALSE. The widest signed value available holds up to
//
//     9223372036854775807
//
// which is 19 digits - so 19 digits fit only up to that point, and a 19-digit
// value ABOVE it is let through the guard, converted, and overflows with
// MCH1210. That is the same abend the guard was written to remove.
//
// THE RIVAL IS "COUNT THE DIGITS", and it is the natural thing to write when
// the failing values are 10 and 14 digits long: any digit count you pick is
// either short enough to reject values that are perfectly good or long enough
// to admit values that are not. The number does not have a length that decides
// it; it has a VALUE that decides it, and only a conversion that can fail
// safely - or a comparison made before converting - can tell them apart.
//
// FOUR VALUES, chosen so that no single rule about length explains all four:
//
//   9999999999999999999    19 digits, above the maximum   separating
//   -9999999999999999999   the same, negated              separating
//   9223372036854775807    19 digits, exactly the maximum boundary
//   999999999999999999     18 digits, always safe         control
//
// Every one of them is a JOB NAME, because not one of them fits a 32-bit
// integer. The two separating values are expected to abend today; the boundary
// and the control are expected to pass today and to keep passing, and if a fix
// turns either of them into an error it has become a length rule again.
//
// FOUR PROCEDURES, not one. An abend is an ERROR that ends its procedure, so a
// single procedure would report the first value and hide the other three -
// which is exactly how the 19-digit case slipped past the last round.
//
// Nothing here is quoted, and nothing needs to be: these are plain decimal
// digits with at most a leading minus, which YAML 1.1 and RMSC read the same
// way. .kind and SCDEF_criterion_text are asserted separately, as they are
// throughout this suite - a criterion classed correctly but rendered from the
// wrong field would be invisible to .kind alone.
//==============================================================================

//------------------------------------------------------------------------------
// SEPARATING - 19 digits, one field-width short of safe
//
// 9999999999999999999 is greater than 9223372036854775807, so converting it
// overflows. Expect an ERROR (MCH1210) rather than a failure until this is
// fixed.
//------------------------------------------------------------------------------

dcl-proc test_direct_19_digits_over_the_maximum_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('dir19hi.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 9999999999999999999' + LF: def):
    'the definition loads - 19 digits is not a reason to refuse a file');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'it does not fit a 32-bit integer, so it is a JOB NAME - and ' +
          '"19 digits always fit" is false, which is why it abends');
  aEqual('JOBNAME:9999999999999999999': SCDEF_criterion_text(def.criteria(1)):
         'rendered as written, the same way 4294967296 is');

end-proc;

//------------------------------------------------------------------------------
// NOT SEPARATING AFTER ALL - the same value negated
//
// This was written as a second separating case, on the reading that the guard
// might count characters (20, refused) or digits (19, let through and
// overflowing). It came out GREEN on the first run, and the reason turned out
// to have nothing to do with the guard: MEASURED with a throwaway probe,
// 'check_alive: -1' in the direct form already renders JOBNAME:-1. A leading
// sign disqualifies a value from being a port here before any width or digit
// count is consulted, so EVERY negative direct value is a job name and this
// one could never have reached the conversion.
//
// It is kept, because the behaviour is worth pinning and nothing else in the
// suite pins it, but it is NOT evidence about the guard. The case that
// actually separates the two readings is the one below it: 9223372036854775808
// is unsigned, 19 digits, and one above the maximum.
//------------------------------------------------------------------------------

dcl-proc test_direct_19_digits_negative_over_the_maximum_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('dir19neg.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: -9999999999999999999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'below any 32-bit integer, so a JOB NAME');
  aEqual('JOBNAME:-9999999999999999999': SCDEF_criterion_text(def.criteria(1)):
         'rendered as written, sign and all');

end-proc;

//------------------------------------------------------------------------------
// SEPARATING - 19 digits, EXACTLY ONE above the maximum
//
// 9223372036854775808 is the maximum plus one: the smallest unsigned value
// that passes a 19-digit guard and still overflows the conversion. It is the
// tightest statement of the defect there is, and it sits one digit-value away
// from the boundary case below, which must stay green.
//
// A fix that widened the guard to 18 digits would make this green and the
// control red. A fix that compared the value rather than counting its length
// makes all four green. Only the second is right.
//
// Expect an ERROR (MCH1210), not a failure, until it is fixed.
//------------------------------------------------------------------------------

dcl-proc test_direct_19_digits_one_over_the_maximum_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('dir19p1.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 9223372036854775808' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'one past the widest value that converts, and still nowhere near ' +
          'a 32-bit integer - a JOB NAME');
  aEqual('JOBNAME:9223372036854775808': SCDEF_criterion_text(def.criteria(1)):
         'the value one above the maximum renders whole');

end-proc;

//------------------------------------------------------------------------------
// THE BOUNDARY - 19 digits, exactly the largest value that converts
//
// 9223372036854775807 is the top of the widest signed field, so it converts
// without overflowing and is then found not to fit a 32-bit integer, which
// makes it a JOB NAME like the rest.
//
// Expected GREEN today. It is the value that shows the guard's premise is not
// merely too generous but has a real edge: one more digit's worth of value and
// the case above happens.
//------------------------------------------------------------------------------

dcl-proc test_direct_19_digits_at_the_maximum_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('dir19max.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 9223372036854775807' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind:
          'it converts, and then does not fit 32 bits - a JOB NAME');
  aEqual('JOBNAME:9223372036854775807': SCDEF_criterion_text(def.criteria(1)):
         'the exact maximum renders whole');

end-proc;

//------------------------------------------------------------------------------
// THE CONTROL - 18 digits, safe under any reading
//
// Passes today and must keep passing. If a fix makes this red it has stopped
// classifying long digit strings as job names at all.
//------------------------------------------------------------------------------

dcl-proc test_direct_18_digits_is_a_job_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('dir18.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 999999999999999999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_JOB: def.criteria(1).kind: 'a JOB NAME');
  aEqual('JOBNAME:999999999999999999': SCDEF_criterion_text(def.criteria(1)):
         '18 digits is safe under any reading of the guard');

end-proc;

//##############################################################################
//##                                                                          ##
//##  WAIT TIMES - startup_wait_time and stop_wait_time                       ##
//##                                                                          ##
//##############################################################################
//
// MEASURED against sc 1.7.1, startup_wait_time, read back through sc info.
// stop_wait_time behaves identically:
//
//   30              ->  30
//   0               ->  0
//   -5              ->  -5
//   2147483647      ->  2147483647
//   2147483648      ->  -2147483648     upstream WRAPS at 32 bits
//   4294967296      ->  0               wraps
//   99999999999999  ->  276447231       wraps
//   abc             ->  rc=253, the definition is REJECTED, and stderr says
//                       Invalid value specified for attribute
//                       'startup_wait_time'
//
// THE RULE RMSC ADOPTS, decided by the project owner: a wait time RMSC cannot
// use INVALIDATES THE DEFINITION - one rule for both shapes of bad input.
//
//   not a number   ->  reject.  MATCHES upstream.
//   out of range   ->  reject.  DIVERGES from upstream, deliberately: upstream
//                      silently wraps, and turning 4294967296 into a
//                      ZERO-second startup wait is worse than refusing the
//                      file. Nobody writes 4294967296 on purpose.
//
// "Cannot use" means it does not fit a 32-bit signed integer, so the accepted
// range is -2147483648 .. 2147483647 inclusive. NEGATIVE VALUES INSIDE THAT
// RANGE ARE FINE - upstream accepts -5 and so must RMSC. Out of range is not
// the same rule as "too many digits" and not the same rule as "negative".
//
// MEASURED IN RMSC, 5 September 2026, when these tests were first run: RMSC
// ALREADY DIVERGES ON NEGATIVES, before any of this work. Every negative wait
// time - -5, -2147483648, -2147483649 alike - comes back as 60, the default,
// and the definition loads. So "upstream accepts -5 and so must RMSC" is not
// a case that is green today and must stay green; it is a case that is RED
// today and has to be MADE green by whoever implements the rule. It is left
// asserted as the rule states it, per the brief, and reported rather than
// softened.
//
// WHY THE CONTROLS BELOW ARE THE IMPORTANT HALF OF THIS BLOCK. The previous
// fix on this codebase passed every test aimed at it and still broke every
// working case, because no case in the suite asserted that a GOOD value still
// worked. A fix and the break it could have been must disagree about at least
// one case here, so the ordinary values, the zero, the negative and the
// absent keys are all asserted explicitly and not left to test_defaults and
// test_explicit_values to carry.
//
// ONE CASE PER PROCEDURE, deliberately. Several of these values currently
// ABEND rather than reject, and an abend ends the procedure it happens in; if
// two lived together the second would never be reached and would be reported
// as neither red nor green.
//
// WORDING IS NOT ASSERTED, only that a reason was recorded and that it names
// the attribute at fault. Naming it is the whole justification for diverging
// from upstream here - "reporting it beats substituting a nonsense value" is
// only true if the report says which value. The existing rejection tests in
// this suite assert the same way for start_cmd, check_alive and cluster.
//==============================================================================

//------------------------------------------------------------------------------
// THE SEPARATING PAIR - one apart in value, opposite answers
//
// 2147483647 accepted and 2147483648 rejected is the sharpest pair available.
// It rules out "large values are rejected" with the boundary anywhere else -
// at 10 digits, at 1000000, at 2147483646. Any rule that gets BOTH of these
// right is the real rule, and no rule that gets only one of them right is.
//
// They are split across two procedures because the second currently abends.
//------------------------------------------------------------------------------

dcl-proc test_startup_wait_at_32bit_maximum_is_accepted export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtmax.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 2147483647' + LF: def):
    'the largest value that fits 32 bits signed still loads');

  iEqual(2147483647: def.startup_wait:
         'MEASURED - upstream keeps 2147483647 whole, and so must RMSC');

end-proc;

dcl-proc test_startup_wait_one_past_32bit_maximum_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wtmaxp1.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 2147483648' + LF: def):
    'one past the maximum does not fit, so the definition is rejected - ' +
    'upstream wraps this to -2147483648 and RMSC deliberately will not');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('startup_wait_time': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//------------------------------------------------------------------------------
// THE LOWER BOUNDARY - MEASURED, 5 September 2026
//
// The rule is a 32-bit SIGNED range, so it has two ends, and a guard written
// only against the top end is the obvious way to implement it wrongly: -5
// keeps working, 2147483648 is refused, and -2147483649 still abends. Nothing
// else in this block would notice.
//
// These two were written as DERIVED from the stated rule, because the brief
// had measured only the positive end, and were labelled as such rather than
// passed off as observations. The measurement was then taken, and upstream is
// symmetric - it wraps at both ends, exactly as a cast to int does:
//
//     startup_wait_time: -2147483648   ->  -2147483648   fits, accepted
//     startup_wait_time: -2147483649   ->   2147483647   wraps, sign flips
//     startup_wait_time: -4294967296   ->   0
//     startup_wait_time: -99999999999999 -> -276447231
//
// So RMSC diverges identically at both ends, and these assertions rest on an
// observation rather than on an inference from the rule. The label is left in
// its corrected form rather than deleted: whoever reads this next should be
// able to tell that the question was asked.
//
// WHAT THEY MEASURED IN RMSC, 5 September 2026: -2147483648 loads and reports
// 60, and -2147483649 loads too. Neither abends, where the positive values
// past the maximum do - so the negative side is not the same code path with a
// missing sign, it is a path that never converts at all.
//------------------------------------------------------------------------------

dcl-proc test_startup_wait_at_32bit_minimum_is_accepted export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtmin.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: -2147483648' + LF: def):
    'the most negative value that fits 32 bits signed still loads');

  iEqual(-2147483648: def.startup_wait: 'and is kept whole');

end-proc;

dcl-proc test_startup_wait_one_past_32bit_minimum_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wtminm1.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: -2147483649' + LF: def):
    'one past the minimum does not fit either - a guard on the top end ' +
    'alone passes every other case in this block and fails this one');

  assert((%len(def.err) > 0): 'a reason is recorded');

end-proc;

//------------------------------------------------------------------------------
// FURTHER OUT OF RANGE - each of these abends today with MCH1210
//
// 4294967296 is the value the owner's reasoning is built on: upstream turns it
// into a ZERO-second startup wait, which is a service declared dead the
// instant it is asked to start.
//------------------------------------------------------------------------------

dcl-proc test_startup_wait_beyond_32_bits_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wt4g.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 4294967296' + LF: def):
    'rejected - upstream wraps this to 0, which is worse than refusing it');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('startup_wait_time': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

dcl-proc test_startup_wait_far_beyond_32_bits_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wt14d.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 99999999999999' + LF: def):
    'fourteen digits - rejected, where upstream wraps it to 276447231');

  assert((%len(def.err) > 0): 'a reason is recorded');

end-proc;

//------------------------------------------------------------------------------
// The same rule, on the other key
//
// This is what says the rule is about wait times and not about
// startup_wait_time. A fix applied to one reader and not the other passes
// every case above.
//------------------------------------------------------------------------------

dcl-proc test_stop_wait_beyond_32_bits_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wtstop4g.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'stop_wait_time: 4294967296' + LF: def):
    'stop_wait_time is read by the same rule, not a startup-only one');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('stop_wait_time': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//------------------------------------------------------------------------------
// NOT A NUMBER - the half of the rule that MATCHES upstream
//
// This replaces test_bad_wait_time_falls_back, which asserted the behaviour
// being changed: that 'soon' quietly became 60. Under the new rule the file is
// refused instead, and upstream refuses it too - rc=253, "Invalid value
// specified for attribute 'startup_wait_time'". The old test is deleted rather
// than left to fail, so that nothing in the suite still claims the substituted
// default is correct.
//------------------------------------------------------------------------------

dcl-proc test_startup_wait_not_a_number_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wtnan.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: abc' + LF: def):
    'MEASURED - upstream rejects the file rather than substituting 60');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('startup_wait_time': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

dcl-proc test_stop_wait_not_a_number_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  nEqual(false: load_fixture('wtstopnan.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'stop_wait_time: abc' + LF: def):
    'and the same on the other key');

  assert((%len(def.err) > 0): 'a reason is recorded');

end-proc;

//##############################################################################
//##  THE CONTROLS - green today, and green after                             ##
//##############################################################################
//
// Every one of these is a value somebody actually writes. If a fix turns any
// of them red it has not tightened the rule, it has broken the feature: this
// is the group the previous fix on this codebase had nothing to fail against.
//##############################################################################

dcl-proc test_wait_times_ordinary_values_still_work export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtok.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 30' + LF +
    'stop_wait_time: 15' + LF: def): 'an ordinary definition still loads');

  iEqual(30: def.startup_wait: 'startup_wait_time is 30, not the default');
  iEqual(15: def.stop_wait: 'stop_wait_time is 15, not the default');

end-proc;

//------------------------------------------------------------------------------
// ZERO IS NOT MISSING
//
// MEASURED - upstream keeps 0. The rival this rules out is a guard written as
// "if the converted value is zero, use the default", which is the shape a
// conversion that reports failure by returning 0 invites. Both wait times are
// asserted because a zero-means-missing reading would be written once and
// applied to both.
//------------------------------------------------------------------------------

dcl-proc test_wait_times_zero_is_not_missing export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtzero.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 0' + LF +
    'stop_wait_time: 0' + LF: def): 'zero loads');

  iEqual(0: def.startup_wait: 'zero is a value, not an absent key');
  iEqual(0: def.stop_wait: 'and the same on the other key');

end-proc;

//------------------------------------------------------------------------------
// A NEGATIVE VALUE INSIDE THE RANGE IS FINE
//
// MEASURED - upstream accepts -5 and reports -5. This is the case that rules
// out the easiest wrong reading of "cannot use": that a wait time must be
// positive. It is a separate rule from the range rule and RMSC is not adopting
// it.
//------------------------------------------------------------------------------

dcl-proc test_wait_times_negative_in_range_is_kept export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtneg.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: -5' + LF +
    'stop_wait_time: -5' + LF: def):
    'MEASURED - upstream loads this definition, so RMSC must too');

  iEqual(-5: def.startup_wait:
         'MEASURED upstream -5, MEASURED in RMSC today 60 - this control ' +
         'is RED before the change, not after it');
  iEqual(-5: def.stop_wait: 'and the same on the other key');

end-proc;

//------------------------------------------------------------------------------
// The absent keys still take the defaults
//
// test_defaults asserts this too, among six other things. It is repeated here
// on its own so that a fix which loses the defaults says so in one line rather
// than inside a failure about batch_mode or stop_cmd.
//------------------------------------------------------------------------------

dcl-proc test_wait_times_absent_take_the_defaults export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('wtabsent.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  iEqual(60: def.startup_wait: 'startup_wait_time defaults to 60');
  iEqual(45: def.stop_wait: 'stop_wait_time defaults to 45');

end-proc;

//##############################################################################
//##                                                                          ##
//##  SCALAR LENGTH - a value too long to hold invalidates the definition     ##
//##                                                                          ##
//##############################################################################
//
// MEASURED IN RMSC, 5 September 2026, and found by accident: a YAML scalar is
// capped at 1024 characters and is SILENTLY TRUNCATED past it. A check_alive:
// of 1031 characters - eight values of 128 with seven commas - arrived as
// 1024, losing seven characters off the eighth value, and NOTHING reported
// it. criteria_count was still 8, because splitting a truncated string on
// commas still yields eight items, so every structural assertion agreed. Only
// comparing the TEXT found it.
//
// THE RULE RMSC ADOPTS, decided by the project owner: a scalar RMSC cannot
// hold INVALIDATES THE DEFINITION. Same rule and same reasoning as a wait time
// it cannot use - if RMSC cannot represent the value it must not quietly use a
// wrong one. A definition that is not valid is not listed on stdout; it is
// reported on stderr and joins the collection's bad-definition list. What that
// does to the DIRECTORY is pinned in SCCOLL.TEST, not here.
//
// THE LIMIT IS 1024 CHARACTERS for a scalar VALUE.
//
// WHY start_cmd IS THE ONE THAT MATTERS. A check_alive: of a thousand
// characters is a curiosity. A start_cmd: is a real command line, and a real
// one with many arguments can plausibly pass 1024 - today it is cut at 1024
// and THE WRONG COMMAND RUNS. Nothing in the output says so, because a
// truncated command is still a command.
//
// ONE CASE PER PROCEDURE, as in the wait-time block above and for the same
// reason: a failed assertion ends its procedure, so two cases sharing one
// would leave the second dark.
//
// WORDING IS NOT ASSERTED, only that a reason was recorded and that it names
// the attribute at fault - as test_start_cmd_required, test_check_alive_required
// and the wait-time rejections all do.
//##############################################################################

//------------------------------------------------------------------------------
// sl_value - upper-case alphanumeric filler of exactly LEN characters
//
// Upper case so a value written into check_alive: renders identically whether
// the job-name folding rule is applied or not: these cases are about LENGTH
// and must not go red because some other rule moved. The tag is at the front
// so two values differ in their first few characters rather than only past
// several hundred.
//------------------------------------------------------------------------------
dcl-proc sl_value;
  dcl-pi *n varchar(2048);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  dcl-c FILLER const('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
  dcl-s v varchar(2100);

  v = 'RMSCSL' + %trimr(tag);

  dow %len(v) < len;
    v += FILLER;
  enddo;

  return %subst(v: 1: len);

end-proc;

//------------------------------------------------------------------------------
// sl_criteria - eight comma-separated values, the first seven of 128 and the
// eighth of LAST_LEN
//
// 7 x 128 = 896, plus the eighth, plus seven commas. So
//
//     last_len = 121  ->  896 + 121 + 7 = 1024   the largest that must load
//     last_len = 122  ->  896 + 122 + 7 = 1025   one longer, must be refused
//     last_len = 128  ->  896 + 128 + 7 = 1031   the value that started this
//
// EVERY VALUE IS 128 OR SHORTER on purpose. A criterion holds 128 characters,
// so nothing in this block can be cut by the criterion width instead of by
// the scalar cap - the two limits are not allowed to overlap, or a red case
// would not say which of them produced it.
//
// The caller asserts the length rather than trusting this comment.
//------------------------------------------------------------------------------
dcl-proc sl_criteria;
  dcl-pi *n varchar(2048);
    last_len like(INTEGER_t) const;
  end-pi;

  dcl-s ca varchar(2048);
  dcl-s i  like(INTEGER_t);

  for i = 1 to 7;
    if i = 1;
      ca = sl_value('C' + %char(i): 128);
    else;
      ca += ',' + sl_value('C' + %char(i): 128);
    endif;
  endfor;

  ca += ',' + sl_value('C8': last_len);

  return ca;

end-proc;

//------------------------------------------------------------------------------
// sl_equal - compare two values that may be longer than 512 characters
//
// THIS SUITE'S OWN aEqualV IS 512 WIDE. A 1024-character value handed to it
// arrives truncated on BOTH sides, so it would compare two cut strings, find
// them equal, and report as a pass exactly the defect this block exists to
// detect. Do not reach for aEqualV in this block, and do not narrow this.
//
// Reports lengths and tails rather than two thousand-character strings, which
// are unreadable in the RUCALLTST output; the tail is where the difference is.
//------------------------------------------------------------------------------
dcl-proc sl_equal;
  dcl-pi *n;
    expected varchar(2048) const;
    actual   varchar(2048) const;
    ctx      varchar(64) const;
  end-pi;

  if %trimr(expected) = %trimr(actual);
    assert(*on: %trim(ctx));
    return;
  endif;

  assert(*off: %trim(ctx) + ': expected ' + %char(%len(%trimr(expected))) +
               ' chars ending "' + %trim(sl_tail(expected)) + '" but got ' +
               %char(%len(%trimr(actual))) + ' chars ending "' +
               %trim(sl_tail(actual)) + '"');

end-proc;

dcl-proc sl_tail;
  dcl-pi *n varchar(64);
    v varchar(2048) const;
  end-pi;

  dcl-s t varchar(2048);

  t = %trimr(v);
  if %len(t) <= 48;
    return t;
  endif;

  return %subst(t: %len(t) - 47: 48);

end-proc;

//==============================================================================
// THE VALUE THAT STARTED THIS - check_alive of 1031, refused
//
// Eight values of 128 with seven commas. RED today: it loads, seven characters
// short, and says nothing.
//==============================================================================

dcl-proc test_scalar_check_alive_1031_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  ca  varchar(2048);

  ca = sl_criteria(128);
  iEqual(1031: %len(ca): 'eight 128-character values, comma separated');

  nEqual(false: load_fixture('sl1031ca.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: ' + ca + LF: def):
    'a scalar of 1031 does not fit 1024, so the definition is refused - ' +
    'today it loads with the eighth value seven characters short');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('check_alive': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//==============================================================================
// THE ONE THAT MATTERS - start_cmd of 1031, refused
//
// A command line, not a check. Cut at 1024 it is still a runnable command, and
// it is the WRONG one. Nothing downstream can tell.
//==============================================================================

dcl-proc test_scalar_start_cmd_1031_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('SC1031': 1031 - 16);
  iEqual(1031: %len(cmd): 'a command line of 1031 characters');

  nEqual(false: load_fixture('sl1031sc.yaml':
    'start_cmd: ' + cmd + LF +
    'check_alive: 8080' + LF: def):
    'a command RMSC cannot hold whole refuses the definition rather ' +
    'than running a shortened command');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('start_cmd': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//------------------------------------------------------------------------------
// THE SEPARATING PAIR - one character apart, opposite answers
//
// 1031 on its own says only "somewhere at or below 1031". It would pass
// against a rule that refused anything past 200, past 512, past 900 - every
// one of which would refuse ordinary definitions that must keep working. The
// pair below is what puts the boundary in one place:
//
//     1024  ->  ACCEPTED, and the value kept WHOLE
//     1025  ->  REFUSED
//
// Both halves are needed. Accepted-and-whole is the half that a "reject long
// scalars" fix with the boundary too low fails; refused is the half that
// today's silent truncation fails. No rule that gets only one of them right is
// the rule.
//
// WHOLE, not merely accepted. A fix that raised the cap to 1025 and still
// truncated at 1024 would satisfy an assertion that only asked whether the
// definition loaded.
//
// It is written twice, once on check_alive and once on start_cmd, because
// they are different attributes and a cap applied to the YAML reader and a cap
// applied to one field's copy behave identically on one of them and not on the
// other.
//------------------------------------------------------------------------------

dcl-proc test_scalar_check_alive_at_1024_is_accepted_whole export;

  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  ca   varchar(2048);
  dcl-s  v8   varchar(256);

  ca = sl_criteria(121);
  iEqual(1024: %len(ca): 'seven of 128, one of 121, seven commas');

  v8 = sl_value('C8': 121);
  iEqual(121: %len(v8): 'the eighth value really is 121 characters');

  assert(load_fixture('sl1024ca.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: ' + ca + LF: def):
    'exactly 1024 fits, so the definition still loads');

  iEqual(8: def.criteria_count: 'all eight criteria are there');

  // criteria_count is 8 whether the scalar was cut or not - splitting a
  // truncated string on commas still yields eight items - so the TEXT of the
  // last one is the only assertion here that can tell the two apart.
  //
  // SCDEF_criterion_text, not .job_name. MEASURED, 5 September 2026: job_name
  // holds 10 characters, an IBM i job name, and a value of 121 arrives there
  // cut to 10 whether the scalar was capped or not - so an assertion on that
  // field says nothing at all about this rule. The rendered text is where the
  // whole value lives; test_criterion_text_job_not_truncated measures the same
  // thing and uses the same instrument.
  aEqualV(SCDEF_CHECK_JOB: def.criteria(8).kind: 'the eighth is a job name');
  aEqual('JOBNAME:' + v8: SCDEF_criterion_text(def.criteria(8)):
         'and it is whole - this is the assertion the count cannot make');

end-proc;

dcl-proc test_scalar_check_alive_at_1025_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  ca  varchar(2048);

  ca = sl_criteria(122);
  iEqual(1025: %len(ca): 'one character more than the case above');

  nEqual(false: load_fixture('sl1025ca.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: ' + ca + LF: def):
    'one past 1024 does not fit, so the definition is refused');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('check_alive': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

dcl-proc test_scalar_start_cmd_at_1024_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('SC1024': 1024 - 16);
  iEqual(1024: %len(cmd): 'a command line of exactly 1024 characters');

  assert(load_fixture('sl1024sc.yaml':
    'start_cmd: ' + cmd + LF +
    'check_alive: 8080' + LF: def):
    'exactly 1024 fits, so the definition still loads');

  sl_equal(cmd: def.start_cmd:
           'and the command is kept whole, not shortened');

end-proc;

dcl-proc test_scalar_start_cmd_at_1025_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('SC1025': 1025 - 16);
  iEqual(1025: %len(cmd): 'one character more than the case above');

  nEqual(false: load_fixture('sl1025sc.yaml':
    'start_cmd: ' + cmd + LF +
    'check_alive: 8080' + LF: def):
    'one past 1024 does not fit, so the definition is refused');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('start_cmd': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//==============================================================================
// THE CONTROL - long, but nowhere near the cap, and it must still load whole
//
// Green today and after any fix. It rules out the fix that is easiest to get
// wrong in the other direction: a limit put in at 128, or 256, or 512, which
// would refuse every one of these and pass all four rejection cases above.
//
// 200 characters of start_cmd, and a check_alive of two 100-character values.
// Both values are inside the 128 a criterion holds, so nothing here can be cut
// by a width other than the one under test.
//==============================================================================

dcl-proc test_scalar_long_but_within_the_cap_still_loads export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);
  dcl-s  v1  varchar(256);
  dcl-s  v2  varchar(256);

  cmd = '/usr/bin/ptlong ' + sl_value('OK200': 200 - 16);
  v1  = sl_value('OKA': 100);
  v2  = sl_value('OKB': 100);

  iEqual(200: %len(cmd): 'a 200-character command');
  iEqual(201: %len(v1) + 1 + %len(v2): 'and a 201-character check_alive');

  assert(load_fixture('sl200ok.yaml':
    'start_cmd: ' + cmd + LF +
    'check_alive: ' + v1 + ',' + v2 + LF: def):
    'a long definition well inside the cap still loads');

  sl_equal(cmd: def.start_cmd: 'the command is whole');

  iEqual(2: def.criteria_count: 'two criteria');
  aEqual('JOBNAME:' + v1: SCDEF_criterion_text(def.criteria(1)):
         'the first value is whole');
  aEqual('JOBNAME:' + v2: SCDEF_criterion_text(def.criteria(2)):
         'and so is the second');

end-proc;

//##############################################################################
//##                                                                          ##
//##  SEQUENCE ITEM LENGTH - an item too long to hold invalidates the         ##
//##  definition, and the item holder is NOT the scalar holder                ##
//##                                                                          ##
//##############################################################################
//
// The block above pins the `key: value` scalar at 1024. A SEQUENCE ITEM lives
// in a different, SMALLER holder, and the two limits must not be confused:
//
//     a scalar value    key: value        1024
//     a sequence item   a list entry       512
//
// MEASURED IN RMSC, 5 September 2026, by loading definitions of each shape and
// reading back the item that arrived:
//
//   shape                                        written   arrived   reported
//   -----------------------------------------    -------   -------   --------
//   environment_vars: block item                   512       512     loads
//   environment_vars: block item                   513       512     loads
//   environment_vars: block item                  1000       512     loads
//   environment_vars: block item                  1025        -      refused,
//                                "... is longer than 1024 characters"
//   environment_vars: [ flow item ]                512       512     loads
//   environment_vars: [ flow item ]                513       512     loads
//   environment_vars: [ flow item ]               1000       512     loads
//
// So TODAY an item of 513 to 1022 characters is SILENTLY CUT AT 512 in both
// forms, and nothing says so. The block form has a guard, but it is testing
// the scalar's 1024 against a holder of 512 - it cannot fire until the item is
// already twice too long, and when it does fire it names the wrong number. The
// flow form has no item guard at all: the 1025 refusal measured above is the
// KEY LINE's scalar guard firing on `environment_vars: [....]` as a whole,
// which is a different rule reaching the same file by accident. Both leave the
// 513-1022 band unguarded.
//
// THE RULE, the same one the scalar block adopted: an item RMSC cannot hold
// INVALIDATES THE DEFINITION, with a message naming the key and the limit that
// actually applies - 512, not 1024.
//
// WHY environment_vars IS THE KEY THESE CASES USE. Wholeness has to be
// assertable, and it is only assertable on a key whose stored field is as wide
// as the item holder. MEASURED, same day: `def.envvars` elements are 512 wide,
// and `def.groups` and `def.deps` elements are 64. A 400-character group loads
// today and arrives as 64 characters with nothing reported - so an assertion
// on def.groups(n) cannot tell a 512-item cap from a 64-character group field,
// and would go green against either. environment_vars is the one key where the
// item that arrives can be compared with the item that was written.
//
// (That 64 is a THIRD width, below both limits here, and no case in this block
// depends on it either way. It is noted because it is real, not because these
// cases test it.)
//
// THE CONTROL FOR THE OTHER DIRECTION IS ALREADY IN THIS SUITE.
// test_scalar_start_cmd_at_1024_is_accepted_whole and
// test_scalar_check_alive_at_1024_is_accepted_whole both go red the moment a
// fix drags 512 across the scalar path, so they are not written again here.
// test_seq_short_items_both_forms_load_whole below covers the ordinary
// sequence that must keep working.
//
// ONE CASE PER PROCEDURE, as above and for the same reason.
//
// WORDING IS NOT ASSERTED. The key and the NUMBER are: a message that says
// 1024 about a 512-wide holder is the defect, not a phrasing preference.
//##############################################################################

//------------------------------------------------------------------------------
// si_item - filler for one sequence item, exactly LEN characters
//
// Built on sl_value, which is alphanumeric: no comma, so a flow sequence sees
// ONE item and not two, and no leading '-' or '[' to be read as structure.
// Case is irrelevant here - environment_vars is kept verbatim, and the groups
// case asserts only that the definition is refused.
//------------------------------------------------------------------------------
dcl-proc si_item;
  dcl-pi *n varchar(2048);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  return sl_value(tag: len);

end-proc;

//==============================================================================
// THE SEPARATING PAIR, BLOCK FORM - one character apart, opposite answers
//
//     512  ->  ACCEPTED, and the item kept WHOLE
//     513  ->  REFUSED
//
// Accepted-and-whole is the half a fix with the boundary too low fails.
// Refused is the half today's silent cut fails. WHOLE, not merely accepted:
// a truncated item still counts as one item, exactly as a truncated scalar
// still yielded eight criteria, so envvar_count says nothing here and the
// text is the only assertion that can tell them apart.
//==============================================================================

dcl-proc test_seq_item_block_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('B512': 512);
  iEqual(512: %len(it): 'a block sequence item of exactly 512 characters');

  assert(load_fixture('si512b.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- ' + it + LF: def):
    'exactly 512 fits, so the definition still loads');

  iEqual(1: def.envvar_count: 'one item');

  got = def.envvars(1);
  sl_equal(it: got: 'and the item is kept whole');

end-proc;

dcl-proc test_seq_item_block_at_513_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('B513': 513);
  iEqual(513: %len(it): 'one character more than the case above');

  if load_fixture('si513b.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars:' + LF +
       '- ' + it + LF: def);
    // Not nEqual(false: load_fixture(...)): the interesting part of the red is
    // WHAT ARRIVED, and a bare false/true says nothing about the cut.
    got = def.envvars(1);
    assert(*off: 'a block item of 513 does not fit 512, so the definition ' +
                 'must be refused - instead it loaded and the item arrived ' +
                 %char(%len(%trimr(got))) + ' characters, ending "' +
                 %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names the limit that applies to a sequence item, 512');
  assert((%scan('1024': def.err) = 0):
         'and not 1024, which is the scalar limit and not this one');

end-proc;

//==============================================================================
// THE SEPARATING PAIR, FLOW FORM
//
// The same two lengths written the other way. A cap applied to the block
// branch and a cap applied to the item wherever it is read behave identically
// on the block cases above and differently here, which is the whole reason
// both forms are written out.
//
// 512 and 513 are both far inside the 1024 the KEY LINE holds - the value
// `environment_vars: [<512>]` is 514 characters - so nothing in this pair can
// be produced by the scalar guard instead of the item guard.
//==============================================================================

dcl-proc test_seq_item_flow_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('F512': 512);
  iEqual(512: %len(it): 'a flow sequence item of exactly 512 characters');

  assert(load_fixture('si512f.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars: [' + it + ']' + LF: def):
    'exactly 512 fits in flow form too, so the definition still loads');

  iEqual(1: def.envvar_count: 'one item');

  got = def.envvars(1);
  sl_equal(it: got: 'and the item is kept whole');

end-proc;

dcl-proc test_seq_item_flow_at_513_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('F513': 513);
  iEqual(513: %len(it): 'one character more than the case above');

  if load_fixture('si513f.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars: [' + it + ']' + LF: def);
    got = def.envvars(1);
    assert(*off: 'a flow item of 513 does not fit 512, so the definition ' +
                 'must be refused - instead it loaded and the item arrived ' +
                 %char(%len(%trimr(got))) + ' characters, ending "' +
                 %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names the limit that applies to a sequence item, 512');
  assert((%scan('1024': def.err) = 0):
         'and not 1024, which is the scalar limit and not this one');

end-proc;

//==============================================================================
// 1000 - THE LENGTH THAT SAYS WHICH LIMIT WAS APPLIED
//
// Under the scalar's 1024 and over the item's 512. Every other case in this
// block is satisfied by a fix that puts 1024 on the sequence path - 513 would
// still be refused if the boundary were anywhere at or below 513, and 512
// would still load if it were anywhere at or above 512. This one is not: it is
// refused only if the number reached for was 512.
//
// It is also the length where the message matters most. A guard that fires
// here while still reporting "longer than 1024 characters" is reporting
// something the file plainly does not do.
//
// Both forms, for the same reason the pair above is written twice.
//==============================================================================

dcl-proc test_seq_item_block_at_1000_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('B1000': 1000);
  iEqual(1000: %len(it): 'under the scalar limit of 1024, over the item 512');

  if load_fixture('si1000b.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars:' + LF +
       '- ' + it + LF: def);
    got = def.envvars(1);
    assert(*off: 'a block item of 1000 is inside 1024 but far outside 512, ' +
                 'so the definition must be refused - instead it loaded and ' +
                 'the item arrived ' + %char(%len(%trimr(got))) +
                 ' characters, ending "' + %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names 512 - the item limit, which is what 1000 exceeded');
  assert((%scan('1024': def.err) = 0):
         'and not 1024, which 1000 does not exceed');

end-proc;

dcl-proc test_seq_item_flow_at_1000_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('F1000': 1000);
  iEqual(1000: %len(it): 'under the scalar limit of 1024, over the item 512');

  // The whole value is 1002 characters, still inside the 1024 the key line
  // holds, so a refusal here can only have come from the item limit.
  if load_fixture('si1000f.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars: [' + it + ']' + LF: def);
    got = def.envvars(1);
    assert(*off: 'a flow item of 1000 is inside 1024 but far outside 512, ' +
                 'so the definition must be refused - instead it loaded and ' +
                 'the item arrived ' + %char(%len(%trimr(got))) +
                 ' characters, ending "' + %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names 512 - the item limit, which is what 1000 exceeded');
  assert((%scan('1024': def.err) = 0):
         'and not 1024, which 1000 does not exceed');

end-proc;

//==============================================================================
// A SECOND KEY - the rule belongs to sequences, not to one key's copy loop
//
// environment_vars carries every case above because it is the only key whose
// stored field is wide enough to show wholeness. That makes it the one key a
// fix written against these tests would be tempted to guard. groups is a
// sequence too, and it must be refused on the same length.
//
// Only the refusal is asserted. def.groups holds 64 characters, so there is no
// wholeness to assert here and no case in this block pretends otherwise.
//==============================================================================

dcl-proc test_seq_item_groups_block_at_513_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);

  it = si_item('G513': 513);
  iEqual(513: %len(it): 'one past the item limit, on a different key');

  nEqual(false: load_fixture('si513g.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- ' + it + LF: def):
    'the item limit applies to groups as well as to environment_vars');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('groups': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names the limit that applies to a sequence item, 512');

end-proc;

//==============================================================================
// THE CONTROL - ordinary sequences, both forms, must keep loading whole
//
// Green today and after any fix. It is the half that a guard put in at 64, or
// 128, or 256 fails - every one of which would refuse real definitions and
// still pass every rejection case above.
//
// Both forms in one definition, and the values are short enough that none of
// the three widths in play here can be the one that cuts them.
//==============================================================================

dcl-proc test_seq_short_items_both_forms_load_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('sishort.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- PATH=/QOpenSys/pkgs/bin:/usr/bin' + LF +
    '- LOGLEVEL=debug' + LF +
    'groups: [web, autostart]' + LF: def):
    'an ordinary definition with a block and a flow sequence still loads');

  iEqual(2: def.envvar_count: 'two block items');
  got = def.envvars(1);
  sl_equal('PATH=/QOpenSys/pkgs/bin:/usr/bin': got: 'block item 1 whole');
  got = def.envvars(2);
  sl_equal('LOGLEVEL=debug': got: 'block item 2 whole');

  iEqual(2: def.group_count: 'two flow items');
  aEqualV('web': def.groups(1): 'flow item 1 whole');
  aEqualV('autostart': def.groups(2): 'flow item 2 whole');

end-proc;

//##############################################################################
//##                                                                          ##
//##  A QUOTED VALUE IS MEASURED BY WHAT IT STORES, NOT BY WHAT IS WRITTEN    ##
//##                                                                          ##
//##############################################################################
//
// The two blocks above pin the limits and they are not in question here:
//
//     a scalar value    key: value        1024
//     a sequence item   a list entry       512
//
// What is in question is WHICH STRING is measured against them. A YAML value
// can be written quoted, and the quotes are not part of the value - they are
// removed before anything is stored. So a quoted value carries two lengths:
// the RAW text on the line, and the CONTENT that ends up in the field. Only
// the second one has to fit anything.
//
// MEASURED IN RMSC, 5 September 2026, on start_cmd:
//
//   written                                     raw    stored    result
//   ----------------------------------------    ----   ------    --------
//   unquoted, 1023 characters                   1023     1023    loads
//   unquoted, 1024 characters                   1024     1024    loads
//   unquoted, 1025 characters                   1025        -    refused
//   "quoted", 1023 characters inside quotes     1025     1023    REFUSED
//   "quoted", 1024 characters inside quotes     1026     1024    REFUSED
//
// The last two are the defect. Both store a value that fits - 1023 and 1024
// are the two lengths the first two rows prove are acceptable - and both are
// refused because the quote pair was counted against the limit.
//
// WHY IT IS WORSE THAN WHAT IT REPLACED. The guard was put in to stop a value
// too long to hold being silently cut, and that was right. But a silent
// truncation makes a service behave oddly; a false refusal makes a VALID
// service DISAPPEAR - it is not listed, and the row a consumer screen-scrapes
// is not there at all. The guard now does to correct definitions the thing it
// was written to prevent.
//
// THE RULE THESE CASES ARE WRITTEN AGAINST: a value is measured after it is
// unquoted, because what is measured must be what is stored. Nothing else in
// the two blocks above changes, and both limits keep their own number.
//
// THE RIVAL TO RULE OUT IS "ADD TWO TO THE LIMIT". It is the obvious fix - the
// overshoot is exactly the two quote characters - and it is right only while
// unquoting removes exactly two characters. It does not always: a doubled
// apostrophe inside a single-quoted scalar is YAML's one escape there, and it
// stores ONE character for the TWO that were written. So a value can be three,
// four or twenty characters shorter than its raw text. The two apostrophe
// cases below are the ones that separate "measure the content" from "allow two
// more characters", and they are the reason this block does not simply assert
// the quoted limit as 1026.
//
// MEASURED, 5 September 2026, single-quoted values carrying ONE doubled
// apostrophe, loaded and the boundary walked one character at a time:
//
//   stored   between quotes   raw    scalar today    item today
//   ------   --------------   ---    ------------    ----------
//     1019             1020   1022   loads
//     1021             1022   1024   loads
//     1022             1023   1025   REFUSED
//      509              510    512                   loads
//      510              511    513                   REFUSED
//
// So the guard today is exactly "raw > limit", on both holders, and the
// EFFECTIVE limit for such a value is the limit MINUS THREE - two quotes and
// one collapsed apostrophe - not the limit. Add two and it becomes the limit
// minus one, which is still wrong and is wrong by MORE for every further
// apostrophe: a value with twenty of them would be refused twenty characters
// early. The arithmetic is not a constant, which is the finding, and it is why
// the only rule that works is to measure the string that gets stored.
//
// WHAT IS ASSERTED FOR AN ACCEPTED VALUE IS THAT IT IS WHOLE, not merely that
// the definition loaded, for the reason the scalar block already gives: a fix
// that raised a cap without moving the cut satisfies a load-only assertion.
//
// THE FOUR CONTROL CASES COME FIRST, and they are prerequisites rather than
// decoration. Everything below them assumes that RMSC strips quotes at all,
// at both the scalar and the item level and in both sequence forms. If a
// control is red, every length case beneath it is meaningless rather than
// merely failing, and the reader needs to know which of the two it is looking
// at.
//
// THE UNQUOTED CONTROLS ARE ALREADY IN THIS SUITE and are not written again:
// test_scalar_start_cmd_at_1024_is_accepted_whole,
// test_scalar_start_cmd_at_1025_is_rejected,
// test_seq_item_block_at_512_is_accepted_whole and
// test_seq_item_block_at_513_is_rejected are the unquoted halves of the pairs
// below, they are green today, and a fix that flattened the two limits into
// one would take them red.
//
// ONE CASE PER PROCEDURE, as in the blocks above and for the same reason.
//
// 05/09/2026 - RM - written against the defect, before the fix
//##############################################################################

//------------------------------------------------------------------------------
// qa_value - a value of exactly LEN characters containing ONE apostrophe
//
// The apostrophe goes in the middle rather than at either end: at the end it
// would sit against the closing quote, and a value that happened to be handled
// by a rule about the LAST character would look like a value handled by the
// escape rule.
//------------------------------------------------------------------------------
dcl-proc qa_value;
  dcl-pi *n varchar(2048);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  dcl-s v    varchar(2048);
  dcl-s half like(INTEGER_t);

  v    = sl_value(tag: len - 1);
  half = %div(len: 2);

  return %subst(v: 1: half) + APOS + %subst(v: half + 1);

end-proc;

//------------------------------------------------------------------------------
// qa_doubled - the same value written as it must appear INSIDE single quotes
//
// YAML's only escape inside single quotes is the doubled apostrophe, and it
// stands for one literal apostrophe. So the text on the line is longer than
// the value it carries, which is the arithmetic the two apostrophe cases are
// about. SCYAML.TEST already pins the unquoting itself; this only writes it.
//------------------------------------------------------------------------------
dcl-proc qa_doubled;
  dcl-pi *n varchar(2100);
    v varchar(2048) const;
  end-pi;

  dcl-s r varchar(2100);
  dcl-s i like(INTEGER_t);

  for i = 1 to %len(%trimr(v));
    if %subst(v: i: 1) = APOS;
      r += APOS + APOS;
    else;
      r += %subst(v: i: 1);
    endif;
  endfor;

  return r;

end-proc;

//==============================================================================
// CONTROL - a short quoted scalar loads, and loses its quotes
//
// The prerequisite for every scalar case below. Green today. Both spellings in
// one procedure on purpose: neither can fail for a length reason at 200
// characters, so there is nothing here for one assertion to hide from another.
//==============================================================================

dcl-proc test_quoted_short_scalar_loads_unquoted export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('QSHORT': 200 - 16);
  iEqual(200: %len(cmd): 'a 200-character command, far inside every limit');

  assert(load_fixture('qshortd.yaml':
    'start_cmd: "' + cmd + '"' + LF +
    'check_alive: 8080' + LF: def):
    'a double-quoted command loads');

  sl_equal(cmd: def.start_cmd:
           'and what is stored is the CONTENT - the quotes are not part of ' +
           'the value, which is the whole premise of this block');

  clear def;

  assert(load_fixture('qshorts.yaml':
    'start_cmd: ''' + cmd + '''' + LF +
    'check_alive: 8080' + LF: def):
    'and so does a single-quoted one');

  sl_equal(cmd: def.start_cmd: 'stored without its quotes');

end-proc;

//==============================================================================
// CONTROL - short quoted sequence items load, and lose their quotes
//
// The prerequisite for every sequence case below. Green today, in both forms
// and both spellings.
//
// environment_vars, not groups: a group element holds 64 characters, so it
// cannot show wholeness at any length that matters here. The header of the
// SEQUENCE ITEM LENGTH block above measures that and says so.
//==============================================================================

dcl-proc test_quoted_short_seq_items_load_unquoted export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('qishortb.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- "PATH=/QOpenSys/pkgs/bin"' + LF +
    '- ''LOGLEVEL=debug''' + LF: def):
    'a block sequence of quoted items loads');

  iEqual(2: def.envvar_count: 'two block items');
  got = def.envvars(1);
  sl_equal('PATH=/QOpenSys/pkgs/bin': got: 'double-quoted block item unquoted');
  got = def.envvars(2);
  sl_equal('LOGLEVEL=debug': got: 'single-quoted block item unquoted');

  clear def;

  assert(load_fixture('qishortf.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars: ["PATH=/QOpenSys/pkgs/bin", ''LOGLEVEL=debug'']' + LF:
    def):
    'and so does a flow sequence of quoted items');

  iEqual(2: def.envvar_count: 'two flow items');
  got = def.envvars(1);
  sl_equal('PATH=/QOpenSys/pkgs/bin': got: 'double-quoted flow item unquoted');
  got = def.envvars(2);
  sl_equal('LOGLEVEL=debug': got: 'single-quoted flow item unquoted');

end-proc;

//==============================================================================
// THE SCALAR PAIR, DOUBLE QUOTED - 1024 inside the quotes is accepted whole
//
// RED today: the raw text is 1026, the guard reads the raw, and the definition
// is refused. The unquoted 1024 in
// test_scalar_start_cmd_at_1024_is_accepted_whole is the same value and loads,
// which is what makes this a defect rather than a limit.
//==============================================================================

dcl-proc test_scalar_double_quoted_at_1024_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('QD1024': 1024 - 16);
  iEqual(1024: %len(cmd): 'exactly 1024 characters INSIDE the quotes');

  assert(load_fixture('qd1024.yaml':
    'start_cmd: "' + cmd + '"' + LF +
    'check_alive: 8080' + LF: def):
    'the stored value is 1024, which fits, so the definition must load - ' +
    'today the quote pair is counted against the limit and a valid ' +
    'definition disappears');

  sl_equal(cmd: def.start_cmd:
           'and the command is whole, with no quotes in it');

end-proc;

//==============================================================================
// THE OTHER HALF - 1025 inside the quotes is still refused
//
// Green today, and it is the half that a fix of "allow two more characters"
// would keep green while getting the apostrophe case wrong. It is here because
// without it the case above is satisfied by removing the guard altogether.
//==============================================================================

dcl-proc test_scalar_double_quoted_at_1025_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('QD1025': 1025 - 16);
  iEqual(1025: %len(cmd): 'one character more than the case above');

  nEqual(false: load_fixture('qd1025.yaml':
    'start_cmd: "' + cmd + '"' + LF +
    'check_alive: 8080' + LF: def):
    'quoting does not raise the limit - what is stored is 1025 and 1025 ' +
    'does not fit');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('start_cmd': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//==============================================================================
// THE SCALAR PAIR, SINGLE QUOTED
//
// The same two lengths in the other spelling. Written out because a guard
// applied where double quotes are handled and a guard applied where any quoted
// scalar is handled behave identically above and differently here.
//==============================================================================

dcl-proc test_scalar_single_quoted_at_1024_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('QS1024': 1024 - 16);
  iEqual(1024: %len(cmd): 'exactly 1024 characters INSIDE the quotes');

  assert(load_fixture('qs1024.yaml':
    'start_cmd: ''' + cmd + '''' + LF +
    'check_alive: 8080' + LF: def):
    'single quotes are not part of the value either');

  sl_equal(cmd: def.start_cmd: 'and the command is whole');

end-proc;

dcl-proc test_scalar_single_quoted_at_1025_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd varchar(2048);

  cmd = '/usr/bin/ptlong ' + sl_value('QS1025': 1025 - 16);
  iEqual(1025: %len(cmd): 'one character more than the case above');

  nEqual(false: load_fixture('qs1025.yaml':
    'start_cmd: ''' + cmd + '''' + LF +
    'check_alive: 8080' + LF: def):
    'what is stored is 1025, and 1025 does not fit');

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('start_cmd': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//==============================================================================
// THE ARITHMETIC CASE, SCALAR - unquoting removes THREE characters, not two
//
// A single-quoted value with one doubled apostrophe in it. Written: 1025
// characters between the quotes, 1027 on the line. Stored: 1024, because the
// two apostrophes become one.
//
// 1024 is the largest value that fits, so this must load and the stored
// command must have exactly one apostrophe in it.
//
// THIS IS THE CASE THAT SEPARATES THE TWO FIXES. Measure the content and it is
// 1024 and it loads. Allow two more characters than the limit and it is 1027
// against 1026 and it is refused - and the definition that disappears is one
// whose value fits perfectly well. Every other case in this block is satisfied
// by either fix.
//
// The apostrophe is the only escape a single-quoted YAML scalar has, so no
// other spelling of this case exists. A double-quoted scalar has more of them
// - if RMSC ever processes backslash escapes, the same arithmetic applies
// there and with bigger numbers.
//==============================================================================

dcl-proc test_scalar_apostrophe_stored_1024_is_accepted_whole export;

  dcl-ds def   likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd   varchar(2048);
  dcl-s  onwire varchar(2100);

  cmd = qa_value('QA1024': 1024);
  iEqual(1024: %len(cmd): 'the value that gets STORED is exactly 1024');
  assert((%scan(APOS: cmd) > 0): 'and it has an apostrophe in it');
  assert((%scan(APOS + APOS: cmd) = 0):
         'exactly one - the stored value is the unescaped form, and a ' +
         'doubled apostrophe in it would mean the escape was never applied');

  onwire = qa_doubled(cmd);
  iEqual(1025: %len(onwire):
         'written between the quotes it is 1025 - the apostrophe is doubled');

  assert(load_fixture('qa1024.yaml':
    'start_cmd: ''' + onwire + '''' + LF +
    'check_alive: 8080' + LF: def):
    'what is stored is 1024 and 1024 fits, so this must load - a rule of ' +
    '"the limit plus two quotes" refuses it, and refuses a definition ' +
    'whose value is perfectly holdable');

  sl_equal(cmd: def.start_cmd:
           'and the stored command is the UNESCAPED one - a single ' +
           'apostrophe where two were written');

end-proc;

//==============================================================================
// THE ITEM PAIR, BLOCK FORM, DOUBLE QUOTED
//
// The item limit is 512 and it keeps its own number. RED today for the same
// reason as the scalar: the raw item is 514.
//==============================================================================

dcl-proc test_seq_item_block_double_quoted_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QB512': 512);
  iEqual(512: %len(it): 'exactly 512 characters inside the quotes');

  assert(load_fixture('qb512.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- "' + it + '"' + LF: def):
    'the stored item is 512, which fits, so the definition must load');

  iEqual(1: def.envvar_count: 'one item');
  got = def.envvars(1);
  sl_equal(it: got: 'and the item is whole, with no quotes in it');

end-proc;

dcl-proc test_seq_item_block_double_quoted_at_513_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QB513': 513);
  iEqual(513: %len(it): 'one character more than the case above');

  if load_fixture('qb513.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars:' + LF +
       '- "' + it + '"' + LF: def);
    got = def.envvars(1);
    assert(*off: 'quoting does not raise the item limit - what is stored ' +
                 'is 513 and 513 does not fit 512, so the definition must ' +
                 'be refused. Instead it loaded and the item arrived ' +
                 %char(%len(%trimr(got))) + ' characters, ending "' +
                 %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0):
         'and names the item limit, 512');

end-proc;

//==============================================================================
// THE ITEM PAIR, BLOCK FORM, SINGLE QUOTED
//==============================================================================

dcl-proc test_seq_item_block_single_quoted_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QBS512': 512);
  iEqual(512: %len(it): 'exactly 512 characters inside the quotes');

  assert(load_fixture('qbs512.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- ''' + it + '''' + LF: def):
    'the stored item is 512, which fits, so the definition must load');

  iEqual(1: def.envvar_count: 'one item');
  got = def.envvars(1);
  sl_equal(it: got: 'and the item is whole');

end-proc;

//==============================================================================
// THE ITEM PAIR, FLOW FORM
//
// Both spellings again. The whole key line is 516 characters at 512 and 518 at
// 513, so nothing in this pair can be produced by the scalar guard on the key
// line instead of by the item guard - the same argument the unquoted flow pair
// above makes.
//==============================================================================

dcl-proc test_seq_item_flow_double_quoted_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QF512': 512);
  iEqual(512: %len(it): 'exactly 512 characters inside the quotes');

  assert(load_fixture('qf512.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars: ["' + it + '"]' + LF: def):
    'the stored item is 512 in flow form too, so the definition must load');

  iEqual(1: def.envvar_count: 'one item');
  got = def.envvars(1);
  sl_equal(it: got: 'and the item is whole');

end-proc;

dcl-proc test_seq_item_flow_single_quoted_at_512_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QFS512': 512);
  iEqual(512: %len(it): 'exactly 512 characters inside the quotes');

  assert(load_fixture('qfs512.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars: [''' + it + ''']' + LF: def):
    'and single quotes are not part of a flow item either');

  iEqual(1: def.envvar_count: 'one item');
  got = def.envvars(1);
  sl_equal(it: got: 'and the item is whole');

end-proc;

dcl-proc test_seq_item_flow_double_quoted_at_513_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  it  varchar(2048);
  dcl-s  got varchar(2048);

  it = si_item('QF513': 513);
  iEqual(513: %len(it): 'one character more than the case above');

  if load_fixture('qf513.yaml':
       'start_cmd: /usr/bin/webproxy' + LF +
       'check_alive: 8080' + LF +
       'environment_vars: ["' + it + '"]' + LF: def);
    got = def.envvars(1);
    assert(*off: 'what is stored is 513 and 513 does not fit 512, so the ' +
                 'definition must be refused. Instead it loaded and the ' +
                 'item arrived ' + %char(%len(%trimr(got))) +
                 ' characters, ending "' + %trim(sl_tail(got)) + '"');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('environment_vars': def.err) > 0):
         'and the reason names the key at fault');
  assert((%scan('512': def.err) > 0): 'and names the item limit, 512');

end-proc;

//==============================================================================
// THE ARITHMETIC CASE, SEQUENCE ITEM
//
// The same separation as the scalar apostrophe case, against the item's own
// limit: written 513 between the quotes, stored 512, and 512 is what fits.
//
// It is written for the item as well as for the scalar because the two limits
// are enforced in different places - the SEQUENCE ITEM LENGTH block above
// exists because a guard written for the scalar was firing on items with the
// wrong number - and a fix that got the arithmetic right in one place and
// added two in the other would pass whichever of these two was left out.
//==============================================================================

dcl-proc test_seq_item_apostrophe_stored_512_is_accepted_whole export;

  dcl-ds def    likeds(SCDEF_t) inz(*likeds);
  dcl-s  it     varchar(2048);
  dcl-s  onwire varchar(2100);
  dcl-s  got    varchar(2048);

  it = qa_value('QA512': 512);
  iEqual(512: %len(it): 'the item that gets STORED is exactly 512');

  onwire = qa_doubled(it);
  iEqual(513: %len(onwire):
         'written between the quotes it is 513 - the apostrophe is doubled');

  assert(load_fixture('qa512.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- ''' + onwire + '''' + LF: def):
    'what is stored is 512 and 512 fits, so this must load - a rule of ' +
    '"the limit plus two quotes" refuses it');

  iEqual(1: def.envvar_count: 'one item');
  got = def.envvars(1);
  sl_equal(it: got:
           'and the stored item is the UNESCAPED one - a single apostrophe ' +
           'where two were written');

end-proc;
