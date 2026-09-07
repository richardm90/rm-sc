**free

//==============================================================================
// SCMAIN.TEST - command line parsing test suite
//
// SCMAIN_parse is a pure function over one string: no files, no system state,
// no network. `scr check webproxy -v` arrives here as 'check webproxy -v'.
// That makes it the cheapest thing in the project to test exhaustively, and
// until now the only module with no suite at all - every option, every
// operation and the whole exit-status surface rested on nothing.
//
// The suite therefore has two jobs:
//
//   1. Pin the behaviour that already exists. Most of it was established by
//      measurement against upstream sc 1.7.1 and none of it was held by a
//      test, so a change could alter any of it silently. The order-dependence
//      of -a is the most valuable single case here: it was a real defect
//      until recently, and it is invisible to any test that does not run the
//      same two arguments in both orders.
//
//   2. State the contract for the return value. SCMAIN_parse returns an EXIT
//      STATUS, not a boolean, and opts.err carries anything still to be said:
//
//        parsed fine                     ->   0, err empty
//        parsed fine, worth a warning    ->   0, err holds the warning
//        could not be understood         -> 255, err holds the message
//
//      The caller prints err when it is non-empty and exits with the status,
//      so status 0 with a message means "worked, say this", and a non-zero
//      status with a message means "failed, say this". The status no longer
//      has to be inferred from which procedure returned false.
//
// Nothing here exercises the middle row, because the two upstream cases that
// warn and carry on - an unrecognised option, and --version - are both
// refused by RMSC today. Those two tests pin RMSC's refusal and record in
// place what upstream does instead, so that when the decision is taken it
// lands as a failing test rather than passing unnoticed. See
// test_unknown_option_refused and test_version_refused.
//
// No setUpSuite or tearDownSuite: there is no fixture to build, nothing is
// written and nothing is left behind. Every options structure is declared
// inz(*likeds) - likeds() does not inherit the template's inz, and an
// uninitialised structure here would carry garbage length prefixes on every
// varying field.
//
// Service names are invented. This repository is public.
//
// 01/09/2026 - RM - created
//==============================================================================

ctl-opt nomain;
// RMSCPGM brings in RMSC.SRVPGM, which exports SCMAIN_parse. RMSCDEPS is
// listed for the same reason the other suites list it: the rmtools code is
// bound by copy into RMSC.SRVPGM and so is not reachable through its exports.
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCMAIN_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include QINCLUDE,TESTCASE

// The two exit statuses, named so the assertions read as the contract rather
// than as two magic numbers.
dcl-c PARSE_OK     const(0);
dcl-c PARSE_USAGE  const(255);

dcl-pr parse_args like(INTEGER_t);
  args like(SCMAIN_ARGS_t) const;
  opts likeds(SCMAIN_OPTS_t);
end-pr;

dcl-pr aEqualV;
  expected  varchar(1024) const;
  actual    varchar(1024) const;
  fieldName varchar(128) const;
end-pr;

dcl-pr assert_message_set;
  opts likeds(SCMAIN_OPTS_t) const;
  ctx  varchar(64) const;
end-pr;

dcl-pr assert_no_message;
  opts likeds(SCMAIN_OPTS_t) const;
  ctx  varchar(64) const;
end-pr;

dcl-pr assert_message_names;
  opts likeds(SCMAIN_OPTS_t) const;
  want varchar(64) const;
  ctx  varchar(64) const;
end-pr;

dcl-pr mk_value varchar(1024);
  len  like(INTEGER_t) const;
  tail varchar(64) const;
end-pr;

dcl-pr mk_digits varchar(1024);
  len like(INTEGER_t) const;
end-pr;

//==============================================================================
// Helpers
//==============================================================================

///
// parse_args - parse into a template-fresh options structure.
//
// For the tests that parse more than one command line. `clear` is NOT the way
// to reuse a structure here: it sets every field to blanks and zeros, not to
// the template's initial values, so a second parse would start from
// ignore_groups = '' rather than from 'system' and the test would be asking a
// different question than it looks like it is asking.
//
// Assigning from a locally declared inz(*likeds) structure gives the same
// starting point the caller idiom gives - the template's own defaults - on
// every call.
///
dcl-proc parse_args;
  dcl-pi *n like(INTEGER_t);
    args like(SCMAIN_ARGS_t) const;
    opts likeds(SCMAIN_OPTS_t);
  end-pi;

  dcl-ds fresh likeds(SCMAIN_OPTS_t) inz(*likeds);

  opts = fresh;

  return SCMAIN_parse(args: opts);

end-proc;

///
// aEqualV - compare varying-length values.
//
// iRPGUnit's aEqual is declared opdesc with char(32565) options(*varsize), so
// it takes each argument's length from the operational descriptor, and for a
// varying-length array element inside a data structure that length is the
// PREVIOUS element's. Scalars and return values are unaffected, but this
// suite uses aEqualV for every varying value rather than relying on the
// reader remembering which comparisons are safe. A plain RPG comparison has
// no descriptor involved at all.
///
dcl-proc aEqualV;
  dcl-pi *n;
    expected  varchar(1024) const;
    actual    varchar(1024) const;
    fieldName varchar(128) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(fieldName) + ': expected "' + %trim(expected) +
         '" but was "' + %trim(actual) + '"');

end-proc;

