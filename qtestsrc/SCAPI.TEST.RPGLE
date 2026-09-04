**free

//==============================================================================
// SCAPI.TEST - Bound-call API test suite
//
// The API's whole purpose is that a caller gets values instead of text it has
// to parse, so these check the values - and check that nothing is written to
// standard output, since a green-screen caller must not have stray text
// appear underneath its display file.
//
// Starting and stopping are not exercised against real services here, for the
// same reason as SCEXEC: a suite that takes services down on whatever system
// it runs on, and leaves them down when it fails, is not one worth having.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCAPI_D.rpgleinc'
/include 'SCDIRS_D.rpgleinc'
/include 'include/RMLIST_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMENVVAR_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

//------------------------------------------------------------------------------
// The staged fixture for the failing-operation cases at the end of this file.
//
// Declared here because RPG requires it: a global declaration after the first
// procedure is RNF0256. The reasoning for the fixture is with the cases it
// serves, under "A FAILING OPERATION MUST SAY WHY".
//------------------------------------------------------------------------------

dcl-s g_api_dir like(STMF_t);

// A job name nothing on any system will be running. The staged services are
// checked for THIS, and submitted under API_JOBNAME, so the poll can never
// succeed however healthy the batch job is.
dcl-c API_BADJOB const('ZZSCAPINOJOB');

// Ten characters, so it is a legal job name, and not API_BADJOB
dcl-c API_JOBNAME const('ZZSCAPIJOB');

// THE TWO STAGED SERVICES, AND WHY NEITHER NAME IS A PREFIX OF THE OTHER.
//
// They were zzscapi_fail and zzscapi_fail2, and the group case below asks
// whether the joined message names BOTH members - with %scan, which finds a
// substring anywhere. 'zzscapi_fail' occurs inside 'zzscapi_fail2', so the
// assertion "the message names the FIRST failed member" was satisfied by a
// message that mentioned only the second. It could not fail for the defect it
// names, and the group branch losing one member's reason is exactly the defect
// it is watching for.
//
// So the short names now differ from their first distinguishing character
// onwards, in both directions, and so do the friendly ones. The same rule
// tools/narration-test.sh states for its own fixtures: no staged name is a
// prefix or a substring of any other staged name, and no short name is a
// substring of any friendly name.
dcl-c API_FAIL       const('zzscapi_alfa');
dcl-c API_FAIL_NAME  const('Zulu Scapi Alfa');
dcl-c API_FAIL2      const('zzscapi_bravo');
dcl-c API_FAIL2_NAME const('Zulu Scapi Bravo');
dcl-c API_GROUP      const('zzscapigrp');

dcl-pr write_failing_def;
  short    varchar(64) const;
  friendly varchar(64) const;
end-pr;

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
// SC_check_all returns a list a caller can page through
//==============================================================================

dcl-proc test_check_all_returns_a_list export;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);

  list = SC_check_all();

  assert((list.num_rows > 0): 'at least one service');
  iEqual(%size(row): list.val_size: 'rows are the status structure');

  assert(LIST_get_by_rrn(list: 1: %addr(row)): 'first row readable');
  assert((%len(%trim(row.NAME)) > 0): 'name populated');
  assert((%len(%trim(row.STATUS)) > 0): 'status populated');
  iEqual(1: row.RRN: 'RRN set, so the row can be found again');

end-proc;

//==============================================================================
// Status is one of the three values, as a value rather than as text to parse
//==============================================================================

dcl-proc test_status_is_a_known_value export;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  list = SC_check_all();

  for i = 1 to list.num_rows;
    assert(LIST_get_by_rrn(list: i: %addr(row)): 'row ' + %char(i));
    assert((row.STATUS = SC_RUNNING or row.STATUS = SC_NOT_RUNNING
            or row.STATUS = SC_PARTIAL):
           'row ' + %char(i) + ' status is one of the three known values, ' +
           'not "' + %trim(row.STATUS) + '"');
  endfor;

end-proc;

//==============================================================================
// Every row carries its own RRN, in order
//==============================================================================

