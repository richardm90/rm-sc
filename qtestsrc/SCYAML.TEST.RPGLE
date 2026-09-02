**free

//==============================================================================
// SCYAML.TEST - YAML reader test suite
//
// The suite writes its own fixtures rather than reading files from the deploy
// directory, so it does not depend on a path that differs per user. The
// fixtures are created with IFS_OPEN_TYPE_WRITE, which tags them CCSID 1208,
// so the round trip exercises the real UTF-8 conversion both ways.
//
// Every case here is a form that appears in a real service definition. The
// service names are invented; the shapes are not.
//
// Cases are labelled MEASURED where the expectation was read off sc 1.7.1 on
// the box, and DERIVED where it was reasoned from the rule but not observed.
// The distinction is not bookkeeping. It has already caught one wrong
// expectation: the empty element in a flow sequence, [a,,b], was DERIVED from
// the measured trailing-comma case as "an empty element is absent wherever it
// appears", asserted two items, and was wrong - upstream rejects the whole
// file. It was measured BECAUSE it was labelled as inference. Unlabelled it
// would have read as observation and driven the parser to load a definition
// upstream discards. Label new cases the same way, and promote a DERIVED one
// only on a measurement, never on agreement with the code.
//
// AND AUDIT THE PASSING ONES. The derived case that most needed measuring here
// was not one of the failing ones - it was test_hash_in_scalar_quoted_from_start,
// which had been green from the day it was written. A red test advertises
// itself; a green derived assertion never does, and it agrees with whatever
// the code happens to do, which is exactly how the three defects listed in
// CLAUDE.md survived behind assertions that could not fail. The question that
// finds these is not "what is failing" but "what has never been checked
// against upstream", and it has to be asked deliberately.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
// RMSCPGM brings in RMSC.SRVPGM for the SCYAML_* procedures under test.
// RMSCDEPS is needed separately for the rmtools IFS_* procedures the fixture
// helpers call: RMSC.BND exports only SCYAML_* symbols, so the rmtools code
// copied into RMSC.SRVPGM is deliberately not reachable from here.
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCYAML_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

//==============================================================================
// Test environment
//==============================================================================

dcl-s g_dir like(STMF_t);

// EBCDIC HT, invariant across the EBCDIC CCSIDs. The fixture helper declares
// its parameter ccsid(*utf8), so RPG converts at the call boundary and the
// byte on disk is a real x'09' tab - which is what the cases using this are
// about. Written as a constant because a literal tab in this source would be
// invisible to anyone reading it and liable to be reflowed by an editor.
dcl-c YAML_HT x'05';


dcl-pr remove_fixtures end-pr;

dcl-pr write_fixture like(STMF_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
end-pr;

dcl-pr parse_fixture like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  doc     likeds(SCYAML_DOC_t);
end-pr;

//==============================================================================
// Suite set-up
//==============================================================================

dcl-proc setUpSuite export;

  // Qualify the directory by current user. A fixed path under /tmp belongs to
  // whoever runs the suite first: the directory is created 755, so a second
  // user gets read and execute but not write, and every fixture write fails.
  g_dir = '/tmp/rmsc-scyaml-test-' + %trim(psds.current_user);

  // Harmless if it already exists from an earlier run
  IFS_crtdir(g_dir);

end-proc;

//==============================================================================
// Suite tear-down
//
// Remove the fixtures this suite wrote, so a run leaves nothing behind and a
// renamed fixture cannot linger and be mistaken for a current one.
//
// Only *.yaml is removed, and only from this suite's own per-user directory.
//
// NOTE when debugging a WRITE-side fault - a CCSID mismatch, a truncated
// value - the bytes on disk are the evidence you need, and the fixture
// content in this source is not a substitute for them. Comment out the call
// to remove_fixtures below and re-run to keep them.
//==============================================================================

dcl-proc tearDownSuite export;

  remove_fixtures();

end-proc;

dcl-proc remove_fixtures;

  dcl-s dir      pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);

  dir = IFS_opendir(g_dir);
  if dir = *null;
    return;
  endif;

  dow IFS_readdir(dir: filename);
    if %len(filename) > 5
       and %subst(filename: %len(filename) - 4) = '.yaml';
      IFS_remove_file(%trim(g_dir) + '/' + %trim(filename));
    endif;
  enddo;

  IFS_closedir(dir);

  // IFS_dltdir fails on a non-empty directory and returns nothing, so a stray
  // non-.yaml file here would leave the directory behind with nothing said.
  // Assert the postcondition rather than assume it.
  IFS_dltdir(g_dir);
  assert((not IFS_isa_directory(g_dir)):
         'Fixture directory ' + %trim(g_dir) + ' not removed');

end-proc;

//==============================================================================
// Helpers
//==============================================================================

dcl-proc write_fixture;
  dcl-pi *n like(STMF_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);

  path = %trim(g_dir) + '/' + %trim(name);

  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create fixture ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));

  // IFS_write_utf8, not IFS_write. IFS_OPEN_TYPE_WRITE tags the file CCSID
  // 1208 and opens it O_CCSID, which means "the bytes I hand you are already
  // in the file's CCSID". IFS_write does a raw write, so job-CCSID data would
  // be stored as EBCDIC under a UTF-8 tag and come back mangled. The _utf8
  // variant declares its parameter ccsid(*utf8), so RPG converts at the call
  // boundary and the bytes on disk really are UTF-8 - matching the real
  // definition files.
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  return path;

