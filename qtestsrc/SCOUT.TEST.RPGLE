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

//------------------------------------------------------------------------------
// The silence flag as it stood before this suite touched anything.
//
// It is MODULE state - it lives for the activation, not for the call - and
// every procedure in this suite shares one activation, so the only moment its
// starting value can be read is before any test procedure has run.
// setUpSuite is that moment. See test_silent_starts_off.
//------------------------------------------------------------------------------
//
// INITIALISED TO *ON, WHICH IS THE WRONG ANSWER ON PURPOSE. Uninitialised it
// would be *off, which is exactly what test_silent_starts_off asserts - so a
// setUpSuite that never ran, or one that stopped assigning this field, would
// leave the case passing on a value nobody measured. Seeded with the value the
// case rejects, the omission fails loudly instead.
dcl-s g_silent_at_suite_start like(BOOLEAN_t) inz(*on);

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
// Suite set-up
//
// Read the silence flag BEFORE anything else, and before the first test
// procedure runs. Nothing else belongs here: read it, then leave it alone.
//==============================================================================

dcl-proc setUpSuite export;

  g_silent_at_suite_start = SCOUT_silent();

end-proc;

//==============================================================================
// Colour must be off for these: the format assertions are about bytes, and an
// escape sequence would land inside the status columns.
//
// SILENCE IS RESET FOR THE SAME REASON, and it is a sharper one. Both flags are
// module state and both outlive the procedure that set them, so a test that
// left one on would change what every test after it saw - and ORDER(*API) does
// not promise which those are. The narration cases in this file assert on
// RENDERED text, which must not move whichever way the flag is set, so a leak
// would not fail them; it would simply mean this suite had stopped testing what
// it says it tests.
//==============================================================================

dcl-proc setUp export;

  SCOUT_set_colour(false);
  SCOUT_set_silent(false);

end-proc;

//==============================================================================
// Suite tear-down
//
// Leave the flags where they were found. A suite that ended with silence on
// would hand it to whatever ran next in the same job, and the symptom would be
// output that simply did not appear.
//==============================================================================

dcl-proc tearDownSuite export;

  SCOUT_set_silent(false);
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

//##############################################################################
//##                                                                          ##
//##  BLOCK B - paste into qtestsrc/SCOUT.TEST.RPGLE                          ##
//##                                                                          ##
//##############################################################################
//
// The message itself. It is rendering, so it belongs beside
// SCOUT_not_running_suffix and SCOUT_no_services_warning rather than in
// SCEXEC - and for the same reason those are there: it is byte-exact
// upstream text, and pure formatting tests are deterministic on any box.
//
// PROPOSED, matching SCOUT_no_services_warning's shape:
//
//   dcl-pr SCOUT_invalid_criteria like(SCOUT_LINE_t);
//     friendly  like(SCDEF_NAME_t) const;   // the FRIENDLY name
//     criterion like(SCDEF_NAME_t) const;   // 'PORT:abc', already rendered
//   end-pr;
//
// Exported at the END of RMSC.BND's list. CLAUDE.md: the signature pins the
// ORDER, so an export inserted in the middle silently rebinds every caller
// after it.
//
// REUSES aEqualExact and aEqualV, already in that suite.
//==============================================================================

//==============================================================================
// The message is upstream's, character for character
//
// MEASURED from sc 1.7.1, on stderr:
//
//   Invalid data for port number or job name criteria for service 'ZZ bad': PORT:abc
//
// Single quotes round the name, a colon and one space before the criterion,
// and the criterion in the same PORT:value form SCDEF_criterion_text already
// produces. "port number or job name" is upstream's wording and stays even
// though only a port can produce this - measured: a 27-character job name is
// accepted without complaint.
//
// aEqualExact rather than aEqual, so a trailing blank is a difference. The
// captured line shows none. If it turns out upstream emits one - stderr was
// not captured through cat -A - this assertion is where to add it, and
// tools/error-delivery-test.sh should gain the same expectation.
//==============================================================================

dcl-proc test_invalid_criteria_message export;

  aEqualExact('Invalid data for port number or job name criteria for ' +
              'service ''ZZ bad'': PORT:abc':
              SCOUT_invalid_criteria('ZZ bad': 'PORT:abc'):
              'the measured line, byte for byte');

end-proc;

//==============================================================================
// It names the service by its FRIENDLY name
//
// MEASURED: the definition is zzbad and the message says 'ZZ bad'. Worth its
// own test because every other place RMSC names a service in a listing uses
// the short name first - the check row is "zzbad (ZZ bad)" - so an
// implementation that reached for def.short_name would look right and read
// wrong.
//
// The second case is the one that catches it: a name where the two differ in
// a way no substring match could confuse.
//==============================================================================

dcl-proc test_invalid_criteria_uses_the_friendly_name export;

  aEqualExact('Invalid data for port number or job name criteria for ' +
              'service ''Z last'': PORT:xyz':
              SCOUT_invalid_criteria('Z last': 'PORT:xyz'):
              'friendly name, not the short name');

  assert((%scan('zzzlast': SCOUT_invalid_criteria('Z last': 'PORT:xyz')) = 0):
         'the short name appears nowhere in it');

end-proc;

//==============================================================================
// The criterion passes through unaltered
//
// The same contract SCOUT_not_running_suffix has and for the same reason: the
// rendering happened before this procedure was called, and re-spacing or
// re-casing it here would put two renderings of the same criterion in the
// codebase that could drift apart.
//
// The JOBNAME cases cannot be produced by anything today - only a port can be
// unusable - and are here anyway, because the message's own wording says job
// names and a later change that made one unusable should not have to touch
// this procedure.
//==============================================================================

dcl-proc test_invalid_criteria_passes_the_criterion_through export;

  aEqualExact('Invalid data for port number or job name criteria for ' +
              'service ''ZZ x'': PORT:12ab':
              SCOUT_invalid_criteria('ZZ x': 'PORT:12ab'): 'mixed digits');

  aEqualExact('Invalid data for port number or job name criteria for ' +
              'service ''ZZ x'': PORT:':
              SCOUT_invalid_criteria('ZZ x': 'PORT:'): 'an empty value');

  aEqualExact('Invalid data for port number or job name criteria for ' +
              'service ''ZZ x'': JOBNAME:QUSRWRK/SOMEJOB':
              SCOUT_invalid_criteria('ZZ x': 'JOBNAME:QUSRWRK/SOMEJOB'):
              'a job form passes through too');

end-proc;

//==============================================================================
// INFERRED - the message is not a check row and must not be shaped like one
//
// It goes to stderr, so it is not read by the consumer that parses columns -
// but the consumer's rule is positional, and error-delivery-test.sh's whole
// premise is that RMSC has put error text on stdout before now. If this line
// ever reached stdout, the one thing that must not happen is that it parses
// AS A ROW: a bogus row is silently accepted, whereas a non-row line is
// silently dropped, and dropped is survivable.
//
// So: no bar in column 22, and the line does not begin with two spaces.
//==============================================================================

dcl-proc test_invalid_criteria_is_not_row_shaped export;

  dcl-s line like(SCOUT_LINE_t);

  line = SCOUT_invalid_criteria('ZZ bad': 'PORT:abc');

  assert((%scan('|': line) <> SCOUT_BAR_COLUMN):
         'no bar in column 22 - it must not parse as a check row');
  assert((%subst(line: 1: 2) <> '  '):
         'and it does not start with the two spaces a row starts with');

end-proc;

