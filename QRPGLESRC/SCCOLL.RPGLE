**free

//==============================================================================
// SCCOLL     - Service definition collection
//
// Discovery, group listing and dependency resolution.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service definition collection');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCDIRS_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMLIST_D.rpgleinc'
/include 'include/RMPATH_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// Internal prototypes
///

dcl-pr is_yaml like(BOOLEAN_t);
  filename like(IFS_DIR_FILENAME_t) const;
end-pr;

dcl-pr record_bad;
  coll likeds(SCCOLL_t);
  def  likeds(SCDEF_t) const;
end-pr;

dcl-pr find_rrn like(INTEGER_t);
  coll likeds(SCCOLL_t);
  name like(SCDEF_NAME_t) const;
end-pr;

dcl-pr visit like(BOOLEAN_t);
  coll  likeds(SCCOLL_t);
  name  like(SCDEF_NAME_t) const;
  order likeds(SCCOLL_ORDER_t);
  path  likeds(SCCOLL_ORDER_t);
end-pr;

dcl-pr in_order like(BOOLEAN_t);
  order likeds(SCCOLL_ORDER_t) const;
  name  like(SCDEF_NAME_t) const;
end-pr;


//==============================================================================
// SCCOLL_init
//   Clear the collection and create its backing list
//==============================================================================

dcl-proc SCCOLL_init export;
  dcl-pi *n;
    coll likeds(SCCOLL_t);
  end-pi;

  dcl-ds def likeds(SCDEF_t);
  dcl-s  key like(SCCOLL_KEY_t);

  clear coll;

  // Keyed on the short name in UTF-8, so LIST_sort_by_key - which compares
  // the key as raw bytes - orders the collection exactly as upstream's
  // TreeMap does.
  coll.list = LIST_create('SCCOLL': %size(def): %size(key));

end-proc;

//==============================================================================
// SCCOLL_load
//==============================================================================

dcl-proc SCCOLL_load export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    ignore_globals like(BOOLEAN_t) const options(*nopass);
  end-pi;

  dcl-ds dirs likeds(SCDIRS_t);
  dcl-ds def  likeds(SCDEF_t);
  dcl-s i     like(INTEGER_t);
  dcl-s skip  like(BOOLEAN_t) inz(false);

  SCCOLL_init(coll);

  if %parms() >= 2 and %addr(ignore_globals) <> *null;
    skip = ignore_globals;
  endif;

  if SCDIRS_search_path(dirs: skip) = 0;
    // No definition directory at all is a legitimate state, not an error:
    // a system with no services configured has nothing to manage.
    return true;
  endif;

  for i = 1 to dirs.count;
    SCCOLL_load_dir(coll: dirs.path(i));
  endfor;

  return true;

end-proc;

//==============================================================================
// SCCOLL_load_dir
//   Load one directory, flat
//==============================================================================

dcl-proc SCCOLL_load_dir export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    dir  like(STMF_t) const;
  end-pi;

  dcl-s handle   pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s path     like(STMF_t);
  dcl-s rrn      like(INTEGER_t);
  dcl-s key      like(SCCOLL_KEY_t);
  dcl-ds def     likeds(SCDEF_t);

  handle = IFS_opendir(dir);
  if handle = *null;
    return false;
  endif;

  dow IFS_readdir(handle: filename);

    // readdir yields these first; walking into them would not terminate
    if filename = '.' or filename = '..';
      iter;
    endif;

    path = %trim(dir) + '/' + %trim(filename);

    // Skipped, not walked. Upstream's loader does the same
    // - 'if (f.isDirectory()) { continue; }' - and reaches the definitions
    // it ships under system/ and oss_common/ because the search path names
    // those directories. Recursing here would report services upstream
    // cannot see, which is as much a parity defect as missing some, and the
    // harder one to notice because nothing looks absent.
    if IFS_isa_directory(path);
      iter;
    endif;

    if not is_yaml(filename);
      iter;
    endif;

    if not SCDEF_load(path: def);
      record_bad(coll: def);
      iter;
    endif;

    // only_if_executable lets a definition describe software that may not be
    // installed. Upstream skips it silently; so do we, or every system would
    // report services it does not have.
    if %len(%trim(def.only_if_executable)) > 0
       and not IFS_isa_directory(def.only_if_executable)
       and IFS_open_file(def.only_if_executable: IFS_OPEN_TYPE_READ) < 0;
      iter;
    endif;

    // Directories are merged in search-path order, and a definition read
    // later REPLACES one of the same name read earlier - upstream merges
    // each directory with putAll. Skipping the later one instead would let
    // the global copy win, which is the opposite of what a user directory
    // is for, and is invisible until two directories define the same name.
    key = def.short_name;

    rrn = find_rrn(coll: def.short_name);
    if rrn > 0;
      LIST_update_by_rrn(coll.list: rrn: %addr(def): %addr(key));
      iter;
    endif;

    LIST_add(coll.list: %addr(def): %addr(key));
    coll.count += 1;

  enddo;

  IFS_closedir(handle);

  // Sorted here rather than after the whole search path, so the collection is
  // ordered at every point a caller could look at it - which is what a
  // TreeMap gives upstream for free. It also means a definition read from a
  // later directory lands in its place rather than on the end.
  LIST_sort_by_key(coll.list);

  return true;

