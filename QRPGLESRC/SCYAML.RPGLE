**free

//==============================================================================
// SCYAML     - YAML reader
//
// Reads the shallow YAML subset that Service Commander definitions use. See
// SCYAML_D.rpgleinc for what is and is not supported, and why.
//
// The file is opened with IFS_OPEN_TYPE_READ, which sets o_ccsid to the job
// CCSID, so the C runtime converts from the file's tagged CCSID on read. The
// definitions are UTF-8 on disk; the lines arrive here in the job CCSID and no
// further conversion is needed.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: YAML reader');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

///
// Include copybooks
///

/include 'SCYAML_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// Internal prototypes
///

dcl-pr add_key like(INTEGER_t);
  doc  likeds(SCYAML_DOC_t);
  name like(SCYAML_KEY_t) const;
end-pr;

dcl-pr add_item like(BOOLEAN_t);
  doc       likeds(SCYAML_DOC_t);
  key_index like(INTEGER_t) const;
  value     like(SCYAML_ITEM_t) const;
end-pr;

dcl-pr find_key like(INTEGER_t);
  doc likeds(SCYAML_DOC_t) const;
  key like(SCYAML_KEY_t) const;
end-pr;

dcl-pr strip_eol like(STRING_t);
  line like(STRING_t) const;
end-pr;

dcl-pr strip_comment like(STRING_t);
  line like(STRING_t) const;
end-pr;

dcl-pr unquote like(SCYAML_VALUE_t);
  value like(SCYAML_VALUE_t) const;
end-pr;

dcl-pr is_null_literal like(BOOLEAN_t);
  value like(SCYAML_VALUE_t) const;
end-pr;

dcl-pr split_flow like(BOOLEAN_t);
  doc       likeds(SCYAML_DOC_t);
  key_index like(INTEGER_t) const;
  value     like(SCYAML_VALUE_t) const;
  line_no   like(INTEGER_t) const;
end-pr;

dcl-pr next_comma like(INTEGER_t);
  text like(SCYAML_VALUE_t) const;
end-pr;

//==============================================================================
// SCYAML_parse
//   Read and parse a definition file
//==============================================================================

