# One isolated job. Driven by run.py; stdout is a flushed JSON event stream.
using UnitTestDesign, JSON, Random
using Combinatorics: combinations
const U = UnitTestDesign
const ADAPTERS = Dict{String,Any}("ipog" => IPOG(), "gnd" => GND(seed=0),
                                  "gnd10" => GND(seed=0, candidates=10))
# Extension file may register engine objects with generate(engine, request), or
# functions (space, keywords) -> TestCases. See README for the complete contract.
register_solver(name, adapter) = (ADAPTERS[name] = adapter)
function event(kind; kw...)
    println(JSON.json(Dict("event" => kind, (string(k)=>v for (k,v) in kw)...)))
    flush(stdout)
end
# Spec fields beyond n × v (arity, forbid, space, model, stronger, adapt) and
# the metrics recorded beside the timings (plan §7.2, §7.3).
include("spaces.jl"); include("model_specs.jl"); include("metrics.jl")

function model(s)
    n, v = s["n"], s["v"]
    names, domains, rules = base_model(s)
    family = s["family"]
    family in ("none","mixed","invalid","partition","scoped","lazy_scoped","whole",
        "pattern","macro","noop_scoped","noop_whole","matching","chain","equality",
        "global_budget","alldifferent","tabulated_scope","lazy_scope") ||
        throw(ArgumentError("unknown benchmark family: $family"))
    if family == "mixed"
        domains = [Any[1:(i == 1 ? v : 2)...] for i in 1:n]
    elseif family == "invalid"
        foreach(d -> push!(d, Invalid(0)), domains)
    elseif family == "partition"
        domains = [Any[Partition(Symbol(:level,k), Returns(k)) for k in 1:v] for _ in 1:n]
    end
    if family in ("scoped", "lazy_scoped", "whole", "pattern", "macro")
        r = family == "pattern" ? forbid((p1=1,p2=1)) :
            family == "macro" ? @forbid(p1 == 1 && p2 == 1) :
            family == "whole" ? forbid(c -> c.p1 == 1 && c.p2 == 1) :
            forbid((a,b)->a==1 && b==1, :p1,:p2)
        push!(rules,r)
    elseif family == "noop_scoped"
        push!(rules,forbid((a,b)->false,:p1,:p2))
    elseif family == "noop_whole"
        push!(rules,forbid(c->false))
    elseif family in ("matching", "chain", "equality")
        for i in (family == "matching" ? (1:2:n-1) : (1:n-1))
            pred = family == "equality" ? ((a,b)->a!=b) : ((a,b)->a==1 && b==1)
            push!(rules,forbid(pred,names[i],names[i+1]))
        end
    elseif family == "global_budget"
        push!(rules,forbid(c -> sum(values(c)) > n + n÷2))
    elseif family in ("tabulated_scope", "lazy_scope")
        n >= 8 && v == 4 || throw(ArgumentError("$family requires n >= 8 and v = 4"))
        push!(rules,forbid((xs...)->sum(xs)>12,names[1:6]...))
    elseif family == "alldifferent"
        for i in 1:n, j in i+1:n
            push!(rules,forbid((a,b)->a==b,names[i],names[j]))
        end
    end
    adapted_must, adapted_stronger = adapt!(s, names, domains, rules)
    space = TestSpace((names[i] => domains[i] for i in 1:n)...;
                      constraints=rules, tabulation_limit=family in ("lazy_scoped","lazy_scope") ? 1 : 100_000)
    stronger = s["usage"] == "stronger" ? [Tuple(names[1:min(6,n)]) => 3] : Pair[]
    extra = [spec_stronger(s, names); adapted_stronger]
    isempty(extra) || (stronger = Pair[stronger; extra])
    must = s["usage"] == "seed" ? [(p1=2,)] : Any[]
    isempty(adapted_must) || (must = Any[must; adapted_must])
    kw = (; strength=s["strength"], stronger, must_include=must,
            feasibility_limit=get(s,"nodes",100_000), explanation_limit=get(s,"explanations",1_000_000))
    return (;space,kw,names,domains)
end

const LAST_REQUEST = Ref{Any}(nothing)
is_builtin(adapter) = adapter isa Union{IPOG,GND}