///
// A failing parse must say why. The caller prints opts.err and exits with the
// status, so a non-zero status with an empty message exits silently - which
// to a user looks exactly like a program that fell over.
///
dcl-proc assert_message_set;
  dcl-pi *n;
    opts likeds(SCMAIN_OPTS_t) const;
    ctx  varchar(64) const;
  end-pi;

  assert((%trimr(opts.err) <> ''):
         %trim(ctx) + ': expected a message in opts.err, but it was empty');

end-proc;

///
// A clean parse must say nothing. Anything in err is printed, and on the
// check path anything printed is read by a consumer parsing by column.
///
dcl-proc assert_no_message;
  dcl-pi *n;
    opts likeds(SCMAIN_OPTS_t) const;
    ctx  varchar(64) const;
  end-pi;

  aEqualV('': opts.err: %trim(ctx) + ': opts.err');

end-proc;

//==============================================================================
// A bare operation parses, and every default is what the defaults say
//
// The whole default surface in one place. `scr check` with nothing else is
// the most common invocation there is, and every field below is a promise
// something downstream relies on.
//==============================================================================

dcl-proc test_defaults export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  sts  like(INTEGER_t);

  sts = SCMAIN_parse('check': opts);

  iEqual(PARSE_OK: sts: 'a bare operation parses');
  assert_no_message(opts: 'bare check');

  aEqualV('check': opts.operation: 'operation');
  aEqualV('': opts.spec: 'no specifier given');

  nEqual(false: opts.verbose:        'verbose off by default');
  nEqual(false: opts.quiet:          'quiet off by default');
  nEqual(false: opts.colours:        'colour off by default');
  nEqual(false: opts.splf:           'splf off by default');
  nEqual(false: opts.all:            'all off by default');
  nEqual(false: opts.ignore_globals: 'globals read by default');

  aEqualV('1': opts.sampletime: 'sampletime defaults to 1');

end-proc;

//==============================================================================
// --ignore-groups defaults to `system`, and that default is load-bearing
//
// A bare `check` is meant to show the services someone configured, not the
// dozens of host and TCP server definitions that ship under system/. The
// consumer screen-scrapes that output, so this default decides what appears
// on a screen. It gets its own test rather than only a line in test_defaults
// because it is the one default whose loss would look like data rather than
// like a bug.
//==============================================================================

dcl-proc test_ignore_groups_default_is_system export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check': opts): 'parse');
  aEqualV(SCMAIN_DFT_IGNORE: opts.ignore_groups: 'check ignores system');

  iEqual(PARSE_OK: parse_args('list': opts): 'parse');
  aEqualV(SCMAIN_DFT_IGNORE: opts.ignore_groups: 'list ignores system too');

  iEqual(PARSE_OK: parse_args('groups': opts): 'parse');
  aEqualV(SCMAIN_DFT_IGNORE: opts.ignore_groups: 'groups ignores system too');

end-proc;

//==============================================================================
// The first non-option word is the operation, the second is the specifier
//==============================================================================

dcl-proc test_operation_and_specifier export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('check webproxy': opts): 'parse');
  assert_no_message(opts: 'operation and specifier');
  aEqualV('check': opts.operation: 'first word is the operation');
  aEqualV('webproxy': opts.spec: 'second word is the specifier');

end-proc;

//==============================================================================
// `status` is upstream's alias for `check` and is normalised to it
//
// Normalised at parse time, so nothing downstream has to know about the
// alias. A consumer sending `status` must get identical output to `check`.
//==============================================================================

dcl-proc test_status_normalised_to_check export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('status webproxy': opts): 'parse');
  aEqualV('check': opts.operation: 'status becomes check');
  aEqualV('webproxy': opts.spec: 'specifier unaffected');

end-proc;

//==============================================================================
// Every operation RMSC accepts, accepted
//
// Fourteen words, one of which is the alias. This list is the command
// surface: losing one is how an operation stops existing without anything
// failing to compile, and accepting one upstream does not have is the same
// defect in the other direction.
//
// `reload` is deliberately absent - see test_reload_refused.
//==============================================================================

dcl-proc test_every_operation_accepted export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  ops  varchar(16) dim(14);
  dcl-s  want varchar(16);
  dcl-s  i    like(INTEGER_t);

  ops(1)  = 'check';
  ops(2)  = 'status';
  ops(3)  = 'start';
  ops(4)  = 'stop';
  ops(5)  = 'kill';
  ops(6)  = 'restart';
  ops(7)  = 'info';
  ops(8)  = 'file';
  ops(9)  = 'list';
  ops(10) = 'groups';
  ops(11) = 'jobinfo';
  ops(12) = 'loginfo';
  ops(13) = 'perfinfo';
  ops(14) = 'scrunattrs';

  for i = 1 to %elem(ops);

    iEqual(PARSE_OK: parse_args(ops(i) + ' webproxy': opts):
           'operation ' + %trim(ops(i)) + ' accepted');
    assert_no_message(opts: %trim(ops(i)));

    if ops(i) = 'status';
      want = 'check';
    else;
      want = ops(i);
    endif;

    aEqualV(want: opts.operation: 'operation ' + %trim(ops(i)));
    aEqualV('webproxy': opts.spec: 'specifier after ' + %trim(ops(i)));

  endfor;

end-proc;