end-proc;

//==============================================================================
// is_yaml
//==============================================================================

dcl-proc is_yaml;
  dcl-pi *n like(BOOLEAN_t);
    filename like(IFS_DIR_FILENAME_t) const;
  end-pi;

  dcl-s lower like(IFS_DIR_FILENAME_t);

  lower = STRING_lower(%trim(filename));

  if %len(lower) > 5 and %subst(lower: %len(lower) - 4) = '.yaml';
    return true;
  endif;

  if %len(lower) > 4 and %subst(lower: %len(lower) - 3) = '.yml';
    return true;
  endif;

  return false;

end-proc;

//==============================================================================
// record_bad
//==============================================================================

dcl-proc record_bad;
  dcl-pi *n;
    coll likeds(SCCOLL_t);
    def  likeds(SCDEF_t) const;
  end-pi;

  if coll.bad_count >= %elem(coll.bad_name);
    return;
  endif;

  coll.bad_count += 1;
  coll.bad_name(coll.bad_count) = def.short_name;
  coll.bad_err(coll.bad_count)  = def.err;

end-proc;

//==============================================================================
// find_rrn
//   The row a definition of this name occupies, or zero
//
// SCCOLL_find answers whether one is there; a replacement needs to know
// where, so the later definition can take the earlier one's place rather
// than being appended alongside it.
//==============================================================================

