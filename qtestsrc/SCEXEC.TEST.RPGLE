**free

//==============================================================================
// SCEXEC.TEST - Service operations test suite
//
// Status determination is what these mostly cover, because it is the logic
// every operation and every consumer depends on. It is tested against real
// system state - a port that is genuinely listening, a job that genuinely
// exists - rather than against a stub, since the point is whether RMSC agrees
// with the machine.
//
// Starting and stopping real services is deliberately NOT tested here. Doing
// so would mean a suite that takes services down on whatever system it runs
// on, and leaves them down when it fails.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCEXEC_D.rpgleinc'
/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCLOG_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'SCQRY_D.rpgleinc'
/include 'SCMAIN_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMQCMD_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-pr pt_dir like(STMF_t) end-pr;

dcl-pr pt_load_def like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  def     likeds(SCDEF_t);
end-pr;

dcl-pr pt_failed varchar(512);
  ev likeds(SCEXEC_EVAL_t) const;
  i  like(INTEGER_t) const;
end-pr;

dcl-pr pt_join varchar(512);
  ev likeds(SCEXEC_EVAL_t) const;
end-pr;

dcl-s g_dir like(STMF_t);

// SSH: the suite reaches this system over it, so it is listening
dcl-c SSH_PORT_TEXT const('22');
// Nothing listens here
dcl-c UNUSED_PORT_TEXT const('59417');

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

dcl-pr remove_fixtures end-pr;

// ADHOC PGM- and LONG-ROW blocks - see the two group headers at the end of
// this suite. Global declarations must precede the first subprocedure, so
// these live here rather than beside the procedures that use them.
dcl-pr lg_equal;
  expected varchar(4096) const;
  actual   varchar(4096) const;
  ctx      varchar(64) const;
end-pr;

dcl-pr tail48 varchar(64);
  v varchar(4096) const;
end-pr;

// AD-HOC LONG PORT SPECIFIER block - see the group header at the end of this
// suite.
dcl-pr az_spec varchar(512);
  tail varchar(64) const;
end-pr;


//------------------------------------------------------------------------------
// JOB-ORDER block - see the group header at the end of this suite. Global
// declarations must precede the first subprocedure, so these live here rather
// than beside the procedures that use them.
//------------------------------------------------------------------------------

// Two invented job names. This suite submits every job carrying either of
// them and ends every one it finds, so neither may be a name anything else on
// a machine could reasonably choose.
dcl-c ORD_JOB_A const('RMSCSEQA');
dcl-c ORD_JOB_B const('RMSCSEQB');

// How many jobs are staged under ORD_JOB_B. Three rather than one so the
// order WITHIN a criterion is visible as well as the order BETWEEN criteria.
dcl-c ORD_B_JOBS const(3);

// Long enough that the suite cannot outlive them, short enough that a job
// leaked by a run killed before its teardown goes away on its own.
dcl-c ORD_RUNS_FOR const('600');

// How long to wait for a staged job to start, and to go away again
dcl-c ORD_WAIT const(60);

dcl-s g_ord_a      varchar(64);
dcl-s g_ord_b      varchar(64) dim(ORD_B_JOBS);
dcl-s g_ord_staged like(BOOLEAN_t) inz(false);
dcl-s g_ord_tried  like(BOOLEAN_t) inz(false);

dcl-pr ord_stage end-pr;
dcl-pr ord_sweep end-pr;

dcl-pr ord_end_all;
  jobname varchar(10) const;
end-pr;

dcl-pr ord_submit varchar(64);
  jobname varchar(10) const;
  known   varchar(2048) const;
  want    like(INTEGER_t) const;
end-pr;

dcl-pr ord_is_staged like(BOOLEAN_t);
  qualified varchar(64) const;
  jobname   varchar(10) const;
end-pr;

dcl-pr ord_number varchar(16);
  qualified varchar(64) const;
end-pr;

dcl-pr ord_names varchar(512);
  jobs likeds(SCQRY_JOBS_t);
end-pr;

dcl-pr ord_expected varchar(512);
  with_a like(BOOLEAN_t) const;
end-pr;

dcl-pr ord_equal;
  expected varchar(512) const;
  actual   varchar(512) const;
  ctx      varchar(500) const;
end-pr;

// A THIRD invented name, for the per-criterion overflow case. Its jobs are
// staged separately from A and B and swept separately, because under
// ORDER(*API) the overflow case may run either side of the others and a
// shared sweep would let whichever staged second end the other's jobs.
dcl-c ORD_JOB_C const('RMSCSEQC');

// SCQRY_MAX_JOBS, and one more than it. Written as literals rather than
// derived from the constant ON PURPOSE: deriving them would make a future
// widening of the array silently stage that many jobs, and a suite that
// submits five hundred jobs because a constant moved is a worse outcome than
// one that goes red and says so. The case asserts the constant is still 32.
dcl-c ORD_CAP    const(32);
dcl-c ORD_C_JOBS const(33);

dcl-s g_ord_c_first  varchar(64);
dcl-s g_ord_c_set    varchar(2048);
dcl-s g_ord_c_staged like(BOOLEAN_t) inz(false);
dcl-s g_ord_c_tried  like(BOOLEAN_t) inz(false);

dcl-pr ord_stage_c end-pr;

dcl-pr ord_submit_many;
  jobname varchar(10) const;
  from    like(INTEGER_t) const;
  want    like(INTEGER_t) const;
end-pr;

dcl-pr ord_known varchar(2048);
  jobs likeds(SCQRY_JOBS_t);
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-scexec-test-' + %trim(psds.current_user);
  IFS_crtdir(g_dir);
  SCOUT_set_colour(false);

end-proc;

dcl-proc tearDownSuite export;

  // Unconditionally, whatever the tests did, and whether or not they were
  // ever staged. A suite that leaves submitted jobs behind when it fails is
  // worse than no suite.
  ord_sweep();

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

//==============================================================================
// A port criterion agrees with the machine
//==============================================================================

