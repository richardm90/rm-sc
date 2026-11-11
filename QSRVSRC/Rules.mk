# rm-tools modules come in through the RMTOOLS binding directory, which the
# rm-tools submodule (deps/rm-tools) builds into this project's own OBJLIB.
# Its entries are all *MODULE and are therefore bound BY COPY - so RMSC has
# no runtime dependency on any rm-tools library.
# See docs/tobi-binding.md.
RMSC.SRVPGM: RMSC.BND SCYAML.MODULE SCDEF.MODULE SCDIRS.MODULE SCCOLL.MODULE SCQRY.MODULE SCNET.MODULE SCJOB.MODULE SCOUT.MODULE SCLAUNCH.MODULE SCLOG.MODULE SCEXEC.MODULE SCMAIN.MODULE SCAPI.MODULE \
             RMTOOLS.BNDDIR
RMSC.SRVPGM: TEXT = RMSC: Service Commander procedures
# QC2LE supplies the C runtime SCOUT uses for isatty and printf. A module's
# own ctl-opt bnddir is honoured by CRTBNDRPG but not by CRTSRVPGM, so it has
# to be named here.
RMSC.SRVPGM: BNDDIR = RMTOOLS QC2LE
