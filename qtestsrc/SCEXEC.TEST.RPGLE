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

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-scexec-test-' + %trim(psds.current_user);
  IFS_crtdir(g_dir);
  SCOUT_set_colour(false);

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