dcl-proc test_status_running_on_live_port export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('live.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + LF: def): 'load');

  aEqualV(SCOUT_RUNNING: SCEXEC_status(def): 'a listening port is RUNNING');

end-proc;

dcl-proc test_status_not_running_on_dead_port export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('dead.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + UNUSED_PORT_TEXT + LF: def): 'load');

  aEqualV(SCOUT_NOT_RUNNING: SCEXEC_status(def):
          'an unused port is NOT RUNNING');

end-proc;

//==============================================================================
// PARTIAL: some criteria satisfied, not all
//
// Easy to overlook, and the reason status is not a boolean. A service
// declaring a job and a port is half up if the job exists but nothing is
// listening yet.
//==============================================================================

dcl-proc test_status_partial export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('partial.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + ',' + UNUSED_PORT_TEXT + LF: def):
    'load');

  iEqual(2: def.criteria_count: 'two criteria');
  aEqualV(SCOUT_PARTIAL: SCEXEC_status(def):
          'one satisfied, one not, is PARTIAL');

end-proc;

//==============================================================================
// Every criterion satisfied is RUNNING, not PARTIAL
//==============================================================================

dcl-proc test_status_all_satisfied export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('allup.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + ',QP0ZSPWP' + LF: def): 'load');

  aEqualV(SCOUT_RUNNING: SCEXEC_status(def):
          'a live port and a live job is RUNNING');

end-proc;

//==============================================================================
// Individual criteria
//==============================================================================

dcl-proc test_criterion_port export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('crit1.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + LF: def): 'load');

  nEqual(true: SCEXEC_criterion_alive(def.criteria(1)): 'live port');

end-proc;

dcl-proc test_criterion_job export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('crit2.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: QP0ZSPWP' + LF: def): 'load');

  nEqual(true: SCEXEC_criterion_alive(def.criteria(1)):
         'the job running this suite');

end-proc;

dcl-proc test_criterion_job_absent export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('crit3.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ZZNOSUCH' + LF: def): 'load');

  nEqual(false: SCEXEC_criterion_alive(def.criteria(1)):
         'a job that cannot exist');

end-proc;

//==============================================================================
// A LOWER-CASE job name still finds the job, whichever key it arrived through
//
// MEASURED 4 September against sc 1.7.1, two definitions naming this job in
// lower case, one through each key. Both reported RUNNING, and so did RMSC:
//
//     check_alive: qp0zspwp                            -> RUNNING
//     check_alive: jobname / check_alive_criteria: qp0zspwp -> RUNNING
//
// THIS IS A REGRESSION GUARD FOR A FIX THAT HAS NOT BEEN MADE YET, and the
// only one of its kind. docs/messages.md § "Two defects the fixture pack found
// on its first run" records that a job name reached through
// check_alive_criteria must be RENDERED as it was written, and
// test_criterion_text_companion_job_as_written in SCDEF.TEST asserts exactly
// that. The obvious way to satisfy it is to stop folding the value on the way
// in - and *JOB names on this system are upper case, so a lookup made with the
// unfolded value finds nothing.
//
// The failure that would cause is the one CLAUDE.md singles out: a live
// service reported as NOT RUNNING, silently, on a definition nobody would
// think to re-check. Nothing in SCDEF can catch it, because SCDEF is where the
// text is kept and keeping the text is correct. It shows up only where the
// text is USED to ask the system a question, which is here.
//
// So the two sides of the rule are: the criterion is RENDERED as written and
// LOOKED UP folded. Neither test alone says that; together they do.
//
// THE FIXTURE IS THE JOB THIS SUITE RUNS IN, as test_criterion_job's is, and
// the same argument applies: an iRPGUnit suite on this platform runs in a
// QP0ZSPWP job, so the value is available on every run and needs nothing
// installed. It is written here in lower case ON PURPOSE - upper case is what
// test_criterion_job already covers, and would make this row unable to fail.
//==============================================================================

dcl-proc test_criterion_job_lower_case export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('critlc1.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: qp0zspwp' + LF: def): 'load');

  nEqual(true: SCEXEC_criterion_alive(def.criteria(1)):
         'MEASURED - a lower-case job name in check_alive still finds the ' +
         'job running this suite');

  assert(load_def('critlc2.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: qp0zspwp' + LF: def): 'load');

  nEqual(true: SCEXEC_criterion_alive(def.criteria(1)):
         'MEASURED - and so does one reached through check_alive_criteria, ' +
         'whose TEXT must survive unfolded but whose LOOKUP must not');

end-proc;

//==============================================================================
// The jobs behind a running service can be identified
//==============================================================================

dcl-proc test_jobs_for_running_service export;

  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);

  assert(load_def('jobs.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + LF: def): 'load');

  assert((SCEXEC_jobs(def: jobs) > 0): 'at least one job found');
  assert((%len(%trim(jobs.name(1))) > 0): 'job name populated');

end-proc;

//==============================================================================
// A job satisfying two criteria is counted once
//==============================================================================

dcl-proc test_jobs_deduplicated export;

  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s i like(INTEGER_t);
  dcl-s j like(INTEGER_t);

  assert(load_def('dedup.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + SSH_PORT_TEXT + ',' + SSH_PORT_TEXT + LF: def): 'load');

  SCEXEC_jobs(def: jobs);

  for i = 1 to jobs.count;
    for j = i + 1 to jobs.count;
      assert((jobs.name(i) <> jobs.name(j)): 'no job listed twice');
    endfor;
  endfor;

end-proc;

//==============================================================================
// A definition with no criteria cannot be running
//==============================================================================

dcl-proc test_status_no_criteria export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  // Built directly: SCDEF refuses to load a definition with no check_alive,
  // which is the right behaviour but leaves this path otherwise unreachable
  def.criteria_count = 0;

  aEqualV(SCOUT_NOT_RUNNING: SCEXEC_status(def):
          'nothing to check means not running');

end-proc;

//==============================================================================
// Log file location
//==============================================================================

dcl-proc test_log_path_default export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('logdefault.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF: def): 'load');

  assert((%scan('.sc/logs': SCLOG_dir(def)) > 0):
         'defaults to the home log directory');
  assert((%scan('logdefault.log': SCLOG_path(def)) > 0):
         'named after the service');

end-proc;

dcl-proc test_log_path_explicit export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('logexplicit.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF +
    'log_dir: /tmp/rmsc-logs' + LF: def): 'load');

  aEqualV('/tmp/rmsc-logs': SCLOG_dir(def): 'log_dir wins');
  aEqualV('/tmp/rmsc-logs/logexplicit.log': SCLOG_path(def): 'full path');

end-proc;

//==============================================================================
// check output for a real service is a well-formed row
//
// SCOUT pins the format; this pins that SCEXEC feeds it the right values.
//==============================================================================

dcl-proc test_check_row_for_service export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s row like(SCOUT_LINE_t);

  assert(load_def('rowtest.yaml':
    'name: Row Test' + LF +
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: ' + UNUSED_PORT_TEXT + LF: def): 'load');

  row = SCOUT_check_row(SCEXEC_status(def): def.short_name: def.friendly);

  iEqual(SCOUT_BAR_COLUMN: %scan('|': row): 'bar in column 22');
  aEqualV('NOT RUNNING': %trim(%subst(row: 1: 20)): 'status');
  assert((%scan('rowtest (Row Test)': row) > 0): 'name and friendly name');

end-proc;

//==============================================================================
// Group exclusion, which a bare 'check' depends on
//
// Consumers rely on the default: a bare check lists the services someone
// configured, not the several dozen host and TCP server definitions that ship
// with the system.
//==============================================================================

dcl-proc test_group_exclusion export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('grouped.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF +
    'groups:' + LF +
    '- system' + LF: def): 'load');

  nEqual(true: SCDEF_in_group(def: 'system'): 'in the system group');
  nEqual(true: SCDEF_in_group(def: 'all'): 'and in all, as everything is');

end-proc;

//==============================================================================
// list and check report how many services they displayed
//
// Upstream warns - on stderr, exiting 0 - whenever an operation matches
// nothing:
//
//   WARNING: No services are found in group 'all'
//
// It does so in three situations that look different and are the same: a
// named group with no members, a collection that is empty, and group
// exclusions that removed everything. The caller can only tell which happened
// if the operation says how many services it actually displayed, so both
// report a count.
//
// The exclusion case is the one worth pinning here. Every definition belongs
// to the implicit group 'all', so excluding 'all' empties a collection that
// is not itself empty - the case a count of the collection would get wrong.
//==============================================================================

dcl-proc test_list_reports_how_many export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  // Put the fixtures there rather than relying on files another test
  // happened to leave behind: under ORDER(*API) this suite's tests do not run
  // in source order, so a count taken from whatever is lying in the directory
  // is a count of which tests ran first.
  assert(load_def('counted1.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55990' + LF: def): 'fixture 1');
  assert(load_def('counted2.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55991' + LF: def): 'fixture 2');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'fixtures loaded');

  n = SCCOLL_count(coll);
  assert((n > 0): 'fixture directory is not empty');

  iEqual(n: SCEXEC_list(coll: ''): 'every service listed is counted');
  iEqual(0: SCEXEC_list(coll: 'all'):
         'nothing listed when every group is excluded');

end-proc;

//==============================================================================
// list can be restricted to one group
//
// 'sc list group:backend' lists that group's members. RMSC printed nothing at
// all: its group branch routes anything that is not check or a state change
// to run_reporting, which has no list case, so every service was visited and
// none was printed. Nothing caught it because no test and no gate ever passed
// a group specifier to list.
//
// The named group wins over --ignore-groups, so the exclusions are not
// applied on top: asking for a group you also excluded is asking for it.
//==============================================================================

dcl-proc test_list_restricted_to_a_group export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  assert(load_def('ingroup1.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55994' + LF +
    'groups:' + LF + '- listgrp' + LF: def): 'fixture in the group');
  assert(load_def('ingroup2.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55995' + LF +
    'groups:' + LF + '- listgrp' + LF: def): 'second in the group');
  assert(load_def('outgroup.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55996' + LF +
    'groups:' + LF + '- othergrp' + LF: def): 'fixture outside it');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'fixtures loaded');

  iEqual(2: SCEXEC_list(coll: '': 'listgrp'):
         'only the group members are listed');
  iEqual(0: SCEXEC_list(coll: '': 'nosuchgroup'):
         'an empty group lists nothing');
  iEqual(2: SCEXEC_list(coll: 'listgrp': 'listgrp'):
         'the named group wins over the exclusions');

end-proc;

dcl-proc test_check_all_reports_how_many export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  // As above: this test's fixtures are this test's responsibility
  assert(load_def('checked1.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55992' + LF: def): 'fixture 1');
  assert(load_def('checked2.yaml':
    'start_cmd: /usr/bin/x' + LF + 'check_alive: 55993' + LF: def): 'fixture 2');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'fixtures loaded');

  n = SCCOLL_count(coll);
  assert((n > 0): 'fixture directory is not empty');

  iEqual(0: SCEXEC_check_all(coll: 'all'):
         'nothing checked when every group is excluded');
  iEqual(n: SCEXEC_check_all(coll: ''): 'every service checked is counted');

end-proc;

// BLOCK 2 - paste into qtestsrc/SCEXEC.TEST.RPGLE
//
// Needs pt_dir and pt_load_def from Block 1 (a second copy - the suites are
// separate programs), plus:
//   /include 'SCEXEC_D.rpgleinc'
//   /include 'SCDEF_D.rpgleinc'
//   /include 'include/RMIFS_D.rpgleinc'
//   /include 'include/RMTOOLS_D.rpgleinc'   // LF, STRING_t, BOOLEAN_t, INTEGER_t
//   /include 'include/PSDS_D.rpgleinc'
// and:
//   dcl-pr pt_failed varchar(512);
//     ev likeds(SCEXEC_EVAL_t) const;
//     i  like(INTEGER_t) const;
//   end-pr;
//   dcl-pr pt_join varchar(512);
//     ev likeds(SCEXEC_EVAL_t) const;
//   end-pr;
//
// FIXTURES. Two are needed and both are free:
//   - port 22 is listening, because the suite arrived over SSH. This is the
//     same fixture SCQRY.TEST relies on and CLAUDE.md sanctions.
//   - ports 55997-55999 and job NOSUCHJOB1/NOSUCHJOB3 are not running.
// Every test below asserts its fixture rather than skipping on it, so a box
// where SSH is on another port goes red with a message that says so instead of
// reporting a pass it did not earn.
//
// NOTE the DS declarations are inz(*likeds). docs/testing-notes.md: likeds()
// copies subfield definitions, not the template's inz keyword, and an
// uninitialised SCEXEC_EVAL_t would carry a plausible-looking failed_count off
// the stack.
//==============================================================================

//------------------------------------------------------------------------------
// pt_failed - one element of eval.failed, as a procedure return value
//
// eval.failed is a varying-length ARRAY, and docs/testing-notes.md records
// that aEqual reads element N with element N-1's length, so
// aEqual('PORT:55998': ev.failed(2): ...) would compare against a truncated
// value and pass or fail for the wrong reason. Suites work around this with a
// local aEqualV; routing the element through a procedure RESULT removes the
// descriptor from the picture entirely, so plain aEqual is correct here and
// this block does not depend on whether SCEXEC.TEST defines aEqualV.
//------------------------------------------------------------------------------
dcl-proc pt_failed;
  dcl-pi *n varchar(512);
    ev likeds(SCEXEC_EVAL_t) const;
    i  like(INTEGER_t) const;
  end-pi;

  if i < 1 or i > ev.failed_count;
    return '*OUT-OF-RANGE*';
  endif;

  return %trimr(ev.failed(i));

end-proc;

//------------------------------------------------------------------------------
// pt_join - the failures joined the way the suffix joins them
//
// Captured: "PORT:55998, JOBNAME:NOSUCHJOB3" - comma, then one space, in
// declaration order. SCOUT_not_running_suffix takes an already-joined string,
// so no exported procedure performs the join; this helper is the test's own
// statement of what the join must be, and asserting against it pins both the
// ordering and the contents of eval.failed in one value.
//------------------------------------------------------------------------------
dcl-proc pt_join;
  dcl-pi *n varchar(512);
    ev likeds(SCEXEC_EVAL_t) const;
  end-pi;

  dcl-s joined varchar(512) inz('');
  dcl-s i   like(INTEGER_t);

  for i = 1 to ev.failed_count;
    if i > 1;
      joined += ', ';
    endif;
    joined += %trimr(ev.failed(i));
  endfor;

  return joined;

end-proc;

//==============================================================================
// FIXTURE GUARD - port 22 is up and port 55999 is down
//
// Runs the two assumptions every other test in this block rests on through
// SCEXEC_evaluate itself. If this goes red, the failures below are about the
// box, not about the code. Asserted, never skipped: CLAUDE.md - "a suite that
// passes because its fixture is absent is worse than one that fails".
//==============================================================================

dcl-proc test_evaluate_fixture_ports export;

  dcl-ds def likeds(SCDEF_t)        inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t)  inz(*likeds);

  assert(pt_load_def('ptup.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  aEqual('RUNNING': ev.state:
         'FIXTURE: port 22 must be listening - this suite arrived over SSH');

  clear ev;
  clear def;              // a stale criteria_count would fake a pass
  assert(pt_load_def('ptdown.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  aEqual('NOT RUNNING': ev.state:
         'FIXTURE: port 55999 must not be listening');

end-proc;

//==============================================================================
// Everything alive: RUNNING, alive = total, nothing failed
//
// Captured for a fully running service - no suffix, so nothing is listed:
//   RUNNING            | webproxy (Web Proxy) $
//==============================================================================

dcl-proc test_evaluate_all_alive export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptalive.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('RUNNING': ev.state: 'state');
  iEqual(1: ev.alive: 'alive');
  iEqual(1: ev.total: 'total');
  iEqual(0: ev.failed_count: 'nothing failed');

end-proc;

//==============================================================================
// Nothing alive: NOT RUNNING, alive is zero, total still counts every criterion
//
// Captured:
//   NOT RUNNING        | zzsdead (Probe dead) $
//
// The capture shows NO suffix on a fully stopped service, which is the
// assertion that matters and is made in the SCOUT block. What the capture
// cannot show is whether upstream still collected the failures internally, so
// ev.failed_count is deliberately NOT asserted here - see the INFERRED test
// below, which is about that and is marked as such.
//==============================================================================

dcl-proc test_evaluate_none_alive export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptdead.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999,NOSUCHJOB1' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('NOT RUNNING': ev.state: 'state');
  iEqual(0: ev.alive: 'alive');
  iEqual(2: ev.total: 'total counts every criterion, not just the failed ones');

end-proc;

//==============================================================================
// INFERRED - a fully stopped service still collects its failures
//
// Nothing in the captures shows this: upstream prints no suffix for
// NOT RUNNING, so the list is invisible either way. It is asserted because a
// procedure named "evaluate" that populates failed only in the PARTIAL case is
// a trap for the next caller, and because leaving it unasserted would let the
// array hold whatever the previous evaluation left in it.
//
// If the fix deliberately leaves failed empty for NOT RUNNING, change this
// test to assert failed_count = 0 and say why in the comment. Either answer is
// defensible; an unstated one is not.
//==============================================================================

dcl-proc test_evaluate_none_alive_lists_failures export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptdead2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999,NOSUCHJOB1' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  iEqual(2: ev.failed_count: 'both criteria recorded as failed');
  aEqual('PORT:55999, JOBNAME:NOSUCHJOB1': pt_join(ev): 'failures, joined');

end-proc;

//==============================================================================
// One of two alive: PARTIAL, counts 1 and 2, the dead one listed
//
// Captured:
//   PARTIAL (1/2)      | zzsport (Probe zzsport) [not running at -->PORT:55999]
//
// alive is the count of criteria that ARE running - the capture's zzsport has
// two criteria, one of which answers, and shows (1/2). A (dead/total) reading
// would have shown (1/2) here too, which is why the three-criterion test below
// exists: (1/3) and (2/3) tell the two apart.
//==============================================================================

dcl-proc test_evaluate_partial_one_of_two export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptpart2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55999' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'state');
  iEqual(1: ev.alive: 'one alive');
  iEqual(2: ev.total: 'of two');
  iEqual(1: ev.failed_count: 'one failure listed');
  aEqual('PORT:55999': pt_failed(ev: 1): 'the failure is the dead port');

end-proc;

//==============================================================================
// One of three alive: the counts are (alive/total), not (dead/total)
//
// Captured:
//   PARTIAL (1/3)      | zzstwo (Probe two) [not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]
//
// Two failures are listed against a first number of 1, so the first number
// counts what IS running. This fixture mirrors that shape exactly: one live
// criterion, then a dead port and a dead job name, in that declared order.
//==============================================================================

dcl-proc test_evaluate_partial_counts_alive_not_dead export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptpart3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55998,NOSUCHJOB3' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'state');
  iEqual(1: ev.alive: 'the first number is the count that ARE running');
  iEqual(3: ev.total: 'the second is every criterion');
  iEqual(2: ev.failed_count: 'two failures');

end-proc;

//==============================================================================
// Several failures keep declaration order and join with ", "
//
// Captured:
//   ... [not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]
//
// Comma, then exactly one space, and PORT:55998 before JOBNAME:NOSUCHJOB3 -
// which is the order they are declared in, not alphabetical (J < P) and not
// grouped by type. The same fixture is loaded a second time here with the
// order of the two dead criteria swapped, so a passing result cannot be an
// accident of a stable sort.
//==============================================================================

dcl-proc test_evaluate_failures_join_in_declared_order export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptorder1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55998,NOSUCHJOB3' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PORT:55998':         pt_failed(ev: 1): 'first failure');
  aEqual('JOBNAME:NOSUCHJOB3': pt_failed(ev: 2): 'second failure');
  aEqual('PORT:55998, JOBNAME:NOSUCHJOB3': pt_join(ev):
         'joined with comma and one space, in declaration order');

  // The same two, declared the other way round
  clear ev;
  clear def;
  assert(pt_load_def('ptorder2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: NOSUCHJOB3,22,55998' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('JOBNAME:NOSUCHJOB3, PORT:55998': pt_join(ev):
         'order follows the definition, not the type or the alphabet');

end-proc;

//==============================================================================
// Only one of many alive
//
// The narrowest case the counts have to survive: four criteria, one answering.
// Upstream's widest captured count is (2/3); this asks the same question one
// step further out, and is where an off-by-one between alive, total and
// failed_count shows up as 1 + 3 <> 4.
//==============================================================================

dcl-proc test_evaluate_one_of_four export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptpart4.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55997,55998,NOSUCHJOB3' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'state');
  iEqual(1: ev.alive: 'alive');
  iEqual(4: ev.total: 'total');
  iEqual(3: ev.failed_count: 'failed_count');
  iEqual(ev.total: ev.alive + ev.failed_count:
         'alive + failed accounts for every criterion');
  aEqual('PORT:55997, PORT:55998, JOBNAME:NOSUCHJOB3': pt_join(ev):
         'all three failures, in order');

end-proc;

//==============================================================================
// SCEXEC_status is UNCHANGED - it still returns the bare word
//
// SCAPI exposes it to bound callers who compare against a constant
// SC_PARTIAL of 'PARTIAL'. If the counts leak into this return value, those
// callers stop matching and nothing tells them: the comparison simply goes
// false. This test exists to fail loudly if the fix is made in the wrong
// place.
//
// Literals, not the SCOUT_* constants, on purpose: a change that redefined
// the constant would be invisible to a test written in terms of it.
//==============================================================================

dcl-proc test_status_still_returns_bare_words export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ptstat1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'load');
  aEqual('RUNNING': SCEXEC_status(def): 'running');

  clear def;
  assert(pt_load_def('ptstat2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999' + LF: def): 'load');
  aEqual('NOT RUNNING': SCEXEC_status(def): 'not running');

  clear def;
  assert(pt_load_def('ptstat3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55999' + LF: def): 'load');
  aEqual('PARTIAL': SCEXEC_status(def):
         'still the bare word - SC_PARTIAL in SCAPI compares against it');

end-proc;

//==============================================================================
// One evaluation, one set of answers
//
// SCEXEC_evaluate exists so the status and the failure list come from the SAME
// pass over the criteria. Two separate passes would disagree whenever a
// service changes state between them, and the row would then show a count that
// contradicts its own list. Asserting that evaluate and status agree is the
// closest a test can get to that from outside.
//==============================================================================

dcl-proc test_evaluate_agrees_with_status export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ptagree.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55999' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual(%trimr(SCEXEC_status(def)): %trimr(ev.state):
         'evaluate and status describe the same service the same way');

end-proc;

//==============================================================================
// A second copy of Block 1's fixture helpers: the suites are separate bound
// programs, so each needs its own.
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

//##############################################################################
//##                                                                          ##
//##  BLOCK A - paste into qtestsrc/SCEXEC.TEST.RPGLE                         ##
//##                                                                          ##
//##  Blocks B (SCOUT.TEST) and C (SCDEF.TEST) are already in their suites    ##
//##  and are not reproduced here.                                            ##
//##                                                                          ##
//##############################################################################
//
// Tests for UNUSABLE criteria - written before the fix, and red then. They
// pass now.
//
// A criterion can be UNUSABLE rather than merely UNSATISFIED:
//
//   check_alive: port
//   check_alive_criteria: abc
//
// names a port whose value is not a number. Nothing can ever be asked about
// it. Today RMSC converts the text to an integer at parse time without
// checking, so most of these do not fail an assertion - they end the job with
// RNX0105 and take the suite with them. That is the point: a test that cannot
// pass against the current code is the only kind that proves it can detect
// the defect (CLAUDE.md, "Test first").
//
//------------------------------------------------------------------------------
// THE PROPOSAL THESE TESTS ARE WRITTEN AGAINST - accepted, and declared
//------------------------------------------------------------------------------
//
// 1. SCDEF_load STORES THE TEXT AND DOES NOT CONVERT IT. A port criterion
//    keeps its text in .raw whatever that text is, and loading never fails
//    over it - measured: sc list and sc info are unaffected, and info prints
//    "Check-alive conditions: PORT:abc" and exits 0. .port is filled only
//    when the text is a usable port number, and left 0 otherwise.
//
//    This is where the crash is today, and moving the conversion is most of
//    the fix. It also makes the mixed-criteria path reachable from a test
//    without depending on what the YAML reader does with a list.
//
// 2. SCEXEC_EVAL_t GAINS THREE FIELDS - unusable_count, unusable_index,
//    unusable_text: THAT it happened, WHICH criterion, and enough to render
//    upstream's message.
//
//    A COUNT, not a flag, because zero and blank are then the "nothing wrong"
//    reading. A stale structure lies whatever the sense of the field, and
//    this way it lies in the same direction failed_count already does rather
//    than in a new one - see test_evaluate_does_not_inherit_a_previous_verdict.
//
//    NOT a fourth value in .state, which is like(SCOUT_STATUS_t) and goes
//    straight to SCOUT_check_row on the byte-exact path. .state is left BLANK
//    when unusable_count > 0, with alive, total, failed_count and failed_text
//    zero and blank: the defect being fixed is that unusable and unsatisfied
//    were one boolean, and leaving a plausible NOT RUNNING behind recreates
//    it one layer up.
//
//    USABILITY IS DECIDED FROM .raw BEFORE ANYTHING IS PROBED. It is a
//    property of the text, not of the machine, so a definition containing an
//    unusable criterion asks the machine nothing at all. That is what makes
//    the counts zero rather than partial.
//
// 3. WHAT MAKES A PORT VALUE USABLE:
//
//      usable  <=>  the text, trimmed, is an optional '+' or '-' followed by
//                   one or more ASCII digits, AND the value fits .port
//
//    Upstream's wording - "Invalid data for port number or job name criteria"
//    - is the wording of a parse failure, and sc is Java, so the reading is
//    Integer.parseInt in a try/catch. Hence 0, -1, +8080 and 65536 are all
//    USABLE: they parse, and simply can never be satisfied. One deliberate
//    departure, at test_port_too_large_for_the_field_is_unusable.
//
//    The leading '+' is MEASURED - criteria=+8080 gives rc 0, criteria=+22
//    gives rc 0. An earlier draft of this block called it unusable on the
//    grounds that a rule with one exception in it is a rule nobody can
//    apply. The rule simply has two signs in it, which is no harder to
//    apply and is what Java's parseInt has done since 7.
//
//    ONLY A PORT CRITERION CAN BE UNUSABLE - measured.
//
//    RENDERING: A CRITERION RENDERS ITS TEXT, ALWAYS. Measured against sc
//    1.7.1 since this block was first written, through sc info:
//
//      criteria=08080   -> PORT:08080      criteria=8080   -> PORT:8080
//      criteria= 8080   -> PORT:8080       criteria=-1     -> PORT:-1
//
//    A leading zero SURVIVES, so it is not the parsed number being printed.
//    An earlier draft of these tests had the rule as "the text when it
//    cannot be parsed, the number when it can", which fitted the evidence
//    then available - PORT:abc has no number to print - and is wrong. The
//    criterion holds the string throughout and only becomes a number when
//    something needs to look for a port.
//
//    TWO CONSEQUENCES, both live in this block:
//
//    - The number is still what gets PROBED. Text for rendering, number for
//      looking, from one field. test_criterion_used_as_number_rendered_as_text
//      pins both halves at once, because an implementation that renders from
//      the number and one that probes from the text both look right in every
//      other test here.
//
//    - Any criterion BUILT IN CODE rather than parsed must populate .raw, or
//      it renders as 'PORT:' with nothing after the colon. The ad-hoc
//      'port:445' specifier is the path where that could bite, and
//      docs/parity.md already records ad-hoc naming as a difference on the
//      byte-exact check path. The directly-built criteria below all set .raw
//      and .port together for exactly this reason.
//
// 4. SCEXEC_check_all GAINS A TRAILING COUNT of the services it could not
//    evaluate, options(*nopass) and LAST, so the export order RMSC.BND's
//    signature pins is untouched. The caller needs it to exit 253 and to
//    suppress the trailing blank line. As declared:
//
//      dcl-pr SCEXEC_check_all like(INTEGER_t);
//        coll          likeds(SCCOLL_t);
//        ignore_groups like(SCDEF_NAME_t) const;
//        unusable      like(INTEGER_t) options(*nopass);
//      end-pr;
//
//    THREE parameters. An earlier draft of this block called it with four,
//    having assumed it carried a group filter in third place the way
//    SCEXEC_list does. It does not, and never has - the two calls at lines
//    506 and 508 of this suite pass two. Nothing else in this block rested on
//    that assumption: none of the fixtures below declares a `groups:` key, so
//    there is no group to restrict to, and line 508 already establishes that
//    ignore_groups = '' visits every definition in the directory. Whatever
//    routes `check group:NAME` to a subset does it somewhere other than this
//    procedure's parameter list, and nothing here is about that.
//
//------------------------------------------------------------------------------
// CHOOSING A FIXTURE VALUE - the YAML typing hazard
//------------------------------------------------------------------------------
//
// READ THIS BEFORE ADDING A TEST HERE. Upstream's rendering is not upstream's
// doing at all: its YAML reader TYPES the scalar, and what sc prints is the
// typed value. Measured against sc 1.7.1:
//
//   022      -> PORT:18       YAML 1.1: a leading zero means OCTAL
//   0755     -> PORT:493      octal again
//   08080    -> PORT:08080    invalid octal, so it stays a string
//   '022'    -> PORT:022      quoted, so it stays a string
//   1_000    -> PORT:1000     YAML 1.1 digit separator
//   +8080    -> PORT:8080     typed as an integer, and the sign is gone
//
// RMSC's YAML parser does none of this, so for any such value the two
// implementations disagree - and the disagreement is OUT OF SCOPE BY
// DECISION, recorded in docs/parity.md. Teaching RMSC full YAML 1.1 scalar
// typing so that 'check_alive: 022' means port 18 is a large change whose
// only value is agreeing about definitions nobody writes deliberately.
//
// THE CONSEQUENCE FOR TESTS, which is what this note is for: an unquoted
// fixture value that YAML types differently from its own text would pin
// RMSC's behaviour as CORRECT in a place where it is in fact the known
// difference. A test like that passes, looks like evidence, and quietly
// asserts the opposite of what docs/parity.md says.
//
// So: any fixture value with a LEADING ZERO, an UNDERSCORE or a LEADING PLUS
// is QUOTED here, and the quoting is load-bearing - it is not stylistic and
// must not be tidied away. Quoted, both implementations keep the string, and
// the test is about RMSC's rule rather than about YAML's.
//
// Two existing values are safe by luck rather than by care, and are worth
// knowing about because the luck would not survive an edit:
//   -1     upstream prints the typed integer -1, RMSC prints the raw text
//          '-1'. They coincide. +1 would NOT have.
//   0      types as integer 0 and prints as '0'. 00 would not have.
//
// (The two paths also disagree with EACH OTHER upstream: plain
// 'check_alive: 08080' renders PORT:8080 - that path parses the string and
// prints the number - while the companion form renders PORT:08080. Nothing
// in this block depends on that, and it is recorded in docs/parity.md.)
//
//------------------------------------------------------------------------------
// BASIS OF EACH ASSERTION - read this before believing a failure
//------------------------------------------------------------------------------
//
//   MEASURED    taken from the side-by-side run against sc 1.7.1 quoted in
//               the case's own comment. A failure means RMSC differs from
//               upstream.
//   INFERRED    follows from the proposal above, itself reasoned from
//               measured behaviour. Ask whether the inference was wrong
//               before assuming the implementation is.
//   UNMEASURED  upstream's behaviour is genuinely unknown here. The test
//               states the most defensible reading and says what to do if the
//               box says otherwise. Do not relax one of these into a weaker
//               assertion - change it to the measured answer, and say so.
//   CHOSEN      this proposal deliberately does not follow the reading of
//               upstream, with the reason given. A failure is a decision to
//               revisit, not necessarily a defect.
//
//------------------------------------------------------------------------------
// WHAT THIS BLOCK NEEDS ADDING TO THE SUITE'S GLOBAL DECLARATIONS
//------------------------------------------------------------------------------
//
//   dcl-pr uc_is_status_word like(BOOLEAN_t);
//     word varchar(64) const;
//   end-pr;
//
//   dcl-pr uc_dir like(STMF_t) end-pr;
//
//   dcl-pr uc_load_named like(BOOLEAN_t);
//     dir     like(STMF_t) const;
//     name    like(STMF_t) const;
//     content like(STRING_t) const;
//     def     likeds(SCDEF_t);
//   end-pr;
//
//   dcl-pr uc_remove_dir;
//     dir like(STMF_t) const;
//   end-pr;
//
// It REUSES pt_load_def and pt_failed, already in the suite - a duplicate
// procedure will not compile.
//
// FIXTURES, all free, all asserted rather than skipped on:
//   - port 22 listens, because the suite arrived over SSH. The same fixture
//     SCQRY.TEST relies on and CLAUDE.md sanctions.
//   - ports 55997-55999 do not, and job NOSUCHJOB1 does not exist.
//   - 'abc' is not a number, on any machine.
//
// Every DS is inz(*likeds): docs/testing-notes.md, likeds() copies the
// subfield definitions and not the template's inz keyword.
//
// A NOTE ON aEqual AND BLANKS. Where a field is expected to be BLANK the
// assertion uses aEqualV, not aEqual. aEqual is declared char(32565)
// options(*varsize) const with operational descriptors, and a zero-length
// literal is a poor thing to hand that; aEqualV takes varchar and %trimr's
// both sides, which is exactly the question being asked. SCDEF.TEST already
// does this - aEqualV('': def.criteria(1).subsystem: 'no subsystem').
// Non-blank expectations keep aEqual, and array elements go through
// pt_failed, per docs/testing-notes.md.
//
// 01/09/2026 - RM - written against the change, before the change
//==============================================================================


//------------------------------------------------------------------------------
// uc_is_status_word - is this one of the three words SCEXEC_status may return
//
// Literals rather than the SCOUT_* constants on purpose, exactly as
// test_status_still_returns_bare_words does it: a change that redefined a
// constant would be invisible to a test written in terms of it.
//------------------------------------------------------------------------------
dcl-proc uc_is_status_word;
  dcl-pi *n like(BOOLEAN_t);
    word varchar(64) const;
  end-pi;

  dcl-s w varchar(64);

  w = %trimr(word);

  if w = 'RUNNING' or w = 'NOT RUNNING' or w = 'PARTIAL';
    return true;
  endif;

  return false;

end-proc;

//------------------------------------------------------------------------------
// uc_dir - a directory this block owns, guaranteed EMPTY on the way out
//
// pt_load_def deletes its fixture as soon as SCDEF_load has read it, which is
// right for a single definition and useless for the two collection cases
// below: those need three definitions present at once and NOTHING ELSE in the
// directory. The suite's g_dir cannot serve, because other tests write into
// it and under ORDER(*API) a count taken from it is a count of which tests
// ran first.
//
// It CLEARS the directory rather than only creating it. Both callers count
// what they find, so a test that failed halfway and returned before its
// tear-down would otherwise leave files behind and make the OTHER one fail
// for a reason that has nothing to do with it. A cascading failure sends the
// reader to the wrong test; docs/testing-notes.md makes the same argument
// about the flaky teardown in SCLIFE.TEST.
//
// Call it ONCE per test, at the top. Calling it twice would wipe the caller's
// own fixtures. Qualified by user because a fixed /tmp path belongs to
// whoever runs the suite first and is created 755.
//------------------------------------------------------------------------------
dcl-proc uc_dir;
  dcl-pi *n like(STMF_t);
  end-pi;

  dcl-s d like(STMF_t);

  d = '/tmp/rmsc-unusable-test-' + %trim(psds.current_user);

  uc_remove_dir(d);       // anything a previous failure left
  IFS_crtdir(d);

  return d;

end-proc;

//------------------------------------------------------------------------------
// uc_load_named - write a definition into a named directory and load it
//
// Unlike pt_load_def the fixture is LEFT in place, because the collection
// tests need several of them at once. Each caller removes the directory
// before returning, and uc_dir clears it on the way in as a second defence.
//------------------------------------------------------------------------------
dcl-proc uc_load_named;
  dcl-pi *n like(BOOLEAN_t);
    dir     like(STMF_t) const;
    name    like(STMF_t) const;
    content like(STRING_t) const;
    def     likeds(SCDEF_t);
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);

  path = %trim(dir) + '/' + %trim(name);

  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create fixture ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  return SCDEF_load(path: def);

end-proc;

//------------------------------------------------------------------------------
// uc_remove_dir - remove every .yaml in a directory, then the directory
//
// Silent about a directory that is not there: it is called both as a
// tear-down and as uc_dir's clean slate, and the second case is normally a
// no-op.
//------------------------------------------------------------------------------
dcl-proc uc_remove_dir;
  dcl-pi *n;
    dir like(STMF_t) const;
  end-pi;

  dcl-s handle   pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  handle = IFS_opendir(dir);
  if handle = *null;
    return;
  endif;

  dow IFS_readdir(handle: filename);
    if %len(filename) > 5
       and %subst(filename: %len(filename) - 4) = '.yaml';
      IFS_remove_file(%trim(dir) + '/' + %trim(filename));
    endif;
  enddo;

  IFS_closedir(handle);
  IFS_dltdir(dir);

end-proc;


//==============================================================================
// THE CANARY - an unusable port does not take the job down
//
// The minimal reproduction, and the first test to run when something here
// goes red. Today it does not fail an assertion; it ends the job with
// RNX0105 - "A character representation of a numeric value is in error" - and
// the whole suite goes with it. Everything below is only meaningful once this
// one reports rather than aborts.
//
// MEASURED that the definition itself is fine: sc list and sc info are
// unaffected by it and exit 0, and info renders "Check-alive conditions:
// PORT:abc". So loading must SUCCEED - a fix that made SCDEF_load reject the
// file would trade a crash for a different parity defect.
//==============================================================================

dcl-proc test_unusable_port_does_not_crash export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ucbad.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def):
    'a definition with an unusable port still LOADS - sc list and sc info ' +
    'are unaffected by one');

  iEqual(1: def.criteria_count: 'one criterion');

  SCEXEC_evaluate(def: ev);   // today: RNX0105, and the suite ends here

  assert((ev.unusable_count > 0):
         'evaluate returned, and said the criterion cannot be used');

