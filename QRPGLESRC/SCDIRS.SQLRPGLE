**free

//==============================================================================
// SCDIRS     - Definition directory resolution
//
// Works out where service definitions live. The home directory comes from
// QSYS2.USER_INFO rather than $HOME, because $HOME is not reliably set in a
// batch job - which is exactly where a service is started from.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Definition directory resolution');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCDIRS_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMENVVAR_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-pr add_dir;
  dirs likeds(SCDIRS_t);
  path like(STMF_t) const;
end-pr;

//==============================================================================
// SCDIRS_search_path
//==============================================================================

dcl-proc SCDIRS_search_path export;
  dcl-pi *n like(INTEGER_t);
    dirs likeds(SCDIRS_t);
    ignore_globals like(BOOLEAN_t) const options(*nopass);
  end-pi;

  dcl-s home  like(STMF_t);
  dcl-s skip  like(BOOLEAN_t) inz(false);

  clear dirs;

  if %parms() >= 2 and %addr(ignore_globals) <> *null;
    skip = ignore_globals;
  endif;

  // The two subdirectories are named rather than found. Upstream's loader
  // skips subdirectories - 'if (f.isDirectory()) { continue; }' - and reaches
  // the definitions it ships under system/ and oss_common/ by naming those
  // paths. Walking the tree instead would report anything anyone ever left
  // below this directory as a service, which upstream would never see.
  if not skip;
    add_dir(dirs: SCDIRS_GLOBAL);
    add_dir(dirs: SCDIRS_GLOBAL + '/' + SCDIRS_SYS_REL);
    add_dir(dirs: SCDIRS_GLOBAL + '/' + SCDIRS_OSS_REL);
  endif;

  home = SCDIRS_home_dir();
  if %len(%trim(home)) > 0;
    add_dir(dirs: %trim(home) + '/' + SCDIRS_USER_REL);
  endif;

  // Last, so it can override everything else, which is the point of it
  add_dir(dirs: %trim(ENVVAR_get(SCDIRS_CUSTOM_ENV)));

  return dirs.count;

end-proc;

//==============================================================================
// add_dir
//   Append a directory, if it exists and there is room
//==============================================================================

dcl-proc add_dir;
  dcl-pi *n;
    dirs likeds(SCDIRS_t);
    path like(STMF_t) const;
  end-pi;

  if %len(%trim(path)) = 0 or dirs.count >= SCDIRS_MAX;
    return;
  endif;

  // Callers walk the list without checking, so a path that cannot be opened
  // must never reach them
  if not IFS_isa_directory(path);
    return;
  endif;

  dirs.count += 1;
  dirs.path(dirs.count) = path;

end-proc;

//==============================================================================
// SCDIRS_home_dir
//==============================================================================

dcl-proc SCDIRS_home_dir export;
  dcl-pi *n like(STMF_t) end-pi;

  dcl-s home varchar(1024) inz('');

  // Fall back to /home/<user> when the profile carries no home directory, as
  // upstream does. Returning blank here is not neutral: the caller then skips
  // the user definitions directory entirely, so user-level services would go
  // missing with nothing said about it.
  exec sql
    SELECT COALESCE(NULLIF(TRIM(HOME_DIRECTORY), ''),
                    '/home/' CONCAT TRIM(CURRENT_USER))
      INTO :home
      FROM QSYS2.USER_INFO
     WHERE AUTHORIZATION_NAME = CURRENT_USER;

  if sqlcode <> 0;
    return '';
  endif;

  return home;

end-proc;
