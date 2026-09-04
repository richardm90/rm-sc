**free

//==============================================================================
// SCAPIDRV - a caller of the bound-call API, so that its SILENCE can be seen
//
// WHY THIS EXISTS, AND WHY IT IS NOT AN iRPGUnit SUITE.
//
// SCAPI's header promises, verbatim: "Nothing here writes to standard output: a
// green-screen program calling this must not have stray text appear underneath
// its display file, so status is returned rather than printed."
//
// That promise is an ABSENCE, and an absence on a FILE DESCRIPTOR. iRPGUnit
// runs inside the ILE job whose descriptor 1 is the thing under test, and a
// suite cannot capture its own stdout - so no assertion in qtestsrc/*.TEST can
// see whether the promise holds. qtestsrc/SCOUT.TEST.RPGLE can pin the silence
// FLAG's own contract and nothing more; what a caller actually receives on its
// two streams only exists outside the job.
//
// So the observation has to be made from the shell, and the shell has nothing
// to observe: every existing entry point either goes through SCRUN, which is
// the command line and is SUPPOSED to print, or is a procedure no shell can
// call. This program is the missing piece - a caller of SC_start/SC_stop/
// SC_check_all that is CALLable from `system -kpieO`, exactly as scripts/scr
// calls SCRUN, and whose own two streams are therefore the API's two streams.
//
// IT WRITES NOTHING TO STDOUT OR STDERR ITSELF. That is the entire design
// constraint and it is the reason for the result file: if this program reported
// its outcome by printing it, the assertion "the API path printed nothing"
// could not be made, because this program's own report would be there. So the
// outcome goes to an IFS file whose path the caller supplies, and the two
// streams are left pristine for tools/api-silence-test.sh to assert about.
//
// It stands in for the green-screen program in SCAPI's header. That program has
// a display file where this has a result file, and the question asked of both
// is the same one: after the call returns, is there anything on the screen that
// the program did not put there.
//
// PARAMETERS COME FROM THE ENVIRONMENT, NOT FROM CL.
//
//   SCAPIDRV_OP     check-all | start | stop | restart | kill | leak-probe
//                   | leak-sweep
//   SCAPIDRV_SVC    the service or group the operation acts on
//   SCAPIDRV_OUT    IFS path to write the outcome to
//
// and, for leak-sweep only, because that one operation needs a fixture of each
// SHAPE rather than one service:
//
//   SCAPIDRV_GRP    a group at least one staged service belongs to
//   SCAPIDRV_NOGRP  a group name NO staged service belongs to
//
// scripts/scr documents the trap this avoids: "CL CALL passes a character
// literal at its own length, not at the length the program declares. A short
// literal into a char(1024) parameter leaves the program reading whatever
// happens to follow it in memory." That is survivable for one parameter that a
// wrapper pads; it is three chances to get it wrong here. The environment is
// already proven to reach an ILE job through `system -kpieO` - it is how
// SC_SERVICES_DIR reaches SCDIRS in tools/narration-test.sh - so it is used
// instead, and no padding rule has to be remembered in two places.
//
// getenv comes from the C runtime rather than from RMTOOLS deliberately: this
// program is built by a shell script with CRTBNDRPG rather than by TOBi, and
// the fewer copybooks it needs the fewer ways that build can break for a reason
// that has nothing to do with what it is testing.
//
// THE RESULT FILE, one key=value per line, so a shell can grep it:
//
//   op=<the operation asked for>
//   svc=<the service asked for>
//   rc=<0 when the call returned true, 1 when it returned false>
//   msg=<the message the API returned, or rows=<n> for check-all>
//
// and leak-sweep adds, before those, one line per step plus the reading it
// takes before it has called anything at all:
//
//   silent_before=<0|1>
//   sweep<n>=<label>|rc=<0|1>|silent=<0|1>|msg=<what the call returned>
//
// `rc` and `msg` are what make the silence assertion mean something. An absence
// is satisfied by a program that did nothing at all, so the harness reads this
// file to confirm the operation was actually attempted and actually reached a
// verdict before it believes the empty streams. tools/api-silence-test.sh says
// so at greater length.
//
// 03/09/2026 - RM - created
//==============================================================================

