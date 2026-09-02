**free

//==============================================================================
// SCCOLL.TEST - Service definition collection test suite
//
// Builds a fixture tree with a subdirectory, a non-YAML file, a broken
// definition and a dependency cycle, then exercises discovery, grouping and
// dependency resolution against it.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCDIRS_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-s g_dir like(STMF_t);
dcl-s g_sub like(STMF_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr write_file;
  path    like(STMF_t) const;
  content like(STRING_t) const;
end-pr;

dcl-pr remove_tree end-pr;

dcl-s g_ord  like(STMF_t);
dcl-s g_ord2 like(STMF_t);

dcl-pr ord_setup end-pr;

dcl-pr ord_teardown end-pr;

dcl-pr cp_before like(BOOLEAN_t);
  a_val varchar(512) const;
  b_val varchar(512) const;
end-pr;

//==============================================================================
// Suite set-up
//==============================================================================

dcl-proc setUpSuite export;

  dcl-s y like(STRING_t);

  g_dir = '/tmp/rmsc-sccoll-test-' + %trim(psds.current_user);
  g_sub = %trim(g_dir) + '/sub';

  IFS_crtdir(g_dir);
  IFS_crtdir(g_sub);

  // A plain three-link chain: web depends on api depends on db
  y = 'start_cmd: /usr/bin/db' + LF;
  y += 'check_alive: 8080' + LF;
  y += 'groups:' + LF;
  y += '- data' + LF;
  write_file(%trim(g_dir) + '/db.yaml': y);

  y = 'start_cmd: /usr/bin/api' + LF;
  y += 'check_alive: 8081' + LF;
  y += 'service_dependencies:' + LF;
  y += '- db' + LF;
  y += 'groups:' + LF;
  y += '- web' + LF;
  write_file(%trim(g_dir) + '/api.yaml': y);

  y = 'start_cmd: /usr/bin/web' + LF;
  y += 'check_alive: 8082' + LF;
  y += 'service_dependencies:' + LF;
  y += '- api' + LF;
  y += 'groups:' + LF;
  y += '- web' + LF;
  y += '- autostart' + LF;
  write_file(%trim(g_dir) + '/web.yaml': y);

  // A cycle, and a dependency that does not exist
  y = 'start_cmd: /usr/bin/c1' + LF;
  y += 'check_alive: 8091' + LF;
  y += 'service_dependencies:' + LF;
  y += '- cyc2' + LF;
  write_file(%trim(g_dir) + '/cyc1.yaml': y);

  y = 'start_cmd: /usr/bin/c2' + LF;
  y += 'check_alive: 8092' + LF;
  y += 'service_dependencies:' + LF;
  y += '- cyc1' + LF;
  write_file(%trim(g_dir) + '/cyc2.yaml': y);

  y = 'start_cmd: /usr/bin/orphan' + LF;
  y += 'check_alive: 8093' + LF;
  y += 'service_dependencies:' + LF;
  y += '- nosuchservice' + LF;
  write_file(%trim(g_dir) + '/orphan.yaml': y);

  // .yml is as valid an extension as .yaml
  y = 'start_cmd: /usr/bin/cache' + LF;
  y += 'check_alive: 8094' + LF;
  write_file(%trim(g_dir) + '/cache.yml': y);

  // Not a definition, and must not be treated as one
  y = 'this is not a service' + LF;
  write_file(%trim(g_dir) + '/notes.txt': y);

  // A definition missing a required key: recorded, not fatal
  y = 'check_alive: 9999' + LF;
  write_file(%trim(g_dir) + '/broken.yaml': y);

  // In a subdirectory, which must NOT be walked. Upstream's
  // YamlServiceDefLoader.loadFromDirectory skips them outright -
  // 'if (f.isDirectory()) { continue; }' - and reaches the definitions it
  // ships under system/ and oss_common/ by naming those two paths, not by
  // recursing. A scan that recurses finds definitions upstream never sees.
  y = 'start_cmd: /usr/bin/nested' + LF;
  y += 'check_alive: 8095' + LF;
  write_file(%trim(g_sub) + '/nested.yaml': y);

  // The same short name as g_dir/db.yaml, in the directory loaded second.
  // Upstream merges each directory with putAll, so the later one wins - that
  // is what makes a user's copy of a service override the global copy.
  y = 'name: Overriding DB' + LF;
  y += 'start_cmd: /usr/bin/db-override' + LF;
  y += 'check_alive: 8081' + LF;
  write_file(%trim(g_sub) + '/db.yaml': y);

  ord_setup();

end-proc;

dcl-proc tearDownSuite export;

  remove_tree();
  ord_teardown();

end-proc;

//==============================================================================
// Helpers
//==============================================================================

dcl-proc write_file;
  dcl-pi *n;
    path    like(STMF_t) const;
    content like(STRING_t) const;
  end-pi;

  dcl-s handle like(INTEGER_t);

  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

end-proc;

dcl-proc remove_tree;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  // Subdirectory first: a directory cannot be removed while it holds files
  dir = IFS_opendir(g_sub);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_sub) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_sub);
  endif;

  dir = IFS_opendir(g_dir);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_dir) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_dir);
  endif;

  assert((not IFS_isa_directory(g_dir)):
         'Fixture tree ' + %trim(g_dir) + ' not removed');

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
// Discovery reads one directory flat and accepts both extensions
//
// Flat, not recursive, because that is what upstream does. A directory it
// would never look in is a directory RMSC must not report services from:
// finding MORE than upstream is as much a parity defect as finding fewer,
// and it is the harder one to notice, since nothing looks missing.
//==============================================================================

