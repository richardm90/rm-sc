**free

//==============================================================================
// SCOUT      - Output formatting
//
// The 'check' row layout is an interface, not a presentation choice. At least
// one consumer parses it by column position: status from columns 1-20, the
// name between the bar and the opening parenthesis, the description inside the
// parentheses. A row that does not yield all three is silently dropped by that
// consumer, so a formatting slip makes services disappear from a screen rather
// than raising anything.
//
// Two consequences shape this module:
//
//   - the no-colour row is byte-identical to upstream, and is pinned by tests
//     that parse it the way the consumer does;
//   - colour is emitted only when standard output is a terminal, because an
//     ANSI escape sequence would otherwise land inside the status columns.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Output formatting');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCOUT_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// C runtime
///

dcl-pr c_printf extproc('printf');
  fmt  pointer value options(*string);
  arg1 pointer value options(*string: *nopass);
end-pr;

// Warnings go to a descriptor rather than through printf, because printf
// writes to standard output and that is precisely where they must not go.
// Flushing stdout before anything is written to stderr. Without it the two
// streams arrive out of order on a terminal: printf is buffered and flushed at
// exit, write(2) is not. It never showed before narration, because the failure
// path put nothing on stdout - there was nothing to interleave. No harness can
// see it either, since every one of them captures the streams to separate
// files, which discards the ordering.
dcl-pr c_fflush int(10) extproc('fflush');
  stream pointer value;
end-pr;

dcl-pr c_write int(10) extproc('write');
  fd    int(10) value;
  buf   pointer value;
  bytes uns(10) value;
end-pr;

dcl-c STDERR_FD const(2);

// EBCDIC newline as the C runtime writes it to stdout here
dcl-c NL const(x'25');

///
// ANSI colour. Applied to the padded status only, so the visible column
// positions are identical with colour on or off.
///

dcl-c ESC        const(x'27');
dcl-c ANSI_RESET const('[0m');
dcl-c ANSI_GREEN const('[32m');
dcl-c ANSI_RED   const('[31m');
dcl-c ANSI_AMBER const('[33m');

///
// Colour state. OFF unless switched on explicitly - see SCOUT_is_tty.
///

dcl-s g_colour like(BOOLEAN_t) inz(false);

// Whether anything is written at all. Off by default, so the command line is
// unaffected and this can only ever be turned on deliberately.
//
// It exists for SCAPI, whose header promises that a green-screen caller will
// not find stray text under its display file. Narration made that promise
// false: the lines are emitted from SCEXEC, which both entry points share.
// The rule this restores is "RMSC prints when a human is watching" rather
// than "RMSC prints whenever this code runs".
dcl-s g_silent like(BOOLEAN_t) inz(false);

dcl-pr colour_for like(SCOUT_LINE_t);
  status like(SCOUT_STATUS_t) const;
end-pr;

//==============================================================================
// SCOUT_check_row
//==============================================================================

dcl-proc SCOUT_check_row export;
  dcl-pi *n like(SCOUT_LINE_t);
    status like(SCOUT_STATUS_t) const;
    name   like(SCOUT_LINE_t) const;
    desc   like(SCOUT_LINE_t) const;
    suffix like(SCOUT_LINE_t) const options(*nopass);
  end-pi;

  dcl-s padded like(SCOUT_LINE_t);
  dcl-s field  like(SCOUT_LINE_t);
  dcl-s row    like(SCOUT_LINE_t);

  // Left-justified in a fixed-width field. %trimr then explicit padding, so a
  // status longer than the field widens the row rather than being cut - a
  // truncated status would still parse, and would parse wrongly.
  padded = %trimr(status);
  dow %len(padded) < SCOUT_STATUS_WIDTH;
    padded += ' ';
  enddo;

  if SCOUT_colour();
    field = %trim(colour_for(status)) + padded + ESC + ANSI_RESET;
  else;
    field = padded;
  endif;

  row = '  ' + field + ' | ' + %trim(name) + ' (' + %trim(desc) + ') ';

  // Appended AFTER the trailing space, so the row itself is byte-for-byte
  // what it has always been and only a partial service's line ends with ']'.
  if %parms() >= 4 and %addr(suffix) <> *null
     and %len(%trim(suffix)) > 0;
    row += %trim(suffix);
  endif;

  return row;

