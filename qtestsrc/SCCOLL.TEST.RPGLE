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

dcl-s g_fil like(STMF_t);

dcl-pr fil_setup end-pr;

dcl-pr fil_teardown end-pr;

dcl-pr fil_has like(BOOLEAN_t);
  grp  likeds(SCCOLL_GROUPS_t) const;
  want varchar(64) const;
end-pr;

dcl-pr fil_load;
  coll likeds(SCCOLL_t);
end-pr;

dcl-s g_nam like(STMF_t);

dcl-pr nam_setup end-pr;

dcl-pr nam_teardown end-pr;

dcl-s g_blk like(STMF_t);

dcl-pr blk_setup end-pr;

dcl-pr blk_teardown end-pr;

dcl-pr blk_entry_len like(INTEGER_t);
  dir_path like(STMF_t) const;
  prefix   varchar(64) const;
end-pr;

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
  fil_setup();
  nam_setup();
  blk_setup();

end-proc;

dcl-proc tearDownSuite export;

  remove_tree();
  ord_teardown();
  fil_teardown();
  nam_teardown();
  blk_teardown();

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

//==============================================================================
// Filter fixture set-up
//
// Six definitions, five distinct declared groups, in a directory of this
// fixture set's own.
//
//   rmscfil_a   filgrp_zx, filgrp_mx
//   rmscfil_b   filgrp_ax
//   rmscfil_c   filgrp_9x
//   rmscfil_d   filgrp__x
//   rmscfil_e   filgrp_mx, filgrp_ax
//   rmscfil_f   (no groups at all)
//
// Two things are being controlled at once.
//
// THE GROUP NAMES DISCRIMINATE THE TWO COLLATIONS. They differ at one
// character, chosen from the four the measurement on the box used:
// code point puts them 9x _x ax mx zx (0x39 0x5F 0x61 0x6D 0x7A), the job's
// EBCDIC collation puts them _x ax mx zx 9x (0x6D 0x81 0x94 0xA9 0xF9). A
// fixture of alpha/middle/zebra would agree under both and prove nothing -
// which is exactly why the group-sort defect survived so long, every group
// name on this system being letters only.
//
// THE MEMBERSHIP IS ARRANGED SO THE FILTER CASES SEPARATE. Each filtered
// case below leaves behind a group that only an EXCLUDED service declared
// (which must vanish) and a group an excluded service SHARED with a
// survivor (which must remain). Without the second, filtering services and
// filtering the answer's group names give the same result and the test
// cannot tell the two implementations apart.
//
// THE WRITE ORDER IS DELIBERATE AND MUST NOT BE TIDIED, for the same reason
// ord_setup's is: directory read order follows creation order. Written
// e c a f d b, so neither the read order nor its reverse is any expected
// answer. Groups are also listed WITHIN each definition in an order that is
// not the expected one - rmscfil_a declares zx before mx - so the sequence
// in which group names are first encountered is:
//
//   unfiltered            zx mx ax 9x _x      expected  9x _x ax mx zx
//   ignoring filgrp_mx    ax 9x _x            expected  9x _x ax
//   ignoring zx and _x    ax 9x mx            expected  9x ax mx
//
// and in each case the encounter order, its reverse, the EBCDIC order and
// the expected order are four different sequences. No test below can pass by
// accident, and a failure says which mechanism produced the answer.
//==============================================================================

dcl-proc fil_setup;

  dcl-s y like(STRING_t);

  g_fil = '/tmp/rmsc-sccoll-filter-' + %trim(psds.current_user);

  IFS_crtdir(g_fil);

  // 1st written. Declares filgrp_mx and filgrp_ax - it is excluded by the
  // filgrp_mx filter, and filgrp_ax must survive it because rmscfil_b
  // declares that too. This is the shared-group case.
  y = 'name: Filter echo' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-e' + LF;
  y += 'check_alive: 8115' + LF;
  y += 'groups:' + LF;
  y += '- filgrp_mx' + LF;
  y += '- filgrp_ax' + LF;
  write_file(%trim(g_fil) + '/rmscfil_e.yaml': y);

  // 2nd written. The only declarer of filgrp_9x.
  y = 'name: Filter charlie' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-c' + LF;
  y += 'check_alive: 8113' + LF;
  y += 'groups:' + LF;
  y += '- filgrp_9x' + LF;
  write_file(%trim(g_fil) + '/rmscfil_c.yaml': y);

  // 3rd written. The only declarer of filgrp_zx, and a second declarer of
  // filgrp_mx. Excluding it by filgrp_zx must take filgrp_zx away while
  // leaving filgrp_mx, which rmscfil_e also declares; excluding it by
  // filgrp_mx must take filgrp_zx away too, because nothing else declares
  // that. filgrp_zx is listed FIRST so the encounter order is not the
  // expected one.
  y = 'name: Filter alpha' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-a' + LF;
  y += 'check_alive: 8111' + LF;
  y += 'groups:' + LF;
  y += '- filgrp_zx' + LF;
  y += '- filgrp_mx' + LF;
  write_file(%trim(g_fil) + '/rmscfil_a.yaml': y);

  // 4th written. No groups key at all. It contributes no group name, and
  // must not contribute a blank one either.
  y = 'name: Filter foxtrot' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-f' + LF;
  y += 'check_alive: 8116' + LF;
  write_file(%trim(g_fil) + '/rmscfil_f.yaml': y);

  // 5th written. The only declarer of filgrp__x.
  y = 'name: Filter delta' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-d' + LF;
  y += 'check_alive: 8114' + LF;
  y += 'groups:' + LF;
  y += '- filgrp__x' + LF;
  write_file(%trim(g_fil) + '/rmscfil_d.yaml': y);

  // 6th written. Keeps filgrp_ax alive across every filter that excludes
  // rmscfil_e.
  y = 'name: Filter bravo' + LF;
  y += 'start_cmd: /usr/bin/rmscfil-b' + LF;
  y += 'check_alive: 8112' + LF;
  y += 'groups:' + LF;
  y += '- filgrp_ax' + LF;
  write_file(%trim(g_fil) + '/rmscfil_b.yaml': y);

end-proc;


