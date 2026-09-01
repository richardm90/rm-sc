**free

//==============================================================================
// SCOUT.TEST - Output formatting test suite
//
// These assertions exist because 'check' output is an interface. At least one
// consumer parses it by column position and silently drops any row that does
// not yield status, name and description - so a formatting slip does not raise
// an error, it makes services vanish from a screen.
//
// The tests therefore check the row the way that consumer reads it: status
// from columns 1-20, the bar's column, the name between the bar and the
// opening parenthesis, the description between the parentheses.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCOUT_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

//==============================================================================
// aEqualV - see docs/testing-notes.md
//==============================================================================

dcl-proc aEqualV;
  dcl-pi *n;
    expected varchar(512) const;
    actual   varchar(512) const;
    fieldName varchar(64) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(fieldName) + ': expected "' + %trim(expected) +
         '" but was "' + %trim(actual) + '"');

end-proc;

//==============================================================================
// Colour must be off for these: the format assertions are about bytes, and an
// escape sequence would land inside the status columns.
//==============================================================================

dcl-proc setUp export;

  SCOUT_set_colour(false);

end-proc;

//==============================================================================
// The row is byte-exact
//==============================================================================

dcl-proc test_check_row_exact export;

  aEqualV('  RUNNING            | webproxy (Web Proxy) ':
          SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy'):
          'running row');

  aEqualV('  NOT RUNNING        | jobrunner (Job Runner) ':
          SCOUT_check_row(SCOUT_NOT_RUNNING: 'jobrunner': 'Job Runner'):
          'stopped row');

  aEqualV('  PARTIAL            | cache (Cache Service) ':
          SCOUT_check_row(SCOUT_PARTIAL: 'cache': 'Cache Service'):
          'partial row');

end-proc;

//==============================================================================
// The bar lands in column 22 regardless of status or name length
//
// This is the single assertion the consumer's parser depends on most.
//==============================================================================

dcl-proc test_bar_column export;

  dcl-s row like(SCOUT_LINE_t);

  row = SCOUT_check_row(SCOUT_RUNNING: 'a': 'A');
  iEqual(SCOUT_BAR_COLUMN: %scan('|': row): 'short name');

  row = SCOUT_check_row(SCOUT_NOT_RUNNING: 'a-very-long-service-name-indeed':
                        'A rather long description of the service');
  iEqual(SCOUT_BAR_COLUMN: %scan('|': row): 'long name and description');

  row = SCOUT_check_row(SCOUT_PARTIAL: 'x': 'Y');
  iEqual(SCOUT_BAR_COLUMN: %scan('|': row): 'partial status');

end-proc;

//==============================================================================
// Two leading spaces, and the name starts at column 24
//==============================================================================

dcl-proc test_leading_and_name_column export;

  dcl-s row like(SCOUT_LINE_t);

  row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');

  aEqualV('  ': %subst(row: 1: 2): 'two leading spaces');
  aEqualV(' ': %subst(row: SCOUT_BAR_COLUMN - 1: 1): 'space before the bar');
  aEqualV(' ': %subst(row: SCOUT_BAR_COLUMN + 1: 1): 'space after the bar');
  aEqualV('w': %subst(row: SCOUT_NAME_COLUMN: 1): 'name starts at column 24');
  aEqualV(' ': %subst(row: %len(row): 1): 'one trailing space');

end-proc;

//==============================================================================
// The row parses the way the consumer parses it
//
// Status from columns 1-20 trimmed, name between the bar and '(', description
// between '(' and the last ')'. All three must be present or the row is
// dropped.
//==============================================================================

dcl-proc test_parses_as_consumer_reads_it export;

  dcl-s row       like(SCOUT_LINE_t);
  dcl-s pos_start like(INTEGER_t);
  dcl-s pos_end   like(INTEGER_t);

  row = SCOUT_check_row(SCOUT_NOT_RUNNING: 'jobrunner': 'Job Runner');

  aEqualV('NOT RUNNING': %trim(%subst(row: 1: 20)): 'status from columns 1-20');

  pos_start = %scan('|': row);
  pos_end   = %scan('(': row);
  assert((pos_start > 0): 'a bar is present');
  assert((pos_end > pos_start): 'an opening parenthesis follows it');
  aEqualV('jobrunner':
          %trim(%subst(row: pos_start + 1: pos_end - pos_start - 1)):
          'name between bar and parenthesis');

  pos_start = %scan('(': row);
  pos_end   = %scanr(')': row);
  assert((pos_end > pos_start): 'a closing parenthesis follows');
  aEqualV('Job Runner':
          %subst(row: pos_start + 1: pos_end - pos_start - 1):
          'description inside the parentheses');

end-proc;

//==============================================================================
// A description containing parentheses still yields the right text
//
// The consumer scans forward for '(' and BACKWARD for ')', so the outermost
// pair wins.
//==============================================================================

