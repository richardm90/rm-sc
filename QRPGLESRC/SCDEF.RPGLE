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
  def  likeds(SCDEF_t);
  raw  like(SCDEF_CRIT_t) const;
  kind like(SCDEF_KIND_t) const options(*nopass);
end-pr;

// The type names check_alive may carry instead of a value, or blank if it
// carries a value. PORT and JOBNAME only, matched without regard to case -
// 'pgm' and 'process' are not types and fall through to being job names.
dcl-pr criterion_type like(SCDEF_KIND_t);
  value like(SCDEF_CRIT_t) const;
end-pr;

// Whether a port criterion's text can be used as a port number at all.
dcl-pr usable_port like(BOOLEAN_t);
  value like(SCDEF_CRIT_t) const;
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

  // Upstream takes the short name from the file name, lower-cased.
  //
  // Not dead code, though discovery now makes it look it: SCCOLL only ever
  // hands this procedure names that already passed upstream's filename regex,
  // which admits no capitals, so via that path the lower-casing changes
  // nothing. SCDEF_load is also called directly - by the bound-call API and by
  // the suites - and those callers can pass any path at all. Removing this
  // would leave those callers with a short name that no longer matches how
  // every other part of RMSC spells it.
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

  dcl-s key    like(SCYAML_KEY_t);
  dcl-s i      like(INTEGER_t);
  dcl-s n      like(INTEGER_t);
  dcl-s forced like(SCDEF_KIND_t);

  // check_alive is required and has no alternative spelling. A file carrying
  // only check_alive_criteria is discarded - the caller's criteria_count
  // check reports it - which is what upstream does with it.
  key = 'check_alive';
  if not SCYAML_has(doc: key);
    return true;
  endif;

  // The type-and-value form: check_alive names a TYPE and check_alive_criteria
  // supplies its value. It applies only when both keys are present and the
  // first really is a type name; 'check_alive: port' on its own means a job
  // called PORT, and a check_alive carrying an ordinary value ignores the
  // companion. All three measured against sc 1.7.1.
  //
  // The type decides the kind outright. 'jobname' with a value of 12345 is a
  // job named 12345, not port 12345, so the value is never re-inspected.
  if SCYAML_has(doc: 'check_alive_criteria') and not SCYAML_is_seq(doc: key);
    forced = criterion_type(SCYAML_value(doc: key));
    if %len(%trim(forced)) > 0;
      if not add_criterion(def: SCYAML_value(doc: 'check_alive_criteria'):
                           forced);
        def.err = 'More than ' + %char(SCDEF_MAX_CRITERIA) +
                  ' check_alive criteria';
        return false;
      endif;
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

      // A comma in the last position leaves nothing after it, and %SUBST
      // rejects a start beyond the end of the string. 'check_alive: name,'
      // abended the whole command where upstream loads the definition and
      // reports the service normally - and this one arrives in a file rather
      // than on a command line, so it is the likelier of the two to be met.
      if comma < %len(rest);
        rest = %trim(%subst(rest: comma + 1));
      else;
        rest = '';
      endif;
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
    def  likeds(SCDEF_t);
    raw  like(SCDEF_CRIT_t) const;
    kind like(SCDEF_KIND_t) const options(*nopass);
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

  // A kind given by the caller came from a check_alive naming a type, and
  // settles it: the value is not inspected, so a job named 12345 stays a job.
  if %parms() >= 3 and %addr(kind) <> *null and %len(%trim(kind)) > 0;
    def.criteria(def.criteria_count).kind = kind;
    if kind = SCDEF_CHECK_PORT;
      // Only if it really is a number. %int is lenient - it reads 22 out of
      // '22,23' and 12 out of '12ab' - and raises RNX0105 on 'abc', so
      // converting whatever arrived either answers the wrong question
      // silently or brings the program down. Upstream keeps the text, loads
      // the definition, and complains when it tries to USE it, so .port stays
      // zero here and the criterion is judged unusable at evaluate time.
      if usable_port(work);
        def.criteria(def.criteria_count).port = %int(work);
      endif;
    else;
      slash = %scan('/': work);
      if slash > 1 and slash < %len(work);
        def.criteria(def.criteria_count).subsystem =
            STRING_upper(%subst(work: 1: slash - 1));
        def.criteria(def.criteria_count).job_name =
            STRING_upper(%subst(work: slash + 1));
      else;
        def.criteria(def.criteria_count).job_name = STRING_upper(work);
      endif;
    endif;
    return true;
  endif;

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

  // Note that 'digits' above decides the KIND. A criterion reached through
  // the type-and-value form is a port because check_alive said so, and its
  // value may be anything at all - see the forced-kind path below, which is
  // where 'port' + 'abc' arrives. Nothing is converted without checking.

  // PGM-name: jobs running that program
  if %len(work) > 4 and STRING_upper(%subst(work: 1: 4)) = 'PGM-';
    def.criteria(def.criteria_count).kind = SCDEF_CHECK_PGM;
    def.criteria(def.criteria_count).program =
        STRING_upper(%subst(work: 5));
    return true;
  endif;

  // subsystem/job, or a bare job name
  def.criteria(def.criteria_count).kind = SCDEF_CHECK_JOB;
  slash = %scan('/': work);
  if slash > 1 and slash < %len(work);
    def.criteria(def.criteria_count).subsystem =
        STRING_upper(%subst(work: 1: slash - 1));
    def.criteria(def.criteria_count).job_name =
        STRING_upper(%subst(work: slash + 1));
  else;
    def.criteria(def.criteria_count).job_name =
        STRING_upper(work);
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