//==============================================================================
// Filter fixture tear-down
//
// Flat, so no subdirectory to empty first. Asserts the removal for the
// reason ord_teardown does: a leftover rmscfil_* file lands in the directory
// in a DIFFERENT creation order on the next run, and creation order is one
// of the variables these fixtures exist to control.
//==============================================================================

dcl-proc fil_teardown;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_fil);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_fil) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_fil);
  endif;

  assert((not IFS_isa_directory(g_fil)):
         'Filter fixture tree ' + %trim(g_fil) + ' not removed');

end-proc;


//==============================================================================
// fil_load - load the filter fixture into a fresh collection
//
// Every test below starts the same way. Asserting the load here means a
// missing fixture FAILS the test that needed it rather than quietly giving
// it an empty collection to agree with.
//==============================================================================

dcl-proc fil_load;
  dcl-pi *n;
    coll likeds(SCCOLL_t);
  end-pi;

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_fil): 'filter fixture loaded');
  iEqual(6: SCCOLL_count(coll): 'six definitions in the filter fixture');

end-proc;


//==============================================================================
// fil_has - is a group name anywhere in the result?
//
// Position-independent, for asserting ABSENCE. A group that must not be
// there has no position to assert about, and 'name(4) is not filgrp_zx' is
// satisfied by filgrp_zx sitting at name(2).
//
// Compares with plain RPG for the reason aEqualV exists: grp.name(n) is a
// varying-length array element, and anything reading it through an
// operational descriptor reads element N with element N-1's length.
//==============================================================================

dcl-proc fil_has;
  dcl-pi *n like(BOOLEAN_t);
    grp  likeds(SCCOLL_GROUPS_t) const;
    want varchar(64) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to grp.count;
    if %trimr(grp.name(i)) = %trimr(want);
      return true;
    endif;
  endfor;

  return false;

end-proc;


//==============================================================================
// With no filter, the answer is every distinct group declared, sorted by
// code point
//
// The baseline the filtered cases are measured against, and the assertion
// that the new optional parameter has not disturbed the two-argument form.
// It is the existing contract restated on a fixture that can actually see a
// collation mistake, which test_groups' data/web/autostart cannot.
//
// Also pins three things the filter work could break in passing:
//
//   - rmscfil_f declares no groups at all and must contribute nothing, not
//     a blank entry. A loop that appends before testing for a name gives
//     six groups, one of them empty, and the count assertion alone would
//     catch that only by luck of the array bound.
//   - the implicit group 'all', which every definition belongs to and which
//     the filter matches on, is NOT part of the answer. test_groups already
//     says built-in groups are the caller's decision; teaching the filter
//     about 'all' is the change most likely to leak it into the result.
//   - the returned count is the count that was filled.
//==============================================================================

dcl-proc test_groups_filter_omitted export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n like(INTEGER_t);
  dcl-s  i like(INTEGER_t);

  fil_load(coll);

  n = SCCOLL_groups(coll: groups);

  iEqual(5: groups.count: 'five distinct groups declared');
  iEqual(groups.count: n: 'the returned count is the count filled');

  aEqualV('filgrp_9x': groups.name(1):
          'group 1 - digit, code point 0x39 (EBCDIC would put it LAST)');
  aEqualV('filgrp__x': groups.name(2):
          'group 2 - underscore, code point 0x5F');
  aEqualV('filgrp_ax': groups.name(3):
          'group 3 - letter a, code point 0x61 (declared twice, listed once)');
  aEqualV('filgrp_mx': groups.name(4):
          'group 4 - letter m, code point 0x6D (declared twice, listed once)');
  aEqualV('filgrp_zx': groups.name(5):
          'group 5 - letter z, code point 0x7A (encountered FIRST)');

  nEqual(false: fil_has(groups: 'all'):
         'the implicit group all is not part of the answer');

  for i = 1 to groups.count;
    assert((%len(%trimr(groups.name(i))) > 0):
           'group ' + %char(i) + ' has a name - the definition with no ' +
           'groups key contributed nothing, not a blank');
  endfor;

end-proc;


//==============================================================================
// A blank filter excludes nothing
//
// Same expectation as the omitted form, reached down the other path. The
// two are different code: %parms tells you the argument is THERE, and
// something separate has to decide it is empty. An implementation that
// checks only %parms treats a blank filter as a list of one nameless group
// and, depending on how it matches, either excludes nothing (right, by
// luck) or excludes every service whose group list is empty (wrong, and
// invisible until a definition has no groups - which rmscfil_f does).
//
// Both blanks and a zero-length value, because they are two different
// values, not one: if SCDEF_NAME_t is varying then *blanks sets the field
// to its full declared length of blanks while '' sets it to length zero, so
// a test for %len(ignore) = 0 passes one and fails the other, and a test
// that scans for a comma without trimming first sees a very long token.
// SCEXEC_list(coll: '') is already called this way by SCEXEC.TEST, so the
// zero-length form is one a caller really does pass.
//==============================================================================

dcl-proc test_groups_filter_blank export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  nofilt like(SCDEF_NAME_t);

  fil_load(coll);

  nofilt = *blanks;
  n = SCCOLL_groups(coll: groups: nofilt);

  iEqual(5: groups.count: 'a blank filter excludes nothing');
  iEqual(groups.count: n: 'the returned count is the count filled');

  aEqualV('filgrp_9x': groups.name(1): 'group 1 - and still sorted');
  aEqualV('filgrp__x': groups.name(2): 'group 2');
  aEqualV('filgrp_ax': groups.name(3): 'group 3');
  aEqualV('filgrp_mx': groups.name(4): 'group 4');
  aEqualV('filgrp_zx': groups.name(5): 'group 5');

  // The zero-length form of the same thing
  n = SCCOLL_groups(coll: groups: '');

  iEqual(5: groups.count: 'and neither does a zero-length one');
  iEqual(groups.count: n: 'the returned count is the count filled');
  aEqualV('filgrp_9x': groups.name(1): 'group 1');
  aEqualV('filgrp_zx': groups.name(5): 'group 5');

end-proc;