dcl-proc SCYAML_parse export;
  dcl-pi *n like(BOOLEAN_t);
    stmf like(STMF_t) const;
    doc  likeds(SCYAML_DOC_t);
  end-pi;

  dcl-s handle    pointer;
  dcl-s line      like(STRING_t);
  dcl-s work      like(STRING_t);
  dcl-s key_name  like(SCYAML_KEY_t);
  dcl-s value     like(SCYAML_VALUE_t);
  dcl-s item      like(SCYAML_ITEM_t);
  dcl-s colon     like(INTEGER_t);
  dcl-s cur_key   like(INTEGER_t) inz(0);
  dcl-s line_no   like(INTEGER_t) inz(0);

  clear doc;

  handle = IFS_fopen(stmf: IFS_OPEN_TYPE_READ);
  if handle = *null;
    doc.err = 'Cannot open ' + %trim(stmf);
    return false;
  endif;

  dow IFS_fgets(handle: line);
    line_no += 1;

    // IFS_fgets replaces LF with a blank and trims the right. A CR from a
    // CRLF file survives that, so strip it before anything else - otherwise
    // it lands inside the last value on every line.
    work = strip_eol(line);

    // Blank line
    if %len(%trim(work)) = 0;
      iter;
    endif;

    work = %trim(work);

    // Whole-line comment.
    if %subst(work: 1: 1) = '#';
      iter;
    endif;

    // A trailing comment goes the same way. This used to be left in place, on
    // the reasoning that a '#' inside a start_cmd was likelier than a trailing
    // comment and truncating a command was the worse failure. The reasoning
    // was sound but the premise was not measured: sc 1.7.1 strips trailing
    // comments, and the whitespace rule protects the case it was worried about
    // anyway, since a '#' with no space before it stays put.
    work = strip_comment(work);

    // Sequence item: '-' followed by a blank, or '-' alone
    if %subst(work: 1: 1) = '-'
       and (%len(work) = 1 or %subst(work: 2: 1) = ' ');

      if cur_key = 0;
        doc.err = 'Sequence item with no key at line ' + %char(line_no);
        IFS_fclose(handle);
        return false;
      endif;

      if %len(work) = 1;
        item = '';
      else;
        item = %trim(unquote(%trim(%subst(work: 2))));
      endif;

      doc.keys(cur_key).is_seq = true;
      if not add_item(doc: cur_key: item);
        doc.err = 'More than ' + %char(SCYAML_MAX_ITEMS) +
                  ' sequence items at line ' + %char(line_no);
        IFS_fclose(handle);
        return false;
      endif;
      iter;
    endif;

    // Otherwise a 'key: value' line. Split on the first colon, and require
    // the text before it to be a bare key with no blanks - that way a colon
    // inside a value (a path, a URL, a host:port) is left alone.
    colon = %scan(':': work);
    if colon < 2 or %scan(' ': %subst(work: 1: colon - 1)) > 0;
      doc.err = 'Cannot parse line ' + %char(line_no) + ': ' +
                %subst(work: 1: %min(80: %len(work)));
      IFS_fclose(handle);
      return false;
    endif;

    key_name = %subst(work: 1: colon - 1);
    if colon = %len(work);
      value = '';
    else;
      value = %trim(%subst(work: colon + 1));
    endif;

    cur_key = add_key(doc: key_name);
    if cur_key = 0;
      doc.err = 'More than ' + %char(SCYAML_MAX_KEYS) +
                ' keys at line ' + %char(line_no);
      IFS_fclose(handle);
      return false;
    endif;

    // Inline flow sequence, including the empty '[]'
    if %len(value) >= 2
       and %subst(value: 1: 1) = '['
       and %subst(value: %len(value): 1) = ']';
      doc.keys(cur_key).is_seq = true;
      if not split_flow(doc: cur_key: value: line_no);
        // split_flow sets doc.err itself at every point it can fail. It used
        // to be the caller's job to supply the item-ceiling message, which
        // meant any future failure inside split_flow that forgot to set err
        // would have been reported as a ceiling overflow.

        IFS_fclose(handle);
        return false;
      endif;
      iter;
    endif;

    // An unquoted null is an absent value, not the text 'null'
    if is_null_literal(value);
      value = '';
    else;
      value = unquote(value);
    endif;

    doc.keys(cur_key).value = value;

  enddo;

  IFS_fclose(handle);
  return true;

end-proc;

//==============================================================================
// strip_eol
//   Remove trailing CR and blanks left by a CRLF file
//==============================================================================

dcl-proc strip_eol;
  dcl-pi *n like(STRING_t);
    line like(STRING_t) const;
  end-pi;

  dcl-s work like(STRING_t);
  dcl-c CR const(x'0D');

  work = %trimr(line);
  dow %len(work) > 0 and %subst(work: %len(work): 1) = CR;
    work = %trimr(%subst(work: 1: %len(work) - 1));
  enddo;

  return work;

end-proc;

//==============================================================================
// strip_comment
//   Remove a trailing comment
//
// A '#' opens a comment only when it starts the line or follows whitespace,
// and only outside quotes. All of that is measured against sc 1.7.1:
// 'Nospace#hash' keeps its hash, '"Dquote # hash"' keeps its hash, and a
// comment following a closing quote is still a comment - so this runs before
// unquote rather than after it.
//
// A quote only quotes when it OPENS a scalar. In "Bobs' service # comment"
// the apostrophe is an ordinary character and the comment is stripped, which
// a scan treating every quote as an opener gets wrong - it swallows the rest
// of the line and keeps the comment. Measured, along with the inch-mark
// spelling.
//
// Whitespace before the '#' goes with it, tabs included. %TRIM removes blanks
// only, so the tab is removed explicitly; a tab reaches here as EBCDIC x'05',
// the source line having been converted on the way in. That conversion is the
// assumption: x'05' is HT in every EBCDIC CCSID including the 1146 this
// compiles under, but a job running 65535 or 1208 gets no conversion and the
// tab arrives as x'09'. The failure would be silent - no error, the comment
// simply stops being stripped - which is why the assumption is written down
// rather than left in the constant.
//==============================================================================

