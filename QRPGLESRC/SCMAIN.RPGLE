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

dcl-pr run_changing like(BOOLEAN_t);
  opts likeds(SCMAIN_OPTS_t) const;
  coll likeds(SCCOLL_t);
  name like(SCDEF_NAME_t) const;
  err  like(SCEXEC_ERR_t);
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

  // CLEAR sets a structure to zeros and blanks, NOT to its inz() values, so
  // every default has to be restated here. SCMAIN_OPTS_t.sample_secs carries
  // inz(1) and that is not what survives this line - the default window went
  // to zero the moment the conversion moved into the parse loop, and no value
  // anybody types could show it, because every explicit value still parsed
  // correctly. Only the absent-option path was wrong. It is the same reason
  // SCDEF_clear exists rather than a CLEAR on SCDEF_t.
  clear opts;
  opts.ignore_groups = SCMAIN_DFT_IGNORE;
  opts.sampletime = '1';
  opts.sample_secs = 1;

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
      // >= 16, not > 16. `--ignore-groups=` with an EMPTY value is meaningful
      // - it clears the default `system` exclusion, and upstream treats it as
      // equivalent to -a: measured, 36 rows against 4 for a bare `list`. At
      // `> 16` the empty form is exactly 16 characters, misses this branch
      // entirely and falls through to `Unknown option`, so RMSC refused a
      // form upstream accepts.
      //
      // Worth knowing WHY this is here rather than in its own change: a guard
      // written as "the value must be between 1 and 512 characters" would
      // have cemented that bug rather than exposed it. The test author found
      // it while writing the controls for the guard and reported it as a
      // separate failing case rather than folding it into one that was
      // already red.
      when %len(word) >= 16 and %subst(word: 1: 16) = '--ignore-groups=';
        // Checked BEFORE the assignment, because the assignment is the
        // truncation. A list longer than the holder was silently cut, and the
        // groups named in the tail were then NOT excluded - so services the
        // caller asked to hide appeared. Every other field of this class was
        // fixed by sizing the holder to its source; that cannot work here,
        // because the source is a list of n names and there is no n.
        if %len(word) - 16 > SCDEF_NAME_MAX;
          opts.err = 'Value for --ignore-groups is longer than ' +
                     %char(SCDEF_NAME_MAX) + ' characters';
          return SCMAIN_EXIT_USAGE;
        endif;
        // %SUBST rejects a start position beyond the string rather than
        // returning an empty one - the same trap that abended on a trailing
        // comma in `--ignore-groups=web,` and was fixed in 031b524.
        if %len(word) = 16;
          opts.ignore_groups = '';
        else;
          opts.ignore_groups = %subst(word: 17);
        endif;
      when %len(word) >= 13 and %subst(word: 1: 13) = '--sampletime=';
        // `>= 13`, so an EMPTY --sampletime= reaches the value parse. It was
        // `> 13` on the stated grounds that the empty form had no measured
        // meaning upstream. It has one, measured 8 September 2026: upstream
        // warns that the value is not valid, falls back to one second and
        // exits 0. At `> 13` RMSC answered `Unknown option --sampletime=`
        // with status 255 - a different class of answer entirely.
        if %len(word) - 13 > SCDEF_NAME_MAX;
          opts.err = 'Value for --sampletime is longer than ' +
                     %char(SCDEF_NAME_MAX) + ' characters';
          return SCMAIN_EXIT_USAGE;
        endif;
        // The same %SUBST guard as --ignore-groups above, and it has to move
        // in step with the threshold: relaxing `> 13` to `>= 13` is exactly
        // what makes an empty value reach this line, and %SUBST rejects a
        // start position past the end rather than returning an empty string.
        // Changed the threshold without copying the guard three lines up, and
        // it abended with RNX0100 on `--sampletime=`.
        if %len(word) = 13;
          opts.sampletime = '';
        else;
          opts.sampletime = %subst(word: 14);
        endif;
        // Converted HERE, not where perfinfo uses it, and the warning goes
        // out from here too. That is what makes `-q --sampletime=abc` silent
        // and `--sampletime=abc -q` not: the quiet flag is whatever the parse
        // has seen so far. Measured against upstream, both orders.
        opts.sample_secs = sample_seconds(opts.sampletime: opts.quiet);

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
  // The specifier's value AS TYPED. `value` is upper-cased for the job form,
  // correctly - the criterion is matched upper-cased. The ad-hoc service's
  // NAME must not follow it: upstream preserves the case the user typed.
  dcl-s typed like(SCMAIN_SPEC_t);
  dcl-s adhoc_port like(INTEGER_t);
  dcl-s adhoc_norm like(SCDEF_CRIT_t);
  dcl-s slash like(INTEGER_t);

  // Assigned, not cleared: CLEAR would leave 'enabled' *off, so every ad-hoc
  // port:, job: and PGM- spec would be a disabled definition the moment
  // anything reads that field. Harmless today because only the loader reads
  // it, which is exactly what makes it worth removing now rather than later.
  SCDEF_clear(def);
  work = %trim(spec);

  if %len(work) > 5 and STRING_lower(%subst(work: 1: 5)) = 'port:';
    value = %subst(work: 6);
    // Upstream's naming, matched deliberately even though RMSC's was arguably
    // better: `scr check port:22` used to print a name that could be fed back
    // in, where upstream's `ad_hoc_port_22` cannot. Richard's decision, 10
    // September 2026 - on existing functionality RMSC aims for parity unless
    // there is a good reason not to, and "ours is better" is not one.
    // docs/parity.md carries the measured table and the argument.
    def.short_name = 'ad_hoc_port_' + %trim(value);
    def.friendly   = 'Ad hoc service running at port ' + %trim(value);
    def.criteria_count = 1;
    def.criteria(1).kind = SCDEF_CHECK_PORT;
    def.criteria(1).raw  = value;
    // Converted ONLY when the text is usable, and both halves matter.
    //
    // The first attempt at this deleted the conversion outright, reasoning
    // that leaving `.port` at zero would route the criterion into SCEXEC's
    // unusable handling. That is true for an unusable value and FALSE for a
    // good one: SCDEF_criterion_usable inspects `raw` alone, so `port:22`
    // stayed usable, kept a zero port, and probed port 0. Every ad-hoc port
    // check reported NOT RUNNING, including ones that were genuinely up.
    //
    // It survived a full test run because every case aimed at this line used
    // a value that reports NOT RUNNING whether the code is right or wrong -
    // port:-1, port:65536, port:abc. A listening port is the case where the
    // fix and the break disagree, and nothing had asked for one.
    //
    // The line it replaced was `.port = %int(value)` with no check of any
    // kind, so every unusable ad-hoc port brought the whole command down:
    //
    //     scr check port:abc             CEE9901 RNX0105
    //     scr check port:4294967296      CEE9901 MCH1210
    //     scr check port:99999999999999  CEE9901 MCH1210
    //
    // where upstream exits 253 with 'Invalid data for port number or job name
    // criteria for service ...: PORT:<raw>'. Leaving `.port` at zero routes
    // the criterion into SCEXEC's existing unusable handling, which already
    // produces that message verbatim - so nothing new is written to report it,
    // and the ad-hoc path now answers the same way the companion form does.
    //
    // port:-1 and port:65536 stay usable and report NOT RUNNING, as upstream
    // does. Measured. They are the pair that rules out a 1..65535 range check,
    // which is the wrong rule this could easily have been fixed into.
    // Validated, converted and normalised from ONE string - the whole spec,
    // not the truncated copy kept for display. See SCDEF_port_text.
    if SCDEF_port_text(value: adhoc_port: adhoc_norm);
      def.criteria(1).port = adhoc_port;
    endif;

    // `raw` is taken from the normalised text WHETHER OR NOT the value was
    // usable, and that half matters as much as the conversion. Keeping the
    // spec verbatim here left 128 leading zeros in a 128-wide field, which
    // strip to '0' and read back as a perfectly usable port 0 - so an
    // unusable value reported NOT RUNNING against port 0 instead of the
    // error upstream gives. The normalised text is computed before usability
    // is decided precisely so it is available on both paths.
    if adhoc_norm <> '';
      def.criteria(1).raw = adhoc_norm;
    endif;
    return true;
  endif;

  if %len(work) > 4 and STRING_lower(%subst(work: 1: 4)) = 'job:';
    typed = %subst(work: 5);
    value = STRING_upper(typed);
    // THREE things here, and each is separately easy to get wrong.
    //
    // The name is built from `typed`, not `value`: upstream preserves case,
    // so `job:qinter` is `ad_hoc_job_qinter`. RMSC used to name it from the
    // upper-cased criterion and printed `job:QINTER`.
    //
    // The SLASH is translated in the NAME and NOT in the description -
    // `job:QUSRWRK/QINTER` gives `ad_hoc_job_QUSRWRK_QINTER` described as
    // `at job QUSRWRK/QINTER`. Built from one string, one of the two is
    // wrong whichever string is chosen.
    //
    // `value` stays upper-cased for the criterion below. That is not a
    // casualty of this change; it is why the two are now separate.
    def.short_name = 'ad_hoc_job_' + %xlate('/': '_': %trim(typed));
    def.friendly   = 'Ad hoc service running at job ' + %trim(typed);
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
    // WITH the prefix. `raw` is what SCDEF_criterion_text renders and what
    // conflict detection compares, and the same program named in a FILE keeps
    // it - `check_alive: PGM-X` renders JOBNAME:PGM-X, which is upstream's
    // form. Storing the bare name here made RMSC disagree with itself:
    //
    //     ad-hoc PGM-X   ->  JOBNAME:X          (this line, before)
    //     file   PGM-X   ->  JOBNAME:PGM-X      (upstream's form)
    //
    // The display half is cosmetic; the other half is not. Two criteria are
    // the same criterion when their raw text matches, so an ad-hoc PGM-X was
    // treated as claiming what a service whose JOB NAME is X claims.
    //
    // `program` stays bare - that is the value the query needs.
    def.criteria(1).raw  = 'PGM-' + %trim(value);
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

  // Decided BEFORE the load, because upstream decides it before it reads
  // anything: 'sc info' with no service prints usage, exits 255 and leaves
  // stdout EMPTY even when a definition on disk will not load. Deciding it
  // afterwards meant RMSC announced a broken definition on stdout - the
  // stream a column-parsing consumer reads - for a command that never ran.
  //
  // groups, list and check are the operations that describe the whole
  // collection, so an absent service is ordinary for those three and a usage
  // failure for every other.
  if %len(%trim(opts.spec)) = 0
     and opts.operation <> 'groups'
     and opts.operation <> 'list'
     and opts.operation <> 'check';
    opts.err = 'Operation ' + %trim(opts.operation) + ' needs a service';
    return SCMAIN_EXIT_USAGE;
  endif;

  // quiet reaches the loader because the warnings found during the walk are
  // emitted there, where the 'if not opts.quiet' block below cannot see them.
  SCCOLL_load(coll: opts.ignore_globals: opts.quiet);

  // A definition that failed to load is reported but does not stop the rest
  // being managed. Under -q it is suppressed, which is what quiet is for.
  if not opts.quiet;
    // On stderr, where upstream puts them. A load warning on stdout is a
    // non-row line on the stream the consumer parses by column position -
    // dropped if it is lucky, misread if it is not.
    for i = 1 to coll.bad_count;
      SCOUT_warnln('WARNING: ' + %trim(coll.bad_name(i)) + ': ' +
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
        when opts.operation = 'start' or opts.operation = 'stop'
          or opts.operation = 'kill' or opts.operation = 'restart';
          // Each member's failure goes to stderr, as upstream's does. The
          // exit status is NOT changed with it: upstream exits 0 from a group
          // operation even when every member fails, and RMSC already matches.
          // That half looks like a defect and is not.
          //
          // SCEXEC reports every failure itself now, on stderr, so nothing
          // is printed here. err is still SET, for a caller that has no
          // stream to read - see SCAPI.
          SCOUT_writeln(SCOUT_op_progress(opts.operation: def.short_name));
          run_changing(opts: coll: def.short_name: err);
        other;
          run_reporting(opts: def);
      endsl;
    endfor;

    // check closes its output with a blank line here just as it does over the
    // whole collection. Confirmed against sc 1.7.1 for both a populated group
    // and an empty one; the state-changing operations are left alone, since
    // nothing has been checked about them. list never reaches this point -
    // SCEXEC_list writes its own trailing blank line.
    //
    // loginfo joins it, and the way that was got wrong is the reason this
    // comment is worth reading. Its blank line was first emitted inside
    // SCEXEC_loginfo, per service, because the measurement had been taken on
    // a single named service - where per-service and per-command cannot be
    // told apart. On a two-member group upstream printed ONE blank and RMSC
    // printed TWO. Anything measured only on a named service should be
    // checked against a group before it is believed.
    if opts.operation = 'check' or opts.operation = 'loginfo'
       or opts.operation = 'jobinfo';
      SCOUT_writeln('');
    endif;

    // A state-changing command ends with one blank line however many members
    // it touched - per COMMAND, where the errors on stderr are per ERROR.
    // Measured; the asymmetry is upstream's.
    if acted and (opts.operation = 'start' or opts.operation = 'stop'
               or opts.operation = 'kill'  or opts.operation = 'restart');
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

  // Everything else needs one named service.
  //
  // A backstop rather than the decision: the same test now runs before the
  // load, so that a usage failure prints nothing on stdout for a command that
  // never ran. Nothing should reach here with an empty spec - groups, list and
  // check are answered above, and every other operation was turned away
  // earlier - but the two tests must stay in step, and a wrong answer here is
  // an exit status rather than a crash.
  if %len(%trim(opts.spec)) = 0;
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
    when opts.operation = 'start' or opts.operation = 'stop'
      or opts.operation = 'kill' or opts.operation = 'restart';
      SCOUT_writeln(SCOUT_op_progress(opts.operation: def.short_name));
      if not run_changing(opts: coll: def.short_name: err);
        // NO trailing blank here. Upstream prints it only when the command
        // EXITS 0 - measured across five failure shapes after a first
        // implementation printed it on both paths. A group command always
        // exits 0, which is why "one blank per command" fitted every
        // observation until a failing single-service command was looked at.
        //
        // opts.err is left EMPTY: SCEXEC has already reported the failure, in
        // upstream's words and on upstream's streams. SCRUN's contract - a
        // non-zero exit with no message is a failure that has reported itself.
        return SCMAIN_EXIT_FAILED;
      endif;
      SCOUT_writeln('');
    when opts.operation = 'list';
      SCOUT_writeln(SCOUT_list_row(def.short_name: def.friendly));
    other;
      run_reporting(opts: def);
      // The same trailer as the group path above, for the single-service
      // form. Both paths need it because neither reaches the other.
      if opts.operation = 'loginfo' or opts.operation = 'jobinfo';
        SCOUT_writeln('');
      endif;
  endsl;

  return SCMAIN_EXIT_OK;

end-proc;

//==============================================================================
// run_changing
//   start / stop / kill / restart, dispatched one way for both callers
//
// One procedure rather than four branches duplicated between the group loop
// and the single-service path. The narration made the duplication expensive:
// the progress line, the failure handling and the trailing blank all had to
// agree across eight places, and CLAUDE.md records what four copies of one
// splitter cost when only one of them learned about quotes.
//==============================================================================

dcl-proc run_changing;
  dcl-pi *n like(BOOLEAN_t);
    opts likeds(SCMAIN_OPTS_t) const;
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
    err  like(SCEXEC_ERR_t);
  end-pi;

  select;
    when opts.operation = 'start';
      return SCEXEC_start(coll: name: err);
    when opts.operation = 'stop';
      return SCEXEC_stop(coll: name: false: err);
    when opts.operation = 'kill';
      return SCEXEC_stop(coll: name: true: err);
    when opts.operation = 'restart';
      return SCEXEC_restart(coll: name: err);
  endsl;

  // Unreachable: both callers test the operation before calling. A false with
  // no message would exit non-zero saying nothing, so say something.
  err = 'Operation ' + %trim(opts.operation) + ' is not state-changing';
  return false;

end-proc;

//==============================================================================
// run_reporting
//==============================================================================

// --sampletime arrives as text and reaches perfinfo as a number of seconds.
//
// Measured against upstream 1.7.1 on 8 September 2026, because every part of
// this is somebody's expectation:
//
//   --sampletime=2.5    honoured; a 2.55s window per job
//   --sampletime=0.25   honoured; sub-second windows work
//   --sampletime=0      accepted, and means do not wait
//   (absent)            1 second
//   --sampletime=abc    WARNING on stderr naming the whole argument, then 1
//   --sampletime=       the same warning, then 1
//   -q                  suppresses that warning entirely
//
// So a whole number will not do, which is what this returned before: the
// documented form of the option is `x.x` and RMSC was discarding it in
// silence and sampling for one second instead.
//
// The one departure is a NEGATIVE value. Upstream takes it as a number and
// then fails to gather anything, printing "Unable to retrieve performance
// data for job ..." per job - its own sampling code breaking on a negative
// sleep. RMSC accepts it without a warning, as upstream does, and clamps the
// window to zero, so a report still comes out. Recorded in docs/parity.md;
// reproducing a crash faithfully is not parity worth having.
dcl-proc sample_seconds;
  dcl-pi *n like(SCQRY_SECS_t);
    text  like(SCDEF_NAME_t) const;
    quiet like(BOOLEAN_t) const;
  end-pi;

  dcl-c SAMPLE_DEFAULT 1;
  dcl-s work   varchar(32);
  dcl-s i      like(INTEGER_t);
  dcl-s c      char(1);
  dcl-s dots   like(INTEGER_t) inz(0);
  dcl-s dot_at like(INTEGER_t) inz(0);
  dcl-s from   like(INTEGER_t) inz(1);
  dcl-s digits like(INTEGER_t) inz(0);
  dcl-s sign   varchar(1) inz('');
  dcl-s whole  varchar(32);
  dcl-s frac   varchar(32);

  work = %trim(text);

  if %len(work) = 0;
    return invalid_sample(text: quiet: SAMPLE_DEFAULT);
  endif;

  if %subst(work: 1: 1) = '-' or %subst(work: 1: 1) = '+';
    sign = %subst(work: 1: 1);
    from = 2;
  endif;

  for i = from to %len(work);
    c = %subst(work: i: 1);
    if c = '.';
      dots += 1;
      dot_at = i;
    elseif c >= '0' and c <= '9';
      digits += 1;
    else;
      return invalid_sample(text: quiet: SAMPLE_DEFAULT);
    endif;
  endfor;

  // '.', '..', '1.2.3' and a bare sign are all not numbers.
  if dots > 1 or digits = 0;
    return invalid_sample(text: quiet: SAMPLE_DEFAULT);
  endif;

  // %SUBST past the end of a string is an ABEND, not an empty result, and
  // both ends of a decimal point can be past it. This is the FOURTH time that
  // trap has been sprung in this one procedure in a single afternoon - after
  // an empty --sampletime=, and twice more in guards written to prevent it.
  // `.5` has an empty integer part and `2.` an empty fraction; upstream reads
  // the first as 0.5 and the second as 2.0, so both are numbers and neither
  // may crash.
  if dots = 0;
    whole = %subst(work: from);
    frac  = '';
  else;
    if dot_at > from;
      whole = %subst(work: from: dot_at - from);
    else;
      whole = '0';
    endif;
    if dot_at < %len(work);
      frac = %subst(work: dot_at + 1);
    else;
      frac = '';
    endif;
  endif;

  // Leading zeros are not significant, so 00000001.5 is one integer digit and
  // not eight.
  dow %len(whole) > 1 and %subst(whole: 1: 1) = '0';
    whole = %subst(whole: 2);
  enddo;
  if %len(whole) = 0;
    whole = '0';
  endif;

  // COUNT WHAT THE RECEIVER HOLDS, not characters. SCQRY_SECS_t is
  // packed(10:3): seven digits before the point and three after. An earlier
  // version guarded on the length of the whole string at eleven, which admits
  // `9999999999` - ten integer digits - and abends on the conversion with
  // RNX0103. That is the THIRD time this project has written a width guard
  // against the wrong width, after usable_port at nineteen digits and this
  // same procedure at ten. The lesson each time is identical: a guard has to
  // be expressed in the units of the thing it protects.
  if %len(whole) > 7;
    return invalid_sample(text: quiet: SAMPLE_DEFAULT);
  endif;

  // More precision than the field carries is TRUNCATED, not refused. Upstream
  // accepts such a value, and refusing one it accepts would be a divergence
  // invented by a guard rather than measured.
  if %len(frac) > 3;
    frac = %subst(frac: 1: 3);
  endif;

  if %len(frac) = 0;
    return %dec(sign + whole: 10: 3);
  endif;

  return %dec(sign + whole + '.' + frac: 10: 3);

end-proc;

// Upstream's wording, captured verbatim, and it names the WHOLE argument
// rather than just the value. -q suppresses it, measured.
dcl-proc invalid_sample;
  dcl-pi *n like(SCQRY_SECS_t);
    text     like(SCDEF_NAME_t) const;
    quiet    like(BOOLEAN_t) const;
    fallback like(SCQRY_SECS_t) const;
  end-pi;

  if not quiet;
    SCOUT_warnln('WARNING: Value specified for sample time argument is ' +
                 'not valid: --sampletime=' + %trimr(text));
  endif;

  return fallback;

end-proc;

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
      SCEXEC_perfinfo(def: opts.sample_secs);
    when opts.operation = 'scrunattrs';
      SCEXEC_scrunattrs(def);
  endsl;

end-proc;