//==============================================================================
// The filter names SERVICES to leave out, not groups to leave out of the
// answer
//
// The heart of it. Ignoring filgrp_mx excludes rmscfil_a and rmscfil_e,
// and the groups of what is LEFT are then collected:
//
//   filgrp_mx  gone    - the filtered group itself
//   filgrp_zx  gone    - declared ONLY by rmscfil_a, which was excluded
//   filgrp_ax  PRESENT - rmscfil_e declared it and was excluded, but
//                        rmscfil_b declares it and survives
//   filgrp_9x  present - rmscfil_c, untouched
//   filgrp__x  present - rmscfil_d, untouched
//
// filgrp_zx is what separates the two readings. An implementation that
// takes the full group list and drops the names in the filter returns four
// groups including filgrp_zx, and passes every other assertion here.
// filgrp_ax is the other half: an implementation that drops a group as soon
// as any declarer is excluded loses it, and also passes everything else.
//
// The three survivors are also the three that reverse between the
// collations, so this is the filtered sort test as well - EBCDIC would
// answer _x ax 9x.
//==============================================================================

dcl-proc test_groups_filter_excludes_services export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'filgrp_mx';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(3: groups.count: 'three groups survive');
  iEqual(groups.count: n: 'the returned count is the count filled');

  aEqualV('filgrp_9x': groups.name(1):
          'group 1 - digit first, so filtering did not lose the code-point ' +
          'sort (EBCDIC would answer filgrp__x here)');
  aEqualV('filgrp__x': groups.name(2): 'group 2');
  aEqualV('filgrp_ax': groups.name(3):
          'group 3 - declared by the excluded rmscfil_e AND the surviving ' +
          'rmscfil_b, so it stays');

  nEqual(false: fil_has(groups: 'filgrp_zx'):
         'filgrp_zx was declared only by rmscfil_a, which the filter ' +
         'excluded - a filter on GROUP NAMES would have left it here');
  nEqual(false: fil_has(groups: 'filgrp_mx'):
         'the filtered group itself is gone');
  nEqual(true: fil_has(groups: 'filgrp_ax'):
         'the shared group is not gone');

end-proc;


//==============================================================================
// The filter is a comma-separated list
//
// Ignoring filgrp_zx and filgrp__x excludes rmscfil_a and rmscfil_d.
// rmscfil_a also declared filgrp_mx, which rmscfil_e keeps alive - so this
// is a second, independent instance of the shared-group case, reached
// through the other element of the list rather than the first.
//
//   filgrp_zx  gone    - rmscfil_a excluded, sole declarer
//   filgrp__x  gone    - rmscfil_d excluded, sole declarer
//   filgrp_mx  PRESENT - rmscfil_a excluded, rmscfil_e survives
//   filgrp_9x  present
//   filgrp_ax  present
//
// A split that keeps only the first token leaves filgrp__x here; one that
// keeps only the last leaves filgrp_zx. Neither is caught by the count
// alone if the other happens to remove something, so both are named.
//==============================================================================

dcl-proc test_groups_filter_multiple export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'filgrp_zx,filgrp__x';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(3: groups.count: 'three groups survive two filter values');
  iEqual(groups.count: n: 'the returned count is the count filled');

  aEqualV('filgrp_9x': groups.name(1):
          'group 1 - digit first, still code point (EBCDIC would answer ' +
          'filgrp_ax here)');
  aEqualV('filgrp_ax': groups.name(2): 'group 2');
  aEqualV('filgrp_mx': groups.name(3):
          'group 3 - rmscfil_a declared it and was excluded, rmscfil_e ' +
          'declares it and survives');

  nEqual(false: fil_has(groups: 'filgrp_zx'):
         'the first value in the list took its sole declarer out');
  nEqual(false: fil_has(groups: 'filgrp__x'):
         'and so did the last - a split that keeps one end fails here');

end-proc;


//==============================================================================
// Matching is case-insensitive
//
// Same fixture, same filter, typed in upper case: the answer must not
// change. The existing code lowercases the filter, so what this pins is
// that the comparison it feeds is against a group name treated the same
// way.
//
// The fixture group names are all lower case on purpose. Whether a group
// name declared in UPPER CASE in a YAML file is itself folded is a separate
// question this change does not touch, and asserting it here would be
// asserting something nobody has stated.
//==============================================================================

dcl-proc test_groups_filter_case_insensitive export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'FILGRP_MX';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(3: groups.count: 'upper case filters the same three out');
  iEqual(groups.count: n: 'the returned count is the count filled');

  aEqualV('filgrp_9x': groups.name(1): 'group 1');
  aEqualV('filgrp__x': groups.name(2): 'group 2');
  aEqualV('filgrp_ax': groups.name(3): 'group 3');

  nEqual(false: fil_has(groups: 'filgrp_zx'):
         'and it really did exclude the services, not just fail to match');

end-proc;


//==============================================================================
// A filter naming a group nothing declares excludes nothing
//
// Two shapes, because they fail differently. Alone, a name that matches
// nothing must be a no-op rather than an error or an empty answer. Beside a
// name that does match, it must not disturb the one that does - which is
// where a splitter that stops at the first unmatched token, or that
// compares the whole string rather than each value, gives itself away.
//==============================================================================

dcl-proc test_groups_filter_unknown_group export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'filgrp_nosuchgroup';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(5: groups.count: 'a group nothing declares excludes nothing');
  iEqual(groups.count: n: 'the returned count is the count filled');
  aEqualV('filgrp_9x': groups.name(1): 'and the answer is the unfiltered one');
  aEqualV('filgrp_zx': groups.name(5): 'right through to the last');

  // Beside one that does match
  ignore = 'filgrp_nosuchgroup,filgrp_mx';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(3: groups.count:
         'an unmatched value does not stop the next one matching');
  iEqual(groups.count: n: 'the returned count is the count filled');
  nEqual(false: fil_has(groups: 'filgrp_zx'):
         'rmscfil_a was still excluded');

end-proc;


//==============================================================================
// Every definition belongs to the implicit group all, so a filter of all
// excludes everything
//
// The answer is an empty result and a zero count, not the unfiltered list.
// An implementation that only ever compares the filter against the groups a
// definition DECLARES never matches 'all', because no definition declares
// it, and returns all five.
//
// Asserted in both cases as a zero count rather than by reading name(1),
// which after a clear holds blanks and would compare equal to a good many
// things.
//
// INFERRED: that 'all' is matched case-insensitively like any other value.
// The brief says the whole filter is lowercased and gives 'all' as a value
// in it; nothing makes 'all' special in that respect.
//==============================================================================

