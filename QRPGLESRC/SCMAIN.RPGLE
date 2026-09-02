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

// The group a bare operation implicitly acts on, and the name upstream uses
// when it reports that the operation matched nothing.
dcl-c SCMAIN_GROUP_ALL const('all');

dcl-pr next_token like(SCMAIN_ARGS_t);
  rest like(SCMAIN_ARGS_t);
end-pr;

dcl-pr warn_if_empty;
  shown like(INTEGER_t) const;
  group like(SCDEF_NAME_t) const;
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
  dcl-pi *n like(INTEGER_t);
    args like(SCMAIN_ARGS_t) const;
    opts likeds(SCMAIN_OPTS_t);
  end-pi;

  dcl-s rest      like(SCMAIN_ARGS_t);
  dcl-s word      like(SCMAIN_ARGS_t);
  dcl-s eq        like(INTEGER_t);
  dcl-s refused   like(BOOLEAN_t) inz(false);

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
      // An explicit refusal, and it is final. The wrapper APPENDS --colors
      // when stdout is a terminal, after whatever the user typed, so plain
      // last-wins would turn colour back on every time somebody asked for it
      // off - and a terminal is the only place anyone would ever ask, since
      // colour is off everywhere else.
      when word = '--disable-colors' or word = '--disable-colours';
        opts.colours = false;
        refused = true;
      // Not an upstream flag. Upstream decides by asking whether stdout is a
      // terminal; RMSC cannot ask that from ILE, so whatever CAN ask - the
      // PASE wrapper, with [ -t 1 ] - says so explicitly. It states what the
      // environment supports, which is a default, and a default does not
      // overrule someone who said no.
      when word = '--colors' or word = '--colours';
        if not refused;
          opts.colours = true;
        endif;
      when word = '--splf';
        opts.splf = true;
      when word = '--ignore-globals';
        opts.ignore_globals = true;
      // Applied here rather than after the loop, because upstream applies it
      // where it appears: it clears the group exclusions AND turns
      // --ignore-globals back off, so '--ignore-globals --all' loads globals
      // and '--all --ignore-globals' does not. Deferring it to the end makes
      // the two forms behave the same, and only one of them is right.
      when word = '-a' or word = '--all';
        opts.all = true;
        opts.ignore_globals = false;
        opts.ignore_groups = '';
      when %len(word) > 16 and %subst(word: 1: 16) = '--ignore-groups=';
        opts.ignore_groups = %subst(word: 17);
      when %len(word) > 13 and %subst(word: 1: 13) = '--sampletime=';
        opts.sampletime = %subst(word: 14);

      when %len(word) > 1 and %subst(word: 1: 1) = '-';
        opts.err = 'Unknown option ' + %trim(word);
        return SCMAIN_EXIT_USAGE;

      when %len(%trim(opts.operation)) = 0;
        if not is_operation(word);
          opts.err = 'Unknown operation ' + %trim(word);
          return SCMAIN_EXIT_USAGE;
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
        return SCMAIN_EXIT_USAGE;
    endsl;
  enddo;

  if %len(%trim(opts.operation)) = 0;
    opts.err = 'No operation given';
    return SCMAIN_EXIT_USAGE;
  endif;

  return SCMAIN_EXIT_OK;

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
// warn_if_empty
//   Upstream's warning when an operation displayed nothing
//
// Emitted on standard error, and the operation still succeeds. Matching
// nothing is not a failure - it is an empty group, an empty collection, or
// exclusions that removed everything, and upstream treats all three the same.
//==============================================================================