end-proc;


//==============================================================================
// THE POINT OF THE WHOLE CHANGE - unusable is not unsatisfied
//
// Two definitions the old boolean could not tell apart:
//
//   PORT:abc    cannot be asked      -> upstream prints NO ROW, writes one
//                                       line to stderr, exits 253
//   PORT:55999  asked, answered no   -> upstream prints NOT RUNNING, exits 0
//
// MEASURED for both halves. The two stdout results and the two exit statuses
// are not comparable from inside the job; what IS comparable is that the
// structure describing them differs, and that a caller can tell which is
// which without guessing.
//==============================================================================

dcl-proc test_unusable_is_distinguished_from_unsatisfied export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // Unusable: the text is not a port number
  assert(pt_load_def('ucdist1.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load unusable');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'one criterion cannot be used');
  iEqual(0: ev.failed_count:
         'and it is NOT reported as a failed check - nothing was checked');

  // Unsatisfied: a perfectly good port number nothing is listening on
  clear ev;
  clear def;
  assert(pt_load_def('ucdist2.yaml':
    'name: ZZ dead' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 55999' + LF: def): 'load unsatisfied');

  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count: 'a dead port is perfectly usable');
  iEqual(1: ev.failed_count: 'it is a failed check');
  aEqual('NOT RUNNING': ev.state: 'and it has a status');

end-proc;


//==============================================================================
// WHICH criterion, and rendered ready for the message
//
// MEASURED - the stderr line names the criterion in the same PORT:value form
// SCDEF_criterion_text already produces for every other criterion:
//
//   Invalid data for port number or job name criteria for service 'ZZ bad': PORT:abc
//
// unusable_index is asserted as well as the text because the text alone does
// not identify WHICH of several identical-looking criteria was rejected, and
// a caller wanting to say more than upstream does needs the subscript.
//==============================================================================

dcl-proc test_unusable_names_the_criterion export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ucname.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_index: 'the first criterion is the one rejected');
  aEqual('PORT:abc': ev.unusable_text:
         'rendered the way the message renders it - its text, which is ' +
         'what a criterion always renders, not a fallback for when there ' +
         'is no number');

end-proc;


//==============================================================================
// INFERRED - an unusable criterion leaves no counts to misread
//
// state blank, alive/total/failed_count zero, nothing in failed.
//
// Not measured, and could not be: upstream prints no row for this service at
// all, so no capture can show what it thought the counts were. It is asserted
// because the alternative - a plausible NOT RUNNING and a partial count left
// behind - is the shape of the defect being fixed, one layer up. A caller
// that reads state without reading unusable_count then prints a row upstream
// does not print, with numbers describing a walk that never happened.
//
// total is deliberately 0 rather than 1. Usability is settled for every
// criterion BEFORE anything is probed, so a definition containing an unusable
// one asks the machine nothing. A total of 1 would say a criterion was
// counted, which invites a caller to compute alive/total from it.
//
// CHOSEN. If the fix prefers to keep the counts populated up to the point of
// failure, that is arguable - but then say so here and assert the values it
// does produce, rather than deleting the test.
//==============================================================================

dcl-proc test_unusable_leaves_no_partial_counts export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ucempty.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqualV('': ev.state:
          'blank - not a status word, so a caller that ignores ' +
          'unusable_count is obviously wrong rather than plausibly wrong');
  nEqual(false: uc_is_status_word(ev.state):
         'and specifically not one of the three');
  iEqual(0: ev.alive:  'nothing was probed');
  iEqual(0: ev.total:  'so nothing was counted either');
  iEqual(0: ev.failed_count: 'and nothing failed - it was never asked');
  aEqualV('': ev.failed_text: 'no suffix material');
  aEqual('*OUT-OF-RANGE*': pt_failed(ev: 1): 'the failed array is empty');

end-proc;


//==============================================================================
// A definition mixing an unusable criterion with a usable one
//
// Built directly rather than through YAML, for two reasons.
//
// First, YAML CANNOT express the mix - now measured, by the test below, which
// asked whether check_alive_criteria splits on commas and was answered no. A
// companion value is one criterion whatever is in it, and one criterion is
// either usable or not. So direct construction is not merely convenient here,
// it is the only way to reach the path at all.
//
// Second, and more important: the loop over criteria is generic, so it must
// behave whether or not YAML can produce the input. Building the criteria
// here reaches the path regardless - the same argument test_status_no_criteria
// already makes for a definition with no check_alive at all.
//
// Building them is only possible BECAUSE of part 1 of the proposal: the text
// lives in .raw and usability is decided from it at evaluate time. If that is
// not how the fix works, this test cannot be written - which is itself an
// argument for the design.
//
// INFERRED that one bad criterion condemns the whole service. Measured only
// for a service whose ONLY criterion is bad. The reading: upstream discovers
// the problem when it tries to USE the criterion, and the resulting exception
// leaves the service with no row - there is no partial row in any capture and
// no mechanism by which half a service could print.
//
// The unusable criterion is placed SECOND here and FIRST in the second half,
// so a pass cannot be an accident of position - the trick
// test_evaluate_failures_join_in_declared_order already uses.
//==============================================================================

dcl-proc test_unusable_mixed_with_usable_built_directly export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // usable first, unusable second
  def.criteria_count   = 2;
  def.criteria(1).kind = SCDEF_CHECK_PORT;
  def.criteria(1).raw  = '22';
  def.criteria(1).port = 22;
  def.criteria(2).kind = SCDEF_CHECK_PORT;
  def.criteria(2).raw  = 'abc';
  def.criteria(2).port = 0;

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'one of the two cannot be used');
  iEqual(2: ev.unusable_index: 'and it is the second one');
  aEqual('PORT:abc': ev.unusable_text: 'named by its text');
  aEqualV('': ev.state:
          'a live port alongside it does not rescue the service - upstream ' +
          'prints no row for a service it could not evaluate');
  iEqual(0: ev.alive:
         'and the live port was never probed: usability is settled first');

  // unusable first, usable second
  clear ev;
  clear def;
  def.criteria_count   = 2;
  def.criteria(1).kind = SCDEF_CHECK_PORT;
  def.criteria(1).raw  = 'abc';
  def.criteria(1).port = 0;
  def.criteria(2).kind = SCDEF_CHECK_PORT;
  def.criteria(2).raw  = '22';
  def.criteria(2).port = 22;

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'still one');
  iEqual(1: ev.unusable_index: 'now the first');
  aEqualV('': ev.state: 'still no status, whichever order they arrive in');

end-proc;


//==============================================================================
// MEASURED - the companion does NOT split on commas
//
// This test asked whether check_alive_criteria splits on commas the way
// check_alive does. Its PREMISE assertion answered: it does not. Measured
// against sc 1.7.1:
//
//   criteria=8080,abc   info=[PORT:8080,abc]   check rc=253  Invalid data...
//   criteria=22,55999   info=[PORT:22,55999]   check rc=253  Invalid data...
//
// The value is ONE criterion, kept whole, and it is UNUSABLE - the whole
// string is offered to the port conversion and the whole string fails.
//
// The second row is the one worth pausing on: 22 and 55999 are both perfectly
// good ports, and together they are still one unusable criterion. So an
// implementation that "helpfully" split the companion would turn an
// upstream error into a running service. That is why this test survived
// rather than being deleted when its premise was rejected - the premise was
// wrong, and the correct behaviour is worth pinning precisely because
// splitting looks like an improvement.
//
// THE TWO PATHS DIFFER, and this is the whole of it:
//   check_alive: 22,55999                    -> TWO criteria (existing tests)
//   check_alive: port + criteria: 22,55999   -> ONE criterion, unusable
//
// It also settles how a mixed usable/unusable definition can be reached: not
// through the companion, which cannot express one, but only by building the
// criteria directly - which is what the test above does, and why it was
// written that way before this was known.
//==============================================================================