end-proc;

dcl-proc parse_fixture;
  dcl-pi *n like(BOOLEAN_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
    doc     likeds(SCYAML_DOC_t);
  end-pi;

  return SCYAML_parse(write_fixture(name: content): doc);

end-proc;


//==============================================================================
// The two required keys are read
//==============================================================================

dcl-proc test_required_keys export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('minimal.yaml':
    'start_cmd: /QOpenSys/pkgs/bin/webproxy' + LF +
    'check_alive: 8080' + LF: doc): 'parse');

  aEqual('/QOpenSys/pkgs/bin/webproxy': SCYAML_value(doc: 'start_cmd'): 'start_cmd');
  aEqual('8080': SCYAML_value(doc: 'check_alive'): 'check_alive');
  iEqual(2: SCYAML_key_count(doc): 'key count');

end-proc;

//==============================================================================
// A file with no trailing newline still yields its last key
//
// The shipped mapepire.yaml has no trailing newline, and appending to it
// without allowing for that glues the next key onto the last line.
//==============================================================================

dcl-proc test_no_trailing_newline export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('no-newline.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080': doc): 'parse');

  aEqual('8080': SCYAML_value(doc: 'check_alive'): 'last key without trailing LF');
  iEqual(2: SCYAML_key_count(doc): 'key count');

end-proc;

//==============================================================================
// Whole-line comments and blank lines are ignored
//==============================================================================

dcl-proc test_comments_and_blanks export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comments.yaml':
    '# Web Proxy Service' + LF +
    '# Generated by install.sh' + LF +
    '' + LF +
    'name: Web Proxy' + LF +
    '   # indented comment' + LF +
    'check_alive: 8080' + LF: doc): 'parse');

  iEqual(2: SCYAML_key_count(doc): 'comments and blanks skipped');
  aEqual('Web Proxy': SCYAML_value(doc: 'name'): 'name');

end-proc;

//==============================================================================
// MEASURED - a TAB-indented comment line is a load error, not a crash
//
// YAML forbids a tab as indentation. Upstream reports the file unloadable and
// carries on with the rest of the walk:
//
//   Invalid configuration for service 'x' ... while scanning for the next token
//   WARNING: Ignoring file due to load errors: ...
//
// RMSC abends (RNX0100) on it today, which takes down the whole walk rather
// than the one definition. What is pinned here is the classification: such a
// file must come back as a load ERROR - parse false, with error text - and
// must neither crash nor be silently accepted.
//
// The space-indented CONTROL is asserted first, and deliberately repeats what
// test_comments_and_blanks already covers. It is here for two reasons. An
// abend ends the procedure it happens in, so a control placed after the tab
// case would never run and its absence would say nothing. And it is the
// neighbouring case that must NOT change: a fix that rejected all indented
// comments would satisfy the tab assertion below while breaking every real
// definition file, and only the control catches that.
//==============================================================================

dcl-proc test_tab_indented_comment_line export;

  dcl-ds doc_ctl likeds(SCYAML_DOC_t);
  dcl-ds doc_tab likeds(SCYAML_DOC_t);

  // CONTROL, and first on purpose - spaces are legal indentation
  assert(parse_fixture('indent-space-comment.yaml':
    'name: Web Proxy' + LF +
    '   # space-indented comment' + LF +
    'check_alive: 8080' + LF: doc_ctl): 'space-indented comment parses');
  iEqual(2: SCYAML_key_count(doc_ctl): 'and is skipped, not counted');

  // The defect - a tab where those spaces were
  nEqual(false: parse_fixture('indent-tab-comment.yaml':
    'name: Web Proxy' + LF +
    YAML_HT + '# tab-indented comment' + LF +
    'check_alive: 8080' + LF: doc_tab): 'tab indentation does not load');
  assert((%len(SCYAML_error(doc_tab)) > 0): 'and says why');

end-proc;

//==============================================================================
// An unquoted null is an absent value, but the key is still present
//==============================================================================

dcl-proc test_null_literal export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('null.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'stop_cmd: null' + LF +
    'check_alive: 8080' + LF: doc): 'parse');

  nEqual(true: SCYAML_has(doc: 'stop_cmd'): 'stop_cmd present');
  aEqual('': SCYAML_value(doc: 'stop_cmd'): 'stop_cmd empty');

end-proc;

//==============================================================================
// A quoted null is the four-character string, not an absent value
//==============================================================================

dcl-proc test_quoted_null_is_text export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quoted-null.yaml':
    'stop_cmd: ''null''' + LF: doc): 'parse');

  aEqual('null': SCYAML_value(doc: 'stop_cmd'): 'quoted null kept as text');

end-proc;

//==============================================================================
// A comma-separated check_alive is one value, split later by SCDEF
//==============================================================================

dcl-proc test_multi_criteria export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('multi.yaml':
    'check_alive: webproxy,8080' + LF: doc): 'parse');

  aEqual('webproxy,8080': SCYAML_value(doc: 'check_alive'): 'kept whole');
  nEqual(false: SCYAML_is_seq(doc: 'check_alive'): 'not a sequence');

end-proc;

//==============================================================================
// Booleans appear both quoted and bare in real definitions
//==============================================================================