ctl-opt dftactgrp(*no) actgrp(*new);
ctl-opt bnddir('RMSCPGM':'RMSCDEPS');

/include 'SCAPI_D.rpgleinc'
/include 'SCOUT_D.rpgleinc'
/include 'include/RMLIST_D.rpgleinc'
/include 'include/RMIFS_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

// The marker the leak probe writes. Long, and not a word any RMSC message
// contains, so a harness grepping for it cannot match something else that
// happened to be printed.
dcl-c LEAK_MARKER const('SCAPIDRV-STILL-SPEAKING');

// THE SWEEP MARKERS, ONE PER RETURN OUT OF THE PRIVATE FUNNEL.
//
// SCAPI's four public operations - SC_start, SC_stop, SC_kill, SC_restart -
// all go through one private procedure, and that procedure returns from FOUR
// places: a group nothing matched, a group that ran, an unknown single
// service, and a single service that ran. Each of those returns has to put the
// silence flag back, and if one of them does not then everything AFTER it in
// the activation is mute.
//
// One marker per shape is what makes that legible. A single marker at the end
// would go missing for any of the four and say nothing about which; with one
// after each call, the FIRST missing marker names the return that leaked.
//
// NO MARKER IS A PREFIX OF ANOTHER - they separate at the step digit - so a
// harness may match them whole or by substring and get the same answer either
// way. SWEEP-0 is written BEFORE any API call: it is the control, and its
// absence means SCOUT could not write at all in this job rather than that
// silence escaped.
dcl-c SWEEP_0 const('SCAPIDRV-SWEEP-0-BEFORE-ANY-CALL');
dcl-c SWEEP_1 const('SCAPIDRV-SWEEP-1-GROUP-NO-MEMBER');
dcl-c SWEEP_2 const('SCAPIDRV-SWEEP-2-GROUP-RAN');
dcl-c SWEEP_3 const('SCAPIDRV-SWEEP-3-UNKNOWN-SERVICE');
dcl-c SWEEP_4 const('SCAPIDRV-SWEEP-4-SINGLE-RAN');
dcl-c SWEEP_5 const('SCAPIDRV-SWEEP-5-NESTED-RESTART');
dcl-c SWEEP_6 const('SCAPIDRV-SWEEP-6-KILL');
dcl-c SWEEP_7 const('SCAPIDRV-SWEEP-7-CHECK-ALL');

// A name nothing will ever be called. The unknown-service step needs no
// fixture - being absent IS the fixture - so it is a literal here rather than
// one more environment variable the harness has to keep in step.
dcl-c SWEEP_UNKNOWN const('zzscapidrv_no_such_service');

dcl-pr getenv pointer extproc('getenv');
  name pointer value options(*string);
end-pr;

dcl-pr env_text varchar(512);
  name varchar(64) const;
end-pr;

dcl-s op    varchar(32);
dcl-s svc   varchar(128);
dcl-s grp   varchar(128);
dcl-s nogrp varchar(128);
dcl-s outp like(STMF_t);
dcl-s msg  like(SC_MSG_t);
dcl-s ok   like(BOOLEAN_t);
dcl-s text like(STRING_t);
dcl-s hdl  like(INTEGER_t);

dcl-ds lst likeds(LIST_t) inz(*likeds);

// What leak-sweep accumulates for the result file. It is NOT printed as it
// goes: the markers are the only thing this program is allowed to put on a
// stream, so everything else waits for the file at the end.
dcl-s g_sweep like(STRING_t) inz('');
dcl-s g_step  like(INTEGER_t) inz(0);

dcl-pr sweep_step;
  label varchar(64) const;
  ok    like(BOOLEAN_t) const;
  mark  varchar(64) const;
  msg   varchar(512) const;
end-pr;

dcl-pr bool_text varchar(1);
  b like(BOOLEAN_t) const;
end-pr;

//------------------------------------------------------------------------------
// Read what to do
//------------------------------------------------------------------------------