dcl-proc test_rrns_are_sequential export;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-s i like(INTEGER_t);

  list = SC_check_all();

  for i = 1 to list.num_rows;
    assert(LIST_get_by_rrn(list: i: %addr(row)): 'row ' + %char(i));
    iEqual(i: row.RRN: 'RRN matches its position');
  endfor;

end-proc;

//==============================================================================
// The system group is left out by default, and can be asked for
//
// A caller wants the services someone configured, not the several dozen that
// ship with the operating system.
//==============================================================================

dcl-proc test_ignore_groups export;

  dcl-ds def_list likeds(LIST_t) inz(*likeds);
  dcl-ds all_list likeds(LIST_t) inz(*likeds);

  def_list = SC_check_all();
  all_list = SC_check_all('');

  assert((all_list.num_rows > def_list.num_rows):
         'asking for everything returns more than the default');

end-proc;

//==============================================================================
// DERIVED, not measured - a trailing comma in ignore_groups changes nothing
//
// ignore_groups is the same comma-separated list shape that abends (RNX0100)
// on a trailing comma elsewhere, and it reaches a SECOND copy of that splitter
// - the copy that was not fixed when the first one was. That is the entire
// basis for this test: the same six lines, so presumed the same defect. It was
// not measured, because the bound-call API has no upstream counterpart to
// measure it against.
//
// The CONTROL runs first, and it is what gives the real assertion any force.
// 'system' has to actually exclude something, or the comparison below is two
// identical no-ops agreeing with each other - the shape of assertion
// CLAUDE.md records as having hidden three defects here already. It also runs
// first because an abend ends the procedure where it happens.
//
// 'system,' is compared against 'system' rather than against the default, so
// that nothing here assumes what the default ignore list contains.
//
// Like test_ignore_groups above, this needs the system group to be populated
// on the box. If it is not, this suite has larger problems than a comma, and
// failing rather than skipping is the right answer.
//==============================================================================

dcl-proc test_ignore_groups_trailing_comma export;

  dcl-ds sys_list   likeds(LIST_t) inz(*likeds);
  dcl-ds all_list   likeds(LIST_t) inz(*likeds);
  dcl-ds trail_list likeds(LIST_t) inz(*likeds);

  // CONTROL, and first on purpose - 'system' must exclude something for the
  // assertion below to be capable of failing
  sys_list = SC_check_all('system');
  all_list = SC_check_all('');
  assert((sys_list.num_rows < all_list.num_rows):
         'ignoring system leaves out at least one service');

  // The defect - the same list, one trailing comma
  trail_list = SC_check_all('system,');

  iEqual(sys_list.num_rows: trail_list.num_rows:
         'a trailing comma is the same list, so the same services');

end-proc;

//==============================================================================
// SC_check fills one row
//==============================================================================

dcl-proc test_check_one_service export;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-ds one  likeds(SC_STATUS_ROW_t) inz(*likeds);

  list = SC_check_all();
  assert(LIST_get_by_rrn(list: 1: %addr(row)): 'take a real service');

  assert(SC_check(row.NAME: one): 'found');
  aEqualV(row.NAME: one.NAME: 'same service');
  aEqualV(row.STATUS: one.STATUS: 'same status');

end-proc;

//==============================================================================
// Refreshing one row keeps the RRN the caller had
//
// A subfile program refreshes a row and then puts it back with
// LIST_update_by_rrn, which needs the RRN to survive.
//==============================================================================

dcl-proc test_check_preserves_rrn export;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);

  list = SC_check_all();
  assert(LIST_get_by_rrn(list: 1: %addr(row)): 'take a real service');

  row.RRN = 7;
  assert(SC_check(row.NAME: row): 'found');
  iEqual(7: row.RRN: 'the caller RRN is left alone');

end-proc;

//==============================================================================
// An unknown service is reported, not guessed at
//==============================================================================

dcl-proc test_check_unknown_service export;

  dcl-ds row likeds(SC_STATUS_ROW_t) inz(*likeds);

  nEqual(false: SC_check('nosuchservice': row): 'not found');

end-proc;

//==============================================================================
// Acting on something that does not exist says so
//==============================================================================

dcl-proc test_unknown_service_message export;

  dcl-s msg like(SC_MSG_t);

  nEqual(false: SC_start('nosuchservice': msg): 'refused');
  assert((%scan('nosuchservice': msg) > 0): 'the message names it');