dcl-proc test_groups_filter_all export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'all';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(0: groups.count: 'ignoring all leaves no service, so no group');
  iEqual(0: n: 'and the returned count says so too');

  ignore = 'ALL';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(0: groups.count: 'in upper case as well');
  iEqual(0: n: 'and the returned count says so too');

  // Beside a value that matches only some services, all still takes the lot
  ignore = 'filgrp_mx,all';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(0: groups.count: 'and as one value of several');
  iEqual(0: n: 'and the returned count says so too');

end-proc;


//==============================================================================
// A filter value matches a whole group name, not part of one
//
// 'filgrp_a' is a prefix of 'filgrp_ax' and of nothing else. If the match
// is a %scan of the group name against the comma-separated string - the
// obvious way to write it, and the reason this is worth a test - then
// filtering on 'filgrp_a' silently excludes rmscfil_b and rmscfil_e.
//
// The reverse is asserted too: a filter value that CONTAINS a real group
// name must not match it either, which is the same defect with the scan the
// other way round.
//
// INFERRED. The brief says a service is excluded when it belongs to a group
// NAMED in the filter, which reads as the whole name; it does not say so in
// as many words. If upstream turns out to match on substrings this test is
// the one to change, and it should be changed deliberately.
//==============================================================================

dcl-proc test_groups_filter_matches_whole_name export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'filgrp_a';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(5: groups.count:
         'a prefix of a group name is not that group name');
  iEqual(groups.count: n: 'the returned count is the count filled');
  nEqual(true: fil_has(groups: 'filgrp_ax'):
         'filgrp_ax is untouched by a filter on filgrp_a');

  ignore = 'filgrp_axtra';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(5: groups.count:
         'nor does a longer value that contains a real group name match it');
  nEqual(true: fil_has(groups: 'filgrp_ax'): 'filgrp_ax still there');

end-proc;


//==============================================================================
// Asking for a filtered answer does not change the collection
//
// coll is passed by reference, not const, and the cheapest way to write
// this change is to drop the excluded definitions and then run the existing
// loop. That would leave the caller holding a collection with services
// missing from it - and SCEXEC_groups, the caller this parameter exists
// for, is one command among several sharing one loaded collection.
//
// A silent one, too: `scr groups --ignore-groups=x` would print correctly
// and the damage would show up in whatever the same job asked next.
//
// INFERRED: the brief does not say the collection is left alone. It says
// the command asks the model for what it needs, which a destructive filter
// would satisfy while being wrong.
//==============================================================================

dcl-proc test_groups_filter_leaves_collection_alone export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-ds def    likeds(SCDEF_t) inz(*likeds);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  ignore = 'filgrp_mx';
  SCCOLL_groups(coll: groups: ignore);

  iEqual(6: SCCOLL_count(coll):
         'all six definitions are still in the collection');
  nEqual(true: SCCOLL_find(coll: 'rmscfil_a': def):
         'the excluded rmscfil_a is still there');
  aEqualV('Filter alpha': def.friendly: 'and is still itself');
  nEqual(true: SCCOLL_find(coll: 'rmscfil_e': def):
         'and so is the excluded rmscfil_e');

  // The unfiltered answer, asked afterwards, is still the unfiltered answer
  SCCOLL_groups(coll: groups);
  iEqual(5: groups.count:
         'and the collection still answers with all five groups');

end-proc;


//==============================================================================
// The result structure is filled, not added to
//
// Both directions through the same structure, because they break
// differently. Wide-then-narrow leaves stale names above the new count, and
// a count that is not reset reports them; narrow-then-wide is the case
// where a count that is added to rather than assigned runs the array past
// its bound.
//
// The caller this parameter exists for does exactly this - SCEXEC_groups
// holds one result structure - and note that `clear` on a data structure
// resets it to blanks, not to the template's inz, so a clear-and-refill
// implementation is not automatically safe either.
//
// INFERRED: the brief does not say the structure is reset. It does say the
// count returned agrees with what was filled, which this is the awkward
// case of.
//==============================================================================

dcl-proc test_groups_filter_result_not_accumulated export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  fil_load(coll);

  // Wide, then narrow, through the SAME structure
  n = SCCOLL_groups(coll: groups);
  iEqual(5: n: 'five unfiltered');

  ignore = 'filgrp_mx';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(3: groups.count: 'three filtered - not eight, and not still five');
  iEqual(groups.count: n: 'the returned count is the count filled');
  aEqualV('filgrp_9x': groups.name(1): 'and the right three, in order');
  aEqualV('filgrp__x': groups.name(2): 'group 2');
  aEqualV('filgrp_ax': groups.name(3): 'group 3');
  nEqual(false: fil_has(groups: 'filgrp_zx'):
         'no leftover from the wider answer is counted');

  // Narrow, then wide, through the same structure again
  n = SCCOLL_groups(coll: groups);

  iEqual(5: groups.count: 'five again afterwards');
  iEqual(groups.count: n: 'the returned count is the count filled');
  aEqualV('filgrp_9x': groups.name(1): 'group 1');
  aEqualV('filgrp_zx': groups.name(5): 'through to group 5');

end-proc;


//==============================================================================
// An empty collection with a filter answers zero
//
// The degenerate case, and the one a loop written to run at least once gets
// wrong. Nothing is loaded, so nothing can be excluded and nothing can be
// collected; the filter must not turn that into a failure or into a stray
// entry. SCCOLL_init is called and load_dir is not, deliberately - see the
// note in docs/testing-notes.md about what an uninitialised likeds()
// structure contains.
//==============================================================================

