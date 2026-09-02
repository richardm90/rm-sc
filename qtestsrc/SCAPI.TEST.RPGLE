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
/include 'include/RMLIST_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
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