dcl-proc test_quoted_and_bare_bool export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('bools.yaml':
    'batch_mode: ''true''' + LF +
    'environment_is_inheriting_vars: true' + LF: doc): 'parse');

  aEqual('true': SCYAML_value(doc: 'batch_mode'): 'quoted true');
  aEqual('true': SCYAML_value(doc: 'environment_is_inheriting_vars'): 'bare true');

end-proc;

//==============================================================================
// An empty inline sequence is a sequence, not a scalar
//==============================================================================

dcl-proc test_empty_flow_sequence export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('empty-flow.yaml':
    'service_dependencies: []' + LF: doc): 'parse');

  nEqual(true: SCYAML_is_seq(doc: 'service_dependencies'): 'is a sequence');
  iEqual(0: SCYAML_count(doc: 'service_dependencies'): 'no items');

end-proc;

//==============================================================================
// A populated inline sequence
//==============================================================================

dcl-proc test_flow_sequence export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('flow.yaml':
    'groups: [web, autostart]' + LF: doc): 'parse');

  iEqual(2: SCYAML_count(doc: 'groups'): 'two items');
  aEqual('web': SCYAML_item(doc: 'groups': 1): 'item 1');
  aEqual('autostart': SCYAML_item(doc: 'groups': 2): 'item 2');

end-proc;

//==============================================================================
// MEASURED - a trailing comma in a flow sequence is valid YAML
//
//   groups: [rmscrevg,]
//
// loads upstream and the group is listed. RMSC abends (RNX0100) on it, so one
// definition written this way stops the whole walk. The empty element after
// the last comma is absent: one group, not two, and not one plus a blank.
//
// In a procedure of its own rather than beside the [a,,b] case below, because
// an abend ends the procedure it happens in and would take the other case
// with it - leaving one defect reported and the other invisible.
//==============================================================================

dcl-proc test_flow_sequence_trailing_comma export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('flow-trailing-comma.yaml':
    'groups: [rmscrevg,]' + LF: doc): 'parse');

  iEqual(1: SCYAML_count(doc: 'groups'): 'one item, not two');
  aEqual('rmscrevg': SCYAML_item(doc: 'groups': 1): 'the group itself');
  aEqual('': SCYAML_item(doc: 'groups': 2): 'nothing in a second slot');

end-proc;

//==============================================================================
// MEASURED - an empty element between two commas invalidates the whole file
//
//   groups: [rmscpg_alpha,,rmscpg_beta]
//
// is NOT a sequence with a gap in it. Upstream rejects the definition outright:
//
//   Invalid configuration for service 'x' from file [...]: while parsing a
//   flow node
//   WARNING: Ignoring file due to load errors: ...
//
// so the empty element is neither absent nor null - it is a syntax error, and
// the service disappears rather than loading with two groups.
//
// WHY THIS DIFFERS FROM THE TRAILING COMMA ABOVE, which loads with one item.
// The inconsistency is real and it is worth understanding before anyone tidies
// it away: a trailing comma has nothing after it, and YAML tolerates a flow
// sequence that simply ends there. A gap between two commas is a position
// where a node is REQUIRED and none is present, which is a parse error. The
// two look like the same thing written twice and they are not.
//
// THIS EXPECTATION WAS WRONG WHEN IT WAS FIRST WRITTEN. It was marked DERIVED
// and asserted two items, reasoning by one step from the trailing-comma case
// that an empty element is absent wherever it appears. The step was invalid,
// and it was measured afterwards precisely because it was labelled as
// inference rather than observation. Left unmarked it would have become a
// specification, and RMSC would have been built to load a file upstream
// discards. That is the argument for the MEASURED/DERIVED distinction in this
// suite, and it is why the labels are worth the noise they add.
//==============================================================================

dcl-proc test_flow_sequence_empty_element export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  nEqual(false: parse_fixture('flow-empty-element.yaml':
    'groups: [rmscpg_alpha,,rmscpg_beta]' + LF: doc): 'parse fails');
  assert((%len(SCYAML_error(doc)) > 0): 'error text set');

end-proc;

//==============================================================================
// THE FLOW SPLITTER MUST KNOW ABOUT QUOTES
//
// A comma inside a quoted flow item is an ordinary character and does not
// separate items. The three tests below pin that from both sides: two shapes
// where a quoted comma must NOT split, and one where an unquoted comma must
// still split.
//
// REGRESSION, and the reason this group exists. The empty-element rejection
// added for [a,,b] is applied by a splitter that cuts on raw commas without
// knowing where the quotes are. Given ['a,,b'] it sees a gap between two
// commas that YAML never sees, and REFUSES THE WHOLE FILE:
//
//   Empty item in flow sequence at line N
//
// Before this work that line loaded, with junk items. It now makes the service
// disappear from check altogether - which is the failure mode CLAUDE.md
// singles out, a service silently vanishing from a screen rather than an error
// being raised. It is worse than the defect the rejection was added to fix.
//
// Each shape is a procedure of its own rather than one procedure with a
// control first. The concern that ordering answers - a parse failure making
// later assertions meaningless - only arises WITHIN a procedure, and a failed
// parse here does not abend, so every procedure runs and reports its own
// verdict whatever the others do. Splitting them is what makes the report say
// which shape broke, rather than one procedure failing three times over.
//==============================================================================

