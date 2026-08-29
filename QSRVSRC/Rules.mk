# Phase 0 spike: prove cross-library bind-by-copy of an rmtools module.
#
# TOBi builds MODULE() only from .MODULE prerequisites in the target line, so
# naming an out-of-project module there is not possible - it would try to build
# it. BNDDIR is a supported per-target variable, and RMSCDEPS holds *MODULE
# entries, which the binder brings in BY COPY.
SCPING.SRVPGM: SCPING.BND SCPING.MODULE RMSCDEPS.BNDDIR
SCPING.SRVPGM: TEXT = RMSC: Phase 0 build spike
SCPING.SRVPGM: BNDDIR = RMSCDEPS
