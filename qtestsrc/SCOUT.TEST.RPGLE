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

dcl-pr aEqualExact;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(64) const;
end-pr;

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

// BLOCK 3 - paste into qtestsrc/SCOUT.TEST.RPGLE
//
// Pure formatting: no fixtures, no system state, deterministic on any box.
// This is the block that holds the byte-exact contract, so it is the one to
// run first when something goes red.
//
// Needs in the global declarations:
//   dcl-pr aEqualExact;
//     expected  varchar(512) const;
//     actual    varchar(512) const;
//     fieldName varchar(64) const;
//   end-pr;
//==============================================================================

//------------------------------------------------------------------------------
// aEqualExact - a comparison in which a trailing blank is a difference
//
// Neither existing helper can be used for the check row.
//
// aEqual pads the shorter operand with blanks, as RPG comparison does, so
// '...(Probe dead)' and '...(Probe dead) ' compare EQUAL - and the trailing
// space is precisely what the check contract requires and what the consumer's
// third field depends on. aEqualV is worse for this: it %trimr's both sides
// deliberately.
//
// So the length is compared first and the content only then, and the failure
// message brackets both values and gives their lengths, because a one-byte
// difference in trailing whitespace is invisible in a test report otherwise.
//
// If SCOUT_LINE_t turns out to be fixed-length rather than varying, every
// %len below reports the declared length and these tests need the value
// captured into a varchar first - say so rather than relaxing the assertion.
//------------------------------------------------------------------------------
dcl-proc aEqualExact;
  dcl-pi *n;
    expected  varchar(512) const;
    actual    varchar(512) const;
    fieldName varchar(64) const;
  end-pi;

  assert((%len(expected) = %len(actual) and expected = actual):
         %trim(fieldName) + ': expected [' + expected + '] (' +
         %char(%len(expected)) + ' bytes) but was [' + actual + '] (' +
         %char(%len(actual)) + ' bytes)');

end-proc;

//==============================================================================
// The status text is PARTIAL followed by (alive/total)
//
// Captured: "PARTIAL (1/2)", "PARTIAL (1/3)", "PARTIAL (2/3)" - one space
// after PARTIAL, a slash with no spaces round it, no padding of either number.
//
// aEqualV/aEqual rather than aEqualExact here on purpose: SCOUT_STATUS_t may
// be fixed-length, in which case the return value is blank-padded and a length
// comparison would fail for a reason that has nothing to do with the format.
// The exact byte layout is pinned where it actually matters - in the assembled
// row, below.
//==============================================================================

dcl-proc test_partial_status_text export;

  aEqual('PARTIAL (1/2)': SCOUT_partial_status(1: 2): 'one of two');
  aEqual('PARTIAL (1/3)': SCOUT_partial_status(1: 3): 'one of three');
  aEqual('PARTIAL (2/3)': SCOUT_partial_status(2: 3): 'two of three');

end-proc;

//==============================================================================
// INFERRED - the counts are rendered as given, with no special cases
//
// No capture shows (0/n) or a count in double figures: upstream would report a
// service with nothing alive as NOT RUNNING, and the captured services have at
// most three criteria. SCOUT_partial_status is specified as presentation only,
// so it should render what it is handed rather than second-guess it.
//
// CONFIRM ON THE BOX if a definition with ten or more criteria is available.
// If upstream pads or abbreviates a wide count, this expectation is wrong.
//==============================================================================

dcl-proc test_partial_status_renders_what_it_is_given export;

  aEqual('PARTIAL (0/2)':   SCOUT_partial_status(0: 2):   'zero alive');
  aEqual('PARTIAL (9/10)':  SCOUT_partial_status(9: 10):  'double figures');
  aEqual('PARTIAL (10/10)': SCOUT_partial_status(10: 10): 'both double');

end-proc;

//==============================================================================
// The suffix wraps the joined failures in [not running at -->...]
//
// Captured, character for character:
//   [not running at -->PORT:55999]
//
// Note the arrow: two hyphens and a greater-than, no space either side of it,
// and no space after "at" other than the single one before the arrow. The
// closing bracket is the last character of the line.
//==============================================================================

dcl-proc test_not_running_suffix_single export;

  aEqual('[not running at -->PORT:55999]':
         SCOUT_not_running_suffix('PORT:55999'): 'port failure');

  aEqual('[not running at -->JOBNAME:NOSUCHJOB1]':
         SCOUT_not_running_suffix('JOBNAME:NOSUCHJOB1'): 'job failure');

  aEqual('[not running at -->JOBNAME:QUSRWRK/NOSUCHJOB2]':
         SCOUT_not_running_suffix('JOBNAME:QUSRWRK/NOSUCHJOB2'): 'SBS/JOB failure');

  aEqual('[not running at -->JOBNAME:PGM-NOSUCHPGM]':
         SCOUT_not_running_suffix('JOBNAME:PGM-NOSUCHPGM'): 'PGM- failure');

