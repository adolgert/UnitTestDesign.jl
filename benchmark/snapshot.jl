# A before/after snapshot of generation, measurement and follow-up results
# (design/20260928_secondary_plan.md, "The before/after snapshot"). Stages C,
# D and E2 promise that figures, rows and order do not move; the benchmark
# fingerprint sees only unconstrained IPOG, so this script prints a fixed
# corpus as text instead. For each case: a header line; every field of the
# result, one per line, with `repr`; and the result's `show` text. A call
# that throws prints the exception's type and message instead.
#
# Run it at a stage's base commit, in a git worktree, and at the stage's head,
# then compare the two outputs. Manifest.toml is not tracked, so copy it into
# the worktree (or run `Pkg.instantiate()` there):
#
#     git worktree add --detach ../base <base-commit>
#     cp Manifest.toml ../base/
#     julia --project=../base benchmark/snapshot.jl > base.txt
#     julia --project=. benchmark/snapshot.jl > head.txt
#     diff base.txt head.txt
#
# The invariant holds when the diff is empty. The script uses only the public
# API and reads only the fields the docstrings list, so the same file runs
# against both commits; a field that a commit lacks, such as `Followup.proofs`
# before Stage E1, is not printed there. Nothing machine-dependent is printed:
# no timings, object ids or file paths, and two runs print the same bytes. It
# takes about two minutes and prints about 35 MB.
#
# The corpus, each part at the default limits and at tight ones:
#
# - Generation: `covering` at strengths 1 to 3 with the default engine
#   (IPOG() until decision D1 made it Auto()), with IPOG() and GND (fixed
#   seeds) named, `excursions` and `full_factorial`, on spaces with tabulated and
#   lazy rules, whole-case rules, partitions, `Invalid` values, `stronger`
#   groups that hold an invalid parameter, and ordinary and negative
#   must-include rows (groups and must-include rows at strengths 1 and 2);
#   and positional calls. One space has lazy and tabulated rules, their
#   scopes out of parameter order, active in negative rows' sub-requests. In
#   another, a negative row's engine reaches a tight `feasibility_limit` after
#   every classification succeeds, and at a tighter one so does a later
#   invalid value's classification.
# - Measurement: `coverage`, `missing_interactions`, `report` and
#   `design_sizes` on those results, and `coverage` on hand-written rows with
#   repeats, rejected rows and rows with two `Invalid` values, written as
#   named tuples, tuples and vectors. Two spaces are built so that sharing an
#   answer cache between measurements would change a figure.
# - Follow-ups: `diagnose` and `followups` on the spaces of probe 04
#   (design/components_review_probes/04_proof_union.jl), on outcomes drawn with
#   fixed seeds for the spaces of the random sweep in test/test_diagnose.jl, and
#   on generated results.
#
# The random spaces come from a small generator here, with fixed seeds, rather
# than from test/random_problems.jl, which needs the test oracle loaded and
# makes no `Invalid` values, whole-case rules or lazy rules.

using UnitTestDesign
using Random: Xoshiro, randperm
using Base.CoreLogging: with_logger, NullLogger


## Output

"The result records printed field by field; any other value prints with `repr`."
const RECORDS = (:TestCases, :Exclusion, :Coverage, :CoveragePart, :Report, :DesignSizes,
                 :Diagnosis, :Suspect, :Followup, :FollowupProof)

"The records that define their own one-line `show`, printed beside their fields."
const ONE_LINE = (:TestCases, :Exclusion, :Coverage, :CoveragePart, :Report, :DesignSizes,
                  :Diagnosis, :Followup)

"The small records, printed on one line as a named tuple of their fields."
const SMALL = (:Exclusion, :Suspect, :FollowupProof)

record_name(x) = parentmodule(typeof(x)) === UnitTestDesign ? nameof(typeof(x)) : nothing
isscalar(x) = x isa Union{Number, Symbol, AbstractString, Nothing, Missing}
fields(x) = NamedTuple{fieldnames(typeof(x))}(Tuple(getfield(x, f) for f in fieldnames(typeof(x))))