dcl-proc test_discovery export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');

  // db api web cyc1 cyc2 orphan cache - broken, notes.txt and the
  // subdirectory's nested.yaml all excluded
  iEqual(7: SCCOLL_count(coll): 'definitions found');

  nEqual(false: SCCOLL_find(coll: 'nested': def):
         'subdirectory NOT walked');
  nEqual(true: SCCOLL_find(coll: 'cache': def):
         '.yml accepted as well as .yaml');
  nEqual(false: SCCOLL_find(coll: 'notes': def):
         'non-YAML file ignored');

end-proc;

//==============================================================================
// A later directory's definition replaces an earlier one of the same name
//
// Upstream loads global, system, oss_common, the user's directory and then
// the custom one, merging each with putAll, so the LAST one loaded wins.
// A user's copy of a service overriding the global copy is the entire point
// of having a user directory, and getting this backwards is invisible until
// two directories happen to define the same name.
//==============================================================================

dcl-proc test_later_directory_overrides export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'first directory loaded');
  assert(SCCOLL_load_dir(coll: g_sub): 'second directory loaded');

  nEqual(true: SCCOLL_find(coll: 'db': def): 'db found');
  aEqualV('Overriding DB': def.friendly: 'later definition wins');

end-proc;

//==============================================================================
// A definition that fails to load is recorded, not fatal
//
// One malformed file must not stop the rest of the system being managed.
//==============================================================================

dcl-proc test_broken_definition_recorded export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load still succeeds');

  iEqual(1: coll.bad_count: 'one bad definition');
  aEqualV('broken': coll.bad_name(1): 'named');
  assert((%len(coll.bad_err(1)) > 0): 'reason recorded');

end-proc;

//==============================================================================
// Lookup is by short name, case-insensitively
//==============================================================================

dcl-proc test_find_by_name export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');

  nEqual(true: SCCOLL_find(coll: 'api': def): 'found');
  aEqual('/usr/bin/api': def.start_cmd: 'right definition');
  nEqual(true: SCCOLL_find(coll: 'API': def): 'case-insensitive');
  nEqual(false: SCCOLL_find(coll: 'nosuchthing': def): 'absent');

end-proc;

//==============================================================================
// Groups are the distinct set across the collection, plus the built-in all
//==============================================================================