//==============================================================================
// MEASURED - a quoted item containing commas is ONE item
//
//   groups: ['a,,b']   ->  loads, one group, value  a,,b
//
// The exact shape the rejection misfires on: the quotes make both commas
// ordinary characters, so there is no empty element and nothing to reject.
//
// The VALUE is asserted, not only the count. A splitter that returned one item
// of the wrong text - 'a' say, or the item with its quotes still on - would
// satisfy a count-only assertion and still be broken.
//==============================================================================

dcl-proc test_flow_item_quoted_double_comma export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('flow-quoted-double-comma.yaml':
    'groups: [''a,,b'']' + LF: doc): 'the file still loads');

  iEqual(1: SCYAML_count(doc: 'groups'): 'one item, not three and not none');
  aEqual('a,,b': SCYAML_item(doc: 'groups': 1): 'commas are part of the value');
  aEqual('': SCYAML_item(doc: 'groups': 2): 'nothing in a second slot');

end-proc;

//==============================================================================
// MEASURED - the plainer shape of the same rule
//
//   groups: ['a, b']   ->  loads, one group, value  a, b
//
// One comma rather than two, so it does not trip the empty-element rejection
// and fails for the simpler reason instead: a comma inside quotes should never
// separate items, and this splitter has never known that. Worth its own test
// because it is the shape someone actually writes, and because a fix aimed
// only at the doubled comma above would leave it broken.
//
// The space after the comma is part of the value. It is inside the quotes, so
// nothing may trim it.
//==============================================================================

dcl-proc test_flow_item_quoted_comma_space export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('flow-quoted-comma-space.yaml':
    'groups: [''a, b'']' + LF: doc): 'the file still loads');

  iEqual(1: SCYAML_count(doc: 'groups'): 'one item, not two');
  aEqual('a, b': SCYAML_item(doc: 'groups': 1):
         'comma and the space after it are both inside the value');

end-proc;

//==============================================================================
// CONTROL - an UNQUOTED comma must still split
//
//   groups: [a, 'b,c']   ->  loads, TWO items, 'a' and 'b,c'
//
// Green today, and it has to stay green. The two tests above are satisfied by
// a splitter that stops splitting on commas altogether, which would collapse
// every real flow sequence in every definition file into a single item. This
// is the boundary: quote awareness, not the abandonment of splitting.
//
// Both items are asserted. A splitter returning two items where the second is
// 'b' - having split inside the quotes and then dropped the tail - has the
// right count and the wrong contents.
//==============================================================================

dcl-proc test_flow_split_still_splits export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('flow-quoted-mixed.yaml':
    'groups: [a, ''b,c'']' + LF: doc): 'parse');

  iEqual(2: SCYAML_count(doc: 'groups'): 'two items');
  aEqual('a': SCYAML_item(doc: 'groups': 1): 'the unquoted one');
  aEqual('b,c': SCYAML_item(doc: 'groups': 2): 'the quoted one, comma intact');

end-proc;

//==============================================================================
// Block sequences appear both flush left and indented in real definitions
//==============================================================================

dcl-proc test_block_sequence_flush export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('seq-flush.yaml':
    'groups:' + LF +
    '- autostart' + LF +
    '- web' + LF: doc): 'parse');

  iEqual(2: SCYAML_count(doc: 'groups'): 'two items');
  aEqual('autostart': SCYAML_item(doc: 'groups': 1): 'item 1');

end-proc;

dcl-proc test_block_sequence_indented export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('seq-indent.yaml':
    'groups:' + LF +
    '  - web' + LF +
    '  - backend' + LF +
    'check_alive: 8080' + LF: doc): 'parse');

  iEqual(2: SCYAML_count(doc: 'groups'): 'two items');
  aEqual('backend': SCYAML_item(doc: 'groups': 2): 'item 2');
  aEqual('8080': SCYAML_value(doc: 'check_alive'): 'key after sequence ends it');

end-proc;

//==============================================================================
// Two sequences in one file stay separate
//==============================================================================

dcl-proc test_two_sequences export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('two-seq.yaml':
    'service_dependencies:' + LF +
    '- jobrunner' + LF +
    'groups:' + LF +
    '- web' + LF +
    '- autostart' + LF: doc): 'parse');

  iEqual(1: SCYAML_count(doc: 'service_dependencies'): 'one dependency');
  iEqual(2: SCYAML_count(doc: 'groups'): 'two groups');
  aEqual('jobrunner': SCYAML_item(doc: 'service_dependencies': 1): 'dependency');
  aEqual('web': SCYAML_item(doc: 'groups': 1): 'group 1');

end-proc;

//==============================================================================
// A CR left by a CRLF file must not survive into the value
//==============================================================================

dcl-proc test_crlf_line_endings export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('crlf.yaml':
    'check_alive: 8080' + CRLF +
    'batch_mode: true' + CRLF: doc): 'parse');

  aEqual('8080': SCYAML_value(doc: 'check_alive'): 'no trailing CR');
  aEqual('true': SCYAML_value(doc: 'batch_mode'): 'no trailing CR');

end-proc;

//==============================================================================
// A colon inside a value is not a key separator
//==============================================================================

dcl-proc test_colon_in_value export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('colon.yaml':
    'start_cmd: /usr/bin/proxy --listen host:8080 --upstream a:b' + LF: doc): 'parse');

  aEqual('/usr/bin/proxy --listen host:8080 --upstream a:b':
         SCYAML_value(doc: 'start_cmd'): 'colons preserved');

end-proc;