dcl-proc test_groups_filter_empty_collection export;

  dcl-ds coll   likeds(SCCOLL_t) inz(*likeds);
  dcl-ds groups likeds(SCCOLL_GROUPS_t) inz(*likeds);
  dcl-s  n      like(INTEGER_t);
  dcl-s  ignore like(SCDEF_NAME_t);

  SCCOLL_init(coll);
  iEqual(0: SCCOLL_count(coll): 'nothing loaded');

  ignore = 'filgrp_mx';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(0: groups.count: 'no definitions, no groups');
  iEqual(0: n: 'and the returned count says so too');

  ignore = 'all';
  n = SCCOLL_groups(coll: groups: ignore);

  iEqual(0: n: 'ignoring all on an empty collection is still zero');

end-proc;


//==============================================================================
// fil_get - one definition out of the filter fixture
//
// Defined here rather than prototyped at the top of the suite, the way
// SCEXEC.TEST's uc_ helpers are: every caller is below it.
//
// It asserts the find, so a fixture that failed to load fails the test that
// needed it instead of handing it an empty definition to agree with.
//==============================================================================

dcl-proc fil_get;
  dcl-pi *n;
    name like(SCDEF_NAME_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);

  fil_load(coll);
  nEqual(true: SCCOLL_find(coll: name: def):
         'fixture definition ' + %trim(name) + ' found');

end-proc;


//==============================================================================
// A TRAILING COMMA IS AN EMPTY ELEMENT, AND AN EMPTY ELEMENT IS DISCARDED
//
// EXPECTED RED until the splitter behind SCCOLL_in_groups is fixed. And red
// as an ERROR, not a FAILURE: the list is walked comma to comma and the
// element after the last one is taken as a substring starting past the end of
// the value, which raises RNX0100 (substring out of range). iRPGUnit reports
// an unhandled exception as an ERROR for the test case, so a reader looking
// for five red FAILURES will not find them - and every assertion in a
// procedure after the call that abends is never reached, which is why the
// control assertions in each test below come FIRST and are not tidied into
// one test of their own.
//
// Upstream sc is Java and splits the list with String.split, which with the
// default limit discards trailing empty elements: "a,".split(",") is
// ["a"], "a,,".split(",") is ["a"], and ",".split(",") is empty. So
// 'filgrp_mx,' must behave EXACTLY as 'filgrp_mx' does, and a list of
// nothing but separators must behave exactly as a blank one does - which the
// specification already says matches nothing.
//
// Where the trailing comma comes from is worth saying, because it is not a
// contrived value: it is what a shell or a config file leaves behind when a
// list is built up a value at a time, and what a user types when they delete
// the last group from --ignore-groups=a,b and stop at the comma. A crash is
// the worst of the three possible answers.
//
// The fixture is fil_setup's, reused as-is:
//   rmscfil_a  filgrp_zx, filgrp_mx
//   rmscfil_b  filgrp_ax
//   rmscfil_f  no groups at all
//
// Commas in the MIDDLE of a list, blanks, case folding and the prefix
// collision between filgrp_a and filgrp_ax are all pinned already by the
// test_groups_filter_* tests above, which reach the same splitter through
// SCCOLL_groups. Nothing here repeats them; each test below pairs its
// trailing-comma call with the identical list WITHOUT the comma, so a
// failure separates 'the trailing comma broke it' from 'this list never
// matched in the first place'.
//==============================================================================

dcl-proc test_in_groups_trailing_comma_matches export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  grp like(SCDEF_NAME_t);

  fil_get('rmscfil_a': def);

  grp = 'filgrp_mx';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'control - rmscfil_a declares filgrp_mx');

  grp = 'filgrp_mx,';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'the trailing element is empty and is discarded, so this answers ' +
         'exactly as filgrp_mx does');

  grp = 'all,';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'and the built-in all is reached through the same split');

end-proc;


//==============================================================================
// A trailing comma on a list that matches NOTHING is still an answer
//
// The half that a crash hides most easily. False and RNX0100 look the same
// from a caller that only ever asks whether the answer was true, and the
// group filter is exactly such a caller.
//
// EXPECTED RED, as an ERROR - see the block comment above.
//==============================================================================

dcl-proc test_in_groups_trailing_comma_no_match export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  grp like(SCDEF_NAME_t);

  fil_get('rmscfil_b': def);

  grp = 'filgrp_mx';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'control - rmscfil_b declares filgrp_ax and nothing else');

  grp = 'filgrp_mx,';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'a list that does not match is an answer, not a crash');

  // A definition with no groups key at all is the other shape of no match,
  // and the one where an implementation that walks the DECLARED groups
  // rather than the filter never reaches the bad substring.
  fil_get('rmscfil_f': def);

  grp = 'filgrp_mx,';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'and a definition declaring no groups answers too');

end-proc;


//==============================================================================
// A trailing comma after several elements
//
// The first test's list has one element and the empty one; this has three and
// the empty one, so an implementation that special-cases a single value, or
// that only ever looks at the first or the last element, is separated from
// one that discards the empty element wherever it falls.
//
// Both directions, because the count of elements is not what decides the
// answer: the same three-element shape is asserted true when the match is the
// LAST real element, and false when none of the real elements matches.
//
// EXPECTED RED, as an ERROR - see the block comment above.
//==============================================================================

dcl-proc test_in_groups_trailing_comma_after_several export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  grp like(SCDEF_NAME_t);

  fil_get('rmscfil_a': def);

  grp = 'filgrp_9x,filgrp__x,filgrp_mx';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'control - the third of three is declared by rmscfil_a');

  grp = 'filgrp_9x,filgrp__x,filgrp_mx,';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'a fourth, empty element does not change that');

  grp = 'filgrp_9x,filgrp__x,';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'and where no real element matches, the empty one does not ' +
         'match either');

end-proc;


//==============================================================================
// A list of nothing but a separator is an empty list
//
// ',' is two empty elements, both trailing, so Java's split gives an array of
// length zero and the answer is the blank-list answer: matches nothing.
//
// The control is the zero-length list rather than *blanks. SCDEF_NAME_t is
// varying, so the two are different values - test_groups_filter_blank makes
// the same point - and the zero-length one is the value a caller really
// passes.
//
// EXPECTED RED, as an ERROR - see the block comment above.
//==============================================================================

dcl-proc test_in_groups_comma_only export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  grp like(SCDEF_NAME_t);

  fil_get('rmscfil_a': def);

  grp = '';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'control - a zero-length list matches nothing');

  grp = ',';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'and a list of nothing but a separator is the same list');