end-proc;

//==============================================================================
// colour_for
//   Green running, red stopped, amber anything else
//==============================================================================

dcl-proc colour_for;
  dcl-pi *n like(SCOUT_LINE_t);
    status like(SCOUT_STATUS_t) const;
  end-pi;

  select;
    when %trimr(status) = SCOUT_RUNNING;
      return ESC + ANSI_GREEN;
    when %trimr(status) = SCOUT_NOT_RUNNING;
      return ESC + ANSI_RED;
    other;
      return ESC + ANSI_AMBER;
  endsl;

end-proc;

//==============================================================================
// SCOUT_list_row
//==============================================================================

dcl-proc SCOUT_list_row export;
  dcl-pi *n like(SCOUT_LINE_t);
    name like(SCOUT_LINE_t) const;
    desc like(SCOUT_LINE_t) const;
  end-pi;

  return %trim(name) + ' (' + %trim(desc) + ')';

end-proc;

//==============================================================================
// SCOUT_is_tty
//==============================================================================

// There is no reliable way to ask this from ILE. isatty is not exported by
// the C runtime here, and job type is actively the wrong signal: a consumer
// that runs interactively and pipes 'check' into a parser would be told it
// has a terminal, and escape sequences would land in the status columns.
//
// So the answer is always false, and colour is off unless something that CAN
// tell - the PASE wrapper, with [ -t 1 ] - switches it on.
dcl-proc SCOUT_is_tty export;
  dcl-pi *n like(BOOLEAN_t) end-pi;

  return false;

end-proc;

//==============================================================================
// SCOUT_set_colour
//==============================================================================

dcl-proc SCOUT_set_colour export;
  dcl-pi *n;
    enabled like(BOOLEAN_t) const;
  end-pi;

  g_colour = enabled;

end-proc;

//==============================================================================
// SCOUT_colour
//==============================================================================

dcl-proc SCOUT_colour export;
  dcl-pi *n like(BOOLEAN_t) end-pi;

  return g_colour;

end-proc;

//==============================================================================
// SCOUT_set_silent / SCOUT_silent
//   Whether anything is written at all
//
// SAVE AND RESTORE AROUND A CALL, never set-on-entry-and-clear-on-exit:
//
//   was = SCOUT_silent();
//   SCOUT_set_silent(*on);
//   ...
//   SCOUT_set_silent(was);
//
// The flag is module state, so it lives for the ACTIVATION and not the call.
// Clearing it unconditionally on the way out un-silences at the first inner
// return - SC_restart calls SC_stop and SC_start, so the naive version stops
// being silent half way through itself. Saving and restoring nests correctly
// and makes "silent for this call" mean the call rather than the job.
//==============================================================================

dcl-proc SCOUT_set_silent export;
  dcl-pi *n;
    enabled like(BOOLEAN_t) const;
  end-pi;

  g_silent = enabled;

end-proc;

dcl-proc SCOUT_silent export;
  dcl-pi *n like(BOOLEAN_t);
  end-pi;

  return g_silent;

end-proc;

//==============================================================================
// SCOUT_writeln
//==============================================================================

dcl-proc SCOUT_writeln export;
  dcl-pi *n;
    line like(SCOUT_LINE_t) const;
  end-pi;

  if g_silent;
    return;
  endif;

  // %s rather than the line itself as the format string: a service name or
  // description carrying a percent sign would otherwise be read as a
  // conversion specifier.
  //
  // The line is NOT trimmed. The check row ends with a significant trailing
  // space, and trimming it here silently broke byte compatibility while every
  // format test still passed - the fault was in the writer, not the format.
  c_printf('%s' + NL: line);

end-proc;

//==============================================================================
// SCOUT_warnln
//   Write a line to standard error
//==============================================================================

dcl-proc SCOUT_warnln export;
  dcl-pi *n;
    line like(SCOUT_LINE_t) const;
  end-pi;

  dcl-s buf like(SCOUT_LINE_t);

  if g_silent;
    return;
  endif;

  // Order matters more than it looks. A reader on a terminal sees one
  // conversation, not two streams, and a progress line arriving after the
  // error it precedes reads as a different sequence of events. NULL flushes
  // every open output stream.
  c_fflush(*null);

  buf = line + NL;
  c_write(STDERR_FD: %addr(buf: *data): %len(buf));

