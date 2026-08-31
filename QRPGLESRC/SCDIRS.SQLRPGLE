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
/include 'include/RMTOOLS_D.rpgleinc'

//==============================================================================
// SCDIRS_search_path
//==============================================================================

dcl-proc SCDIRS_search_path export;
  dcl-pi *n like(INTEGER_t);
    dirs likeds(SCDIRS_t);
  end-pi;

  dcl-s home like(STMF_t);
  dcl-s user_dir like(STMF_t);

  clear dirs;

  // Global first, matching upstream's search order
  if IFS_isa_directory(SCDIRS_GLOBAL);
    dirs.count += 1;
    dirs.path(dirs.count) = SCDIRS_GLOBAL;
  endif;

  home = SCDIRS_home_dir();
  if %len(%trim(home)) > 0;
    user_dir = %trim(home) + '/' + SCDIRS_USER_REL;
    if IFS_isa_directory(user_dir);
      dirs.count += 1;
      dirs.path(dirs.count) = user_dir;
    endif;
  endif;

  return dirs.count;

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