op    = env_text('SCAPIDRV_OP');
svc   = env_text('SCAPIDRV_SVC');
outp  = env_text('SCAPIDRV_OUT');
grp   = env_text('SCAPIDRV_GRP');
nogrp = env_text('SCAPIDRV_NOGRP');

msg = *blanks;
ok  = false;

//------------------------------------------------------------------------------
// Do it
//
// EVERY BRANCH SETS msg. check-all returns a list rather than a message, so it
// reports the row count in the same field - which is what lets the harness
// prove that the call did something without the harness needing to know which
// operation it asked for.
//------------------------------------------------------------------------------

select;
  when op = 'check-all';
    lst = SC_check_all();
    ok  = (lst.num_rows > 0);
    msg = 'rows=' + %char(lst.num_rows);

  when op = 'start';
    ok = SC_start(svc: msg);

  when op = 'stop';
    ok = SC_stop(svc: msg);

  when op = 'restart';
    ok = SC_restart(svc: msg);

  when op = 'kill';
    ok = SC_kill(svc: msg);

  // THE MODULE-STATE PROBE. Make an API call, then ask SCOUT to write a line
  // the way any other consumer of the service program would.
  //
  // The silence flag is MODULE state, so it lives for the whole activation and
  // not for the call. If SCAPI switches it on and never switches it back, then
  // everything that shares the activation is silenced too - and it is silenced
  // invisibly, because nothing returns an error and nothing appears. This
  // operation is the one shape of program that can tell: an API call followed
  // by a write that has every right to be seen.
  //
  // The marker is written LAST and unconditionally, so its absence means the
  // write was suppressed rather than that this branch was never reached - the
  // result file says the branch ran.
  when op = 'leak-probe';
    lst = SC_check_all();
    ok  = (lst.num_rows > 0);
    msg = 'rows=' + %char(lst.num_rows);
    SCOUT_writeln(LEAK_MARKER);

  // THE SWEEP. One activation, every return out of SCAPI's private funnel,
  // and a marker after each.
  //
  // WHAT leak-probe ABOVE COULD NOT SEE, and the reason this exists. That
  // operation calls SC_check_all, which reaches the loader and nothing else -
  // it never enters the funnel the four public operations share. So the four
  // places that have to put the silence flag back were covered by no assertion
  // at all: any one of them could be deleted and every suite in this project
  // would stay green.
  //
  // THE ORDER IS CHOSEN SO EACH STEP REACHES A DIFFERENT RETURN, and so that
  // the ones needing a live service come after the step that starts it:
  //
  //   1  group:<nogrp>   a group operation where NO MEMBER MATCHED. Being
  //                      absent is the whole fixture - no definition claims
  //                      this group - so it costs nothing to stage
  //   2  group:<grp>     a group operation that RAN. Starts whatever the
  //                      staged group holds, which is what leaves a live
  //                      service for the steps below
  //   3  <no such name>  an UNKNOWN SINGLE SERVICE, refused by name
  //   4  <svc>           a SINGLE SERVICE THAT RAN, and succeeded
  //   5  restart <svc>   the same funnel entered while it is already inside
  //                      itself. A restore that assigns *off rather than
  //                      putting the SAVED value back is correct for every
  //                      step above and wrong here, and this is the only step
  //                      that can tell
  //   6  kill <svc>      a fourth verb through the same funnel, and it leaves
  //                      the fixture down for the harness
  //   7  check_all       the loader path, which is what leak-probe covers.
  //                      Kept so that one run answers both questions
  //
  // EVERY STEP RECORDS SCOUT_silent() AFTER ITS CALL as well as writing its
  // marker. The marker is what a real consumer would see and is the assertion
  // that matters; the flag reading names the defect directly - "the flag was
  // still ON when step N returned" - so a red says which return leaked rather
  // than only that something after it went quiet.
  when op = 'leak-sweep';
    // BEFORE ANYTHING. tools/api-silence-test.sh records under "WHAT THIS
    // SCRIPT CANNOT ASSERT" that the flag's value in a FRESH activation was
    // out of reach, because every other observation is made after a call has
    // already run. This is the reading it asked for: SCOUT_silent() in a job
    // that has not yet entered SCAPI.
    g_sweep = 'silent_before=' + bool_text(SCOUT_silent()) + LF;
    SCOUT_writeln(SWEEP_0);

    ok = SC_start('group:' + %trim(nogrp): msg);
    sweep_step('group-no-member': ok: SWEEP_1: msg);

    ok = SC_start('group:' + %trim(grp): msg);
    sweep_step('group-ran': ok: SWEEP_2: msg);

    ok = SC_start(SWEEP_UNKNOWN: msg);
    sweep_step('unknown-single': ok: SWEEP_3: msg);

    ok = SC_start(svc: msg);
    sweep_step('single-ran': ok: SWEEP_4: msg);

    ok = SC_restart(svc: msg);
    sweep_step('nested-restart': ok: SWEEP_5: msg);

    ok = SC_kill(svc: msg);
    sweep_step('kill': ok: SWEEP_6: msg);

    lst = SC_check_all();
    ok  = (lst.num_rows > 0);
    sweep_step('check-all': ok: SWEEP_7: 'rows=' + %char(lst.num_rows));

    // The operation as a whole succeeded when every step reached a verdict.
    // The individual verdicts are in the sweep lines; this is only so the
    // common result-file shape stays the same for every operation.
    ok  = true;
    msg = 'steps=' + %char(g_step);

  other;
    msg = 'SCAPIDRV: unknown operation';