//==============================================================================
// Trailing comments
//
// The rule, and it is the plain YAML one: in an unquoted scalar a '#' begins a
// comment when it is preceded by whitespace or starts the line. Everything from
// the '#' to end of line is discarded and the whitespace before it is trimmed.
// A '#' with no whitespace in front of it is an ordinary character, and inside
// single or double quotes a '#' is always literal.
//
// This matters on the byte-exact path. The value of 'name' lands in the
// parenthesised description of a check row, which a consumer parses out; a
// criterion that keeps a comment glued to it is later converted to a number.
//
// The cases below marked MEASURED were read off sc 1.7.1 on the box, running
// both implementations over the same definitions. The ones marked DERIVED
// follow from the same rule but were not observed directly - if one of them
// ever fails, confirm against upstream before changing the parser to suit it.
//
// Whole-line comments, flush left and indented, are already covered by
// test_comments_and_blanks and are not repeated here.
//
// The previous test here, test_hash_in_value_preserved, asserted the opposite:
// that 'start_cmd: /usr/bin/proxy --tag #1' kept its '#1'. That was a guess
// about which failure was worse, not a measurement, and upstream does not
// agree with it. It is replaced by test_trailing_comment_in_command below.
//==============================================================================

//==============================================================================
// MEASURED - a trailing comment is stripped and the spaces before it go too
//==============================================================================

dcl-proc test_trailing_comment_stripped export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-trailing.yaml':
    'name: Trail value   # trailing comment' + LF: doc): 'parse');

  aEqual('Trail value': SCYAML_value(doc: 'name'): 'comment and gap removed');

end-proc;

//==============================================================================
// MEASURED - no space after the '#' does not make it content
//
// What decides the question is the whitespace BEFORE the '#'. What follows it
// is comment text either way.
//==============================================================================

dcl-proc test_trailing_comment_no_space_after_hash export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-nogap.yaml':
    'name: Nogap #comment' + LF: doc): 'parse');

  aEqual('Nogap': SCYAML_value(doc: 'name'): 'stripped despite no gap');

end-proc;

//==============================================================================
// MEASURED - a comment that reads like content is still a comment
//
// '#1 priority' looks like part of the description and is not. This is the
// case a reader is most tempted to special-case; upstream does not.
//==============================================================================

dcl-proc test_trailing_comment_looks_like_content export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-content.yaml':
    'name: Hash #1 priority' + LF: doc): 'parse');

  aEqual('Hash': SCYAML_value(doc: 'name'): 'stripped, not kept as text');

end-proc;

//==============================================================================
// MEASURED - a '#' with no whitespace in front of it is an ordinary character
//
// This is the boundary the fix must not cross. A parser that strips from the
// first '#' anywhere on the line eats this value.
//==============================================================================

dcl-proc test_hash_without_preceding_space_kept export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-nospace.yaml':
    'name: Nospace#hash' + LF: doc): 'parse');

  aEqual('Nospace#hash': SCYAML_value(doc: 'name'): 'literal hash kept');

end-proc;

//==============================================================================
// MEASURED - inside quotes a '#' is always literal, both quote characters
//
// The whitespace in front of the '#' is inside the quotes, so the rule that
// would otherwise start a comment does not apply.
//==============================================================================

dcl-proc test_hash_in_quotes_kept export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-quoted.yaml':
    'name: "Dquote # hash"' + LF +
    'sbmjob_opts: ''Squote # hash''' + LF: doc): 'parse');

  aEqual('Dquote # hash': SCYAML_value(doc: 'name'): 'double quoted');
  aEqual('Squote # hash': SCYAML_value(doc: 'sbmjob_opts'): 'single quoted');

end-proc;

//==============================================================================
// MEASURED - the rule is a property of scalars, not of the 'name' key
//
// A criterion is converted to a number downstream, so '55999 # port trailing
// comment' does not merely read badly, it stops being a port. The gate fixture
// rmscgate_comments.yaml carries the same shape against upstream.
//==============================================================================

dcl-proc test_trailing_comment_on_other_keys export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-keys.yaml':
    'check_alive: 55999 # port trailing comment' + LF +
    'start_cmd: /usr/bin/webproxy --port 55999   # start it' + LF: doc): 'parse');

  aEqual('55999': SCYAML_value(doc: 'check_alive'): 'criterion is still a port');
  aEqual('/usr/bin/webproxy --port 55999':
         SCYAML_value(doc: 'start_cmd'): 'command keeps its arguments');

end-proc;

//==============================================================================
// MEASURED - the command case the old test had backwards
//
// Replaces test_hash_in_value_preserved. Same fixture line, the expectation
// upstream actually produces.
//==============================================================================

dcl-proc test_trailing_comment_in_command export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('hash.yaml':
    'start_cmd: /usr/bin/proxy --tag #1' + LF: doc): 'parse');

  aEqual('/usr/bin/proxy --tag':
         SCYAML_value(doc: 'start_cmd'): 'trailing comment stripped');

end-proc;

//==============================================================================
// MEASURED - a TAB before the '#' starts a comment too
//
// The rule says whitespace, and a tab is whitespace. Written as DERIVED, and
// promoted when it was measured against sc 1.7.1 during a later review: the
// observation matched.
//
// YAML_HT is declared at the top of this suite; see the note there.
//==============================================================================

dcl-proc test_trailing_comment_after_tab export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('comment-tab.yaml':
    'name: Tabbed' + YAML_HT + '# tab before the hash' + LF: doc): 'parse');

  aEqual('Tabbed': SCYAML_value(doc: 'name'): 'tab counts as whitespace');