end-proc;

//==============================================================================
// The suffix passes an already-joined list through unaltered
//
// Captured:
//   [not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]
//
// The join happens before this procedure - it must not re-space, re-order or
// otherwise touch what it is given.
//==============================================================================

dcl-proc test_not_running_suffix_joined export;

  aEqual('[not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]':
         SCOUT_not_running_suffix('PORT:55998, JOBNAME:NOSUCHJOB3'):
         'two failures, joined by the caller');

  aEqual('[not running at -->PORT:1, PORT:2, PORT:3]':
         SCOUT_not_running_suffix('PORT:1, PORT:2, PORT:3'):
         'three failures pass through unchanged');

end-proc;

//==============================================================================
// A RUNNING row is byte-identical to today's, called the way it is today
//
// This is the regression guard for the whole change. The expectation is
// copied from fixtures/check.txt, which is the committed byte-exact baseline,
// and compared with aEqualExact so the trailing space is part of the
// assertion. Three arguments, because the fourth is options(*nopass) and every
// existing caller passes three.
//==============================================================================

dcl-proc test_check_row_running_unchanged export;

  dcl-s row varchar(512);

  row = SCOUT_check_row('RUNNING': 'webproxy': 'Web Proxy');

  aEqualExact('  RUNNING            | webproxy (Web Proxy) ': row: 'running row');
  iEqual(44: %len(row): 'length, as a cross-check on the literal above');
  aEqual('|': %subst(row: 22: 1): 'pipe at column 22');
  aEqual(' ': %subst(row: %len(row): 1): 'the row still ends in a space');

end-proc;

//==============================================================================
// A NOT RUNNING row is byte-identical to today's, and gets NO suffix
//
// Captured under cat -A, so the trailing space is evidence rather than
// assumption:
//   NOT RUNNING        | zzsdead (Probe dead) $
//
// A fully stopped service has failures - every one of its criteria - and
// upstream lists none of them. If the fix appends a suffix whenever
// failed_count > 0, this is the test that catches it.
//==============================================================================

dcl-proc test_check_row_not_running_unchanged export;

  dcl-s row varchar(512);

  row = SCOUT_check_row('NOT RUNNING': 'zzsdead': 'Probe dead');

  aEqualExact('  NOT RUNNING        | zzsdead (Probe dead) ': row: 'stopped row');
  iEqual(44: %len(row): 'length');
  aEqual('|': %subst(row: 22: 1): 'pipe at column 22');
  aEqual(' ': %subst(row: %len(row): 1): 'ends in a space, no suffix');

end-proc;

//==============================================================================
// The suffix is appended AFTER the row's existing trailing space
//
// Captured:
//   PARTIAL (1/2)      | zzsport (Probe zzsport) [not running at -->PORT:55999]
//                                              ^ the row's own trailing space
//
// Stated without a second literal: the four-argument row must be the
// three-argument row with the suffix concatenated on the end, nothing removed
// and nothing inserted. So a change to the base row can only break this in one
// place rather than two.
//==============================================================================

dcl-proc test_check_row_suffix_is_pure_append export;

  dcl-s bare   varchar(512);
  dcl-s full   varchar(512);
  dcl-s suffix varchar(512);

  suffix = '[not running at -->PORT:55999]';

  bare = SCOUT_check_row('PARTIAL (1/2)': 'zzsport': 'Probe zzsport');
  full = SCOUT_check_row('PARTIAL (1/2)': 'zzsport': 'Probe zzsport': suffix);

  iEqual(%len(bare) + %len(suffix): %len(full): 'nothing added but the suffix');
  aEqualExact(bare: %subst(full: 1: %len(bare)): 'the row up to the suffix');
  aEqualExact(suffix: %subst(full: %len(bare) + 1): 'the suffix, verbatim');
  aEqual(' ': %subst(full: %len(bare): 1):
         'the row keeps its trailing space, the suffix goes after it');
  aEqual(']': %subst(full: %len(full): 1): 'the line then ends in a bracket');

end-proc;

//==============================================================================
// INFERRED - an omitted suffix and an empty suffix give the same row
//
// No capture bears on this. It is asserted because SCEXEC will have to decide
// whether to call the four-argument form unconditionally, and if '' produced
// a row that differed from the three-argument one - a stray space, say - the
// RUNNING and NOT RUNNING rows would change without anything obviously being
// about them.
//
// If the fix instead makes an empty suffix an error, replace this test with
// one that pins that. Do not delete it.
//==============================================================================

dcl-proc test_check_row_empty_suffix_matches_omitted export;

  aEqualExact(SCOUT_check_row('RUNNING': 'webproxy': 'Web Proxy'):
              SCOUT_check_row('RUNNING': 'webproxy': 'Web Proxy': ''):
              'empty suffix changes nothing');

