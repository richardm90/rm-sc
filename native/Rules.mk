# rmsc_fork_helper is PASE-only native code, not an ILE object - f_fork400()
# cannot be called from RPGLE or ILE C, both of which run in the ILE/MI
# machine environment rather than PASE. See docs/tobi-binding.md for why
# this directory exists and how it differs from everything else TOBi
# builds here.
#
# TOBi's own parser requires a custom-recipe target's NAME to carry a real,
# recognized object-type suffix - MEASURED: a target named with a made-up
# suffix (e.g. ".rebuild") is rejected outright ("Warning: Target '...' is
# not supported"), even though the skill documentation's own example for an
# externally-built object uses exactly this shape (".SRVPGM", chosen there
# for the same reason - not because a real *SRVPGM object results; nothing
# here calls CRTSRVPGM). No corresponding QSYS object exists for this
# target, so TOBi's own staleness check (looking for the object on the
# library list) never finds one - this target recompiles on every
# `makei build`, which is harmless and fast (a few lines of C), not a
# correctness concern.
#
# NOT listed as a prerequisite of RMSC.SRVPGM or anything else - MEASURED,
# two ways: (1) doing so makes TOBi auto-add it to CRTSRVPGM's BNDSRVPGM()
# parameter, since that's how TOBi derives BNDSRVPGM from any .SRVPGM
# prerequisite (the same mechanism that derives MODULE() from .MODULE
# prerequisites) - and binding to it fails, because it isn't a real
# *SRVPGM. (2) it does not need to be: `makei build`'s own top-level `all`
# target already reaches every object TOBi's parser recorded against a
# recognized suffix, across every SUBDIRS directory, with no other target
# needing to reference it at all.
#
# The deployed path must match SCLAUNCH_FORK_HELPER in
# QRPGLESRC/SCLAUNCH.RPGLE exactly - RMSC calls it by this fixed, absolute
# path at runtime, with no PATH lookup. /QOpenSys/pkgs/lib/rmsc/native/
# itself is NOT created by this build - it is owned by qsys, matching
# upstream's own /QOpenSys/pkgs/lib/sc/native/ (same ownership, same
# drwxr-sr-x/755 shape). A privileged profile creates it once, during
# installation, before the first `makei build` - see docs/tobi-binding.md.
# A missing or unwritable directory here fails the compile loudly and
# clearly (no such file or directory), which is the point: this is an
# installation precondition, not something a regular build should be able
# to silently paper over by creating a system directory itself.
#
# The deploy path is written literally, not as a make variable - MEASURED:
# TOBi's custom-recipe handling does not preserve a plain Rules.mk variable
# reference the way ordinary GNU make would (it expanded to empty).
#
# The source is named with its directory (native/...), not bare - MEASURED:
# a custom recipe's commands run from the project root, not from this
# directory, unlike a generated recipe (which TOBi itself prefixes).
RMSC_FORK_HELPER.SRVPGM: rmsc_fork_helper.c
	/QOpenSys/pkgs/bin/cc -o /QOpenSys/pkgs/lib/rmsc/native/rmsc_fork_helper native/rmsc_fork_helper.c