//##############################################################################
//##                                                                          ##
//##  NARRATION - the lines sc prints while it is changing state              ##
//##                                                                          ##
//##############################################################################
//
// Written BEFORE the implementation, from docs/messages.md
// § "Narration - the family RMSC does not have" alone. Every literal below is
// either a transcription of a line captured from sc 1.7.1 on 3 September with
// tools/d2-probe.sh - marked CAPTURED - or is assembled from captured parts
// and says so - marked COMPOSED. Nothing docs/messages.md marks `unmeasured`
// is asserted anywhere in this block.
//
// WHY THESE ARE RPG TESTS AT ALL. The four procedures RETURN the line rather
// than printing it, exactly as SCOUT_check_row and SCOUT_no_services_warning
// already do, so the WORDING is reachable from iRPGUnit. Everything that only
// exists OUTSIDE the ILE job - which stream each line lands on, the order the
// lines appear in, the trailing blank line after each command, and the fact
// that -q does not suppress any of it - is in tools/narration-test.sh and is
// not attempted here.
//
//------------------------------------------------------------------------------
// WHAT IS DELIBERATELY NOT ASSERTED IN THIS FILE, AND WHY
//
// That the progress line names the service by its SHORT name and the state
// line by its FRIENDLY one - the single riskiest rule in the family, the one
// docs/messages.md § "The two whole-surface differences" raises first.
//
// It cannot be asserted here. SCOUT_op_progress is handed one name and
// SCOUT_svc_state is handed one name; neither can pick the wrong one, because
// neither is offered a choice. The choice belongs to the CALLER. A test here
// that passed 'rmscn_solo' and asserted the friendly name was absent would
// read like coverage of that rule while being incapable of detecting a single
// way of getting it wrong - which is the failure mode CLAUDE.md opens with.
//
// So it is asserted end to end in tools/narration-test.sh, where a real
// definition has both names and the implementation has to choose, and nowhere
// in this file.
//
// The dependency lines are different, and ARE asserted below: SCOUT_dep_start
// is handed BOTH names, so the order they appear in and which one is
// parenthesised is this procedure's decision and can be got wrong here.
//------------------------------------------------------------------------------
// PROPOSED prototypes. Matching SCOUT_no_services_warning's shape, and
// exported at the END of RMSC.BND's list - CLAUDE.md: the signature pins the
// ORDER, so an export inserted in the middle silently rebinds every caller
// after it.
//
//   dcl-s SCOUT_STATE_t varchar(16) template;
//
//   dcl-c SCOUT_STARTED         'STARTED';
//   dcl-c SCOUT_STOPPED         'STOPPED';
//   dcl-c SCOUT_ALREADY_RUNNING 'ALREADY RUNNING';
//   dcl-c SCOUT_ALREADY_STOPPED 'ALREADY STOPPED';
//
//   dcl-pr SCOUT_op_progress like(SCOUT_LINE_t);
//     verb       like(SCDEF_NAME_t) const;   // 'start', in any case
//     short_name like(SCDEF_NAME_t) const;   // the SHORT name
//   end-pr;
//
//   dcl-pr SCOUT_svc_state like(SCOUT_LINE_t);
//     friendly like(SCDEF_NAME_t) const;     // the FRIENDLY name
//     state    like(SCOUT_STATE_t) const;    // one of the four constants
//   end-pr;
//
//   dcl-pr SCOUT_dep_start like(SCOUT_LINE_t);
//     short_name like(SCDEF_NAME_t) const;   // the dependency, SHORT
//     friendly   like(SCDEF_NAME_t) const;   // the dependency, FRIENDLY
//   end-pr;
//
//   dcl-pr SCOUT_dep_stop like(SCOUT_LINE_t);
//     friendly like(SCDEF_NAME_t) const;     // the dependent, FRIENDLY only
//   end-pr;
//
// AND FIVE MORE, for the failure side of the family. The four above were
// specified before anyone had made a start FAIL; the re-probe did, and found
// four more lines - one of which was in no catalogue anyone had read.
//
// TWO WERE ASKED FOR:
//
//   dcl-pr SCOUT_err_timeout like(SCOUT_LINE_t);
//     friendly like(SCDEF_NAME_t) const;     // the FRIENDLY name
//   end-pr;
//
//   dcl-pr SCOUT_err_dep_failed like(SCOUT_LINE_t);
//     short_name like(SCDEF_NAME_t) const;   // the DEPENDENCY, short
//     friendly   like(SCDEF_NAME_t) const;   // the DEPENDENT, friendly
//     nested     like(SCOUT_LINE_t) const;   // the inner message, whole
//   end-pr;
//
// THREE MORE ARE PROPOSED HERE, and the reasoning is the one that produced the
// first two: a line nobody can reach from iRPGUnit is a line whose wording is
// checked by a shell script comparing whole streams, where a one-byte
// difference is reported as "stdout differs" and has to be read out of a diff.
//
//   dcl-pr SCOUT_svc_partial like(SCOUT_LINE_t);
//     friendly like(SCDEF_NAME_t) const;
//   end-pr;
//
// NOT a fifth SCOUT_svc_state constant, and docs/messages.md says why in as
// many words: the four states go to stdout and this one goes to STDERR, so
// growing the enumeration would put it on the wrong stream. A separate
// procedure makes the difference structural rather than remembered.
//
//   dcl-pr SCOUT_only_started like(SCOUT_LINE_t);
//     friendly like(SCDEF_NAME_t) const;
//     alive    like(INTEGER_t) const;
//     total    like(INTEGER_t) const;
//     failures like(SCOUT_LINE_t) const;     // SCOUT_not_running_suffix's
//   end-pr;                                  // output, already rendered
//
// The `failures` parameter is the interesting one. The line ends
// `[failed to start --> [not running at -->JOBNAME:X]]`, and the INNER bracket
// is byte-for-byte what SCOUT_not_running_suffix already produces for the
// check row. So this procedure composes the existing one rather than
// re-rendering the same thing a second way - the contract
// SCOUT_check_row's fourth parameter already has, for the same reason: two
// renderings of one criterion in one codebase will drift apart.
//
//   dcl-pr SCOUT_log_detail like(SCOUT_LINE_t);
//     path like(SCOUT_LINE_t) const;
//   end-pr;
//
// THIS IS THE ONE WITH THE STRONGEST CLAIM TO A PROCEDURE, and it is the one
// nobody knew existed. `For details, see log file at: <path>` goes to STDOUT -
// the stream a consumer parses by column position - on a start that FAILED.
// Every other line discovered by the failure probe went to stderr. A line on
// stdout that arrives only on the failure path is exactly the thing that would
// never be seen in testing and would be seen by the consumer.
//
// All five go at the END of RMSC.BND's export list, after the first four, for
// the reason CLAUDE.md gives.
//
// THE FOUR STATES ARE REFERRED TO BY CONSTANT NAME ONLY below, never by their
// values. If the implementation prefers an integer enumeration, or different
// spellings, only SCOUT_D.rpgleinc changes and no assertion in this file has
// to be touched.
//
// REUSES aEqualExact and aEqualV, already in this suite. aEqualExact is the
// right one throughout: a trailing blank is a difference, and see
// test_narration_lines_have_no_trailing_blank for why that is a live question
// rather than a formality.
//==============================================================================

//==============================================================================
// The progress line, exactly as captured
//
// CAPTURED, from the four-line dependency walk in docs/messages.md and from
// the group-start and group-stop transcripts in the same section:
//
//   Performing operation 'START' on service 'rmscd2_parent'
//   Performing operation 'START' on service 'rmscd2_dep'
//   Performing operation 'STOP' on service 'rmscd2_dep'
//
// Single quotes round both the verb and the name, one space either side of
// "on service", and nothing after the closing quote.
//==============================================================================

dcl-proc test_op_progress_captured export;

  aEqualExact('Performing operation ''START'' on service ''rmscd2_parent''':
              SCOUT_op_progress('START': 'rmscd2_parent'):
              'the captured START line for the parent');

  aEqualExact('Performing operation ''START'' on service ''rmscd2_dep''':
              SCOUT_op_progress('START': 'rmscd2_dep'):
              'the captured START line for the dependency');

  aEqualExact('Performing operation ''STOP'' on service ''rmscd2_dep''':
              SCOUT_op_progress('STOP': 'rmscd2_dep'):
              'the captured STOP line');

end-proc;

//==============================================================================
// The verb is upper-cased HERE, not by the caller
//
// docs/messages.md records the verb as "upper-cased" - a person types
// `sc start x` and reads 'START'. WHERE the upper-casing happens is not
// something a capture can say, so this test is a DESIGN PIN rather than a
// transcription: it puts the transformation in SCOUT_op_progress, where the
// rendering is, so that no caller can forget it.
//
// The separating value is the LOWERCASE verb. Passing 'START' would agree with
// a procedure that upper-cases and with one that passes its argument straight
// through; passing 'start' tells them apart. 'ReStArT' rules out a rule that
// only handles an all-lower argument.
//
// IF THE IMPLEMENTATION PUTS THE UPPER-CASING IN THE CALLER INSTEAD, this is
// the assertion to move - not the one in tools/narration-test.sh, which drives
// `scr start` from the shell and holds the end-to-end guarantee whichever side
// does the work.
//==============================================================================

