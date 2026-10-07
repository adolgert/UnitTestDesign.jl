# Instrument the native ordinary pipeline without changing src/: the three
# phases `_generate` runs for an ordinary request, each timed on the objects
# production uses. Classification is `_Classified`, which walks the request's
# layout and keeps a count per support and the excluded targets' ids (no
# required target is listed, plan §5.6); the engine covers its targets
# (`classified.targets`); validation is the certifier's recount on the layout
# against the same targets. Before Phase 5 these were `classify_targets`, a
# `RequiredTargets` built from its list and the list recount, which production
# no longer runs (review p5-integration 2).
# The trial-adapter wrapper adds certification AFTER these measured phases;
# use phase events, not this adapter's total time, for native phase attribution.
struct ProfiledEngine{E}
    inner::E
end
function UnitTestDesign.generate(engine::ProfiledEngine,request::UnitTestDesign.Request)
    U._has_invalid(request.space) && throw(ArgumentError("phase adapter supports ordinary models only"))
    classification=@timed U._Classified(request)
    classified=classification.value
    construction=@timed U.cover_ordinary(engine.inner,request,classified.targets)
    validation=@timed U.validate_design(request,construction.value,classified.targets)
    event("phase";classification_seconds=classification.time,
        engine_seconds=construction.time,validation_seconds=validation.time,
        classification_bytes=classification.bytes,engine_bytes=construction.bytes,
        validation_bytes=validation.bytes)
    record=U.engine_record(engine.inner)
    return U.Design(construction.value,:covering,record.name,record.seed,
        U.nrequired(classified.targets),validation.value,classified.excluded,U.n_must_include(request),(;))
end
register_solver("profile_ipog",ProfiledEngine(IPOG()))
register_solver("profile_gnd",ProfiledEngine(GND(seed=0)))