//==============================================================================
// An unrecognised operation is a usage failure
//
// Measured on sc 1.7.1: `sc wibble` exits 255 and prints the usage line on
// stderr. Only the status and the presence of a message are pinned, not the
// wording - the wording is upstream's to change.
//==============================================================================

dcl-proc test_unknown_operation_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: parse_args('wibble': opts): 'unknown operation');
  assert_message_set(opts: 'wibble');

  iEqual(PARSE_USAGE: parse_args('wibble webproxy': opts):
         'unknown operation with a specifier');
  assert_message_set(opts: 'wibble webproxy');

end-proc;

//==============================================================================
// No operation at all is a usage failure
//
// Measured: bare `sc` exits 255 with the usage line. Blanks matter as much as
// the empty string - scr pads its argument to the full 1024 bytes before the
// CL CALL, so an empty command line arrives here as spaces.
//==============================================================================

dcl-proc test_no_operation_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: parse_args('': opts): 'empty command line');
  assert_message_set(opts: 'empty');

  iEqual(PARSE_USAGE: parse_args('      ': opts): 'blanks only');
  assert_message_set(opts: 'blanks');

end-proc;

//==============================================================================
// Options alone are not an operation
//
// `sc -h` exits 255 with the usage line upstream, which is what an
// options-only command line gets here too. Both -v, an option RMSC accepts,
// and -h, one it does not, must fail for want of an operation.
//==============================================================================

dcl-proc test_options_without_operation_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: parse_args('-v': opts):
         'a known option is still not an operation');
  assert_message_set(opts: '-v alone');

  iEqual(PARSE_USAGE: parse_args('-h': opts): '-h prints usage and fails');
  assert_message_set(opts: '-h');

end-proc;

//==============================================================================
// A third non-option word is refused
//
// Two positional words is the whole grammar: operation and specifier. A third
// is far more likely to be an unquoted specifier containing a space than
// anything anyone meant, and guessing which two of the three to keep would
// act on something nobody asked for.
//==============================================================================

dcl-proc test_third_word_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: SCMAIN_parse('check webproxy extra': opts):
         'three positional words');
  assert_message_set(opts: 'third word');

end-proc;

//==============================================================================
// -v and -q are independent flags
//
// Asserting that the OTHER flag stayed off matters as much as asserting the
// one under test came on: a parser that assigns to the wrong subfield passes
// every test that only looks at the field it expected to change.
//==============================================================================

dcl-proc test_verbose_and_quiet export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check -v': opts): 'parse -v');
  assert_no_message(opts: '-v');
  nEqual(true:  opts.verbose: '-v sets verbose');
  nEqual(false: opts.quiet:   '-v leaves quiet alone');

  iEqual(PARSE_OK: parse_args('check -q': opts): 'parse -q');
  assert_no_message(opts: '-q');
  nEqual(true:  opts.quiet:   '-q sets quiet');
  nEqual(false: opts.verbose: '-q leaves verbose alone');

end-proc;

//==============================================================================
// --splf
//==============================================================================

dcl-proc test_splf export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('start webproxy --splf': opts): 'parse');
  assert_no_message(opts: '--splf');
  nEqual(true: opts.splf: '--splf set');

end-proc;

//==============================================================================
// --ignore-globals
//==============================================================================

dcl-proc test_ignore_globals export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('check --ignore-globals': opts): 'parse');
  assert_no_message(opts: '--ignore-globals');
  nEqual(true: opts.ignore_globals: '--ignore-globals set');

  // It does not disturb the group default. The two are separate exclusions:
  // one is about which directories are read, the other about which groups are
  // displayed, and conflating them was how --ignore-globals came to be parsed
  // into a field nothing read.
  aEqualV(SCMAIN_DFT_IGNORE: opts.ignore_groups:
          'group default survives --ignore-globals');

end-proc;

//==============================================================================
// Both spellings of the colour options are accepted
//
// --colors/--colours is RMSC's own, not upstream's: scr appends it when
// [ -t 1 ] says stdout is a terminal, because isatty cannot be asked from
// ILE and job type is the wrong signal. --disable-colors/--disable-colours is
// upstream's. Both spellings exist because both are in circulation, and a
// user typing the British one must not get a usage failure.
//==============================================================================

dcl-proc test_colour_options export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check --colors': opts): 'parse --colors');
  assert_no_message(opts: '--colors');
  nEqual(true: opts.colours: '--colors sets colour');

  iEqual(PARSE_OK: parse_args('check --colours': opts): 'parse --colours');
  assert_no_message(opts: '--colours');
  nEqual(true: opts.colours: '--colours sets colour');

  iEqual(PARSE_OK: parse_args('check --disable-colors': opts):
         'parse --disable-colors');
  assert_no_message(opts: '--disable-colors');
  nEqual(false: opts.colours: '--disable-colors leaves colour off');

  iEqual(PARSE_OK: parse_args('check --disable-colours': opts):
         'parse --disable-colours');
  assert_no_message(opts: '--disable-colours');
  nEqual(false: opts.colours: '--disable-colours leaves colour off');

  // Colour on, then off, in that order.
  iEqual(PARSE_OK: parse_args('check --colors --disable-colors': opts):
         'parse');
  nEqual(false: opts.colours: 'disable after enable leaves colour off');

end-proc;

