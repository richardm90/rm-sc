**free

//==============================================================================
// SCAPI      - Service Commander bound-call API
//
// The interface for an ILE caller. Nothing here writes to standard output:
// a green-screen program calling this must not have stray text appear
// underneath its display file, so status is returned rather than printed.
//
// That is also the substantive difference from the command line. Reading
// 'check' output means running a process, waiting for a job, re-reading every
// definition, and then parsing text by column position - and a consumer that
// parses by column silently drops any row it cannot make sense of. Here the
// status arrives as a value.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Bound-call API');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

/include 'SCAPI_D.rpgleinc'
/include 'SCCOLL_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCEXEC_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMLIST_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-c SCAPI_DFT_IGNORE const('system');

///
// The loaded definitions, kept for the life of the activation.
//
// Without this the API is pointless. Measured: reloading on every call costs
// 2.64s per call and ten calls take 26.4s, which is no better than running the
// command - the caller saves the process and the job, then pays it all back
// re-reading 39 definitions it already read.
//
// Definitions are read once and reused. Live status is NOT cached: every call
// re-queries the system, because that is the question being asked.
//
// The cost is staleness - a definition added or edited after the first call
// is not seen until SC_refresh(). For a long-running display program that is
// the right trade, and SC_refresh gives it a way to say otherwise.
///

dcl-ds g_coll likeds(SCCOLL_t) inz(*likeds);
dcl-s g_loaded like(BOOLEAN_t) inz(false);

dcl-pr ensure_loaded;
end-pr;

dcl-pr ignored_by like(BOOLEAN_t);
  def           likeds(SCDEF_t) const;
  ignore_groups like(SC_NAME_t) const;
end-pr;

dcl-pr act_on like(BOOLEAN_t);
  name   like(SC_NAME_t) const;
  action like(SC_NAME_t) const;
  msg    like(SC_MSG_t);
end-pr;

//==============================================================================
// ensure_loaded
//==============================================================================

dcl-proc ensure_loaded;

  if g_loaded;
    return;
  endif;

  SCCOLL_load(g_coll);
  g_loaded = true;

end-proc;

//==============================================================================
// SC_refresh
//   Forget the loaded definitions, so the next call re-reads them
//==============================================================================

dcl-proc SC_refresh export;

  g_loaded = false;

end-proc;

//==============================================================================
// SC_check_all
//==============================================================================

dcl-proc SC_check_all export;
  dcl-pi *n likeds(LIST_t);
    ignore_groups like(SC_NAME_t) const options(*nopass);
  end-pi;

  dcl-ds list likeds(LIST_t) inz(*likeds);
  dcl-ds def  likeds(SCDEF_t)  inz(*likeds);
  dcl-ds row  likeds(SC_STATUS_ROW_t) inz(*likeds);
  dcl-s ignore like(SC_NAME_t);
  dcl-s i      like(INTEGER_t);
  dcl-s rrn    like(INTEGER_t) inz(0);

  ignore = SCAPI_DFT_IGNORE;
  if %parms() >= 1 and %addr(ignore_groups) <> *null;
    ignore = ignore_groups;
  endif;

  list = LIST_create('SCAPI': %size(row));

  ensure_loaded();

  for i = 1 to SCCOLL_count(g_coll);
    if not SCCOLL_get(g_coll: i: def) or ignored_by(def: ignore);
      iter;
    endif;

    reset row;
    rrn += 1;
    row.RRN    = rrn;
    row.NAME   = def.short_name;
    row.DESC   = def.friendly;
    row.STATUS = SCEXEC_status(def);

    LIST_add(list: %addr(row));
  endfor;

  return list;

end-proc;

//==============================================================================
// SC_check
//==============================================================================

dcl-proc SC_check export;
  dcl-pi *n like(BOOLEAN_t);
    name   like(SC_NAME_t) const;
    status likeds(SC_STATUS_ROW_t);
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s rrn like(INTEGER_t);

  // The caller may be refreshing one row of a list it already holds, so keep
  // whatever RRN it had rather than zeroing it
  rrn = status.RRN;

  ensure_loaded();

  if not SCCOLL_find(g_coll: name: def);
    return false;
  endif;

  status.RRN    = rrn;
  status.NAME   = def.short_name;
  status.DESC   = def.friendly;
  status.STATUS = SCEXEC_status(def);

  return true;

end-proc;

//==============================================================================
// ignored_by
//==============================================================================