dcl-proc strip_comment;
  dcl-pi *n like(STRING_t);
    line like(STRING_t) const;
  end-pi;

  dcl-s work     like(STRING_t);
  dcl-s i        like(INTEGER_t);
  dcl-s c        char(1);
  dcl-s nxt      char(1);
  dcl-s prev     char(1);
  dcl-s in_sq    like(BOOLEAN_t) inz(*off);
  dcl-s in_dq    like(BOOLEAN_t) inz(*off);
  // Whether the scan is somewhere a scalar could begin. A quote only quotes
  // when it OPENS a scalar; anywhere else it is an ordinary character, which
  // is why this flag exists rather than a bare "is this a quote" test.
  dcl-s at_start like(BOOLEAN_t) inz(*on);
  // Flow-collection nesting, so a comma is only a separator inside one.
  dcl-s depth    like(INTEGER_t) inz(0);
  dcl-c HT const(x'05');

  work = line;
  i = 1;

  dow i <= %len(work);
    c = %subst(work: i: 1);

    if in_sq;
      if c = '''';
        // YAML escapes a quote inside a single-quoted scalar by doubling it.
        // The pair is one character and does not end the scalar - reading the
        // first as a close and then declining to reopen truncated the value
        // and left the quotes on it.
        if i < %len(work) and %subst(work: i + 1: 1) = '''';
          i += 1;
        else;
          in_sq = *off;
        endif;
      endif;

    elseif in_dq;
      // A backslash escapes the next character, so a quote behind one does
      // not close the scalar.
      if c = '\';
        i += 1;
      elseif c = '"';
        in_dq = *off;
      endif;

    else;
      select;
        // Whitespace does not consume a scalar-start position: the value in
        // 'key: "quoted"' still begins at the quote.
        when c = ' ' or c = HT;

        when at_start and c = '''';
          in_sq    = *on;
          at_start = *off;

        when at_start and c = '"';
          in_dq    = *on;
          at_start = *off;

        when c = '#';
          prev = ' ';
          if i > 1;
            prev = %subst(work: i - 1: 1);
          endif;
          if i = 1 or prev = ' ' or prev = HT;
            work = %subst(work: 1: i - 1);
            // Trailing blanks and tabs go with the comment.
            dow %len(work) > 0
                and (%subst(work: %len(work): 1) = ' '
                     or %subst(work: %len(work): 1) = HT);
              work = %subst(work: 1: %len(work) - 1);
            enddo;

            // Nothing but whitespace stood before the '#'. A blank-indented
            // comment never reaches here, the whole-line test above having
            // caught it once %trim removed the blanks - so this is a
            // TAB-indented comment, which YAML does not allow and upstream
            // reports as a load error. Hand the line back untouched so it
            // reaches that error, rather than returning an empty string the
            // caller goes on to index into.
            if %len(work) = 0;
              return line;
            endif;

            return work;
          endif;
          at_start = *off;

        // A colon opens a value only when it ends a key - 'PORT:8080' is one
        // plain scalar, not a key and a value.
        when c = ':';
          nxt = ' ';
          if i < %len(work);
            nxt = %subst(work: i + 1: 1);
          endif;
          if i = %len(work) or nxt = ' ' or nxt = HT;
            at_start = *on;
          else;
            at_start = *off;
          endif;

        // Only a dash that is already at a scalar-start position introduces a
        // sequence item. The dashes in '--tag' are part of a plain scalar.
        when c = '-' and at_start;

        // Only where a scalar could begin. A bracket in the middle of a
        // plain scalar is an ordinary character, and treating it as opening a
        // collection re-enabled the comma rule one level down - which is the
        // same quote-blindness this procedure exists to remove.
        when at_start and (c = '[' or c = '{');
          depth += 1;
          at_start = *on;

        when c = ']' or c = '}';
          if depth > 0;
            depth -= 1;
          endif;
          at_start = *off;

        // A comma separates items inside a flow collection. Outside one it is
        // an ordinary character in a plain scalar, and treating it as a
        // separator everywhere was the only rule here that YAML does not have.
        when c = ',';
          at_start = (depth > 0);

        other;
          at_start = *off;
      endsl;
    endif;

    i += 1;
  enddo;

  return work;

end-proc;

//==============================================================================
// unquote
//   Strip one layer of matching surrounding quotes
//
// A doubled apostrophe inside a single-quoted scalar is YAML's escape for one
// apostrophe and is collapsed here. Backslash escapes inside a DOUBLE-quoted
// scalar are not decoded - '\"' stays two characters where upstream renders
// one. That gap predates this procedure handling escapes at all, and no
// definition on the box uses one; it is recorded in the plan rather than
// fixed here, because decoding one escape without the rest would be a worse
// half-measure than decoding none.
//==============================================================================

dcl-proc unquote;
  dcl-pi *n like(SCYAML_VALUE_t);
    value like(SCYAML_VALUE_t) const;
  end-pi;

  dcl-s work  like(SCYAML_VALUE_t);
  dcl-s first char(1);
  dcl-s last  char(1);
  dcl-s pos   like(INTEGER_t);

  work = %trim(value);
  if %len(work) < 2;
    return work;
  endif;

  first = %subst(work: 1: 1);
  last  = %subst(work: %len(work): 1);

  if first = '''' and last = '''';
    work = %subst(work: 2: %len(work) - 2);

    // YAML escapes an apostrophe inside a single-quoted scalar by doubling
    // it, so collapse each pair back to one. Without this the pair reached
    // the parenthesised description on the byte-exact path - 'don''t' where
    // upstream renders "don't".
    pos = %scan('''''': work);
    dow pos > 0;
      if pos + 1 < %len(work);
        work = %subst(work: 1: pos) + %subst(work: pos + 2);
      else;
        // The pair ends the scalar; there is nothing after it to keep, and
        // asking %SUBST for it would raise the same error being fixed
        // elsewhere in this change.
        work = %subst(work: 1: pos);
      endif;

      if pos + 1 > %len(work);
        leave;
      endif;
      pos = %scan('''''': work: pos + 1);
    enddo;

    return work;
  endif;

  if first = '"' and last = '"';
    return %subst(work: 2: %len(work) - 2);
  endif;

  return work;

end-proc;

//==============================================================================
// is_null_literal
//   An unquoted null or ~ means no value
//==============================================================================

dcl-proc is_null_literal;
  dcl-pi *n like(BOOLEAN_t);
    value like(SCYAML_VALUE_t) const;
  end-pi;

  dcl-s work like(SCYAML_VALUE_t);

  work = %trim(value);
  if work = '~';
    return true;
  endif;

  // Quoted 'null' is the four-character string, not an absent value
  if %len(work) = 4 and %xlate('NULL': 'null': work) = 'null';
    return true;
  endif;

  return false;

end-proc;

//==============================================================================
// next_comma
//   Position of the first comma that SEPARATES flow items, or 0
//
// A comma inside quotes belongs to the item rather than between items.
// Splitting on raw commas made "['a,,b']" look like a gap where YAML requires
// a node, so the empty-element check refused a file upstream loads happily -
// and a service vanishing from 'check' is the failure this project cares most
// about.
//
// A quote only quotes when it opens an item, as everywhere else in this
// parser: '[Bobs' service, x]' is two items, because that apostrophe is an
// ordinary character in a plain scalar.
//==============================================================================

dcl-proc next_comma;
  dcl-pi *n like(INTEGER_t);
    text like(SCYAML_VALUE_t) const;
  end-pi;

  dcl-s i        like(INTEGER_t);
  dcl-s c        char(1);
  dcl-s in_sq    like(BOOLEAN_t) inz(*off);
  dcl-s in_dq    like(BOOLEAN_t) inz(*off);
  dcl-s at_start like(BOOLEAN_t) inz(*on);
  dcl-c HT const(x'05');

  i = 1;
  dow i <= %len(text);
    c = %subst(text: i: 1);

    if in_sq;
      if c = '''';
        if i < %len(text) and %subst(text: i + 1: 1) = '''';
          i += 1;
        else;
          in_sq = *off;
        endif;
      endif;

    elseif in_dq;
      if c = '\';
        i += 1;
      elseif c = '"';
        in_dq = *off;
      endif;

    else;
      select;
        when c = ' ' or c = HT;

        when at_start and c = '''';
          in_sq    = *on;
          at_start = *off;

        when at_start and c = '"';
          in_dq    = *on;
          at_start = *off;

        when c = ',';
          return i;

        other;
          at_start = *off;
      endsl;
    endif;

    i += 1;
  enddo;

  return 0;