//==============================================================================
// --disable-colors must beat a --colors that follows it
//
// INFERRED, NOT MEASURED - and the one assertion in this suite that is a
// specification rather than a record of something observed.
//
// The reasoning: scr appends --colors AFTER the user's own arguments whenever
// stdout is a terminal. So `scr check --disable-colors` typed at a terminal
// reaches SCMAIN_parse as 'check --disable-colors --colors'. If the two
// options are simply last-wins, an explicit request to turn colour off is
// silently overridden every time it is made interactively - and interactively
// is the only time it is ever made, since colour is already off when stdout
// is not a terminal. An explicit disable therefore has to stick.
//
// Upstream cannot answer this: it has no --colors. The wrapper's argument
// order makes it ours to answer.
//
// A failure here is a real defect in colour precedence rather than a mistake
// in the test - but read the reasoning above before changing code.
//==============================================================================

dcl-proc test_disable_colours_beats_appended_colours export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('check --disable-colors --colors': opts):
         'parse');
  nEqual(false: opts.colours:
         'an explicit --disable-colors survives the appended --colors');

end-proc;

//==============================================================================
// --ignore-groups= REPLACES the default rather than adding to it
//
// This is upstream's measured behaviour, and it is why a $HOME/.scrc holding
// --ignore-groups=backend makes a bare `list` show MORE services rather than
// fewer: the supplied list replaces `system` instead of joining it.
//==============================================================================

dcl-proc test_ignore_groups_replaces_default export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check --ignore-groups=web': opts): 'parse');
  assert_no_message(opts: '--ignore-groups=web');
  aEqualV('web': opts.ignore_groups: 'replaces the system default');

  // Comma-separated, and kept whole: splitting it is the consumer's job, the
  // same way a comma-separated check_alive is kept whole by SCYAML.
  iEqual(PARSE_OK: parse_args('check --ignore-groups=web,db,backend': opts):
         'parse');
  aEqualV('web,db,backend': opts.ignore_groups: 'list kept whole');

end-proc;

//==============================================================================
// --sampletime= takes its value
//==============================================================================

dcl-proc test_sampletime export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('perfinfo webproxy --sampletime=5': opts):
         'parse');
  assert_no_message(opts: '--sampletime=5');
  aEqualV('5': opts.sampletime: 'sampletime taken from the argument');

end-proc;

//==============================================================================
// -a and --all clear the group exclusions
//
// -a is how a user asks to see everything, the system group included. It also
// turns --ignore-globals back off, which is what the two ordering tests below
// are about.
//==============================================================================

dcl-proc test_all_short_and_long export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('list -a': opts): 'parse -a');
  assert_no_message(opts: '-a');
  nEqual(true: opts.all: '-a sets all');
  aEqualV('': opts.ignore_groups: '-a clears the group exclusions');
  nEqual(false: opts.ignore_globals: '-a leaves globals being read');
  // -a is a flag, not a specifier. `list -a` and `list all` are different
  // command lines and only one of them fills spec.
  aEqualV('': opts.spec: '-a is not a specifier');

  iEqual(PARSE_OK: parse_args('list --all': opts): 'parse --all');
  assert_no_message(opts: '--all');
  nEqual(true: opts.all: '--all sets all');
  aEqualV('': opts.ignore_groups: '--all clears the group exclusions');
  aEqualV('': opts.spec: '--all is not a specifier');

end-proc;

//==============================================================================
// -a acts WHERE IT APPEARS, not at the end of parsing
//
// The most valuable pair in this suite. The ordering is upstream's, and
// getting it wrong was a real defect here until recently:
//
//   --ignore-globals --all   ends up READING globals   (-a undid it)
//   --all --ignore-globals   ends up IGNORING globals  (-a ran first)
//
// A parser that applies -a as a post-pass gives the same answer to both, and
// every single-order test still passes. Only running the same two arguments
// in both orders can tell the difference - which is why they are two tests
// and not one.
//==============================================================================

dcl-proc test_all_after_ignore_globals export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('check --ignore-globals --all': opts):
         'parse');
  nEqual(true:  opts.all: 'all set');
  nEqual(false: opts.ignore_globals:
         '-a after --ignore-globals turns it back off');
  aEqualV('': opts.ignore_groups: 'and clears the group exclusions');

end-proc;

dcl-proc test_all_before_ignore_globals export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: SCMAIN_parse('check --all --ignore-globals': opts):
         'parse');
  nEqual(true: opts.all: 'all set');
  nEqual(true: opts.ignore_globals:
         '--ignore-globals after -a stands - -a acted before it was given');
  aEqualV('': opts.ignore_groups:
          'groups stay cleared - --ignore-globals does not restore them');

end-proc;

//==============================================================================
// The same ordering rule for --ignore-groups
//
// -a clears the exclusions at the point it appears, so a list given after it
// stands and a list given before it does not.
//==============================================================================

dcl-proc test_all_and_ignore_groups_ordering export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check --ignore-groups=web --all': opts):
         'parse');
  aEqualV('': opts.ignore_groups: '-a clears a list given before it');

  iEqual(PARSE_OK: parse_args('check --all --ignore-groups=web': opts):
         'parse');
  aEqualV('web': opts.ignore_groups: 'a list given after -a stands');

end-proc;

