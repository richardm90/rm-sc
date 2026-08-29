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
