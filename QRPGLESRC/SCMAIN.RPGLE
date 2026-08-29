**free

//==============================================================================
// SCMAIN     - Command line
//
// Parses a command line, resolves what it names, and runs it.
//
// Parsing and running are separate procedures so the parsing can be tested on
// its own. An operation that quietly resolves to the wrong service, or a flag
// that silently does nothing, is the kind of fault that only shows up in
// production.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Command line');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCMAIN_D.rpgleinc'
/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCEXEC_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-pr next_token like(SCMAIN_ARGS_t);
  rest like(SCMAIN_ARGS_t);
end-pr;

dcl-pr is_operation like(BOOLEAN_t);
  word like(SCMAIN_ARGS_t) const;
end-pr;

dcl-pr run_reporting;
  opts likeds(SCMAIN_OPTS_t) const;
  def  likeds(SCDEF_t) const;
end-pr;

dcl-pr resolve_one like(BOOLEAN_t);
  opts likeds(SCMAIN_OPTS_t);
  coll likeds(SCCOLL_t);
  def  likeds(SCDEF_t);
end-pr;

//==============================================================================
// SCMAIN_parse
//==============================================================================

dcl-proc SCMAIN_parse export;
  dcl-pi *n like(BOOLEAN_t);
    args like(SCMAIN_ARGS_t) const;
    opts likeds(SCMAIN_OPTS_t);
  end-pi;

  dcl-s rest like(SCMAIN_ARGS_t);
  dcl-s word like(SCMAIN_ARGS_t);
  dcl-s eq   like(INTEGER_t);

  clear opts;
  opts.ignore_groups = SCMAIN_DFT_IGNORE;
  opts.sampletime = '1';

  rest = %trim(args);

  dow %len(rest) > 0;
    word = next_token(rest);
    if %len(word) = 0;
      leave;
    endif;

    select;
      when word = '-v';
        opts.verbose = true;
      when word = '-q';
        opts.quiet = true;
      when word = '--disable-colors' or word = '--disable-colours';
        opts.colours = false;
      // Not an upstream flag. Upstream decides by asking whether stdout is a
      // terminal; RMSC cannot ask that from ILE, so whatever CAN ask - the
      // PASE wrapper, with [ -t 1 ] - says so explicitly.
      when word = '--colors' or word = '--colours';
        opts.colours = true;
      when word = '--splf';
        opts.splf = true;
      when word = '--ignore-globals';
        opts.ignore_globals = true;
      when word = '-a' or word = '--all';
        opts.all = true;
      when %len(word) > 16 and %subst(word: 1: 16) = '--ignore-groups=';
        opts.ignore_groups = %subst(word: 17);
      when %len(word) > 13 and %subst(word: 1: 13) = '--sampletime=';
        opts.sampletime = %subst(word: 14);

      when %len(word) > 1 and %subst(word: 1: 1) = '-';
        opts.err = 'Unknown option ' + %trim(word);
        return false;

      when %len(%trim(opts.operation)) = 0;
        if not is_operation(word);
          opts.err = 'Unknown operation ' + %trim(word);
          return false;
        endif;
        opts.operation = STRING_lower(word);
        // status is upstream's alias for check
        if opts.operation = 'status';
          opts.operation = 'check';
        endif;

      when %len(%trim(opts.spec)) = 0;
        opts.spec = word;

      other;
        opts.err = 'Unexpected argument ' + %trim(word);
        return false;
    endsl;
  enddo;

  if %len(%trim(opts.operation)) = 0;
    opts.err = 'No operation given';
    return false;
  endif;

  // -a overrides the group exclusions, as upstream does
  if opts.all;
    opts.ignore_groups = '';
  endif;

  return true;

end-proc;

//==============================================================================
// next_token
//   Take the next space-separated word, leaving the remainder
//==============================================================================

dcl-proc next_token;
  dcl-pi *n like(SCMAIN_ARGS_t);
    rest like(SCMAIN_ARGS_t);
  end-pi;

  dcl-s space like(INTEGER_t);
  dcl-s word  like(SCMAIN_ARGS_t);

  rest = %trim(rest);
  if %len(rest) = 0;
    return '';
  endif;

  space = %scan(' ': rest);
  if space = 0;
    word = rest;
    rest = '';
  else;
    word = %subst(rest: 1: space - 1);
    rest = %trim(%subst(rest: space + 1));
  endif;

  return word;