# Certification of trial adapters is part of the timed operation. Ordinary
# and negative target classification uses the same request as the validator.
# The 0.5 merge replaced the per-target helpers this called (_classify_negative,
# _with_invalid, _negative_request by parameter) with classify_negative_targets.
negative_required(r) = first(U.classify_negative_targets(r))

function certify(adapter_result,r)
    matrix = if adapter_result isa U.Design
        adapter_result.strategy == :covering || throw(ArgumentError("a trial engine must return a covering Design"))
        adapter_result.matrix
    elseif adapter_result isa TestCases
        adapter_result.strategy == :covering || throw(ArgumentError("a trial function must return covering TestCases"))
        rows=[U._positions(r,U.case_indices(r.space,row)) for row in adapter_result]
        isempty(rows) ? zeros(Int,length(r.arity),0) : reduce(hcat,rows)
    else
        throw(ArgumentError("a trial adapter must return Design or TestCases, got $(typeof(adapter_result))"))
    end
    required,_=U.classify_targets(r)
    U.validate_design(r,matrix,required;negative=negative_required(r))
    return adapter_result
end

function generate_cases(adapter, m)
    if adapter isa Function
        x=adapter(m.space,m.kw)
        x isa TestCases || throw(ArgumentError("function adapters must return TestCases"))
        r=U.Request(m.space;m.kw...)
        LAST_REQUEST[]=r
        return certify(x,r)
    end
    r = U.Request(m.space; m.kw...)
    LAST_REQUEST[] = r
    design=U.generate(adapter,r)
    design isa U.Design || throw(ArgumentError("engine adapters must return Design"))
    is_builtin(adapter) || certify(design,r)
    return TestCases(r,design)
end

half_rows(prepared) = collect(prepared)[1:(length(prepared)÷2)]
function generation_model(s,m,prepared)
    if s["usage"] == "upgrade"
        return merge(m,(;kw=merge(m.kw,(;strength=3,must_include=collect(prepared)))))
    elseif s["usage"] == "topup"
        return merge(m,(;kw=merge(m.kw,(;must_include=half_rows(prepared)))))
    end
    return m
end

function measure_rows(rows,m)
    return coverage(rows,m.space;strength=m.kw.strength,stronger=m.kw.stronger,
                    feasibility_limit=m.kw.feasibility_limit,explanation_limit=m.kw.explanation_limit)
end

function operation(s,m,prepared)
    usage = s["usage"]
    adapter = ADAPTERS[s["solver"]]
    if usage == "core"
        adapter isa Function && throw(ArgumentError("function adapters do not support usage=core; register an engine with generate(engine, Request)"))
        r = U.Request(m.space; m.kw...)
        LAST_REQUEST[] = r
        design=U.generate(adapter,r)
        design isa U.Design || throw(ArgumentError("engine adapters must return Design"))
        is_builtin(adapter) || certify(design,r)
        return design
    elseif usage == "named"
        is_builtin(adapter) || throw(ArgumentError("usage=named uses the public API, which accepts only IPOG/GND; use reuse for trial adapters"))
        s["family"] in ("lazy_scope","lazy_scoped") && throw(ArgumentError("usage=named cannot preserve forced-lazy tabulation_limit; use public or reuse"))
        LAST_REQUEST[] = nothing
        return covering(NamedTuple{Tuple(m.names)}(Tuple(m.domains)); constraints=m.space.constraints,engine=adapter,m.kw...)
    elseif usage == "positional"
        is_builtin(adapter) || throw(ArgumentError("usage=positional uses the public API, which accepts only IPOG/GND; use reuse for trial adapters"))
        isempty(m.space.constraints) || throw(ArgumentError("usage=positional cannot preserve the named model's constraints; use named or reuse"))
        LAST_REQUEST[] = nothing
        return covering(m.domains...; engine=adapter,m.kw...)
    elseif usage == "public"
        is_builtin(adapter) || throw(ArgumentError("usage=public accepts only IPOG/GND; use reuse for trial adapters"))
        LAST_REQUEST[] = nothing
        return covering(m.space;engine=adapter,m.kw...)
    elseif usage == "coverage"
        return coverage(prepared)
    elseif usage == "audit_half"
        return measure_rows(half_rows(prepared),m)
    elseif usage == "audit_empty"
        return measure_rows(Any[],m)
    elseif usage in ("upgrade","topup")
        return generate_cases(adapter,generation_model(s,m,prepared))
    elseif usage == "report"
        return report(prepared)
    elseif usage == "collect"
        return collect(prepared)
    elseif usage == "iterate"
        return sum(sum(values(row)) for row in prepared)
    elseif usage == "realize"
        return realize(prepared; rng=Xoshiro(0))
    elseif usage == "export"
        return github_matrix(prepared)
    elseif usage == "factorial"
        LAST_REQUEST[] = nothing
        return full_factorial(m.space;limit=1_000_000)
    elseif usage == "excursion"
        LAST_REQUEST[] = nothing
        return excursions(m.space;distance=2)
    elseif usage == "feasibility"
        f=U.Feasibility([U.ordinary_indices(m.space,i) for i in eachindex(m.names)],m.space.tables;limit=m.kw.feasibility_limit)
        status,witness=U.completable(f,zeros(Int,s["n"]))
        return (;status,witness,stats=f.stats,memo=U.memo_size(f))
    elseif usage in ("reuse","seed","stronger")
        return generate_cases(adapter,m)
    else
        throw(ArgumentError("unknown benchmark usage: $usage"))
    end