end-proc;

//==============================================================================
// Where a quote quotes, and where it is just a character
//
// A quote only quotes when it STARTS the scalar. A quote appearing part way
// through a plain scalar is an ordinary character with no special meaning, and
// it neither opens a quoted region nor suppresses comment stripping.
//
// This is the line the tests below pin, and it is easy to miss, because a
// parser that scans for quotes anywhere on the line gets the balanced cases
// right by accident. An apostrophe or an inch mark is a single quote character
// with no partner, so such a parser opens a region that never closes, swallows
// the rest of the line and silently keeps the trailing comment.
//
// 'Bobs'' service' is not a contrived shape. Possessives and inch marks turn up
// in the 'name' key, which is the value that lands in the parenthesised
// description on the byte-exact check path.
//==============================================================================

//==============================================================================
// MEASURED - an apostrophe mid-value is a character, and the comment still goes
//==============================================================================

dcl-proc test_apostrophe_in_plain_scalar export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-apostrophe.yaml':
    'name: Bobs'' service # comment after an apostrophe' + LF: doc): 'parse');

  aEqual('Bobs'' service': SCYAML_value(doc: 'name'): 'apostrophe kept, comment gone');

end-proc;

//==============================================================================
// MEASURED - an inch mark mid-value behaves the same way
//
// The double-quote counterpart of the apostrophe case. Both are a lone,
// unpaired quote character in a plain scalar.
//==============================================================================

dcl-proc test_inch_mark_in_plain_scalar export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-inch.yaml':
    'name: A 5" pipe # comment after an inch mark' + LF: doc): 'parse');

  aEqual('A 5" pipe': SCYAML_value(doc: 'name'): 'inch mark kept, comment gone');

end-proc;

//==============================================================================
// MEASURED - a BALANCED pair mid-value, the case that passes by luck
//
// A parser that scans for quotes anywhere gets this one right for the wrong
// reason: its two quotes pair up and the region it invents closes before the
// '#'. Kept as a regression guard, and as the contrast that shows why the two
// tests above fail while this one does not.
//==============================================================================

dcl-proc test_balanced_quotes_in_plain_scalar export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-balanced.yaml':
    'name: Its "fine" now # comment after both' + LF: doc): 'parse');

  aEqual('Its "fine" now': SCYAML_value(doc: 'name'): 'quotes kept, comment gone');

end-proc;

//==============================================================================
// MEASURED - a '#' inside mid-value quotes is still a comment
//
// This one reads oddly and is meant to. The scalar starts with 'Say', so it is
// plain; the quotes in it are therefore literal characters and quote nothing,
// so the space before the '#' starts a comment in the ordinary way and the
// closing quote is inside the discarded text. Following the rule where it
// looks wrong is the whole point of writing it down.
//
// Written as DERIVED, and singled out at the time as the least safe of the
// derived cases precisely because its expected value looks wrong at a glance -
// the same shape of assumption that did fail on the flow sequence. Measured
// against sc 1.7.1 during a later review: 'Say "hi' is what upstream returns.
// The looks-wrong reading was the right one here, but it was worth doubting.
//==============================================================================

dcl-proc test_hash_inside_mid_value_quotes export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-plain-hash.yaml':
    'name: Say "hi # there" now' + LF: doc): 'parse');

  aEqual('Say "hi': SCYAML_value(doc: 'name'): 'mid-value quotes do not protect');

end-proc;

//==============================================================================
// MEASURED - a '[' inside a plain scalar does not open a flow collection
//
//   name: a [b, "c # d"] e   ->  a [b, "c
//
// A flow collection is opened only by a '[' that STARTS the scalar. One in the
// middle of a plain scalar is an ordinary character, exactly as a quote is.
//
// The expected value cuts mid-quote and looks wrong, which is the same shape
// as test_hash_inside_mid_value_quotes above and the same reason: the scalar
// starts with 'a', so it is plain, so every quote and bracket in it is
// literal, so the space before the '#' begins a comment like any other. Having
// been caught once by an expectation that merely looked reasonable, it is
// worth saying that this one was measured and not reasoned.
//
// What RMSC does today is a chain of three steps, each plausible: it reads the
// '[' as opening a flow collection; that re-enables the rule that a comma
// starts a new scalar; the new scalar begins with a quote, so the quote is
// treated as real quoting and protects the '#'. The whole line survives where
// upstream cuts. The defect is only in the first step.
//==============================================================================

dcl-proc test_bracket_in_plain_scalar export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('plain-bracket.yaml':
    'name: a [b, "c # d"] e' + LF: doc): 'parse');

  aEqual('a [b, "c': SCYAML_value(doc: 'name'):
         'a mid-scalar bracket opens nothing, so the comment still goes');

end-proc;