dcl-proc test_groups export;

  dcl-ds coll   likeds(SCCOLL_t);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s i     like(INTEGER_t);
  dcl-s found like(BOOLEAN_t);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');
  SCCOLL_groups(coll: groups);

  // data, web, autostart - web is declared twice and listed once. Built-in
  // groups are not injected here; that is the caller's decision.
  iEqual(3: groups.count: 'distinct groups declared');

  for i = 1 to groups.count;
    if groups.name(i) = 'autostart';
      found = true;
    endif;
  endfor;
  nEqual(true: found: 'autostart present');

end-proc;

//==============================================================================
// Dependencies come out before the service that needs them
//==============================================================================

dcl-proc test_start_order export;

  dcl-ds coll  likeds(SCCOLL_t);
  dcl-ds order likeds(SCCOLL_ORDER_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');
  assert(SCCOLL_start_order(coll: 'web': order): 'resolved');

  iEqual(3: order.count: 'three services');
  aEqualV('db': order.name(1): 'deepest dependency first');
  aEqualV('api': order.name(2): 'then its dependant');
  aEqualV('web': order.name(3): 'the requested service last');

end-proc;

dcl-proc test_start_order_no_dependencies export;

  dcl-ds coll  likeds(SCCOLL_t);
  dcl-ds order likeds(SCCOLL_ORDER_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');
  assert(SCCOLL_start_order(coll: 'db': order): 'resolved');

  iEqual(1: order.count: 'just itself');
  aEqualV('db': order.name(1): 'itself');

end-proc;

//==============================================================================
// A cycle is named, not fallen into
//
// Upstream detects this too - validateNoCircularDependencies, run only for
// operations that change state - and names every hop:
//
//   Circular dependency detected in service definitions!!
//       cyc1 (Cycle 1) depends on ----> cyc2 (Cycle 2)
//       cyc2 (Cycle 2) depends on ----> cyc1 (Cycle 1)
//
// on stderr, exiting 253. RMSC names one service, on stdout as well as
// stderr, exiting 255. Both refuse before launching anything, which is the
// part that matters here; the wording is an open difference recorded in
// docs/parity.md.
//==============================================================================

dcl-proc test_dependency_cycle_detected export;

  dcl-ds coll  likeds(SCCOLL_t);
  dcl-ds order likeds(SCCOLL_ORDER_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');

  nEqual(false: SCCOLL_start_order(coll: 'cyc1': order): 'refused');
  assert((%scan('cycle': order.err) > 0): 'error says cycle');
  assert((%scan('cyc': order.err) > 0): 'error names a service in it');

end-proc;

//==============================================================================
// A dependency on a service that does not exist is reported
//==============================================================================

dcl-proc test_missing_dependency export;

  dcl-ds coll  likeds(SCCOLL_t);
  dcl-ds order likeds(SCCOLL_ORDER_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_dir): 'load');

  nEqual(false: SCCOLL_start_order(coll: 'orphan': order): 'refused');
  assert((%scan('nosuchservice': order.err) > 0): 'error names the missing one');

end-proc;

//==============================================================================
// The search path resolves on this system
//
// Deliberately does not assert which services exist: that is specific to the
// machine the suite happens to run on.
//==============================================================================

dcl-proc test_search_path export;

  dcl-ds dirs likeds(SCDIRS_t) inz(*likeds);
  dcl-s  home like(STMF_t);

  home = SCDIRS_home_dir();
  assert((%len(%trim(home)) > 0): 'home directory resolved from USER_INFO');

  // Zero is legitimate on a system with nothing installed, so only the shape
  // of the result is asserted
  assert((SCDIRS_search_path(dirs) >= 0): 'search path resolves');
  iEqual(dirs.count: SCDIRS_search_path(dirs): 'count matches the list');

end-proc;

//==============================================================================
// Regression: varying-length array elements survive a round trip, and the
// comparison helper reads them correctly.
//
// This started as a diagnostic. Two failures had lost exactly one character
// from element 2 of such an array, and it proved the data was fine and
// iRPGUnit's aEqual was misreading it - see aEqualV.
//==============================================================================

dcl-proc test_varchar_array_elements export;

  dcl-ds local likeds(SCCOLL_ORDER_t) inz(*likeds);

  local.count = 3;
  local.name(1) = 'db';
  local.name(2) = 'api';
  local.name(3) = 'web';

  // Plain RPG comparison - no operational descriptors involved
  assert((local.name(1) = 'db'):  'element 1 via assert');
  assert((local.name(2) = 'api'): 'element 2 via assert');
  assert((local.name(3) = 'web'): 'element 3 via assert');

  // Same data through aEqual, which is declared opdesc with *varsize
  aEqualV('db': local.name(1): 'element 1 via aEqual');
  aEqualV('api': local.name(2): 'element 2 via aEqual');
  aEqualV('web': local.name(3): 'element 3 via aEqual');

end-proc;

//==============================================================================
// Ordering fixture set-up
//
// Separate from g_dir on purpose: adding these six definitions to the shared
// directory would change the count test_discovery asserts, and under
// ORDER(*API) nothing guarantees which test sees which state.
//
// THE WRITE ORDER BELOW IS DELIBERATE AND MUST NOT BE TIDIED. Directory read
// order follows creation order, so writing these in the order the assertions
// expect makes readdir alone produce the expected answer and the tests pass
// against code that does no sorting whatsoever. That is not a hypothetical:
// it is what the first version of this file did. See the header for the four
// sequences the write order is chosen to differ from.
//==============================================================================

dcl-proc ord_setup;

  dcl-s y like(STRING_t);

  g_ord  = '/tmp/rmsc-sccoll-order-' + %trim(psds.current_user);
  g_ord2 = %trim(g_ord) + '/dir2';

  IFS_crtdir(g_ord);
  IFS_crtdir(g_ord2);

  // Short names differ at one character only. Code point orders them
  // 9one, _two, athree, zulu; EBCDIC orders them _two, athree, zulu, 9one.
  // They are written athree, zulu, 9one, _two - neither of those, nor the
  // reverse of either.

  // 1st written, 3rd expected
  y = 'name: Ordering alpha' + LF;
  y += 'start_cmd: /usr/bin/rmscord-alpha' + LF;
  y += 'check_alive: 8103' + LF;
  y += 'groups:' + LF;
  y += '- ordgrp_9x' + LF;
  write_file(%trim(g_ord) + '/rmscord_athree.yaml': y);

  // 2nd written, 4th expected. Short name sorts LAST, friendly name sorts
  // FIRST - under either collation. Mirrors the live sc 1.7.1 check where
  // rmscgate_zulu with friendly 'Aardvark friendly' still came last.
  y = 'name: Aardvark ordering' + LF;
  y += 'start_cmd: /usr/bin/rmscord-zulu' + LF;
  y += 'check_alive: 8104' + LF;
  y += 'groups:' + LF;
  y += '- ordgrp_ax' + LF;
  write_file(%trim(g_ord) + '/rmscord_zulu.yaml': y);

  // 3rd written, 1st expected. ordgrp_ax repeated from rmscord_zulu, so the
  // distinct group set is three, not four.
  y = 'name: Ordering nine' + LF;
  y += 'start_cmd: /usr/bin/rmscord-nine' + LF;
  y += 'check_alive: 8101' + LF;
  y += 'groups:' + LF;
  y += '- ordgrp_ax' + LF;
  write_file(%trim(g_ord) + '/rmscord_9one.yaml': y);

  // 4th written, 2nd expected
  y = 'name: Ordering under' + LF;
  y += 'start_cmd: /usr/bin/rmscord-under' + LF;
  y += 'check_alive: 8102' + LF;
  y += 'groups:' + LF;
  y += '- ordgrp__x' + LF;
  write_file(%trim(g_ord) + '/rmscord__two.yaml': y);

  // Second directory, written in the reverse of its expected order for the
  // same reason. Same short name as g_ord/rmscord_athree.yaml: the later
  // directory wins - pinned already by test_later_directory_overrides - and
  // the replacement must keep the key's sorted position rather than being
  // appended.
  y = 'name: Ordering replaced' + LF;
  y += 'start_cmd: /usr/bin/rmscord-replaced' + LF;
  y += 'check_alive: 8106' + LF;
  write_file(%trim(g_ord2) + '/rmscord_athree.yaml': y);

  // Written LAST of all six, loaded SECOND, expected FIRST. Sorts before
  // everything under both collations ('0' = 0x30 / 0xF0 against
  // '9' = 0x39 / 0xF9), so a merged sort puts it at rrn 1 while
  // sort-per-directory-then-append puts it fifth and no sorting at all puts
  // it last. That is the whole discrimination for the multi-directory case.
  y = 'name: Ordering zero' + LF;
  y += 'start_cmd: /usr/bin/rmscord-zero' + LF;
  y += 'check_alive: 8105' + LF;
  write_file(%trim(g_ord2) + '/rmscord_0zero.yaml': y);

end-proc;


//==============================================================================
// Ordering fixture tear-down
//
// Modelled on remove_tree: the subdirectory has to be emptied and removed
// before its parent can go. Asserts the removal so a suite that silently
// leaves fixtures behind is a failing suite, not a quiet one - a stale
// rmscord_* file would be counted by the next run, and worse, a leftover from
// an earlier run lands in the directory in a DIFFERENT creation order, which
// is exactly the variable these fixtures control.
//==============================================================================

dcl-proc ord_teardown;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_ord2);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_ord2) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_ord2);
  endif;

  dir = IFS_opendir(g_ord);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_ord) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_ord);
  endif;

  assert((not IFS_isa_directory(g_ord)):
         'Ordering fixture tree ' + %trim(g_ord) + ' not removed');

