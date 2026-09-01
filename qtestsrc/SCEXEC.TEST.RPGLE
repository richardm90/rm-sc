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

//##############################################################################
//##                                                                          ##
//##  BLOCK A - paste into qtestsrc/SCEXEC.TEST.RPGLE                         ##
//##                                                                          ##
//##  Blocks B (SCOUT.TEST) and C (SCDEF.TEST) are already in their suites    ##
//##  and are not reproduced here.                                            ##
//##                                                                          ##
//##############################################################################
//
// Tests for UNUSABLE criteria - written before the fix, and red today.
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