//==============================================================================
// SCDEF_criterion_text
//==============================================================================

dcl-proc SCDEF_criterion_text export;
  dcl-pi *n like(SCDEF_NAME_t);
    criterion likeds(SCDEF_CRITERION_t) const;
  end-pi;

  // From the raw text, not from the converted number. They are the same for
  // any ordinary port, and they differ in exactly the cases that matter: a
  // value that could not be converted renders as it was written - upstream
  // says PORT:abc, not PORT:0 - and one that %int would silently read part of
  // renders whole, PORT:22,23 rather than PORT:22.
  if criterion.kind = SCDEF_CHECK_PORT;
    return 'PORT:' + %trim(criterion.raw);
  endif;

  // Everything else is a job name to upstream, including the SBS/JOB slash
  // form and the PGM- prefix - there is no PGM: rendering. Built from raw
  // rather than the split-out fields so those forms survive intact, and
  // upper-cased because upstream folds the criterion as it parses it.
  return 'JOBNAME:' + STRING_upper(%trim(criterion.raw));

end-proc;

//==============================================================================
// criterion_type
//   The type a check_alive value names, or blank if it names a value
//
// Upstream accepts PORT and JOBNAME, matched without regard to case. Nothing
// else is a type: 'pgm' and 'process' both come back blank and are read as
// job names, which is what sc 1.7.1 does with them.
//==============================================================================

dcl-proc criterion_type;
  dcl-pi *n like(SCDEF_KIND_t);
    value like(SCDEF_CRIT_t) const;
  end-pi;

  dcl-s work like(SCDEF_CRIT_t);

  work = STRING_upper(%trim(value));

  select;
    when work = 'PORT';
      return SCDEF_CHECK_PORT;
    when work = 'JOBNAME';
      return SCDEF_CHECK_JOB;
    other;
      return *blanks;
  endsl;

end-proc;

//==============================================================================
// usable_port
//   Can this text be used as a port number?
//
// Upstream's complaint - "Invalid data for port number or job name criteria" -
// is the wording of a parse failure, and sc is Java, so the rule is what
// Integer.parseInt accepts: optionally signed digits, nothing else.
//
// Deliberately NOT a range check. 0, -1 and 65536 all parse, so upstream
// accepts them and reports the service NOT RUNNING; refusing them here would
// be a worse parity defect than the crash this replaces. The only departure
// is a value too wide for the field, which is refused rather than truncated -
// silently turning 4294967296 into something else is a wrong answer with no
// error, which is the fault being fixed.
//==============================================================================

dcl-proc usable_port;
  dcl-pi *n like(BOOLEAN_t);
    value like(SCDEF_CRIT_t) const;
  end-pi;

  dcl-s work like(SCDEF_CRIT_t);
  dcl-s i    like(INTEGER_t);
  dcl-s from like(INTEGER_t) inz(1);

  work = %trim(value);
  if %len(work) = 0;
    return false;
  endif;

  if %subst(work: 1: 1) = '-' or %subst(work: 1: 1) = '+';
    from = 2;
  endif;
  if %len(work) < from;
    return false;
  endif;

  for i = from to %len(work);
    if %subst(work: i: 1) < '0' or %subst(work: i: 1) > '9';
      return false;
    endif;
  endfor;

  // Wider than the field can hold. %int would wrap rather than refuse.
  if %len(work) - (from - 1) > 10;
    return false;
  endif;

  monitor;
    if %int(work) = 0;
    endif;
  on-error;
    return false;
  endmon;

  return true;

end-proc;

//==============================================================================
// SCDEF_criterion_usable
//==============================================================================

dcl-proc SCDEF_criterion_usable export;
  dcl-pi *n like(BOOLEAN_t);
    criterion likeds(SCDEF_CRITERION_t) const;
  end-pi;

  if criterion.kind = SCDEF_CHECK_PORT;
    return usable_port(criterion.raw);
  endif;

  return true;

end-proc;