//==============================================================================
// MEASURED - a scalar quoted FROM THE START still protects its '#'
//
// The counterpart that stops the fix over-correcting. Having learnt that a
// mid-value quote means nothing, a parser must not conclude that quotes mean
// nothing: here the value is genuinely single-quoted from its first character,
// so the '#' is inside quotes and survives, and the outer quotes come off.
//
// The leading '- ' is there deliberately. It must not be mistaken for a
// sequence item, being quoted content on a key line.
//
// Written as DERIVED and promoted on measurement against sc 1.7.1, both
// spellings:
//
//   name: '- not a list # x'   ->  - not a list # x
//   name: "- not a list # y"   ->  - not a list # y
//
// NOTE THE KEY. Upstream was measured on 'name', because that is the value the
// check row prints and so the one whose output can be read back; this test
// asserts on 'sbmjob_opts'. The two are not the same key and the quoted output
// above did not come from this fixture. That is deliberate and it is sound -
// the rule is a property of YAML scalars, not of any particular key, and
// test_trailing_comment_on_other_keys pins that generality separately - but
// nobody should read the lines above as a transcript of what this test runs.
//
// Only the single-quoted spelling is asserted here. The double-quoted one is
// already covered by test_hash_in_quotes_kept, so adding it would duplicate
// rather than extend.
//==============================================================================

dcl-proc test_hash_in_scalar_quoted_from_start export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-from-start.yaml':
    'sbmjob_opts: ''- not a list # x''' + LF: doc): 'parse');

  aEqual('- not a list # x':
         SCYAML_value(doc: 'sbmjob_opts'): 'real quoting still protects');
  nEqual(false: SCYAML_is_seq(doc: 'sbmjob_opts'): 'not a sequence');

end-proc;

//==============================================================================
// MEASURED - a comment AFTER a closing quote is still a comment
//
// The direct counterpart to test_hash_in_scalar_quoted_from_start. That test
// pins that a '#' INSIDE the quotes survives; this one pins that a '#' after
// the closing quote does not, and that the quotes still come off.
//
// The pair matters more than either half. Together they establish that comment
// detection happens with knowledge of where the quoted region ends - one pass,
// not two. A fix that unquoted first and then looked for a comment gets both
// of these wrong, and wrong in opposite directions: it strips the '#' that has
// to survive inside the quotes, and it keeps the one that has to go after
// them, along with the quotes it should by then have removed. Neither test
// alone would catch that; a suite with only one of them would report a pass on
// a parser that had merely swapped which case it broke.
//
// Both spellings were measured on the 'name' key. They are split across two
// fixtures here rather than sharing one, because two 'name' keys in a single
// file is the duplicate-key case - last wins, as test_duplicate_key_last_wins
// pins - and the first assertion would silently stop being made.
//==============================================================================

dcl-proc test_comment_after_closing_quote export;

  dcl-ds doc_dq likeds(SCYAML_DOC_t);
  dcl-ds doc_sq likeds(SCYAML_DOC_t);

  assert(parse_fixture('quote-then-comment-dq.yaml':
    'name: "Quoted dq" # comment after a quoted value' + LF: doc_dq): 'parse dq');

  aEqual('Quoted dq': SCYAML_value(doc_dq: 'name'):
         'double quotes off, comment gone');

  assert(parse_fixture('quote-then-comment-sq.yaml':
    'name: ''Quoted sq'' # comment after a quoted value' + LF: doc_sq):
         'parse sq');

  aEqual('Quoted sq': SCYAML_value(doc_sq: 'name'):
         'single quotes off, comment gone');

end-proc;

//==============================================================================
// MEASURED - '' inside a single-quoted scalar is an escaped quote
//
//   name: 'don''t # x'   ->  don't # x
//
// The doubled quote is YAML's only escape inside single quotes. It means one
// literal apostrophe and it does NOT end the scalar.
//
// RMSC returns  'don''t  today: truncated at the '#' AND with the quotes still
// attached, because it reads the first quote of the pair as closing the scalar
// and never reopens. One assertion on the whole value catches both halves.
//==============================================================================

dcl-proc test_escaped_quote_in_single_quoted_scalar export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('escape-quote.yaml':
    'name: ''don''''t # x''' + LF: doc): 'parse');

  aEqual('don''t # x': SCYAML_value(doc: 'name'):
         'escape resolved, quotes off, comment protected');

end-proc;

//==============================================================================
// MEASURED - the same escape in the shape it will actually be written in
//
//   name: 'Bobs'' service # notes'   ->  Bobs' service # notes
//
// A possessive in a friendly name, quoted so that the '#' in the note is kept.
// Same defect as the test above, and here as well because this is the form
// someone really writes, and because a fix that handled an escape mid-word
// would pass that one while still failing on an escape before a space.
//
// Note what this value would do to the check row if the truncation survived:
// 'name' is the parenthesised description on the byte-exact path.
//==============================================================================

dcl-proc test_escaped_quote_possessive_name export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('escape-possessive.yaml':
    'name: ''Bobs'''' service # notes''' + LF: doc): 'parse');

  aEqual('Bobs'' service # notes': SCYAML_value(doc: 'name'):
         'apostrophe kept, comment inside the quotes kept');

end-proc;

//==============================================================================
// Quoted and bare values, and relative paths
//==============================================================================

dcl-proc test_quoted_and_bare_values export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('quoting.yaml':
    'sbmjob_opts: ''JOBQ(QUSRNOMAX)''' + LF +
    'name: "Web Proxy"' + LF +
    'dir: .' + LF +
    'start_cmd: ../../bin/webproxy' + LF: doc): 'parse');

  aEqual('JOBQ(QUSRNOMAX)': SCYAML_value(doc: 'sbmjob_opts'): 'single quotes stripped');
  aEqual('Web Proxy': SCYAML_value(doc: 'name'): 'double quotes stripped');
  aEqual('.': SCYAML_value(doc: 'dir'): 'relative dir');
  aEqual('../../bin/webproxy': SCYAML_value(doc: 'start_cmd'): 'relative command');