end

function exclusion_counts(excluded)
    return Dict("total"=>length(excluded),
        "forbidden"=>count(e->e.status==:forbidden,excluded),
        "implied"=>count(e->e.status==:implied,excluded),
        "minimal_verified"=>count(e->e.minimal==:verified,excluded),
        "minimal_unresolved"=>count(e->e.minimal==:unresolved,excluded),
        "minimal_not_applicable"=>count(e->e.minimal==:not_applicable,excluded))
end

function describe_part(part)
    return Dict("covered"=>part.covered,"feasible"=>part.feasible,
        "missing"=>length(part.missing),"unknown"=>length(part.unknown),
        "rows"=>part.rows,"duplicates"=>part.duplicates,"rejected"=>length(part.rejected),
        "exclusions"=>exclusion_counts(part.excluded))
end

function describe(x)
    if x isa U.Design
        return Dict("cases"=>size(x.matrix,2),"required"=>x.required,"covered"=>x.covered,
                    "excluded"=>length(x.excluded),"exclusions"=>exclusion_counts(x.excluded),
                    "negative_required"=>x.negative_required,"negative_covered"=>x.negative_covered,
                    "negative_exclusions"=>exclusion_counts(x.negative_excluded),"engine_extras"=>engine_extras(x))
    elseif x isa TestCases
        return Dict("cases"=>length(x),"required"=>x.required,"covered"=>x.covered,
                    "excluded"=>length(x.excluded),"exclusions"=>exclusion_counts(x.excluded),
                    "negative_required"=>x.negative_required,"negative_covered"=>x.negative_covered,
                    "negative_exclusions"=>exclusion_counts(x.negative_excluded),"engine_extras"=>engine_extras(x))
    elseif x isa Coverage
        return Dict("covered"=>x.ordinary.covered,"feasible"=>x.ordinary.feasible,
                    "missing"=>length(x.ordinary.missing),"complete"=>iscomplete(x),
                    "ordinary"=>describe_part(x.ordinary),"negative"=>describe_part(x.negative))
    elseif x isa Report
        bonus=Dict(string(k)=>v for (k,v) in pairs(x.bonus))
        bonus["negative"]=Dict(string(k)=>v for (k,v) in pairs(x.bonus.negative))
        return Dict("result_type"=>"Report","cases"=>x.n_cases,"strength"=>x.strength,
                    "complete"=>iscomplete(x.coverage),"ordinary"=>describe_part(x.coverage.ordinary),
                    "negative"=>describe_part(x.coverage.negative),"bonus"=>bonus,
                    "exclusions"=>exclusion_counts(x.excluded),"recorded_exclusions"=>exclusion_counts(x.recorded))
    elseif x isa NamedTuple && haskey(x,:status)
        return Dict("status"=>string(x.status),"nodes"=>x.stats.total_nodes,
                    "rule_checks"=>x.stats.evaluations,"rule_memo"=>x.memo)
    else
        return Dict("result_type"=>string(typeof(x)))
    end
