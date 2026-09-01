**free

//==============================================================================
// SCDIRS.TEST - Definition directory resolution test suite
//
// The directories upstream reads, in the order it reads them:
//
//   /QOpenSys/etc/sc/services
//   /QOpenSys/etc/sc/services/system
//   /QOpenSys/etc/sc/services/oss_common
//   $HOME/.sc/services
//   the custom directory, when one is configured
//
// Order is not cosmetic. Upstream merges each directory into the collection
// with putAll, so a definition read later replaces one of the same name read
// earlier - which is what lets a user's copy of a service override the global
// copy. Get the order wrong and the wrong definition wins, silently.
//
// The three global entries are named paths, not the result of walking the
// tree: YamlServiceDefLoader.loadFromDirectory skips subdirectories outright
// ('if (f.isDirectory()) { continue; }'), and reaches system/ and oss_common/
// by naming them. Confirmed against the installed sc 1.7.1, which cannot see
// a definition placed one directory down.
//
// Upstream takes the custom directory from the 'services.dir' JVM system
// property. ILE has no equivalent, so RMSC reads an environment variable.
//
// 31/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCDIRS_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMENVVAR_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-s g_custom like(STMF_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

dcl-pr contains_path like(BOOLEAN_t);
  dirs likeds(SCDIRS_t) const;
  want like(STMF_t) const;
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_custom = '/tmp/rmsc-scdirs-test-' + %trim(psds.current_user);
  IFS_crtdir(g_custom);

  // Nothing from a previous run should still be pointing anywhere
  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);

end-proc;

dcl-proc tearDownSuite export;

  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);
  IFS_dltdir(g_custom);

end-proc;

//==============================================================================
// The three global directories come first, in upstream's order
//==============================================================================

dcl-proc test_global_directories_in_order export;

  dcl-ds dirs likeds(SCDIRS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  // Fail rather than skip: a suite that passes because its fixture is absent
  // reports success while testing nothing.
  assert(IFS_isa_directory(SCDIRS_GLOBAL):
         'fixture: ' + SCDIRS_GLOBAL + ' must exist');
  assert(IFS_isa_directory(SCDIRS_GLOBAL + '/system'):
         'fixture: the system subdirectory must exist');
  assert(IFS_isa_directory(SCDIRS_GLOBAL + '/oss_common'):
         'fixture: the oss_common subdirectory must exist');

  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);
  n = SCDIRS_search_path(dirs);

  assert((n >= 3): 'at least the three global directories');
  aEqualV(SCDIRS_GLOBAL: dirs.path(1): 'global directory first');
  aEqualV(SCDIRS_GLOBAL + '/system': dirs.path(2): 'system second');
  aEqualV(SCDIRS_GLOBAL + '/oss_common': dirs.path(3): 'oss_common third');

end-proc;

//==============================================================================
// The custom directory is searched, and searched last
//
// Last, because it must be able to override everything else.
//==============================================================================

dcl-proc test_custom_directory_is_last export;

  dcl-ds dirs likeds(SCDIRS_t) inz(*likeds);
  dcl-s  n    like(INTEGER_t);

  assert(ENVVAR_put(SCDIRS_CUSTOM_ENV: g_custom): 'custom directory set');

  n = SCDIRS_search_path(dirs);

  assert((n > 0): 'search path resolves');
  aEqualV(g_custom: dirs.path(n): 'custom directory searched last');

end-proc;

//==============================================================================
// With nothing configured, there is no custom directory
//==============================================================================

dcl-proc test_custom_directory_absent_when_unset export;

  dcl-ds dirs likeds(SCDIRS_t) inz(*likeds);

  ENVVAR_dlt(SCDIRS_CUSTOM_ENV);
  SCDIRS_search_path(dirs);

  nEqual(false: contains_path(dirs: g_custom):
         'custom directory not searched when unset');

end-proc;

//==============================================================================
// A configured directory that does not exist is skipped, not returned
//
// Callers walk the list without checking, so a path that cannot be opened
// must never reach them.
//==============================================================================

dcl-proc test_custom_directory_ignored_when_missing export;

  dcl-ds dirs likeds(SCDIRS_t) inz(*likeds);
  dcl-s  gone like(STMF_t);

  gone = %trim(g_custom) + '/no-such-directory';
  assert(ENVVAR_put(SCDIRS_CUSTOM_ENV: gone): 'custom directory set');

  SCDIRS_search_path(dirs);

  nEqual(false: contains_path(dirs: gone):
         'missing custom directory skipped');

end-proc;

//==============================================================================
// Helpers
//==============================================================================

dcl-proc aEqualV;
  dcl-pi *n;
    expected  varchar(512) const;
    actual    varchar(512) const;
    fieldName varchar(64) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(fieldName) + ': expected "' + %trim(expected) +
         '" but was "' + %trim(actual) + '"');

end-proc;

dcl-proc contains_path;
  dcl-pi *n like(BOOLEAN_t);
    dirs likeds(SCDIRS_t) const;
    want like(STMF_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to dirs.count;
    if %trim(dirs.path(i)) = %trim(want);
      return true;
    endif;
  endfor;

  return false;

end-proc;
