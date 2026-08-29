**free

//==============================================================================
// SCDEF      - Service definition model
//
// Maps a parsed YAML document onto a typed service definition and applies
// upstream's defaults.
//
// SCYAML deliberately does not know which keys are meaningful. That knowledge
// lives here, which is why an unrecognised key is recorded rather than
// rejected: a key added upstream must not stop a definition loading.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Service definition model');
/include 'include/RMCOMP_H.rpgleinc'
/define APP_SERVICE_PROGRAM
/include 'include/RMTOOLS_H.rpgleinc'

///
// Include copybooks
///

/include 'SCDEF_D.rpgleinc'
/include 'SCYAML_D.rpgleinc'
/include 'include/RMPATH_D.rpgleinc'
/include 'include/RMSTRING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

///
// Internal prototypes
///

dcl-pr is_known_key like(BOOLEAN_t);
  key like(SCYAML_KEY_t) const;
end-pr;

dcl-pr to_boolean like(BOOLEAN_t);
  value   like(SCYAML_VALUE_t) const;
  default like(BOOLEAN_t) const;
end-pr;

dcl-pr to_integer like(INTEGER_t);
  value   like(SCYAML_VALUE_t) const;
  default like(INTEGER_t) const;
end-pr;

dcl-pr add_criterion like(BOOLEAN_t);
  def likeds(SCDEF_t);
  raw like(SCDEF_CRIT_t) const;
end-pr;

dcl-pr load_criteria like(BOOLEAN_t);
  doc likeds(SCYAML_DOC_t) const;
  def likeds(SCDEF_t);
end-pr;

dcl-pr split_commas like(BOOLEAN_t);
  def   likeds(SCDEF_t);
  value like(SCYAML_VALUE_t) const;
end-pr;

//==============================================================================
// SCDEF_load
//==============================================================================