//==============================================================================
// Options are accepted before the operation and after the specifier
//
// The usage line is `sc [options] <operation> <service>`, so leading options
// have to work; scr appends --colors to the end of whatever the user typed,
// so trailing options have to work too. Both positions are real ones.
//
// The leading position is INFERRED from the usage line rather than measured.
// The trailing position is how every colour-enabled invocation through scr
// arrives, so it is not inferred at all.
//==============================================================================

dcl-proc test_option_positions export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('-v check webproxy': opts):
         'options before the operation');
  assert_no_message(opts: 'leading option');
  nEqual(true: opts.verbose: 'leading -v honoured');
  aEqualV('check': opts.operation: 'operation still found');
  aEqualV('webproxy': opts.spec: 'specifier still found');

  // The shape every interactive `scr check webproxy` actually arrives in.
  iEqual(PARSE_OK: parse_args('check webproxy --colors': opts):
         'options after the specifier');
  nEqual(true: opts.colours: 'trailing --colors honoured');
  aEqualV('check': opts.operation: 'operation still found');
  aEqualV('webproxy': opts.spec: 'specifier still found');

  // Interleaved, either side of both positional words.
  iEqual(PARSE_OK: parse_args('-q check -v webproxy --splf': opts):
         'options either side of both words');
  nEqual(true: opts.quiet:   'leading -q');
  nEqual(true: opts.verbose: 'interleaved -v');
  nEqual(true: opts.splf:    'trailing --splf');
  aEqualV('check': opts.operation: 'operation');
  aEqualV('webproxy': opts.spec: 'specifier');

end-proc;

//==============================================================================
// Runs of blanks separate words, and are not words themselves
//
// Not a hypothetical. scr runs printf "%-1024s" over the argument string
// before the CL CALL, because a short character literal passed into a
// char(1024) parameter leaves the program reading whatever follows it in
// memory. So EVERY command line arriving through the wrapper carries hundreds
// of trailing blanks, and a parser that took a blank run for a word would
// refuse all of them as having a third positional word.
//==============================================================================

dcl-proc test_blank_runs_are_separators export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check    webproxy': opts):
         'a run of blanks between words');
  aEqualV('check': opts.operation: 'operation');
  aEqualV('webproxy': opts.spec: 'specifier');

  iEqual(PARSE_OK: parse_args('check webproxy          ': opts):
         'trailing blanks, as the wrapper always sends them');
  assert_no_message(opts: 'trailing blanks');
  aEqualV('webproxy': opts.spec: 'trailing blanks are not a third word');

  iEqual(PARSE_OK: parse_args('   check   -v   ': opts):
         'leading, interior and trailing blanks');
  aEqualV('check': opts.operation: 'operation');
  aEqualV('': opts.spec: 'no specifier appeared out of the blanks');
  nEqual(true: opts.verbose: 'option still seen');

end-proc;

//==============================================================================
// Specifier forms are stored verbatim
//
// group:, all, port: and job: are resolved by SCEXEC against real state, not
// by the parser. Its whole job is to hand the word over unaltered: lowercase
// it, strip a prefix or validate a port here and the resolution downstream is
// working from something the user did not type.
//==============================================================================

dcl-proc test_specifier_forms export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check group:web': opts): 'parse group:');
  aEqualV('group:web': opts.spec: 'group specifier kept whole');

  iEqual(PARSE_OK: parse_args('check all': opts): 'parse all');
  aEqualV('all': opts.spec: 'all is a specifier, not a flag');
  nEqual(false: opts.all: 'the word all does not set the -a flag');

  iEqual(PARSE_OK: parse_args('check port:8080': opts): 'parse port:');
  aEqualV('port:8080': opts.spec: 'ad hoc port specifier kept whole');

  iEqual(PARSE_OK: parse_args('jobinfo job:WEBPROXY': opts): 'parse job:');
  aEqualV('job:WEBPROXY': opts.spec: 'job specifier kept whole, case intact');

end-proc;

//==============================================================================
// An unrecognised option is REFUSED - a known, deliberate difference
//
// Measured on sc 1.7.1:
//
//   sc check --badflag   exit 0, and on stderr:
//     WARNING: Argument '--badflag' unrecognized and ignored
//   ...after which the check runs normally.
//
// RMSC refuses it instead. Whether to adopt upstream's warn-and-carry-on has
// NOT been decided, so this test pins what RMSC does today rather than what
// upstream does - deliberately, so that the difference is held by something
// that runs rather than by a paragraph in docs/parity.md.
//
// It is also the only case that would exercise the middle row of the new
// contract, status 0 WITH a message. When the decision is taken, this test
// becomes:
//
//   iEqual(PARSE_OK: sts: ...);             // upstream exits 0
//   assert_message_set(opts: ...);          // carrying the WARNING text
//   aEqualV('check': opts.operation: ...);  // and the operation still runs
//
// Until then a red test here means the behaviour changed without this suite
// being updated, which is exactly the signal wanted.
//==============================================================================

dcl-proc test_unknown_option_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: parse_args('check --badflag': opts):
         'RMSC refuses an unrecognised option; upstream warns and exits 0');
  assert_message_set(opts: '--badflag');

  // A short-form unknown option is refused the same way.
  iEqual(PARSE_USAGE: parse_args('check -Z': opts): 'unknown short option');
  assert_message_set(opts: '-Z');

end-proc;

