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
  fieldName varchar(500) const;
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
  ctx      varchar(500) const;
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

// User-text width block - see USER TEXT IS NOT SILENTLY SHORTENED at the
// foot of this suite. ut_lc is the lower-case filler; the upper-case one
// (sl_value) is reused where case cannot matter.
dcl-pr ut_lc varchar(2048);
  tag varchar(16) const;
  len like(INTEGER_t) const;
end-pr;

dcl-pr ut_entry_len like(INTEGER_t);
  prefix varchar(512) const;
end-pr;

dcl-pr ut_drop like(BOOLEAN_t);
  name   like(STMF_t) const;
  prefix varchar(512) const;
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

//------------------------------------------------------------------------------
// A MESSAGE PARAMETER IS A HOLDER TOO, and this one was 64 wide until
// 7 September 2026 - the same defect as the subject of the width block below,
// in the text that reports it.
//
// MEASURED on this box the same day, with a throwaway suite: a 120-character
// value passed to a `varchar(64) const` parameter arrives 64 long, silently,
// and `opdesc` on the prototype does not change that; passed to a
// `varchar(200) const` it arrives whole. So every message longer than the
// parameter had its reasoning cut mid-word, and the cases where that hurt most
// were the ones whose failure text is meant to explain itself.
//
// 500 IS SIZED TO WHAT CAN REACH IT: the longest message written in these
// suites today is 271 characters, and iRPGUnit's own `assert` takes
// `msgIfFalse varchar(16384)`, so nothing downstream cuts what this carries.
//
// BUT iEqual, nEqual AND aEqual CANNOT BE FIXED HERE. Their third parameter is
// declared `fieldName varchar(64)` in iRPGUnit's own TESTCASE copybook, with
// no *varsize, so a longer message is cut at 64 at the call site and no width
// chosen in this repository can change it. Where one of those carries the
// reasoning, THE POINT MUST FIT IN THE FIRST 64 CHARACTERS. Where it will not
// fit, use assert() or one of the helpers here instead.
//------------------------------------------------------------------------------
dcl-proc aEqualV;
  dcl-pi *n;
    expected varchar(512) const;
    actual   varchar(512) const;
    fieldName varchar(500) const;
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
    ctx      varchar(500) const;
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
// Eight values of 128 with seven commas. It was RED when written: the
// definition loaded, seven characters short, and said nothing. It is refused
// now.
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
// It was RED when written: the raw text is 1026, the guard read the raw, and
// the definition was refused. The unquoted 1024 in
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
// The item limit is 512 and it keeps its own number. It was RED when written
// for the same reason as the scalar: the raw item is 514.
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

//##############################################################################
//##                                                                          ##
//##  USER TEXT IS NOT SILENTLY SHORTENED                                     ##
//##                                                                          ##
//##############################################################################
//
// MEASURED, 7 September 2026, against sc 1.7.1 and RMSC side by side. Four
// fields holding text the USER wrote are narrower than the text that can reach
// them, and the excess is cut with nothing reported:
//
//   what was written                    upstream           RMSC
//   --------------------------------    ---------------    -----------------
//   a 100-character file name           name column 100    cut at 64
//   a 200-character `name:`             description 200    cut at 128
//   a 100-character group               kept whole         cut at 64
//   a service_dependencies entry        kept whole         cut at 64
//
// NOTHING IS NEWLY REFUSED BY THIS BLOCK. The scalar cap of 1024 and the
// sequence-item cap of 512 are already in place and already tested above; every
// value here is inside both, so a red case in this block can only be a
// TRUNCATION and never a guard firing. Each field is being widened to the bound
// its SOURCE already has - a file name to 255, a `name:` to the scalar's 1024,
// a group and a dependency to the item's 512 - so that truncation becomes
// impossible rather than merely rarer.
//
// WHOLENESS IS THE ASSERTION, not loading. This is the whole reason the block
// exists and it is worth being blunt about: a truncated name still loads, still
// counts as one service, still has one group and still renders a row. Every
// structural assertion in this suite agrees with the defect. Only comparing the
// TEXT can tell a cut value from a whole one - which is exactly how the 1024
// scalar cap was found, and it is the same lesson twice.
//
// THE PAIRS. Each field gets a value AT the old width, one OVER it, one near
// the new bound, and a short control:
//
//   short_name    64 / 65 / 250      the base name of the file
//   friendly     128 / 129 / 1000    `name:`
//   groups        64 /  65 /  500    one block-sequence item
//   deps          64 /  65 /  500    one block-sequence item
//
// The value AT the old width was green when this block was written and must
// STAY green - it is the half a fix that moves the boundary the wrong way, or
// narrows something on the way past, would fail. The value ONE OVER was red
// and is what separates "handled at every length" from "handled up to 64". The
// value near the new bound was red and is what separates a real widening from
// a boundary nudged by one. The widening has landed and all of them pass.
//
// sl_equal IS THE COMPARATOR, not aEqualV. aEqualV is 512 wide - which is one
// of the boundaries under test - so a 1000-character value handed to it would
// arrive cut on BOTH sides, compare equal, and report the defect as a pass.
// The same argument the scalar block already makes; it applies here with more
// force because 512 is not merely nearby, it is a value this block uses.
//
// WITNESSES THAT WOULD NOT DO, and why they are not used:
//
//   criteria(n).job_name   10 wide - useless for anything past ten characters
//   def.groups(n)          the field under test, so it cannot witness deps
//   def.deps(n)            likewise, so it cannot witness groups
//
// so groups and deps are each measured on themselves and never against one
// another, and every comparison goes through a local varchar(2048).
//
// ONE CASE PER PROCEDURE, as in the blocks above: a failed assertion ends its
// procedure, so two lengths sharing one would leave the second dark.
//##############################################################################