dcl-proc test_op_progress_upper_cases_the_verb export;

  aEqualExact('Performing operation ''START'' on service ''rmscn_solo''':
              SCOUT_op_progress('start': 'rmscn_solo'):
              'a lower-case verb is rendered upper-case');

  aEqualExact('Performing operation ''RESTART'' on service ''rmscn_solo''':
              SCOUT_op_progress('ReStArT': 'rmscn_solo'):
              'a mixed-case verb too');

  aEqualExact('Performing operation ''STOP'' on service ''rmscn_solo''':
              SCOUT_op_progress('STOP': 'rmscn_solo'):
              'an already upper-case verb is left alone');

end-proc;

//==============================================================================
// CAPTURED - the other two state-changing verbs
//
// This block used to be marked COMPOSED. docs/messages.md quoted the progress
// line for START and STOP only, said of RESTART merely that there is "one
// RESTART progress line", and did not quote KILL's anywhere at all - so the
// verb was the one part of the sentence nothing had measured.
//
// The re-probe settled it: "All four verbs captured verbatim: START, STOP,
// KILL, RESTART". The sentence is the same for every one of them and the verb
// is the only thing that moves.
//
// tools/narration-test.sh still re-measures all four against upstream on each
// run. That is not now covering a gap - it is what keeps this file's literals
// anchored to something other than a transcription.
//==============================================================================

dcl-proc test_op_progress_restart_and_kill export;

  dcl-s start_line varchar(512);
  dcl-s variant      varchar(512);

  aEqualExact('Performing operation ''RESTART'' on service ''rmscn_solo''':
              SCOUT_op_progress('restart': 'rmscn_solo'): 'RESTART');

  aEqualExact('Performing operation ''KILL'' on service ''rmscn_solo''':
              SCOUT_op_progress('kill': 'rmscn_solo'): 'KILL');

  // All four render the SAME sentence and only the verb moves. Asserted as a
  // property, because four literals can all be right while a special case for
  // one verb sits behind them - a stray space or a different preposition that
  // happened to be typed the same way twice.
  start_line = SCOUT_op_progress('start': 'x');

  variant = %scanrpl('KILL': 'START': SCOUT_op_progress('kill': 'x'));
  aEqualExact(start_line: variant: 'KILL''s line is START''s, verb aside');

  variant = %scanrpl('RESTART': 'START': SCOUT_op_progress('restart': 'x'));
  aEqualExact(start_line: variant: 'RESTART''s line is START''s, verb aside');

  variant = %scanrpl('STOP': 'START': SCOUT_op_progress('stop': 'x'));
  aEqualExact(start_line: variant: 'STOP''s line is START''s, verb aside');

end-proc;

//==============================================================================
// The four state lines, exactly as captured
//
// CAPTURED, all four, from docs/messages.md § Narration:
//
//   Service 'RMSC D2 depsvc' successfully started
//   Service 'RMSC D2 narrate' successfully stopped
//   Service 'RMSC D2 depsvc' is already running
//   Service 'RMSC D2 labels' is already stopped
//
// Note the shape they share: the word Service, the name in single quotes, and
// then the state. "successfully started", not "started successfully"; "is
// already running", not "already running".
//==============================================================================

dcl-proc test_svc_state_captured export;

  aEqualExact('Service ''RMSC D2 depsvc'' successfully started':
              SCOUT_svc_state('RMSC D2 depsvc': SCOUT_STARTED):
              'the captured started line');

  aEqualExact('Service ''RMSC D2 narrate'' successfully stopped':
              SCOUT_svc_state('RMSC D2 narrate': SCOUT_STOPPED):
              'the captured stopped line');

  aEqualExact('Service ''RMSC D2 depsvc'' is already running':
              SCOUT_svc_state('RMSC D2 depsvc': SCOUT_ALREADY_RUNNING):
              'the captured already-running line');

  aEqualExact('Service ''RMSC D2 labels'' is already stopped':
              SCOUT_svc_state('RMSC D2 labels': SCOUT_ALREADY_STOPPED):
              'the captured already-stopped line');

end-proc;

//==============================================================================
// The four states are four different lines
//
// The separating question this answers: is the state parameter READ at all?
//
// Four literals asserted one at a time can all be right while the procedure
// still collapses two states onto one line - if, say, SCOUT_STOPPED and
// SCOUT_ALREADY_STOPPED were mapped to the same branch, every assertion above
// would still have to be written out separately and the mistake would show up
// only as one of them failing. Asserting the lines are pairwise DIFFERENT for
// ONE name states the property directly, and it is the assertion a stub that
// returns blanks fails first: six comparisons, all of which a blank return
// makes equal.
//
// It also rules out the two cross-wirings that read plausibly:
// "is already started" and "successfully running". The word `successfully`
// belongs to the two outcome states and the word `already` to the two no-op
// states, and neither appears in the other pair.
//==============================================================================

dcl-proc test_svc_state_four_states_are_distinct export;

  dcl-s started  varchar(512);
  dcl-s stopped  varchar(512);
  dcl-s running  varchar(512);
  dcl-s halted   varchar(512);

  started = SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED);
  stopped = SCOUT_svc_state('Alpha One Narrate': SCOUT_STOPPED);
  running = SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_RUNNING);
  halted  = SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_STOPPED);

  assert((started <> stopped): 'started and stopped differ');
  assert((started <> running): 'started and already-running differ');
  assert((started <> halted):  'started and already-stopped differ');
  assert((stopped <> running): 'stopped and already-running differ');
  assert((stopped <> halted):  'stopped and already-stopped differ');
  assert((running <> halted):  'already-running and already-stopped differ');

  assert((%scan('successfully': started) > 0): 'started is a success line');
  assert((%scan('successfully': stopped) > 0): 'stopped is a success line');
  assert((%scan('successfully': running) = 0): 'already-running is not');
  assert((%scan('successfully': halted)  = 0): 'already-stopped is not');

  assert((%scan('already': started) = 0): 'started is not a no-op line');
  assert((%scan('already': stopped) = 0): 'stopped is not a no-op line');
  assert((%scan('already': running) > 0): 'already-running is a no-op line');
  assert((%scan('already': halted)  > 0): 'already-stopped is a no-op line');

end-proc;

//==============================================================================
// The name is reproduced verbatim between the quotes
//
// The friendly name is whatever the definition's `name:` says, and this
// procedure is presentation only - the same contract SCOUT_not_running_suffix
// has. Nothing may be trimmed, re-cased or normalised on the way through.
//
// The separating value is a friendly name carrying PARENTHESES. It is a real
// one - system_admin1's, already used in this suite's captured PARTIAL rows -
// and it tells "reproduce the name" apart from "reproduce it up to the first
// bracket", which is a rule an implementation copied from the check row's
// description handling could plausibly arrive at.
//==============================================================================

dcl-proc test_svc_state_reproduces_the_name export;

  aEqualExact('Service ''Navigator for i (latest generation)'' ' +
              'successfully started':
              SCOUT_svc_state('Navigator for i (latest generation)':
                              SCOUT_STARTED):
              'parentheses in the name survive');

  aEqualExact('Service ''a'' is already running':
              SCOUT_svc_state('a': SCOUT_ALREADY_RUNNING):
              'a one-character name is not padded');

end-proc;

//==============================================================================
// The start-side dependency line, exactly as captured
//
// CAPTURED, from docs/messages.md § Narration, both times it appears:
//
//   Attempting to start service dependency 'rmscd2_depsvc' (RMSC D2 depsvc)...
//   Attempting to start service dependency 'rmscd2_dep' (RMSC D2 dependency)...
//
// The trailing three dots are part of the line. So is the space between the
// closing quote and the opening parenthesis, and the absence of one between
// the closing parenthesis and the dots.
//==============================================================================

dcl-proc test_dep_start_captured export;

  aEqualExact('Attempting to start service dependency ''rmscd2_depsvc'' ' +
              '(RMSC D2 depsvc)...':
              SCOUT_dep_start('rmscd2_depsvc': 'RMSC D2 depsvc'):
              'the captured dependency line');

  aEqualExact('Attempting to start service dependency ''rmscd2_dep'' ' +
              '(RMSC D2 dependency)...':
              SCOUT_dep_start('rmscd2_dep': 'RMSC D2 dependency'):
              'the same line from the group-start transcript');

end-proc;