dcl-proc test_parentheses_in_description export;

  dcl-s row       like(SCOUT_LINE_t);
  dcl-s pos_start like(INTEGER_t);
  dcl-s pos_end   like(INTEGER_t);

  row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy (TLS)');

  pos_start = %scan('(': row);
  pos_end   = %scanr(')': row);
  aEqualV('Web Proxy (TLS)':
          %subst(row: pos_start + 1: pos_end - pos_start - 1):
          'outermost parentheses win');

end-proc;

//==============================================================================
// The format holds a status of up to 18 characters
//
// That is the hard limit, not an arbitrary one: the consumer reads the status
// from columns 1-20 and two of those are the leading spaces. A longer status
// cannot be represented here at all - it would either be cut, and parse to
// something wrong, or widen the row and push the bar out of column 22. The
// three real statuses are 7, 11 and 7 characters, so the limit is not close.
//==============================================================================

dcl-proc test_status_at_field_width export;

  dcl-s row like(SCOUT_LINE_t);

  // Exactly 18 characters
  row = SCOUT_check_row('NOT RUNNING (PART)': 'x': 'Y');

  iEqual(SCOUT_BAR_COLUMN: %scan('|': row): 'bar still in column 22');
  aEqualV('NOT RUNNING (PART)': %trim(%subst(row: 1: 20)):
          'status still readable from columns 1-20');

end-proc;

//==============================================================================
// Every real status is comfortably inside the limit
//==============================================================================

dcl-proc test_real_statuses_fit export;

  assert((%len(SCOUT_RUNNING) <= SCOUT_STATUS_WIDTH): 'RUNNING fits');
  assert((%len(SCOUT_NOT_RUNNING) <= SCOUT_STATUS_WIDTH): 'NOT RUNNING fits');
  assert((%len(SCOUT_PARTIAL) <= SCOUT_STATUS_WIDTH): 'PARTIAL fits');

end-proc;

//==============================================================================
// With colour off there are no escape sequences at all
//==============================================================================

dcl-proc test_no_escapes_without_colour export;

  dcl-s row like(SCOUT_LINE_t);

  SCOUT_set_colour(false);
  row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');

  iEqual(0: %scan(x'27': row): 'no ESC byte anywhere in the row');
  nEqual(false: SCOUT_colour(): 'colour reports off');

end-proc;

//==============================================================================
// With colour on the escapes are present but the visible columns do not move
//==============================================================================

dcl-proc test_colour_preserves_columns export;

  dcl-s row   like(SCOUT_LINE_t);
  dcl-s plain like(SCOUT_LINE_t);

  SCOUT_set_colour(false);
  plain = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');

  SCOUT_set_colour(true);
  row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');

  assert((%scan(x'27': row) > 0): 'escapes present when colour is on');
  assert((%len(row) > %len(plain)): 'the coloured row is longer in bytes');

  // The visible text either side of the status field is unchanged
  aEqualV('  ': %subst(row: 1: 2): 'two leading spaces still');
  assert((%scan(' | webproxy (Web Proxy) ': row) > 0):
         'everything after the status is unchanged');

  SCOUT_set_colour(false);

end-proc;

//==============================================================================
// list rows carry no padding
//==============================================================================

dcl-proc test_list_row export;

  aEqualV('webproxy (Web Proxy)':
          SCOUT_list_row('webproxy': 'Web Proxy'): 'list row');
  aEqualV('cache (Cache Service)':
          SCOUT_list_row('cache': 'Cache Service'): 'another list row');

end-proc;

//==============================================================================
// The empty-result warning is upstream's text, verbatim
//
// Captured from the installed sc 1.7.1:
//   $ sc check group:nosuchgroup
//   WARNING: No services are found in group 'nosuchgroup'   (on stderr, rc 0)
//   $ sc check --ignore-globals
//   WARNING: No services are found in group 'all'           (on stderr, rc 0)
//
// A bare check or list reports the implicit group as 'all'. RMSC printed
// nothing at all in the first case and raised an error with different wording
// in the second, which nothing could see until --ignore-globals started
// working and a collection could be empty.
//==============================================================================

dcl-proc test_no_services_warning export;

  aEqualV('WARNING: No services are found in group ''all''':
          SCOUT_no_services_warning('all'): 'implicit group');
  aEqualV('WARNING: No services are found in group ''nosuchgroup''':
          SCOUT_no_services_warning('nosuchgroup'): 'named group');

end-proc;

//==============================================================================
// Colour defaults to whether standard output is a terminal
//
// This is what keeps escapes out of piped output, which is the only reason a
// consumer reading columns 1-20 works at all.
//==============================================================================

dcl-proc test_tty_detection export;

  // RPGUnit runs in a spawned batch job, so stdout is not a terminal here
  nEqual(false: SCOUT_is_tty(): 'not a terminal under RPGUnit');

end-proc;
