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
/include 'SCDIRS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/RMENVVAR_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'

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

  dcl-s  home     like(STMF_t);
  dcl-s  scrc_txt like(STRING_t) ccsid(*utf8);
  dcl-s  prefix   like(SCMAIN_ARGS_t);
  dcl-s  cli_args like(SCMAIN_ARGS_t);
  dcl-s  full_args like(SCMAIN_ARGS_t);

  // .scrc/SC_OPTIONS - DECIDED 19 September 2026, docs/parity.md, "scrc and
  // SC_OPTIONS". Read before anything else, so the tokens they contribute
  // reach SCMAIN_parse exactly as if they had been typed first on the real
  // command line - which is what gives the documented flags (-a,
  // --ignore-groups, --sampletime) their measured last-wins precedence
  // against whatever the caller actually typed.
  //
  // Blank when the file does not exist - IFS_read itself is silent about a
  // missing file, and .scrc is optional for every user, so that silence is
  // correct here and not worth a check of its own.
  home = SCDIRS_home_dir();
  if %len(%trim(home)) > 0;
    scrc_txt = IFS_read(%trim(home) + '/.scrc');
  endif;

  prefix = SCMAIN_config_prefix(scrc_txt: ENVVAR_get('SC_OPTIONS'));

  // Upstream has no equivalent limit - its strings are unbounded - so this
  // is an RMSC-only guard, the same shape as the ones already in
  // SCMAIN_parse for an oversized --ignore-groups or --sampletime value:
  // refuse to guess rather than silently truncate a combined line nobody
  // asked to have cut. Combined length only, checked before the
  // concatenation that would otherwise do the truncating.
  cli_args = %trimr(p_args);
  if %len(%trimr(prefix)) = 0;
    full_args = cli_args;
  elseif %len(%trimr(prefix)) + 1 + %len(cli_args) > SCMAIN_ARGS_SIZE;
    SCOUT_warnln('WARNING: options from .scrc/SC_OPTIONS are too long to ' +
                 'apply together with this command line and were ignored');
    full_args = cli_args;
  else;
    full_args = %trimr(prefix) + ' ' + cli_args;
  endif;

  // Two independent questions, and neither is inferred from the other: the
  // status says what to exit with, opts.err says what still needs saying.
  // A status of 0 carrying a message is a warning; a non-zero status with no
  // message is a failure that has already reported itself.
  // BARE, no 'sc: ' prefix - DECIDED 18 September 2026, docs/parity.md.
  // Measured: upstream's stderr starts at column 1 in every case, with no
  // prefix of any kind. The prefix was a survival from the escape-message
  // era, when the line arrived as `CPF9897: sc: ...` and 'sc:' was doing the
  // work of naming the program; it outlived the message it was named for.
  status = SCMAIN_parse(full_args: opts);
  if opts.err <> '';
    SCOUT_warnln(%trim(opts.err));
  endif;
  if status <> SCMAIN_EXIT_OK;
    c_exit(status);
  endif;

  status = SCMAIN_run(opts);
  if opts.err <> '';
    SCOUT_warnln(%trim(opts.err));
  endif;
  if status <> SCMAIN_EXIT_OK;
    c_exit(status);
  endif;

end-proc;