end-proc;


//==============================================================================
// cp_before - is a_val before b_val in CODE-POINT order?
//
// Needed only by test_search_path_is_ordered, which cannot use literal
// expected values because the definitions on the search path belong to the
// machine. Everywhere else the expectation is a literal and the comparison is
// equality, which no collation can disagree about.
//
// A plain RPG '<' on the job CCSID is EBCDIC and is exactly the wrong answer
// here. Assigning to a ccsid(*utf8) field converts, and a comparison between
// two fields of that CCSID is a byte comparison - which for these names is
// code-point order. test_codepoint_helper proves that before anything relies
// on it.
//==============================================================================

dcl-proc cp_before;
  dcl-pi *n like(BOOLEAN_t);
    a_val varchar(512) const;
    b_val varchar(512) const;
  end-pi;

  dcl-s a_utf varchar(512) ccsid(*utf8);
  dcl-s b_utf varchar(512) ccsid(*utf8);

  a_utf = %trimr(a_val);
  b_utf = %trimr(b_val);

  return (a_utf < b_utf);

end-proc;


//==============================================================================
// The comparison helper itself is right
//
// An instrument check, not a test of RMSC, and it passes today as it should.
// If cp_before is not code-point ordering, test_search_path_is_ordered fails
// and points the finger at SCCOLL for something SCCOLL did not do. This
// asserts the instrument against the three pairs measured on the box, and
// asserts the EBCDIC answer is the OPPOSITE for two of them - without that
// second half the helper could be a plain job-CCSID compare and still pass.
//==============================================================================