end-proc;

//==============================================================================
// The captured PARTIAL rows, end to end, byte for byte
//
// Each expectation below is one of the captured lines, reproduced by composing
// the three new procedures the way the fix will compose them. This is the test
// the change exists to pass, and the one that would have caught the bare
// PARTIAL that is there today.
//
// The literals are split across source lines to stay inside the source record
// length; %len is asserted alongside each one so a mistake in the split cannot
// pass as a match. The lengths come from the captures: 77, 83, 91, 86.
//==============================================================================

dcl-proc test_check_row_captured_single_failure export;

  dcl-s row varchar(512);

  // PARTIAL (1/2)      | zzsport (Probe zzsport) [not running at -->PORT:55999]
  row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzsport': 'Probe zzsport':
                        SCOUT_not_running_suffix('PORT:55999'));
  aEqualExact('  PARTIAL (1/2)      | zzsport (Probe zzsport) ' +
              '[not running at -->PORT:55999]': row: 'zzsport row');
  iEqual(77: %len(row): 'zzsport row length');

  // PARTIAL (1/2)      | zzsjob (Probe zzsjob) [not running at -->JOBNAME:NOSUCHJOB1]
  row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzsjob': 'Probe zzsjob':
                        SCOUT_not_running_suffix('JOBNAME:NOSUCHJOB1'));
  aEqualExact('  PARTIAL (1/2)      | zzsjob (Probe zzsjob) ' +
              '[not running at -->JOBNAME:NOSUCHJOB1]': row: 'zzsjob row');
  iEqual(83: %len(row): 'zzsjob row length');

  // PARTIAL (1/2)      | zzssbs (Probe zzssbs) [not running at -->JOBNAME:QUSRWRK/NOSUCHJOB2]
  row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzssbs': 'Probe zzssbs':
                        SCOUT_not_running_suffix('JOBNAME:QUSRWRK/NOSUCHJOB2'));
  aEqualExact('  PARTIAL (1/2)      | zzssbs (Probe zzssbs) ' +
              '[not running at -->JOBNAME:QUSRWRK/NOSUCHJOB2]': row: 'zzssbs row');
  iEqual(91: %len(row): 'zzssbs row length');

  // PARTIAL (1/2)      | zzspgm (Probe zzspgm) [not running at -->JOBNAME:PGM-NOSUCHPGM]
  row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzspgm': 'Probe zzspgm':
                        SCOUT_not_running_suffix('JOBNAME:PGM-NOSUCHPGM'));
  aEqualExact('  PARTIAL (1/2)      | zzspgm (Probe zzspgm) ' +
              '[not running at -->JOBNAME:PGM-NOSUCHPGM]': row: 'zzspgm row');
  iEqual(86: %len(row): 'zzspgm row length');

end-proc;

//==============================================================================
// The captured rows with two failures and with a bracketed description
//
// Captured:
//   PARTIAL (1/3)      | zzstwo (Probe two) [not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]
//   PARTIAL (2/3)      | system_admin1 (Navigator for i (latest generation)) [not running at -->PORT:2003]
//
// The second is worth its own case for a reason that has nothing to do with
// PARTIAL: its description contains parentheses. README pins the description
// as "between ( and the LAST )", so a consumer - and any test - that scans for
// the first ) would cut this row short. The suffix now moves the last ) away
// from the end of the line, which is exactly the condition under which that
// bug would appear.
//
// Lengths from the captures: 92 and 104.
//==============================================================================

dcl-proc test_check_row_captured_multiple_failures export;

  dcl-s row varchar(512);

  row = SCOUT_check_row(SCOUT_partial_status(1: 3): 'zzstwo': 'Probe two':
                        SCOUT_not_running_suffix('PORT:55998, JOBNAME:NOSUCHJOB3'));
  aEqualExact('  PARTIAL (1/3)      | zzstwo (Probe two) ' +
              '[not running at -->PORT:55998, JOBNAME:NOSUCHJOB3]': row:
              'zzstwo row');
  iEqual(92: %len(row): 'zzstwo row length');

  row = SCOUT_check_row(SCOUT_partial_status(2: 3): 'system_admin1':
                        'Navigator for i (latest generation)':
                        SCOUT_not_running_suffix('PORT:2003'));
  aEqualExact('  PARTIAL (2/3)      | system_admin1 ' +
              '(Navigator for i (latest generation)) ' +
              '[not running at -->PORT:2003]': row: 'system_admin1 row');
  iEqual(104: %len(row): 'system_admin1 row length');

end-proc;