dcl-proc SCDEF_load export;
  dcl-pi *n like(BOOLEAN_t);
    stmf like(STMF_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  dcl-ds doc likeds(SCYAML_DOC_t);

  clear def;

  if not SCYAML_parse(stmf: doc);
    def.err = SCYAML_error(doc);
    return false;
  endif;

  return SCDEF_from_doc(doc: stmf: def);

end-proc;

//==============================================================================
// SCDEF_from_doc
//==============================================================================

dcl-proc SCDEF_from_doc export;
  dcl-pi *n like(BOOLEAN_t);
    doc  likeds(SCYAML_DOC_t) const;
    stmf like(STMF_t) const;
    def  likeds(SCDEF_t);
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s n    like(INTEGER_t);
  dcl-s key  like(SCYAML_KEY_t);

  clear def;

  def.defined_at = stmf;

  // Upstream takes the short name from the file name, lower-cased
  def.short_name = STRING_lower(PATH_name(stmf));

  // A cluster definition is rejected rather than silently half-honoured:
  // RMSC does not implement cluster mode, and quietly starting a single
  // backend where the author asked for several would be worse than refusing.
  if SCYAML_has(doc: 'cluster');
    def.is_cluster = true;
    def.err = 'Service ' + %trim(def.short_name) +
              ' uses cluster mode, which RMSC does not implement';
    return false;
  endif;

  def.friendly    = SCYAML_value(doc: 'name');
  def.dir         = SCYAML_value(doc: 'dir');
  def.start_cmd   = SCYAML_value(doc: 'start_cmd');
  def.log_dir     = SCYAML_value(doc: 'log_dir');
  def.sbmjob_opts = SCYAML_value(doc: 'sbmjob_opts');
  def.only_if_executable = SCYAML_value(doc: 'only_if_executable');

  if %len(SCYAML_value(doc: 'sbmjob_jobname')) > 0;
    def.sbmjob_jobname = SCYAML_value(doc: 'sbmjob_jobname');
  endif;

  // A stop_cmd of null is the same as no stop_cmd: fall back to ENDJOB
  def.stop_cmd = SCYAML_value(doc: 'stop_cmd');
  def.has_stop_cmd = (%len(%trim(def.stop_cmd)) > 0);

  def.startup_wait = to_integer(SCYAML_value(doc: 'startup_wait_time'):
                                SCDEF_DFT_STARTUP_WAIT);
  def.stop_wait    = to_integer(SCYAML_value(doc: 'stop_wait_time'):
                                SCDEF_DFT_STOP_WAIT);

  def.batch_mode   = to_boolean(SCYAML_value(doc: 'batch_mode'): false);
  def.inherit_vars = to_boolean(
      SCYAML_value(doc: 'environment_is_inheriting_vars'): true);

  // Friendly name defaults to the short name, so 'check' always has something
  // to print in its description column
  if %len(%trim(def.friendly)) = 0;
    def.friendly = def.short_name;
  endif;

  if not load_criteria(doc: def);
    return false;
  endif;

  // Sequences
  n = SCYAML_count(doc: 'environment_vars');
  for i = 1 to n;
    if def.envvar_count >= SCDEF_MAX_ENVVARS;
      def.err = 'More than ' + %char(SCDEF_MAX_ENVVARS) + ' environment_vars';
      return false;
    endif;
    def.envvar_count += 1;
    def.envvars(def.envvar_count) = SCYAML_item(doc: 'environment_vars': i);
  endfor;

  n = SCYAML_count(doc: 'service_dependencies');
  for i = 1 to n;
    if def.dep_count >= SCDEF_MAX_DEPS;
      def.err = 'More than ' + %char(SCDEF_MAX_DEPS) + ' service_dependencies';
      return false;
    endif;
    def.dep_count += 1;
    def.deps(def.dep_count) = STRING_lower(SCYAML_item(doc:
                                'service_dependencies': i));
  endfor;

  n = SCYAML_count(doc: 'groups');
  for i = 1 to n;
    if def.group_count >= SCDEF_MAX_GROUPS;
      def.err = 'More than ' + %char(SCDEF_MAX_GROUPS) + ' groups';
      return false;
    endif;
    def.group_count += 1;
    def.groups(def.group_count) = STRING_lower(SCYAML_item(doc: 'groups': i));
  endfor;

  // Record anything not in the schema. Not an error - see the header.
  for i = 1 to SCYAML_key_count(doc);
    key = SCYAML_key_name(doc: i);
    if not is_known_key(key);
      if def.unknown_count < SCDEF_MAX_UNKNOWN;
        def.unknown_count += 1;
        def.unknown(def.unknown_count) = key;
      endif;
    endif;
  endfor;

  // The two keys upstream requires
  if %len(%trim(def.start_cmd)) = 0;
    def.err = 'Service ' + %trim(def.short_name) + ' has no start_cmd';
    return false;
  endif;

  if def.criteria_count = 0;
    def.err = 'Service ' + %trim(def.short_name) + ' has no check_alive';
    return false;
  endif;

  return true;

end-proc;

//==============================================================================
// load_criteria
//   check_alive, or its deprecated alias, in scalar or sequence form
//==============================================================================

dcl-proc load_criteria;
  dcl-pi *n like(BOOLEAN_t);
    doc likeds(SCYAML_DOC_t) const;
    def likeds(SCDEF_t);
  end-pi;

  dcl-s key like(SCYAML_KEY_t);
  dcl-s i   like(INTEGER_t);
  dcl-s n   like(INTEGER_t);

  // check_alive_criteria is upstream's deprecated spelling. Accept it, but
  // prefer check_alive when a file carries both.
  key = 'check_alive';
  if not SCYAML_has(doc: key);
    key = 'check_alive_criteria';
    if not SCYAML_has(doc: key);
      return true;
    endif;
  endif;

  if SCYAML_is_seq(doc: key);
    n = SCYAML_count(doc: key);
    for i = 1 to n;
      if not add_criterion(def: SCYAML_item(doc: key: i));
        def.err = 'More than ' + %char(SCDEF_MAX_CRITERIA) +
                  ' check_alive criteria';
        return false;
      endif;
    endfor;
    return true;
  endif;

  return split_commas(def: SCYAML_value(doc: key));

end-proc;

//==============================================================================
// split_commas
//   A scalar check_alive may hold several criteria, comma separated
//==============================================================================

dcl-proc split_commas;
  dcl-pi *n like(BOOLEAN_t);
    def   likeds(SCDEF_t);
    value like(SCYAML_VALUE_t) const;
  end-pi;

  dcl-s rest  like(SCYAML_VALUE_t);
  dcl-s part  like(SCDEF_CRIT_t);
  dcl-s comma like(INTEGER_t);

  rest = %trim(value);

  dow %len(rest) > 0;
    comma = %scan(',': rest);
    if comma = 0;
      part = %trim(rest);
      rest = '';
    else;
      part = %trim(%subst(rest: 1: comma - 1));
      rest = %trim(%subst(rest: comma + 1));
    endif;

    if %len(part) > 0;
      if not add_criterion(def: part);
        def.err = 'More than ' + %char(SCDEF_MAX_CRITERIA) +
                  ' check_alive criteria';
        return false;
      endif;
    endif;
  enddo;

  return true;

end-proc;

//==============================================================================
// add_criterion
//   Classify one criterion by its shape, as upstream does
//==============================================================================

dcl-proc add_criterion;
  dcl-pi *n like(BOOLEAN_t);
    def likeds(SCDEF_t);
    raw like(SCDEF_CRIT_t) const;
  end-pi;

  dcl-s work  like(SCDEF_CRIT_t);
  dcl-s slash like(INTEGER_t);
  dcl-s i     like(INTEGER_t);
  dcl-s digits like(BOOLEAN_t);

  work = %trim(raw);
  if %len(work) = 0;
    return true;
  endif;

  if def.criteria_count >= SCDEF_MAX_CRITERIA;
    return false;
  endif;

  def.criteria_count += 1;
  def.criteria(def.criteria_count).raw = work;

  // All digits: a port
  digits = true;
  for i = 1 to %len(work);
    if %subst(work: i: 1) < '0' or %subst(work: i: 1) > '9';
      digits = false;
      leave;
    endif;
  endfor;

  if digits;
    def.criteria(def.criteria_count).kind = SCDEF_CHECK_PORT;
    def.criteria(def.criteria_count).port = %int(work);
    return true;
  endif;

  // PGM-name: jobs running that program
  if %len(work) > 4 and %xlate('pgm-': 'PGM-': %subst(work: 1: 4)) = 'PGM-';
    def.criteria(def.criteria_count).kind = SCDEF_CHECK_PGM;
    def.criteria(def.criteria_count).program =
        %xlate('abcdefghijklmnopqrstuvwxyz': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
               %subst(work: 5));
    return true;
  endif;

  // subsystem/job, or a bare job name
  def.criteria(def.criteria_count).kind = SCDEF_CHECK_JOB;
  slash = %scan('/': work);
  if slash > 1 and slash < %len(work);
    def.criteria(def.criteria_count).subsystem =
        %xlate('abcdefghijklmnopqrstuvwxyz': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
               %subst(work: 1: slash - 1));
    def.criteria(def.criteria_count).job_name =
        %xlate('abcdefghijklmnopqrstuvwxyz': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
               %subst(work: slash + 1));
  else;
    def.criteria(def.criteria_count).job_name =
        %xlate('abcdefghijklmnopqrstuvwxyz': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
               work);
  endif;

  return true;

end-proc;

//==============================================================================
// to_boolean
//==============================================================================

dcl-proc to_boolean;
  dcl-pi *n like(BOOLEAN_t);
    value   like(SCYAML_VALUE_t) const;
    default like(BOOLEAN_t) const;
  end-pi;

  dcl-s work like(SCYAML_VALUE_t);

  work = STRING_lower(%trim(value));

  if %len(work) = 0;
    return default;
  endif;

  // YAML 1.1 truthy spellings, which is what upstream's parser accepted
  if work = 'true' or work = 'yes' or work = 'on' or work = '1';
    return true;
  endif;

  if work = 'false' or work = 'no' or work = 'off' or work = '0';
    return false;
  endif;

  return default;

end-proc;

//==============================================================================
// to_integer
//==============================================================================

dcl-proc to_integer;
  dcl-pi *n like(INTEGER_t);
    value   like(SCYAML_VALUE_t) const;
    default like(INTEGER_t) const;
  end-pi;

  dcl-s work like(SCYAML_VALUE_t);
  dcl-s i    like(INTEGER_t);

  work = %trim(value);
  if %len(work) = 0;
    return default;
  endif;

  // A non-numeric wait time falls back to the default rather than failing the
  // load: a bad number should not stop a service being managed.
  for i = 1 to %len(work);
    if %subst(work: i: 1) < '0' or %subst(work: i: 1) > '9';
      return default;
    endif;
  endfor;

  return %int(work);

end-proc;

//==============================================================================
// is_known_key
//==============================================================================

dcl-proc is_known_key;
  dcl-pi *n like(BOOLEAN_t);
    key like(SCYAML_KEY_t) const;
  end-pi;

  select;
    when key = 'name'
      or key = 'dir'
      or key = 'start_cmd'
      or key = 'stop_cmd'
      or key = 'check_alive'
      or key = 'check_alive_criteria'
      or key = 'startup_wait_time'
      or key = 'stop_wait_time'
      or key = 'log_dir'
      or key = 'batch_mode'
      or key = 'sbmjob_jobname'
      or key = 'sbmjob_opts'
      or key = 'environment_is_inheriting_vars'
      or key = 'environment_vars'
      or key = 'service_dependencies'
      or key = 'groups'
      or key = 'only_if_executable'
      or key = 'cluster';
      return true;
    other;
      return false;
  endsl;

end-proc;

//==============================================================================
// SCDEF_in_group
//==============================================================================

dcl-proc SCDEF_in_group export;
  dcl-pi *n like(BOOLEAN_t);
    def   likeds(SCDEF_t) const;
    group like(SCDEF_NAME_t) const;
  end-pi;

  dcl-s i    like(INTEGER_t);
  dcl-s want like(SCDEF_NAME_t);

  want = STRING_lower(%trim(group));

  // Every service is in 'all'
  if want = 'all';
    return true;
  endif;

  for i = 1 to def.group_count;
    if def.groups(i) = want;
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// SCDEF_effective_dir
//==============================================================================

dcl-proc SCDEF_effective_dir export;
  dcl-pi *n like(STMF_t);
    def likeds(SCDEF_t) const;
  end-pi;

  dcl-s base like(STMF_t);
  dcl-s slash like(INTEGER_t);

  // The directory holding the definition file
  base = def.defined_at;
  slash = %scanr('/': base);
  if slash > 1;
    base = %subst(base: 1: slash - 1);
  else;
    base = '.';
  endif;

  if %len(%trim(def.dir)) = 0;
    return base;
  endif;

  // An absolute dir stands alone; a relative one resolves against the file
  if %subst(%trim(def.dir): 1: 1) = '/';
    return %trim(def.dir);
  endif;

  return %trim(base) + '/' + %trim(def.dir);

end-proc;
