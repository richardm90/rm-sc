**free

//==============================================================================
// SCLAUNCH.TEST - Service launch test suite
//
// Environment assembly and the start command are tested directly, without
// launching anything. Both are worth pinning: an environment that drops $PORT
// breaks any service reading it, and a start command that does not fully
// detach would keep RMSC running for as long as the service does.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt nomain;
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCLAUNCH_D.rpgleinc'
/include 'SCDEF_D.rpgleinc'
/include 'SCYAML_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'
/include 'include/PSDS_D.rpgleinc'
/include QINCLUDE,TESTCASE

dcl-s g_dir like(STMF_t);

dcl-pr aEqualV;
  expected  varchar(512) const;
  actual    varchar(512) const;
  fieldName varchar(500) const;
end-pr;

dcl-pr load_def like(BOOLEAN_t);
  name    like(STMF_t) const;
  content like(STRING_t) const;
  def     likeds(SCDEF_t);
end-pr;

dcl-pr env_has like(BOOLEAN_t);
  env   likeds(SCLAUNCH_ENV_t) const;
  entry like(SCDEF_ENVVAR_t) const;
end-pr;

dcl-pr remove_fixtures end-pr;

// Derived-job-name block - see THE DERIVED JOB NAME STILL TRUNCATES at the
// foot of this suite
dcl-pr jn_lc varchar(2048);
  tag varchar(16) const;
  len like(INTEGER_t) const;
end-pr;

//==============================================================================
// Suite set-up and tear-down
//==============================================================================

dcl-proc setUpSuite export;

  g_dir = '/tmp/rmsc-sclaunch-test-' + %trim(psds.current_user);
  IFS_crtdir(g_dir);

end-proc;

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
  IFS_dltdir(g_dir);
  assert((not IFS_isa_directory(g_dir)):
         'Fixture directory ' + %trim(g_dir) + ' not removed');

end-proc;

//==============================================================================
// Helpers
//==============================================================================

//------------------------------------------------------------------------------
// A MESSAGE PARAMETER IS A HOLDER TOO, and this one was 64 wide until
// 7 September 2026 - the same defect as the subject of the width block below,
// in the text that reports it.
//
// MEASURED on this box the same day, with a throwaway suite: a 120-character
// value passed to a `varchar(64) const` parameter arrives 64 long, silently,
// and `opdesc` on the prototype does not change that; passed to a
// `varchar(200) const` it arrives whole. So every message longer than the
// parameter had its reasoning cut mid-word, and the cases where that hurt most
// were the ones whose failure text is meant to explain itself.
//
// 500 IS SIZED TO WHAT CAN REACH IT: the longest message written in these
// suites today is 271 characters, and iRPGUnit's own `assert` takes
// `msgIfFalse varchar(16384)`, so nothing downstream cuts what this carries.
//
// BUT iEqual, nEqual AND aEqual CANNOT BE FIXED HERE. Their third parameter is
// declared `fieldName varchar(64)` in iRPGUnit's own TESTCASE copybook, with
// no *varsize, so a longer message is cut at 64 at the call site and no width
// chosen in this repository can change it. Where one of those carries the
// reasoning, THE POINT MUST FIT IN THE FIRST 64 CHARACTERS. Where it will not
// fit, use assert() or one of the helpers here instead.
//------------------------------------------------------------------------------
dcl-proc aEqualV;
  dcl-pi *n;
    expected varchar(512) const;
    actual   varchar(512) const;
    fieldName varchar(500) const;
  end-pi;

  assert((%trimr(expected) = %trimr(actual)):
         %trim(fieldName) + ': expected "' + %trim(expected) +
         '" but was "' + %trim(actual) + '"');

end-proc;