//==============================================================================
// The pipe is still at column 22 on a PARTIAL row - asserted by position
//
// CLAUDE.md: the consumer parses by column position and silently drops any row
// that does not yield three fields. Every captured PARTIAL row has the pipe in
// the same place as every RUNNING row, so the widened status must be absorbed
// by the padding, not by shifting the separator.
//
// Checked across all three captured widths, and against the RUNNING row, so a
// pass cannot come from one lucky width. The two characters either side are
// asserted too: a row with '||' or with the pipe against the name would still
// have a pipe at 22.
//==============================================================================

dcl-proc test_check_row_pipe_column_partial export;

  dcl-s row varchar(512);

  row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzsport': 'Probe zzsport':
                        SCOUT_not_running_suffix('PORT:55999'));
  aEqual(' | ': %subst(row: 21: 3): 'PARTIAL (1/2): separator at columns 21-23');
  aEqual('zzsport': %subst(row: 24: 7): 'name starts at column 24');

  row = SCOUT_check_row(SCOUT_partial_status(1: 3): 'zzstwo': 'Probe two':
                        SCOUT_not_running_suffix('PORT:55998, JOBNAME:NOSUCHJOB3'));
  aEqual(' | ': %subst(row: 21: 3): 'PARTIAL (1/3): separator at columns 21-23');

  row = SCOUT_check_row(SCOUT_partial_status(2: 3): 'zzsthree': 'Probe three':
                        SCOUT_not_running_suffix('PORT:2003'));
  aEqual(' | ': %subst(row: 21: 3): 'PARTIAL (2/3): separator at columns 21-23');

  row = SCOUT_check_row('RUNNING': 'zzsthree': 'Probe three');
  aEqual(' | ': %subst(row: 21: 3): 'RUNNING: the same columns');

end-proc;

//==============================================================================
// A status wider than 18 pushes the pipe right - upstream's behaviour, not a
// tidier one
//
// No capture reaches this: the widest captured status is "PARTIAL (2/3)", 13
// characters. The brief records that upstream pads to 18 WITHOUT truncating,
// so a count wide enough to exceed 18 moves the separator instead of losing
// characters off the status.
//
// INFERRED, and deliberately asserting the uglier answer. Two behaviours have
// to be told apart here and both are plausible implementations:
//
//   truncate to 18   ->  '  PARTIAL (1000/20 | ...'   pipe at 22, text lost
//   pad, never cut   ->  '  PARTIAL (1000/2000) | ...' pipe at 23, text kept
//
// The second is what upstream does, so it is what RMSC must do - a divergence
// that only shows up on a service with a thousand criteria is still a
// divergence, and truncating is the one that corrupts the status field rather
// than merely moving it. "PARTIAL (1000/2000)" is 19 characters, one over.
//
// CONFIRM ON THE BOX if a definition wide enough can be built; otherwise this
// is the brief's word, not a capture's.
//==============================================================================

dcl-proc test_check_row_wide_status_not_truncated export;

  dcl-s row    varchar(512);
  dcl-s stat_text varchar(512);

  stat_text = SCOUT_partial_status(1000: 2000);
  aEqual('PARTIAL (1000/2000)': stat_text: 'a 19-character status');

  row = SCOUT_check_row(SCOUT_partial_status(1000: 2000): 'zzswide': 'Probe wide':
                        SCOUT_not_running_suffix('PORT:1'));

  aEqualExact('  PARTIAL (1000/2000) | zzswide (Probe wide) ' +
              '[not running at -->PORT:1]': row: 'wide status row');
  iEqual(71: %len(row): 'wide row length');
  aEqual('|': %subst(row: 23: 1):
         'the pipe moves to 23 rather than the status being cut');
  aEqual('PARTIAL (1000/2000)': %subst(row: 3: 19):
         'the status survives whole, which is the point');

end-proc;

//==============================================================================
// A status exactly 18 wide still leaves the pipe at 22
//
// The boundary either side of the case above. "PARTIAL (100/1000)" is exactly
// 18 characters, so it needs no padding and must not gain any: an
// implementation that padded to 18 and then added a space unconditionally
// would put the pipe at 23 here, breaking a row that has no business moving.
//
// INFERRED in the same way as the test above - derived from the 18-column
// contract in CLAUDE.md and README, not from a capture.
//==============================================================================

dcl-proc test_check_row_status_exactly_18 export;

  dcl-s row varchar(512);

  aEqual('PARTIAL (100/1000)': SCOUT_partial_status(100: 1000):
         'exactly 18 characters');

  row = SCOUT_check_row(SCOUT_partial_status(100: 1000): 'zzsedge': 'Probe edge':
                        SCOUT_not_running_suffix('PORT:1'));

  aEqual(' | ': %subst(row: 21: 3): 'separator still at columns 21-23');
  aEqual('zzsedge': %subst(row: 24: 7): 'name still starts at column 24');

end-proc;