dcl-proc test_codepoint_helper export;

  dcl-s ebc_ax varchar(32);
  dcl-s ebc_9x varchar(32);

  // Measured: utf8 9x before ax, _x before ax, 9x before _x
  nEqual(true:  cp_before('rmscgate_9x': 'rmscgate_ax'): '9x before ax');
  nEqual(true:  cp_before('rmscgate__x': 'rmscgate_ax'): '_x before ax');
  nEqual(true:  cp_before('rmscgate_9x': 'rmscgate__x'): '9x before _x');

  nEqual(false: cp_before('rmscgate_ax': 'rmscgate_9x'): 'and not the reverse');
  nEqual(false: cp_before('rmscgate_ax': 'rmscgate__x'): 'nor that reverse');

  // Measured: the job CCSID reverses the first of those. Through variables,
  // so the compiler cannot fold it away and the comparison really is a
  // run-time one on the job CCSID. If this ever fails, the job is not running
  // EBCDIC and the fixture names above no longer separate the two collations
  // - which would make every ordering test in this file vacuous.
  ebc_ax = 'rmscgate_ax';
  ebc_9x = 'rmscgate_9x';
  assert((ebc_ax < ebc_9x):
         'job CCSID is EBCDIC: ax sorts before 9x, so the fixture names ' +
         'above really do separate the two collations');