end-proc;


//==============================================================================
// Two trailing commas are two empty elements, and both are discarded
//
// The case that separates 'ignore the last element if it is empty' from
// 'ignore every empty element'. A splitter fixed by testing only for a comma
// in the last position answers this one wrongly, or crashes on it.
//
// ',,' is asserted as well: three empty elements, no real one, and still the
// blank-list answer rather than a crash.
//
// EXPECTED RED, as an ERROR - see the block comment above.
//==============================================================================

dcl-proc test_in_groups_two_trailing_commas export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  grp like(SCDEF_NAME_t);

  fil_get('rmscfil_a': def);

  grp = 'filgrp_mx';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'control - rmscfil_a declares filgrp_mx');

  grp = 'filgrp_mx,,';
  nEqual(true: SCCOLL_in_groups(def: grp):
         'two empty elements are discarded, not one');

  grp = ',,';
  nEqual(false: SCCOLL_in_groups(def: grp):
         'and separators alone are an empty list');

end-proc;


//##############################################################################
//##                                                                          ##
//##  THE FILENAME RULE                                                       ##
//##                                                                          ##
//##############################################################################
//
// MEASURED - upstream decides what is a definition file by its NAME, with a
// regex over the whole filename:
//
//     ^[a-z\-_0-9]+\.y[a]{0,1}ml$
//
// So the base name may hold only lower-case letters, digits, hyphen and
// underscore, and the extension must be exactly '.yaml' or '.yml'. Every
// other file in the directory is skipped, with one line per skipped file on
// stderr:
//
//     WARNING: Ignoring file: /full/path/to/the/file
//
// RMSC accepts names upstream rejects, so a file upstream ignores becomes a
// service in RMSC's output. Measured on the box: rmscgate_Ignored.yaml, with
// a capital I, loads in RMSC as 'rmscgate_ignored' and appears in check.
// Upstream ignores it and warns.
//
// Finding MORE services than upstream is the harder direction to notice,
// because nothing looks missing - the same argument the test_discovery header
// already makes about not walking subdirectories.
//
// EVERY FILE BELOW HOLDS THE SAME VALID DEFINITION. That is the point of the
// fixture: content cannot explain any difference in the result, so the only
// thing that can decide which become services is the name. A fixture whose
// rejected files were also malformed would pass against a loader that applied
// no name rule at all.
//
// ITS OWN DIRECTORY, like the ordering and filter fixtures, because the
// assertion is a COUNT. Sharing g_dir would make it a count of whatever else
// had been written there, and under ORDER(*API) nothing says which test runs
// first.
//
// WHAT IS NOT ASSERTED: the stderr warning. Standard error is not observable
// from inside the ILE job, so there is nothing here that could check it and
// an assertion pretending otherwise could not fail. The wording is measured
// and belongs to the output comparison against upstream instead.
//==============================================================================

//------------------------------------------------------------------------------
// nam_setup - nine files, three of them legal names
//
// TWO OF THE SIX REJECTS PROVE LESS THAN THE OTHERS, and it is worth saying
// so rather than letting a later reader count them as six pieces of evidence:
//
//   nodots         has no extension, and
//   .hidden.yaml   begins with a dot
//
// Both are expected to be skipped whatever the name rule does - a loader
// looking only for a '.yaml' or '.yml' suffix already drops 'nodots', and
// '.hidden.yaml' may be dropped by whatever handles dot entries. They are
// included because upstream's regex rejects them and a complete transcription
// of the rule is worth having, not because either discriminates.
//
// The four that DO discriminate are Bad.yaml, UPPER.YAML, has.dot.yaml and
// backup.yaml.bak.
//------------------------------------------------------------------------------
dcl-proc nam_setup;

  dcl-s y like(STRING_t);

  g_nam = '/tmp/rmsc-sccoll-name-' + %trim(psds.current_user);

  IFS_crtdir(g_nam);

  // One definition, written under nine names. Valid, so that nothing but the
  // name can decide the outcome.
  y = 'start_cmd: /usr/bin/rmscnam' + LF;
  y += 'check_alive: 8120' + LF;

  // Legal names - these three must become services
  write_file(%trim(g_nam) + '/good.yaml': y);
  write_file(%trim(g_nam) + '/also.yml': y);
  write_file(%trim(g_nam) + '/under_score-dash9.yaml': y);

  // Illegal names - these six must not
  write_file(%trim(g_nam) + '/Bad.yaml': y);          // capital in base name
  write_file(%trim(g_nam) + '/UPPER.YAML': y);        // capitals in both
  write_file(%trim(g_nam) + '/has.dot.yaml': y);      // dot inside base name
  write_file(%trim(g_nam) + '/backup.yaml.bak': y);   // extension is .bak
  write_file(%trim(g_nam) + '/nodots': y);            // no extension
  write_file(%trim(g_nam) + '/.hidden.yaml': y);      // leading dot

end-proc;

//------------------------------------------------------------------------------
// nam_teardown - remove the fixture and prove it went
//
// The readdir filter skips '.' and '..' only, so '.hidden.yaml' is removed
// like any other entry. IFS_dltdir fails silently on a non-empty directory,
// which is why the postcondition is asserted rather than assumed.
//------------------------------------------------------------------------------
dcl-proc nam_teardown;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_nam);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_nam) + '/' + %trim(filename));
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_nam);
  endif;

  assert((not IFS_isa_directory(g_nam)):
         'Filename fixture tree ' + %trim(g_nam) + ' not removed');

end-proc;

//==============================================================================
// Only a legal filename becomes a service
//
// The count is the assertion that covers all nine files at once. The names
// are asserted as well because a count of three would also be produced by a
// loader that took the wrong three - and one that accepted Bad.yaml while
// rejecting good.yaml would be exactly as wrong and exactly as quiet.
//
// 'bad' and 'upper' are asserted absent by name because those are the two
// whose short name is predictable when the rule is not applied: RMSC lower-
// cases a short name taken from the filename, which is how rmscgate_Ignored
// .yaml was measured arriving as 'rmscgate_ignored'. The other four rejects
// are covered by the count, since what they would be CALLED if wrongly
// loaded is not worth guessing at.
//==============================================================================