end-proc;

//==============================================================================
// SCOUT_no_services_warning
//   Upstream's wording for an operation that matched nothing
//==============================================================================

dcl-proc SCOUT_no_services_warning export;
  dcl-pi *n like(SCOUT_LINE_t);
    group like(SCOUT_LINE_t) const;
  end-pi;

  // Upstream's wording, verbatim, quotes included
  return 'WARNING: No services are found in group ''' + %trim(group) + '''';

end-proc;

//==============================================================================
// SCOUT_partial_status
//==============================================================================

dcl-proc SCOUT_partial_status export;
  dcl-pi *n like(SCOUT_STATUS_t);
    alive like(INTEGER_t) const;
    total like(INTEGER_t) const;
  end-pi;

  return SCOUT_PARTIAL + ' (' + %char(alive) + '/' + %char(total) + ')';

end-proc;

//==============================================================================
// SCOUT_not_running_suffix
//==============================================================================

dcl-proc SCOUT_not_running_suffix export;
  dcl-pi *n like(SCOUT_LINE_t);
    joined like(SCOUT_LINE_t) const;
  end-pi;

  return '[not running at -->' + %trim(joined) + ']';

end-proc;

//==============================================================================
// SCOUT_invalid_criteria
//   Upstream's wording for a criterion that cannot be used
//==============================================================================

dcl-proc SCOUT_invalid_criteria export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly  like(SCOUT_LINE_t) const;
    criterion like(SCOUT_LINE_t) const;
  end-pi;

  // Upstream's wording, verbatim, quotes included
  return 'Invalid data for port number or job name criteria for service ''' +
         %trim(friendly) + ''': ' + %trim(criterion);

end-proc;


//==============================================================================
// NARRATION
//
// What upstream says while it is doing something. Every text here was captured
// from sc 1.7.1 on the box; docs/messages.md holds the captures and says which
// are measured and which are still composed. Read it before changing a byte.
//
// THE STREAMS ARE NOT UNIFORM, AND THAT IS UPSTREAM'S DOING. The progress
// line, the four states, both dependency lines and the log-file detail go to
// STDOUT. The partial-state line, the shortfall warning and both errors go to
// STDERR. The split is recorded at each procedure so it survives tidying.
//==============================================================================

//==============================================================================
// SCOUT_op_progress
//   Performing operation 'START' on service 'x'                        STDOUT
//==============================================================================

dcl-proc SCOUT_op_progress export;
  dcl-pi *n like(SCOUT_LINE_t);
    verb       like(SCOUT_LINE_t) const;
    short_name like(SCOUT_LINE_t) const;
  end-pi;

  // Upper-cased HERE rather than by each caller, so there is one place it can
  // be got wrong. The service is named by its SHORT name; every other line in
  // the family uses the friendly one. That asymmetry is measured, not a slip.
  return 'Performing operation ''' + STRING_upper(%trim(verb)) +
         ''' on service ''' + %trim(short_name) + '''';

end-proc;

//==============================================================================
// SCOUT_svc_state
//   Service 'Friendly' successfully started, and its three siblings    STDOUT
//==============================================================================

dcl-proc SCOUT_svc_state export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly like(SCOUT_LINE_t) const;
    state    like(SCOUT_STATE_t) const;
  end-pi;

  dcl-s tail like(SCOUT_LINE_t);

  select;
    when state = SCOUT_STARTED;
      tail = 'successfully started';
    when state = SCOUT_STOPPED;
      tail = 'successfully stopped';
    when state = SCOUT_ALREADY_RUNNING;
      tail = 'is already running';
    when state = SCOUT_ALREADY_STOPPED;
      tail = 'is already stopped';
    other;
      tail = '';
  endsl;

  return 'Service ''' + %trim(friendly) + ''' ' + %trim(tail);

end-proc;

//==============================================================================
// SCOUT_dep_start
//   Attempting to start service dependency 'x' (X)...                  STDOUT
//==============================================================================

dcl-proc SCOUT_dep_start export;
  dcl-pi *n like(SCOUT_LINE_t);
    short_name like(SCOUT_LINE_t) const;
    friendly   like(SCOUT_LINE_t) const;
  end-pi;

  return 'Attempting to start service dependency ''' + %trim(short_name) +
         ''' (' + %trim(friendly) + ')...';

end-proc;

//==============================================================================
// SCOUT_dep_stop
//   Attempting to stop dependent service 'X'...                        STDOUT
//
// NOT the mirror of SCOUT_dep_start, and this is measured. The start side
// names the service twice, short then friendly in parentheses; this side names
// it once, friendly only, and says 'dependent' rather than 'dependency'.
// Making the two symmetrical would be introducing a defect, not removing one.
//==============================================================================

dcl-proc SCOUT_dep_stop export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly like(SCOUT_LINE_t) const;
  end-pi;

  return 'Attempting to stop dependent service ''' + %trim(friendly) + '''...';

end-proc;

//==============================================================================
// SCOUT_err_timeout
//   ERROR: Timed out waiting for service 'X' to start                  STDERR
//==============================================================================

dcl-proc SCOUT_err_timeout export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly like(SCOUT_LINE_t) const;
  end-pi;

  return 'ERROR: Timed out waiting for service ''' + %trim(friendly) +
         ''' to start';

end-proc;

//==============================================================================
// SCOUT_err_dep_failed
//   ERROR: Could not start dependency 'x' for service 'X': <inner>     STDERR
//
// The inner message is embedded WHOLE, its own 'ERROR: ' prefix included, so
// the line carries the word twice. Measured; do not strip it.
//==============================================================================

dcl-proc SCOUT_err_dep_failed export;
  dcl-pi *n like(SCOUT_LINE_t);
    short_name like(SCOUT_LINE_t) const;
    friendly   like(SCOUT_LINE_t) const;
    nested     like(SCOUT_LINE_t) const;
  end-pi;

  return 'ERROR: Could not start dependency ''' + %trim(short_name) +
         ''' for service ''' + %trim(friendly) + ''': ' + %trim(nested);

end-proc;

//==============================================================================
// SCOUT_svc_partial
//   Service 'X' is already partially running. ...                      STDERR
//
// Deliberately not a fifth SCOUT_svc_state constant: the four states go to
// stdout and this goes to stderr, so folding it in would make the stream
// difference something to remember rather than something structural.
//==============================================================================

dcl-proc SCOUT_svc_partial export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly like(SCOUT_LINE_t) const;
  end-pi;

  return 'Service ''' + %trim(friendly) + ''' is already partially running. ' +
         'You may need to restart if this operation fails.';

end-proc;

//==============================================================================
// SCOUT_only_started
//   WARNING: Service 'X' only 1/2 started [failed to start --> [...]]  STDERR
//
// The inner bracket is SCOUT_not_running_suffix's output, passed in rather
// than rendered again here. Two renderings of one criterion in one codebase
// drift apart, and this is a line nobody reads until it matters.
//==============================================================================

dcl-proc SCOUT_only_started export;
  dcl-pi *n like(SCOUT_LINE_t);
    friendly like(SCOUT_LINE_t) const;
    alive    like(INTEGER_t) const;
    total    like(INTEGER_t) const;
    failures like(SCOUT_LINE_t) const;
  end-pi;

  return 'WARNING: Service ''' + %trim(friendly) + ''' only ' +
         %char(alive) + '/' + %char(total) + ' started ' +
         '[failed to start --> ' + %trim(failures) + ']';

end-proc;

//==============================================================================
// SCOUT_log_detail
//   For details, see log file at: <path>                               STDOUT
//
// On the stream a consumer parses by column position. It yields no bar at
// column 22 and does not begin with two spaces, so a row-parsing consumer
// drops it - but that is a property of the consumer, not of this line.
//==============================================================================

dcl-proc SCOUT_log_detail export;
  dcl-pi *n like(SCOUT_LINE_t);
    path like(SCOUT_LINE_t) const;
  end-pi;

  return 'For details, see log file at: ' + %trim(path);

end-proc;
