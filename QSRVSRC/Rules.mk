# RMTOOLS modules come in through RMSCDEPS, whose entries are all *MODULE and
# are therefore bound BY COPY - so RMSC has no runtime dependency on the
# RMTOOLS library and no job calling it needs RMTOOLS on its library list.
# See docs/tobi-binding.md.
RMSC.SRVPGM: RMSC.BND SCYAML.MODULE SCDEF.MODULE SCDIRS.MODULE SCCOLL.MODULE \
             RMSCDEPS.BNDDIR
RMSC.SRVPGM: TEXT = RMSC: Service Commander procedures
RMSC.SRVPGM: BNDDIR = RMSCDEPS