end-proc;

dcl-proc test_unknown_group_message export;

  dcl-s msg like(SC_MSG_t);

  nEqual(false: SC_stop('group:nosuchgroup': msg): 'refused');
  assert((%scan('nosuchgroup': msg) > 0): 'the message names it');

end-proc;

//==============================================================================
// The row structure matches what a caller is likely to already have
//
// The widths are the interface here: a subfile program adopting this should
// not have to change the structure it pages through.
//==============================================================================

dcl-proc test_row_layout export;

  dcl-ds row likeds(SC_STATUS_ROW_t) inz(*likeds);

  row.NAME   = *all'x';
  row.DESC   = *all'y';
  row.STATUS = *all'z';

  iEqual(64:  %len(row.NAME):   'name is 64');
  iEqual(128: %len(row.DESC):   'description is 128');
  iEqual(20:  %len(row.STATUS): 'status is 20');

end-proc;

//==============================================================================
// Definitions are cached; live status is not
//
// The cache is what makes the API worth using - reloading definitions on every
// call costs as much as running the command. But caching the STATUS as well
// would be a bug: the question a caller is asking is what the system is doing
// now.
//==============================================================================

dcl-proc test_status_is_never_cached export;

  dcl-ds first  likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-ds second likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-ds list   likeds(LIST_t) inz(*likeds);
  dcl-ds row    likeds(SC_STATUS_ROW_t) inz(*likeds);

  list = SC_check_all();
  assert(LIST_get_by_rrn(list: 1: %addr(row)): 'take a real service');

  assert(SC_check(row.NAME: first): 'first read');
  assert(SC_check(row.NAME: second): 'second read');

  // Both queried the system rather than one replaying the other. They agree
  // because nothing changed in between, which is the point: a cached status
  // would also agree, so this pins the values rather than the mechanism.
  aEqualV(first.STATUS: second.STATUS: 'consistent across calls');
  assert((first.STATUS = SC_RUNNING or first.STATUS = SC_NOT_RUNNING
          or first.STATUS = SC_PARTIAL): 'a real status, not a stale blank');

end-proc;

//==============================================================================
// SC_refresh is callable and leaves the API working
//==============================================================================

dcl-proc test_refresh export;

  dcl-ds before likeds(LIST_t) inz(*likeds);
  dcl-ds after  likeds(LIST_t) inz(*likeds);

  before = SC_check_all();
  SC_refresh();
  after = SC_check_all();

  iEqual(before.num_rows: after.num_rows:
         'the same services are found after a refresh');

end-proc;

