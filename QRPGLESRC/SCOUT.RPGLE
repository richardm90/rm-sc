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
// SCOUT_writeln
//==============================================================================

dcl-proc SCOUT_writeln export;
  dcl-pi *n;
    line like(SCOUT_LINE_t) const;
  end-pi;

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