dcl-proc ignored_by;
  dcl-pi *n like(BOOLEAN_t);
    def           likeds(SCDEF_t) const;
    ignore_groups like(SC_NAME_t) const;
  end-pi;

  dcl-s rest  like(SC_NAME_t);
  dcl-s part  like(SC_NAME_t);
  dcl-s comma like(INTEGER_t);

  rest = STRING_lower(%trim(ignore_groups));

  dow %len(rest) > 0;
    comma = %scan(',': rest);
    if comma = 0;
      part = %trim(rest);
      rest = '';
    else;
      part = %trim(%subst(rest: 1: comma - 1));

      // As in SCCOLL_in_groups, which this duplicates: a comma in the last
      // position leaves nothing after it and %SUBST rejects the start. Fixing
      // one copy of a splitter and not the other is how the defect returns.
      if comma < %len(rest);
        rest = %trim(%subst(rest: comma + 1));
      else;
        rest = '';
      endif;
    endif;

    if %len(part) > 0 and SCDEF_in_group(def: part);
      return true;
    endif;
  enddo;

  return false;

end-proc;

//==============================================================================
// act_on
//   One place for start, stop, kill and restart, including group: handling
//==============================================================================

dcl-proc act_on;
  dcl-pi *n like(BOOLEAN_t);
    name   like(SC_NAME_t) const;
    action like(SC_NAME_t) const;
    msg    like(SC_MSG_t);
  end-pi;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s err   like(SCEXEC_ERR_t);
  dcl-s group like(SC_NAME_t);
  dcl-s i     like(INTEGER_t);
  dcl-s ok    like(BOOLEAN_t) inz(true);
  dcl-s acted like(BOOLEAN_t) inz(false);
  dcl-s one   like(BOOLEAN_t);

  msg = '';
  ensure_loaded();

  // 'group:x' is accepted so a caller that already builds that prefix for the
  // command line does not have to change how it does it
  if %len(name) > 6 and STRING_lower(%subst(name: 1: 6)) = 'group:';
    group = STRING_lower(%subst(name: 7));

    for i = 1 to SCCOLL_count(g_coll);
      if not SCCOLL_get(g_coll: i: def) or not SCDEF_in_group(def: group);
        iter;
      endif;
      acted = true;

      select;
        when action = 'start';
          one = SCEXEC_start(g_coll: def.short_name: err);
        when action = 'stop';
          one = SCEXEC_stop(g_coll: def.short_name: false: err);
        when action = 'kill';
          one = SCEXEC_stop(g_coll: def.short_name: true: err);
        other;
          one = SCEXEC_restart(g_coll: def.short_name: err);
      endsl;

      // Carry on through the group rather than stopping at the first
      // failure: a caller asking for a group wants as much of it up as can
      // be, and one bad service should not hide the rest.
      if not one;
        ok = false;
        if %len(%trim(msg)) > 0;
          msg += '; ';
        endif;
        msg += %trim(err);
      endif;
    endfor;

    if not acted;
      msg = 'No services in group ' + %trim(group);
      return false;
    endif;

    return ok;
  endif;

  if not SCCOLL_find(g_coll: name: def);
    msg = 'Unknown service ' + %trim(name);
    return false;
  endif;

  select;
    when action = 'start';
      ok = SCEXEC_start(g_coll: def.short_name: err);
    when action = 'stop';
      ok = SCEXEC_stop(g_coll: def.short_name: false: err);
    when action = 'kill';
      ok = SCEXEC_stop(g_coll: def.short_name: true: err);
    other;
      ok = SCEXEC_restart(g_coll: def.short_name: err);
  endsl;

  if not ok;
    msg = err;
  endif;

  return ok;

end-proc;

//==============================================================================
// SC_start / SC_stop / SC_kill / SC_restart
//==============================================================================

dcl-proc SC_start export;
  dcl-pi *n like(BOOLEAN_t);
    name like(SC_NAME_t) const;
    msg  like(SC_MSG_t);
  end-pi;

  return act_on(name: 'start': msg);

end-proc;

dcl-proc SC_stop export;
  dcl-pi *n like(BOOLEAN_t);
    name like(SC_NAME_t) const;
    msg  like(SC_MSG_t);
  end-pi;

  return act_on(name: 'stop': msg);

end-proc;

dcl-proc SC_kill export;
  dcl-pi *n like(BOOLEAN_t);
    name like(SC_NAME_t) const;
    msg  like(SC_MSG_t);
  end-pi;

  return act_on(name: 'kill': msg);

end-proc;

dcl-proc SC_restart export;
  dcl-pi *n like(BOOLEAN_t);
    name like(SC_NAME_t) const;
    msg  like(SC_MSG_t);
  end-pi;

  return act_on(name: 'restart': msg);

end-proc;