end
function stats()
    r=LAST_REQUEST[]
    r === nothing && return Dict()
    f=r.feasibility
    return Dict("queries"=>f.stats.queries,"nodes"=>f.stats.total_nodes,
        "memo_hits"=>f.stats.memo_hits,"rule_checks"=>f.stats.evaluations,
        "rule_memo"=>U.memo_size(r),"assignment_memo"=>length(f.memo),
        "search_retained_bytes"=>Base.summarysize(f))
end

# Independent exhaustive oracle for modest plain-integer covering jobs.
# Never used on large jobs; its timings are outside the solver measurement.
function verify_seed_rows(rows,m)
    length(rows) >= length(m.kw.must_include) || error("oracle: missing must_include rows")
    for (i,seed) in enumerate(m.kw.must_include)
        for (key,value) in pairs(seed)
            p=key isa Symbol ? findfirst(==(key),m.names) : Int(key)
            p === nothing && error("oracle: seed parameter absent from model")
            U.same_value(rows[i][p],value) || error("oracle: must_include row $i changed")
        end
    end
end

function verify_domains(rows,m)
    for row in rows
        length(row)==length(m.names) || error("oracle: wrong number of parameters")
        all(any(v->U.same_value(row[i],v),m.domains[i]) for i in eachindex(m.names)) ||
            error("oracle: returned value outside its parameter domain")
    end
end

# Invalid or Partition values, which the exhaustive oracle skips, whatever the family:
# named spaces and the `invalid` adaptation hold them too.
wrapped(m) = any(x -> x isa Union{Invalid,Partition}, Iterators.flatten(m.domains))

function oracle(x,m,s)
    x isa Union{U.Design,TestCases} && s["usage"] in
        ("core","reuse","public","named","positional","seed","stronger","upgrade","topup") || return "not_applicable"
    (s["family"] in ("invalid","partition") || wrapped(m)) && return "not_applicable"
    prod(big(length(d)) for d in m.domains) <= 4096 || return "not_run_large"
    n=s["n"]
    rows = x isa U.Design ? [collect(x.matrix[:,j]) for j in axes(x.matrix,2)] : [collect(values(row)) for row in x]
    verify_domains(rows,m)
    verify_seed_rows(rows,m)
    function allowed(row)
        all(m.space.constraints) do rule
            vals=isempty(rule.scope) ? (NamedTuple{Tuple(m.names)}(Tuple(row)),) : Tuple(row[findfirst(==(nm),m.names)] for nm in rule.scope)
            !rule.predicate(vals...)
        end
    end
    all(allowed,rows) || error("oracle: forbidden returned row")
    valid=[collect(row) for row in Iterators.product(m.domains...) if allowed(row)]
    groups=[collect(1:n)=>m.kw.strength; [collect(Int,findfirst(==(nm),m.names) for nm in g)=>t for (g,t) in m.kw.stronger]]
    for (group,t) in groups, support in combinations(group,t)
        expected=Set(Tuple(row[support]) for row in valid)
        observed=Set(Tuple(row[support]) for row in rows)
        expected ⊆ observed || error("oracle: missing interaction")
    end
    return "passed_exhaustive"
end

function verification(x,m,s,prepared)
    target_model=generation_model(s,m,prepared)
    exhaustive=oracle(x,target_model,s)
    public_check="not_applicable"
    if (s["family"] in ("invalid","partition") || wrapped(m)) && length(m.names)<=8
        covering_result=x isa Union{U.Design,TestCases} && x.strategy==:covering
        value=covering_result ? x : prepared
        if value !== nothing
            check_model=covering_result ? target_model : m
            cases = value isa U.Design ? U.to_cases(U.Request(check_model.space;check_model.kw...),value.matrix) : collect(value)
            rows=[collect(values(row)) for row in cases]
            verify_domains(rows,check_model)
            verify_seed_rows(rows,check_model)
            c=measure_rows(cases,check_model)
            iscomplete(c) || error("verification: public coverage incomplete for small wrapped-value model")
            isempty(c.ordinary.rejected) && isempty(c.negative.rejected) ||
                error("verification: public coverage rejected returned rows")
            public_check="passed_public_coverage"
        end
    end
    return Dict("exhaustive"=>exhaustive,"public_coverage"=>public_check)
