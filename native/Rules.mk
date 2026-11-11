# rmsc_fork_helper is PASE-only native code, not an ILE object - f_fork400()
# cannot be called from RPGLE or ILE C, both of which run in the ILE/MI
# machine environment rather than PASE. See docs/tobi-binding.md for why
# this directory exists and how it differs from everything else TOBi
# builds here.
#
# TOBi's own parser requires a custom-recipe target's NAME to carry a real,
# recognized object-type suffix - MEASURED: a target named with a made-up
# suffix (e.g. ".rebuild") is rejected outright ("Warning: Target '...' is
# not supported").
#
# The target is a *DTAARA, and the recipe really creates it: after the
# compile it recreates <OBJLIB>/RMSCFORK, holding the deployed binary's
# path. That object is what make compares the prerequisites' timestamps
# against, so the helper is rebuilt only when rmsc_fork_helper.c or
# SCLAUNCH_D changes. (This target used to be RMSC_FORK_HELPER.SRVPGM,
# naming an object nothing created, so TOBi never found it and the recipe
# ran on every `makei build`.) Consequence: deleting the binary alone does
# not trigger a rebuild - delete the data area as well (DLTDTAARA
# DTAARA(<OBJLIB>/RMSCFORK)), or touch rmsc_fork_helper.c.
#
# NOT listed as a prerequisite of RMSC.SRVPGM or anything else: `makei
# build`'s own top-level `all` target already reaches every object TOBi's
# parser recorded, across every SUBDIRS directory. (When this target was a
# .SRVPGM, listing it also made TOBi add it to CRTSRVPGM's BNDSRVPGM() -
# MEASURED - which failed, since it was never a real *SRVPGM.)
#
# The deploy path - /QOpenSys/opt/rm-sc/<release>/bin/rmsc_fork_helper - is
# read from SCLAUNCH_FORK_HELPER in QPROTOSRC/SCLAUNCH_D.RPGLEINC, the one
# place the release number is written, so the path RMSC calls and the path
# the helper is deployed to can never disagree. It is read in the recipe
# itself because a plain Rules.mk variable does not survive into a custom
# recipe's command line (MEASURED - it expands to empty); TOBi's own
# $(OBJLIB) does. The recipe is one shell command (joined with \) so the
# path, held in a shell variable, is still set on every step.
#
# The recipe names its files only through $< and $(lastword $^), never
# literally: a custom recipe's commands run from the project root, not from
# this directory, and TOBi rewrites the prerequisites relative to that root
# (MEASURED).
#
# The recipe creates the <release>/bin directories, but NOT
# /QOpenSys/opt/rm-sc itself - creating that is a one-time installation
# step for a privileged profile (an ordinary build profile cannot create
# entries under /QOpenSys), which also makes it writable by the build
# profile's group; see README.md "Installation". A missing or unwritable
# directory fails the build loudly, which is the point.
#
# makei build's own "Build Successful!" banner can be wrong when a custom
# recipe's command fails (MEASURED in rm-tools) - check the command output.
# A failed step stops the recipe before the data area is recreated, so the
# next build retries.
RMSCFORK.DTAARA: rmsc_fork_helper.c SCLAUNCH_D.RPGLEINC
	P=$$(sed -n "s/^dcl-c SCLAUNCH_FORK_HELPER const('\(.*\)');.*$$/\1/p" "$(lastword $^)") && \
	test -n "$$P" && \
	mkdir -p "$${P%/rmsc_fork_helper}" && \
	/QOpenSys/pkgs/bin/cc -o "$$P" "$<" && \
	{ system "DLTDTAARA DTAARA($(OBJLIB)/RMSCFORK)" >/dev/null 2>&1 ; true ; } && \
	system "CRTDTAARA DTAARA($(OBJLIB)/RMSCFORK) TYPE(*CHAR) LEN(64) VALUE('$$P') TEXT('RMSC: rmsc_fork_helper build stamp')"