end-proc;

//==============================================================================
// split_flow
//   Split an inline [a, b, c] sequence into items
//==============================================================================

dcl-proc split_flow;
  dcl-pi *n like(BOOLEAN_t);
    doc       likeds(SCYAML_DOC_t);
    key_index like(INTEGER_t) const;
    value     like(SCYAML_VALUE_t) const;
    line_no   like(INTEGER_t) const;
  end-pi;

  dcl-s inner like(SCYAML_VALUE_t);
  dcl-s part  like(SCYAML_ITEM_t);
  dcl-s comma like(INTEGER_t);

  // Drop the enclosing brackets
  inner = %trim(%subst(value: 2: %len(value) - 2));

  // '[]' holds nothing. The key is still a sequence, just an empty one.
  if %len(inner) = 0;
    return true;
  endif;

  dow %len(inner) > 0;
    comma = next_comma(inner);
    if comma = 0;
      part = %trim(inner);
      inner = '';
    else;
      part = %trim(%subst(inner: 1: comma - 1));

      // '[a,]' is valid YAML and abended here: a comma in the last position
      // leaves nothing after it, and %SUBST rejects a start beyond the end.
      if comma < %len(inner);
        inner = %trim(%subst(inner: comma + 1));
      else;
        inner = '';
      endif;
    endif;

    // A gap between two commas is a position where YAML requires a node and
    // none is present, so upstream rejects the whole file: 'while parsing a
    // flow node'. A comma in the LAST position is different - it leaves
    // nothing after it, and that is tolerated. Measured against sc 1.7.1;
    // '[a,]' loads with one item where '[a,,b]' loads not at all.
    if %len(part) = 0;
      doc.err = 'Empty item in flow sequence at line ' + %char(line_no);
      return false;
    endif;

    if not add_item(doc: key_index: unquote(part));
      doc.err = 'More than ' + %char(SCYAML_MAX_ITEMS) +
                ' sequence items at line ' + %char(line_no);
      return false;
    endif;
  enddo;

  return true;