dcl-proc load_def;
  dcl-pi *n like(BOOLEAN_t);
    name    like(STMF_t) const;
    content like(STRING_t) const;
    def     likeds(SCDEF_t);
  end-pi;

  dcl-s path   like(STMF_t);
  dcl-s handle like(INTEGER_t);

  path = %trim(g_dir) + '/' + %trim(name);
  handle = IFS_open_file(path: IFS_OPEN_TYPE_WRITE);
  assert((handle >= 0): 'Could not create ' + %trim(path) +
                        ' - ' + %trim(IFS_error_text()));
  IFS_write_utf8(handle: content);
  IFS_close_file(handle);

  return SCDEF_load(path: def);

end-proc;

dcl-proc env_has;
  dcl-pi *n like(BOOLEAN_t);
    env   likeds(SCLAUNCH_ENV_t) const;
    entry like(SCDEF_ENVVAR_t) const;
  end-pi;

  dcl-s i like(INTEGER_t);

  for i = 1 to env.count;
    if %trimr(env.entry(i)) = %trimr(entry);
      return true;
    endif;
  endfor;

  return false;

end-proc;

//==============================================================================
// A single port criterion publishes PORT and PORT_PLUS_1..8
//==============================================================================

dcl-proc test_port_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('webproxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/webproxy.log': env);

  nEqual(true: env_has(env: 'PORT=8080'): 'PORT');
  nEqual(true: env_has(env: 'PORT_PLUS_1=8081'): 'PORT_PLUS_1');
  nEqual(true: env_has(env: 'PORT_PLUS_8=8088'): 'PORT_PLUS_8');

end-proc;

//==============================================================================
// Two ports make PORT ambiguous, so it is not published
//==============================================================================