end-proc;


//==============================================================================
// Definitions come back in code-point order of the SHORT NAME
//
// The core case. Upstream holds definitions in a TreeMap keyed on the short
// name, so `sc list` and `sc check` print them sorted; RMSC returned them in
// directory-read order.
//
// Every name below differs from the others at exactly one character, chosen
// so that code point and EBCDIC disagree: code point gives 9one, _two,
// athree, zulu, while a native RPG comparison gives _two, athree, zulu, 9one.
// A fixture of alpha/middle/zebra would pass under either and prove nothing.
//
// They are also WRITTEN in a third order - athree, zulu, 9one, _two - so no
// sorting at all gives a fourth wrong answer rather than the right one by
// accident. See ord_setup.
//
// INFERRED: that SCCOLL_get walks the collection in the collection's order
// for rrn 1..count. The brief states the range; the ordering of the walk is
// the thing under test.
//==============================================================================

dcl-proc test_order_by_short_name export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_ord): 'ordering fixture loaded');

  iEqual(4: SCCOLL_count(coll): 'four definitions');

  assert(SCCOLL_get(coll: 1: def): 'rrn 1 read');
  aEqualV('rmscord_9one': def.short_name:
          'rrn 1 - digit first, code point 0x39 (written 3rd)');

  assert(SCCOLL_get(coll: 2: def): 'rrn 2 read');
  aEqualV('rmscord__two': def.short_name:
          'rrn 2 - underscore next, code point 0x5F, EBCDIC would put it ' +
          'first (written 4th)');

  assert(SCCOLL_get(coll: 3: def): 'rrn 3 read');
  aEqualV('rmscord_athree': def.short_name:
          'rrn 3 - letter after underscore, code point 0x61 (written 1st)');

  assert(SCCOLL_get(coll: 4: def): 'rrn 4 read');
  aEqualV('rmscord_zulu': def.short_name:
          'rrn 4 - last (written 2nd)');

end-proc;


//==============================================================================
// The sort key is the short name, not the friendly name
//
// Measured against sc 1.7.1: a definition rmscgate_zulu whose friendly name
// was 'Aardvark friendly' still sorted LAST. rmscord_zulu reproduces that.
//
// 'Aardvark ordering' sorts before 'Ordering alpha/nine/under' under both
// collations - 'A' is 0x41 in ASCII and 0xC1 in EBCDIC, 'O' is 0x4F and 0xD6
// - so an implementation keyed on the friendly name puts rmscord_zulu at
// rrn 1 whichever way it compares. Asserting it is at rrn 4, and that rrn 1
// is not it, catches that with no collation caveat at all.
//
// rmscord_zulu is written SECOND of the four, so neither its expected
// position nor rrn 1's can come from the read order.
//==============================================================================

dcl-proc test_order_key_is_short_name_not_friendly export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_ord): 'ordering fixture loaded');

  assert(SCCOLL_get(coll: 4: def): 'rrn 4 read');
  aEqualV('rmscord_zulu': def.short_name:
          'the short name that sorts last is last');
  aEqualV('Aardvark ordering': def.friendly:
          'and its friendly name is the one that would have sorted first - ' +
          'so the fixture really does discriminate');

  assert(SCCOLL_get(coll: 1: def): 'rrn 1 read');
  aEqualV('rmscord_9one': def.short_name:
          'rrn 1 is not the Aardvark definition, so friendly is not the key');