dcl-proc test_filename_rule export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_nam): 'filename fixture loaded');

  // good.yaml, also.yml, under_score-dash9.yaml - and nothing else
  iEqual(3: SCCOLL_count(coll): 'three of the nine files are definitions');

  nEqual(true: SCCOLL_find(coll: 'good': def):
         'a plain lower-case name loads');
  nEqual(true: SCCOLL_find(coll: 'also': def):
         '.yml is as legal an extension as .yaml');
  nEqual(true: SCCOLL_find(coll: 'under_score-dash9': def):
         'underscore, hyphen and digits are all legal in a base name');

  nEqual(false: SCCOLL_find(coll: 'bad': def):
         'a capital letter in the base name is not legal');
  nEqual(false: SCCOLL_find(coll: 'upper': def):
         'and neither is a capitalised extension');

end-proc;


//##############################################################################
//##                                                                          ##
//##  A BLANK IN THE FILENAME                                                 ##
//##                                                                          ##
//##############################################################################
//
// MEASURED - the name rule must be applied to the filename AS IT IS ON DISK,
// not to a trimmed copy of it. A blank is not in [a-z\-_0-9], so upstream
// rejects a name carrying one and warns with the blank intact:
//
//     WARNING: Ignoring file: /path/trail.yaml
//
// RMSC trims first, so 'trail.yaml ' passes the check as 'trail.yaml'. It then
// tries to open the trimmed path - a file that is not the one on disk - and
// fails with a load error in its own wording. Upstream never opens it at all.
//
// A SEPARATE DIRECTORY from the nam_ fixture, deliberately. The two could
// share one, since every file added here is meant to be ignored and the count
// would stay at three - but the nam_ count is a clean statement about the
// character-class rule, and these files carry a fixture-creation risk that
// the character-class files do not. Keeping them apart means that if a blank
// ever fails to reach disk intact, only this test is affected and
// test_filename_rule stays trustworthy.
//
// THE FIXTURE IS VERIFIED BEFORE IT IS TRUSTED. If a trailing blank were
// trimmed on the way to disk, the file would land as 'trail.yaml' - a legal
// name - and load as service 'trail'. That is indistinguishable from the
// defect by its result: both give a service called 'trail'. So the test reads
// the directory back and asserts the blank is really there before it asserts
// anything about loading. Without that, a red result could mean either the
// defect or a broken fixture, and CLAUDE.md is explicit that a suite must not
// report something it has not established.
//
// The risk is not symmetric. IFS paths are varchar, so a LEADING blank is
// carried by any implementation; a TRAILING one is lost by anything that
// applies %trimr on the way to the API. The trailing case is the one that
// needed proving, and it is the one measured as accepted.
//==============================================================================

//------------------------------------------------------------------------------
// blk_setup - one legal name and three that carry a blank
//------------------------------------------------------------------------------
dcl-proc blk_setup;

  dcl-s y like(STRING_t);

  g_blk = '/tmp/rmsc-sccoll-blank-' + %trim(psds.current_user);

  IFS_crtdir(g_blk);

  y = 'start_cmd: /usr/bin/rmscblk' + LF;
  y += 'check_alive: 8130' + LF;

  // The only legal name here. Its presence proves the loader ran at all, so
  // that a count of one cannot be confused with a count of none.
  write_file(%trim(g_blk) + '/plain.yaml': y);

  // Trailing blank - accepted by RMSC today, rejected upstream. The literal
  // below really does end in a blank and that is not a typo; STMF_t is
  // varchar, so the length is carried and the blank reaches the API.
  write_file(%trim(g_blk) + '/trail.yaml ': y);

  // Leading blank - the same rule, the other end of the name
  write_file(%trim(g_blk) + '/ lead.yaml': y);

  // CONTROL - a blank in the MIDDLE, which no trimming touches and which is
  // already rejected. It is what shows the defect is specifically about
  // trimming rather than about blanks in general.
  write_file(%trim(g_blk) + '/x y.yaml': y);

end-proc;

//------------------------------------------------------------------------------
// blk_teardown - remove the fixture, without trimming the names
//
// NOTE THE MISSING %trim ON filename. Every other teardown in this suite
// writes %trim(filename), which is correct there and would be a bug here: it
// would ask for 'trail.yaml' and leave 'trail.yaml ' on disk, so the directory
// would never empty, IFS_dltdir would fail silently, and the next run would
// inherit a fixture it did not write. IFS_DIR_FILENAME_t is varchar, so the
// untrimmed value is the exact name.
//------------------------------------------------------------------------------
dcl-proc blk_teardown;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_blk);
  if dir <> *null;
    dow IFS_readdir(dir: filename);
      if filename <> '.' and filename <> '..';
        IFS_remove_file(%trim(g_blk) + '/' + filename);
      endif;
    enddo;
    IFS_closedir(dir);
    IFS_dltdir(g_blk);
  endif;

  assert((not IFS_isa_directory(g_blk)):
         'Blank-name fixture tree ' + %trim(g_blk) + ' not removed');

end-proc;

//------------------------------------------------------------------------------
// blk_entry_len - the LENGTH of the first directory entry starting with prefix
//
// Length, not existence, because an RPG comparison blank-pads the shorter
// operand: 'trail.yaml' and 'trail.yaml ' compare EQUAL, so no equality test
// can tell them apart. The length can, and it is the only thing that can.
// Returns 0 when nothing matches.
//------------------------------------------------------------------------------
dcl-proc blk_entry_len;
  dcl-pi *n like(INTEGER_t);
    dir_path like(STMF_t) const;
    prefix   varchar(64) const;
  end-pi;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s found    like(INTEGER_t) inz(0);

  dir = IFS_opendir(dir_path);
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