//==============================================================================
// --version is REFUSED - the second known, deliberate difference
//
// Measured: `sc --version` exits 0 and prints a version to stdout. RMSC has
// no such option and refuses it. Same reasoning as above: the decision to add
// one has not been taken, so RMSC's behaviour is what is pinned here, and
// adding --version will show up as a failure rather than as a silent change.
//==============================================================================

dcl-proc test_version_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: SCMAIN_parse('--version': opts):
         'RMSC has no --version; upstream prints one and exits 0');
  assert_message_set(opts: '--version');

end-proc;

//==============================================================================
// `reload` is refused, and says why
//
// Cluster-only upstream, and cluster mode is out of scope. Refusing it with a
// message is the point: the alternative is accepting the word and appearing
// to have done something.
//==============================================================================

dcl-proc test_reload_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_USAGE: SCMAIN_parse('reload webproxy': opts): 'reload refused');
  assert_message_set(opts: 'reload');

end-proc;

//==============================================================================
// Every option at once, none of them clobbering another
//
// Each option is tested alone above, which proves each one can be set and not
// that they can coexist. A parser that writes past the end of a field, or
// reuses one subfield for two options, passes every single-option test.
//==============================================================================

dcl-proc test_all_options_together export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  sts  like(INTEGER_t);

  sts = SCMAIN_parse('check webproxy -v -q --splf --colors --ignore-globals ' +
                     '--sampletime=5 --ignore-groups=web,db': opts);

  iEqual(PARSE_OK: sts: 'every option together parses');
  assert_no_message(opts: 'all options');

  aEqualV('check': opts.operation: 'operation');
  aEqualV('webproxy': opts.spec: 'specifier');
  nEqual(true:  opts.verbose:        'verbose');
  nEqual(true:  opts.quiet:          'quiet');
  nEqual(true:  opts.splf:           'splf');
  nEqual(true:  opts.colours:        'colours');
  nEqual(true:  opts.ignore_globals: 'ignore_globals');
  nEqual(false: opts.all:            'all was not asked for');
  aEqualV('5': opts.sampletime: 'sampletime');
  aEqualV('web,db': opts.ignore_groups: 'ignore_groups');

end-proc;

//==============================================================================
// A LIST-VALUED OPTION IS REFUSED WHEN IT WILL NOT FIT, NOT TRUNCATED
//
// --ignore-groups= and --sampletime= both arrive as free text and are both
// held in a 512-character field, while the command line they arrive on is
// 1024. Measured on this build, with the probe that produced these numbers
// removed again:
//
//   SCMAIN_ARGS_t          1024      opts.err              1024
//   opts.ignore_groups      512      opts.spec              256
//   opts.sampletime         512      SCDEF_NAME_t           512
//
// So the value after `--ignore-groups=` can be longer than the field that
// holds it. The longest one that fits on the command line is 1003 - 1024 less
// the 16 characters of `--ignore-groups=`, less the shortest operation word
// and the blank after it (`list`, `stop`, `info`; with `check` it is 1002).
// The brief's figure of 1007 is not reachable: it leaves no room for an
// operation, and a command line with no operation is refused before any
// option is looked at.
//
// Every other field of this class was fixed by sizing the holder to its
// source. That cannot be done here, because the source is a list of n names
// and there is no n. The rule is therefore a GUARD: a value that does not fit
// is REFUSED - status 255, a message naming the option, and nothing run - in
// preference to being silently cut.
//
// WHY TRUNCATION IS NOT COSMETIC. --ignore-groups names the groups to EXCLUDE
// from output. Cutting the tail off the list means the groups named in the
// tail are NOT excluded, so services the caller asked to hide APPEAR in
// check, list and groups output. The failure adds rows rather than removing
// them, which is why a count is no way to test it - see
// test_long_ignore_list_still_excludes in SCCOLL.TEST, which names the
// services instead.
//
// DIVERGENCE FROM UPSTREAM, DELIBERATE. sc is Java and has no such limit; a
// 4000-character list works there. This is the same sanctioned divergence as
// the wait-time and scalar-length rules already in docs/parity.md: RMSC
// refuses what it cannot represent rather than quietly doing something other
// than what was asked. A failure here is a decision to revisit, not
// necessarily a defect - but a PASS at 513 that returns 0 is the defect.
//
// WHAT EACH CASE RULES OUT. The pair at 512/513 is the whole of it: 512 is
// the widest value that fits and must be ACCEPTED WHOLE, 513 is the narrowest
// that does not and must be REFUSED. An implementation that truncates and one
// that guards agree about every value below 512 and disagree about 513, so a
// suite that tested only 600, or only short values, would not be able to tell
// them apart. 511 and 512 are here so that a guard written one off - refusing
// at 512, or comparing against the arriving argument rather than the value -
// shows up as a red control rather than as a green over-strict parser.
//==============================================================================

///
// A refusal that does not name the option leaves the user to find which of
// their arguments was too long by bisection.
///
dcl-proc assert_message_names;
  dcl-pi *n;
    opts likeds(SCMAIN_OPTS_t) const;
    want varchar(64) const;
    ctx  varchar(64) const;
  end-pi;

  assert((%scan(%trimr(want): opts.err) > 0):
         %trim(ctx) + ': expected opts.err to name ' + %trim(want) +
         ', but it was "' + %trim(opts.err) + '"');

end-proc;

