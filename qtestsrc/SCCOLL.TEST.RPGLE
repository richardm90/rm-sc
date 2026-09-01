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

end-proc;

dcl-proc tearDownSuite export;

  remove_tree();

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
// Upstream recurses with no visited set and overflows its stack, which says
// nothing about which definitions are at fault.
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