//==============================================================================
// A blank in the filename is not trimmed away before the rule is applied
//
// coll.bad_count IS THE ASSERTION THAT CARRIES THIS TEST. Everything else here
// passes whether the rule works or not, and this test shipped green once
// because it had only the rest.
//
// The reason is that the right answer and the wrong one end in the same place.
// Correct: the name is rejected, the file is skipped, no service. Today: the
// trimmed name passes the rule, RMSC opens /dir/trail.yaml, which is not the
// file on disk, the open fails - and still no service. A count of services, or
// an absence-by-name, cannot tell those apart. That is precisely the shape
// CLAUDE.md records as having hidden three defects here: an assertion true of
// both the behaviour wanted and the behaviour present.
//
// What separates them is whether anything was RECORDED. A file rejected by the
// filename rule is skipped in silence. A file accepted and then failing to
// open is a load failure, and lands in the collection's bad-definition list -
// the same list test_broken_definition_recorded reads, and what SCMAIN prints
// as WARNING. So the correct behaviour leaves bad_count at zero and the defect
// cannot.
//
// Expect 2 today, not 1: '%trim' takes blanks off BOTH ends, so ' lead.yaml'
// is accepted and fails to open exactly as 'trail.yaml ' does. 'x y.yaml' adds
// nothing to it - trimming does not touch a blank in the middle, so the rule
// rejects it and it is skipped silently, which is the control working.
//
// ORDER. The two fixture-integrity assertions come first: they establish the
// blanks reached disk, without which nothing below is about a fixture that
// exists. bad_count comes next, ahead of the service count, because it is the
// one that discriminates and the report should say so before it says anything
// weaker.
//==============================================================================

dcl-proc test_filename_blank_not_trimmed export;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t) inz(*likeds);

  // FIXTURE INTEGRITY - 'trail.yaml ' is eleven characters, not ten
  iEqual(11: blk_entry_len(g_blk: 'trail.yaml'):
         'the trailing blank reached disk - if this fails the rest of ' +
         'this test is meaningless, and nothing below it is evidence');

  // FIXTURE INTEGRITY - ' lead.yaml' still begins with a blank
  iEqual(10: blk_entry_len(g_blk: ' lead'):
         'the leading blank reached disk');

  SCCOLL_init(coll);
  assert(SCCOLL_load_dir(coll: g_blk): 'blank-name fixture loaded');

  // THE DISCRIMINATING ASSERTION. A name the rule rejects is skipped without
  // a word; a name it accepts and then cannot open is recorded here. Only
  // this tells the two apart - see the header.
  iEqual(0: coll.bad_count:
         'a blank in the name is rejected silently, not accepted and then ' +
         'recorded as a definition that would not load');

  // plain.yaml, and nothing else
  iEqual(1: SCCOLL_count(coll): 'one of the four files is a definition');

  nEqual(true: SCCOLL_find(coll: 'plain': def):
         'the legal name loads, so the loader did run');

  nEqual(false: SCCOLL_find(coll: 'trail': def):
         'a trailing blank is part of the name, and not legal in one');
  nEqual(false: SCCOLL_find(coll: 'lead': def):
         'nor is a leading blank');

end-proc;

//##############################################################################
//##                                                                          ##
//##  A DIRECTORY PATH ENDING IN A SEPARATOR                                  ##
//##                                                                          ##
//##############################################################################
//
// FIXED. This test was written red and is kept as the regression guard.
//
// WHAT IT WAS. Given a directory that already ended in '/', RMSC concatenated
// and doubled the separator:
//
//     RMSC:      /tmp/x/slash//somefile.yaml
//     upstream:  /tmp/x/slash/somefile.yaml
//
// A trailing slash is what shell tab-completion produces, so it was easy to
// arrive at without meaning to. The defect was pre-existing rather than
// introduced by this work.
//
// WHAT IT IS NOW. Measured after the fix, with the directory given as
// '/tmp/x/':
//
//     Defined in: /tmp/x/rmscslash.yaml
//
// byte-identical on both implementations, and the skip warning likewise. So
// the stored path itself was measured correct, not merely the property this
// test asserts.
//
// WHAT THIS TEST CAN AND CANNOT SEE. SCDEF_t exposes no field holding the file
// a definition was read from - nothing in any suite reads one, and there is no
// SCDEF accessor for it - so the doubled path itself could not be asserted
// from inside the job. SCDEF_effective_dir is the nearest observable: with no
// 'dir' key present it yields the definition file's own directory, which
// test_effective_dir_absent in SCDEF.TEST already pins.
//
// So this asserts the PROPERTY rather than the path: a trailing separator on
// the directory must not change anything RMSC derives from it. Comparing the
// two loads against each other rather than against a literal also means the
// test does not drift if the fixture directory moves.
//
// WHAT A GREEN RESULT PROVES, AND WHAT IT DOES NOT. Green here shows that
// effective_dir is unaffected by a trailing separator. It does NOT by itself
// establish that the stored path is right, because effective_dir could in
// principle normalise where a stored path does not - so if this test is ever
// the only evidence, it is not enough. That reasoning still stands and is why
// the paragraph is kept; it is simply no longer the whole picture, since the
// stored path was measured directly above.
//
// NOT DOCUMENTED IN parity.md. docs/parity.md does mention the 'Defined in:'
// line, but about a different difference that happens to share the output
// line - the two implementations naming their own copy of the same file. It
// never recorded the separator doubling, and a reader sent there would come
// away thinking this had already been accounted for.
//==============================================================================

dcl-proc test_trailing_slash_directory export;

  dcl-ds bare  likeds(SCCOLL_t) inz(*likeds);
  dcl-ds slash likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def   likeds(SCDEF_t) inz(*likeds);

  dcl-s bare_dir  varchar(512);
  dcl-s slash_dir varchar(512);

  SCCOLL_init(bare);
  assert(SCCOLL_load_dir(bare: g_nam): 'loaded without a trailing slash');
  nEqual(true: SCCOLL_find(bare: 'good': def): 'good found');
  bare_dir = SCDEF_effective_dir(def);

  SCCOLL_init(slash);
  assert(SCCOLL_load_dir(slash: %trim(g_nam) + '/'):
         'loaded with a trailing slash');
  nEqual(true: SCCOLL_find(slash: 'good': def):
         'the same service is found either way');
  slash_dir = SCDEF_effective_dir(def);

  iEqual(SCCOLL_count(bare): SCCOLL_count(slash):
         'the same directory, so the same definitions');

  aEqualV(bare_dir: slash_dir:
          'a trailing separator changes nothing RMSC derives from the path');

end-proc;