//##############################################################################
//##                                                                          ##
//##  A FAILING OPERATION MUST SAY WHY                                        ##
//##                                                                          ##
//##############################################################################
//
// WHAT THIS SUITE COULD NOT SEE, AND WHY.
//
// Two procedures here already assert on `msg` - test_unknown_service_message
// and test_unknown_group_message - and both of them ask about a name SCAPI
// itself refuses before SCEXEC is ever reached. SCAPI fills those messages in.
// So every assertion this file made about `msg` was about text SCAPI writes,
// and no assertion at all was made about text SCAPI RELAYS.
//
// That is the gap the narration work fell through. SCEXEC_start now narrates
// its failures - it prints `ERROR: Timed out waiting for service '<friendly>'
// to start` - and returns failure with an EMPTY error string on the paths where
// it does. On the command line that is fine: the line has already been printed
// and the caller is a person reading a terminal. Through the API the reason is
// simply LOST. SC_start returns false and says nothing, where it used to say
// `<short> did not start within <n> seconds`.
//
// MEASURED 3 September 2026, through qtestsrc/SCAPIDRV.PGM.RPGLE against the
// deployed build, with a staged service that cannot come up:
//
//     op=start
//     svc=zzapis_fail
//     rc=1
//     msg=                          <- nothing at all
//
// and, as the control, the path SCAPI does fill in itself:
//
//     op=start
//     svc=nosuchservice
//     rc=1
//     msg=Unknown service nosuchservice
//
// The field works. Nothing is put in it.
//
// IT MATTERS MORE, NOT LESS, ONCE THE API GOES SILENT. The silence switch takes
// the printed copy away from an API caller deliberately, and that is only safe
// BECAUSE the reason comes back in `msg`. A silent API that also returns no
// reason does not hide a message from a green-screen program; it destroys it.
//
// WHY THE FIXTURE IS STAGED RATHER THAN BORROWED. The suite header says that
// starting and stopping are not exercised against real services here, and that
// stays true: everything below acts on two definitions this suite writes into a
// directory of its own and points SCDIRS at, exactly as SCLIFE.TEST does. Their
// start command is a bounded `sleep` that binds nothing and their liveliness
// criterion is a job name that never exists, so the start is guaranteed to take
// the TIMEOUT path - which is the path that narrates, and therefore the path
// that loses the message. A start command that failed outright would take a
// different branch and would probably return its message today, which would
// make this test pass while proving nothing.
//
// The short names begin with 'z' on purpose: the collection sorts by code
// point, so these two land at the END and no existing test that reads row 1
// meets them.
//==============================================================================

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_api_dir = '/tmp/rmsc-scapi-test-' + %trim(psds.current_user);
  IFS_crtdir(g_api_dir);

  // Nothing from a previous run should still be pointing anywhere
  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);

  write_failing_def(API_FAIL:  API_FAIL_NAME);
  write_failing_def(API_FAIL2: API_FAIL2_NAME);

  assert(ENVVAR_put(SCDIRS_CUSTOM_ENV: g_api_dir):
         'the staged directory could not be configured');

  // The API caches definitions, and this suite has changed where they come
  // from. Without this every case below would ask about a collection loaded
  // before the fixture existed.
  SC_refresh();

end-proc;

dcl-proc tearDownSuite export;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  // Unconditionally, whatever the tests did. A suite that leaves the search
  // path pointing at a directory it then deletes is worse than no suite.
  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);

  dir = IFS_opendir(g_api_dir);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if %len(filename) > 5
         and %subst(filename: %len(filename) - 4) = '.yaml';
        IFS_remove_file(%trim(g_api_dir) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_api_dir);
  endif;

  SC_refresh();

end-proc;

//------------------------------------------------------------------------------
// A definition that is guaranteed to time out.
//
// `sleep` rather than a command that fails: the start must reach the POLL and
// then run out of time, because that is the branch that narrates. A start
// command that could not be run at all takes a different branch, and a test
// that accidentally took it would be asserting about a message that is not the
// one at issue.
//
// IT IS SUBMITTED TO BATCH, AND THAT IS NOT A DETAIL. Measured 3 September
// 2026: with batch_mode unset, starting one of these from inside the RPGUnit
// job made the WHOLE iRPGUnit REPORT DISAPPEAR - the run exited 1 and printed
// nothing but the narration, no summary, no failure list, not even the joblog
// messages `system` normally echoes. The non-batch launcher runs the start
// command through PASE, and the job's standard output does not survive it.
//
// A suite whose report vanishes is worse than one that fails, for the reason
// CLAUDE.md gives about fixtures that are absent: it reports nothing while
// appearing to have run. SCLIFE.TEST submits its service to batch and its
// report is intact, which is what identified the difference, and this follows
// it.
//
// SO THE TWO NAMES ARE DELIBERATELY DIFFERENT. The job is submitted under
// API_JOBNAME and the liveliness criterion looks for API_BADJOB, which nothing
// will ever be called - so the batch job starts, the poll never finds what it
// is looking for, and the start times out. SCLIFE.TEST uses the same name for
// both, because it wants its service to come UP; this one wants the opposite
// and gets it from the mismatch rather than from a broken command.
//
// startup_wait_time is 2, because this is waited out on every run.
//------------------------------------------------------------------------------
dcl-proc write_failing_def;
  dcl-pi *n;
    short    varchar(64) const;
    friendly varchar(64) const;
  end-pi;

  dcl-s y      like(STRING_t);
  dcl-s handle like(INTEGER_t);
  dcl-s path   like(STMF_t);

  y = 'name: ' + %trim(friendly) + LF;
  y += 'start_cmd: /QOpenSys/usr/bin/sleep 20' + LF;
  y += 'check_alive: ' + API_BADJOB + LF;
  y += 'batch_mode: true' + LF;
  y += 'sbmjob_jobname: ' + API_JOBNAME + LF;
  y += 'sbmjob_opts: JOBQ(QUSRNOMAX)' + LF;
  y += 'startup_wait_time: 2' + LF;
  y += 'stop_wait_time: 2' + LF;
  y += 'groups:' + LF;
  y += '  - ' + API_GROUP + LF;

  path = %trim(g_api_dir) + '/' + %trim(short) + '.yaml';
  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: y);
  IFS_close_file(handle);

