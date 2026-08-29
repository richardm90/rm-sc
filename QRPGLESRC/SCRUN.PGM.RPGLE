**free

//==============================================================================
// SCRUN      - PASE entry point
//
// Takes a whole command line as one parameter, because that is the shape the
// shell wrapper has: 'sc check mapepire -v' arrives here as one string.
//
// A failure is reported and then thrown as an escape message. That is what
// makes the exit status non-zero for the caller - without it, the wrapper
// would report success no matter what happened.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service Commander');
ctl-opt dftactgrp(*no) actgrp(*caller);
ctl-opt main(SCRUN);
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');
/include 'include/RMCOMP_H.rpgleinc'

/include 'SCMAIN_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMMSG_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-proc SCRUN;
  dcl-pi *n;
    p_args char(SCMAIN_ARGS_SIZE) const;
  end-pi;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  if not SCMAIN_parse(%trimr(p_args): opts);
    SCOUT_writeln('sc: ' + %trim(opts.err));
    throw('sc: ' + %trim(opts.err));
    return;
  endif;

  if not SCMAIN_run(opts);
    SCOUT_writeln('sc: ' + %trim(opts.err));
    throw('sc: ' + %trim(opts.err));
    return;
  endif;

end-proc;