//==============================================================================
// It names the dependency TWICE - short first, friendly in parentheses
//
// This is the half of the asymmetry that can be got wrong inside SCOUT, and
// docs/messages.md says in as many words that "anyone implementing this from
// the table above will get it wrong by making them match".
//
// The separating fixture is a pair of names that share NO substring: a short
// name of lower case and underscores, a friendly name of capitals and spaces.
// Neither can be mistaken for the other, so an implementation that printed the
// friendly name twice, or the short name twice, or swapped them, produces a
// line that differs from the expected one somewhere a reader can see.
//
// Three rival rules are ruled out, each by a value:
//   friendly only, the stop-side shape  -> 'zzdep' must be present
//   short only                          -> 'Quebec Bravo' must be present
//   the two the other way round         -> the byte-exact line settles it
//==============================================================================

dcl-proc test_dep_start_names_both_short_first export;

  dcl-s line varchar(512);

  line = SCOUT_dep_start('zzdep': 'Quebec Bravo');

  aEqualExact('Attempting to start service dependency ''zzdep'' ' +
              '(Quebec Bravo)...': line: 'short in quotes, friendly in parens');

  assert((%scan('zzdep': line) > 0): 'the short name is present');
  assert((%scan('Quebec Bravo': line) > 0): 'the friendly name is present');
  assert((%scan('zzdep': line) < %scan('Quebec Bravo': line)):
         'the short name comes first');

end-proc;

//==============================================================================
// The line ends in exactly three dots
//
// Cheap, and the three-dot tail is the detail most likely to be dropped when
// the line is retyped from the table rather than copied. Asserted by position
// rather than by a scan, so a line that merely CONTAINS '...' somewhere does
// not satisfy it, and the character before them is asserted too: '...' at the
// end of a line that had lost its closing parenthesis would otherwise pass.
//
// Four dots and two dots are both ruled out, from opposite directions.
//==============================================================================

dcl-proc test_dep_start_ends_in_three_dots export;

  dcl-s line varchar(512);

  line = SCOUT_dep_start('zzdep': 'Quebec Bravo');

  assert((%len(line) > 4): 'there is a line at all');
  aEqualExact('...': %subst(line: %len(line) - 2: 3): 'the last three bytes');
  aEqualExact(')': %subst(line: %len(line) - 3: 1):
              'a closing parenthesis immediately before them, not a fourth dot');

end-proc;

//==============================================================================
// The stop-side line, exactly as captured
//
// CAPTURED, from the group-stop transcript in docs/messages.md § Narration:
//
//   Attempting to stop dependent service 'RMSC D2 labels'...
//
// One name, the friendly one, no parentheses. The noun is "dependent" and not
// "dependency", and the word order is "stop dependent service" against the
// start side's "start service dependency" - the two lines are not the same
// sentence with one word changed.
//==============================================================================

dcl-proc test_dep_stop_captured export;

  aEqualExact('Attempting to stop dependent service ''RMSC D2 labels''...':
              SCOUT_dep_stop('RMSC D2 labels'):
              'the captured dependent line');

end-proc;

//==============================================================================
// The stop side is NOT the start side with a different verb
//
// The asymmetry, asserted as its own question so a failure says which rule
// broke rather than only that a literal moved.
//
// The separating values, and the rival each rules out:
//
//   no '(' anywhere in the line      -> rules out '<short>' (<friendly>)...,
//                                       the start-side shape reused
//   the word 'dependency' absent     -> rules out the start side's noun
//   the word 'dependent' present     -> and confirms the one that replaces it
//
// The fixture's friendly name deliberately carries no parenthesis of its own,
// which is what makes the first of those a question about the FORMAT rather
// than about the name it was handed.
//
// THE SHORT NAME'S ABSENCE IS NOT ASSERTED HERE, though it is the headline half
// of the asymmetry. SCOUT_dep_stop is never handed a short name, so a test that
// looked for one and failed to find it could not fail whatever the procedure
// did - and CLAUDE.md opens with three defects that shipped behind exactly that
// shape of assertion. It is asserted in tools/narration-test.sh instead,
// against a real definition, where the caller holds both names and can pass
// the wrong one.
//==============================================================================

dcl-proc test_dep_stop_is_not_symmetrical export;

  dcl-s line varchar(512);

  line = SCOUT_dep_stop('Quebec Bravo');

  aEqualExact('Attempting to stop dependent service ''Quebec Bravo''...':
              line: 'friendly name only, no parentheses');

  assert((%scan('(': line) = 0):
         'no parenthesis - this is not the start-side shape');
  assert((%scan('dependency': line) = 0):
         'the start side''s noun does not appear');
  assert((%scan('dependent': line) > 0):
         'and the stop side''s noun does');

  assert((%len(line) > 3): 'there is a line at all');
  aEqualExact('...': %subst(line: %len(line) - 2: 3):
              'it ends in three dots too');

end-proc;

//==============================================================================
// The two dependency lines are different lines
//
// Stated directly, because the mistake docs/messages.md warns about is
// precisely that they get made to match. One procedure delegating to the other
// would satisfy every literal above only until somebody simplified it; this
// says the two must never render alike for the same service.
//
// It is also stub-detecting on its own terms: two blank returns are equal.
//==============================================================================

dcl-proc test_dep_lines_are_not_the_same_line export;

  assert((SCOUT_dep_start('zzdep': 'Quebec Bravo') <>
          SCOUT_dep_stop('Quebec Bravo')):
         'the start-side and stop-side lines differ');

end-proc;

//==============================================================================
// No narration line can be read as a check row
//
// docs/parity.md, on the cost of adding these lines: "these are new lines on
// stdout, which the consumer parses by column position. They do not yield
// three fields, so a parser that drops malformed rows is unaffected - but that
// is a property of the consumer, not of the output, and is worth confirming
// before the lines are added."
//
// This is that confirmation, and it is the assertion in this block with the
// most at stake. CLAUDE.md's first warning is that a bad row does not raise an
// error, it makes services vanish from a screen. A narration line that
// happened to yield three fields would be ACCEPTED by the consumer as a
// service - which is worse than being dropped, because dropped is survivable.
//
// The dependency line is the one to worry about: it is the only member of the
// family that carries a parenthesised name, which is two of the three fields a
// row needs. It has no bar and does not begin in two spaces, so it is safe -
// but it is safe by one byte's worth of luck rather than by design, and that
// is exactly the kind of thing worth pinning.
//
// %len is asserted first in each case. It makes the %subst below safe, and it
// is what stops this whole procedure from passing against a stub.
//==============================================================================

dcl-proc test_narration_lines_are_not_check_rows export;

  dcl-s lines varchar(512) dim(6);
  dcl-s i     int(10);

  lines(1) = SCOUT_op_progress('START': 'rmscn_solo');
  lines(2) = SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED);
  lines(3) = SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_STOPPED);
  lines(4) = SCOUT_dep_start('zzdep': 'Quebec Bravo');
  lines(5) = SCOUT_dep_stop('Quebec Bravo');
  lines(6) = SCOUT_svc_state('Navigator for i (latest generation)':
                             SCOUT_STARTED);

  for i = 1 to %elem(lines);
    assert((%len(lines(i)) > 2):
           'line ' + %char(i) + ' was rendered at all');
    assert((%scan('|': lines(i)) <> SCOUT_BAR_COLUMN):
           'line ' + %char(i) + ': no bar in column 22');
    assert((%subst(lines(i): 1: 2) <> '  '):
           'line ' + %char(i) + ': does not begin with the two spaces a row does');
  endfor;

end-proc;

//==============================================================================
// No narration line carries trailing whitespace - MEASURED, WITH A CONTROL
//
// This block used to say the opposite: that the document could not testify
// about trailing whitespace, because `show` strips the terminal '$' and
// markdown does not preserve a trailing space, so the absence recorded there
// might be the transcription's rather than upstream's.
//
// It is settled now, and settled in the way that makes it evidence instead of
// silence. The same probe run captured a `check` row alongside the narration:
//
//   [  RUNNING            | rmscd2_batch (RMSC D2 batch) ]   <- space present
//   [Service 'RMSC D2 narrate' successfully started]         <- none
//
// THE CONTROL IS THE WHOLE POINT. A method that showed nothing on either line
// would prove nothing; this one demonstrably shows a trailing space where one
// exists, and shows none on any narration line. That is the difference between
// "no trailing space was recorded" and "there is no trailing space".
//
// Worth its own test rather than being left to aEqualExact because house style
// here pulls the wrong way: the check row's trailing space IS the contract, is
// documented as such, and is the first thing anyone reads about this module.
//==============================================================================