end-proc;

//==============================================================================
// The fixture proves itself before anything is concluded from it
//
// EVERY ASSERTION BELOW WOULD PASS FOR THE WRONG REASON WITHOUT THIS. If the
// staged directory never reached SCDIRS, SC_start would not find the service,
// SCAPI would refuse it, and SCAPI would fill in `Unknown service …` - which is
// a perfectly non-empty message. The regression case would go green against a
// fixture that did not exist, reporting the health of the one path that was
// already covered.
//
// So the API has to be able to SEE the staged definition, asked through
// SC_check, which is the same question by a route that changes nothing.
//==============================================================================

dcl-proc test_staged_failing_service_is_visible export;

  dcl-ds row likeds(SC_STATUS_ROW_t) inz(*likeds);

  assert(SC_check(API_FAIL: row):
         'the staged definition ' + API_FAIL + ' is not visible to the API - ' +
         'SCDIRS did not read ' + %trim(g_api_dir) + ', and every case below ' +
         'would be asserting about an unknown service instead');

  aEqualV(API_FAIL: row.NAME: 'the row is the staged service');
  aEqualV(SC_NOT_RUNNING: row.STATUS:
          'and it is not running, so a start of it has work to do');

  assert(SC_check(API_FAIL2: row): 'the second staged definition too');

end-proc;

//==============================================================================
// A failing start returns a reason, not merely a failure
//
// THE ASSERTION THE WHOLE BLOCK EXISTS FOR, and it is red today.
//
// SEPARATING VALUES, and the rival each rules out:
//
//   the call returns FALSE          rules out the service having come up. An
//                                   absent message from a start that SUCCEEDED
//                                   would be correct - there is no reason to
//                                   report - so the failure has to be
//                                   established before the message is asked
//                                   about, and it is asserted first
//   msg is non-blank                the defect itself
//   msg names the service           rules out a message that is non-empty by
//                                   accident - a bare 'failed', a stray
//                                   separator, or the '; ' the group branch
//                                   appends. Either name will do: RMSC's
//                                   present wording uses the short name and
//                                   upstream's uses the friendly one, and this
//                                   assertion must survive that change being
//                                   made
//
// IT IS NOT ASSERTED THAT THE MESSAGE MATCHES A PARTICULAR SENTENCE. The
// wording is a D2 decision - docs/messages.md records `<short> did not start
// within <n> seconds` against upstream's `ERROR: Timed out waiting for service
// '<friendly>' to start` and does not say which RMSC will settle on. Pinning
// one here would make this case fail when that decision is taken, for a reason
// that has nothing to do with what it is testing.
//==============================================================================

dcl-proc test_failing_start_returns_a_reason export;

  dcl-s msg like(SC_MSG_t);
  dcl-s ok  like(BOOLEAN_t);

  msg = *blanks;
  ok  = SC_start(API_FAIL: msg);

  nEqual(false: ok:
         'the staged service came UP - it was supposed to time out, so an ' +
         'assertion about its failure message would prove nothing');

  assert((%len(%trim(msg)) > 0):
         'SC_start returned failure with an EMPTY message. On the command ' +
         'line SCEXEC has already printed the reason; through the API this ' +
         'field is the only copy of it, and it is blank');

  assert((%scan(API_FAIL: msg) > 0 or %scan(API_FAIL_NAME: msg) > 0):
         'the message does not name the service by either name: "' +
         %trim(msg) + '"');

end-proc;