//------------------------------------------------------------------------------
// ut_lc - LOWER-CASE alphanumeric filler of exactly LEN characters
//
// Lower case, where sl_value is upper. Three of the four fields here fold or
// are compared against a folded value:
//
//   short_name   lower-cased from the file name
//   deps         lower-cased
//   groups       lower-cased
//
// so a lower-case fixture value renders identically whether the folding rule is
// applied or not, and these cases stay about LENGTH. It also keeps every file
// name inside the character class upstream's name rule accepts - [a-z0-9_-] -
// so nothing in this block can be rejected for its spelling instead of its
// length. `name:` is kept verbatim and uses sl_value; the case is irrelevant
// there and the upper-case helper already exists.
//
// The tag is at the FRONT, so two values of different lengths differ within
// their first dozen characters rather than only past several hundred.
//------------------------------------------------------------------------------
dcl-proc ut_lc;
  dcl-pi *n varchar(2048);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  dcl-c LCFILL const('abcdefghijklmnopqrstuvwxyz0123456789');
  dcl-s v varchar(2100);

  v = 'rmscut' + %trimr(tag);

  dow %len(v) < len;
    v += LCFILL;
  enddo;

  return %subst(v: 1: len);

end-proc;

//------------------------------------------------------------------------------
// ut_entry_len - the LENGTH of the first fixture directory entry starting with
// PREFIX, or 0 when nothing matches
//
// THE FIXTURE IS VERIFIED BEFORE IT IS TRUSTED, and at 250 characters that is
// not a formality. If a long name were cut on its way to disk the file would
// land under a SHORTER name, and RMSC would then be handed a short name and
// return a short one - which is indistinguishable, by its result, from the
// defect these cases exist to detect. A red result has to mean the defect and
// not a broken fixture, so the length on disk is established first.
//
// The parameter is 512 and not 64 on purpose: a narrow one here would be the
// same mistake the instrument is measuring, and this suite has made it before.
//------------------------------------------------------------------------------
dcl-proc ut_entry_len;
  dcl-pi *n like(INTEGER_t);
    prefix varchar(512) const;
  end-pi;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s found    like(INTEGER_t) inz(0);

  dir = IFS_opendir(g_dir);
  if dir = *null;
    return 0;
  endif;

  dow IFS_readdir(dir: filename);
    if %len(filename) >= %len(prefix)
       and %subst(filename: 1: %len(prefix)) = prefix;
      found = %len(filename);
      leave;
    endif;
  enddo;

  IFS_closedir(dir);

  return found;

end-proc;

//------------------------------------------------------------------------------
// ut_drop - remove one fixture and say whether it really went
//
// FOR THE ONE FIXTURE THIS SUITE'S TEAR-DOWN CANNOT REMOVE. remove_fixtures
// deletes '.yaml' files and nothing else, so the dotless entry below has to
// clear up after itself or IFS_dltdir fails and tearDownSuite reports a second
// failure that says nothing about the case that caused it.
//
// IT MEASURES THE OUTCOME RATHER THAN THE RETURN CODE. Reading the directory
// back answers the question that matters - is the entry gone - and answers it
// the same way whatever IFS_remove_file reports.
//------------------------------------------------------------------------------
dcl-proc ut_drop;
  dcl-pi *n like(BOOLEAN_t);
    name   like(STMF_t) const;
    prefix varchar(512) const;
  end-pi;

  IFS_remove_file(%trim(g_dir) + '/' + %trim(name));

  return (ut_entry_len(prefix) = 0);

end-proc;

//==============================================================================
// SHORT NAME - the base name of the file, at 64, 65, 127, 128 and 250
//
// `name:` is written SHORT in every one of these, and deliberately. The
// friendly name falls back to the short name when the key is absent, so a long
// file name with no `name:` would exercise two fields at once and a red result
// could not say which of them cut the value. Here only short_name is long.
//
// 250 IS THE LARGEST A '.yaml' FILE CAN CARRY. Measured on this box, and
// measured again on 7 September 2026: the IFS accepts a file name of 255
// characters and refuses 256, so 250 + '.yaml' is exactly at the limit. (A
// '.yml' file can carry 251, which SCCOLL.TEST covers on real directory
// entries - see the note there. This suite cannot: its tear-down removes
// '.yaml' files only, so a '.yml' fixture would be left behind and the
// directory would not go.)
//
// THERE WERE TWO DEFECTS HERE, NOT ONE, THEY LIVED IN DIFFERENT REPOSITORIES,
// AND BOTH ARE NOW FIXED. Measured by loading one definition per base-name
// length, 113 to 130 and then in steps to 250, and reading back
// %len(def.short_name):
//
//     base name   short name, before       short name, now
//     ---------   ----------------------   ---------------
//        64 - 127   64       truncated     whole   <- RMSC's own holder
//       128 - 250    0       GONE          whole   <- rmtools
//
// THE SECOND ONE IN FULL, because the shape of it is worth keeping.
// PATH_BASENAME_t was varchar(128). A file name of 133 characters truncated to
// 128, which dropped the '.yaml' off the end; the scanr for the dot then
// returned 0, %subst(basename: 1: pos - 1) became %subst(x: 1: -1) and raised,
// and a MONITOR swallowed it into ''. So the name did not shorten, it
// disappeared - which is why the old boundary was a base name of 127 and not
// 128, and why it was 127 for '.yml' as well as for '.yaml'.
//
// rmtools 2.0.7, released 7 September 2026, widened PATH_BASENAME_t to
// varchar(255) and replaced the MONITOR with a `pos > 0` guard, so a name with
// no dot in it now returns the base name rather than an empty string. RMSC's
// own holder is 512, so every base name the IFS can hold arrives whole.
//
// UNTIL THAT LANDED THE CASES PAST 127 WERE MARKERS, not expectations. They
// were named ..._blocked_on_rmtools and they asserted the EMPTY name that
// really came back, in the idiom tools/error-delivery-test.sh calls `pinned`.
// Two reasons, and both still apply to the next thing that has to be written
// this way: tools/verify.sh reports one verdict, and a suite red for months
// waiting on another repository trains everyone to wave through the next red;
// and a marker written this way goes RED the day the fix arrives and says in
// its own failure text what to change it to. These did, on 7 September 2026,
// and this is what they were changed to. Nobody had to remember.
//
// EVERY CASE PROVES ITS FIXTURE FIRST. A case that passed because its file was
// never written would be the worst of both worlds - it reports success and
// measures nothing - so ut_entry_len establishes the name really is on disk at
// its full length before anything is concluded from what came back.
//
// 127 IS STILL THE CASE THAT GUARDS THE BAND RMSC OWNS. It is the largest name
// our own widening had to handle, and without it a fix that went from 64 to
// 100 would turn 65 green and leave nothing to catch it - every other real
// case here is at or below 65.
//==============================================================================