dcl-proc test_narration_lines_have_no_trailing_blank export;

  dcl-s lines varchar(512) dim(5);
  dcl-s i     int(10);

  lines(1) = SCOUT_op_progress('START': 'rmscn_solo');
  lines(2) = SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED);
  lines(3) = SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_RUNNING);
  lines(4) = SCOUT_dep_start('zzdep': 'Quebec Bravo');
  lines(5) = SCOUT_dep_stop('Quebec Bravo');

  for i = 1 to %elem(lines);
    assert((%len(lines(i)) > 0):
           'line ' + %char(i) + ' was rendered at all');
    assert((%subst(lines(i): %len(lines(i)): 1) <> ' '):
           'line ' + %char(i) + ' ends in a space');
  endfor;

end-proc;

//##############################################################################
//##                                                                          ##
//##  THE FAILURE SIDE - four lines found by making a start FAIL              ##
//##                                                                          ##
//##############################################################################
//
// The four procedures above were specified from a probe that only ever watched
// services succeed. docs/messages.md § "The fifth state, and three messages
// nobody had seen" records what happened when one was made to fail: three of
// the four lines below were invisible until then, and one of those is on
// STDOUT.
//
// That is the general lesson and it is worth more than the four literals: a
// success-path probe measures the success path. It does not measure "what this
// command prints", and reading it as though it did is how a stdout line came to
// be missing from a document whose whole purpose is to list every line.
//
// BASIS. docs/messages.md gives these four as TEMPLATES - `<friendly>`,
// `<n>/<m>`, `JOBNAME:X`, `<path>` - rather than as four transcribed lines, so
// every literal below is the captured sentence with a value substituted into
// it. Where a real value from the same probe run exists it is used rather than
// invented: `RMSC gap partial` and `JOBNAME:ZZNOSUCHJOB` and the counts `1/2`
// all come from the PARTIAL check row captured in that same run,
//
//   PARTIAL (1/2)      | rmscg_part (RMSC gap partial) [not running at -->JOBNAME:ZZNOSUCHJOB]
//
// so the substitution is a transcription too, and not a plausible-looking
// guess. Marked SUBSTITUTED where that is what it is.
//==============================================================================

//==============================================================================
// The timeout error, and the ERROR: prefix that is part of it
//
// CAPTURED sentence, SUBSTITUTED name:
//
//   ERROR: Timed out waiting for service '<friendly>' to start
//
// SEPARATING VALUES:
//
//   the ERROR: prefix is IN the line   rules out the prefix being added by
//                                      whatever writes to stderr. It is not:
//                                      docs/messages.md shows the nested form
//                                      embedding this whole message, "ERROR:
//                                      prefix included", which is only possible
//                                      if the prefix belongs to the text.
//   the FRIENDLY name                  rules out RMSC's own habit. RMSC's
//                                      present text is `<short> did not start
//                                      within <n> seconds`, so both the name
//                                      AND the sentence change here.
//   no seconds count anywhere          rules out carrying RMSC's `<n> seconds`
//                                      across into upstream's wording, which is
//                                      the natural way to "translate" the old
//                                      line rather than replace it
//==============================================================================

dcl-proc test_err_timeout_captured export;

  dcl-s line varchar(512);

  line = SCOUT_err_timeout('RMSC gap partial');

  aEqualExact('ERROR: Timed out waiting for service ''RMSC gap partial'' ' +
              'to start': line: 'the captured timeout line');

  assert((%subst(line: 1: 7) = 'ERROR: '):
         'the ERROR: prefix is part of the text, not of the stream');
  assert((%scan('seconds': line) = 0):
         'no seconds count - that is RMSC''s wording, not upstream''s');

end-proc;

//==============================================================================
// The nested dependency error - TWO names, in opposite roles
//
// CAPTURED sentence, SUBSTITUTED values:
//
//   ERROR: Could not start dependency '<short>' for service '<friendly>': <nested>
//
// THIS IS THE SAME TRAP AS THE DEPENDENCY LINES, ONE LEVEL UP. The line carries
// two names, and they are not two names for one service: the first is the
// DEPENDENCY by its short name and the second is the DEPENDENT by its friendly
// name. Getting them the right way round is not a spelling question.
//
// SEPARATING VALUES. The fixture pair share no substring in either direction,
// so each of these is a real question:
//
//   'zzdep' inside the first quotes    rules out the dependent being named
//                                      first, which is the order the SENTENCE
//                                      suggests - "could not start X for Y"
//                                      reads as though X were the thing you
//                                      asked for
//   'Quebec Bravo' after "for service" rules out both names being the same
//                                      service's, and rules out short-short
//   short first, friendly second       asserted by position, so a line with
//                                      both names in the wrong places still
//                                      fails
//==============================================================================