end-proc;

//==============================================================================
// add_key
//   Add a key, or return the existing one if it repeats (last value wins)
//==============================================================================

dcl-proc add_key;
  dcl-pi *n like(INTEGER_t);
    doc  likeds(SCYAML_DOC_t);
    name like(SCYAML_KEY_t) const;
  end-pi;

  dcl-s existing like(INTEGER_t);

  existing = find_key(doc: name);
  if existing > 0;
    // A repeated key replaces the earlier one, so reset it to scalar
    doc.keys(existing).value = '';
    doc.keys(existing).is_seq = false;
    return existing;
  endif;

  if doc.key_count >= SCYAML_MAX_KEYS;
    return 0;
  endif;

  doc.key_count += 1;
  doc.keys(doc.key_count).name = name;
  return doc.key_count;

end-proc;

//==============================================================================
// add_item
//   Append a sequence item
//==============================================================================

dcl-proc add_item;
  dcl-pi *n like(BOOLEAN_t);
    doc       likeds(SCYAML_DOC_t);
    key_index like(INTEGER_t) const;
    value     like(SCYAML_ITEM_t) const;
  end-pi;

  if doc.item_count >= SCYAML_MAX_ITEMS;
    return false;
  endif;

  doc.item_count += 1;
  doc.items(doc.item_count).key_index = key_index;
  doc.items(doc.item_count).value = value;
  return true;

end-proc;