end-proc;


//==============================================================================
// Sorting applies to the MERGED collection, not to each directory as read
//
// SCCOLL_load_dir is called once per directory on the real search path -
// global, system, oss_common, the user's, then the custom one - and a later
// definition replaces an earlier one of the same name
// (test_later_directory_overrides pins that).
//
// This is the case that separates 'sorted the collection' from 'sorted each
// directory as it was read':
//
//   rmscord_0zero is written LAST of all six, to the SECOND directory, and
//   must come back at rrn 1. Sort-per-directory-then-append leaves it at
//   rrn 5; no sorting at all leaves it at rrn 5 too.
//
//   rmscord_athree is REPLACED by the second directory's copy and must stay
//   at rrn 4 with the new friendly name. An implementation that removes and
//   re-adds on replace, or that appends the replacement, moves it to the end.
//
// INFERRED: both of these follow from upstream keeping one TreeMap and
// merging each directory into it with putAll, and from TreeMap.put replacing
// a value without moving its key. Neither was separately measured live.
//==============================================================================

dcl-proc test_order_across_directories export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_ord):  'first directory loaded');
  assert(SCCOLL_load_dir(coll: g_ord2): 'second directory loaded');

  // four, plus rmscord_0zero, less nothing - rmscord_athree is replaced
  iEqual(5: SCCOLL_count(coll): 'five definitions after the merge');

  assert(SCCOLL_get(coll: 1: def): 'rrn 1 read');
  aEqualV('rmscord_0zero': def.short_name:
          'written last, loaded second, sorts first - merged, not appended');

  assert(SCCOLL_get(coll: 2: def): 'rrn 2 read');
  aEqualV('rmscord_9one': def.short_name: 'rrn 2');

  assert(SCCOLL_get(coll: 3: def): 'rrn 3 read');
  aEqualV('rmscord__two': def.short_name: 'rrn 3');

  assert(SCCOLL_get(coll: 4: def): 'rrn 4 read');
  aEqualV('rmscord_athree': def.short_name:
          'the replaced definition holds its sorted position');
  aEqualV('Ordering replaced': def.friendly:
          'and it is the later directory''s copy, not the first''s');

  assert(SCCOLL_get(coll: 5: def): 'rrn 5 read');
  aEqualV('rmscord_zulu': def.short_name: 'rrn 5');

end-proc;


//==============================================================================
// Lookup still resolves every name after the collection has been reordered
//
// A guard, not evidence of the defect - it passes today and should. A sort
// moves rows, and if SCCOLL_find is backed by anything that remembers where a
// row was - a position cached at load time, an index built before the sort -
// it breaks silently, and `scr check <name>` starts answering about the wrong
// service.
//
// INFERRED: the brief does not say how find is implemented. This is a guard,
// not a specification.
//==============================================================================

dcl-proc test_find_after_sort export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_ord):  'first directory loaded');
  assert(SCCOLL_load_dir(coll: g_ord2): 'second directory loaded');

  nEqual(true: SCCOLL_find(coll: 'rmscord_0zero': def): 'zero found');
  aEqualV('Ordering zero': def.friendly: 'and it is the right one');

  nEqual(true: SCCOLL_find(coll: 'rmscord_9one': def): 'nine found');
  aEqualV('Ordering nine': def.friendly: 'and it is the right one');

  nEqual(true: SCCOLL_find(coll: 'rmscord__two': def): 'under found');
  aEqualV('Ordering under': def.friendly: 'and it is the right one');

  nEqual(true: SCCOLL_find(coll: 'rmscord_athree': def): 'alpha found');
  aEqualV('Ordering replaced': def.friendly: 'and it is the later copy');

  nEqual(true: SCCOLL_find(coll: 'rmscord_zulu': def): 'zulu found');
  aEqualV('Aardvark ordering': def.friendly: 'and it is the right one');

  nEqual(false: SCCOLL_find(coll: 'rmscord_nosuchthing': def):
         'and a name that is not there is still absent');

