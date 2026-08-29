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

    // Whole-line comment. Trailing comments are deliberately not stripped:
    // a '#' inside a start_cmd is far more likely than a trailing comment,
    // and silently truncating a command string is the worse failure.
    if %subst(work: 1: 1) = '#';
      iter;
    endif;

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
      if not split_flow(doc: cur_key: value);
        doc.err = 'More than ' + %char(SCYAML_MAX_ITEMS) +
                  ' sequence items at line ' + %char(line_no);
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
// unquote
//   Strip one layer of matching surrounding quotes
//==============================================================================

dcl-proc unquote;
  dcl-pi *n like(SCYAML_VALUE_t);
    value like(SCYAML_VALUE_t) const;
  end-pi;

  dcl-s work  like(SCYAML_VALUE_t);
  dcl-s first char(1);
  dcl-s last  char(1);

  work = %trim(value);
  if %len(work) < 2;
    return work;
  endif;

  first = %subst(work: 1: 1);
  last  = %subst(work: %len(work): 1);

  if (first = '''' and last = '''') or (first = '"' and last = '"');
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
// split_flow
//   Split an inline [a, b, c] sequence into items
//==============================================================================

dcl-proc split_flow;
  dcl-pi *n like(BOOLEAN_t);
    doc       likeds(SCYAML_DOC_t);
    key_index like(INTEGER_t) const;
    value     like(SCYAML_VALUE_t) const;
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
    comma = %scan(',': inner);
    if comma = 0;
      part = %trim(inner);
      inner = '';
    else;
      part = %trim(%subst(inner: 1: comma - 1));
      inner = %trim(%subst(inner: comma + 1));
    endif;

    if not add_item(doc: key_index: unquote(part));
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