end-proc;

//==============================================================================
// is_operation
//==============================================================================

dcl-proc is_operation;
  dcl-pi *n like(BOOLEAN_t);
    word like(SCMAIN_ARGS_t) const;
  end-pi;

  dcl-s w like(SCMAIN_ARGS_t);

  w = STRING_lower(%trim(word));

  select;
    when w = 'check' or w = 'status' or w = 'start' or w = 'stop'
      or w = 'kill'  or w = 'restart' or w = 'info'  or w = 'file'
      or w = 'list'  or w = 'groups'  or w = 'jobinfo' or w = 'loginfo'
      or w = 'perfinfo' or w = 'scrunattrs';
      return true;
    other;
      return false;
  endsl;

end-proc;

//==============================================================================
// SCMAIN_adhoc
//   port:N, job:NAME, job:SBS/NAME or PGM-NAME
//==============================================================================

dcl-proc SCMAIN_adhoc export;
  dcl-pi *n like(BOOLEAN_t);
    spec like(SCMAIN_SPEC_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  dcl-s work  like(SCMAIN_SPEC_t);
  dcl-s value like(SCMAIN_SPEC_t);
  dcl-s slash like(INTEGER_t);

  clear def;
  work = %trim(spec);

  if %len(work) > 5 and STRING_lower(%subst(work: 1: 5)) = 'port:';
    value = %subst(work: 6);
    def.short_name = 'port:' + %trim(value);
    def.friendly   = 'ad hoc port ' + %trim(value);
    def.criteria_count = 1;
    def.criteria(1).kind = SCDEF_CHECK_PORT;
    def.criteria(1).raw  = value;
    def.criteria(1).port = %int(value);
    return true;
  endif;

  if %len(work) > 4 and STRING_lower(%subst(work: 1: 4)) = 'job:';
    value = STRING_upper(%subst(work: 5));
    def.short_name = 'job:' + %trim(value);
    def.friendly   = 'ad hoc job ' + %trim(value);
    def.criteria_count = 1;
    def.criteria(1).kind = SCDEF_CHECK_JOB;
    def.criteria(1).raw  = value;
    slash = %scan('/': value);
    if slash > 1 and slash < %len(value);
      def.criteria(1).subsystem = %subst(value: 1: slash - 1);
      def.criteria(1).job_name  = %subst(value: slash + 1);
    else;
      def.criteria(1).job_name = value;
    endif;
    return true;
  endif;

  if %len(work) > 4 and STRING_upper(%subst(work: 1: 4)) = 'PGM-';
    value = STRING_upper(%subst(work: 5));
    def.short_name = 'PGM-' + %trim(value);
    def.friendly   = 'ad hoc program ' + %trim(value);
    def.criteria_count = 1;
    def.criteria(1).kind = SCDEF_CHECK_PGM;
    def.criteria(1).raw  = value;
    def.criteria(1).program = value;
    return true;
  endif;

  return false;

end-proc;

//==============================================================================
// resolve_one
//   Find the single service a specifier names
//==============================================================================

dcl-proc resolve_one;
  dcl-pi *n like(BOOLEAN_t);
    opts likeds(SCMAIN_OPTS_t);
    coll likeds(SCCOLL_t);
    def  likeds(SCDEF_t);
  end-pi;

  // Ad hoc specifiers do not need a definition to exist
  if SCMAIN_adhoc(opts.spec: def);
    return true;
  endif;

  // A path names a file directly, which is how upstream lets you act on a
  // definition that is not on the search path at all
  if %scan('/': opts.spec) > 0;
    if not SCDEF_load(opts.spec: def);
      opts.err = 'Cannot load ' + %trim(opts.spec) + ': ' + %trim(def.err);
      return false;
    endif;
    return true;
  endif;

  if not SCCOLL_find(coll: opts.spec: def);
    opts.err = 'Unknown service ' + %trim(opts.spec);
    return false;
  endif;

  return true;

end-proc;

//==============================================================================
// SCMAIN_run
//==============================================================================

dcl-proc SCMAIN_run export;
  dcl-pi *n like(BOOLEAN_t);
    opts likeds(SCMAIN_OPTS_t);
  end-pi;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err   like(SCEXEC_ERR_t);
  dcl-s i     like(INTEGER_t);
  dcl-s group like(SCDEF_NAME_t);
  dcl-s acted like(BOOLEAN_t) inz(false);

  SCOUT_set_colour(opts.colours);

  SCCOLL_load(coll);

  // A definition that failed to load is reported but does not stop the rest
  // being managed. Under -q it is suppressed, which is what quiet is for.
  if not opts.quiet;
    for i = 1 to coll.bad_count;
      SCOUT_writeln('WARNING: ' + %trim(coll.bad_name(i)) + ': ' +
                    %trim(coll.bad_err(i)));
    endfor;
  endif;

  // Operations over the whole collection
  select;
    when opts.operation = 'groups';
      SCEXEC_groups(coll: opts.ignore_groups);
      return true;

    when opts.operation = 'list' and %len(%trim(opts.spec)) = 0;
      SCEXEC_list(coll: opts.ignore_groups);
      return true;

    // A bare 'check', which is how a caller asks for everything
    when opts.operation = 'check'
     and (%len(%trim(opts.spec)) = 0 or STRING_lower(opts.spec) = 'all');
      SCEXEC_check_all(coll: opts.ignore_groups);
      return true;
  endsl;

  // group:NAME applies the operation to every member
  if %len(opts.spec) > 6 and STRING_lower(%subst(opts.spec: 1: 6)) = 'group:';
    group = STRING_lower(%subst(opts.spec: 7));
    for i = 1 to SCCOLL_count(coll);
      if not SCCOLL_get(coll: i: def) or not SCDEF_in_group(def: group);
        iter;
      endif;
      acted = true;
      select;
        when opts.operation = 'check';
          SCEXEC_check(def);
        when opts.operation = 'start';
          if not SCEXEC_start(coll: def.short_name: err);
            SCOUT_writeln('ERROR: ' + %trim(err));
          endif;
        when opts.operation = 'stop';
          if not SCEXEC_stop(coll: def.short_name: false: err);
            SCOUT_writeln('ERROR: ' + %trim(err));
          endif;
        when opts.operation = 'kill';
          if not SCEXEC_stop(coll: def.short_name: true: err);
            SCOUT_writeln('ERROR: ' + %trim(err));
          endif;
        when opts.operation = 'restart';
          if not SCEXEC_restart(coll: def.short_name: err);
            SCOUT_writeln('ERROR: ' + %trim(err));
          endif;
        other;
          run_reporting(opts: def);
      endsl;
    endfor;

    if not acted;
      opts.err = 'No services in group ' + %trim(group);
      return false;
    endif;
    return true;
  endif;

  // Everything else needs one named service
  if %len(%trim(opts.spec)) = 0;
    opts.err = 'Operation ' + %trim(opts.operation) + ' needs a service';
    return false;
  endif;

  if not resolve_one(opts: coll: def);
    return false;
  endif;

  select;
    when opts.operation = 'check';
      SCEXEC_check(def);
    when opts.operation = 'start';
      if not SCEXEC_start(coll: def.short_name: err);
        opts.err = err;
        return false;
      endif;
    when opts.operation = 'stop';
      if not SCEXEC_stop(coll: def.short_name: false: err);
        opts.err = err;
        return false;
      endif;
    when opts.operation = 'kill';
      if not SCEXEC_stop(coll: def.short_name: true: err);
        opts.err = err;
        return false;
      endif;
    when opts.operation = 'restart';
      if not SCEXEC_restart(coll: def.short_name: err);
        opts.err = err;
        return false;
      endif;
    when opts.operation = 'list';
      SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
    other;
      run_reporting(opts: def);
  endsl;

  return true;

end-proc;

//==============================================================================
// run_reporting
//==============================================================================

dcl-proc run_reporting;
  dcl-pi *n;
    opts likeds(SCMAIN_OPTS_t) const;
    def  likeds(SCDEF_t) const;
  end-pi;

  select;
    when opts.operation = 'info';
      SCEXEC_info(def);
    when opts.operation = 'file';
      SCEXEC_file(def);
    when opts.operation = 'jobinfo';
      SCEXEC_jobinfo(def);
    when opts.operation = 'loginfo';
      SCEXEC_loginfo(def);
    when opts.operation = 'perfinfo';
      SCEXEC_perfinfo(def);
    when opts.operation = 'scrunattrs';
      SCEXEC_scrunattrs(def);
  endsl;

end-proc;