"""
    emit(path, x)

Print `x` as lines `path = repr`, in a fixed order: a record's fields in
declaration order (a small record's on one line), a vector's elements one
per line unless they are all scalars, and a `TestSpace` as its one-line
summary, since the space is the input.
"""
function emit(path::AbstractString, x)
    name = record_name(x)
    if x isa TestSpace
        println(path, " = ", repr(x))
    elseif name in SMALL
        println(path, " = ", repr(fields(x)), name in ONE_LINE ? " |show| " * sprint(show, x) : "")
    elseif name in RECORDS
        name in ONE_LINE && println(path, " |show| ", sprint(show, x))
        for field in fieldnames(typeof(x))
            emit(string(path, ".", field), getfield(x, field))
        end
    elseif x isa AbstractVector && !all(isscalar, x)
        println(path, " = ", length(x), " elements")
        for (i, element) in enumerate(x)
            emit(string(path, "[", i, "]"), element)
        end
    else
        println(path, " = ", repr(x))
    end
    return nothing
end

"The text a REPL prints for `x`, each line indented behind a bar."
function emit_display(x)
    println("text/plain:")
    for line in split(sprint(show, MIME"text/plain"(), x), '\n')
        println("  | ", line)
    end
    return nothing
end

"""
    run_case(f, label) -> result or nothing

Print a header naming the case, then `f()`'s fields and display, or the
exception it threw: its type and message, only the first line for an
exception the package does not raise on purpose, whose later lines can name
source files.
"""
function run_case(f, label::AbstractString)
    println("== ", label)
    x = try
        f()
    catch err
        text = sprint(showerror, err)
        err isa Union{ArgumentError, ResourceLimitError, ConstraintError} ||
            (text = first(split(text, '\n')))
        println("threw ", nameof(typeof(err)), ": ", text)
        return nothing
    end
    emit("result", x)
    emit_display(x)
    return x
end

"The keywords of a set of limits as the header shows them."
limits_text(limits::NamedTuple) =
    isempty(limits) ? "default limits" : join(("$k = $v" for (k, v) in pairs(limits)), ", ")

const DEFAULT = NamedTuple()
const TIGHT = (feasibility_limit = 2, explanation_limit = 1)
const TIGHT_EXPLANATION = (explanation_limit = 1,)
const LIMITS = [DEFAULT, TIGHT, TIGHT_EXPLANATION]


## Spaces

"A space built without the warning a lazily evaluated rule gives."
quiet_space(domains; kwargs...) = with_logger(() -> TestSpace(domains; kwargs...), NullLogger())

"""
    Case

One space and what to ask of it: its domains and rules, the strengths to
generate at, and optional `stronger` groups, must-include rows and an
excursion base. `measured` are the strengths at which hand-written rows are
measured, and a result also one strength above its own. `limits` are the
sets of limits each call runs under, and `sizes` says whether to run
`design_sizes`, which generates every strategy. `enumerated` says whether to
run the calls that read every row of the space, `full_factorial()` and the
hand-written row sets, which print too many rows for a large space.
"""
Base.@kwdef struct Case
    name::String
    domains::NamedTuple
    constraints::Vector = Constraint[]
    tabulation_limit::Int = 10^5
    strengths::Vector{Int} = [1, 2, 3]
    measured::Vector{Int} = [2, 3]
    stronger::Vector = []
    must_include::Vector = []
    from::Any = nothing
    limits::Vector = LIMITS
    sizes::Bool = true
    enumerated::Bool = true
end

space_of(case::Case) =
    quiet_space(case.domains; constraints = case.constraints, tabulation_limit = case.tabulation_limit)