dcl-proc test_short_name_at_64_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);
  dcl-s  got varchar(2048);

  nm = ut_lc('sn64': 64);
  iEqual(64: %len(nm): 'a base name of exactly 64 characters');

  assert(load_fixture(nm + '.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 64-character file name still loads');

  got = def.short_name;
  sl_equal(nm: got:
           'the short name is whole at 64 - the OLD width, so this is the ' +
           'half a fix that moves the boundary the wrong way fails');

end-proc;

dcl-proc test_short_name_at_65_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);
  dcl-s  got varchar(2048);

  nm = ut_lc('sn65': 65);
  iEqual(65: %len(nm): 'one character more than the case above');

  assert(load_fixture(nm + '.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 65-character file name still loads');

  iEqual(70: ut_entry_len('rmscutsn65'):
         'the fixture really did land on disk with all 65 characters and ' +
         'its extension - without this a red below could be a broken ' +
         'fixture rather than the defect');

  got = def.short_name;
  sl_equal(nm: got:
           'the short name is whole at 65 - the first length RMSC''s own ' +
           '64-wide holder used to cut, and it cut it silently');

end-proc;

dcl-proc test_short_name_at_127_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);
  dcl-s  got varchar(2048);

  nm = ut_lc('sn127': 127);
  iEqual(127: %len(nm):
         'the largest base name the OLD rmtools could hand back whole - one ' +
         'more and the dot did not survive its 128-character cut');

  assert(load_fixture(nm + '.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 127-character file name still loads');

  iEqual(132: ut_entry_len('rmscutsn127'):
         'the fixture really did land on disk as 127 characters of base ' +
         'name and five of extension');

  got = def.short_name;
  sl_equal(nm: got:
           'the short name is whole at 127 - the TOP of the band RMSC ' +
           'owns, and the case a widening that went to 100 rather than 255 ' +
           'would fail while every other real case here went green');

end-proc;

dcl-proc test_short_name_at_128_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);
  dcl-s  got varchar(2048);

  nm = ut_lc('sn128': 128);
  iEqual(128: %len(nm):
         'one character past the last name the old PATH_BASENAME_t could ' +
         'hand back with its dot intact');

  assert(load_fixture(nm + '.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 128-character file name loads - it always did, and that was the ' +
    'trouble: it loaded with no name and said nothing');

  iEqual(133: ut_entry_len('rmscutsn128'):
         'the fixture really did land on disk as 128 characters of base ' +
         'name and five of extension - a case that passed because its ' +
         'file was never written would measure nothing');

  got = def.short_name;
  sl_equal(nm: got:
           'whole at 128 - the first length that came back EMPTY until ' +
           'rmtools 2.0.7 widened PATH_BASENAME_t');

end-proc;

dcl-proc test_short_name_at_250_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);
  dcl-s  got varchar(2048);

  nm = ut_lc('sn250': 250);
  iEqual(250: %len(nm): 'the longest base name a .yaml file can carry');

  assert(load_fixture(nm + '.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'the longest file name the IFS will hold still loads');

  iEqual(255: ut_entry_len('rmscutsn250'):
         'the fixture really did land on disk as 255 characters - 250 of ' +
         'base name and five of extension');

  got = def.short_name;
  sl_equal(nm: got:
           'whole at 250 - kept alongside 128 because 128 was the old ' +
           'boundary and 250 is the ceiling, and a partial fix could have ' +
           'moved one without the other. The 251 a .yml file can carry is ' +
           'in SCCOLL.TEST, on a real directory entry');

end-proc;

dcl-proc test_short_name_ordinary_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('rmscut_ordinary.yaml':
    'name: probe' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'an ordinary file name still loads');

  got = def.short_name;
  sl_equal('rmscut_ordinary': got:
           'THE CONTROL - an everyday name is untouched, which a widening ' +
           'that broke the lower-casing or the extension strip would fail');

end-proc;

//==============================================================================
// AND ONE ENTRY LONGER THAN ANY DEFINITION FILE CAN BE - 255, WITH NO DOT
//
// THE QUESTION THIS ANSWERS IS "IS ANYTHING ABOVE 251 REACHABLE?", asked when
// rmtools 2.0.7 landed. Measured on this box, 7 September 2026, by creating
// files of 250, 251, 252, 255 and 256 characters: the IFS accepts 255 and
// refuses 256 with ENAMETOOLONG. A definition file must end '.yaml' or '.yml',
// which is five characters or four, so the longest base name a definition file
// can have is 250 or 251 and there is no way to make it 252. Those two cases
// are covered above and in SCCOLL.TEST.
//
// A 255-character entry with NO extension is the one thing above 251 that can
// be built, and SCDEF_load is the only door it can come through - a directory
// walk selects by extension, so SCCOLL cannot see it. It is written because
// the same rmtools change that widened the holder also replaced the MONITOR
// with a `pos > 0` guard, and the dotless name is precisely the input that
// guard exists for: no dot, so nothing to strip, and before the fix that path
// raised into an empty string.
//
// IF SCDEF_load IS EVER GIVEN AN EXTENSION RULE OF ITS OWN, this case should
// be changed to assert the REFUSAL rather than deleted. That it accepts a
// dotless file today is measured, not assumed - the nEqual below is what
// measures it - but it is a decision nobody in this repository has taken
// deliberately, and the length is the only thing here that could not be
// re-covered somewhere else.
//
// IT REMOVES ITS OWN FIXTURE ON EVERY PATH, INCLUDING THE ONE WHERE THE LOAD
// RAISES. This suite's tear-down deletes '.yaml' files and nothing else, so a
// dotless file left in the directory makes IFS_dltdir fail and turns
// tearDownSuite red - a second failure, in another place, saying nothing about
// this one.
//
// AN UNCONDITIONAL REMOVAL AFTER THE CALL IS NOT ENOUGH, and that is the whole
// reason for the MONITOR. A dotless name is exactly the input that raised
// before rmtools 2.0.7 - no dot, so the old code took %subst(x: 1: -1) - and
// if SCDEF_load escapes rather than returning, a removal written after it
// never runs. The case that exists to survive an older rmtools would then take
// the tear-down down with it. So the load sits in a MONITOR, the removal is in
// the on-error as well as on the normal path, and everything is asserted
// afterwards from variables.
//
// THE REMOVAL IS CHECKED BY READING THE DIRECTORY BACK, not by trusting a
// return code - see ut_drop. An assertion that the fixture went is cheap, and
// without it the only report of a failed removal is the misleading one in
// tearDownSuite.
//==============================================================================

dcl-proc test_short_name_dotless_at_255_is_whole export;

  dcl-ds def    likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm     varchar(2048);
  dcl-s  got    varchar(2048);
  dcl-s  loaded like(BOOLEAN_t) inz(*off);
  dcl-s  raised like(BOOLEAN_t) inz(*off);
  dcl-s  gone   like(BOOLEAN_t) inz(*off);
  dcl-s  ondisk like(INTEGER_t) inz(0);

  nm = ut_lc('dot255': 255);

  monitor;
    loaded = load_fixture(nm:
      'name: probe' + LF +
      'start_cmd: /usr/bin/rmscut' + LF +
      'check_alive: 8080' + LF: def);
    got = def.short_name;
  on-error;
    raised = *on;
  endmon;

  ondisk = ut_entry_len('rmscutdot255');
  gone   = ut_drop(nm: 'rmscutdot255');

  iEqual(255: %len(nm):
         'the longest entry the IFS will hold, and four characters longer ' +
         'than any name a .yml definition file can have');

  iEqual(255: ondisk:
         'the fixture really did land on disk at 255 characters - without ' +
         'this a short answer below could be a short file name');

  assert(gone:
         'the 255-character fixture is off disk again. This suite''s ' +
         'tear-down removes ''.yaml'' files only, so a leftover would fail ' +
         'IFS_dltdir and report a second failure in tearDownSuite that says ' +
         'nothing about this case');

  assert((not raised):
         'SCDEF_load RETURNED rather than raising on a name with no dot in ' +
         'it. That is what the pos > 0 guard added in rmtools 2.0.7 is for: ' +
         'before it, the basename extraction did %subst(x: 1: -1) on a ' +
         'dotless name and escaped once the MONITOR that swallowed it came ' +
         'out. If this is red, the build is against an rmtools older than ' +
         '2.0.7 - and the fixture has still been removed');

  // assert, not nEqual: iRPGUnit cuts nEqual's message at 64 and the point of
  // this one is past that. See the note above aEqualV.
  assert(loaded:
         'a file with no extension is still a definition when it is handed ' +
         'to SCDEF_load by name - the extension rule belongs to the ' +
         'directory walk, not to this. If this is red, SCDEF_load has ' +
         'gained an extension rule of its own and this case should assert ' +
         'the REFUSAL rather than be deleted');

  sl_equal(nm: got:
           'and its short name is the whole 255 - no dot to strip, which is ' +
           'the input the new pos > 0 guard exists for');

end-proc;


//==============================================================================
// FRIENDLY NAME - `name:`, at 128, 129 and 1000
//
// 1000 is inside the 1024 a scalar holds, so nothing here can be the scalar
// guard firing. test_scalar_long_but_within_the_cap_still_loads above already
// pins that a 200-character value loads; this is about what ARRIVES.
//==============================================================================

dcl-proc test_friendly_at_128_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  fv  varchar(2048);
  dcl-s  got varchar(2048);

  fv = sl_value('FR128': 128);
  iEqual(128: %len(fv): 'a name: of exactly 128 characters');

  assert(load_fixture('utfr128.yaml':
    'name: ' + fv + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 128-character name: still loads');

  got = def.friendly;
  sl_equal(fv: got:
           'the friendly name is whole at 128 - the width it has today');

end-proc;

dcl-proc test_friendly_at_129_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  fv  varchar(2048);
  dcl-s  got varchar(2048);

  fv = sl_value('FR129': 129);
  iEqual(129: %len(fv): 'one character more than the case above');

  assert(load_fixture('utfr129.yaml':
    'name: ' + fv + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a 129-character name: still loads');

  got = def.friendly;
  sl_equal(fv: got:
           'the friendly name is whole at 129 - today it arrives 128 ' +
           'characters long and the description printed by check is short ' +
           'by one, silently');

end-proc;

dcl-proc test_friendly_at_1000_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  fv  varchar(2048);
  dcl-s  got varchar(2048);

  fv = sl_value('FR1000': 1000);
  iEqual(1000: %len(fv): 'inside the 1024 a scalar holds, far past 128');

  assert(load_fixture('utfr1000.yaml':
    'name: ' + fv + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'a name: of 1000 is inside the scalar cap, so it must still load - a ' +
    'refusal here would be the scalar guard firing on a value it does not ' +
    'cover');

  got = def.friendly;
  sl_equal(fv: got:
           'and it arrives whole - 1000 is what separates a widening to the ' +
           'scalar bound from one to 256 or 512');

end-proc;

dcl-proc test_friendly_ordinary_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('utfrshort.yaml':
    'name: Web Proxy (staging)' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'an ordinary name: still loads');

  got = def.friendly;
  sl_equal('Web Proxy (staging)': got:
           'THE CONTROL - an everyday description is kept verbatim, spaces, ' +
           'brackets, mixed case and all');

end-proc;

//==============================================================================
// GROUPS - one block-sequence item, at 64, 65 and 500
//
// 500 is inside the 512 an item holds, so a refusal at 500 would be the item
// guard firing on a value it does not cover - which is why 500 and not 513.
// test_seq_item_groups_block_at_513_is_rejected above owns the other side of
// that boundary and this block does not touch it.
//
// def.deps IS NOT USED AS A WITNESS HERE. It is the same holder and the same
// defect, so a dependency that agreed with a group would prove only that the
// two were cut alike.
//==============================================================================

dcl-proc test_group_at_64_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  gv  varchar(2048);
  dcl-s  got varchar(2048);

  gv = ut_lc('gr64': 64);
  iEqual(64: %len(gv): 'a group of exactly 64 characters');

  assert(load_fixture('utgr64.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- ' + gv + LF: def): 'a 64-character group still loads');

  iEqual(1: def.group_count: 'one group');

  got = def.groups(1);
  sl_equal(gv: got: 'the group is whole at 64 - the width it has today');

end-proc;

dcl-proc test_group_at_65_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  gv  varchar(2048);
  dcl-s  got varchar(2048);

  gv = ut_lc('gr65': 65);
  iEqual(65: %len(gv): 'one character more than the case above');

  assert(load_fixture('utgr65.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- ' + gv + LF: def): 'a 65-character group still loads');

  iEqual(1: def.group_count:
         'one group - and the count says nothing about its length, which is ' +
         'the whole reason the text is compared below');

  got = def.groups(1);
  sl_equal(gv: got:
           'the group is whole at 65 - today it arrives 64 characters long, ' +
           'so two groups differing only past 64 become one');

end-proc;

dcl-proc test_group_at_500_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  gv  varchar(2048);
  dcl-s  got varchar(2048);

  gv = ut_lc('gr500': 500);
  iEqual(500: %len(gv): 'inside the 512 a sequence item holds, far past 64');

  assert(load_fixture('utgr500.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- ' + gv + LF: def):
    'a group of 500 is inside the item cap, so it must still load');

  iEqual(1: def.group_count: 'one group');

  got = def.groups(1);
  sl_equal(gv: got:
           'and it arrives whole - 500 is what separates a widening to the ' +
           'item bound from one to 128 or 256');

end-proc;

dcl-proc test_group_ordinary_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('utgrshort.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- web' + LF +
    '- autostart' + LF: def): 'an ordinary pair of groups still loads');

  iEqual(2: def.group_count: 'two groups');

  got = def.groups(1);
  sl_equal('web': got: 'THE CONTROL - the first group, whole');
  got = def.groups(2);
  sl_equal('autostart': got:
           'and the SECOND, which is where a widening that got the array ' +
           'element stride wrong would show first');

end-proc;

//==============================================================================
// SERVICE DEPENDENCIES - the same holder, the same defect, its own cases
//
// The brief for this work says deps share the groups holder. That is a claim
// about the implementation, and a test that took it on trust would cover one
// field and report two. So deps are measured on themselves at the same three
// lengths, and def.groups is not used as a witness for any of them.
//==============================================================================

dcl-proc test_dep_at_64_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  dv  varchar(2048);
  dcl-s  got varchar(2048);

  dv = ut_lc('dp64': 64);
  iEqual(64: %len(dv): 'a dependency of exactly 64 characters');

  assert(load_fixture('utdp64.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'service_dependencies:' + LF +
    '- ' + dv + LF: def): 'a 64-character dependency still loads');

  iEqual(1: def.dep_count: 'one dependency');

  got = def.deps(1);
  sl_equal(dv: got: 'the dependency is whole at 64 - the width it has today');

end-proc;

dcl-proc test_dep_at_65_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  dv  varchar(2048);
  dcl-s  got varchar(2048);

  dv = ut_lc('dp65': 65);
  iEqual(65: %len(dv): 'one character more than the case above');

  assert(load_fixture('utdp65.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'service_dependencies:' + LF +
    '- ' + dv + LF: def): 'a 65-character dependency still loads');

  iEqual(1: def.dep_count: 'one dependency');

  got = def.deps(1);
  sl_equal(dv: got:
           'the dependency is whole at 65 - today it arrives cut at 64, so ' +
           'the name RMSC then looks up is not the one that was written');

end-proc;

dcl-proc test_dep_at_500_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  dv  varchar(2048);
  dcl-s  got varchar(2048);

  dv = ut_lc('dp500': 500);
  iEqual(500: %len(dv): 'inside the 512 a sequence item holds, far past 64');

  assert(load_fixture('utdp500.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'service_dependencies:' + LF +
    '- ' + dv + LF: def):
    'a dependency of 500 is inside the item cap, so it must still load');

  iEqual(1: def.dep_count: 'one dependency');

  got = def.deps(1);
  sl_equal(dv: got: 'and it arrives whole');

end-proc;

dcl-proc test_dep_ordinary_is_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('utdpshort.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'service_dependencies:' + LF +
    '- db' + LF +
    '- messagequeue' + LF: def):
    'an ordinary pair of dependencies still loads');

  iEqual(2: def.dep_count: 'two dependencies');

  got = def.deps(1);
  sl_equal('db': got: 'THE CONTROL - the first dependency, whole');
  got = def.deps(2);
  sl_equal('messagequeue': got: 'and the second');

end-proc;

//##############################################################################
//##                                                                          ##
//##  sbmjob_jobname IS NOT WIDENED - IT IS REFUSED                           ##
//##                                                                          ##
//##############################################################################
//
// This field is NOT in the block above and the difference is the point. An IBM
// i job name is at most 10 characters. That is an external limit, not a holder
// width RMSC chose, so a longer value can NEVER work - widening the field would
// store something unusable and move the failure to start time, where it costs
// more and says less.
//
// So the rule is the one this suite has already applied twice: a value RMSC
// cannot represent INVALIDATES THE DEFINITION, reported on stderr and joined to
// the collection's bad-definition list. Same rule as an over-long scalar and an
// unusable wait time.
//
// MEASURED, 7 September 2026: a `sbmjob_jobname:` of 20 characters is accepted
// by RMSC and arrives as 10. So RMSC would submit the job under a name the
// author did not write, and every later `stop` and `check` that looks for the
// name in the file would look for the wrong thing.
//
// THE CONTROL IS THE HALF THAT MATTERS. There are TWO paths to a batch job
// name, and only one of them is being changed:
//
//   sbmjob_jobname GIVEN     the author chose it     -> refuse if it cannot work
//   sbmjob_jobname ABSENT    RMSC derives one        -> truncating is CORRECT
//
// The derived path cuts to 10 on purpose, because nobody chose that name. A fix
// that refused a long value on BOTH paths would refuse most services on any
// system, and it would pass every refusal case below. The control for the
// derived path lives in SCLAUNCH.TEST, where the derived name is observable -
// see test_job_name_derived_from_a_long_name there. What this suite can hold is
// the weaker half of it: a definition with a long short name and NO
// sbmjob_jobname must still LOAD.
//
// WORDING IS NOT ASSERTED, only that a reason was recorded and that it names
// the attribute at fault - as every other rejection in this suite does.
//##############################################################################

dcl-proc test_sbmjob_jobname_at_10_is_accepted_whole export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  jn  varchar(2048);
  dcl-s  got varchar(2048);

  jn = sl_value('JN10': 10);
  iEqual(10: %len(jn): 'exactly the length an IBM i job name may be');

  assert(load_fixture('utjn10.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'sbmjob_jobname: ' + jn + LF: def):
    'a job name of exactly 10 is usable, so the definition loads');

  got = def.sbmjob_jobname;
  sl_equal(jn: got:
           'and it is kept whole - green today and it must stay green, ' +
           'because a refusal that started at 10 would refuse every ' +
           'definition that names its job at full length');

end-proc;

dcl-proc test_sbmjob_jobname_at_11_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  jn  varchar(2048);
  dcl-s  got varchar(2048);

  jn = sl_value('JN11': 11);
  iEqual(11: %len(jn): 'one character more than a job name may be');

  if load_fixture('utjn11.yaml':
       'start_cmd: /usr/bin/rmscut' + LF +
       'check_alive: 8080' + LF +
       'sbmjob_jobname: ' + jn + LF: def);
    // Not nEqual(false: load_fixture(...)): the interesting part of the red is
    // WHAT ARRIVED, and a bare true says nothing about the cut.
    got = def.sbmjob_jobname;
    assert(*off: 'a job name of 11 can never be submitted, so the ' +
                 'definition must be refused - instead it loaded and the ' +
                 'name arrived ' + %char(%len(%trimr(got))) +
                 ' characters, as "' + %trim(got) + '", which is not the ' +
                 'name the file asks for');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('sbmjob_jobname': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

dcl-proc test_sbmjob_jobname_at_20_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  jn  varchar(2048);
  dcl-s  got varchar(2048);

  jn = sl_value('JN20': 20);
  iEqual(20: %len(jn): 'the length measured against upstream');

  if load_fixture('utjn20.yaml':
       'start_cmd: /usr/bin/rmscut' + LF +
       'check_alive: 8080' + LF +
       'sbmjob_jobname: ' + jn + LF: def);
    got = def.sbmjob_jobname;
    assert(*off: 'a job name of 20 must be refused - instead it loaded and ' +
                 'the name arrived ' + %char(%len(%trimr(got))) +
                 ' characters, as "' + %trim(got) + '", so RMSC would ' +
                 'submit under a name nobody wrote');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('sbmjob_jobname': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

dcl-proc test_sbmjob_jobname_absent_long_name_still_loads export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);

  nm = ut_lc('jnderived': 100);
  iEqual(100: %len(nm): 'a service name ten times longer than a job name');

  assert(load_fixture(nm + '.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF: def):
    'THE CONTROL - no sbmjob_jobname, so the job name is DERIVED and the ' +
    'derivation truncates on purpose. This must still load. A refusal ' +
    'applied to both paths would refuse most services on the system and ' +
    'would still pass every rejection case above');

  assert((%len(def.err) = 0):
         'and nothing is recorded against it - a long SERVICE name is not a ' +
         'long JOB name, and only the second is refused');

  // WHOLENESS IS DELIBERATELY NOT ASSERTED HERE. This procedure is the
  // control for the DERIVED path and it must be green today and green after
  // the widening; an assertion that is red today would make it a second
  // separating case wearing a control's name, and the thing it controls
  // would go unwatched. What arrives in short_name is measured at 65 and 250
  // above.

end-proc;

//##############################################################################
//##                                                                          ##
//##  THE JOB-NAME GUARD MEASURES ONE STRING AND STORES ANOTHER               ##
//##                                                                          ##
//##############################################################################
//
// The block above refuses a `sbmjob_jobname:` longer than 10 characters, and
// test_sbmjob_jobname_at_11_is_rejected and _at_20_ pin it. Both values are
// unquoted and neither has a blank in it, so for both of them the value AS
// WRITTEN, the value AS STORED and the value AS TRIMMED are the same string and
// nothing can tell them apart.
//
// A DOUBLE-QUOTED SCALAR KEEPS ITS INTERIOR BLANKS, and that is where the three
// come apart. Written
//
//     sbmjob_jobname: "  ABCDEFGHIJ"
//
// the stored value is 12 characters and the trimmed one is 10. A guard that
// measures the trimmed string sees 10, allows it, and hands the assignment 12
// characters to put in a 10-wide field. What lands there is '  ABCDEFGH' - the
// author's last two characters gone - and the launcher trims that to
// 'ABCDEFGH'. The job is then submitted under an eight-character name nobody
// wrote, and every later `stop` and `check` looks for the name in the file.
//
// THAT IS THE SAME HARM THE BLOCK ABOVE EXISTS TO PREVENT, reached by a value
// the guard lets through, which is why it belongs beside those cases rather
// than in a block of its own.
//
// THE FIXTURE CLAIM IS ESTABLISHED FIRST, and it is not a formality. Everything
// here rests on RMSC keeping the blanks inside double quotes. If it strips
// them, "  ABCDEFGHIJ" stores ten characters, is legitimately accepted, and a
// case asserting a refusal would be red today and red after any fix - a test
// nobody could ever make pass. So the first case below asks a field with no
// width guard on it whether the blanks survive at all, and the two that follow
// mean nothing without it.
//
// THE PAIR SEPARATES "MEASURE THE RIGHT STRING" FROM "REFUSE ANYTHING WITH A
// BLANK IN IT". The obvious cheap fix is to reject a value whose spelling is
// not a bare job name, and it makes the refusal case green while breaking the
// acceptance case beside it:
//
//     "  ABCDEFGHIJ"    12 stored, 10 trimmed   must be REFUSED
//     "  ABCDEFGH"      10 stored,  8 trimmed   must be ACCEPTED
//
// Both are the same shape and the same spelling. Only the length of what is
// stored differs, so a guard reading the stored string answers them
// differently and one reading anything else answers them the same way.
//
// WHAT THE LAUNCHER DOES WITH THE ACCEPTED ONE IS ASSERTED IN SCLAUNCH.TEST -
// see test_job_name_explicit_with_leading_blanks there. This suite can see what
// was stored; only that suite can see what would be submitted.
//
// WORDING IS NOT ASSERTED, only that a reason was recorded and that it names
// the attribute at fault, as everywhere else in this suite.
//
// 07/09/2026 - test author - written against the defect, before the fix
//##############################################################################

//==============================================================================
// THE FIXTURE CLAIM - a double-quoted value keeps its leading blanks
//
// Asked of start_cmd, which has no width guard anywhere near this length, so
// nothing here can be answered by a refusal instead of by the blanks. If this
// is red the two cases below are not measuring what their headers say and
// should be re-read before anything is fixed.
//==============================================================================

dcl-proc test_quoted_value_keeps_its_leading_blanks export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('utqblank.yaml':
    'start_cmd: "  /usr/bin/rmscut"' + LF +
    'check_alive: 8080' + LF: def):
    'a double-quoted command with two leading blanks loads');

  got = def.start_cmd;
  iEqual(17: %len(%trimr(got)):
         'and the two blanks inside the quotes are part of the value - 15 ' +
         'characters of command plus the two in front. If this is 15 then ' +
         'RMSC strips leading blanks and the job-name cases below cannot ' +
         'construct a value that is longer stored than trimmed');

  sl_equal('  /usr/bin/rmscut': got:
           'and what is stored is exactly what was inside the quotes');

end-proc;

//==============================================================================
// SEPARATING - 12 characters stored, 10 after trimming, and it is REFUSED
//
// The guard reads the trimmed string today, sees ten, and lets a value through
// that cannot be held. RED until it reads what is stored.
//==============================================================================

dcl-proc test_sbmjob_jobname_quoted_12_stored_10_trimmed_is_rejected export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  if load_fixture('utjnq12.yaml':
       'start_cmd: /usr/bin/rmscut' + LF +
       'check_alive: 8080' + LF +
       'sbmjob_jobname: "  ABCDEFGHIJ"' + LF: def);
    // Not nEqual(false: load_fixture(...)): the interesting part of the red is
    // WHAT ARRIVED, exactly as in the two unquoted rejection cases above.
    got = def.sbmjob_jobname;
    assert(*off: 'twelve characters were stored where ten fit, so the ' +
                 'definition must be refused - instead it loaded and the ' +
                 'name arrived ' + %char(%len(%trimr(got))) +
                 ' characters, as "' + %trim(got) + '". The launcher trims ' +
                 'that, so this service would be submitted under a name ' +
                 'the file does not contain');
  endif;

  assert((%len(def.err) > 0): 'a reason is recorded');
  assert((%scan('sbmjob_jobname': def.err) > 0):
         'and the reason names the attribute at fault');

end-proc;

//==============================================================================
// THE OTHER HALF - 10 stored, 8 after trimming, and it is ACCEPTED
//
// Green today, and it is the half a fix of "refuse anything with a blank in it"
// breaks. Without it the case above is satisfied by refusing every quoted
// value, or every value that is not already a bare job name.
//
// WHAT IS ASSERTED ABOUT THE STORED VALUE IS THE NAME THE LAUNCHER WILL USE,
// not its exact spelling. A fix that keeps the blanks and one that strips them
// on the way in are both correct here and both give the launcher ABCDEFGH;
// pinning one spelling would fail the other for no reason this case is about.
//==============================================================================

dcl-proc test_sbmjob_jobname_quoted_10_stored_8_trimmed_is_accepted export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  got varchar(2048);

  assert(load_fixture('utjnq10.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'sbmjob_jobname: "  ABCDEFGH"' + LF: def):
    'ten characters are stored and ten characters fit, so this definition ' +
    'must load - a guard that refused a blank rather than a length would ' +
    'refuse it, and would still pass every rejection case in this block');

  assert((%len(def.err) = 0):
         'and nothing is recorded against it');

  got = def.sbmjob_jobname;
  aEqualV('ABCDEFGH': %trim(got):
          'and the name the launcher will submit under is the one the file ' +
          'asks for, whole - not a prefix of it');

end-proc;

//##############################################################################
//##                                                                          ##
//##  A KEY TOO LONG TO HOLD IS AN UNRECOGNISED ATTRIBUTE, NOT A DEAD FILE    ##
//##                                                                          ##
//##############################################################################
//
// A YAML key longer than 128 characters refuses the whole definition today. The
// service disappears - not from one attribute, from `check`, `list` and
// everything else.
//
// UPSTREAM WARNS AND CARRIES ON. `Unrecognized attribute '<key>'` and the
// service loads, which is what RMSC already does for an ordinary key it does
// not know - test_unknown_key_is_not_fatal above pins that and passes. So a key
// that is merely LONG is a key RMSC does not recognise, and the length is not a
// reason to treat it differently from any other unrecognised spelling.
//
// A DEFINITION THAT LOADS BUT LOSES SOMETHING WOULD PASS A NAIVE CHECK, which
// is why loading is not the assertion. A fix that recovered from the long key
// by abandoning the rest of the parse leaves a service with no start_cmd and no
// check_alive, and `load returned true` cannot tell that from a healthy one. So
// the real attributes are asserted, by value, after the load.
//
// 200 CHARACTERS, well past the 128 that refuses today, and inside the 1024 a
// scalar line may hold - so nothing here can be answered by the scalar guard
// firing on the length of the line instead of the key.
//
// THE TWO CONTROLS ARE BOTH DIRECTIONS OF THE SAME QUESTION:
//
//   an ordinary unknown key is still recorded   ruled out: a fix that records
//                                               nothing at all, which would
//                                               make the long-key count agree
//                                               with 0 rather than with 1
//   a definition with no unknown keys reports   ruled out: a fix that records
//   none                                        something for every key it
//                                               reads, which would make every
//                                               count agree
//
// The first is test_unknown_key_is_not_fatal, already in this suite and left
// where it is. The second is written below because nothing here asserted it.
//
// WHAT IS RECORDED FOR THE LONG KEY IS ASSERTED AS ITS LEADING TEXT, not as its
// whole 200 characters, AND THAT IS A DECISION RATHER THAN AN OMISSION. It was
// asked as a separate flagged case and answered by the project owner on
// 7 September 2026: SCYAML_KEY_SIZE stays at 128 and a longer key is recorded
// under its first 128 characters. `unknown` is a 16-element array in every
// definition, so carrying a key whole would cost some 16KB per definition and
// drop the collection's ceiling by about a third - to identify an attribute
// that 128 characters already identifies uniquely. It is a deliberate
// truncation of a typo's NAME, and of nothing that acts.
//
// THE COLLISION IT STILL CLOSES is the one that made the width worth asking
// about: two keys agreeing for their first 64 characters used to collapse into
// one, and a repeated key is treated as a REPLACE, so a definition could
// silently lose an attribute it had set. At 128 that needs two 128-character
// keys agreeing throughout, which no typo produces.
//
// So the case that asserted wholeness has been DELETED rather than adjusted,
// which is what its own header said to do if the answer came back this way. Do
// not write it again. What is asserted below - that the recorded entry begins
// with the same 32 characters as the key in the file - is unaffected by the
// truncation and is the part that matters: it says the right attribute was
// named.
//
// 07/09/2026 - test author - written against the defect, before the fix
//##############################################################################

dcl-proc test_long_key_is_recorded_not_fatal export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  key varchar(2048);
  dcl-s  got varchar(2048);

  key = ut_lc('longkey': 200);
  iEqual(200: %len(key):
         'a key of 200 characters - well past the 128 that refuses today, ' +
         'and well inside the 1024 a scalar line may hold');

  assert(load_fixture('utlongkey.yaml':
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    %trim(key) + ': 42' + LF: def):
    'a key RMSC cannot hold is a key RMSC does not RECOGNISE, and an ' +
    'unrecognised key must not take the service with it - upstream warns ' +
    'and loads. Today the whole definition is refused and the service is ' +
    'gone from check and list');

  // THE REAL ATTRIBUTES, BY VALUE. A recovery that abandoned the rest of the
  // parse would return true here and leave nothing usable behind.
  got = def.start_cmd;
  sl_equal('/usr/bin/rmscut': got:
           'the start command survived the long key');

  iEqual(1: def.criteria_count: 'and one check-alive criterion survived');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'and it is a port');
  iEqual(8080: def.criteria(1).port: 'and it is the port the file asks for');

  assert((%len(def.err) = 0):
         'and nothing is recorded as an ERROR against the definition - an ' +
         'unrecognised attribute is a warning, not a failure');

  iEqual(1: def.unknown_count:
         'the long key is recorded as an unrecognised attribute, exactly as ' +
         'a short unknown key is');

  got = def.unknown(1);
  assert((%len(%trimr(got)) > 0):
         'and something was recorded for it, not a blank entry');
  assert((%len(%trimr(got)) >= 32
          and %subst(%trimr(got): 1: 32) = %subst(key: 1: 32)):
         'and what was recorded is THAT key - it begins with the same 32 ' +
         'characters, so it is not some other attribute of the file being ' +
         'reported in its place. Recorded ' +
         %char(%len(%trimr(got))) + ' characters: "' + %trim(got) + '"');

end-proc;

//==============================================================================
// THE SECOND CONTROL - a definition with no unknown keys reports none
//
// Green today and green after. Without it, a fix that recorded an entry for
// every key it read would make the long-key count of 1 agree with itself and
// with nothing else.
//==============================================================================

dcl-proc test_no_unknown_keys_reports_none export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_fixture('utnounknown.yaml':
    'name: Known keys only' + LF +
    'start_cmd: /usr/bin/rmscut' + LF +
    'check_alive: 8080' + LF +
    'startup_wait_time: 30' + LF: def): 'load');

  iEqual(0: def.unknown_count:
         'every key in this file is one RMSC knows, so nothing is ' +
         'unrecognised');

end-proc;