//==============================================================================
// find_key
//   Position of a key, or zero
//==============================================================================

dcl-proc find_key;
  dcl-pi *n like(INTEGER_t);
    doc likeds(SCYAML_DOC_t) const;
    key like(SCYAML_KEY_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to doc.key_count;
    if doc.keys(i).name = key;
      return i;
    endif;
  endfor;

  return 0;

end-proc;

//==============================================================================
// SCYAML_error
//==============================================================================

dcl-proc SCYAML_error export;
  dcl-pi *n like(SCYAML_ERROR_t);
    doc likeds(SCYAML_DOC_t) const;
  end-pi;

  return doc.err;

end-proc;

//==============================================================================
// SCYAML_has
//==============================================================================

dcl-proc SCYAML_has export;
  dcl-pi *n like(BOOLEAN_t);
    doc likeds(SCYAML_DOC_t) const;
    key like(SCYAML_KEY_t) const;
  end-pi;

  return (find_key(doc: key) > 0);

end-proc;

//==============================================================================
// SCYAML_value
//==============================================================================

dcl-proc SCYAML_value export;
  dcl-pi *n like(SCYAML_VALUE_t);
    doc likeds(SCYAML_DOC_t) const;
    key like(SCYAML_KEY_t) const;
  end-pi;

  dcl-s index like(INTEGER_t);

  index = find_key(doc: key);
  if index = 0;
    return '';
  endif;

  return doc.keys(index).value;

end-proc;

//==============================================================================
// SCYAML_is_seq
//==============================================================================

dcl-proc SCYAML_is_seq export;
  dcl-pi *n like(BOOLEAN_t);
    doc likeds(SCYAML_DOC_t) const;
    key like(SCYAML_KEY_t) const;
  end-pi;

  dcl-s index like(INTEGER_t);

  index = find_key(doc: key);
  if index = 0;
    return false;
  endif;

  return doc.keys(index).is_seq;

end-proc;

//==============================================================================
// SCYAML_count
//==============================================================================

dcl-proc SCYAML_count export;
  dcl-pi *n like(INTEGER_t);
    doc likeds(SCYAML_DOC_t) const;
    key like(SCYAML_KEY_t) const;
  end-pi;

  dcl-s index like(INTEGER_t);
  dcl-s i     like(INTEGER_t);
  dcl-s total like(INTEGER_t) inz(0);

  index = find_key(doc: key);
  if index = 0;
    return 0;
  endif;

  for i = 1 to doc.item_count;
    if doc.items(i).key_index = index;
      total += 1;
    endif;
  endfor;

  return total;

end-proc;

//==============================================================================
// SCYAML_item
//==============================================================================

dcl-proc SCYAML_item export;
  dcl-pi *n like(SCYAML_ITEM_t);
    doc   likeds(SCYAML_DOC_t) const;
    key   like(SCYAML_KEY_t) const;
    index like(INTEGER_t) const;
  end-pi;

  dcl-s key_index like(INTEGER_t);
  dcl-s i         like(INTEGER_t);
  dcl-s seen      like(INTEGER_t) inz(0);

  key_index = find_key(doc: key);
  if key_index = 0 or index < 1;
    return '';
  endif;

  for i = 1 to doc.item_count;
    if doc.items(i).key_index = key_index;
      seen += 1;
      if seen = index;
        return doc.items(i).value;
      endif;
    endif;
  endfor;

  return '';

end-proc;

//==============================================================================
// SCYAML_key_count
//==============================================================================

dcl-proc SCYAML_key_count export;
  dcl-pi *n like(INTEGER_t);
    doc likeds(SCYAML_DOC_t) const;
  end-pi;

  return doc.key_count;

end-proc;

//==============================================================================
// SCYAML_key_name
//==============================================================================

dcl-proc SCYAML_key_name export;
  dcl-pi *n like(SCYAML_KEY_t);
    doc   likeds(SCYAML_DOC_t) const;
    index like(INTEGER_t) const;
  end-pi;

  if index < 1 or index > doc.key_count;
    return '';
  endif;

  return doc.keys(index).name;

end-proc;