//==============================================================================
// A failing group start returns one reason per member, with no dangling glue
//
// TWO DEFECTS IN ONE MESSAGE, AND THE SECOND IS NOT REACHABLE YET.
//
// The group branch joins its members' reasons with '; ' and appends the
// separator per failed member rather than between them. Each reason is empty,
// for the reason above, so what should come back is the SEPARATORS ALONE.
//
// MEASURED 3 September 2026: it comes back BLANK. Not '; ; ' - nothing at all.
// So today this case fails on its non-empty assertion, exactly as the
// single-service one does, and the three shape assertions below are never
// reached.
//
// THEY ARE WRITTEN ANYWAY, and it is worth saying why rather than deferring
// them. The moment the reasons stop being empty, the dangling separator becomes
// visible and these become the assertions that see it - and at that moment a
// message of '<reason>; <reason>; ' is NOT blank, so the non-empty assertion
// alone would go green and report the join fixed along with the reason. A group
// case that only asked "is there a message" would do exactly that. The order
// they fire in is the order the two defects are fixed in.
//
// SEPARATING VALUES:
//
//   both members named        the real assertion. Two members failed and two
//                             reasons are owed, so both names must appear.
//                             IT ONLY ASKS THAT QUESTION BECAUSE THE NAMES ARE
//                             PREFIX-FREE - %scan finds a substring anywhere,
//                             so while the members were zzscapi_fail and
//                             zzscapi_fail2 the first-member assertion matched
//                             inside the second member's name and could not
//                             fail. See the declarations at the top of the file
//   does not end in ';'       rules out a separator appended after the last
//                             reason - the dangling '; ' the branch adds per
//                             failed member rather than between them
//   does not start with ';'   rules out one prepended before the first
//   no '; ;' anywhere         rules out a separator with nothing between it and
//                             the next, which is what an empty reason in the
//                             middle of a list looks like
//
// THE LAST THREE ARE STATED AS SHAPES RATHER THAN AS A LITERAL, on purpose. The
// wording of each reason is undecided; the shape of a joined list is not, and
// these three hold whatever the reasons turn out to say.
//==============================================================================

dcl-proc test_failing_group_start_reports_each_member export;

  dcl-s msg  like(SC_MSG_t);
  dcl-s ok   like(BOOLEAN_t);
  dcl-s trim varchar(512);

  msg = *blanks;
  ok  = SC_start('group:' + API_GROUP: msg);

  nEqual(false: ok:
         'the group start SUCCEEDED - both members were supposed to time ' +
         'out, so nothing below would be asserting about a failure');

  trim = %trimr(msg);

  assert((%len(%trim(trim)) > 0):
         'a failing group start returned an EMPTY message');

  assert((%scan(API_FAIL: trim) > 0 or %scan(API_FAIL_NAME: trim) > 0):
         'the message does not name the first failed member: "' + trim + '"');
  assert((%scan(API_FAIL2: trim) > 0 or %scan(API_FAIL2_NAME: trim) > 0):
         'the message does not name the second failed member: "' + trim + '"');

  assert((%subst(trim: %len(trim): 1) <> ';'):
         'the message ends in a separator with nothing after it - the join ' +
         'appends per member rather than between them: "' + trim + '"');
  assert((%subst(trim: 1: 1) <> ';'):
         'the message begins with a separator: "' + trim + '"');
  assert((%scan('; ;': trim) = 0):
         'two separators with nothing between them - a member reported no ' +
         'reason at all: "' + trim + '"');

end-proc;

//==============================================================================
// The unknown-service message still works, and it is the CONTROL
//
// test_unknown_service_message above asserts the same thing. This one exists
// beside the two cases above rather than instead of it, and its job is
// different: it is the proof that `msg` is delivered at all.
//
// Without it, a red on the two cases above has two readings - the reason is not
// being set, or the field never reaches the caller - and they call for
// different fixes. This one is green today and takes the second reading away.
//==============================================================================

dcl-proc test_message_field_is_delivered_at_all export;

  dcl-s msg like(SC_MSG_t);

  msg = *blanks;
  nEqual(false: SC_start('zznosuchservice': msg): 'refused');

  assert((%len(%trim(msg)) > 0):
         'even the unknown-service path returns no message, so the failures ' +
         'above are about DELIVERY and not about the reason being set');
  assert((%scan('zznosuchservice': msg) > 0): 'and it names what was asked for');

end-proc;
