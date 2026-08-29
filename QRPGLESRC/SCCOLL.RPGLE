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

  clear coll;
  coll.list = LIST_create('SCCOLL': %size(def));

end-proc;

//==============================================================================
// SCCOLL_load
//==============================================================================

dcl-proc SCCOLL_load export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
  end-pi;

  dcl-ds dirs likeds(SCDIRS_t);
  dcl-ds def  likeds(SCDEF_t);
  dcl-s i     like(INTEGER_t);

  SCCOLL_init(coll);

  if SCDIRS_search_path(dirs) = 0;
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
//   Load one directory, recursing into subdirectories
//==============================================================================

dcl-proc SCCOLL_load_dir export;
  dcl-pi *n like(BOOLEAN_t);
    coll likeds(SCCOLL_t);
    dir  like(STMF_t) const;
  end-pi;

  dcl-s handle   pointer;
  dcl-s filename like(IFS_DIR_FILENAME_t);
  dcl-s path     like(STMF_t);
  dcl-ds def     likeds(SCDEF_t);
  dcl-ds existing likeds(SCDEF_t);

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

    if IFS_isa_directory(path);
      SCCOLL_load_dir(coll: path);
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

    // The global directory is searched before the user's own, and a user
    // definition of the same name replaces the global one rather than
    // duplicating it.
    if SCCOLL_find(coll: def.short_name: existing);
      iter;
    endif;

    LIST_add(coll.list: %addr(def));
    coll.count += 1;

  enddo;

  IFS_closedir(handle);
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
    coll   likeds(SCCOLL_t);
    groups likeds(SCCOLL_GROUPS_t);
  end-pi;

  dcl-ds def likeds(SCDEF_t);
  dcl-s i    like(INTEGER_t);
  dcl-s j    like(INTEGER_t);
  dcl-s k    like(INTEGER_t);
  dcl-s seen like(BOOLEAN_t);

  clear groups;

  for i = 1 to coll.count;
    if not SCCOLL_get(coll: i: def);
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