end-proc;

//==============================================================================
// Trailing whitespace on a line is not part of the value
//==============================================================================

dcl-proc test_trailing_whitespace export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('trailing.yaml':
    'check_alive: 8080   ' + LF: doc): 'parse');

  aEqual('8080': SCYAML_value(doc: 'check_alive'): 'trailing blanks trimmed');

end-proc;

//==============================================================================
// An absent key is distinguishable from an empty one
//==============================================================================

dcl-proc test_absent_key export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('absent.yaml':
    'check_alive: 8080' + LF: doc): 'parse');

  nEqual(false: SCYAML_has(doc: 'log_dir'): 'absent key');
  aEqual('': SCYAML_value(doc: 'log_dir'): 'absent value is blank');
  iEqual(0: SCYAML_count(doc: 'log_dir'): 'absent count is zero');

end-proc;

//==============================================================================
// Keys can be enumerated, so a caller can report unrecognised ones
//==============================================================================

dcl-proc test_key_enumeration export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('enumerate.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'wibble: 42' + LF: doc): 'parse');

  iEqual(2: SCYAML_key_count(doc): 'two keys');
  aEqual('start_cmd': SCYAML_key_name(doc: 1): 'key 1');
  aEqual('wibble': SCYAML_key_name(doc: 2): 'key 2 - unrecognised, still reported');
  aEqual('': SCYAML_key_name(doc: 3): 'out of range');

end-proc;

//==============================================================================
// A repeated key takes its last value
//==============================================================================

dcl-proc test_duplicate_key_last_wins export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('duplicate.yaml':
    'check_alive: 8080' + LF +
    'check_alive: 9090' + LF: doc): 'parse');

  iEqual(1: SCYAML_key_count(doc): 'one key');
  aEqual('9090': SCYAML_value(doc: 'check_alive'): 'last wins');

end-proc;

//==============================================================================
// A sequence item before any key is an error, not silently dropped
//==============================================================================

dcl-proc test_orphan_sequence_item export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  nEqual(false: parse_fixture('orphan.yaml':
    '- autostart' + LF: doc): 'parse fails');
  assert((%len(SCYAML_error(doc)) > 0): 'error text set');

end-proc;

//==============================================================================
// A line that is neither comment, sequence nor key is an error
//==============================================================================

dcl-proc test_unparseable_line export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  nEqual(false: parse_fixture('bad.yaml':
    'check_alive: 8080' + LF +
    'this line has no colon' + LF: doc): 'parse fails');
  assert((%len(SCYAML_error(doc)) > 0): 'error text set');

end-proc;

//==============================================================================
// A missing file fails cleanly rather than returning an empty document
//==============================================================================

dcl-proc test_missing_file export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  nEqual(false: SCYAML_parse(%trim(g_dir) + '/does-not-exist.yaml': doc):
         'parse fails');
  assert((%len(SCYAML_error(doc)) > 0): 'error text set');

end-proc;

//==============================================================================
// A realistic definition, end to end
//==============================================================================

dcl-proc test_full_definition export;

  dcl-ds doc likeds(SCYAML_DOC_t);

  assert(parse_fixture('full.yaml':
    '# Web Proxy Service' + LF +
    '' + LF +
    'name: Web Proxy' + LF +
    'dir: /QOpenSys/opt/webproxy' + LF +
    'start_cmd: /QOpenSys/pkgs/bin/node src/server.js' + LF +
    'stop_cmd: null' + LF +
    'check_alive: WEBPROXY,8080' + LF +
    'startup_wait_time: 30' + LF +
    'batch_mode: ''true''' + LF +
    'sbmjob_opts: JOBQ(QUSRNOMAX)' + LF +
    'environment_vars:' + LF +
    '- PATH=/QOpenSys/pkgs/bin:/usr/bin' + LF +
    'service_dependencies: []' + LF +
    'groups:' + LF +
    '  - web' + LF +
    '  - autostart' + LF: doc): 'parse');

  aEqual('Web Proxy': SCYAML_value(doc: 'name'): 'name');
  aEqual('/QOpenSys/pkgs/bin/node src/server.js':
         SCYAML_value(doc: 'start_cmd'): 'start_cmd');
  aEqual('': SCYAML_value(doc: 'stop_cmd'): 'stop_cmd null');
  aEqual('WEBPROXY,8080': SCYAML_value(doc: 'check_alive'): 'check_alive');
  aEqual('30': SCYAML_value(doc: 'startup_wait_time'): 'startup_wait_time');
  aEqual('true': SCYAML_value(doc: 'batch_mode'): 'batch_mode');
  aEqual('JOBQ(QUSRNOMAX)': SCYAML_value(doc: 'sbmjob_opts'): 'sbmjob_opts');
  iEqual(1: SCYAML_count(doc: 'environment_vars'): 'one env var');
  aEqual('PATH=/QOpenSys/pkgs/bin:/usr/bin':
         SCYAML_item(doc: 'environment_vars': 1): 'env var with colons');
  iEqual(0: SCYAML_count(doc: 'service_dependencies'): 'no dependencies');
  iEqual(2: SCYAML_count(doc: 'groups'): 'two groups');
  iEqual(11: SCYAML_key_count(doc): 'all keys read');

end-proc;