dcl-proc test_companion_comma_list_is_one_unusable_criterion export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // one good port and one non-number
  assert(pt_load_def('uclist1.yaml':
    'name: ZZ list' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 8080,abc' + LF: def): 'load');

  iEqual(1: def.criteria_count:
         'ONE criterion - the companion does not split on commas, and the ' +
         'plain check_alive form is the only one that does');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'and the whole thing is unusable');
  aEqual('PORT:8080,abc': ev.unusable_text:
         'reported whole, exactly as sc info renders it');

  // TWO good ports - still one criterion, still unusable
  clear ev;
  clear def;
  assert(pt_load_def('uclist2.yaml':
    'name: ZZ list two' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 22,55999' + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count:
         'two valid ports are still not a port - splitting this would turn ' +
         'an upstream error into a running service');
  aEqual('PORT:22,55999': ev.unusable_text: 'reported whole');
  aEqualV('': ev.state: 'and no status, as for any unusable criterion');

end-proc;

//==============================================================================
// INFERRED - two unusable criteria are counted, and the FIRST is named
//
// Upstream prints one message per bad SERVICE - measured, with two bad
// services giving one line each in sort order. What it does with two bad
// criteria in ONE service is unmeasured, and only one of them can appear in a
// single-line message.
//
// The reading: the message names the criterion that stopped the walk, which
// is the first in declaration order. The count is still honest about how many
// there were, because it costs nothing and because a caller that wants to
// report all of them should not have to re-derive what evaluate already knew.
//==============================================================================

dcl-proc test_two_unusable_criteria export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  def.criteria_count   = 3;
  def.criteria(1).kind = SCDEF_CHECK_PORT;
  def.criteria(1).raw  = '22';
  def.criteria(1).port = 22;
  def.criteria(2).kind = SCDEF_CHECK_PORT;
  def.criteria(2).raw  = 'abc';
  def.criteria(2).port = 0;
  def.criteria(3).kind = SCDEF_CHECK_PORT;
  def.criteria(3).raw  = 'xyz';
  def.criteria(3).port = 0;

  SCEXEC_evaluate(def: ev);

  iEqual(2: ev.unusable_count: 'both counted');
  iEqual(2: ev.unusable_index: 'the first unusable one is named');
  aEqual('PORT:abc': ev.unusable_text:
         'and it is the first in declaration order, not the last found');

end-proc;


//==============================================================================
// SCEXEC_status still returns one of the three words
//
// The hard contract. SCAPI exposes it to bound callers who compare the result
// against a constant, and a fourth value - or a blank - makes those
// comparisons go quietly false with nothing to report it. The same argument
// test_status_still_returns_bare_words makes, extended to the one input that
// did not previously return at all.
//
// Membership only. WHICH of the three is a separate decision with its own
// test below, so a disagreement about the choice cannot take the contract
// down with it.
//==============================================================================

dcl-proc test_status_returns_a_word_for_an_unusable_criterion export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ucstat1.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load');

  nEqual(true: uc_is_status_word(SCEXEC_status(def)):
         'RUNNING, NOT RUNNING or PARTIAL - never blank, never a fourth ' +
         'word: a bound caller compares this against a constant');

end-proc;

//==============================================================================
// CHOSEN - and the word is NOT RUNNING
//
// SCEXEC_status cannot express "unusable" - it returns a single word, and its
// three words are its contract. So it has to answer something, and the
// defensible answer is the one that does not claim a service is up: a service
// whose criteria cannot be evaluated is certainly not known to be running.
//
// Note the asymmetry with ev.state, which is BLANK for the same definition.
// It is deliberate. ev.state travels with unusable_count, so a caller has
// something better to read and a blank pushes it to read it. SCEXEC_status
// travels alone, so a blank there is just a fourth value with no name.
//
// If this is decided the other way - PARTIAL, or a fourth SCAPI constant -
// change this test and leave the membership test above alone.
//==============================================================================

dcl-proc test_status_for_an_unusable_criterion_is_not_running export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(pt_load_def('ucstat2.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load');

  aEqual('NOT RUNNING': SCEXEC_status(def):
         'a service that cannot be evaluated is not known to be running');

end-proc;


//==============================================================================
// A definition with only usable criteria is unchanged in EVERY respect
//
// The regression guard for the change. Every assertion here passes today; if
// the fix breaks one it has broken the byte-exact check path, because these
// are the values SCOUT renders.
//
// All three states are exercised, and the new fields asserted CLEAN in each -
// a fix that set them speculatively would make every good service look
// suspect to a caller that checks them first.
//==============================================================================

dcl-proc test_usable_definitions_are_unchanged export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // RUNNING
  assert(pt_load_def('ucok1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  aEqual('RUNNING': ev.state: 'state');
  iEqual(1: ev.alive:  'alive');
  iEqual(1: ev.total:  'total');
  iEqual(0: ev.failed_count:   'nothing failed');
  iEqual(0: ev.unusable_count: 'nothing unusable');
  iEqual(0: ev.unusable_index: 'no index');
  aEqualV('': ev.unusable_text: 'no text');

  // NOT RUNNING
  clear ev;
  clear def;
  assert(pt_load_def('ucok2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999,NOSUCHJOB1' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  aEqual('NOT RUNNING': ev.state: 'state');
  iEqual(0: ev.alive:  'alive');
  iEqual(2: ev.total:  'total');
  iEqual(2: ev.failed_count: 'both failed');
  aEqual('PORT:55999':         pt_failed(ev: 1): 'first failure');
  aEqual('JOBNAME:NOSUCHJOB1': pt_failed(ev: 2): 'second failure');
  iEqual(0: ev.unusable_count: 'nothing unusable');
  aEqualV('': ev.unusable_text: 'no text');

  // PARTIAL
  clear ev;
  clear def;
  assert(pt_load_def('ucok3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,55999' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  aEqual('PARTIAL': ev.state: 'state');
  iEqual(1: ev.alive:  'alive');
  iEqual(2: ev.total:  'total');
  iEqual(1: ev.failed_count: 'one failed');
  aEqual('PORT:55999': pt_failed(ev: 1): 'the failure');
  iEqual(0: ev.unusable_count: 'nothing unusable');
  iEqual(0: ev.unusable_index: 'no index');
  aEqualV('': ev.unusable_text: 'no text');

end-proc;


//==============================================================================
// A reused structure does not inherit the previous verdict
//
// The trap docs/testing-notes.md points at: `clear` on a data structure
// resets to BLANKS, not to the template's inz, and an uninitialised or reused
// SCEXEC_EVAL_t carries plausible-looking counts off the stack.
//
// SCEXEC_check_all walks a collection reusing one structure, so this is not
// hypothetical: a bad service followed by a good one is exactly what the
// measured capture contains. If evaluate only SETS the new fields and never
// clears them, every service after the first bad one inherits its verdict and
// vanishes from the listing - silently, since a vanished row raises nothing.
//
// Deliberately NOT clearing ev between the calls: that is the whole test. The
// reverse direction is checked too, since a fix that clears on the way in but
// not on the way out fails only one of them.
//==============================================================================

dcl-proc test_evaluate_does_not_inherit_a_previous_verdict export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // bad, then good, into the SAME structure
  assert(pt_load_def('ucreuse1.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load the bad one');
  SCEXEC_evaluate(def: ev);
  assert((ev.unusable_count > 0): 'the bad one is bad');

  clear def;              // the DEFINITION is replaced; ev deliberately is not
  assert(pt_load_def('ucreuse2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'load the good one');
  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count:
         'evaluate cleared the previous verdict - otherwise every service ' +
         'after a bad one in a walk inherits it and vanishes');
  iEqual(0: ev.unusable_index: 'and the index with it');
  aEqualV('': ev.unusable_text: 'and the text');
  aEqual('RUNNING': ev.state: 'and it reports its own state');

  // good, then bad, same structure - the other direction
  clear def;
  assert(pt_load_def('ucreuse3.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'load the bad one again');
  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'the verdict arrives');
  iEqual(0: ev.alive: 'and the previous run''s counts are gone');
  iEqual(0: ev.total: 'both of them');
  aEqualV('': ev.state: 'and the previous state word with them');

end-proc;


//==============================================================================
// MEASURED - only a PORT criterion can be unusable
//
//   check_alive: jobname
//   check_alive_criteria: A_VERY_LONG_JOB_NAME_INDEED
//
// gives exit 0 and NOT RUNNING on sc 1.7.1. No error, despite the message
// text mentioning job names, and despite 27 characters being far longer than
// the 10 an IBM i job name can hold.
//
// That last part is why this earns its place rather than being an obvious
// pass: RMSC puts the job name into an SQL parameter, and a value too long
// for the field is the same class of defect as a port too large for its own -
// a truncation to 'A_VERY_LON' would match some other job, or the query would
// fail, and either way nothing would say so. The assertion is therefore NOT
// RUNNING specifically, not merely "did not crash".
//==============================================================================

dcl-proc test_long_job_name_is_usable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('uclongjob.yaml':
    'name: ZZ longjob' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: jobname' + LF +
    'check_alive_criteria: A_VERY_LONG_JOB_NAME_INDEED' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count:
         'a job name of any length or shape is accepted - measured, sc 1.7.1');
  aEqual('NOT RUNNING': ev.state: 'and it is simply not running');
  iEqual(1: ev.total: 'the criterion was counted, so it WAS probed');
  iEqual(1: ev.failed_count: 'and it answered no');

end-proc;


//==============================================================================
//  PORT BOUNDARIES - what makes a value usable
//
//  Only 'abc' is measured. Everything below is reasoned from the proposal's
//  rule and marked. The rule again:
//
//    usable  <=>  trimmed text is [-]digits AND the value fits .port
//
//  Grouped into four tests rather than a dozen so a failure report stays
//  readable, with a field name on every assertion saying which value it was.
//==============================================================================

//------------------------------------------------------------------------------
// INFERRED - whitespace around the number does not make it unusable
//
// A plain YAML scalar is already trimmed by the reader before RMSC sees it,
// so the unquoted case really tests that nothing UN-trims it. The quoted case
// is the interesting one: "22 " keeps its trailing space through YAML, and
// Java's Integer.parseInt would REJECT that - upstream might well call it
// unusable.
//
// STILL UNMEASURED for the quoted form. The measured run shows
// 'criteria= 8080' rendering as PORT:8080, and it is tempting to read that as
// the store trimming the value - but an unquoted YAML scalar has already been
// trimmed by the READER before anything else sees it, so that observation is
// equally explained by YAML and settles nothing about the quoted case.
//
// WHAT WOULD SETTLE IT: read 'check_alive_criteria: "8080 "' back through sc
// info. PORT:8080 means the store trims; PORT:8080 with a trailing space
// means it does not, and then whether it is usable is a separate question
// again.
//
// Until then the reading chosen is the forgiving one: RMSC trims scalar
// values elsewhere, a port with a stray space is unmistakably a port, and
// refusing it would make a service vanish from a listing over whitespace. If
// the box says upstream rejects it, this is the assertion to change - and
// docs/parity.md gains a line, because it is then a deliberate difference
// rather than a defect.
//------------------------------------------------------------------------------

dcl-proc test_port_surrounding_space_is_usable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // unquoted: YAML trims this before RMSC sees it
  assert(pt_load_def('ucsp1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria:   22  ' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: 'unquoted spaces: usable');
  aEqual('RUNNING': ev.state:
         'and it is the SSH port, so the value survived the trim intact');

  // quoted: the trailing space reaches the port conversion
  clear ev;
  clear def;
  assert(pt_load_def('ucsp2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: "22 "' + LF: def): 'load');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count:
         'quoted trailing space: usable - UNMEASURED, the forgiving ' +
         'reading, see the comment');
  aEqual('RUNNING': ev.state: 'and still the SSH port');

end-proc;

//------------------------------------------------------------------------------
// A value that parses but can never be satisfied is USABLE
//
// INFERRED throughout, from the parseInt reading. Zero, a negative, and
// anything above 65535 are all perfectly good integers; they simply name a
// port on which nothing can be listening. Upstream reports the service NOT
// RUNNING and exits 0 - it never gets as far as complaining.
//
// The distinction matters because the obvious over-correction to the crash is
// to validate the RANGE at the same time as the syntax, which would turn
// three ordinary NOT RUNNING services into three error lines and three
// exit-253 runs. That is a worse parity defect than the one being fixed, and
// harder to see.
//
// These are also the values most likely to make the socket query itself fail:
// -1 and 999999 do not fit an unsigned 16-bit port, so a query built without
// checking may error rather than answer. The assertion is NOT RUNNING
// specifically for exactly that reason.
//------------------------------------------------------------------------------

dcl-proc test_port_out_of_range_is_usable_but_never_alive export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // zero
  assert(pt_load_def('ucr1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 0' + LF: def): 'load 0');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: 'port 0 parses, so it is usable');
  aEqual('NOT RUNNING': ev.state: 'and nothing is listening on it');
  aEqual('PORT:0': pt_failed(ev: 1): 'listed as an ordinary failure');

  // negative
  clear ev;
  clear def;
  assert(pt_load_def('ucr2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: -1' + LF: def): 'load -1');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count:
         'a negative parses too - the sign is part of an integer');
  aEqual('NOT RUNNING': ev.state:
         'and the query must ANSWER rather than fail on it');
  aEqual('PORT:-1': pt_failed(ev: 1):
         'MEASURED - sc info renders PORT:-1, so the sign survives both ' +
         'the usability test and the rendering. The two implementations ' +
         'agree here by coincidence: upstream prints the typed integer -1, ' +
         'RMSC prints the raw text. +1 would NOT have agreed - see the ' +
         'header note on YAML typing');

  // one past the top of the port range
  clear ev;
  clear def;
  assert(pt_load_def('ucr3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 65536' + LF: def): 'load 65536');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: '65536 parses');
  aEqual('NOT RUNNING': ev.state: 'and cannot be listening');

  // well past it, still inside a 10-digit field
  clear ev;
  clear def;
  assert(pt_load_def('ucr4.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 999999' + LF: def): 'load 999999');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: 'longer than a port can be, still a number');
  aEqual('NOT RUNNING': ev.state: 'and still merely not running');

  // a leading plus. MEASURED as usable: criteria=+8080 and criteria=+22 both
  // give rc 0. QUOTED, and the quotes are load-bearing - unquoted, YAML types
  // the scalar as an integer and upstream prints PORT:8080 with the sign
  // gone, which is the out-of-scope difference in the header note. Quoted,
  // both implementations keep the string and this test is about the
  // usability rule rather than about YAML.
  //
  // 55999 rather than 8080 because nothing is listening on it, so the state
  // is deterministic on any box.
  clear ev;
  clear def;
  assert(pt_load_def('ucr5.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: "+55999"' + LF: def): 'load +55999');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count:
         'a leading plus parses - MEASURED, rc 0 on sc 1.7.1');
  aEqual('NOT RUNNING': ev.state: 'and nothing is listening on 55999');
  aEqual('PORT:+55999': pt_failed(ev: 1):
         'rendered from the text, so the sign is still there - upstream ' +
         'agrees for a QUOTED value; unquoted it prints PORT:55999');

end-proc;

//------------------------------------------------------------------------------
// A value that is not a number is UNUSABLE
//
// 'abc' is MEASURED. The rest are INFERRED from the same rule, and each is a
// shape a naive conversion gets wrong in a DIFFERENT way, which is why they
// are all here rather than just the one:
//
//   abc      MEASURED - no digits at all
//   12ab     digits FIRST: %int() and friends stop at the first non-digit on
//            some paths and yield 12 - a silently wrong port, the worst
//            outcome available
//   ab12     digits last
//   80 80    an interior space, which trimming does not remove
//   8080.0   a decimal point: numeric to a human, not an integer. YAML types
//            it as a FLOAT, so upstream prints PORT:8080.0 and RMSC prints
//            the same raw text - they agree, and only usability is asserted
//            below in any case
//   (empty)  no value at all - see below
//
// A LEADING PLUS USED TO BE HERE and has moved to the usable test, where it
// belongs: criteria=+8080 and criteria=+22 both give rc 0 on sc 1.7.1. The
// argument for calling it unusable was that a rule with an exception in it is
// a rule nobody can apply - which was true of the rule and false about the
// world. The rule now reads [+|-]digits and has no exception.
//
// THE EMPTY CASE IS A LAYERING QUESTION, and is asserted at the evaluate
// layer only: a criterion whose text is empty cannot name a port, so it is
// unusable. What SCDEF does with an EMPTY companion in YAML is separate and
// UNMEASURED - it may reasonably treat 'check_alive_criteria:' with no value
// as no companion at all, which by test_criteria_companion_absent would make
// the definition a job called PORT. That is why this half is built directly
// rather than loaded: it tests the rule, not the reader. If SCDEF is later
// decided to reject an empty companion outright, this stays correct and
// untouched.
//------------------------------------------------------------------------------

dcl-proc test_port_not_a_number_is_unusable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // digits first - the dangerous one
  assert(pt_load_def('ucn1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 12ab' + LF: def): 'load 12ab');
  SCEXEC_evaluate(def: ev);
  iEqual(1: ev.unusable_count:
         '12ab is not a port - and specifically must not become port 12');
  aEqual('PORT:12ab': ev.unusable_text: 'reported as written');

  // digits last
  clear ev;
  clear def;
  assert(pt_load_def('ucn2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: ab12' + LF: def): 'load ab12');
  SCEXEC_evaluate(def: ev);
  iEqual(1: ev.unusable_count: 'ab12 is not a port either');
  aEqual('PORT:ab12': ev.unusable_text: 'reported as written');

  // an interior space
  clear ev;
  clear def;
  assert(pt_load_def('ucn3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: "80 80"' + LF: def): 'load 80 80');
  SCEXEC_evaluate(def: ev);
  iEqual(1: ev.unusable_count:
         'trimming the ends does not make an interior space go away');

  // a decimal point
  clear ev;
  clear def;
  assert(pt_load_def('ucn4.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 8080.0' + LF: def): 'load 8080.0');
  SCEXEC_evaluate(def: ev);
  iEqual(1: ev.unusable_count: 'a port number is an integer, not a number');

  // empty text, built directly: this is the RULE, not the YAML reader
  clear ev;
  clear def;
  def.criteria_count   = 1;
  def.criteria(1).kind = SCDEF_CHECK_PORT;
  def.criteria(1).raw  = '';
  def.criteria(1).port = 0;
  SCEXEC_evaluate(def: ev);
  iEqual(1: ev.unusable_count: 'no text cannot name a port');
  aEqual('PORT:': ev.unusable_text:
         'and the message renders what there was, which is nothing');

end-proc;

//------------------------------------------------------------------------------
// The criterion is used as a NUMBER and rendered as TEXT
//
// Both halves in one test, because they are the same field read two ways and
// an implementation that gets either half wrong passes every other test here.
//
// A leading zero is the only input that tells them apart. '022' and '22' are
// the same port and different strings, so:
//
//   - if '022' does not come back RUNNING, the probe used the text
//   - if '055999' renders as PORT:55999, the rendering used the number
//
// BOTH VALUES ARE QUOTED, AND THE QUOTES ARE LOAD-BEARING. Unquoted, a
// leading zero is OCTAL to YAML 1.1: upstream reads 022 as the integer 18 and
// prints PORT:18. An earlier version of this test used unquoted 022, which
// would have pinned RMSC's reading of it as 22 as CORRECT - in the one place
// docs/parity.md records the two as deliberately differing. See the header
// note on YAML typing.
//
// 055999 was safe unquoted only because 9 is not an octal digit, so upstream
// falls back to a string and the two happen to agree. That is an accident
// that would evaporate the moment somebody changed the port number, so it is
// quoted too. Quoted, both implementations keep the string, and this test is
// about RMSC's own rule rather than about YAML.
//
// MEASURED for the rendering: sc info on '022' prints PORT:022. INFERRED that
// the SAME rendering reaches ev.failed, which the interface describes as
// holding criteria "already rendered". It has to be inferred - upstream
// prints no suffix for a NOT RUNNING service, so no capture shows the failure
// list for one. It is asserted because the alternative is two renderings of
// the same criterion in the codebase, one for info and one for the check
// suffix, free to drift apart - which is exactly what
// SCOUT_not_running_suffix's pass-through contract exists to prevent, one
// layer down.
//------------------------------------------------------------------------------

dcl-proc test_criterion_used_as_number_rendered_as_text export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  // a live port, written with a leading zero: the NUMBER is what gets probed
  assert(pt_load_def('uczero1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: "022"' + LF: def): 'load "022"');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: '022 is digits, so it is usable');
  aEqual('RUNNING': ev.state:
         'and it found the SSH listener - so the probe used the value 22, ' +
         'not the string');

  // a dead port, same shape: the TEXT is what gets rendered
  clear ev;
  clear def;
  assert(pt_load_def('uczero2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: "055999"' + LF: def): 'load "055999"');
  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count: 'usable');
  aEqual('NOT RUNNING': ev.state: 'and nothing is listening on 55999');
  aEqual('PORT:055999': pt_failed(ev: 1):
         'the leading zero survives into the failure list - a criterion ' +
         'renders its text, always');

end-proc;

//------------------------------------------------------------------------------
// CHOSEN - a number too large for the field is UNUSABLE, not truncated
//
// The one deliberate departure from the parseInt reading. Java has a long to
// fall back on and would report a parse failure at some width; ILE has a
// fixed-width .port field and no exception unless one is raised deliberately.
//
// The three outcomes available are: truncate (4294967296 becomes 0 - a wrong
// answer with no error, the exact failure mode this file exists to remove),
// crash (what happens today), or refuse. Refusing is the only one that tells
// anybody anything, and it lands on the code path that already exists for
// 'abc', so it costs nothing to implement.
//
// The value is 20 digits: too wide for any plausible .port declaration, so
// this test does not encode a guess about that field's actual size. If .port
// is widened later, it still passes.
//
// If the fix instead follows upstream exactly and lets a huge value through,
// say what it does with it - and record the difference in docs/parity.md,
// because a truncated port silently checks the wrong thing.
//------------------------------------------------------------------------------

dcl-proc test_port_too_large_for_the_field_is_unusable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(pt_load_def('ucbig.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: 99999999999999999999' + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count:
         'too wide for the field: refused, never truncated');
  aEqual('PORT:99999999999999999999': ev.unusable_text:
         'and reported as written, so the message shows the real value');

end-proc;


//==============================================================================
// A walk skips the bad service and keeps going
//
// The closest an in-job test can get to the measured stdout:
//
//   $ sc check
//     RUNNING            | mapepire (Mapepire Server)
//   Invalid data for port number or job name criteria for service 'ZZ bad': PORT:abc
//     NOT RUNNING        | rmcbackend (RMCBACKEND)
//     RUNNING            | zzzlast (Z last)
//
// MEASURED: the bad service contributes NO ROW, and every other service still
// prints, in the usual order - the walk is not abandoned. SCEXEC_check_all
// already returns the number of services it displayed, so three definitions
// with one bad one must return 2. Nothing else in the suite would notice if a
// bad service took the rest of the listing with it.
//
// The unusable COUNT is part 4 of the proposal and is what the caller needs
// in order to exit 253 and to suppress the trailing blank line.
//
// The bad definition is named so it sorts in the MIDDLE: a walk that stopped
// at the first error would still return 1 for a bad definition sorted last,
// and this would pass while proving nothing.
//
// ignore_groups is '' - exclude nothing. None of these fixtures declares a
// `groups:` key, and line 508 of this suite already establishes that '' visits
// every definition in the directory. check_all has no group-filter parameter;
// SCEXEC_list is the one that does.
//
// Own directory, cleaned up before returning: ORDER(*API), no test may depend
// on another's fixture.
//==============================================================================

dcl-proc test_check_all_skips_the_unusable_and_continues export;

  dcl-ds coll      likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def       likeds(SCDEF_t)  inz(*likeds);
  dcl-s  d         like(STMF_t);
  dcl-s  bad       like(INTEGER_t);
  dcl-s  displayed like(INTEGER_t);

  d   = uc_dir();
  bad = -1;               // so a procedure that never writes it is caught

  assert(uc_load_named(d: 'ucwalk1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'first, good');

  assert(uc_load_named(d: 'ucwalk2.yaml':
    'name: ZZ bad' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: port' + LF +
    'check_alive_criteria: abc' + LF: def): 'second, unusable');

  assert(uc_load_named(d: 'ucwalk3.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999' + LF: def): 'third, good');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(3: SCCOLL_count(coll):
         'three definitions, and nothing else in the directory');

  // The monitor wraps ONLY the walk, and only so the fixtures are removed
  // when it blows up - which today it does, with RNX0105. It must not wrap
  // the assertions: iRPGUnit signals an escape message to fail one, so a
  // monitor round them would catch a genuine failure and report it as a
  // crash. The assertions are therefore made after the fixtures are gone.
  monitor;
    displayed = SCEXEC_check_all(coll: '': bad);
  on-error;
    uc_remove_dir(d);
    assert((1 = 2): 'the walk raised an exception rather than reporting - ' +
                    'today RNX0105, and the rest of the suite goes with it');
  endmon;

  uc_remove_dir(d);

  iEqual(2: displayed:
         'two rows displayed - the unusable service contributes none, and ' +
         'the one after it still does');
  iEqual(1: bad: 'and one service could not be evaluated');

end-proc;

//==============================================================================
// A walk over good services reports no errors
//
// The other half, and the one that catches a fix reporting an error for every
// service or for none. Without it, an implementation that always set the
// count to 1 would pass the test above.
//
// bad starts at -1 so a procedure that never writes the parameter at all -
// the likeliest way an options(*nopass) output goes wrong - is caught rather
// than mistaken for a zero.
//==============================================================================

dcl-proc test_check_all_reports_no_errors_when_all_usable export;

  dcl-ds coll      likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def       likeds(SCDEF_t)  inz(*likeds);
  dcl-s  d         like(STMF_t);
  dcl-s  bad       like(INTEGER_t);
  dcl-s  displayed like(INTEGER_t);

  d   = uc_dir();
  bad = -1;

  assert(uc_load_named(d: 'ucclean1.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22' + LF: def): 'first');
  assert(uc_load_named(d: 'ucclean2.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 55999' + LF: def): 'second');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  displayed = SCEXEC_check_all(coll: '': bad);

  uc_remove_dir(d);

  iEqual(2: displayed: 'both displayed');
  iEqual(0: bad: 'and neither was unusable');

end-proc;

//==============================================================================
// SCEXEC_groups - the `groups` operation
//
// It had no test at all. The gate holds `groups` byte-exact against a
// captured baseline, which covers this system's real definitions and nothing
// else: no baseline on this box has a definition that DECLARES a group called
// system, none is taken with --ignore-globals, and none is taken with an
// exclusion that empties a group. Those are the three cases below that a
// baseline cannot reach.
//
// WHAT CAN BE OBSERVED. SCEXEC_groups prints one row per group name to
// standard output and returns the number of rows it printed. A test running
// inside the job cannot capture stdout, so the count is the whole of the
// evidence, and every case below is chosen so the COUNT alone discriminates.
// Two things follow, and both are limitations worth stating rather than
// working around:
//
//   - The sorted POSITION of the built-in system entry cannot be asserted
//     here. That it is inserted in order rather than appended is the gate's
//     to hold, byte for byte. What these tests hold is that it is printed
//     exactly once, in the cases where it is printed at all.
//   - Which names were printed cannot be asserted either. The fixtures are
//     therefore arranged so that a wrong SET of names is also a wrong COUNT -
//     a group whose only declarers are excluded takes the count down with it,
//     and a system printed twice takes it up.
//
// Fixture group names sort deliberately either side of 'system': grpbef_*
// before it (0x67) and zgrpaft_* after it (0x7A). Nothing here can see the
// difference, for the reason above; the names are chosen so that when
// something CAN - a baseline, or a later test with an output capture - the
// two insertion branches are already covered by fixtures rather than needing
// new ones.
//
// COVERAGE, NOT A KNOWN DEFECT. Unlike the trailing-comma tests in
// SCCOLL.TEST these are expected to pass as written. They are here because
// nothing exercised this procedure at all, not because it is believed wrong.
//==============================================================================

//------------------------------------------------------------------------------
// gr_dir - a directory these tests own, guaranteed EMPTY on the way in
//
// Modelled on uc_dir and for the same reason: every test below counts what
// comes back, and the suite's g_dir is written to by other tests, so under
// ORDER(*API) a count taken from it is a count of which tests ran first.
// A path of its own also keeps this family and the unusable-service family
// from clearing each other's fixtures.
//
// Defined above its callers rather than prototyped at the top of the suite,
// the way the uc_ helpers are. It reuses uc_load_named and uc_remove_dir,
// which are defined earlier in this member, so this block must stay below
// them.
//
// Call it ONCE per test, at the top; calling it twice wipes the caller's own
// fixtures.
//------------------------------------------------------------------------------
dcl-proc gr_dir;
  dcl-pi *n like(STMF_t);
  end-pi;

  dcl-s d like(STMF_t);

  d = '/tmp/rmsc-groups-test-' + %trim(psds.current_user);

  uc_remove_dir(d);       // anything a previous failure left
  IFS_crtdir(d);

  return d;

end-proc;

//==============================================================================
// An empty collection still has one group
//
// The built-in system entry is added because the global directories were
// READ, not because anything was found in them - upstream adds it on that
// basis - so a collection with nothing in it prints exactly one row.
//
// This is the case a loop written to run once per definition gets wrong, and
// it gets it wrong in the direction that looks like success: zero rows and a
// zero return, from a procedure that did not fail.
//
// The two variations pull in opposite directions on purpose. Excluding 'all'
// removes every service there could have been and must NOT remove the
// built-in; --ignore-globals removes the built-in and leaves nothing at all.
// An implementation that confuses the two answers 0 for the first or 1 for
// the second.
//
// SCCOLL_init is called and load_dir is not, deliberately: docs/testing-notes
// on what an uninitialised likeds() structure contains.
//==============================================================================

dcl-proc test_groups_empty_collection_is_system_only export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);

  SCCOLL_init(coll);
  iEqual(0: SCCOLL_count(coll): 'nothing loaded');

  iEqual(1: SCEXEC_groups(coll: ''):
         'one row - the built-in system group, listed although no ' +
         'definition declared it and none was even read');

  iEqual(1: SCEXEC_groups(coll: 'all'):
         'excluding every service does not take the built-in away');

  iEqual(0: SCEXEC_groups(coll: '': true):
         'and with ignore_globals there is nothing to print at all');

end-proc;

//==============================================================================
// Declared groups that all sort BEFORE the built-in
//
// Two definitions, one group each, both sorting before 'system'. Three rows:
// the two declared and the built-in.
//
// The built-in belongs LAST in this answer, which is the branch that appends.
// The count says only that it was printed once - see the block comment - but
// a fixture that reaches the branch is what makes the case worth having, and
// what a later test with an output capture would build on.
//==============================================================================

dcl-proc test_groups_declared_all_before_system export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  d    like(STMF_t);

  d = gr_dir();

  assert(uc_load_named(d: 'rmscgrp_b1.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55961' + LF +
    'groups:' + LF +
    '- grpbef_a' + LF: def): 'first fixture');
  assert(uc_load_named(d: 'rmscgrp_b2.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55962' + LF +
    'groups:' + LF +
    '- grpbef_b' + LF: def): 'second fixture');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  iEqual(3: SCEXEC_groups(coll: ''):
         'grpbef_a, grpbef_b and the built-in system');

  uc_remove_dir(d);

end-proc;

//==============================================================================
// Declared groups that all sort AFTER the built-in
//
// The other branch: the built-in belongs FIRST here, which is the insertion
// an implementation that appends and then sorts, or that appends and does
// not, gets wrong in the output while still printing three rows. The count
// cannot tell those apart; what it can tell is that inserting at the front
// did not lose or duplicate a name, which an insert that shifts the array by
// hand is entirely capable of.
//==============================================================================

dcl-proc test_groups_declared_all_after_system export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  d    like(STMF_t);

  d = gr_dir();

  assert(uc_load_named(d: 'rmscgrp_z1.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55963' + LF +
    'groups:' + LF +
    '- zgrpaft_x' + LF: def): 'first fixture');
  assert(uc_load_named(d: 'rmscgrp_z2.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55964' + LF +
    'groups:' + LF +
    '- zgrpaft_y' + LF: def): 'second fixture');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  iEqual(3: SCEXEC_groups(coll: ''):
         'zgrpaft_x, zgrpaft_y and the built-in system');

  uc_remove_dir(d);

end-proc;

//==============================================================================
// A definition that declares system is listed once, not twice
//
// The built-in is inserted into the same list the declared names go into, so
// a definition declaring 'system' - which the definitions shipped under
// system/ do, and which is why the built-in exists at all - is the collision
// case. Four rows would be wrong by one, and it is a duplicate ROW in the
// output of a command whose output is screen-scraped.
//
// Two definitions declare it, so an implementation that de-duplicates the
// declared names against each other but not against the built-in still shows
// up as one too many rather than two.
//
// The other two assertions are the same fixture asked the two questions the
// gate's baselines cannot reach:
//
//   - with ignore_globals the BUILT-IN is not added, but a system group a
//     definition declared for itself is still a group it declared. Two rows.
//     INFERRED: the specification says the built-in entry is not added, not
//     that the name is suppressed. An implementation that filters the name
//     out of the answer instead of not adding the entry answers 1 here.
//   - excluding 'system' takes both definitions out, so grpsys_m goes with
//     them and no declared group is left - and the built-in is still
//     printed, because it does not depend on any surviving member. One row.
//     With ignore_globals as well there is nothing left to print at all.
//==============================================================================

dcl-proc test_groups_declared_system_listed_once export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  d    like(STMF_t);

  d = gr_dir();

  assert(uc_load_named(d: 'rmscgrp_s1.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55965' + LF +
    'groups:' + LF +
    '- system' + LF: def): 'first fixture');
  assert(uc_load_named(d: 'rmscgrp_s2.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55966' + LF +
    'groups:' + LF +
    '- system' + LF +
    '- grpsys_m' + LF: def): 'second fixture');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  iEqual(2: SCEXEC_groups(coll: ''):
         'grpsys_m and system - system once, although two definitions ' +
         'declare it and the built-in wants it too');

  iEqual(2: SCEXEC_groups(coll: '': true):
         'with ignore_globals the built-in is not added, but the system ' +
         'the definitions declared is still a declared group');

  iEqual(1: SCEXEC_groups(coll: 'system'):
         'excluding system takes both definitions and grpsys_m with them, ' +
         'and the built-in is printed with no member left');

  iEqual(0: SCEXEC_groups(coll: 'system': true):
         'and with ignore_globals as well, nothing is printed');

  uc_remove_dir(d);

end-proc;

//==============================================================================
// ignore_globals suppresses the built-in entry
//
// Upstream adds system only when it read the global directories, and
// --ignore-globals says it did not. docs/parity.md records this as one of the
// three differences that only became reachable once --ignore-globals was
// parsed into something that read it - so it is exactly the kind of thing
// that goes quietly wrong again.
//
// The control is the same collection with the parameter omitted. Without it
// the assertion is satisfied by a procedure that never prints the built-in at
// all, which is the neighbouring defect.
//
// The fixture declares no system group of its own, so the count moves by
// exactly the one entry under test.
//==============================================================================

dcl-proc test_groups_ignore_globals_omits_builtin export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  d    like(STMF_t);

  d = gr_dir();

  assert(uc_load_named(d: 'rmscgrp_g1.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55967' + LF +
    'groups:' + LF +
    '- grpbef_a' + LF: def): 'first fixture');
  assert(uc_load_named(d: 'rmscgrp_g2.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55968' + LF +
    'groups:' + LF +
    '- grpbef_b' + LF: def): 'second fixture');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  iEqual(3: SCEXEC_groups(coll: '': false):
         'control - ignore_globals off is the same as omitting it');

  iEqual(2: SCEXEC_groups(coll: '': true):
         'the two declared groups, and no built-in system');

  uc_remove_dir(d);

end-proc;

//==============================================================================
// A group whose only members are excluded is not listed
//
// The exclusion names SERVICES to leave out, and the groups of what is LEFT
// are then collected - the same reading SCCOLL.TEST pins for the collection's
// own group list. So excluding grpbef_a removes the only definition that
// declared it, and the name goes with the service rather than surviving as an
// empty group.
//
// Then the case that separates the built-in from everything else: exclude
// both groups and every service is gone, yet one row is still printed. An
// implementation that adds the built-in only when it has something else to
// print answers 0; one that adds it before applying the filter, and filters
// the finished list, also answers 0 for the 'system' exclusion in
// test_groups_declared_system_listed_once above.
//
// Excluding 'all' is the same thing reached through the implicit group every
// definition belongs to, and is what a bare `groups` with the default
// exclusions does on a system where every service is in an excluded group.
//==============================================================================

dcl-proc test_groups_excluded_service_takes_its_group export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  d    like(STMF_t);

  d = gr_dir();

  assert(uc_load_named(d: 'rmscgrp_f1.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55969' + LF +
    'groups:' + LF +
    '- grpbef_a' + LF: def): 'first fixture');
  assert(uc_load_named(d: 'rmscgrp_f2.yaml':
    'start_cmd: /usr/bin/rmscgrp' + LF +
    'check_alive: 55970' + LF +
    'groups:' + LF +
    '- grpbef_b' + LF: def): 'second fixture');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: d): 'fixtures loaded');
  iEqual(2: SCCOLL_count(coll): 'two definitions, and nothing else');

  iEqual(3: SCEXEC_groups(coll: ''):
         'control - both declared groups and the built-in');

  iEqual(2: SCEXEC_groups(coll: 'grpbef_a'):
         'the sole declarer of grpbef_a is excluded, so grpbef_a is not ' +
         'a group any more');

  iEqual(1: SCEXEC_groups(coll: 'grpbef_a,grpbef_b'):
         'both excluded, so only the built-in is left');

  iEqual(1: SCEXEC_groups(coll: 'all'):
         'and the same through the implicit group all');

  uc_remove_dir(d);

end-proc;


//##############################################################################
//##                                                                          ##
//##  THE FAILED-CRITERIA LIST AND THE LENGTH OF A CRITERION                  ##
//##                                                                          ##
//##############################################################################
//
// FOUND BY CODE REVIEW, NOT BY A FAILURE, which is why these are written
// before any fix and three of the four are expected to be RED.
// SCEXEC_evaluate fills ev.failed(n) with the criteria that were not
// satisfied, and ev.failed_text is built from those entries. The entries are
// held 64 characters wide while a rendering runs to 136, so a long criterion
// arrives CUT.
//
// THIS IS ON THE BYTE-EXACT PATH. ev.failed_text is what produces the
// '[not running at -->...]' suffix on a `check` row, and CLAUDE.md's first
// rule is that the consumer screen-scrapes those rows. A cut criterion does
// not raise anything: the row still has three fields, still parses, and
// simply names a criterion that does not exist. docs/messages.md has the
// captured shape.
//
// A criterion's VALUE may be up to 128 characters, documented and measured -
// test_criterion_text_job_not_truncated in SCDEF.TEST has the four
// measurements against sc 1.7.1. 'JOBNAME:' is 8, so a rendering runs to 136.
// SCDEF renders all 136; these ask whether the evaluation still carries them.
//
// THE BOUNDARY IS ON THE RENDERING, NOT ON THE VALUE. A 56-character job name
// renders to 64 and fits; a 57-character one renders to 65 and does not.
// Pick the fixture by the value and the separating case becomes a control.
//
// THE RIVAL HYPOTHESIS is "criteria are carried correctly at every length",
// and only values either side of 64 separate it from the truth:
//
//     20 chars ->  28 rendered   CONTROL - passes today, must keep passing.
//                                It is also what pins the SHAPE of
//                                failed_text, which the three below then
//                                only have to be measured against.
//
//     56 chars ->  64 rendered   CONTROL AT THE EDGE - the last rendering a
//                                64-wide entry holds whole. Rules out "long
//                                criteria fail for some reason other than the
//                                64-wide entry": if this is red, 64 is not
//                                where the edge is.
//
//     57 chars ->  65 rendered   THE SEPARATING CASE. One character longer
//                                than the row above and identical in every
//                                other respect. Red when written. No reading of
//                                "carried correctly at every length"
//                                survives 64 passing and 65 failing.
//
//    128 chars -> 136 rendered   THE FAR END - the documented limit. Rules
//                                out a fix that widened the entry to 72 or to
//                                128 and stopped short of the rendering.
//
// EVERY FIXTURE IS PARTIAL - port 22, which listens because this suite
// arrived over SSH, and then the long dead job name. PARTIAL rather than
// NOT RUNNING on purpose: PARTIAL is the state that actually prints the
// suffix, so these run down the path the consumer reads rather than a
// neighbouring one. The dead half is second, so ev.failed(1) is the long
// criterion and nothing else.
//
// The job names cannot exist: 20 characters is already twice what an IBM i
// job name holds, and test_long_job_name_is_usable measures that upstream
// accepts a name of any length and simply reports it not running.
//
// 05/09/2026 - RM - written against the defect, before the fix
//==============================================================================

//------------------------------------------------------------------------------
// lc_jobname - a job name of exactly LEN characters, distinct per case
//
// A second copy of the idea SCCOLL.TEST's cfl_longname carries; the suites are
// separate bound programs. Built rather than written out so each length is
// stated once and cannot drift from its comment.
//
// UPPER CASE, deliberately: a job name written straight into check_alive: is
// folded, so an upper-case value renders identically whether the folding rule
// is applied or not. These rows are about LENGTH and must not go red when
// some other rule moves. The tag is at the FRONT so two values of different
// lengths differ in their first dozen characters rather than only past 56.
//------------------------------------------------------------------------------
dcl-proc lc_jobname;
  dcl-pi *n varchar(256);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  dcl-c FILLER const('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
  dcl-s v varchar(320);

  v = 'RMSCEXEC' + %trimr(tag);

  dow %len(v) < len;
    v += FILLER;
  enddo;

  return %subst(v: 1: len);

end-proc;

//==============================================================================
// CONTROL - a failed criterion rendering to 28 characters is carried whole
//
// 20-character value, 28 rendered. Nothing near any width in this code. It is
// kept because the three tests below are red, and a reader has to be able to
// tell "long criteria are cut" from "the failed list is broken" - and because
// it is where the SHAPE of failed_text is stated: for a single failure it is
// that failure and nothing else, no wrapper, which is what lets the rows
// below assert one value rather than scan for a substring.
//==============================================================================

dcl-proc test_evaluate_failed_length_28_control export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v   varchar(256);

  v = lc_jobname('L28': 20);
  iEqual(20: %len(v): 'the value really is 20 characters');
  iEqual(28: 8 + %len(v): 'so the rendering really is 28');

  assert(pt_load_def('lclen28.yaml':
    'name: ZZ len28' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,' + v + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'the live port and the dead job');
  iEqual(1: ev.alive: 'one alive');
  iEqual(2: ev.total: 'of two');
  iEqual(1: ev.failed_count: 'one failure');

  aEqual('JOBNAME:' + v: pt_failed(ev: 1):
         'the failed entry is the whole rendering');
  aEqualV('JOBNAME:' + v: ev.failed_text:
          'and so is the suffix material built from it');

end-proc;

//==============================================================================
// CONTROL AT THE EDGE - a failed criterion rendering to exactly 64
//
// 56-character value, 64 rendered: the last rendering a 64-wide entry holds
// whole. This says WHERE the edge is rather than only that there is one. If
// it fails, the diagnosis in the header is wrong and the entry is narrower
// than 64 - find the real width and record it here rather than shortening the
// fixture until it passes.
//==============================================================================

dcl-proc test_evaluate_failed_length_64_edge export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v   varchar(256);

  v = lc_jobname('L64': 56);
  iEqual(56: %len(v): 'the value really is 56 characters');
  iEqual(64: 8 + %len(v):
         'so the rendering is exactly 64 - the last one that fits');

  assert(pt_load_def('lclen64.yaml':
    'name: ZZ len64' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,' + v + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'the live port and the dead job');
  iEqual(1: ev.failed_count: 'one failure');

  aEqual('JOBNAME:' + v: pt_failed(ev: 1):
         'the failed entry is the whole rendering, as at 28');
  aEqualV('JOBNAME:' + v: ev.failed_text: 'and so is the suffix material');

end-proc;

//==============================================================================
// THE SEPARATING CASE - 65 rendered, one character past the entry
//
// RED WHEN WRITTEN, and expected to be; green since the entry was widened.
// 57-character value, 65 rendered. It differs from the row above in exactly
// one character of one job name and in nothing else - same fixture shape, same
// key, same case, same live port beside it. So a pass above and a failure here
// could only have been about the length, which is what makes this the value
// that separates "carried correctly at every length" from the truth.
//
// The failure to expect is a cut entry: 'JOBNAME:' plus the first 56
// characters of the value. Read the message carefully - the two strings agree
// for 64 characters and then one of them stops, which is easy to skim past.
//==============================================================================

dcl-proc test_evaluate_failed_length_65_separating export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v   varchar(256);

  v = lc_jobname('L65': 57);
  iEqual(57: %len(v): 'the value really is 57 characters');
  iEqual(65: 8 + %len(v):
         'so the rendering is 65 - ONE past the 64-wide entry, which is the ' +
         'whole point of this fixture');

  assert(pt_load_def('lclen65.yaml':
    'name: ZZ len65' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,' + v + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'the live port and the dead job');
  iEqual(1: ev.failed_count: 'one failure');

  aEqual('JOBNAME:' + v: pt_failed(ev: 1):
         'the failed entry carries the FULL rendering - 65 characters is ' +
         'not a reason to cut it');
  aEqualV('JOBNAME:' + v: ev.failed_text:
          'and neither is the suffix material cut - this is the text a ' +
          'consumer screen-scrapes off a check row');

end-proc;

//==============================================================================
// THE FAR END - 136 rendered, the documented criterion limit
//
// RED WHEN WRITTEN, green since. 128-character value, 136 rendered: the
// longest criterion a definition may legitimately carry, measured against
// sc 1.7.1 and recorded in test_criterion_text_job_not_truncated. SCDEF
// renders it whole; this asks whether the evaluation still carries it.
//
// It is here because a fix that only moved the edge would pass the 65 above
// and fail this: 72 and 128 are both plausible widths to widen a 64-wide
// entry to, and neither holds 136.
//==============================================================================

dcl-proc test_evaluate_failed_length_136_limit export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v   varchar(256);

  v = lc_jobname('L136': 128);
  iEqual(128: %len(v): 'the value really is the documented 128-char limit');
  iEqual(136: 8 + %len(v): 'so the rendering really is 136');

  assert(pt_load_def('lclen136.yaml':
    'name: ZZ len136' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,' + v + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'the live port and the dead job');
  iEqual(1: ev.failed_count: 'one failure');

  aEqual('JOBNAME:' + v: pt_failed(ev: 1):
         'a criterion at the documented limit is carried whole, all 136 ' +
         'characters of it');
  aEqualV('JOBNAME:' + v: ev.failed_text: 'and so is the suffix material');

end-proc;

//==============================================================================
// THE SUFFIX MATERIAL ALONE, at the separating length
//
// RED WHEN WRITTEN, green since. The four tests above assert ev.failed(1)
// BEFORE ev.failed_text, and assert() ends the procedure at the first failure -
// so on the build this was written against the failed_text half of the
// separating case was never reached and its state went unreported. That matters more than the usual "one assertion per
// test" argument would suggest, because failed_text is the half that reaches
// the CONSUMER: it is what SCOUT_not_running_suffix turns into
// '[not running at -->...]' on a check row, and CLAUDE.md's first rule is
// that those rows are screen-scraped.
//
// So this row asserts nothing but failed_text, at 65 rendered - the same
// value test_evaluate_failed_length_65_separating uses, for the same reason
// it uses it. Its only purpose is to make the state of the byte-exact path
// visible on its own rather than behind another assertion.
//
// It goes green the moment the entries do, if failed_text is built from them
// as the header says. If it stays red after they are fixed, failed_text has a
// width of its own and the fix is not finished.
//==============================================================================

dcl-proc test_evaluate_failed_text_length_65_separating export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v   varchar(256);

  v = lc_jobname('L65': 57);
  iEqual(65: 8 + %len(v): 'the rendering is 65, one past the 64-wide entry');

  assert(pt_load_def('lctxt65.yaml':
    'name: ZZ txt65' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: 22,' + v + LF: def): 'load');

  SCEXEC_evaluate(def: ev);

  aEqual('PARTIAL': ev.state: 'the live port and the dead job');

  aEqualV('JOBNAME:' + v: ev.failed_text:
          'the suffix material carries the FULL rendering - this is the ' +
          'text that reaches a check row, and a cut criterion there names ' +
          'something that does not exist without anything saying so');

end-proc;

//##############################################################################
//##                                                                          ##
//##  AN AD-HOC PORT SPECIFIER THAT IS NOT A PORT NUMBER                      ##
//##                                                                          ##
//##############################################################################
//
// `scr check port:<value>` builds a definition on the spot rather than reading
// one, so the value arrives from the COMMAND LINE and has been through no YAML
// reader and no definition file. SCMAIN_adhoc is where it becomes a criterion,
// and it is the one place in RMSC that converts such a value without first
// asking whether it can be converted.
//
// MEASURED against sc 1.7.1, same box, same day:
//
//   specifier                 upstream sc              RMSC today
//   port:99999999999999       rc 253, message below    rc 255, CEE9901 MCH1210
//   port:4294967296           rc 253, message below    rc 255, CEE9901 MCH1210
//   port:abc                  rc 253, message below    rc 255, CEE9901 RNX0105
//   port:-1                   rc 0, NOT RUNNING        rc 0, NOT RUNNING
//   port:65536                rc 0, NOT RUNNING        rc 0, NOT RUNNING
//
// and the message, on stderr, is the one SCOUT_invalid_criteria already
// renders and qtestsrc/SCOUT.TEST.RPGLE already pins byte for byte:
//
//   Invalid data for port number or job name criteria for service '<friendly>': PORT:<raw>
//
// THE RULE IS THE ONE THE COMPANION FORM ALREADY FOLLOWS - a port value is
// usable if the trimmed text is an optional sign followed by digits and the
// number fits the field. There is no second rule for ad-hoc specifiers; there
// is a second CODE PATH, and it does not implement the rule.
//
// THE RIVAL IS A RANGE CHECK ON 1..65535, and it is the obvious thing to write
// when the symptom is "a bad port number crashes". -1 and 65536 separate it
// from the truth: both are outside any port range, both are perfectly usable,
// and upstream simply reports NOT RUNNING for them. A fix that turned those
// two into errors would pass every case below that names a crash and would be
// a new parity defect. They are asserted first, and together, for that reason.
//
// NOTHING HERE ASSERTS THE AD-HOC NAME. RMSC calls the service 'ad hoc port
// <value>' and upstream calls it 'Ad hoc service running at port <value>';
// that divergence is recorded in docs/parity.md and is a separate decision.
// What is asserted is which values can be used and what happens to the ones
// that cannot.
//
// SCMAIN_adhoc's RETURN VALUE is asserted true even for the values that cannot
// be used. False means "this specifier is not a port:/job:/PGM- form at all",
// which sends the caller down the unknown-service path - and the measured
// message names the ad-hoc service by its FRIENDLY name, so upstream plainly
// built the definition before rejecting the criterion. Refusing at
// SCMAIN_adhoc would produce a different message and a different exit status.
//
// The three unusable values are in three procedures rather than one. Each
// abends today, and an abend is an ERROR that ends its procedure - one
// procedure would report the first value and hide the other two.
//==============================================================================

//------------------------------------------------------------------------------
// THE CONTROL, AND THE ONE THAT RULES OUT A RANGE CHECK
//
// Both values parse; neither can ever match. MEASURED: rc 0 and NOT RUNNING
// for each, with nothing on stderr.
//
// This passes today and must keep passing. If it goes red alongside a fix,
// the fix has become a range check.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_port_outside_any_range_is_still_usable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:-1': def): 'port:-1 is a port: specifier');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');

  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count:
         'MEASURED - -1 parses, so it is USABLE. It simply never matches, ' +
         'and upstream reports NOT RUNNING and exits 0');
  aEqual('NOT RUNNING': ev.state: 'and it has a status, not an error');

  clear ev;
  clear def;

  assert(SCMAIN_adhoc('port:65536': def): 'port:65536 is a port: specifier');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');

  SCEXEC_evaluate(def: ev);
  iEqual(0: ev.unusable_count:
         'MEASURED - 65536 is one past the top of the port range and is ' +
         'still USABLE. The rule is "does it parse", not "is it a port"');
  aEqual('NOT RUNNING': ev.state: 'and NOT RUNNING, exit 0');

end-proc;

//------------------------------------------------------------------------------
// ONE STEP OVER WHAT THE FIELD CAN HOLD
//
// 4294967296 is 2^32 - it parses as digits and does not fit a 32-bit signed
// integer, which is the boundary the companion form already refuses at
// (test_port_too_large_for_the_field_is_unusable, one block up).
//
// MEASURED: upstream rc 253 with the invalid-criteria line. RMSC today ends
// the job with MCH1210 converting it, so expect an ERROR rather than a
// failure until this is fixed.
//
// .raw is asserted as well as the count, because the message renders from it:
// a fix that recognised the value as unusable but did not keep its text would
// print 'PORT:' with nothing after the colon, and the count alone would not
// notice.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_port_over_int_max_is_unusable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:4294967296': def):
         'still a port: specifier - the value being unusable does not make ' +
         'the SPECIFIER unrecognised');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');
  aEqualV('4294967296': def.criteria(1).raw: 'the text is kept as written');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count:
         'too wide for the field: refused, and specifically not truncated ' +
         'into port 0 and quietly probed');
  aEqual('PORT:4294967296': ev.unusable_text:
         'rendered as the message renders it');

end-proc;

//------------------------------------------------------------------------------
// FAR OVER, so no field width could explain it
//
// MEASURED: upstream rc 253 with the invalid-criteria line; RMSC MCH1210.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_port_far_over_int_max_is_unusable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:99999999999999': def): 'a port: specifier');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');
  aEqualV('99999999999999': def.criteria(1).raw: 'text kept as written');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'fourteen digits is not a port number');
  aEqual('PORT:99999999999999': ev.unusable_text:
         'and the message shows the real value');

end-proc;

//------------------------------------------------------------------------------
// NOT DIGITS AT ALL
//
// The same value the companion form already handles correctly
// (test_port_not_a_number_is_unusable). Here it arrives from the command line
// instead, and RMSC ends the job with RNX0105 - a different failure code from
// the two above, which is worth having its own case: they are two conversions,
// not one, and a fix that guarded only the width would leave this one.
//
// MEASURED: upstream rc 253 with the invalid-criteria line.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_port_not_a_number_is_unusable export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:abc': def): 'a port: specifier');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind:
          'kind is PORT - the specifier said so, the value did not');
  aEqualV('abc': def.criteria(1).raw: 'text kept as written');

  SCEXEC_evaluate(def: ev);

  iEqual(1: ev.unusable_count: 'abc is not a port number');
  aEqual('PORT:abc': ev.unusable_text: 'rendered for the message');

end-proc;

//##############################################################################
//##                                                                          ##
//##  AN AD-HOC PORT SPECIFIER THAT IS A PERFECTLY GOOD PORT                  ##
//##                                                                          ##
//##############################################################################
//
// The block above this one covers every ad-hoc value that CANNOT be used. It
// went green, and the change that made it go green also broke every ad-hoc
// value that CAN be used. Nothing above could see that, because nothing above
// evaluates a port that is actually listening - and that is the finding worth
// keeping: a block that covers only the failure case cannot tell a fix from a
// break.
//
// MEASURED on the box, sshd listening on 22, same day:
//
//   sc  check port:22   ->  RUNNING      | ad_hoc_port_22 (Ad hoc service ...)
//   scr check port:22   ->  NOT RUNNING  | port:22 (ad hoc port 22)
//
// It is not about 22. SCMAIN_adhoc sets the criterion's raw TEXT and no longer
// sets its numeric port at all, so every ad-hoc port check probes port 0 -
// including the ones that are genuinely listening.
//
// THE RIVAL THESE CASES MUST RULE OUT IS "THE CRITERION IS USABLE". That is
// TRUE today, for exactly the value that is broken, and it is why the defect
// survived a block of five ad-hoc tests: usability is a property of the TEXT
// and correctness is a property of the NUMBER, and only the text is being set.
// So .port is asserted directly, as a number, and unusable_count is asserted
// 0 alongside it - the pair says "usable AND right", which is the thing that
// is false.
//
// Three procedures, not one. A failed assertion ends its test case in
// iRPGUnit, so a single procedure would report the numeric port and hide the
// evaluation, or report 22 and hide 8080.
//
// THE FIXTURE IS PORT 22 AND sshd. CLAUDE.md names it as the project's
// always-there fixture - the suite arrived over SSH, so it is listening by
// construction - and this suite's own test_evaluate_fixture_ports already
// asserts it rather than skipping on it. tools/gate-listen.py can hold an
// arbitrary port open and is the better fixture where a test needs a port
// NOBODY else could be using, but it is an external process: it cannot be
// started from inside the ILE job iRPGUnit runs in, so a suite depending on
// it would depend on something it cannot guarantee. Present is not the same
// as stable, and here the stable one is 22.
//==============================================================================

//------------------------------------------------------------------------------
// THE NUMBER REACHES THE CRITERION
//
// No system state, no network: this is the whole defect in one assertion. Two
// values, so the case cannot be read as being about 22.
//
// 8080 is the second value because it is the one the rest of this suite uses
// for a port that is not special in any way. Neither value is evaluated here -
// what is asserted is what SCMAIN_adhoc BUILT, before anything probes it.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_port_number_reaches_the_criterion export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:22': def): 'port:22 is a port: specifier');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');
  aEqualV('22': def.criteria(1).raw: 'the text is kept as written');
  iEqual(22: def.criteria(1).port:
         'AND THE NUMBER IS SET. The text alone leaves the probe asking ' +
         'about port 0, which is what every ad-hoc port check does today');

  clear def;

  assert(SCMAIN_adhoc('port:8080': def): 'port:8080 is a port: specifier');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV('8080': def.criteria(1).raw: 'the text is kept as written');
  iEqual(8080: def.criteria(1).port:
         'not about 22 - no ad-hoc port number is being set');

  clear def;

  // The third value is the one the silent-port control below uses. Its number
  // is asserted here rather than there so that the control can stay a control:
  // see the comment in test_adhoc_silent_port_is_not_running.
  assert(SCMAIN_adhoc('port:' + UNUSED_PORT_TEXT: def): 'a port: specifier');
  iEqual(59417: def.criteria(1).port:
         'a listening port and a silent one take the same path, and ' +
         '59417 is the same value as UNUSED_PORT_TEXT');

end-proc;

//------------------------------------------------------------------------------
// AND IT GETS ALL THE WAY THROUGH
//
// The end-to-end half. MEASURED: upstream reports RUNNING for port:22 on this
// box and RMSC reports NOT RUNNING.
//
// unusable_count is asserted 0 in the same case, deliberately. It is 0 today
// as well, so this assertion passes on both sides of the fix - it is here to
// say in the failure report that the criterion was never rejected. RMSC does
// not think port:22 is a bad value; it thinks port 0 is not listening.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_listening_port_is_running export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:' + SSH_PORT_TEXT: def): 'a port: specifier');

  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count:
         'the value is usable - it always was. That is the rival reading ' +
         'this case exists to rule out: usable is not the same as right');
  aEqual('RUNNING': ev.state:
         'MEASURED - sshd is listening on ' + SSH_PORT_TEXT + ' because ' +
         'this suite arrived over it, and upstream reports RUNNING. RMSC ' +
         'reports NOT RUNNING because it probed port 0');

end-proc;

//------------------------------------------------------------------------------
// THE OTHER HALF OF THE PAIR - a silent port is NOT RUNNING
//
// A CONTROL. It passes today and it passes after the fix, and without it the
// case above could be satisfied by a fix that reported RUNNING for every
// ad-hoc port - which is precisely the shape of mistake that produced the
// defect in the first place, only in the other direction.
//
// 59417 is the suite's UNUSED_PORT_TEXT, already relied on by the fixture
// guard.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_silent_port_is_not_running export;

  dcl-ds def likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev  likeds(SCEXEC_EVAL_t) inz(*likeds);

  assert(SCMAIN_adhoc('port:' + UNUSED_PORT_TEXT: def): 'a port: specifier');

  // NOTHING ABOUT .port IS ASSERTED HERE, deliberately, and it was on the
  // first run. It is 0 today like every other ad-hoc port, so the case died
  // on that assertion and never reached the state - which left the control
  // not controlling anything. A control has to be able to run today. The
  // numeric port is the case above's job; this one's job is the state, and
  // it must be green on both sides of the fix.
  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count: 'usable, and simply not there');
  aEqual('NOT RUNNING': ev.state:
         'nothing listens on ' + UNUSED_PORT_TEXT + ', so a fix that ' +
         'hardcoded RUNNING must fail here');

end-proc;

//##############################################################################
//##                                                                          ##
//##  AN AD-HOC PORT SPECIFIER LONGER THAN A CRITERION CAN HOLD               ##
//##                                                                          ##
//##############################################################################
//
// The block above covers ad-hoc values that are SHORT. This one covers a value
// that is longer than the criterion's raw text can hold, which is where the
// usability rule and the conversion can be made to disagree: the guard can be
// applied to one string and the conversion to another, and every short value
// in this suite goes green either way.
//
// MEASURED on this box, 5 September 2026, sshd listening on 22. `Z` below is
// 128 zero characters.
//
//   specifier              upstream sc                     RMSC today
//   -------------------    ---------------------------     -----------------
//   port:Z22               RUNNING, rc 0                   RUNNING, rc 0
//   port:Z4294967296       rc 253, invalid-criteria line   CEE9901 MCH1210
//                                                          at statement 280
//
// (Upstream names the ad-hoc service with the full padded value, RMSC with a
// cut one. Ad-hoc naming is already a recorded difference in docs/parity.md
// and nothing here asserts it.)
//
// SO LEADING ZEROS ARE NOT SPECIAL AND LENGTH IS NOT SPECIAL. `port:Z22` is
// port 22, RUNNING, on both implementations - the zeros are stripped and the
// value parses as decimal 22, which is what Integer.parseInt has always done.
// It is only the VALUE that decides, and the rule is the one the rest of this
// suite already pins: an optional sign, digits, and a number that fits.
//
// THE RIVAL THIS BLOCK EXISTS TO RULE OUT is "a specifier too long to hold is
// unusable". That is the obvious fix when the symptom is "a very long port
// specifier crashes", it makes the crash go away, and it is WRONG: it turns
// `port:Z22` - RUNNING and rc 0 upstream, and RUNNING in RMSC today - into an
// error. Which is why the two cases below that use `port:Z22` are here at all.
// They are green today and must stay green; if a fix makes one of them red,
// the fix has answered the wrong question, and the difference would have to be
// argued into docs/parity.md rather than assumed.
//
// NOTHING ASSERTS ev.unusable_text IN FULL. The value is 138 characters and a
// criterion's raw text holds 128, so no implementation can render the whole of
// it and there is no measured answer for what it renders instead. What IS
// asserted is that the rendering still starts 'PORT:' and has something after
// the colon - a fix that recognised the value as unusable but lost its text
// entirely would print a bare 'PORT:' and no count would notice. What RMSC
// puts in the message for a value it cannot hold whole is a real question and
// a separate one; it is raised in the report accompanying these tests, not
// decided here.
//
// One case per procedure, as in the block above: the first abends today, and
// an abend ends its procedure, so sharing one would hide the two controls.
//
// 05/09/2026 - RM - written against the defect, before the fix
//==============================================================================

//------------------------------------------------------------------------------
// THE CRASH - a zero-padded value that overflows once the padding is stripped
//
// The separating case. 128 zeros then 4294967296: the padding is not the
// point, the padding is what makes the specifier longer than the criterion's
// raw text so that a guard reading the raw and a conversion reading the value
// can be looking at two different strings. Strip the zeros and it is 2^32,
// exactly the value test_adhoc_port_over_int_max_is_unusable already refuses
// when it arrives unpadded.
//
// MEASURED: upstream rc 253 with the invalid-criteria line. RMSC ends the job
// with MCH1210, so expect an ERROR rather than a failure until this is fixed.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_zero_padded_port_over_int_max_is_unusable export;

  dcl-ds def  likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev   likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  spec varchar(512);

  spec = az_spec('4294967296');
  iEqual(143: %len(spec):
         'the measured specifier - port:, 128 zeros, and 4294967296');

  assert(SCMAIN_adhoc(spec: def):
         'still a port: specifier - the value being unusable does not make ' +
         'the SPECIFIER unrecognised');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');

  SCEXEC_evaluate(def: ev);   // today: MCH1210, and the suite ends here

  iEqual(1: ev.unusable_count:
         'the padded value is 2^32 once the zeros are stripped, so it does ' +
         'not fit and must be refused - not converted from one string while ' +
         'a shorter one is what was checked');

  assert((%scan('PORT:': ev.unusable_text) = 1):
         'and the message still renders as PORT:something');
  assert((%len(%trimr(ev.unusable_text)) > 5):
         'with something after the colon - a bare PORT: names nothing, and ' +
         'the count alone would not notice');

end-proc;

//------------------------------------------------------------------------------
// THE FIRST CONTROL - the same padding, a value that fits
//
// GREEN TODAY, on both implementations, and the case that stops the fix being
// a length check. Nothing about the criterion is evaluated here; what is
// asserted is the number SCMAIN_adhoc built, before anything probes it.
//
// MEASURED: upstream reports RUNNING for this specifier and exits 0, so the
// number it reached for was 22.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_zero_padded_port_number_reaches_the_criterion export;

  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  spec varchar(512);

  spec = az_spec(SSH_PORT_TEXT);
  iEqual(135: %len(spec): 'port:, 128 zeros, and 22');

  assert(SCMAIN_adhoc(spec: def): 'a port: specifier');
  iEqual(1: def.criteria_count: 'one criterion');
  aEqualV(SCDEF_CHECK_PORT: def.criteria(1).kind: 'kind is PORT');

  iEqual(22: def.criteria(1).port:
         'MEASURED - 128 leading zeros make no difference to the value, ' +
         'and upstream probes 22 and reports RUNNING. A specifier too long ' +
         'to hold is not the same as a value that cannot be used');

end-proc;

//------------------------------------------------------------------------------
// THE SECOND CONTROL - and it gets all the way through
//
// GREEN TODAY. The end-to-end half of the case above: RMSC reports RUNNING for
// this specifier now, and must still report RUNNING afterwards.
//
// unusable_count is asserted 0 alongside the state, and it is the assertion
// that would catch the wrong fix: a length check would leave the state blank
// and the count 1, and a reader seeing only a state failure could put it down
// to sshd rather than to the guard.
//------------------------------------------------------------------------------

dcl-proc test_adhoc_zero_padded_listening_port_is_running export;

  dcl-ds def  likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev   likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  spec varchar(512);

  spec = az_spec(SSH_PORT_TEXT);

  assert(SCMAIN_adhoc(spec: def): 'a port: specifier');

  SCEXEC_evaluate(def: ev);

  iEqual(0: ev.unusable_count:
         'the value is usable - it is 22 with padding in front of it, and ' +
         'a fix that refused it for its LENGTH would fail here');
  aEqual('RUNNING': ev.state:
         'MEASURED - upstream reports RUNNING for this specifier and so ' +
         'does RMSC today, because sshd is listening on ' + SSH_PORT_TEXT);

end-proc;

//##############################################################################
//##                                                                          ##
//##  AN AD-HOC PGM- SPECIFIER AND THE SAME PROGRAM NAMED IN A FILE           ##
//##                                                                          ##
//##############################################################################
//
// A criterion naming a PROGRAM can be reached two ways - `check_alive:
// PGM-X` in a definition file, and `PGM-X` on the command line - and the two
// must arrive at the same criterion. They do not.
//
// MEASURED on this box, 5 September 2026:
//
//   from a file, check_alive: PGM-ZZNOSUCHPGM
//       sc  info -> Check-alive conditions: JOBNAME:PGM-ZZNOSUCHPGM
//       scr info -> Check-alive conditions: JOBNAME:PGM-ZZNOSUCHPGM
//
//   ad hoc, PGM-ZZNOSUCHPGM on the command line
//       scr info -> Check-alive conditions: JOBNAME:ZZNOSUCHPGM
//
// The ad-hoc path drops the PGM- prefix from the criterion's raw text; the
// file path keeps it, and the file path is the one that agrees with upstream.
//
// THIS IS NOT A PARITY QUESTION. Upstream has no ad-hoc PGM- form at all - it
// answers "Could not find definition for service 'PGM-ZZNOSUCHPGM'". It is
// RMSC disagreeing with itself, and that is why the assertion below compares
// the two RMSC paths to EACH OTHER rather than each to a literal: the two
// must agree whatever the rendering is, and a case written against a literal
// would have to be rewritten the day the rendering moved and would then stop
// saying the thing it exists to say.
//
// IT MATTERS BEYOND DISPLAY. The raw text is what conflict detection compares,
// so an ad-hoc PGM-X today claims the same criterion as a service whose JOB
// NAME is X. That consequence is NOT asserted here, and could not be: nothing
// exported puts a definition built by SCMAIN_adhoc into an SCCOLL_t, so
// SCCOLL_conflicts cannot be reached from an ad-hoc definition from a suite.
// Writing a conflict case over two FILE definitions instead would have been
// green today and green after the fix - it would have tested the path that
// already works. Said here rather than left as a gap somebody rediscovers.
//
// THE RIVAL is "the ad-hoc path is fine and only the file path is unusual".
// test_adhoc_job_renders_as_the_file_form_does rules it out: the same
// comparison over the JOB form is green today, so the two paths agree in
// general and disagree on exactly this one specifier.
//
// 05/09/2026 - RM - written against the defect, before the fix
//==============================================================================

//==============================================================================
// THE SEPARATING CASE - PGM- reaches the same criterion from both directions
//
// Red when written: the ad-hoc side rendered JOBNAME:ZZNOSUCHPGM where the
// file side rendered JOBNAME:PGM-ZZNOSUCHPGM. Both now render the same.
//
// The program cannot exist. ZZ- names nothing on this box, which is the same
// convention the rest of this suite's dead fixtures follow, and the criterion
// is never probed here in any case - what is asserted is what the two paths
// BUILT.
//==============================================================================

dcl-proc test_adhoc_pgm_renders_as_the_file_form_does export;

  dcl-ds filed likeds(SCDEF_t) inz(*likeds);
  dcl-ds adhoc likeds(SCDEF_t) inz(*likeds);
  dcl-s  f     varchar(512);
  dcl-s  a     varchar(512);

  // The file path first - it is the one that matches upstream, so it is the
  // expected value and not merely the other half of a comparison.
  assert(pt_load_def('adhocpgm.yaml':
    'name: ZZ adhoc pgm' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: PGM-ZZNOSUCHPGM' + LF: filed): 'the file form loads');

  iEqual(1: filed.criteria_count: 'one criterion from the file');
  f = SCDEF_criterion_text(filed.criteria(1));

  assert(SCMAIN_adhoc('PGM-ZZNOSUCHPGM': adhoc):
         'PGM-ZZNOSUCHPGM is recognised as an ad-hoc specifier');

  iEqual(1: adhoc.criteria_count: 'one criterion from the command line');
  a = SCDEF_criterion_text(adhoc.criteria(1));

  aEqual(f: a:
         'the same program named two ways must be the same criterion - ' +
         'file gives "' + %trim(f) + '", ad hoc gives "' + %trim(a) + '"');

end-proc;

//==============================================================================
// THE CONTROL - the ad-hoc JOB form already agrees with the file form
//
// Green today and must stay green. Two things rest on it:
//
//   - it rules out "the ad-hoc path renders differently in general", which
//     would make the case above a statement about ad-hoc criteria rather
//     than about the PGM- prefix;
//   - it fails a fix that prepends PGM- to every ad-hoc job criterion, or
//     that repairs the raw text by re-deriving it from the split-out job
//     name for all of them. Both would make the case above pass.
//==============================================================================

dcl-proc test_adhoc_job_renders_as_the_file_form_does export;

  dcl-ds filed likeds(SCDEF_t) inz(*likeds);
  dcl-ds adhoc likeds(SCDEF_t) inz(*likeds);
  dcl-s  f     varchar(512);
  dcl-s  a     varchar(512);

  assert(pt_load_def('adhocjob.yaml':
    'name: ZZ adhoc job' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ZZNOSUCHJOB' + LF: filed): 'the file form loads');

  iEqual(1: filed.criteria_count: 'one criterion from the file');
  f = SCDEF_criterion_text(filed.criteria(1));

  assert(SCMAIN_adhoc('job:ZZNOSUCHJOB': adhoc):
         'job:ZZNOSUCHJOB is recognised as an ad-hoc specifier');

  iEqual(1: adhoc.criteria_count: 'one criterion from the command line');
  a = SCDEF_criterion_text(adhoc.criteria(1));

  aEqual(f: a:
         'the job form already agrees - file gives "' + %trim(f) +
         '", ad hoc gives "' + %trim(a) + '"');

end-proc;

//##############################################################################
//##                                                                          ##
//##  A CHECK ROW LONG ENOUGH TO BE CUT                                       ##
//##                                                                          ##
//##############################################################################
//
// THE ARITHMETIC, stated so a reader can check it rather than trust it:
//
//   a definition may carry               8 criteria
//   one criterion's value may be       128 characters
//   a rendering is 'JOBNAME:' + value  136 characters
//   joined with ', '                     8 x 136 + 7 x 2 = 1102 characters
//
// THAT WORST CASE CANNOT BE WRITTEN IN A FILE, and finding out why is what
// this block cost. Eight values of 128 need 8 x 128 + 7 commas = 1031
// characters of check_alive:, and A YAML SCALAR IS CAPPED AT 1024. The
// original fixture here therefore lost seven characters off its eighth value
// before SCEXEC ever saw it, and the case went red at the YAML layer while
// claiming to be about the row. The cap is now a REFUSAL rather than a silent
// cut - see the SCALAR LENGTH block in SCDEF.TEST - so the same fixture would
// no longer load at all.
//
// SO THE FIXTURE BELOW USES 127, NOT 128:
//
//   8 x 127 + 7 commas                   1023 characters of check_alive:
//   a rendering is 'JOBNAME:' + 127       135 characters
//   joined with ', '                     8 x 135 + 7 x 2 = 1094 characters
//
// 1023 fits the scalar cap with one character to spare, and 1094 is still 70
// characters past the 1024 the line type held when this was written, so the
// case still separates exactly what it was written to separate. Nothing here
// was relaxed to make it pass: the fixture moved to the layer under test and
// the assertion did not move at all.
//
// and a check row is
//
//   '  ' + status padded to 18 + ' | ' + name + ' (' + desc + ') '
//        + '[not running at -->' + that text + ']'
//
// so the worst case is comfortably past 1024, which is what the line type
// holds today. The row is cut, and what is lost is the tail: part of the
// eighth criterion and the closing bracket. Nothing says so.
//
// THIS IS NEW. Before the criterion width was raised to 128 the worst case
// was around 590 characters and could not overflow, so no existing test
// reaches the width and none would notice it moving.
//
// WHY THE ROW AND NOT ONLY THE TEXT. The consumer screen-scrapes check output
// and drops any row that does not yield three fields; a row cut mid-criterion
// still yields three, so the loss is silent at every layer. Both are asserted,
// in that order, so a failure says WHERE the material was lost - in the
// evaluation or in the rendering - rather than only that it was.
//
// THE INSTRUMENT IS 4096 WIDE ON PURPOSE. This suite's own aEqualV is 512,
// and a value of a thousand characters handed to it arrives truncated on BOTH
// sides, so
// it would compare two cut strings, find them equal, and report the defect it
// exists to detect as a pass. lg_equal is used instead. Do not narrow it, and
// do not reach for aEqualV here.
//
// EVERY JOB NAME IS DEAD AND UPPER CASE - dead so all eight criteria genuinely
// fail (128 characters is twelve times what an IBM i job name holds, and
// test_long_job_name_is_usable measures that upstream accepts a name of any
// length and reports it not running), upper case so the row is about LENGTH
// and cannot go red because the folding rule moved.
//
// NOT PARTIAL, unlike the length tests above it: all eight fail, the state is
// NOT RUNNING, and that is the row that carries the longest possible suffix -
// eight renderings rather than seven.
//
// 05/09/2026 - RM - written against the defect, before the fix
//==============================================================================

//------------------------------------------------------------------------------
// lg_equal - compare two values that may be longer than 1024 characters
//
// Reports lengths and the last 48 characters of each rather than the whole of
// both: a failure message carrying two 1102-character strings is unreadable in
// the RUCALLTST output, and the tail is where the interesting difference is.
//------------------------------------------------------------------------------
dcl-proc lg_equal;
  dcl-pi *n;
    expected varchar(4096) const;
    actual   varchar(4096) const;
    ctx      varchar(64) const;
  end-pi;

  dcl-s etail varchar(64);
  dcl-s atail varchar(64);

  if %trimr(expected) = %trimr(actual);
    assert(*on: %trim(ctx));
    return;
  endif;

  etail = tail48(expected);
  atail = tail48(actual);

  assert(*off: %trim(ctx) + ': expected ' + %char(%len(%trimr(expected))) +
               ' chars ending "' + %trim(etail) + '" but got ' +
               %char(%len(%trimr(actual))) + ' chars ending "' +
               %trim(atail) + '"');

end-proc;

dcl-proc tail48;
  dcl-pi *n varchar(64);
    v varchar(4096) const;
  end-pi;

  dcl-s t varchar(4096);

  t = %trimr(v);
  if %len(t) <= 48;
    return t;
  endif;

  return %subst(t: %len(t) - 47: 48);

end-proc;

//------------------------------------------------------------------------------
// az_spec - an ad-hoc port specifier padded with 128 leading zeros
//
// 128 is the width a criterion's raw text holds, so 'port:' + 128 zeros + a
// value is a specifier whose value cannot be held whole however short the
// value itself is. That is the whole point of the padding: it separates the
// string a guard might read from the string a conversion reads. The zeros
// themselves mean nothing - MEASURED, upstream strips them and parses what is
// left as decimal.
//
// Built in a loop rather than written out, because 128 characters of zeros in
// a source line is unreadable and miscountable, and every caller asserts the
// length of what comes back rather than trusting this comment.
//------------------------------------------------------------------------------
dcl-proc az_spec;
  dcl-pi *n varchar(512);
    tail varchar(64) const;
  end-pi;

  dcl-s z varchar(256);
  dcl-s i like(INTEGER_t);

  for i = 1 to 128;
    z += '0';
  endfor;

  return 'port:' + z + %trimr(tail);

end-proc;

//==============================================================================
// THE SEPARATING CASE, EVALUATION SIDE - eight criteria of 135 characters
//
// 1094 characters of failed text out of an evaluation, from a check_alive: of
// 1023 that the YAML layer can hold whole. The row built from the same eight
// renderings is the case after this one.
//==============================================================================

dcl-proc test_check_row_eight_long_criteria_is_not_cut export;

  dcl-ds def   likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev    likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v     varchar(256) dim(8);
  dcl-s  ca    varchar(2048);
  dcl-s  want  varchar(4096);
  dcl-s  got   varchar(4096);
  dcl-s  i     like(INTEGER_t);

  for i = 1 to 8;
    v(i) = lc_jobname('L8' + %char(i): 127);
    if i = 1;
      ca   = v(i);
      want = 'JOBNAME:' + v(i);
    else;
      ca   += ',' + v(i);
      want += ', JOBNAME:' + v(i);
    endif;
  endfor;

  // The fixture states its own arithmetic. If either of these fails the
  // header's numbers are wrong and nothing below means what it says. 1023 is
  // one under the 1024 a YAML scalar holds, deliberately: a fixture of 1031
  // is refused by the YAML layer and never reaches the one under test here.
  iEqual(1023: %len(ca):   'eight 127-character values, comma separated');
  iEqual(1094: %len(want): 'and eight renderings joined with ", "');

  assert(pt_load_def('lcrow8.yaml':
    'name: ZZ row8' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + ca + LF: def): 'load');

  iEqual(8: def.criteria_count: 'all eight criteria survive the load');

  SCEXEC_evaluate(def: ev);

  aEqual('NOT RUNNING': ev.state: 'none of the eight can be satisfied');
  iEqual(0: ev.alive:        'none alive');
  iEqual(8: ev.total:        'of eight');
  iEqual(8: ev.failed_count: 'and all eight failed');

  // The eighth rendering must be present and whole.
  got = %trimr(ev.failed_text);
  assert((%scan('JOBNAME:' + v(8): got) > 0):
         'the eighth rendering is in failed_text whole - it holds ' +
         %char(%len(got)) + ' characters of the 1094 it was given');
  lg_equal(want: got: 'failed_text carries all eight renderings');

  // The ROW is the other half, and it is a SEPARATE case rather than three
  // more assertions here. A failed assertion ends its procedure, so a row
  // assertion placed after the one above could not run until the evaluation
  // side was fixed - it would sit dark today and report nothing about the
  // layer it is for. See test_check_row_long_suffix_is_not_cut.

end-proc;

//==============================================================================
// THE SEPARATING CASE, RENDERING SIDE - a 1102-character suffix in a row
//
// The same eight renderings, built here rather than taken from an evaluation,
// so this case is not blocked by the one above: whichever of the two layers
// is fixed first, the other still reports.
//
// A row carrying this suffix is
//
//   2 + 18 + 3 + 6 + 2 + 7 + 2 + 19 + 1102 + 1  =  1162 characters
//
// MEASURED, first run: 1024. The last 138 characters - the tail of the eighth
// criterion and the bracket - are gone.
//
// so nothing 1024 wide can hold it. What is lost is the tail - part of the
// eighth criterion and the closing bracket - and the consumer still sees
// three fields either way, so the loss raises nothing.
//
// IT LIVES IN THIS SUITE rather than in SCOUT.TEST because it needs the same
// eight values and the same 4096-wide instrument the case above needs, and
// because the length that overflows is a property of what SCEXEC_evaluate
// hands over. SCOUT.TEST pins the row's FORMAT; this pins that the row is
// whole at the longest suffix a definition can produce.
//==============================================================================

dcl-proc test_check_row_long_suffix_is_not_cut export;

  dcl-s v     varchar(256) dim(8);
  dcl-s want  varchar(4096);
  dcl-s row   like(SCOUT_LINE_t);
  dcl-s rtext varchar(4096);
  dcl-s i     like(INTEGER_t);

  for i = 1 to 8;
    v(i) = lc_jobname('L8' + %char(i): 128);
    if i = 1;
      want = 'JOBNAME:' + v(i);
    else;
      want += ', JOBNAME:' + v(i);
    endif;
  endfor;

  iEqual(1102: %len(want): 'eight renderings joined with ", "');

  row = SCOUT_check_row('NOT RUNNING': 'lcrow8': 'ZZ row8':
                        SCOUT_not_running_suffix(want));
  rtext = %trimr(row);

  assert((%len(rtext) > 0): 'the row is not blank');
  assert((%scan('JOBNAME:' + v(8): rtext) > 0):
         'the eighth criterion is in the row whole - the row holds ' +
         %char(%len(rtext)) + ' characters');
  assert((%subst(rtext: %len(rtext): 1) = ']'):
         'and the row ends with its closing bracket, not mid-criterion - ' +
         'it ends "' + %trim(tail48(rtext)) + '"');

end-proc;

//==============================================================================
// THE CONTROL - two short criteria, a row that fits
//
// Green today and after any fix. It rules out a "fix" that stopped emitting
// the suffix, or shortened it, or dropped criteria past the first few: every
// one of those would satisfy the case above by making the row fit, and every
// one of them fails here.
//
// 20-character values, 28 rendered, 58 joined. Nothing near any width.
//==============================================================================

dcl-proc test_check_row_two_short_criteria_control export;

  dcl-ds def   likeds(SCDEF_t)       inz(*likeds);
  dcl-ds ev    likeds(SCEXEC_EVAL_t) inz(*likeds);
  dcl-s  v1    varchar(256);
  dcl-s  v2    varchar(256);
  dcl-s  want  varchar(4096);
  dcl-s  got   varchar(4096);
  dcl-s  row   like(SCOUT_LINE_t);
  dcl-s  rtext varchar(4096);

  v1 = lc_jobname('C2A': 20);
  v2 = lc_jobname('C2B': 20);

  want = 'JOBNAME:' + v1 + ', JOBNAME:' + v2;
  iEqual(58: %len(want): 'two renderings of 28, joined with ", "');

  assert(pt_load_def('lcrow2.yaml':
    'name: ZZ row2' + LF +
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + v1 + ',' + v2 + LF: def): 'load');

  iEqual(2: def.criteria_count: 'two criteria');

  SCEXEC_evaluate(def: ev);

  aEqual('NOT RUNNING': ev.state: 'neither job exists');
  iEqual(2: ev.failed_count: 'both failed');

  got = %trimr(ev.failed_text);
  lg_equal(want: got: 'failed_text carries both renderings');

  row = SCOUT_check_row(ev.state: def.short_name: def.friendly:
                        SCOUT_not_running_suffix(got));
  rtext = %trimr(row);

  assert((%subst(rtext: %len(rtext): 1) = ']'):
         'the row ends with its closing bracket');
  assert((%scan('JOBNAME:' + v2: rtext) > 0):
         'and the second criterion is in the row whole');

end-proc;

//##############################################################################
//##                                                                          ##
//##  JOB-ORDER block - SCEXEC_jobs returns its list in ASCENDING JOB NUMBER  ##
//##                                                                          ##
//##############################################################################
//
// SCEXEC_jobs(def: jobs) returns the count of jobs satisfying a service's
// check-alive criteria and fills jobs.name(1..count) with qualified names in
// the form number/user/name. The ORDER of that list is becoming defined:
// ascending job number. These cases were written before the change and are
// red on it.
//
//------------------------------------------------------------------------------
// WHAT IS NOT ASSERTED HERE, AND WHY
//------------------------------------------------------------------------------
//
// NOT AGREEMENT WITH UPSTREAM. Upstream sc lists the same jobs in a different
// order, measured to be Java HashSet iteration order over the job-name
// strings - a function of the job NUMBERS, which change on every restart. It
// reshuffles whenever a service is restarted, so it is not an order anything
// can be implemented against and no case here asks for it. This is a
// deliberate departure, not a defect.
//
// NOT "SORTED BY NUMBER" AS AGAINST "SORTED AS A STRING". An IBM i job number
// is always six digits, zero-padded, so the two implementations give
// identical results on every input that can exist. NO FIXTURE CAN SEPARATE
// THEM and none below claims to. What the fixture guard DOES assert is the
// premise: that every staged number is six characters wide. If that ever
// stopped being true the two readings would part company, and the guard is
// where that would be noticed.
//
//------------------------------------------------------------------------------
// THE FIXTURE, AND WHY IT IS SHAPED THIS WAY
//------------------------------------------------------------------------------
//
// The database's natural order is USUALLY ALREADY ASCENDING - three jobs
// staged under one name were measured coming back in ascending number order.
// So a service with a SINGLE criterion gives the same answer before and after
// the change, and a case built on one alone would pass either way: watching
// the change not crash rather than testing it (CLAUDE.md, "Test first").
//
// What separates them is TWO criteria where the criterion written FIRST
// matches a job with a HIGHER number than the jobs the second criterion
// matches. Today's answer visits the criteria in the order they are written,
// so the high-numbered job comes FIRST; ascending order puts it LAST.
//
// Job numbers ascend with submission, so the suite stages the SECOND
// criterion's three jobs FIRST and the FIRST criterion's single job LAST:
//
//   submitted   1st  2nd  3rd        4th
//   name        B    B    B          A
//   number      low  ..   ..         highest
//
//   check_alive: A,B     today ->  a,  b1, b2, b3
//                        after ->  b1, b2, b3, a
//
// EVERY EXPECTED VALUE IS ABSOLUTE. The suite records which qualified name
// each SBMJOB produced, in submission order, and the expected list is built
// from that record - it is never computed by sorting anything. A test helper
// that sorted would be a second implementation of the thing under test, and
// this project has already had a helper share the defect it was covering.
//
// THE JOBS ARE THE SUITE'S OWN. Two invented names, submitted by this suite,
// ended by it on the way out and swept on the way in. Nothing pre-existing on
// the machine is counted, per docs/testing-notes.md - "Test against a service
// the suite owns, not one the system owns".
//
// STAGED LAZILY, not in setUpSuite. Standing four jobs up costs a few seconds
// and can fail; done in set-up, a failure would take every one of this
// suite's eighty-odd unrelated cases with it. Done here, only the four cases
// that need the jobs go red, and they say why.
//
//------------------------------------------------------------------------------
// BASIS
//------------------------------------------------------------------------------
//
//   MEASURED  the natural-order and separating-fixture shapes quoted above
//             were measured on this machine before these cases were written.
//   CHOSEN    ascending job number itself. Upstream's order is not
//             implementable; this one is, and is a deliberate departure.
//
// 09/09/2026 - RM - written against the change, before the change
//==============================================================================

//------------------------------------------------------------------------------
// ord_is_staged - is this qualified name one of ours?
//
// GUARDED FOR THE SAME REASON SCQRY.TEST's end_pgm_job is: the sweep ENDJOBs
// whatever a lookup returns, and that lookup is code this project tests
// rather than trusts. A lookup that started returning every active job would
// otherwise have this suite end all of them.
//------------------------------------------------------------------------------
dcl-proc ord_is_staged;
  dcl-pi *n like(BOOLEAN_t);
    qualified varchar(64) const;
    jobname   varchar(10) const;
  end-pi;

  dcl-s q varchar(64);
  dcl-s w varchar(16);

  q = %trimr(qualified);
  w = '/' + %trimr(jobname);

  if %len(q) <= %len(w);
    return false;
  endif;

  return (%subst(q: %len(q) - %len(w) + 1) = w);

end-proc;

//------------------------------------------------------------------------------
// ord_number - the job number out of a qualified name
//------------------------------------------------------------------------------
dcl-proc ord_number;
  dcl-pi *n varchar(16);
    qualified varchar(64) const;
  end-pi;

  dcl-s q varchar(64);
  dcl-s p like(INTEGER_t);

  q = %trimr(qualified);
  p = %scan('/': q);

  if p < 2;
    return '';
  endif;

  return %subst(q: 1: p - 1);

end-proc;

//------------------------------------------------------------------------------
// ord_names - the whole returned list as one value
//
// Plain concatenation, per docs/testing-notes.md: aEqual reads array element N
// with element N-1's length, so comparing the list one subscript at a time
// would compare truncated values. One joined string also makes a failure
// legible - it says what the order WAS, not merely that element 3 differed.
//------------------------------------------------------------------------------
dcl-proc ord_names;
  dcl-pi *n varchar(512);
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s list varchar(512) inz('');

  for i = 1 to jobs.count;
    if i > 1;
      list += ', ';
    endif;
    list += %trim(jobs.name(i));
  endfor;

  if list = '';
    return '(none)';
  endif;

  return list;

end-proc;

//------------------------------------------------------------------------------
// ord_expected - the answer, built from what was submitted and when
//
// NOT SORTED. The three B jobs are listed in submission order and the A job
// last, because that is the order they were created in and job numbers ascend
// with creation - which the fixture guard asserts rather than assumes.
//------------------------------------------------------------------------------
dcl-proc ord_expected;
  dcl-pi *n varchar(512);
    with_a like(BOOLEAN_t) const;
  end-pi;

  dcl-s k    like(INTEGER_t);
  dcl-s list varchar(512) inz('');

  for k = 1 to ORD_B_JOBS;
    if k > 1;
      list += ', ';
    endif;
    list += %trim(g_ord_b(k));
  endfor;

  if with_a;
    list += ', ' + %trim(g_ord_a);
  endif;

  return list;

end-proc;

//------------------------------------------------------------------------------
// ord_equal - compare two lists, with the reasoning intact
//
// Its own helper rather than aEqualV because aEqualV's fieldName is
// varchar(64) and iRPGUnit's own parameters are too: docs/testing-notes.md
// records that anything longer is silently cut at 64, at exactly the moment
// someone is reading it to find out what broke. assert's msgIfFalse is
// varchar(16384), so routing the whole message through assert keeps it.
//------------------------------------------------------------------------------
dcl-proc ord_equal;
  dcl-pi *n;
    expected varchar(512) const;
    actual   varchar(512) const;
    ctx      varchar(500) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(ctx) + ' - expected [' + %trim(expected) +
         '] but was [' + %trim(actual) + ']');

end-proc;

//------------------------------------------------------------------------------
// ord_submit - submit one job and say which one it turned out to be
//
// It waits for the job to be ACTIVE and then identifies it as the one of that
// name NOT already accounted for in `known`. Identified rather than assumed:
// a lookup returns jobs in whatever order it likes, and the whole subject
// here is order, so nothing may be inferred from the order this comes back
// in.
//
// It asserts the exact count of jobs carrying the name, not merely that one
// more appeared. A job left active by a run killed before its teardown would
// otherwise be silently absorbed into the fixture and make every count below
// wrong by one.
//------------------------------------------------------------------------------
dcl-proc ord_submit;
  dcl-pi *n varchar(64);
    jobname varchar(10) const;
    // 2048, not 512: the overflow fixture hands this the names of 32 jobs,
    // and a set truncated on the way in would let this return a job that is
    // already known as though it were the one just submitted.
    known   varchar(2048) const;
    want    like(INTEGER_t) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd    varchar(256);
  dcl-s ok     like(BOOLEAN_t);
  dcl-s waited like(INTEGER_t) inz(0);
  dcl-s i      like(INTEGER_t);
  dcl-s n      like(INTEGER_t);
  dcl-s cand   varchar(64);

  // DLYJOB rather than a PASE delay: the job need only exist under a name of
  // our choosing for the length of the run, and this needs nothing installed
  // and nothing staged in the IFS.
  cmd = 'SBMJOB CMD(DLYJOB DLY(' + ORD_RUNS_FOR + ')) JOB(' +
        %trim(jobname) + ') JOBQ(QUSRNOMAX)';
  ok = QCMD_exc(cmd: qerr);
  assert(ok: 'submitted a staged job: ' + %trim(cmd));

  dow waited < ORD_WAIT;
    if SCQRY_jobs_by_name(jobname: '': jobs) >= want;
      leave;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  n = SCQRY_jobs_by_name(jobname: '': jobs);
  iEqual(want: n: 'staged jobs active named ' + %trim(jobname));

  for i = 1 to jobs.count;
    cand = %trim(jobs.name(i));
    if %scan('|' + %trim(cand) + '|': known) = 0;
      return cand;
    endif;
  endfor;

  assert(false: 'could not tell the job just submitted as ' +
                %trim(jobname) + ' from the ones already staged - active: ' +
                ord_names(jobs) + ', already known: ' + %trim(known));

  return '';

end-proc;

//------------------------------------------------------------------------------
// ord_end_all - end every staged job of one name, and WAIT for it to go
//
// ENDJOB returns when the request is made, not when the job has ended. The
// same shortcut made SCLIFE.TEST flaky; docs/testing-notes.md has it.
//------------------------------------------------------------------------------
dcl-proc ord_end_all;
  dcl-pi *n;
    jobname varchar(10) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s i      like(INTEGER_t);
  dcl-s waited like(INTEGER_t) inz(0);
  dcl-s name   varchar(64);

  // ENDS AND RE-QUERIES IN ONE LOOP, rather than ending once and then
  // waiting. A lookup fills a structure holding SCQRY_MAX_JOBS names, so a
  // single pass CANNOT SEE more jobs than that - and the overflow fixture
  // stages one more than that on purpose. Written the other way round, this
  // ended the 32 it could see, waited sixty seconds for a thirty-third it
  // had never asked about, and left it running on the machine. Measured, on
  // the first run of that fixture.
  //
  // Re-ending a job that is already ending is harmless; the message is
  // ignored, as every other command in this sweep's is.
  dow waited < ORD_WAIT;
    if SCQRY_jobs_by_name(jobname: '': jobs) = 0;
      return;
    endif;

    for i = 1 to jobs.count;
      name = %trim(jobs.name(i));
      if ord_is_staged(name: jobname);
        QCMD_exc('ENDJOB JOB(' + name + ') OPTION(*IMMED)': qerr);
      endif;
    endfor;

    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  assert((SCQRY_jobs_by_name(jobname: '': jobs) = 0):
         'staged jobs named ' + %trim(jobname) + ' did not end within ' +
         %char(ORD_WAIT) + 's - end them by hand before the next run, or ' +
         'the fixture counts below will be wrong by however many are left');

end-proc;

//------------------------------------------------------------------------------
// ord_sweep - both names, unconditionally
//------------------------------------------------------------------------------
dcl-proc ord_sweep;

  ord_end_all(ORD_JOB_A);
  ord_end_all(ORD_JOB_B);
  ord_end_all(ORD_JOB_C);

end-proc;

//------------------------------------------------------------------------------
// ord_stage - stand the four jobs up, once per run
//
// B FIRST AND A LAST, which is the whole of the fixture: job numbers ascend
// with submission, so the job the first criterion matches carries the highest
// number.
//------------------------------------------------------------------------------
dcl-proc ord_stage;

  dcl-s k     like(INTEGER_t);
  dcl-s known varchar(512);

  if g_ord_staged;
    return;
  endif;

  // A second attempt after a failed one would cost another minute of waiting
  // and fail the same way, and the reader would then have four failures to
  // read instead of one.
  assert((not g_ord_tried):
         'the staged jobs could not be created earlier in this run - ' +
         'whichever ordering case ran first says why');
  g_ord_tried = true;

  // Debris from a run killed before its teardown. ITS OWN TWO NAMES ONLY -
  // ord_sweep also ends the overflow fixture's jobs, and under ORDER(*API)
  // this may run after ord_stage_c has staged them.
  ord_end_all(ORD_JOB_A);
  ord_end_all(ORD_JOB_B);

  known = '|';
  for k = 1 to ORD_B_JOBS;
    g_ord_b(k) = ord_submit(ORD_JOB_B: known: k);
    known += %trim(g_ord_b(k)) + '|';
  endfor;

  g_ord_a = ord_submit(ORD_JOB_A: '|': 1);

  g_ord_staged = true;

end-proc;

//==============================================================================
// FIXTURE GUARD - the four staged jobs, and the premise the others rest on
//
// Asserts what the ordering cases below would otherwise assume:
//
//   - every staged job number is SIX characters, which is what makes sorting
//     the qualified name as a string and sorting by job number as a number
//     the same operation. Nothing here can separate those two readings and
//     nothing claims to; this is the assertion that says WHY.
//   - the numbers ascend with submission, so the A job - submitted last, and
//     matched by the FIRST criterion below - carries the HIGHEST number.
//
// The second is the one that can genuinely go wrong: the system's job number
// counter wraps at 999999, and a run that straddled the wrap would make the
// separating case below fail for a reason that has nothing to do with the
// code. It fails HERE instead, saying so.
//
// SEPARATES NOTHING about ordering, and is not meant to. It is green today
// and green after the change.
//==============================================================================

dcl-proc test_jobs_fixture_numbers_ascend export;

  dcl-s k   like(INTEGER_t);
  dcl-s num varchar(16);
  dcl-s prv varchar(16) inz('');

  ord_stage();

  for k = 1 to ORD_B_JOBS;
    iEqual(6: %len(ord_number(g_ord_b(k))):
           'FIXTURE: job number is six digits');
  endfor;
  iEqual(6: %len(ord_number(g_ord_a)):
         'FIXTURE: job number is six digits');

  for k = 1 to ORD_B_JOBS;
    num = ord_number(g_ord_b(k));
    assert((num > prv):
           'FIXTURE: staged job numbers ascend with submission - got ' +
           %trim(g_ord_b(k)) + ' after ' + %trim(prv) +
           '. If this failed the system job number counter wrapped ' +
           'during the run; re-run it');
    prv = num;
  endfor;

  num = ord_number(g_ord_a);
  assert((num > prv):
         'FIXTURE: the job the FIRST criterion matches was submitted LAST ' +
         'and so carries the HIGHEST number - got ' + %trim(g_ord_a) +
         ' after ' + %trim(prv) + '. Without that the separating case ' +
         'below cannot separate anything');

end-proc;

//==============================================================================
// ONE CRITERION - the three jobs come back in ascending number order
//
// GREEN TODAY, and said plainly: the database's natural order for three jobs
// staged under one name was measured as already ascending, so this case
// SEPARATES NOTHING from today's unordered behaviour.
//
// It is here because it is the working case, and because two of the rival
// readings of the change fail it where they pass everything else:
//
//   - sorted the WRONG WAY round. A descending sort satisfies any assertion
//     that only checks "the list is sorted"; this one names the direction.
//   - a sort that DROPS or DUPLICATES an entry. The count is asserted as well
//     as the order, and the order is asserted as an exact list rather than as
//     a property.
//==============================================================================

dcl-proc test_jobs_one_criterion_ascends export;

  dcl-ds def  likeds(SCDEF_t)      inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  ord_stage();

  assert(pt_load_def('ordone.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + ORD_JOB_B + LF: def): 'load');

  iEqual(1: def.criteria_count: 'one criterion');

  n = SCEXEC_jobs(def: jobs);

  iEqual(ORD_B_JOBS: n: 'the three staged jobs, and only those');
  iEqual(ORD_B_JOBS: jobs.count: 'the structure agrees with the return value');

  ord_equal(ord_expected(false): ord_names(jobs):
            'one criterion, three jobs, ascending job number - a descending ' +
            'sort fails here and passes every "is it sorted" test');

end-proc;

//==============================================================================
// TWO CRITERIA - THE SEPARATING CASE
//
// RED TODAY. The first criterion matches the job submitted LAST, so today's
// answer - criteria in the order they are written, jobs in whatever order the
// database returned them - puts the highest-numbered job FIRST:
//
//   today   a,  b1, b2, b3
//   after   b1, b2, b3, a
//
// This is the only shape in this suite where the two readings disagree, and
// every other case in this block gives the same answer either way. If this
// case is ever weakened - to "the list is sorted", or to a single criterion -
// the block stops testing the change and starts watching it not crash.
//
// THE COUNT IS ASSERTED TOO. A sort that also deduplicated, or one that
// dropped an entry off an end, would satisfy an order-only assertion; four
// distinct jobs are staged and four must come back.
//==============================================================================

dcl-proc test_jobs_ascend_across_criteria export;

  dcl-ds def  likeds(SCDEF_t)      inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  ord_stage();

  // A FIRST and B SECOND, deliberately. Written the other way round the
  // criteria would already be visited low-number-first and today's code would
  // return the ascending answer by accident.
  assert(pt_load_def('ordtwo.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + ORD_JOB_A + ',' + ORD_JOB_B + LF: def): 'load');

  iEqual(2: def.criteria_count: 'two criteria');

  n = SCEXEC_jobs(def: jobs);

  iEqual(ORD_B_JOBS + 1: n: 'all four staged jobs');
  iEqual(ORD_B_JOBS + 1: jobs.count:
         'the structure agrees with the return value');

  ord_equal(ord_expected(true): ord_names(jobs):
            'the job matched by the FIRST criterion has the HIGHEST number ' +
            'and must be listed LAST - today it is listed first, which is ' +
            'the whole of what this case separates');

end-proc;

//==============================================================================
// A JOB MATCHED BY TWO CRITERIA IS LISTED ONCE, AND STILL IN ORDER
//
// RED TODAY, on the same shape as the case above, with the deduplication
// question added: the A criterion is written twice, so the A job satisfies
// criterion 1 and criterion 3.
//
//   today   a,  b1, b2, b3      (deduplicated, unordered)
//   after   b1, b2, b3, a
//
// FOUR, NOT FIVE, and that number is the assertion. Deduplication exists
// today - test_jobs_deduplicated covers it for a repeated PORT criterion -
// and a sort dropped in front of, behind, or instead of it could lose it
// without changing the ORDER of anything. An order-only assertion would not
// notice; a count-only assertion would not notice the order. Both are here.
//==============================================================================

dcl-proc test_jobs_repeated_criterion_listed_once_in_order export;

  dcl-ds def  likeds(SCDEF_t)      inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  ord_stage();

  assert(pt_load_def('orddup.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + ORD_JOB_A + ',' + ORD_JOB_B + ',' + ORD_JOB_A + LF:
    def): 'load');

  iEqual(3: def.criteria_count: 'three criteria, two of them the same');

  n = SCEXEC_jobs(def: jobs);

  iEqual(ORD_B_JOBS + 1: n:
         'four jobs, not five - the repeated criterion adds nothing');
  iEqual(ORD_B_JOBS + 1: jobs.count:
         'the structure agrees with the return value');

  ord_equal(ord_expected(true): ord_names(jobs):
            'a job matched by two criteria is listed once, and the list is ' +
            'still in ascending job number - a sort that deduplicated, or ' +
            'one that lost the deduplication, fails one of these two');

end-proc;

//==============================================================================
// PER-CRITERION OVERFLOW - the cap keeps the OLDEST jobs, in order
//
// SCQRY_JOBS_t holds SCQRY_MAX_JOBS names, 32 today. A criterion matching
// more than that overflows, and the truncation happens inside the fetch -
// before any merged list exists - so which jobs survive cannot be decided by
// sorting afterwards. It is decided by the order the rows arrive in. Rows now
// arrive lowest job number first, so the cap keeps the OLDEST 32.
//
// THE FIXTURE IS 33 JOBS UNDER ONE NAME. The first 32 are staged and RECORDED
// - a lookup of exactly 32 returns all of them, so the recorded set is exact
// - and the 33rd is submitted afterwards.
//
// FOUR ASSERTIONS, each ruling out a different wrong answer:
//
//   count is exactly 32        the cap holds at all
//   the first-submitted job
//     is kept and listed 1st   rules out a cap that kept the NEWEST 32,
//                              which ascends just as prettily
//   ascends at every step      rules out an ordering that survives four jobs
//                              and not thirty-two
//   every job kept is one of
//     the 32 RECORDED          rules out a cap that kept an arbitrary 32.
//                              Thirty-two distinct ascending names, all drawn
//                              from a set of 32, can only be that whole set,
//                              so this pins the kept set exactly
//
//------------------------------------------------------------------------------
// THE ONE THING THIS CASE CANNOT VERIFY, SAID PLAINLY
//------------------------------------------------------------------------------
//
// That the 33rd job is really there. EVERY job lookup this suite has fills a
// structure holding SCQRY_MAX_JOBS names, so all of them answer 32 whether 32
// or 33 jobs of that name are active. The suite cannot count past its own cap,
// and it cannot name the job the cap drops, because the dropped job is by
// definition the one no lookup returns.
//
// So the residual risk is exactly this: if the 33rd SBMJOB were accepted and
// the job never went active, there would be no overflow, the four assertions
// above would all hold, and the case would report a pass having tested
// nothing. It is thin - the queue is *NOMAX, the same command started the 32
// jobs before it milliseconds earlier, and the submit itself is asserted - but
// it is real and it is not asserted away.
//
// TWO WAYS TO CLOSE IT, neither taken, both recorded so the next person does
// not have to find them again:
//
//   - END one of the 32 and look again. If a 33rd existed the lookup still
//     returns 32, one of them a name not in the recorded set; if it did not,
//     it returns 31. That both proves and NAMES the extra job - but it also
//     destroys the overflow it just proved, so the assertions above would have
//     to run before it and would still be about the unproved state.
//   - READ THE JOB NUMBER OUT OF THE SUBMIT. SBMJOB's completion message
//     names the job it created; if the command helper surfaces completion
//     messages on success as well as failure, the 33rd job's identity comes
//     from the submit rather than from a lookup, and the absence assertion
//     can be made directly. Whether it does was not established.
//
// WHAT IS NOT ASSERTED AT ALL: which 32 survive when more than 32 match
// ACROSS criteria. The merge fills from each criterion in turn, so that is a
// property of the criterion order rather than of the job numbers, and it is
// documented rather than fixed. This case uses ONE criterion so it cannot be
// quietly asserting the undocumented half.
//
// 09/09/2026 - RM - written after the fix, on a path the fix created
//==============================================================================

//------------------------------------------------------------------------------
// ord_known - every name in a list, delimited, for membership tests
//
// 2048 wide because 32 qualified names do not fit in 512, and a set truncated
// on the way in would make a membership test answer "not one of ours" for a
// job that is - the assertion below failing for a reason that is entirely the
// helper's.
//------------------------------------------------------------------------------
dcl-proc ord_known;
  dcl-pi *n varchar(2048);
    jobs likeds(SCQRY_JOBS_t);
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s list varchar(2048) inz('|');

  for i = 1 to jobs.count;
    list += %trim(jobs.name(i)) + '|';
  endfor;

  return list;

end-proc;

//------------------------------------------------------------------------------
// ord_submit_many - fill a name up to `want` active jobs
//
// Submits without identifying each one, which is the point: only two of the
// staged jobs are ever named in an assertion, and identifying all of them
// would cost a lookup apiece to no purpose.
//
// The submits are COUNTED rather than asserted one at a time, so a fixture
// this size contributes two assertions rather than thirty-two and the suite's
// assertion count still means something. A submit that was refused shows up
// in the count assertion that follows it either way.
//
// `want` MUST NOT EXCEED SCQRY_MAX_JOBS: the count it verifies comes from a
// lookup that cannot return more than that, so asking for more would wait out
// the timeout and then fail on a number that was never obtainable. Measured,
// by asking for 33.
//------------------------------------------------------------------------------
dcl-proc ord_submit_many;
  dcl-pi *n;
    jobname varchar(10) const;
    from    like(INTEGER_t) const;
    want    like(INTEGER_t) const;
  end-pi;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd    varchar(256);
  dcl-s k      like(INTEGER_t);
  dcl-s bad    like(INTEGER_t) inz(0);
  dcl-s waited like(INTEGER_t) inz(0);
  dcl-s n      like(INTEGER_t);

  cmd = 'SBMJOB CMD(DLYJOB DLY(' + ORD_RUNS_FOR + ')) JOB(' +
        %trim(jobname) + ') JOBQ(QUSRNOMAX)';

  for k = from + 1 to want;
    if not QCMD_exc(cmd: qerr);
      bad += 1;
    endif;
  endfor;

  iEqual(0: bad: 'SBMJOBs refused while staging ' + %trim(jobname));

  dow waited < ORD_WAIT;
    if SCQRY_jobs_by_name(jobname: '': jobs) >= want;
      leave;
    endif;
    QCMD_exc('DLYJOB DLY(1)': qerr);
    waited += 1;
  enddo;

  n = SCQRY_jobs_by_name(jobname: '': jobs);
  iEqual(want: n: 'staged jobs active named ' + %trim(jobname));

end-proc;

//------------------------------------------------------------------------------
// ord_stage_c - 33 jobs under one name, 32 of them recorded
//
// Sweeps ONLY its own name, and ord_stage sweeps only A and B. Sharing one
// sweep between them would have whichever staged second end the other's jobs,
// and under ORDER(*API) which runs second is a coin toss - a failure that
// arrives on some runs and not others.
//------------------------------------------------------------------------------
dcl-proc ord_stage_c;

  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-ds qerr likeds(QCMD_ERR_t);
  dcl-s cmd varchar(256);
  dcl-s ok  like(BOOLEAN_t);

  if g_ord_c_staged;
    return;
  endif;

  assert((not g_ord_c_tried):
         'the 33 staged jobs could not be created earlier in this run - ' +
         'the overflow case says why');
  g_ord_c_tried = true;

  ord_end_all(ORD_JOB_C);

  // The first one, identified: it is the only job of that name at this
  // point, and it is the job the cap must KEEP and list first.
  g_ord_c_first = ord_submit(ORD_JOB_C: '|': 1);

  // Up to a full structure's worth, unidentified but counted.
  ord_submit_many(ORD_JOB_C: 1: ORD_CAP);

  // The recorded set, taken while it is still exactly obtainable. One more
  // job than this and no lookup here can see the difference.
  iEqual(ORD_CAP: SCQRY_jobs_by_name(ORD_JOB_C: '': jobs):
         'the 32 recorded before the 33rd is submitted');
  g_ord_c_set = ord_known(jobs);

  // AND ONE MORE, WHICH NOTHING IN THIS SUITE CAN SEE - see the case header,
  // "the one thing this case cannot verify".
  cmd = 'SBMJOB CMD(DLYJOB DLY(' + ORD_RUNS_FOR + ')) JOB(' + ORD_JOB_C +
        ') JOBQ(QUSRNOMAX)';
  ok = QCMD_exc(cmd: qerr);
  assert(ok: 'submitted the 33rd job, the one that overflows: ' + %trim(cmd));

  // Nothing can be polled for, so it is given the time the other 32 needed
  // rather than being asked about.
  QCMD_exc('DLYJOB DLY(2)': qerr);

  g_ord_c_staged = true;

end-proc;

dcl-proc test_jobs_overflowing_criterion_keeps_the_oldest export;

  dcl-ds def  likeds(SCDEF_t)      inz(*likeds);
  dcl-ds jobs likeds(SCQRY_JOBS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);
  dcl-s  i    like(INTEGER_t);
  dcl-s  bad  like(INTEGER_t) inz(0);
  dcl-s  num  varchar(16);
  dcl-s  prv  varchar(16) inz('');
  dcl-s  why  varchar(256) inz('');

  ord_stage_c();

  iEqual(ORD_CAP: SCQRY_MAX_JOBS: 'cap moved - restage this case for it');

  assert(pt_load_def('ordcap.yaml':
    'start_cmd: /usr/bin/ptprobe' + LF +
    'check_alive: ' + ORD_JOB_C + LF: def): 'load');

  n = SCEXEC_jobs(def: jobs);

  iEqual(ORD_CAP: n: '33 jobs match, 32 come back');
  iEqual(ORD_CAP: jobs.count: 'the structure agrees with the return value');

  ord_equal(g_ord_c_first: %trim(jobs.name(1)):
            'the FIRST-submitted job is kept and listed first - a cap that ' +
            'kept the NEWEST 32 would ascend just as prettily and fail only ' +
            'here');

  for i = 1 to jobs.count;
    num = ord_number(%trim(jobs.name(i)));
    if num <= prv;
      bad = i;
      leave;
    endif;
    prv = num;
  endfor;

  // BUILT BEFORE THE ASSERT, not inside it. Both of assert's arguments are
  // evaluated before it is called, so naming jobs.name(bad) in the message
  // would subscript with zero on every PASSING run and end the job.
  if bad > 0;
    why = ' - first descent at element ' + %char(bad) + ', which is ' +
          %trim(ord_number(%trim(jobs.name(bad)))) + ' after ' + %trim(prv);
  else;
    why = '';
  endif;

  assert((bad = 0):
         'all 32 kept jobs ascend by job number at every step' + %trim(why) +
         '. Four jobs ascending does not prove thirty-two do');

  bad = 0;
  for i = 1 to jobs.count;
    if %scan('|' + %trim(jobs.name(i)) + '|': g_ord_c_set) = 0;
      bad = i;
      leave;
    endif;
  endfor;

  if bad > 0;
    why = ' - element ' + %char(bad) + ' is ' + %trim(jobs.name(bad)) +
          ', which was submitted after the first 32';
  else;
    why = '';
  endif;

  assert((bad = 0):
         'every job kept is one of the 32 OLDEST' + %trim(why) +
         '. With the count and the ascent above, this pins the kept set ' +
         'exactly: the cap keeps the oldest, not an arbitrary 32');

end-proc;
