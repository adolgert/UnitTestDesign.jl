# Instrument the native ordinary pipeline without changing src/.
# The trial-adapter wrapper adds certification AFTER these measured phases;
# use phase events, not this adapter's total time, for native phase attribution.
struct ProfiledEngine{E}
    inner::E
end
function UnitTestDesign.generate(engine::ProfiledEngine,request::UnitTestDesign.Request)
    U._has_invalid(request.space) && throw(ArgumentError("phase adapter supports ordinary models only"))
    classification=@timed U.classify_targets(request)
    required,excluded=classification.value
    construction=@timed U.cover_ordinary(engine.inner,request,U.RequiredTargets(request,required))
    validation=@timed U.validate_design(request,construction.value,required)
    event("phase";classification_seconds=classification.time,
        engine_seconds=construction.time,validation_seconds=validation.time,
        classification_bytes=classification.bytes,engine_bytes=construction.bytes,
        validation_bytes=validation.bytes)
    record=U.engine_record(engine.inner)
    return U.Design(construction.value,:covering,record.name,record.seed,
        length(required),validation.value,excluded,U.n_must_include(request),(;))
end
register_solver("profile_ipog",ProfiledEngine(IPOG()))
register_solver("profile_gnd",ProfiledEngine(GND(seed=0)))