end

function certification_label(s,adapter)
    s["usage"] in ("reuse","core","seed","stronger","upgrade","topup","public","named","positional") || return "not_applicable"
    return is_builtin(adapter) ? "production validation included in operation timing" :
        "adapter Request/classify/validate certification included in operation timing"
end

function main()
    s=JSON.parsefile(ARGS[1])
    haskey(ADAPTERS,s["solver"]) || throw(ArgumentError("unknown benchmark solver: $(s["solver"])"))
    s["usage"] in ("reuse","core","named","positional","public","coverage","report","collect",
        "iterate","realize","export","factorial","excursion","feasibility","seed","stronger",
        "upgrade","topup","audit_half","audit_empty") || throw(ArgumentError("unknown benchmark usage: $(s["usage"])"))
    get(s,"runs",0) isa Integer && s["runs"]>=1 || throw(ArgumentError("runs must be a positive integer"))
    event("environment";julia=string(VERSION),threads=Threads.nthreads(),cpu=Sys.cpu_info()[1].model,
          total_memory=Sys.total_memory(),free_memory=Sys.free_memory())
    m=nothing
    t=nothing
    for i in 0:s["runs"]
        # Keep only the final model; every construction is a fresh TestSpace.
        m=nothing; t=nothing
        event("stage";name="gc",phase="construct",run=i)
        GC.gc()
        stage=i==0 ? "construct" : "construct_warm"
        event("stage";name=stage,run=i)
        t=@timed model(s)
        m=t.value
        event("stage";name="diagnostics",phase=stage,run=i)
        event("measurement";stage,run=i,seconds=t.time,allocated_bytes=t.bytes,gc_seconds=t.gctime,
              retained_bytes=Base.summarysize(m.space),rules=length(m.space.tables),
              lazy_rules=count(table->table.lazy!==nothing,m.space.tables))
    end
    t=nothing
    prepared=nothing
    if s["usage"] in ("coverage","report","collect","iterate","realize","export",
                       "upgrade","topup","audit_half","audit_empty")
        event("stage";name="prepare")
        preparation_model=s["usage"] == "upgrade" ? merge(m,(;kw=merge(m.kw,(;strength=2,must_include=Any[])))) : m
        t=@timed generate_cases(ADAPTERS[s["solver"]],preparation_model)
        prepared=t.value
        event("stage";name="diagnostics",phase="prepare")
        event("measurement";stage="prepare",seconds=t.time,allocated_bytes=t.bytes,cases=length(prepared),
              result=describe(prepared),search=stats(),
              certification=is_builtin(ADAPTERS[s["solver"]]) ? "production validation included" : "adapter common certification included")
        LAST_REQUEST[]=nothing
        t=nothing
    end
    lastvalue=nothing
    for i in 0:s["runs"]
        LAST_REQUEST[]=nothing
        lastvalue=nothing
        t=nothing
        reset_extras!()
        event("stage";name="gc",phase="operation",run=i)
        GC.gc()
        stage=i==0 ? "cold" : "warm"
        event("stage";name=stage,run=i)
        t=@timed operation(s,m,prepared)
        lastvalue=t.value
        # Timing and allocated bytes exclude summarysize, JSON and oracle.
        event("stage";name="diagnostics",phase=stage,run=i)
        event("measurement";stage,run=i,seconds=t.time,allocated_bytes=t.bytes,gc_seconds=t.gctime,
              retained_bytes=Base.summarysize(lastvalue),result=describe(lastvalue),search=stats(),
              certification=certification_label(s,ADAPTERS[s["solver"]]))
    end
    event("stage";name="diagnostics",phase="bounds")
    event("bounds";bounds=bounds(lastvalue,generation_model(s,m,prepared)))
    event("stage";name="oracle")
    LAST_REQUEST[]=nothing
    t=nothing
    event("done";validation=verification(lastvalue,m,s,prepared))
end
try
    # Load extension methods before entering the benchmark's world age.
    extension_spec=JSON.parsefile(ARGS[1])
    for f in get(extension_spec,"adapters",String[]); include(abspath(f)); end
    Base.invokelatest(main)
catch e
    event("error";type=string(typeof(e)),message=sprint(showerror,e))
    exit(2)
end