dcl-proc find_rrn;
  dcl-pi *n like(INTEGER_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
  end-pi;

  dcl-ds def  likeds(SCDEF_t);
  dcl-s  i    like(INTEGER_t);
  dcl-s  want like(SCDEF_NAME_t);

  want = STRING_lower(%trim(name));

  for i = 1 to coll.count;
    if SCCOLL_get(coll: i: def) and def.short_name = want;
      return i;
    endif;
  endfor;

  return 0;

end-proc;

//==============================================================================
// SCCOLL_count
//==============================================================================

dcl-proc SCCOLL_count export;
  dcl-pi *n like(INTEGER_t);
    coll likeds(SCCOLL_t);
  end-pi;

  return coll.count;

end-proc;

//==============================================================================
// SCCOLL_get
//==============================================================================

dcl-proc SCCOLL_get export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    rrn  like(INTEGER_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  clear def;
  if rrn < 1 or rrn > coll.count;
    return false;
  endif;

  return LIST_get_by_rrn(coll.list: rrn: %addr(def));

end-proc;

//==============================================================================
// SCCOLL_find
//==============================================================================

dcl-proc SCCOLL_find export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    name like(SCDEF_NAME_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s want like(SCDEF_NAME_t);

  want = STRING_lower(%trim(name));

  for i = 1 to coll.count;
    if SCCOLL_get(coll: i: def) and def.short_name = want;
      return true;
    endif;
  endfor;

  clear def;
  return false;

end-proc;

//==============================================================================
// SCCOLL_groups
//==============================================================================

dcl-proc SCCOLL_groups export;
  dcl-pi *n like(INTEGER_t);
    coll          likeds(SCCOLL_t);
    groups        likeds(SCCOLL_GROUPS_t);
    ignore_groups like(SCDEF_NAME_t) const options(*nopass);
  end-pi;

  dcl-ds def  likeds(SCDEF_t);
  dcl-s i     like(INTEGER_t);
  dcl-s j     like(INTEGER_t);
  dcl-s k     like(INTEGER_t);
  dcl-s seen  like(BOOLEAN_t);
  dcl-s swap  like(SCDEF_NAME_t);

  dcl-s exclude like(SCDEF_NAME_t) inz('');

  if %parms() >= 3 and %addr(ignore_groups) <> *null;
    exclude = ignore_groups;
  endif;

  clear groups;

  for i = 1 to coll.count;
    if not SCCOLL_get(coll: i: def);
      iter;
    endif;

    // The filter names SERVICES to leave out, not names to leave out of the
    // answer. A group declared only by excluded services disappears; one an
    // excluded service shared with a surviving one stays, because the
    // survivor still declares it.
    if exclude <> '' and SCCOLL_in_groups(def: exclude);
      iter;
    endif;

    for j = 1 to def.group_count;
      seen = false;
      for k = 1 to groups.count;
        if groups.name(k) = def.groups(j);
          seen = true;
          leave;
        endif;
      endfor;

      if not seen and groups.count < SCCOLL_MAX_GROUPS;
        groups.count += 1;
        groups.name(groups.count) = def.groups(j);
      endif;
    endfor;
  endfor;

  // Sorted by the same rule the collection itself is sorted by. Group names
  // are not held in a list, so they cannot ride on a UTF-8 key - but the
  // question asked is identical, and asking it in one place is what stops the
  // two drifting. An insertion sort: a collection has a handful of groups.
  for i = 2 to groups.count;
    swap = groups.name(i);
    j = i - 1;
    dow j >= 1 and SCCOLL_sorts_before(swap: groups.name(j));
      groups.name(j + 1) = groups.name(j);
      j -= 1;
    enddo;
    groups.name(j + 1) = swap;
  endfor;

  return groups.count;

end-proc;

//==============================================================================
// SCCOLL_start_order
//   Depth-first, dependencies first, with cycle detection
//==============================================================================

dcl-proc SCCOLL_start_order export;
  dcl-pi *n like(BOOLEAN_t);
    coll  likeds(SCCOLL_t);
    name  like(SCDEF_NAME_t) const;
    order likeds(SCCOLL_ORDER_t);
  end-pi;

  dcl-ds path likeds(SCCOLL_ORDER_t);

  clear order;
  clear path;

  return visit(coll: name: order: path);

end-proc;

//==============================================================================
// visit
//   One node of the depth-first walk
//
// 'path' holds the chain currently being explored. A name reappearing in it
// is a cycle - upstream recurses with no such check and overflows its stack,
// which says nothing useful about which definitions are at fault.
//==============================================================================

dcl-proc visit;
  dcl-pi *n like(BOOLEAN_t);
    coll  likeds(SCCOLL_t);
    name  like(SCDEF_NAME_t) const;
    order likeds(SCCOLL_ORDER_t);
    path  likeds(SCCOLL_ORDER_t);
  end-pi;

  dcl-ds def likeds(SCDEF_t);
  dcl-s want like(SCDEF_NAME_t);
  dcl-s i    like(INTEGER_t);

  want = STRING_lower(%trim(name));

  // Already placed by another branch of the graph
  if in_order(order: want);
    return true;
  endif;

  if in_order(path: want);
    order.err = 'Dependency cycle involving ' + %trim(want);
    return false;
  endif;

  if not SCCOLL_find(coll: want: def);
    order.err = 'Unknown service ' + %trim(want);
    return false;
  endif;

  if path.count >= SCCOLL_MAX_ORDER;
    order.err = 'Dependency chain deeper than ' + %char(SCCOLL_MAX_ORDER);
    return false;
  endif;

  path.count += 1;
  path.name(path.count) = want;

  for i = 1 to def.dep_count;
    if not visit(coll: def.deps(i): order: path);
      return false;
    endif;
  endfor;

  path.count -= 1;

  if order.count >= SCCOLL_MAX_ORDER;
    order.err = 'More than ' + %char(SCCOLL_MAX_ORDER) + ' services to start';
    return false;
  endif;

  order.count += 1;
  order.name(order.count) = want;

  return true;

end-proc;

//==============================================================================
// in_order
//==============================================================================

//==============================================================================
// in_order
//==============================================================================

dcl-proc in_order;
  dcl-pi *n like(BOOLEAN_t);
    order likeds(SCCOLL_ORDER_t) const;
    name  like(SCDEF_NAME_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to order.count;
    if order.name(i) = name;
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// SCCOLL_sorts_before
//   The application's one ordering rule
//==============================================================================

dcl-proc SCCOLL_sorts_before export;
  dcl-pi *n like(BOOLEAN_t);
    a_name like(SCDEF_NAME_t) const;
    b_name like(SCDEF_NAME_t) const;
  end-pi;

  dcl-s a_utf like(SCCOLL_KEY_t);
  dcl-s b_utf like(SCCOLL_KEY_t);

  // Assigning into a ccsid(*utf8) field converts, and comparing two of them
  // compares UTF-8 bytes - which is code-point order, and so upstream's.
  a_utf = a_name;
  b_utf = b_name;

  return (a_utf < b_utf);

end-proc;

//==============================================================================
// SCCOLL_in_groups
//   Is this definition in any of these groups?
//==============================================================================

dcl-proc SCCOLL_in_groups export;
  dcl-pi *n like(BOOLEAN_t);
    def    likeds(SCDEF_t) const;
    groups like(SCDEF_NAME_t) const;
  end-pi;

  dcl-s rest  like(SCDEF_NAME_t);
  dcl-s part  like(SCDEF_NAME_t);
  dcl-s comma like(INTEGER_t);

  rest = STRING_lower(%trim(groups));

  dow %len(rest) > 0;
    comma = %scan(',': rest);
    if comma = 0;
      part = %trim(rest);
      rest = '';
    else;
      part = %trim(%subst(rest: 1: comma - 1));

      // A comma in the last position leaves nothing after it, and %SUBST
      // rejects a start beyond the end of the string rather than yielding an
      // empty one - so '--ignore-groups=web,' abended where it should simply
      // have ignored the empty element, which is what upstream does by
      // splitting in Java.
      if comma < %len(rest);
        rest = %trim(%subst(rest: comma + 1));
      else;
        rest = '';
      endif;
    endif;

    // Whole name, via SCDEF_in_group - not a scan of the comma string, which
    // would let 'filgrp_a' match a service in 'filgrp_ax'.
    if %len(part) > 0 and SCDEF_in_group(def: part);
      return true;
    endif;
  enddo;

  return false;

end-proc;
