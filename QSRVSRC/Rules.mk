# RMTOOLS modules come in through RMSCDEPS, whose entries are all *MODULE and
# are therefore bound BY COPY - so RMSC has no runtime dependency on the
# RMTOOLS library and no job calling it needs RMTOOLS on its library list.
# See docs/tobi-binding.md.
RMSC.SRVPGM: RMSC.BND SCYAML.MODULE SCDEF.MODULE SCDIRS.MODULE SCCOLL.MODULE SCQRY.MODULE SCNET.MODULE SCJOB.MODULE SCOUT.MODULE SCLAUNCH.MODULE SCLOG.MODULE SCEXEC.MODULE SCMAIN.MODULE SCAPI.MODULE \
             RMSCDEPS.BNDDIR
RMSC.SRVPGM: TEXT = RMSC: Service Commander procedures
# QC2LE supplies the C runtime SCOUT uses for isatty and printf. A module's
# own ctl-opt bnddir is honoured by CRTBNDRPG but not by CRTSRVPGM, so it has
# to be named here.
RMSC.SRVPGM: BNDDIR = RMSCDEPS QC2LE