end-proc;


//==============================================================================
// Group names come back in code-point order too
//
// A SECOND instance of the same defect, and now measured rather than inferred.
// RMSC does sort group names, but with a native RPG comparison, which is
// EBCDIC. Nothing had caught it because every group name on this system is
// letters only, and letters collate the same way under both. Three groups
// declared in the order ax, 9x, __x:
//
//     sc :  ordgrp_9x  ordgrp__x  ordgrp_ax     (code point)
//     scr:  ordgrp__x  ordgrp_ax  ordgrp_9x     (EBCDIC)
//
// The three fixture group names differ at one character and reverse
// completely between the collations. They are assigned to services so that
// the order in which they are first ENCOUNTERED matches neither the expected
// order nor the EBCDIC one, whichever way the collection is walked:
//
//     expected (code point)          ordgrp_9x   ordgrp__x   ordgrp_ax
//     EBCDIC                         ordgrp__x   ordgrp_ax   ordgrp_9x
//     first seen, collection in
//       read order                   ordgrp_9x   ordgrp_ax   ordgrp__x
//     first seen, collection in
//       sorted order                 ordgrp_ax   ordgrp__x   ordgrp_9x
//
// Four distinct sequences, so this test cannot pass by accident and a failure
// says which mechanism produced the answer.
//
// groups.name(n) is a varying-length ARRAY ELEMENT, which is exactly the
// shape iRPGUnit's aEqual misreads (element N read with element N-1's
// length - see docs/testing-notes.md). aEqualV throughout.
//==============================================================================

dcl-proc test_group_order_is_codepoint export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_ord): 'ordering fixture loaded');

  SCCOLL_groups(coll: groups);

  // ordgrp_ax is declared by two services and listed once
  iEqual(3: groups.count: 'three distinct groups');

  aEqualV('ordgrp_9x': groups.name(1):
          'group 1 - digit first, code point 0x39 (EBCDIC would put it last)');
  aEqualV('ordgrp__x': groups.name(2):
          'group 2 - underscore, code point 0x5F');
  aEqualV('ordgrp_ax': groups.name(3):
          'group 3 - letter, code point 0x61');

end-proc;


//==============================================================================
// The real search path comes back ordered as well
//
// A REGRESSION GUARD, NOT EVIDENCE. This one passes today, against code that
// does no sorting, and it will keep passing for as long as the definitions on
// this box happen to come back from readdir already sorted - which is
// precisely why the defect survived to be found by reading upstream's source
// rather than by running anything.
//
// It cannot be made discriminating from inside the suite: the names belong to
// the machine, and the suite must not rename or reorder real service
// definitions to make a point. The fixture tests above are the evidence. What
// this adds is that the invariant is asserted over the path the CLI actually
// takes - SCCOLL_load across every directory in the search path, which is
// what `list` and `check` print one row per service from - so a future change
// that sorts the fixture path but not the real one is caught, and so is a
// machine whose definitions stop arriving in sorted order.
//
// Strictly after, not merely not-before: two rows with the same short name
// would mean a replacement was appended rather than merged, which is
// test_order_across_directories' case reaching the real path.
//
// On a system with no definitions installed this proves nothing at all, the
// same caveat test_search_path already carries.
//==============================================================================

dcl-proc test_search_path_is_ordered export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);
  dcl-s  i    like(INTEGER_t);
  dcl-s  prev varchar(512);
  dcl-s  cur  varchar(512);

  SCCOLL_init(coll);
  assert(SCCOLL_load(coll): 'search path loaded');

  for i = 1 to SCCOLL_count(coll);
    assert(SCCOLL_get(coll: i: def): 'rrn ' + %char(i) + ' read');
    cur = %trimr(def.short_name);

    if i > 1;
      assert(cp_before(prev: cur):
             'search path row ' + %char(i) + ': "' + %trim(prev) +
             '" must sort strictly before "' + %trim(cur) +
             '" in code-point order');
    endif;

    prev = cur;
  endfor;

end-proc;
