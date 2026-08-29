**free

//==============================================================================
// SCCMD      - Processing program for the SC command
//
// Assembles the same command line SCRUN takes from the shell, so both routes
// go through one parser rather than two that could drift apart.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: SC command processing program');
ctl-opt dftactgrp(*no) actgrp(*caller);
ctl-opt main(SCCMD);
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');
/include 'include/RMCOMP_H.rpgleinc'

/include 'SCMAIN_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMMSG_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-proc SCCMD;
  dcl-pi *n;
    p_option  char(12) const;
    p_service char(256) const;
    p_colours char(4) const;
    p_all     char(4) const;
    p_ignore  char(64) const;
  end-pi;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s args like(SCMAIN_ARGS_t);

  // The command uses *CHECK, *START and so on; the parser takes the bare word
  args = STRING_lower(%subst(%trimr(p_option): 2));

  if %trimr(p_service) <> '' and %trimr(p_service) <> '*NONE';
    args += ' ' + %trimr(p_service);
  endif;

  if %trimr(p_colours) = '*YES';
    args += ' --colors';
  endif;

  if %trimr(p_all) = '*YES';
    args += ' -a';
  endif;

  if %trimr(p_ignore) <> '' and %trimr(p_ignore) <> '*DFT';
    args += ' --ignore-groups=' + %trimr(p_ignore);
  endif;

  if not SCMAIN_parse(args: opts);
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