function fixed_cases()
    tiny = Partition(:tiny, Returns(1e-9))
    fable = (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])
    fable_rules = [@require(mode == :exact || solver == :none),
                   forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")]
    fable_must = [(mode = :fast, solver = :none, tol = 1e-3), (mode = :exact,)]
    wide = (a = [1, 2, 3, Invalid(0)], b = [:x, :y, Invalid(:bad)], c = [true, false], d = [1, 2, 3],
            e = [:p, :q])
    wide_rules = [forbid((a = 1, b = :y); reason = "a = 1 excludes y"),
                  forbid(:c, :d) do c, d; c && d == 3 end,
                  forbid(; reason = "whole-case: a = 2, d = 1 and e = :q") do r
                      r.a == 2 && r.d == 1 && r.e == :q
                  end]
    wide_must = [(a = Invalid(0), b = :x), (a = 2, e = :q), (b = Invalid(:bad), c = true, d = 2),
                 (a = 3, b = :x, c = false, d = 1, e = :p)]
    subrequest = (a = [1, 2, 3, Invalid(0)], b = [:x, :y, :z], c = [1, 2, Invalid(-1)], d = [true, false],
                  e = [1, 2, 3])
    subrequest_rules = [forbid(:e, :b) do e, b; e == 3 && b != :x end,
                        forbid(:d, :c) do d, c; d && c == 2 end,
                        forbid(:d, :a) do d, a; !d && a == 2 end,
                        forbid(:e, :d, :b) do e, d, b; e == 3 && d && b == :x end]
    # Probe 08a: (w = 1, v = 1) is excluded directly by rule 1 and by a
    # four-pigeon, three-hole rule set that is slow to prove.
    holes = (:x, :y, :z, :u)
    pigeons = [forbid((w, v, p, q) -> w == 1 && v == 1 && p == q, :w, :v, a, b)
               for (i, a) in enumerate(holes) for b in holes[(i + 1):end]]
    eight = NamedTuple{Tuple(Symbol(:x, i) for i in 1:8)}(Tuple(1:4 for _ in 1:8))
    # Five pigeons, x to w, in four holes when a = b = 5.
    five = (:x, :y, :z, :u, :w)
    crowded = [forbid((a, b, p, q) -> a == 5 && b == 5 && p == q, :a, :b, h, k)
               for (i, h) in enumerate(five) for k in five[(i + 1):end]]
    return [
        Case(name = "fable", domains = fable, constraints = fable_rules, must_include = fable_must,
             from = (mode = :exact, solver = :lu, tol = 1e-6)),
        Case(name = "fable, rules lazy", domains = fable, constraints = fable_rules, tabulation_limit = 1,
             must_include = fable_must, from = (mode = :exact, solver = :lu, tol = 1e-6)),
        Case(name = "negative", domains = (n = [1, 2, Invalid(1)], m = [:a, :b], k = [:x, :y]),
             constraints = [@forbid(n == 2 && m == :b), @forbid(m == :a && k == :y)],
             must_include = [(n = Invalid(1), m = :b), (n = 2,), (n = 1, m = :a, k = :x)],
             from = (n = 2, m = :a, k = :x)),
        Case(name = "negative, five parameters", domains = wide, constraints = wide_rules,
             stronger = [(:a, :b, :c) => 3], must_include = wide_must),
        Case(name = "negative, five parameters, rules lazy", domains = wide, constraints = wide_rules,
             tabulation_limit = 5, stronger = [(:a, :b, :c) => 3], must_include = wide_must,
             sizes = false),
        # Negative sub-requests (Stage D). Every rule's scope is written out of
        # parameter order. The two lazy rules (above tabulation_limit) omit both
        # invalid parameters, so they are active in both sub-requests; of the
        # two tabulated rules, the one that reads `c` is active in `a`'s
        # sub-request and the one that reads `a` in `c`'s. At strength 3 each
        # sub-request has targets its rules forbid or imply. A projection that
        # sorted the scopes, or gave a sub-request other rules or tables, would
        # move rows or exclusions.
        Case(name = "negative sub-requests, scopes out of order", domains = subrequest,
             constraints = subrequest_rules, tabulation_limit = 6,
             stronger = [(:c, :a, :e) => 3, (:b, :d) => 2],
             must_include = [(a = Invalid(0), e = 3), (c = Invalid(-1), a = 3, b = :y, d = false, e = 1),
                             (c = Invalid(-1),), (a = 1, b = :x)],
             from = (a = 1, b = :x, c = 1, d = true, e = 1)),
        Case(name = "partitions", domains = (size = [tiny, 1.0, 100.0], mode = [:a, :b], flag = [true, false]),
             constraints = [forbid((size = :tiny, mode = :b); reason = "tiny needs mode a")],
             must_include = [(size = :tiny,), (size = 100.0, mode = :b, flag = false)],
             from = (size = :tiny, mode = :a, flag = false)),
        Case(name = "implied, one rule lazy", domains = (a = [1, 2, 3], b = [1, 2], c = [1, 2, 3], d = [1, 2]),
             constraints = [forbid(:a, :b) do a, b; a == 1 && b != 2 end,
                            forbid((b = 2, c = 3)),
                            forbid(:a, :c, :d) do a, c, d; a == 3 && c == 1 && d == 2 end],
             tabulation_limit = 6, stronger = [(:a, :c, :d) => 3], must_include = [(a = 1,), (c = 3, d = 1)]),
        Case(name = "whole-case rule and an invalid value", domains = (x = [1, 2, 3], y = [1, 2, 3], z = [:a, :b, Invalid(:z)]),
             constraints = [forbid(; reason = "x + y == 4") do r; r.x + r.y == 4 end, forbid((y = 3, z = :b))],
             must_include = [(z = Invalid(:z), x = 3), (x = 2, y = 1)], from = (x = 1, y = 1, z = :a)),
        Case(name = "one parameter", domains = (p = [1, 2, Invalid(3)],), strengths = [1]),
        Case(name = "pigeonhole, probe 08a",
             domains = (w = [1, 2], v = [1, 2], a = [1, 2], x = 1:3, y = 1:3, z = 1:3, u = 1:3),
             constraints = [forbid((w, v, a) -> w == 1 && v == 1, :w, :v, :a); pigeons],
             strengths = [2], measured = [2],
             limits = [DEFAULT, TIGHT, (feasibility_limit = 6,), (feasibility_limit = 10,),
                                         (feasibility_limit = 14,), (explanation_limit = 3,)],
             sizes = false),
        Case(name = "limit exhaustion, eight parameters", domains = eight,
             constraints = [forbid((xs...) -> !all(==(4), xs), keys(eight)...)], strengths = [2], measured = [2],
             limits = [DEFAULT, (feasibility_limit = 1,)], sizes = false),
        Case(name = "negative targets unresolved",
             domains = (n = [1, Invalid(0)], x1 = 1:4, x2 = 1:4, x3 = 1:4, x4 = 1:4),
             constraints = [forbid(n -> n == 1, :n),
                            forbid((a, b, c, d) -> !(a == b == c == d == 4), :x1, :x2, :x3, :x4)],
             strengths = [2], measured = [2], limits = [DEFAULT, (feasibility_limit = 1,), TIGHT], sizes = false),
        # A negative row's engine at feasibility_limit (Stage D). Both engines
        # place a = 5 beside b = 5 in a negative row at n, and the search that
        # proves (a = 5, b = 5) leaves no valid row, five pigeons in four
        # holes, takes 66 nodes; no pair needs that search. At
        # feasibility_limit = 8 every pair is classified but
        # (m = Invalid(0), e = 2), which takes 26 nodes: the rule on
        # (e, x, y, z) leaves it one completion. n = 1 keeps a from 5 in
        # ordinary rows and in negative rows at m, and m = 1 keeps e from 2 in
        # ordinary rows and in negative rows at n. So at feasibility_limit = 40
        # every classification succeeds and n's engine run fails; at 12, the
        # classification of (m = Invalid(0), e = 2) fails too, after n's
        # engine run in the order of the invalid values and before it in
        # target order.
        Case(name = "negative rows' engine at the limit",
             domains = (n = [1, Invalid(0)], m = [1, Invalid(0)], a = 1:5, b = 1:5, x = 1:4, y = 1:4, z = 1:4,
                        u = 1:4, w = 1:4, e = 1:2),
             constraints = [crowded; forbid((n, a) -> n == 1 && a == 5, :n, :a);
                            forbid((m, e) -> m == 1 && e == 2, :m, :e);
                            forbid((e, x, y, z) -> e == 2 && !(x == y == z == 4), :e, :x, :y, :z)],
             strengths = [2], measured = [2], limits = [DEFAULT, (feasibility_limit = 12,), (feasibility_limit = 40,)],
             sizes = false, enumerated = false),
        # Two components that every search solves, each a few nodes deep: a
        # search that has one component's witness cached resolves at a limit
        # where a fresh search does not. So these figures change if two
        # measurements share an answer cache (decision 7 of the plan): the
        # 4 + 4 report's bonus at feasibility_limit = 4, and the strength-3
        # coverage of no rows at limits 2 to 4.
        Case(name = "two components, four parameters each",
             domains = NamedTuple{Tuple(Symbol(c, i) for c in (:a, :b) for i in 1:4)}(Tuple(1:2 for _ in 1:8)),
             constraints = [forbid((a1 = 1, a2 = 1)), forbid((a3 = 1, a4 = 1)), forbid((a2 = 2, a3 = 2)),
                            forbid((b1 = 1, b2 = 1)), forbid((b3 = 1, b4 = 1)), forbid((b2 = 2, b3 = 2))],
             strengths = [2, 3], limits = [DEFAULT, (feasibility_limit = 2,), (feasibility_limit = 3,),
                                           (feasibility_limit = 4,)]),
        Case(name = "two components, three parameters each",
             domains = NamedTuple{Tuple(Symbol(c, i) for c in (:a, :b) for i in 1:3)}(Tuple(1:3 for _ in 1:6)),
             constraints = [forbid((a1 = 1, a2 = 1)), forbid((a2 = 2, a3 = 2)),
                            forbid((b1 = 1, b2 = 1)), forbid((b2 = 2, b3 = 2))],
             strengths = [2], limits = [DEFAULT, (feasibility_limit = 2,), (feasibility_limit = 3,)]),
    ]
end

"""
    random_case(seed) -> Case

A random space drawn from `Xoshiro(seed)`: 3 to 5 parameters with 2 to 4
values, some with an `Invalid` value; 1 to 3 rules over 2 or 3 parameters,
each forbidding 1 to 4 combinations; sometimes a whole-case rule; sometimes
every rule lazy.
"""
function random_case(seed::Integer)
    rng = Xoshiro(seed)
    n = rand(rng, 3:5)
    names = Tuple(Symbol(:p, i) for i in 1:n)
    sizes = [rand(rng, 2:4) for _ in 1:n]
    domains = Tuple(Any[collect(1:k); rand(rng) < 0.3 ? [Invalid(0)] : []] for k in sizes)
    rules = Constraint[]
    for _ in 1:rand(rng, 1:3)
        scope = sort(randperm(rng, n)[1:rand(rng, 2:min(3, n))])
        forbidden = Set(Tuple(rand(rng, 1:sizes[p]) for p in scope) for _ in 1:rand(rng, 1:4))
        push!(rules, forbid((values...) -> values in forbidden, names[scope]...))
    end
    if rand(rng) < 0.3
        p, q = randperm(rng, n)[1:2]
        vp, vq = rand(rng, 1:sizes[p]), rand(rng, 1:sizes[q])
        push!(rules, forbid(r -> r[names[p]] == vp && r[names[q]] == vq; reason = "whole-case"))
    end
    lazy = rand(rng) < 0.3
    return Case(name = "random $seed", domains = NamedTuple{names}(domains), constraints = rules,
                tabulation_limit = lazy ? 1 : 10^5, strengths = collect(1:min(3, n)),
                stronger = n >= 4 ? [names[1:4] => 3] : [], sizes = seed % 3 == 0,
                limits = [DEFAULT, (feasibility_limit = 1,), (feasibility_limit = 3,), TIGHT])
end

"Every row of the full product, the first parameter fastest: valid, rejected and multiple-Invalid rows."
product_rows(domains::NamedTuple) =
    [NamedTuple{keys(domains)}(t) for t in vec(collect(Iterators.product(values(domains)...)))]

"""
    written_forms(rows) -> Vector

The rows in the forms a caller may write them, in turn: a `NamedTuple` with
its names reversed, a `Tuple` in parameter order, a `Vector{Any}`, and a
`NamedTuple` with each partition written by its name.
"""
function written_forms(rows)
    return map(enumerate(rows)) do (i, row)
        i % 4 == 1 ? NamedTuple{reverse(keys(row))}(reverse(values(row))) :
        i % 4 == 2 ? Tuple(row) :
        i % 4 == 3 ? collect(Any, row) :
        map(v -> v isa Partition ? v.name : v, row)
    end
end

"""
    hand_written(domains) -> Vector{Pair{String, Vector}}

Row sets as a person might write them: every row of the product (or every
k-th row, for a large product), with rules broken and two `Invalid` values;
a third of those rows, drawn with a fixed seed, in mixed forms and with the
first three repeated; and no rows.
"""
function hand_written(domains::NamedTuple)
    everything = product_rows(domains)
    step = max(1, length(everything) ÷ 150)
    rows = everything[1:step:end]
    sample = rows[sort(randperm(Xoshiro(3), length(rows))[1:cld(length(rows), 3)])]
    return [
        (step == 1 ? "every row of the product" : "every $(step)th row of the product") => rows,
        "a third of them in mixed forms, the first three repeated" =>
            written_forms([sample; sample[1:min(3, end)]]),
        "no rows" => NamedTuple[],
    ]
end


## Generation and measurement

"""
    generators(case, space) -> Vector{Pair{String, Function}}

The generation calls for one space, each a function of the limits.
"""
function generators(case::Case, space::TestSpace)
    n = length(case.domains)
    calls = Pair{String, Function}[]
    for s in case.strengths
        s <= n || continue
        push!(calls, "covering(strength = $s)" => limits -> covering(space; strength = s, limits...))
        push!(calls, "covering(strength = $s, engine = GND(seed = $s))" =>
                     limits -> covering(space; strength = s, engine = GND(seed = s), limits...))
    end
    # At strength 1 a negative row's sub-request exists only for a group that
    # holds its invalid parameter, and has strength 0; without one, a negative
    # must-include row is completed by a witness search instead.
    if !isempty(case.stronger)
        for s in (2, 1), engine in (IPOG(), GND(seed = 7))
            push!(calls, "covering(strength = $s, stronger = $(case.stronger), engine = $engine)" =>
                         limits -> covering(space; strength = s, stronger = case.stronger, engine, limits...))
        end
    end
    if !isempty(case.must_include)
        for s in unique([min(2, n), 1])
            push!(calls, "covering(strength = $s, must_include = $(case.must_include))" =>
                         limits -> covering(space; strength = s, must_include = case.must_include, limits...))
            push!(calls, "covering(strength = $s, must_include, engine = GND(seed = 11))" =>
                         limits -> covering(space; strength = s, must_include = case.must_include,
                                            engine = GND(seed = 11), limits...))
        end
        if !isempty(case.stronger)
            for engine in (IPOG(), GND(seed = 13))
                push!(calls, "covering(strength = 1, stronger, must_include, engine = $engine)" =>
                             limits -> covering(space; strength = 1, stronger = case.stronger,
                                                must_include = case.must_include, engine, limits...))
            end
        end
    end
    for d in 1:2
        push!(calls, "excursions(distance = $d)" => limits -> excursions(space; distance = d, limits...))
    end
    if case.from !== nothing
        push!(calls, "excursions(from = $(case.from), distance = 2, must_include)" =>
                     limits -> excursions(space; from = case.from, distance = 2,
                                          must_include = case.must_include, limits...))
    end
    case.enumerated && push!(calls, "full_factorial()" => limits -> full_factorial(space; limits...))
    isempty(case.must_include) ||
        push!(calls, "full_factorial(must_include)" =>
                     limits -> full_factorial(space; must_include = case.must_include, limits...))
    push!(calls, "full_factorial(limit = 3)" => limits -> full_factorial(space; limit = 3, limits...))
    return calls
end

"""
    measure_result(label, cases, case)

Measure one generated result: `coverage`, `report` and
`missing_interactions` under each set of limits, and at the default limits
also `coverage` one strength higher, when `case.measured` asks for it, and
without the result's `stronger` groups.
"""
function measure_result(label::AbstractString, cases::TestCases, case::Case)
    n = length(parameters(cases.space))
    s = cases.strength == 0 ? min(2, n) : cases.strength
    for limits in case.limits
        tag = limits_text(limits)
        run_case("measure $label | coverage(cases; strength = $s) | $tag") do
            coverage(cases; strength = s, limits...)
        end
        run_case("measure $label | report(cases) | $tag") do
            report(cases; limits...)
        end
        run_case("measure $label | missing_interactions(cases; strength = $s) | $tag") do
            missing_interactions(cases; strength = s, limits...)
        end
    end
    if s < n && s + 1 in case.measured
        run_case("measure $label | coverage(cases; strength = $(s + 1)) | default limits") do
            coverage(cases; strength = s + 1, stronger = [])
        end
    end
    if !isempty(cases.stronger)
        run_case("measure $label | coverage(cases; stronger = []) | default limits") do
            coverage(cases; stronger = [])
        end
    end
    return nothing
end

function generate_and_measure(case::Case)
    space = space_of(case)
    n = length(case.domains)
    println("#### ", case.name, ": ", repr(space))
    for (call, generate) in generators(case, space)
        label = "$(case.name) | $call"
        generated = nothing
        for limits in case.limits
            cases = run_case(() -> generate(limits), "generate $label | $(limits_text(limits))")
            limits === DEFAULT && (generated = cases)
        end
        generated isa TestCases && measure_result(label, generated, case)
    end
    for (description, rows) in (case.enumerated ? hand_written(case.domains) : [])
        for s in unique(min.(case.measured, n)), limits in case.limits
            run_case("measure $(case.name) | coverage($description, space; strength = $s) | " *
                     limits_text(limits)) do
                coverage(rows, space; strength = s, limits...)
            end
        end
        if !isempty(case.stronger)
            for limits in case.limits
                run_case("measure $(case.name) | coverage($description, space; stronger = " *
                         "$(case.stronger)) | $(limits_text(limits))") do
                    coverage(rows, space; stronger = case.stronger, limits...)
                end
            end
        end
        run_case("measure $(case.name) | missing_interactions($description, space) | default limits") do
            missing_interactions(rows, space; strength = min(2, n))
        end
    end
    if case.sizes
        for limits in case.limits
            run_case("measure $(case.name) | design_sizes(space) | $(limits_text(limits))") do
                design_sizes(space; limits...)
            end
        end
    end
    return nothing
end

"Positional calls: the rows are tuples, and `from` and must-include rows may be tuples or vectors."
function positional_calls()
    d = ([1, 2, 3], [:x, :y], [true, false])
    println("#### positional: ", repr(d))
    run_case(() -> all_pairs(d...), "generate positional | all_pairs")
    run_case(() -> covering(d...; strength = 3, must_include = [(1, :y, true), [2, :x, false]]),
             "generate positional | covering(strength = 3, must_include = [(1, :y, true), [2, :x, false]])")
    run_case(() -> excursions(d...; from = (3, :y, false), distance = 2),
             "generate positional | excursions(from = (3, :y, false), distance = 2)")
    run_case(() -> excursions(d...; from = [3, :y, false], distance = 2),
             "generate positional | excursions(from = [3, :y, false], distance = 2)")
    run_case(() -> full_factorial(d...; must_include = [[3, :y, false]]),
             "generate positional | full_factorial(must_include = [[3, :y, false]])")
    rows = [(1, :x, true), [2, :y, false], (1, :x, true), Any[3, :x, false]]
    run_case(() -> coverage(rows, d...), "measure positional | coverage(tuples and vectors)")
    run_case(() -> coverage(rows, d...; strength = 3), "measure positional | coverage(tuples and vectors; strength = 3)")
    return nothing
end


## Follow-ups

"""
    followup_cases(label, rows, passed, space; strengths, limits_list)

`diagnose` at each strength, then `followups` under each set of limits,
starting from the nearest failing case and in domain order.
"""
function followup_cases(label::AbstractString, rows, passed, space; strengths, limits_list)
    for strength in strengths
        d = run_case(() -> diagnose(rows, passed; space, strength), "diagnose $label | strength = $strength")
        d === nothing && continue
        for prefer in (:nearest, :domain), limits in limits_list
            run_case("followups $label | strength = $strength, prefer = $(repr(prefer)) | " *
                     limits_text(limits)) do
                followups(d; prefer, limits...)
            end
        end
    end
    return nothing
end

const FOLLOWUP_LIMITS = [DEFAULT, (explanation_limit = 1,), (explanation_limit = 2,), (feasibility_limit = 1,),
                         (feasibility_limit = 1, explanation_limit = 1)]

"The spaces and outcomes of probe 04 (design/components_review_probes/04_proof_union.jl)."
function probe_04()
    abn = (a = [1, 2], b = [1, 2], n = [1, Invalid(0)])
    rules_a = [forbid(:a, :b; reason = "a = 2 never, whatever b") do a, b; a == 2 end,
               forbid(:a, :n; reason = "a = 2 never with an ordinary n") do a, n; a == 2 end]
    rows_a = [(a = 1, b = 1, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
    rules_b = [forbid((a = 2, b = 2); reason = "a = 2 needs b = 1"),
               forbid(; reason = "whole-case: no a = 2 with b = 2") do c; c.a == 2 && c.b == 2 end]
    rows_b = [(a = 1, b = 2, n = 1), (a = 1, b = 2, n = Invalid(0)), (a = 2, b = 1, n = 1)]
    nb = (n = [1, Invalid(0)], b = [1, 2])
    rows_c = [(n = 1, b = 1), (n = Invalid(0), b = 1), (n = Invalid(0), b = 2)]
    examples = [
        ("A", abn, rules_a, rows_a, [true, true, false], [1]),
        ("A, rule 1 only", abn, rules_a[1:1], rows_a, [true, true, false], [1]),
        ("B", abn, rules_b, rows_b, [true, true, false], [1]),
        ("B reversed", abn, reverse(rules_b), rows_b, [true, true, false], [1]),
        ("B, rule 1 only", abn, rules_b[1:1], rows_b, [true, true, false], [1]),
        ("C", nb, [forbid((n = 1, b = 2))], rows_c, [true, true, false], [1, 2]),
        ("D", abn, rules_b[1:1], rows_b, [true, true, false], [2]),
    ]
    for (name, domains, rules, rows, passed, strengths) in examples
        space = TestSpace(domains; constraints = rules)
        println("#### probe 04 example $name: ", repr(space))
        followup_cases("probe 04 $name", rows, passed, space; strengths, limits_list = FOLLOWUP_LIMITS)
    end
    return nothing
end

"The valid rows of a space by brute force, ordinary rows first, then negative ones."
function valid_rows(domains::NamedTuple, space::TestSpace)
    rows = filter(row -> isallowed(space, row), product_rows(domains))
    return [filter(!hasinvalid, rows); filter(hasinvalid, rows)]
end

"The spaces of the random sweep in test/test_diagnose.jl, with outcomes drawn from fixed seeds."
function diagnose_sweep()
    sweep = [
        (n = [1, Invalid(0)], b = [1, 2]) => [forbid((n = 1, b = 2))],
        (n = [1, 2, Invalid(-1)], m = [:a, :b, Invalid(:z)], k = [:x, :y]) =>
            [forbid(:n, :k) do n, k; k == :x end, forbid((m = :b, k = :y))],
        (a = [1, 2, Invalid(0)], b = [1, 2], c = [1, 2, Invalid(9)]) =>
            [forbid((a = 1, b = 2)), forbid((a = 2, c = 1)), forbid((b = 1, c = 2))],
    ]
    for (i, (domains, rules)) in enumerate(sweep)
        space = TestSpace(domains; constraints = rules)
        rows = valid_rows(domains, space)
        println("#### diagnose sweep space $i: ", repr(space), "; ", length(rows), " valid rows")
        rng = Xoshiro(20260930 + i)
        for trial in 1:6
            passed = rand(rng, Bool, length(rows))
            followup_cases("sweep space $i, outcomes $trial $(repr(passed))", rows, passed, space;
                           strengths = 1:2, limits_list = [DEFAULT, (feasibility_limit = 1,),
                                                            (explanation_limit = 1,)])
        end
        # The same rows written as tuples and as vectors.
        passed = rand(rng, Bool, length(rows))
        followup_cases("sweep space $i, tuple and vector rows", written_forms(rows), passed, space;
                       strengths = 1:2, limits_list = [DEFAULT])
    end
    return nothing
end

"`diagnose` and `followups` on generated results, one with negative rows."
function diagnose_generated()
    space = TestSpace((n = [1, 2, Invalid(1)], m = [:a, :b], k = [:x, :y]);
                      constraints = [@forbid(n == 2 && m == :b), @forbid(m == :a && k == :y)])
    println("#### diagnose generated: ", repr(space))
    for (name, cases) in ("all_pairs" => all_pairs(space), "full_factorial" => full_factorial(space))
        passed = [!(row.n isa Invalid && row.m == :a) && !(row.n == 2 && row.k == :y) for row in cases]
        d = run_case(() -> diagnose(cases, passed), "diagnose generated $name")
        d === nothing && continue
        for limits in (DEFAULT, (feasibility_limit = 1,))
            run_case(() -> followups(d; limits...), "followups generated $name | $(limits_text(limits))")
        end
    end
    return nothing
end


## The corpus

function main()
    println("# UnitTestDesign before/after snapshot (benchmark/snapshot.jl)")
    for case in [fixed_cases(); [random_case(seed) for seed in 1:12]]
        generate_and_measure(case)
    end
    positional_calls()
    probe_04()
    diagnose_sweep()
    diagnose_generated()
    return nothing
end

main()
