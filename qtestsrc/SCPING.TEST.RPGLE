**free

//==============================================================================
// SCPING.TEST - Phase 0 build spike test suite
//
// THROWAWAY. Proves the RPGUnit loop works end to end and, more usefully,
// that SCPING_upper resolves at run time - which it only can if RMSTRING01
// was bound BY COPY into SCPING.SRVPGM.
//
// Deleted at the start of Phase 1.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;

// RUCRTRPG has no BNDDIR set in testing.json, so the binding must come from
// the source - same route SCPINGP uses. RMSCPGM is found on the library list
// at compile time, which is why RMSC is on preUsrlibl in iproj.json.
ctl-opt bnddir('RMSCPGM');

/include 'SCPING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

//==============================================================================
// The build and bind loop works
//==============================================================================

dcl-proc test_SCPING_upper export;

  aEqual('HELLO':SCPING_upper('hello'):'lower to upper');

end-proc;

//==============================================================================
// Mixed case and non-alphabetic characters pass through
//==============================================================================

dcl-proc test_SCPING_upper_mixed export;

  aEqual('WEBPROXY 8080':SCPING_upper('WebProxy 8080'):'mixed case');

end-proc;

//==============================================================================
// An empty string is not an error
//==============================================================================

dcl-proc test_SCPING_upper_empty export;

  aEqual('':SCPING_upper(''):'empty string');

end-proc;
