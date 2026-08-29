**free

//==============================================================================
// SCPINGP    - Phase 0 build spike caller
//
// THROWAWAY. Calls SCPING_upper and sends the result as a completion message,
// so the bind-by-copy claim can be tested at RUN TIME with RMTOOLS absent
// from the library list. Deleted at the start of Phase 1.
//
// 29/08/2026 - RM - created
//==============================================================================

ctl-opt text('RMSC: Phase 0 build spike caller');
ctl-opt dftactgrp(*no) actgrp(*caller);
ctl-opt main(SCPINGP);
ctl-opt bnddir('RMSCPGM');
/include 'include/RMCOMP_H.rpgleinc'

/include 'SCPING_D.rpgleinc'
/include 'include/RMTOOLS_D.rpgleinc'

dcl-proc SCPINGP;
  dcl-pi *n end-pi;

  dcl-pr sndpgmmsg extpgm('QMHSNDPM');
    msgid char(7) const;
    msgfq char(20) const;
    msgdta char(256) const options(*varsize);
    msglen int(10) const;
    msgtype char(10) const;
    cse char(10) const;
    csecnt int(10) const;
    msgkey char(4);
    errcode char(8) options(*varsize);
  end-pr;

  dcl-s text char(256);
  dcl-s key char(4);
  dcl-ds errcode qualified;
    bytprv int(10) inz(0);
    bytavl int(10) inz(0);
  end-ds;

  text = 'SCPING_upper(hello) = ' + SCPING_upper('hello');
  sndpgmmsg('CPF9897':'QCPFMSG   *LIBL     ':text:%len(%trimr(text)):
            '*COMP':'*':0:key:errcode);

end-proc;
