SC.CMD: SC.CMD SCCMD.PGM
# CMD_PGM, not PGM. TOBi's CRTCMD recipe reads CMD_PGM and defaults it to the
# command's own name, so a 'PGM=' line is silently ignored and the command is
# created pointing at a program that does not exist - which then fails without
# printing anything, because the failure is a command-not-found on the CPP.
SC.CMD: CMD_PGM = SCCMD
SC.CMD: TEXT = RMSC: Service Commander