endsl;

//------------------------------------------------------------------------------
// Report it - to the file, never to a stream
//------------------------------------------------------------------------------

text = 'op=' + %trim(op) + LF
     + 'svc=' + %trim(svc) + LF
     + g_sweep;

if ok;
  text += 'rc=0' + LF;
else;
  text += 'rc=1' + LF;
endif;

text += 'msg=' + %trimr(msg) + LF;

// A path that cannot be opened is NOT reported on a stream. It would be the one
// thing this program printed, and it would print it exactly when the harness
// was failing for some other reason - so the harness is left to notice the
// missing file, which it does, rather than being handed a line that would break
// the assertion it is making.
if %len(%trim(outp)) > 0;
  hdl = IFS_open_file(outp: IFS_OPEN_TYPE_WRITE);
  if hdl >= 0;
    IFS_write_utf8(hdl: text);
    IFS_close_file(hdl);
  endif;
endif;

*inlr = *on;
return;

//==============================================================================
// sweep_step - record one step of the sweep, then write its marker
//
// THE ORDER INSIDE HERE IS THE WHOLE POINT. SCOUT_silent() is read FIRST, while
// nothing has touched the flag since the call returned, and the marker is
// written SECOND. Writing the marker first would be a write through the very
// mechanism under test, and if it were suppressed the reading that followed
// would still be taken - so the two observations would no longer be
// independent.
//==============================================================================

dcl-proc sweep_step;
  dcl-pi *n;
    label varchar(64) const;
    ok    like(BOOLEAN_t) const;
    mark  varchar(64) const;
    msg   varchar(512) const;
  end-pi;

  dcl-s still like(BOOLEAN_t);

  still  = SCOUT_silent();
  g_step += 1;

  g_sweep += 'sweep' + %char(g_step) + '=' + %trim(label)
           + '|rc=' + bool_text(not ok)
           + '|silent=' + bool_text(still)
           + '|msg=' + %trimr(msg) + LF;

  SCOUT_writeln(mark);

end-proc;

//==============================================================================
// bool_text - '1' for true, '0' for false, so a shell can compare it
//==============================================================================

dcl-proc bool_text;
  dcl-pi *n varchar(1);
    b like(BOOLEAN_t) const;
  end-pi;

  if b;
    return '1';
  endif;
  return '0';

end-proc;

//==============================================================================
// env_text - one environment variable as text, blank when it is not set
//==============================================================================

dcl-proc env_text;
  dcl-pi *n varchar(512);
    name varchar(64) const;
  end-pi;

  dcl-s p pointer;

  p = getenv(%trim(name));
  if p = *null;
    return '';
  endif;

  return %str(p);

end-proc;
