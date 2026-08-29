# Copybooks MUST be listed as prerequisites. TOBi only rebuilds when a named
# prerequisite is newer, so a module that lists just its own source will not
# rebuild when a copybook it includes changes - and the build reports
# "Nothing to be done" rather than anything being wrong. The service program
# then keeps the old record layouts while a freshly compiled caller uses the
# new ones, and fields are read at the wrong offsets.
SCYAML.MODULE: SCYAML.RPGLE QPROTOSRC/SCYAML_D.RPGLEINC
SCYAML.MODULE: TEXT = RMSC: YAML reader

SCDEF.MODULE: SCDEF.RPGLE QPROTOSRC/SCDEF_D.RPGLEINC QPROTOSRC/SCYAML_D.RPGLEINC
SCDEF.MODULE: TEXT = RMSC: Service definition model