dcl-proc warn_if_empty;
  dcl-pi *n;
    shown like(INTEGER_t) const;
    group like(SCDEF_NAME_t) const;
  end-pi;

  if shown > 0;
    return;
  endif;

  SCOUT_warnln(SCOUT_no_services_warning(group));

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
  dcl-pi *n like(INTEGER_t);
    opts likeds(SCMAIN_OPTS_t);
  end-pi;

  dcl-ds coll likeds(SCCOLL_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-s err   like(SCEXEC_ERR_t);
  dcl-s i     like(INTEGER_t);
  dcl-s group like(SCDEF_NAME_t);
  dcl-s acted like(BOOLEAN_t) inz(false);
  dcl-s shown    like(INTEGER_t);
  dcl-s unusable like(INTEGER_t) inz(0);
  dcl-s bad      like(BOOLEAN_t) inz(false);
  dcl-s j        like(INTEGER_t);
  dcl-ds conflicts likeds(SCCOLL_CONFLICTS_t) inz(*likeds);
  dcl-ds cdef      likeds(SCDEF_t) inz(*likeds);

  // Anything the parse stage had to say has been said by now. Left in place
  // it would be reported a second time when this stage returns, which is the
  // doubled-message fault the status contract exists to remove.
  opts.err = '';

  SCOUT_set_colour(opts.colours);

  SCCOLL_load(coll: opts.ignore_globals);

  // A definition that failed to load is reported but does not stop the rest
  // being managed. Under -q it is suppressed, which is what quiet is for.
  if not opts.quiet;
    for i = 1 to coll.bad_count;
      SCOUT_writeln('WARNING: ' + %trim(coll.bad_name(i)) + ': ' +
                    %trim(coll.bad_err(i)));
    endfor;

    // Two services claiming one criterion. Reported on every operation, as
    // upstream does - it is a property of the collection, not of whatever is
    // being asked of it.
    //
    // On stderr, which is where upstream puts it and where a warning belongs:
    // stdout is parsed by column position by the consumer. The load failures
    // immediately above still go to stdout, which is wrong for the same
    // reason and is the separate piece of work recorded as D4 - not folded in
    // here, because moving those is a change to output that is byte-compared
    // and deserves its own diff.
    if SCCOLL_conflicts(coll: conflicts) > 0;
      for i = 1 to conflicts.count;
        SCOUT_warnln('WARNING: the following services all have conflicting ' +
                     'definitions for liveliness check ''' +
                     %trim(conflicts.item(i).criterion) + ''':');

        for j = 1 to conflicts.item(i).count;
          if SCCOLL_find(coll: conflicts.item(i).name(j): cdef);
            SCOUT_warnln('    ' + %trim(cdef.short_name) +
                         ' (' + %trim(cdef.friendly) + ')');
          endif;
        endfor;
      endfor;
    endif;
  endif;

  // Operations over the whole collection
  select;
    when opts.operation = 'groups';
      SCEXEC_groups(coll: opts.ignore_groups: opts.ignore_globals);
      return SCMAIN_EXIT_OK;

    when opts.operation = 'list' and %len(%trim(opts.spec)) = 0;
      shown = SCEXEC_list(coll: opts.ignore_groups);
      warn_if_empty(shown: SCMAIN_GROUP_ALL);
      return SCMAIN_EXIT_OK;

    // A bare 'check', which is how a caller asks for everything
    when opts.operation = 'check'
     and (%len(%trim(opts.spec)) = 0 or STRING_lower(opts.spec) = 'all');
      shown = SCEXEC_check_all(coll: opts.ignore_groups: unusable);
      // Nothing found at all is a different thing from services found and
      // not checkable: upstream warns about the first and says nothing
      // further about the second, having already named each one.
      if unusable = 0;
        warn_if_empty(shown: SCMAIN_GROUP_ALL);
      endif;
      if unusable > 0;
        // Reported as it went, in each service's own place. opts.err stays
        // empty so SCRUN exits without adding a word.
        return SCMAIN_EXIT_FAILED;
      endif;
      return SCMAIN_EXIT_OK;
  endsl;

  // group:NAME applies the operation to every member
  if %len(opts.spec) > 6 and STRING_lower(%subst(opts.spec: 1: 6)) = 'group:';
    group = STRING_lower(%subst(opts.spec: 7));

    // Listing a group is the whole-collection listing restricted to it, not a
    // per-service dispatch. Routed here because the loop below has no case
    // for it: every member was visited and none was printed, so 'list
    // group:NAME' produced nothing at all.
    if opts.operation = 'list';
      shown = SCEXEC_list(coll: opts.ignore_groups: group);
      warn_if_empty(shown: group);
      return SCMAIN_EXIT_OK;
    endif;

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

    // check closes its output with a blank line here just as it does over the
    // whole collection. Confirmed against sc 1.7.1 for both a populated group
    // and an empty one; the state-changing operations are left alone, since
    // nothing has been checked about them. list never reaches this point -
    // SCEXEC_list writes its own trailing blank line.
    if opts.operation = 'check';
      SCOUT_writeln('');
    endif;

    // Upstream warns and exits 0 here rather than failing: an empty group is
    // not an error, it is a group with nothing in it. RMSC raised an error
    // with different wording and a non-zero status, which a caller checking
    // the exit code would read as a failure to do the work.
    if not acted;
      SCOUT_warnln(SCOUT_no_services_warning(group));
    endif;
    return SCMAIN_EXIT_OK;
  endif;

  // Everything else needs one named service
  if %len(%trim(opts.spec)) = 0;
    // Upstream treats a missing service as a USAGE failure, not a failed
    // operation: 'sc info' with no service prints the usage line and exits
    // 255. Measured across all ten operations that require one.
    opts.err = 'Operation ' + %trim(opts.operation) + ' needs a service';
    return SCMAIN_EXIT_USAGE;
  endif;

  if not resolve_one(opts: coll: def);
    return SCMAIN_EXIT_FAILED;
  endif;

  select;
    when opts.operation = 'check';
      SCEXEC_check(def: bad);
      if bad;
        // No row was printed and no blank follows one - upstream leaves
        // stdout completely empty when it cannot check the service it was
        // asked about.
        return SCMAIN_EXIT_FAILED;
      endif;
      // Naming one service ends with a blank line just as checking them all
      // does. Nothing compared this until 'check' joined the gate's live
      // differential: stage 1 diffs a BARE check, which takes the other path
      // entirely, so a named check had never been run against upstream.
      SCOUT_writeln('');
    when opts.operation = 'start';
      if not SCEXEC_start(coll: def.short_name: err);
        opts.err = err;
        return SCMAIN_EXIT_FAILED;
      endif;
    when opts.operation = 'stop';
      if not SCEXEC_stop(coll: def.short_name: false: err);
        opts.err = err;
        return SCMAIN_EXIT_FAILED;
      endif;
    when opts.operation = 'kill';
      if not SCEXEC_stop(coll: def.short_name: true: err);
        opts.err = err;
        return SCMAIN_EXIT_FAILED;
      endif;
    when opts.operation = 'restart';
      if not SCEXEC_restart(coll: def.short_name: err);
        opts.err = err;
        return SCMAIN_EXIT_FAILED;
      endif;
    when opts.operation = 'list';
      SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
    other;
      run_reporting(opts: def);
  endsl;

  return SCMAIN_EXIT_OK;

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