///
// mk_value - a comma-separated group list of an EXACT length, ending in a
// group name the caller chooses.
//
// The length is the whole point of these tests, so it is computed rather than
// counted by hand: `len` characters, elements of seven 'g's separated by
// commas, and the caller's tail as the last element. Nothing in the filler
// is a real group name in any fixture, which is what lets a test tell "the
// tail was kept" from "something in this list matched".
///
dcl-proc mk_value;
  dcl-pi *n varchar(1024);
    len  like(INTEGER_t) const;
    tail varchar(64) const;
  end-pi;

  dcl-s fill char(1024) inz(*all'g');
  dcl-s buf  varchar(1024);
  dcl-s want like(INTEGER_t);
  dcl-s i    like(INTEGER_t);

  want = len - %len(%trimr(tail)) - 1;
  assert((want >= 1): 'mk_value: length ' + %char(len) +
         ' leaves no room for the tail ' + %trim(tail));

  buf = %subst(fill: 1: want);

  for i = 8 by 8 to want - 1;
    %subst(buf: i: 1) = ',';
  endfor;

  return buf + ',' + %trimr(tail);

end-proc;

///
// mk_digits - a value of an exact length that is nothing but digits.
//
// --sampletime= takes a number, so a filler of 'g's would risk a refusal for
// a reason that has nothing to do with length, and a green test that proves
// only that the parser dislikes letters.
///
dcl-proc mk_digits;
  dcl-pi *n varchar(1024);
    len like(INTEGER_t) const;
  end-pi;

  dcl-s fill char(1024) inz(*all'5');

  return %subst(fill: 1: len);

end-proc;

//==============================================================================
// 512 characters of --ignore-groups is accepted, and kept WHOLE
//
// The control half of the separating pair, and the one that a fix could get
// wrong in the quiet direction: a guard that refuses at 512 rather than at
// 513 turns a working command line into a usage error, and a guard that
// accepts 512 but stores 500 of it is the defect this work is about wearing a
// different number.
//
// The last element is asserted by name as well as by length. A holder that
// keeps the first 512 characters of a 512-character value and one that keeps
// all of it are the same thing here; a holder that keeps 512 characters of
// SOMETHING ELSE - the argument including `--ignore-groups=`, say - has the
// right length and the wrong tail.
//==============================================================================

dcl-proc test_ignore_groups_at_512_accepted export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_value(512: 'lastgrp');
  iEqual(512: %len(val): 'the fixture value is exactly 512 characters');

  args = 'check --ignore-groups=' + val;
  iEqual(PARSE_OK: parse_args(args: opts): '512 characters is accepted');
  assert_no_message(opts: 'a 512-character list');

  iEqual(512: %len(opts.ignore_groups): 'stored whole, not clipped');
  aEqualV(val: opts.ignore_groups: 'ignore_groups');
  aEqualV('lastgrp':
          %subst(opts.ignore_groups: %len(opts.ignore_groups) - 6):
          'the last group in the list');

end-proc;

//==============================================================================
// 511 characters is accepted too - the guard is not one off
//==============================================================================

dcl-proc test_ignore_groups_at_511_accepted export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_value(511: 'lastgrp');
  iEqual(511: %len(val): 'the fixture value is exactly 511 characters');

  args = 'check --ignore-groups=' + val;
  iEqual(PARSE_OK: parse_args(args: opts): '511 characters is accepted');
  assert_no_message(opts: 'a 511-character list');
  iEqual(511: %len(opts.ignore_groups): 'stored whole');

end-proc;

//==============================================================================
// 513 characters of --ignore-groups is REFUSED
//
// The separating case. One character over the field, and the only value in
// this suite about which a truncating parser and a guarding one disagree by a
// single character.
//==============================================================================

dcl-proc test_ignore_groups_at_513_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_value(513: 'lastgrp');
  iEqual(513: %len(val): 'the fixture value is exactly 513 characters');

  args = 'check --ignore-groups=' + val;
  iEqual(PARSE_USAGE: parse_args(args: opts):
         'one character past the field is a usage error, not a silent cut');
  assert_message_set(opts: 'a 513-character list');
  assert_message_names(opts: '--ignore-groups': '513-character list');

end-proc;

//==============================================================================
// 600 characters of --ignore-groups is REFUSED
//
// Well past the field rather than one past it. Both cases matter: a guard
// written as a comparison against the wrong quantity can refuse the far value
// and accept the near one.
//==============================================================================

dcl-proc test_ignore_groups_at_600_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_value(600: 'lastgrp');
  iEqual(600: %len(val): 'the fixture value is exactly 600 characters');

  args = 'check --ignore-groups=' + val;
  iEqual(PARSE_USAGE: parse_args(args: opts): '600 characters is refused');
  assert_message_set(opts: 'a 600-character list');
  assert_message_names(opts: '--ignore-groups': '600-character list');

end-proc;

//==============================================================================
// The short values still work
//
// The controls, green today and green after. `system` is the default value
// and the one nearly every invocation uses; `a,b,c` is the multi-group list
// that the guard has to keep letting through.
//
// Both are covered elsewhere in this suite as part of a test about something
// else. They are gathered here as well because they are the cases a length
// guard is most likely to break, and a control that lives in another test's
// assertions is a control nobody looks at when this one goes red.
//
// The EMPTY value is a control too, and it is NOT in here - it has its own
// test below because it was red when this block was written, for a reason that
// had nothing to do with length, and a control that is already red controls
// nothing. That defect has since been fixed and both are green.
//==============================================================================