dcl-proc test_err_dep_failed_captured export;

  dcl-s line varchar(512);

  line = SCOUT_err_dep_failed('zzdep': 'Quebec Bravo':
                              'ERROR: Timed out waiting for service ' +
                              '''Bravo Two Narrate'' to start');

  aEqualExact('ERROR: Could not start dependency ''zzdep'' for service ' +
              '''Quebec Bravo'': ERROR: Timed out waiting for service ' +
              '''Bravo Two Narrate'' to start': line:
              'the captured nested line');

  assert((%scan('zzdep': line) < %scan('Quebec Bravo': line)):
         'the dependency is named before the dependent');

end-proc;

//==============================================================================
// The nested message is embedded WHOLE, its ERROR: prefix included
//
// docs/messages.md: "The nested form embeds the whole inner message, ERROR:
// prefix included."
//
// SEPARATING VALUE: the line contains the string 'ERROR:' TWICE. That is the
// one value that tells "embed the inner message" apart from "embed the inner
// message's payload", and the second is what any implementation that had a
// helper for stripping a prefix would produce - RMSC already has one in
// tools/error-delivery-test.sh's stderr_payload, and the idea of stripping a
// prefix before quoting is a natural one.
//
// Asserted by counting rather than by scanning once, because the outer prefix
// alone satisfies a single scan.
//
// The second case pins the other half: the nested text is passed through
// UNALTERED, the contract SCOUT_not_running_suffix and SCOUT_invalid_criteria
// both have. The rendering happened before this procedure was called.
//==============================================================================

dcl-proc test_err_dep_failed_embeds_the_nested_error export;

  dcl-s line   varchar(512);
  dcl-s nested varchar(512);
  dcl-s pos    like(INTEGER_t);
  dcl-s n      like(INTEGER_t);

  nested = 'ERROR: Timed out waiting for service ''Bravo Two Narrate'' to start';
  line   = SCOUT_err_dep_failed('zzdep': 'Quebec Bravo': nested);

  // Count the occurrences of ERROR: - there must be two, the outer and the
  // inner. One means the inner prefix was stripped on the way in.
  n = 0;
  pos = %scan('ERROR:': line);
  dow pos > 0;
    n = n + 1;
    pos = %scan('ERROR:': line: pos + 1);
  enddo;
  iEqual(2: n: 'ERROR: appears twice - the inner prefix survives');

  // And the nested text appears in the line exactly as it was handed over.
  assert((%scan(nested: line) > 0):
         'the nested message is embedded verbatim');
  aEqualExact(nested: %subst(line: %len(line) - %len(nested) + 1):
              'and it is the tail of the line, nothing after it');

end-proc;

//==============================================================================
// The fifth state - a different shape, and NOT a fifth sibling
//
// CAPTURED sentence, SUBSTITUTED name:
//
//   Service '<friendly>' is already partially running. You may need to restart
//   if this operation fails.
//
// TWO SENTENCES, both with full stops, one space between them. That alone is
// what makes it a different shape from the four states, none of which ends in
// a full stop at all.
//
// WHY IT IS ITS OWN PROCEDURE AND NOT A FIFTH SCOUT_svc_state CONSTANT:
// docs/messages.md measured it on STDERR where the other four are on stdout.
// A fifth constant would put it on the wrong stream, and it would do so
// silently - the caller would have no way to know that one value out of five
// had to be routed differently. The stream itself is asserted in
// tools/narration-test.sh; what is asserted here is that the two things do not
// render alike, so nothing can quietly be folded into the other.
//
// SEPARATING VALUES:
//
//   ends in a full stop        rules out the four states' shape
//   contains 'You may need'    rules out truncating at the first sentence,
//                              which is what a line-length limit or a
//                              copy-paste from the table's first clause gives
//   differs from all four      rules out it being reachable through
//   states for one name        SCOUT_svc_state at all
//==============================================================================

dcl-proc test_svc_partial_captured export;

  dcl-s line varchar(512);

  line = SCOUT_svc_partial('RMSC gap partial');

  aEqualExact('Service ''RMSC gap partial'' is already partially running. ' +
              'You may need to restart if this operation fails.': line:
              'the captured partial line, both sentences');

  assert((%subst(line: %len(line): 1) = '.'):
         'it ends in a full stop, which no state line does');
  assert((%scan('You may need': line) > 0):
         'the second sentence survives');

end-proc;

//==============================================================================
// The partial line is not any of the four states
//
// Stated directly, because "add a fifth constant" is the change an implementer
// reading docs/parity.md's family table would make - that table lists it
// alongside the other four as a `partial` kind, and only the re-probe
// separated them.
//==============================================================================

dcl-proc test_svc_partial_is_not_a_state export;

  dcl-s partial varchar(512);

  partial = SCOUT_svc_partial('Alpha One Narrate');

  assert((partial <> SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED)):
         'not the started line');
  assert((partial <> SCOUT_svc_state('Alpha One Narrate': SCOUT_STOPPED)):
         'not the stopped line');
  assert((partial <> SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_RUNNING)):
         'not the already-running line');
  assert((partial <> SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_STOPPED)):
         'not the already-stopped line');

  assert((%scan('partially': partial) > 0): 'and it says partially');
  assert((%scan('partially':
                SCOUT_svc_state('Alpha One Narrate': SCOUT_ALREADY_RUNNING)) = 0):
         'while the already-running line does not');

end-proc;

//==============================================================================
// The n/m warning, and the two arrows that are not the same arrow
//
// CAPTURED sentence, SUBSTITUTED values from the same probe run:
//
//   WARNING: Service '<friendly>' only <n>/<m> started
//            [failed to start --> [not running at -->JOBNAME:X]]
//
// THE DETAIL THAT WILL BE GOT WRONG. There are two arrows and they are spaced
// differently:
//
//   outer:  'failed to start --> ['     space before AND after
//   inner:  'not running at -->JOB'     space before, NONE after
//
// The inner one is not a coincidence: it is byte-for-byte what
// SCOUT_not_running_suffix already produces, and this suite already pins it -
// "no space either side of it" - in test_not_running_suffix_single. So the
// inner bracket is not re-rendered here, it is COMPOSED from the existing
// procedure, and the test composes it the same way. An implementation that
// wrote the inner text out again would be free to space it either way and
// nothing but this would notice.
//
// SEPARATING VALUES:
//
//   '--> [' with a space       rules out copying the inner spacing outward
//   '-->JOBNAME' with none     rules out copying the outer spacing inward
//   two closing brackets       rules out one bracket, which is what writing
//                              the line out by eye produces
//   'only 1/2 started'         rules out 'PARTIAL (1/2)' being reused here -
//                              the same two numbers, a different rendering
//==============================================================================

dcl-proc test_only_started_captured export;

  dcl-s line varchar(512);

  line = SCOUT_only_started('RMSC gap partial': 1: 2:
                            SCOUT_not_running_suffix('JOBNAME:ZZNOSUCHJOB'));

  aEqualExact('WARNING: Service ''RMSC gap partial'' only 1/2 started ' +
              '[failed to start --> [not running at -->JOBNAME:ZZNOSUCHJOB]]':
              line: 'the captured n/m warning');

  assert((%scan('--> [': line) > 0):
         'the outer arrow has a space after it');
  assert((%scan('-->JOBNAME:ZZNOSUCHJOB': line) > 0):
         'and the inner arrow has none');
  aEqualExact(']]': %subst(line: %len(line) - 1: 2):
              'two closing brackets, inner then outer');
  assert((%scan('PARTIAL': line) = 0):
         'the counts are rendered bare, not as a PARTIAL status');

end-proc;

//==============================================================================
// The inner bracket is SCOUT_not_running_suffix's output, unaltered
//
// Stated without a second literal, the way
// test_check_row_suffix_is_pure_append states its contract: whatever
// SCOUT_not_running_suffix returns must appear inside this line verbatim, so a
// change to the suffix's format can only break in one place rather than two.
//
// Three criterion forms, because the suffix already passes an already-joined
// list through and this must not start re-spacing one.
//==============================================================================

dcl-proc test_only_started_nests_the_existing_suffix export;

  dcl-s suffix varchar(512);
  dcl-s line   varchar(512);

  suffix = SCOUT_not_running_suffix('JOBNAME:ZZNOSUCHJOB');
  line   = SCOUT_only_started('RMSC gap partial': 1: 2: suffix);
  assert((%scan(suffix: line) > 0): 'the job form appears verbatim');

  suffix = SCOUT_not_running_suffix('PORT:55999');
  line   = SCOUT_only_started('RMSC gap partial': 1: 2: suffix);
  assert((%scan(suffix: line) > 0): 'the port form appears verbatim');

  suffix = SCOUT_not_running_suffix('PORT:55998, JOBNAME:NOSUCHJOB3');
  line   = SCOUT_only_started('RMSC gap partial': 1: 3: suffix);
  assert((%scan(suffix: line) > 0): 'a joined list is not re-spaced');

  // The counts are rendered as given, with no special cases - the same
  // contract SCOUT_partial_status has and for the same reason.
  assert((%scan('only 1/3 started': line) > 0): 'one of three');

end-proc;

//==============================================================================
// The log-file line - the one on STDOUT
//
// CAPTURED sentence, SUBSTITUTED path:
//
//   For details, see log file at: <path>
//
// THIS IS THE LINE THAT MATTERS MOST IN THIS BLOCK AND IT WAS IN NO CATALOGUE.
// It goes to STDOUT - the stream the consumer parses by column position - and
// it arrives only on a start that FAILED, which is the one path a success probe
// never reaches. Every other line the failure probe found went to stderr.
//
// So it is the exact shape of the defect CLAUDE.md opens with, arriving by the
// door nobody was watching: not a formatting slip in a good row, and not an
// error line on the wrong stream, but a line that upstream deliberately puts on
// stdout and that nothing had ever seen.
//
// SEPARATING VALUES:
//
//   the colon and ONE space    rules out 'at:<path>' and 'at : <path>'
//   the path is the tail       rules out anything after it - a full stop, a
//                              bracket, or a trailing space
//   comma after 'details'      rules out 'For details see', which is what the
//                              sentence reads like when it is retyped
//
// Its not-a-check-row property is asserted with the rest, below, and for this
// line that assertion is not a formality.
//==============================================================================

dcl-proc test_log_detail_captured export;

  dcl-s line varchar(512);
  dcl-s path varchar(512);

  path = '/QOpenSys/var/log/rmscg_part.log';
  line = SCOUT_log_detail(path);

  aEqualExact('For details, see log file at: ' + path: line:
              'the captured log-file line');

  assert((%scan('For details, see': line) = 1):
         'the comma is after "details"');
  aEqualExact(path: %subst(line: %len(line) - %len(path) + 1):
              'the path is the tail of the line, with nothing after it');

  // A second path, so the assertion is about the format and not about one
  // string. A path containing a space is the one that would break a naive
  // implementation that trimmed.
  path = '/home/someone/a directory/svc.log';
  aEqualExact('For details, see log file at: ' + path:
              SCOUT_log_detail(path): 'a path containing a space');

end-proc;

//==============================================================================
// The failure lines are not check rows either - and one of them is on stdout
//
// The same confirmation docs/parity.md asks for, extended to the four lines
// the failure probe found. SCOUT_log_detail's is the one that has to pass it:
// the other three go to stderr, and stderr is not the stream the consumer
// reads. This one IS.
//
// The n/m warning is the other to watch. It carries two bracket pairs and a
// parenthesis-free name, so it cannot yield a description field - but it is the
// longest and most punctuated line in the whole family, and "it does not happen
// to match" is worth an assertion rather than a reading.
//==============================================================================

dcl-proc test_failure_lines_are_not_check_rows export;

  dcl-s lines varchar(512) dim(4);
  dcl-s i     int(10);

  lines(1) = SCOUT_err_timeout('RMSC gap partial');
  lines(2) = SCOUT_err_dep_failed('zzdep': 'Quebec Bravo':
                                  SCOUT_err_timeout('Bravo Two Narrate'));
  lines(3) = SCOUT_svc_partial('RMSC gap partial');
  lines(4) = SCOUT_only_started('RMSC gap partial': 1: 2:
                                SCOUT_not_running_suffix('JOBNAME:ZZNOSUCHJOB'));

  for i = 1 to %elem(lines);
    assert((%len(lines(i)) > 2):
           'line ' + %char(i) + ' was rendered at all');
    assert((%scan('|': lines(i)) <> SCOUT_BAR_COLUMN):
           'line ' + %char(i) + ': no bar in column 22');
    assert((%subst(lines(i): 1: 2) <> '  '):
           'line ' + %char(i) + ': does not begin with two spaces');
    assert((%subst(lines(i): %len(lines(i)): 1) <> ' '):
           'line ' + %char(i) + ': no trailing whitespace');
  endfor;

end-proc;

//==============================================================================
// The stdout one, on its own, because it is the one that could hurt
//
// Separated from the loop above so that a failure names it rather than naming
// "line 5". A path is caller-supplied and could contain anything, so the
// assertion is made against a path chosen to be as row-like as a path can be:
// one with a parenthesised component in it. If SCOUT_log_detail ever gained a
// prefix of two spaces, this and nothing else would say so.
//==============================================================================

dcl-proc test_log_detail_is_not_a_check_row export;

  dcl-s line varchar(512);

  line = SCOUT_log_detail('/home/x/log (old)/svc.log');

  assert((%len(line) > 2): 'the line was rendered');
  assert((%subst(line: 1: 2) <> '  '):
         'it does not begin with the two spaces a check row begins with');
  assert((%scan('|': line) <> SCOUT_BAR_COLUMN):
         'and it has no bar in column 22 - this line is on STDOUT');

end-proc;

//##############################################################################
//##                                                                          ##
//##  SILENCE - the switch that decides whether a human is watching           ##
//##                                                                          ##
//##############################################################################
//
// WHAT THIS BLOCK CAN AND CANNOT REACH, STATED FIRST BECAUSE IT DECIDES
// EVERYTHING BELOW.
//
// RMSC has two entry points sharing one engine. The command line runs
// SCRUN -> SCMAIN -> SCEXEC. A bound-call API in SCAPI - for an ILE program,
// typically a green-screen one with a display file on the screen - runs
// SC_start/SC_stop/SC_kill/SC_restart -> SCEXEC. SCAPI's own header promises:
// "Nothing here writes to standard output: a green-screen program calling this
// must not have stray text appear underneath its display file, so status is
// returned rather than printed."
//
// The narration is emitted from SCEXEC, so it prints on BOTH paths and that
// promise is broken. The loader warnings have been reaching an API caller's
// stderr since earlier work. One switch is to silence both, for the API path
// only.
//
// THE SWITCH'S EFFECT IS AN ABSENCE ON A FILE DESCRIPTOR, AND NOTHING IN THIS
// FILE CAN SEE IT. iRPGUnit runs inside the ILE job whose descriptor 1 is the
// subject; a suite cannot capture its own stdout. So "while silent,
// SCOUT_writeln and SCOUT_warnln write nothing" is not asserted here, in any
// form, and no assertion below is an absence at all - which is why none of them
// needs the companion discipline the narration block above uses.
//
// It is asserted in tools/api-silence-test.sh, which drives
// qtestsrc/SCAPIDRV.PGM.RPGLE - a caller of the API that is CALLable from
// `system -kpieO`, writes nothing itself, and reports through a file - and
// requires both of its streams to be byte-empty, with a companion `scr` run
// proving each suppressed line would otherwise have been there.
//
// WHAT IS LEFT FOR THIS FILE IS THE FLAG'S OWN CONTRACT, and it is worth having
// because three of the four ways to get this wrong are visible from here: a
// setter that does not take, a flag entangled with the colour flag it was
// copied from, and a silence that reaches the RENDERING rather than the
// writing. The last of those is the one that would do real damage, and it is
// the one an implementation is most likely to arrive at.
//
// PROPOSED prototypes, in the idiom of the existing colour pair and exported at
// the END of RMSC.BND's list - CLAUDE.md: the signature pins export ORDER, so
// one inserted in the middle silently rebinds every caller after it.
//
//   dcl-pr SCOUT_set_silent;
//     on_or_off like(BOOLEAN_t) const;
//   end-pr;
//
//   dcl-pr SCOUT_silent like(BOOLEAN_t);
//   end-pr;
//
// THIS SUITE WILL NOT COMPILE UNTIL THEY EXIST. That is deliberate and it is
// the first red: a suite that could not name the procedures it is about would
// have nothing to say.
//==============================================================================

//==============================================================================
// The flag starts OFF - measured at the earliest moment reachable
//
// THE HAZARD THIS TEST IS SHAPED AROUND. The flag is MODULE state, so it lives
// for the whole activation and not for the call, and every procedure in this
// suite shares one activation. A test that called SCOUT_silent() in its own
// body would be reading whatever the previously-run test left behind - and
// iRPGUnit's ORDER(*API) does not promise an order, so the value would depend
// on something nobody controls. It would pass or fail by luck and would look
// like a test of the default.
//
// So the value is captured in setUpSuite, which runs ONCE and before every test
// procedure, and this case asserts the captured value. That is the module's
// state at the first moment anything in this suite touched it, which is as
// close to "the default" as an activation-scoped flag allows.
//
// WHAT IT STILL CANNOT PROVE, and the limit is worth writing down rather than
// glossing: it is the value at the start of THIS suite's run, not the value a
// freshly activated service program has. If something else in the same job had
// already switched it on, this would report that and call it the default. The
// question is settled properly outside the job - see tools/api-silence-test.sh
// § "WHAT THIS SCRIPT CANNOT ASSERT", which records what a driver operation
// reading SCOUT_silent() before any API call would add, and why it is not there
// yet.
//
// THE SEPARATING VALUE IS `false` ITSELF, and it is the whole design: the
// command line must be unaffected, so a flag that defaulted ON would mute
// RMSC's own output everywhere. The rival - "default on, and SCMAIN turns it
// off" - is a real alternative shape and this rules it out.
//
// AND THE THIRD RIVAL IS "setUpSuite NEVER RAN". It is the one this case was
// blind to: an unassigned global is *off, which is the value asserted, so a
// suite whose set-up had been renamed, stopped being exported, or stopped
// touching the field would pass here on a value nobody had read. The global is
// therefore seeded with *on - see its declaration - so the omission produces
// the same red as a flag that really did default on, and the message below
// names both readings.
//==============================================================================

dcl-proc test_silent_starts_off export;

  nEqual(false: g_silent_at_suite_start:
         'silence was already ON when this suite started - either the ' +
         'default is ON, and the command line is muted by a switch nobody ' +
         'asked for, or setUpSuite did not run and this field still holds ' +
         'the *on it was seeded with. Both are real; check setUpSuite first');

end-proc;

//==============================================================================
// The setter takes, in both directions
//
// SEPARATING VALUES: both of them, and neither alone is enough. A getter
// hard-wired to false satisfies the off case; one hard-wired to true satisfies
// the on case; only asking for both tells either from a working pair. The same
// reason test_svc_state_four_states_are_distinct asserts its states pairwise
// rather than one at a time.
//
// The off-then-on-then-off sequence also pins that the flag can be turned back
// OFF, which is not implied by a setter that works once - and which matters,
// because setUp below relies on it to keep this suite's tests independent.
//==============================================================================

dcl-proc test_silent_round_trips export;

  SCOUT_set_silent(false);
  nEqual(false: SCOUT_silent(): 'off after being set off');

  SCOUT_set_silent(true);
  nEqual(true: SCOUT_silent(): 'on after being set on');

  SCOUT_set_silent(false);
  nEqual(false: SCOUT_silent(): 'and off again');

  // Setting it to the value it already holds is not a toggle. Cheap, and it
  // rules out the one implementation that satisfies every assertion above -
  // a setter that ignores its argument and flips.
  SCOUT_set_silent(true);
  SCOUT_set_silent(true);
  nEqual(true: SCOUT_silent(): 'setting on twice leaves it on');

  SCOUT_set_silent(false);

end-proc;

//==============================================================================
// Silence and colour are two flags, not one
//
// WHY THIS IS NOT PARANOIA. The silence pair is specified "in the same idiom as
// the existing colour pair", and the fastest way to write it is to copy
// SCOUT_set_colour and SCOUT_colour and edit the names. The one thing a
// copy-paste of that shape reliably gets wrong is the variable in the middle:
// two setters writing one field, or the new getter reading the old field.
//
// It would be invisible in ordinary use, because the command line sets colour
// and never sets silence, and SCAPI sets silence and never sets colour - so the
// two are never both moved in one job except here.
//
// AND IT WOULD MATTER. Colour off when stdout is not a terminal is what keeps
// escape sequences out of the columns a consumer parses, and CLAUDE.md's first
// warning is that a slip there is silent. A silence switch that turned colour
// back ON would put escapes into `check` output on the one path nobody watches.
//
// SEPARATING VALUES: each flag is moved while the other is held, in both
// directions, and the held one is read afterwards. Four combinations, because
// two would agree with a single shared field in half of them.
//==============================================================================

dcl-proc test_silent_and_colour_are_independent export;

  // Colour off, silence moved: colour must not follow it
  SCOUT_set_colour(false);
  SCOUT_set_silent(true);
  nEqual(false: SCOUT_colour(): 'colour stays off when silence goes on');
  SCOUT_set_silent(false);
  nEqual(false: SCOUT_colour(): 'and when silence goes off again');

  // Colour on, silence moved
  SCOUT_set_colour(true);
  SCOUT_set_silent(true);
  nEqual(true: SCOUT_colour(): 'colour stays on when silence goes on');
  nEqual(true: SCOUT_silent(): 'and silence is on, not merely colour read twice');
  SCOUT_set_silent(false);
  nEqual(true: SCOUT_colour(): 'colour still on after silence goes off');

  // Silence on, colour moved: silence must not follow it
  SCOUT_set_silent(true);
  SCOUT_set_colour(false);
  nEqual(true: SCOUT_silent(): 'silence stays on when colour goes off');
  SCOUT_set_colour(true);
  nEqual(true: SCOUT_silent(): 'and when colour goes on');

  SCOUT_set_colour(false);
  SCOUT_set_silent(false);

end-proc;

//==============================================================================
// Silence suppresses WRITING, not RENDERING
//
// THE ASSERTION IN THIS BLOCK WITH THE MOST AT STAKE, and the reason it is
// worth writing even though the absence itself is out of reach.
//
// "While silent, SCOUT writes nothing" has a wrong reading that is very easy to
// arrive at: put the test in SCOUT and let it cover everything SCOUT produces,
// so that SCOUT_check_row and its family return blanks too. Every existing
// assertion in this file would still pass, because every one of them runs with
// silence off.
//
// IT WOULD BE A SEVERE DEFECT AND A QUIET ONE. SCAPI is the caller that turns
// silence on, and SCAPI's entire job is to RETURN rendered status text -
// SC_STATUS_ROW_t's STATUS field is what a subfile program displays. A silence
// that reached the renderers would empty the status column of every row a
// green-screen program showed, on the one path where nothing is printed and
// nothing raises an error. That is CLAUDE.md's opening warning - a formatting
// slip that makes services vanish from a screen rather than raising an error -
// arriving through the API instead of through the pipe.
//
// SEPARATING VALUE: the SAME call, made twice, once with silence off and once
// with it on, compared byte for byte with aEqualExact. It is stated as an
// equality between two live calls rather than against a literal, so a change to
// the check row's format can only break this in one place rather than two - the
// contract test_check_row_suffix_is_pure_append already uses.
//
// Every renderer that produces something a caller could be handed is covered,
// not just the check row: the API returns status text, and a later change that
// routed a warning line through the API would want the same guarantee.
//==============================================================================

dcl-proc test_silence_does_not_change_what_is_rendered export;

  dcl-s loud_row   varchar(512);
  dcl-s quiet_row  varchar(512);
  dcl-s loud_txt   varchar(512);
  dcl-s quiet_txt  varchar(512);

  SCOUT_set_colour(false);

  SCOUT_set_silent(false);
  loud_row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');
  SCOUT_set_silent(true);
  quiet_row = SCOUT_check_row(SCOUT_RUNNING: 'webproxy': 'Web Proxy');

  aEqualExact(loud_row: quiet_row:
              'the check row is the same while silent - silence stops the ' +
              'WRITING, and a row that came back blank would empty the ' +
              'status column of every row a green-screen caller displays');

  // The row a caller is most likely to be handed on the API path is a PARTIAL
  // one, because it is the one that carries a suffix and therefore the most
  // rendering.
  SCOUT_set_silent(false);
  loud_row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzsport':
                             'Probe zzsport':
                             SCOUT_not_running_suffix('PORT:55999'));
  SCOUT_set_silent(true);
  quiet_row = SCOUT_check_row(SCOUT_partial_status(1: 2): 'zzsport':
                              'Probe zzsport':
                              SCOUT_not_running_suffix('PORT:55999'));
  aEqualExact(loud_row: quiet_row: 'the PARTIAL row too, suffix and all');

  // And the rest of the family, so a fix that special-cased the check row is
  // not mistaken for one that put the switch in the right layer.
  SCOUT_set_silent(false);
  loud_txt = SCOUT_list_row('webproxy': 'Web Proxy');
  SCOUT_set_silent(true);
  quiet_txt = SCOUT_list_row('webproxy': 'Web Proxy');
  aEqualExact(loud_txt: quiet_txt: 'the list row');

  SCOUT_set_silent(false);
  loud_txt = SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED);
  SCOUT_set_silent(true);
  quiet_txt = SCOUT_svc_state('Alpha One Narrate': SCOUT_STARTED);
  aEqualExact(loud_txt: quiet_txt: 'a narration line still renders');

  SCOUT_set_silent(false);
  loud_txt = SCOUT_err_timeout('RMSC gap partial');
  SCOUT_set_silent(true);
  quiet_txt = SCOUT_err_timeout('RMSC gap partial');
  aEqualExact(loud_txt: quiet_txt:
              'and so does an error line - SCAPI has to RETURN this text ' +
              'even when it must not print it');

  SCOUT_set_silent(false);
  loud_txt = SCOUT_no_services_warning('all');
  SCOUT_set_silent(true);
  quiet_txt = SCOUT_no_services_warning('all');
  aEqualExact(loud_txt: quiet_txt: 'and the empty-collection warning');

  SCOUT_set_silent(false);

end-proc;

//==============================================================================
// SCOUT_is_tty does not read the silence flag
//
// THIS CASE USED TO CLAIM MORE THAN IT COULD SHOW, and the correction is worth
// keeping rather than quietly deleting.
//
// It was written to catch a short-circuiting implementation - "if silent, do
// not bother working anything out" - which is a plausible efficiency and would
// leave SCOUT_is_tty answering false whenever silence was on. It cannot catch
// it. iRPGUnit runs in a spawned batch job, so false is ALSO the correct
// answer here, and the two readings agree on every value this suite can
// produce. An assertion that both readings satisfy is not evidence for either.
//
// SO WHAT IS PINNED HERE IS THE NARROWER THING THE NAME NOW SAYS: the answer
// does not MOVE when the silence flag moves. The separating value is the
// equality itself, in both directions - off then on then off again - so an
// implementation that made the terminal question depend on the silence flag in
// EITHER direction fails, and one that simply never looks at it passes. It is
// the honest half of the original claim.
//
// WHAT WOULD BE NEEDED TO RULE OUT THE SHORT-CIRCUIT, and why it is not here:
// a caller whose stdout really is a terminal, where the two readings predict
// true and false. Nothing in this project has one. tools/api-silence-test.sh
// and tools/narration-test.sh both redirect both streams to files, which is the
// same false again, and a suite cannot attach a pty to its own job. It is
// recorded as unreachable rather than approximated, for the reason CLAUDE.md
// gives about fixtures that are absent.
//
// THE NEIGHBOURING RIVAL IS COVERED, and by a case that does have a separating
// value: test_silent_and_colour_are_independent holds colour at TRUE across a
// silence change, and true is a value no short-circuit and no shared field can
// produce by accident.
//==============================================================================

dcl-proc test_is_tty_does_not_move_with_silence export;

  dcl-s before like(BOOLEAN_t);
  dcl-s quiet  like(BOOLEAN_t);
  dcl-s after  like(BOOLEAN_t);

  SCOUT_set_silent(false);
  before = SCOUT_is_tty();
  SCOUT_set_silent(true);
  quiet = SCOUT_is_tty();
  SCOUT_set_silent(false);
  after = SCOUT_is_tty();

  nEqual(before: quiet:
         'the terminal question was answered one way with silence off and ' +
         'another with it on - SCOUT_is_tty is reading the silence flag');
  nEqual(before: after:
         'and the answer did not come back when silence went off again');

end-proc;
