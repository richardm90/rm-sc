**free

//==============================================================================
// SCRUN      - PASE entry point
//
// Takes a whole command line as one parameter, because that is the shape the
// shell wrapper has: 'sc check mapepire -v' arrives here as one string.
//
// A failure is written to standard ERROR and the program exits with a status.
// It is NOT signalled as an escape message, which is what this used to do and
// what upstream's behaviour cannot be matched through:
//
//   - `system` returns 255 for any exception, whatever went wrong, so every
//     failure looked identical to the shell. Upstream distinguishes them.
//   - the message came out twice: once written here, once by the message
//     monitor. The copy written here went to standard OUTPUT, which is where
//     a consumer reads service rows by column position - so an error line
//     could be read as a row, or drop one.
//
// The IBM PASE `system` utility hands back "the exit status set by whatever
// program the CL command calls" as long as no exception is signalled, so
// exiting with a status is the whole mechanism.
//
// The statuses are upstream's, and are decided by SCMAIN_parse and
// SCMAIN_run rather than worked out here from which of them failed - see
// SCMAIN_D for the contract:
//
//   255  the command line could not be understood
//   253  it was understood and could not be carried out
//     0  it worked
//
// The native SC command (SCCMD) still signals, deliberately: a CL caller has
// no exit status to read, and MONMSG is the interface there.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service Commander');
ctl-opt dftactgrp(*no) actgrp(*caller);
ctl-opt main(SCRUN);
ctl-opt bnddir('RMSCPGM':'RMSCDEPS':'QC2LE');
/include 'include/RMCOMP_H.rpgleinc'

/include 'SCMAIN_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

// Ends the activation group with a status. Never returns.
dcl-pr c_exit extproc('exit');
  status int(10) value;
end-pr;

dcl-proc SCRUN;
  dcl-pi *n;
    p_args char(SCMAIN_ARGS_SIZE) const;
  end-pi;

  dcl-ds opts   likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  status like(INTEGER_t);

  // Two independent questions, and neither is inferred from the other: the
  // status says what to exit with, opts.err says what still needs saying.
  // A status of 0 carrying a message is a warning; a non-zero status with no
  // message is a failure that has already reported itself.
  status = SCMAIN_parse(%trimr(p_args): opts);
  if opts.err <> '';
    SCOUT_warnln('sc: ' + %trim(opts.err));
  endif;
  if status <> SCMAIN_EXIT_OK;
    c_exit(status);
  endif;

  status = SCMAIN_run(opts);
  if opts.err <> '';
    SCOUT_warnln('sc: ' + %trim(opts.err));
  endif;
  if status <> SCMAIN_EXIT_OK;
    c_exit(status);
  endif;

end-proc;