dcl-proc test_ignore_groups_short_values_unaffected export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check --ignore-groups=system': opts):
         'the ordinary case, and the default value given explicitly');
  assert_no_message(opts: '--ignore-groups=system');
  aEqualV('system': opts.ignore_groups: 'system');

  iEqual(PARSE_OK: parse_args('check --ignore-groups=a,b,c': opts):
         'a short list');
  assert_no_message(opts: '--ignore-groups=a,b,c');
  aEqualV('a,b,c': opts.ignore_groups: 'kept whole');

end-proc;

//==============================================================================
// AN EMPTY --ignore-groups= VALUE CLEARS THE DEFAULT EXCLUSION
//
// RED WHEN WRITTEN, AND NOT BECAUSE OF THE LENGTH GUARD. This was a second
// defect, found while writing the controls for the first, and it was stated
// here rather than left out because a length guard written as "the value must
// be between 1 and 512 characters" would have cemented it - and would have
// passed every other case in this suite while doing so. It is green now.
//
// MEASURED on this box, sc 1.7.1 against RMSC as it stands:
//
//   sc  list --ignore-groups=     36 rows, exit 0   - same as `sc list -a`
//   sc  list                       4 rows           - the `system` default
//   scr list --ignore-groups=     'sc: Unknown option --ignore-groups='
//
// So upstream reads the empty value as "exclude nothing" - identical to -a -
// and RMSC does not recognise the argument at all. The reading is the one
// test_ignore_groups_replaces_default already pins for the non-empty case:
// the supplied list REPLACES the default, and an empty supplied list replaces
// it with nothing. It is also the form a script gets for free when it builds
// the argument from a variable that happens to be empty.
//
// The assertions are upstream's behaviour, and when they were written they
// were not yet RMSC's - this was the one test in this block that did not state
// what RMSC did. RMSC now accepts the empty value and it passes.
//==============================================================================

dcl-proc test_ignore_groups_empty_value_clears_default export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('check --ignore-groups=': opts):
         'an empty value is meaningful and must parse');
  assert_no_message(opts: '--ignore-groups= (empty)');
  aEqualV('': opts.ignore_groups: 'an empty value clears the default');

  // And it is the value, not the option, that is empty: the operation and
  // everything after the option still have to survive it.
  iEqual(PARSE_OK: parse_args('list --ignore-groups= -v': opts):
         'an empty value in the middle of a command line');
  aEqualV('list': opts.operation: 'operation');
  nEqual(true: opts.verbose: 'the option after it is still seen');

end-proc;

//==============================================================================
// --sampletime= has the identical shape, and the identical guard
//
// Two lines away in the parser and the same 512-character holder. The filler
// is digits rather than letters so that an accepted case cannot be confused
// with a parser that refuses non-numeric text: what is under test is the
// length, and a 512-digit sampletime is meaningless as a duration but is
// exactly as long as the field that holds it.
//
// If a future change validates the number as well, THIS TEST WILL GO RED AT
// THE 512 CASE and must be changed to a value that is both long and valid -
// not relaxed to a shorter one, which would stop separating anything.
//==============================================================================

dcl-proc test_sampletime_at_512_accepted export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_digits(512);
  iEqual(512: %len(val): 'the fixture value is exactly 512 characters');

  args = 'perfinfo webproxy --sampletime=' + val;
  iEqual(PARSE_OK: parse_args(args: opts): '512 characters is accepted');
  assert_no_message(opts: 'a 512-character sampletime');
  iEqual(512: %len(opts.sampletime): 'stored whole, not clipped');
  aEqualV(val: opts.sampletime: 'sampletime');

end-proc;

dcl-proc test_sampletime_at_513_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_digits(513);
  iEqual(513: %len(val): 'the fixture value is exactly 513 characters');

  args = 'perfinfo webproxy --sampletime=' + val;
  iEqual(PARSE_USAGE: parse_args(args: opts):
         'one character past the field is a usage error');
  assert_message_set(opts: 'a 513-character sampletime');
  assert_message_names(opts: '--sampletime': '513-character sampletime');

end-proc;

dcl-proc test_sampletime_at_600_refused export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);
  dcl-s  val  varchar(1024);
  dcl-s  args like(SCMAIN_ARGS_t);

  val = mk_digits(600);
  iEqual(600: %len(val): 'the fixture value is exactly 600 characters');

  args = 'perfinfo webproxy --sampletime=' + val;
  iEqual(PARSE_USAGE: parse_args(args: opts): '600 characters is refused');
  assert_message_set(opts: 'a 600-character sampletime');
  assert_message_names(opts: '--sampletime': '600-character sampletime');

end-proc;

//==============================================================================
// The ordinary sampletime values still parse
//==============================================================================

dcl-proc test_sampletime_short_values_unaffected export;

  dcl-ds opts likeds(SCMAIN_OPTS_t) inz(*likeds);

  iEqual(PARSE_OK: parse_args('perfinfo webproxy --sampletime=1': opts):
         'the default value given explicitly');
  aEqualV('1': opts.sampletime: 'sampletime 1');

  iEqual(PARSE_OK: parse_args('perfinfo webproxy --sampletime=2.5': opts):
         'a fractional sample time');
  aEqualV('2.5': opts.sampletime: 'sampletime 2.5');

end-proc;
