**free

//==============================================================================
// SCPING     - Phase 0 build spike
//
// THROWAWAY. Proves three things before any real code depends on them:
//   1. TOBi compiles a module in this project
//   2. an rmtools module (RMSTRING01) binds BY COPY, leaving no runtime
//      library-list dependency
//   3. RPGUnit runs a test against the resulting service program
//
// Deleted at the start of Phase 1.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Phase 0 build spike');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

///
// Include copybooks
///

/include 'SCPING_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

//==============================================================================
// SCPING_upper
//   Delegates to rmtools STRING_upper
//==============================================================================

dcl-proc SCPING_upper export;
  dcl-pi *n like(STRING_t);
    str like(STRING_t) const;
  end-pi;

  return STRING_upper(str);

end-proc;