dcl-proc test_no_port_when_ambiguous export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);
  dcl-s  i   like(INTEGER_t);
  dcl-s  found like(BOOLEAN_t) inz(false);

  assert(load_def('twoports.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080,8081' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  for i = 1 to env.count;
    if %len(env.entry(i)) >= 5
       and %subst(env.entry(i): 1: 5) = 'PORT=';
      found = true;
    endif;
  endfor;

  nEqual(false: found: 'no PORT when two ports are declared');

end-proc;

//==============================================================================
// A job-name criterion is not a port, so PORT is not published
//==============================================================================

dcl-proc test_no_port_for_job_criterion export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);
  dcl-s  i   like(INTEGER_t);
  dcl-s  found like(BOOLEAN_t) inz(false);

  assert(load_def('jobonly.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: WEBPROXY' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  for i = 1 to env.count;
    if %len(env.entry(i)) >= 5
       and %subst(env.entry(i): 1: 5) = 'PORT=';
      found = true;
    endif;
  endfor;

  nEqual(false: found: 'no PORT for a job-name criterion');

end-proc;

//==============================================================================
// The SCOMMANDER_ metadata upstream exposes
//==============================================================================

dcl-proc test_scommander_metadata export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('meta.yaml':
    'name: Web Proxy' + LF +
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/meta.log': env);

  nEqual(true: env_has(env: 'SCOMMANDER_LOGFILE=/tmp/meta.log'): 'logfile');
  nEqual(true: env_has(env: 'SCOMMANDER_NAME=meta'): 'short name');
  nEqual(true: env_has(env: 'SCOMMANDER_FRIENDLY_NAME=Web Proxy'): 'friendly name');
  nEqual(true: env_has(env: 'SCOMMANDER_DEFINED_AT=' + %trim(g_dir) +
                            '/meta.yaml'): 'defined at');

end-proc;

//==============================================================================
// A service's own variables are carried through verbatim
//==============================================================================

dcl-proc test_service_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('vars.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- PATH=/QOpenSys/pkgs/bin:/usr/bin' + LF +
    '- LOGLEVEL=debug' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  nEqual(true: env_has(env: 'PATH=/QOpenSys/pkgs/bin:/usr/bin'):
         'colons in a value are preserved');
  nEqual(true: env_has(env: 'LOGLEVEL=debug'): 'second variable');

end-proc;

//==============================================================================
// Variables that describe RMSC's own environment are not passed on
//==============================================================================

dcl-proc test_blocked_variables export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-ds env likeds(SCLAUNCH_ENV_t) inz(*likeds);

  assert(load_def('blocked.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF +
    'environment_vars:' + LF +
    '- SHELL=/QOpenSys/pkgs/bin/bash' + LF +
    '- SSH_CLIENT=10.0.0.1 22' + LF +
    '- JAVA_HOME=/QOpenSys/pkgs/lib/jvm' + LF +
    '- LOGLEVEL=debug' + LF: def): 'load');

  SCLAUNCH_build_env(def: '/tmp/x.log': env);

  nEqual(false: env_has(env: 'SHELL=/QOpenSys/pkgs/bin/bash'): 'SHELL dropped');
  nEqual(false: env_has(env: 'SSH_CLIENT=10.0.0.1 22'):
         'SSH_ prefix dropped');
  nEqual(false: env_has(env: 'JAVA_HOME=/QOpenSys/pkgs/lib/jvm'):
         'JAVA_HOME dropped');
  nEqual(true: env_has(env: 'LOGLEVEL=debug'): 'others kept');

end-proc;

//==============================================================================
// The start command detaches
//
// This is the assertion that matters most in this module. Without every part
// of it, RMSC would block for the lifetime of the service it just started.
//==============================================================================

dcl-proc test_start_command_detaches export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd like(SCLAUNCH_CMD_t);

  assert(load_def('detach.yaml':
    'start_cmd: /usr/bin/webproxy --serve' + LF +
    'check_alive: 8080' + LF: def): 'load');

  cmd = SCLAUNCH_start_command(def: '/tmp/detach.log');

  assert((%scan('nohup ': cmd) > 0): 'nohup, so a hangup does not kill it');
  assert((%scan('2>&1': cmd) > 0): 'stderr redirected');
  assert((%scan('< /dev/null': cmd) > 0):
         'stdin detached, or the child holds the caller pipe open');
  aEqualV('&': %subst(cmd: %len(cmd): 1):
          'backgrounded, so the caller returns instead of waiting');
  assert((%scan('/usr/bin/webproxy --serve': cmd) > 0):
         'the command itself is intact');

end-proc;

//==============================================================================
// The start command runs in the service's working directory
//==============================================================================

dcl-proc test_start_command_working_directory export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  cmd like(SCLAUNCH_CMD_t);

  assert(load_def('wd.yaml':
    'start_cmd: ./webproxy' + LF +
    'check_alive: 8080' + LF +
    'dir: /QOpenSys/opt/webproxy' + LF: def): 'load');

  cmd = SCLAUNCH_start_command(def: '/tmp/x.log');

  assert((%scan('cd ''/QOpenSys/opt/webproxy''': cmd) > 0):
         'changes to the working directory first');

end-proc;

//==============================================================================
// Shell quoting
//==============================================================================

dcl-proc test_quoting export;

  aEqualV('''plain''': SCLAUNCH_quote('plain'): 'simple value');
  aEqualV('''has space''': SCLAUNCH_quote('has space'): 'value with a space');
  assert((%scan('\''': SCLAUNCH_quote('it''s')) > 0):
         'an embedded single quote is escaped');

end-proc;

//==============================================================================
// Batch job name derivation
//==============================================================================

dcl-proc test_job_name_from_service export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('web-proxy.yaml':
    'start_cmd: /usr/bin/webproxy' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqualV('WEBPROXY': SCLAUNCH_job_name(def):
          'non-alphanumerics removed, upper-cased');

end-proc;

dcl-proc test_job_name_truncated export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('a-very-long-service-name.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF: def): 'load');

  aEqualV('AVERYLONGS': SCLAUNCH_job_name(def): 'truncated to ten');

end-proc;

dcl-proc test_job_name_explicit export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('explicit.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF +
    'sbmjob_jobname: WEBPROXY' + LF: def): 'load');

  aEqualV('WEBPROXY': SCLAUNCH_job_name(def): 'sbmjob_jobname wins');

end-proc;

//##############################################################################
//##                                                                          ##
//##  THE DERIVED JOB NAME STILL TRUNCATES - and must keep doing so           ##
//##                                                                          ##
//##############################################################################
//
// There are TWO paths to a batch job name and only one of them is changing:
//
//   sbmjob_jobname GIVEN     the author chose it   -> refused if over 10,
//                                                     because an IBM i job name
//                                                     cannot be longer and a
//                                                     stored one would never
//                                                     work. Pinned in
//                                                     SCDEF.TEST.
//   sbmjob_jobname ABSENT    RMSC derives one      -> CUT TO 10, on purpose.
//                                                     Nobody chose that name,
//                                                     so cutting it to fit is
//                                                     the right answer.
//
// THIS BLOCK IS THE CONTROL FOR THE SECOND PATH, and it matters more than the
// refusals it accompanies. The cheapest wrong fix for "a job name over 10 is
// invalid" is one applied wherever a job name is formed - which would refuse
// every service whose own name is longer than ten characters, that is to say
// most of them. Every rejection case in SCDEF.TEST passes against that fix.
// Only these do not.
//
// test_job_name_truncated above already covers a 24-character service name.
// These two go past the widths this round of work is moving - 64, and the 250
// a file name can now carry - because the derived name is built from the SHORT
// NAME, and the short name is the field being widened.
//
// THE TWO ARE NOT BOTH CONTROLS, and it is worth saying which is which because
// the second was WRITTEN as a control and measurement said otherwise:
//
//   100 characters   GREEN throughout. The short name was cut at 64 while
//                    RMSC's own holder was 64 wide, but the first ten
//                    characters survive that, so the derived job name is the
//                    same either way. This is the control - it must stay
//                    green, and it is what a refusal applied to the derived
//                    path as well as the given one would break.
//
//   250 characters   Measured in SCDEF.TEST on 5 September 2026: past 127
//                    characters the short name did not arrive short, it
//                    arrived EMPTY, because PATH_BASENAME_t in rmtools was
//                    varchar(128) and the '.yaml' did not survive its cut. So
//                    there was no name to derive from, SCLAUNCH fell back to a
//                    constant, and the job name that came out was 'SCSERVICE'.
//                    Every service with a file name of 128 characters or more
//                    would have submitted under that one shared name, and stop
//                    and check would have gone looking for it.
//
// THE SECOND WAS BLOCKED ON rmtools AND WAS WRITTEN AS A MARKER: it asserted
// the constant that really came out, in the idiom
// tools/error-delivery-test.sh calls `pinned`, so that tools/verify.sh was not
// left reporting FAILED every run until another repository shipped, and so
// that it would go red the day the fix arrived and say in its own text what to
// change it to.
//
// It did. rmtools 2.0.7, released 7 September 2026, widened PATH_BASENAME_t to
// varchar(255) and replaced the MONITOR with a `pos > 0` guard, the short name
// arrives whole, and the case below is the real expectation it was standing in
// for - RMSCJNA250, derived from the name the file actually has.
//
// IT IS STILL THE ONLY THING IN THIS REPOSITORY that observes what the short
// name does to the job that actually gets SUBMITTED rather than to what is
// stored, which is why it is worth keeping now that it asserts something
// rather than nothing.
//
// THE DERIVATION RULE ITSELF IS NOT CHANGING - confirmed by the project owner:
// the first ten alphanumeric characters of the upper-cased name. Every fixture
// here is lower-case alphanumeric with the tag at the front, so the expected
// value is simply the first ten characters upper-cased.
//
// EVERY CHARACTER OF THE FIXTURE IS LOWER-CASE ALPHANUMERIC, so the derivation
// has nothing to strip and the expected value is simply the first ten
// characters, upper-cased. That keeps these cases about LENGTH: if they used a
// name with hyphens in it they would also be asserting where the stripping
// happens relative to the cut, which is a different rule and is already
// covered by test_job_name_from_service.
//##############################################################################

//------------------------------------------------------------------------------
// jn_lc - lower-case alphanumeric filler of exactly LEN characters, tag first
//------------------------------------------------------------------------------
dcl-proc jn_lc;
  dcl-pi *n varchar(2048);
    tag varchar(16) const;
    len like(INTEGER_t) const;
  end-pi;

  dcl-c LCFILL const('abcdefghijklmnopqrstuvwxyz0123456789');
  dcl-s v varchar(2100);

  v = 'rmscjn' + %trimr(tag);

  dow %len(v) < len;
    v += LCFILL;
  enddo;

  return %subst(v: 1: len);

end-proc;

dcl-proc test_job_name_derived_from_a_long_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);

  nm = jn_lc('a100': 100);
  iEqual(100: %len(nm): 'a service name of 100 characters');

  assert(load_def(nm + '.yaml':
    'start_cmd: /usr/bin/rmscjn' + LF +
    'check_alive: 8080' + LF: def):
    'no sbmjob_jobname, so the job name is derived - and a long SERVICE ' +
    'name must not make the definition invalid');

  aEqualV('RMSCJNA100': SCLAUNCH_job_name(def):
          'the derived name is the first ten characters, upper-cased - ' +
          'truncation is CORRECT on this path and must keep working');

end-proc;

dcl-proc test_job_name_derived_from_the_longest_name export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);
  dcl-s  nm  varchar(2048);

  nm = jn_lc('a250': 250);
  iEqual(250: %len(nm): 'the longest base name a .yaml file can carry');

  assert(load_def(nm + '.yaml':
    'start_cmd: /usr/bin/rmscjn' + LF +
    'check_alive: 8080' + LF: def):
    'the longest service name the IFS will hold still loads - it was the ' +
    'NAME that used to be lost, not the definition');

  aEqualV('RMSCJNA250': SCLAUNCH_job_name(def):
          'the derived name comes from the REAL short name, cut to ten. ' +
          'While PATH_BASENAME_t was varchar(128) this service and every ' +
          'other one named past 127 characters submitted under the ' +
          'constant SCSERVICE, all of them sharing one job name that stop ' +
          'and check would then look for');

end-proc;

//==============================================================================
// AN EXPLICIT JOB NAME WITH LEADING BLANKS SUBMITS UNDER THE NAME IN THE FILE
//
// The other half of test_sbmjob_jobname_quoted_10_stored_8_trimmed_is_accepted
// in SCDEF.TEST. That suite can see what was STORED; this one can see what
// would be SUBMITTED, and the two together are the assertion that matters:
// what the author wrote reaches SBMJOB whole.
//
// A double-quoted scalar keeps its interior blanks, so "  ABCDEFGH" is ten
// characters stored and eight after trimming. Ten fits, so the definition is
// valid and the job name is ABCDEFGH.
//
// GREEN TODAY, and it is a control rather than a driver. It is here so that the
// fix to the guard in SCDEF - measure what is stored, not what is trimmed -
// cannot be made by refusing every value with a blank in it. A refusal there
// makes this case red, and nothing else in either suite would notice.
//==============================================================================

dcl-proc test_job_name_explicit_with_leading_blanks export;

  dcl-ds def likeds(SCDEF_t) inz(*likeds);

  assert(load_def('explicitblank.yaml':
    'start_cmd: /usr/bin/x' + LF +
    'check_alive: 8080' + LF +
    'sbmjob_jobname: "  ABCDEFGH"' + LF: def):
    'ten characters are stored and ten characters fit, so this definition ' +
    'is valid - if it is refused, the job-name guard is reading the ' +
    'spelling of the value rather than its length');

  aEqualV('ABCDEFGH': SCLAUNCH_job_name(def):
          'and the job is submitted under the name the file asks for - not ' +
          'under a prefix of it, and not under one derived from the service ' +
          'name as though no sbmjob_jobname had been given');

end-proc;
