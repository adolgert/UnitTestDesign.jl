using Test
using TestItemRunner

# Guards on the type stability of the feasibility search's hot paths: a rule
# check (`forbids(f, k, partial)`, and `_violates` over every table) that finds
# its verdict in a tabulated table or in the memo allocates nothing, and the
# one dynamic call a check may make, a lazy rule's evaluation on a memo miss,
# lands in code that allocates nothing beyond what the predicate allocates,
# when the domains' element types are concrete. The search's entry points
# infer concrete return types. Translating to the caller's vocabulary reads
# values with their domains' types: a result's rows behind one barrier, and a
# measurement's listed targets through one reading per support. Allocation
# counts differ between Julia versions, so these tests assert zero only where
# zero is the design, and bound the rest between the counts before and after
# the change they guard, measured on Julia 1.10 and 1.13.

@testsnippet StabilitySetup begin
    using UnitTestDesign: Feasibility, forbids, _violates, _candidates
    using Base.CoreLogging: with_logger, NullLogger
    using Profile: Allocs    # not `Profile`, which the items import from UnitTestDesign

    # Every domain has a concrete element type and no predicate allocates, so
    # a check allocates nothing anywhere. With tabulation_limit = 12, rule 1
    # (9 combinations) is tabulated, rule 2 (18) is lazy, and rule 3 is a
    # whole-case rule, always lazy.
    stability_space() = with_logger(NullLogger()) do
        TestSpace((a = [1, 2, 3], b = [:x, :y, :z], c = [true, false], d = 1:3, e = [:p, :q]);
            constraints = [forbid((a = 1, b = :y)),
                           forbid((a, d, e) -> a == 2 && d == 1 && e == :q, :a, :d, :e),
                           forbid(row -> row.a == 3 && row.e == :p)],
            tabulation_limit = 12)
    end

    "Bytes allocated by `g(args...)`, after a first call has compiled it and filled any memo."
    function allocated(g, args...)
        g(args...)
        return @allocated g(args...)
    end

    """
    Bytes `f(x)` asks for: the sizes of all its allocations, as the allocation
    profiler records each one, after a first call has compiled it. For guards
    on builders of large arrays. From Julia 1.11.5 and 1.12 (JuliaLang/julia
    #55223), `@allocated` counts a large array at the size of the block the C
    allocator hands back, and on macOS that can be a larger block freed
    earlier, so its reading depends on what ran before: the Lemma 3.5 build
    read from 4.79 to 6.53 times its result, in the same items run again,
    while asking for the same bytes every time. What a call asks for depends
    only on the call, apart from a few bytes a finalizer run during it may
    ask for. One argument and no varargs (see the targets-interface item).
    """
    function requested(f, x)
        f(x)
        Allocs.clear()
        Allocs.@profile sample_rate = 1 f(x)
        bytes = sum(a -> a.size, Allocs.fetch().allocs; init = 0)
        Allocs.clear()
        return bytes
    end
end


@testitem "stability: a rule check allocates nothing" setup=[StabilitySetup] begin
    space = stability_space()
    @test space.tables[1].lazy === nothing
    @test space.tables[2].lazy !== nothing && length(space.tables[3].scope) == 5
    f = Feasibility(_candidates(space, 0, 0), space.tables)
    key = [2, 1, 1, 2, 2]   # (a = 2, b = :x, c = true, d = 2, e = :q): no rule forbids it
    # A tabulated table, then a scoped lazy one and a whole-case one, whose
    # verdicts the second call reads from the memo.
    @test allocated(forbids, f, 1, key) == 0
    @test allocated(forbids, f, 2, key) == 0
    @test allocated(forbids, f, 3, key) == 0
    # The direct check reads every table.
    @test allocated(_violates, f, key) == 0
    @test !_violates(f, key) && f.stats.evaluations > 0
end


@testitem "stability: a lazy rule's evaluation allocates only what its predicate does" setup=[StabilitySetup] begin
    # A memo miss calls the table's `lazy` function: for a space's rule, a
    # `_LazyRule`, whose evaluation is concrete when the domains' element
    # types are. These predicates allocate nothing, so neither does the
    # evaluation.
    space = stability_space()
    scoped, whole = space.tables[2].lazy, space.tables[3].lazy
    @test allocated(scoped, [2, 1, 2]) == 0
    @test allocated(whole, [3, 1, 1, 2, 1]) == 0
    @test scoped([2, 1, 2]) && !scoped([2, 2, 2]) && whole([3, 1, 1, 2, 1])
end


@testitem "stability: the search's entry points infer their return types" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, TargetList, IndexExplanation, dead, explain_partial, _status, _completable
    space = stability_space()
    request = Request(space; strength = 2)
    f = request.feasibility
    key = [2, 0, 0, 1, 0]
    @test (@inferred forbids(f, 1, [1, 2, 0, 0, 0])) isa Bool
    @test (@inferred forbids(f, 3, [3, 1, 1, 1, 1])) isa Bool
    @test (@inferred _violates(f, key)) isa Bool
    @test (@inferred dead(f, key)) isa Bool
    @test (@inferred dead(request, [1, 0, 0, 0, 0])) isa Bool
    @test (@inferred _status(f, key)) isa Symbol
    @test (@inferred explain_partial(f, key)) isa IndexExplanation
    @test (@inferred Union{Tuple{Symbol, Vector{Int}}, Tuple{Symbol, Nothing}} _completable(f, key, 100)) isa Tuple
    @test (@inferred TargetList(request)[3]) isa Vector{Int}
end


@testitem "stability: a result's rows are read with their domains' types" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, TestCases, generate_full_factorial, row_type, _cases, _pick
    # Eight domains of eight types, more than a tuple built by ntuple or map
    # is inferred for.
    space = TestSpace((a = 1:4, b = [:w, :x, :y, :z], c = [true, false], d = [1.0, 2.0, 3.0],
                       e = ["p", "q", "r"], f = Int32[1, 2, 3, 4], g = ['a', 'b'], h = UInt8[1, 2]);
                      constraints = [forbid((a = 1, b = :y)), forbid((c, d) -> c && d == 2.0, :c, :d)])
    domains = (space.values...,)
    @test (@inferred _pick(domains, (2, 1, 1, 3, 2, 4, 1, 2))) === (2, :w, true, 3.0, "q", Int32(4), 'a', 0x02)
    request = Request(space)
    design = generate_full_factorial(request)
    n = size(design.matrix, 2)
    T = row_type(space, false)
    # The rows take their vector and nothing more.
    @test allocated(_cases, T, domains, request.candidates, design.matrix) <=
          allocated(k -> Vector{T}(undef, k), n) + 1024
    # The result takes about 55 bytes a row; reading each row with
    # from_indices took 1.3 KB.
    @test allocated(TestCases, request, design) <= 2 * sizeof(T) * n
    # A full factorial takes about 470 bytes a row, generation included; 1.9 KB before.
    @test allocated(full_factorial, space) <= 1000 * n
end


@testitem "stability: a measurement names a support's targets with one reading" setup=[StabilitySetup] begin
    using UnitTestDesign: _Named, _values, from_indices
    space = stability_space()
    t = [2, 0, 1, 0, 2]
    named = _Named(space, [1, 3, 5])
    @test named(t) === from_indices(space, t) === (a = 2, c = true, e = :q)
    @test (@inferred _values(named, t)) === (2, true, :q)
    # A measurement holds the _Named of a support as an abstract type, so
    # naming a target is one dynamic call, which allocates the NamedTuple:
    # 64 bytes, where from_indices took 544.
    @test allocated(n -> n[](t), Ref{Any}(named)) <= 128
    # coverage of no rows lists every target as missing: about 780 bytes a
    # target on Julia 1.13 and 930 on 1.10, where naming each with
    # from_indices took 1.2 KB and 1.5 KB.
    wide = TestSpace(NamedTuple{Tuple(Symbol(:x, i) for i in 1:8)}(Tuple(1:4 for _ in 1:8)))
    listed = length(coverage(NamedTuple[], wide; strength = 2).ordinary.missing)
    @test listed == 28 * 16
    @test allocated(s -> coverage(NamedTuple[], s; strength = 2), wide) <= 1100 * listed
end



@testitem "stability: a row is read with one lookup per value" setup=[StabilitySetup] begin
    using UnitTestDesign: value_index, case_indices, _row_indices
    # Eight types, more than inference splits a loop over the row's fields into.
    space = TestSpace((a = 1:4, b = [:w, :x, :y, :z], c = [true, false], d = [1.0, 2.0, 3.0],
                       e = ["p", "q", "r"], f = Int32[1, 2, 3, 4], g = ['a', 'b'], h = UInt8[1, 2]))
    row = (a = 2, b = :x, c = false, d = 2.0, e = "q", f = Int32(3), g = 'b', h = 0x01)
    @test (@inferred value_index(space, 5, "q")) == 2
    @test (@inferred case_indices(space, row)) == [2, 2, 2, 2, 2, 3, 2, 1]
    # Reading a row allocates its index vector, 128 bytes, and nothing per
    # value. Before, case_indices took 608 bytes for this row, and
    # _row_indices 736 to 1104.
    vector = allocated(n -> zeros(Int, n), 8)
    @test allocated(case_indices, space, row) <= vector
    @test allocated(case_indices, space, Tuple(row)) <= vector
    @test allocated((s, r) -> _row_indices(s, r; what = "row", complete = true), space, row) <= vector
    @test allocated((s, r) -> _row_indices(s, r; what = "row", complete = true), space, Tuple(row)) <= vector
end


@testitem "stability: an excursion steps an odometer over each change set" setup=[StabilitySetup] begin
    using UnitTestDesign: build_excursion
    arity, base = fill(5, 14), ones(Int, 14)
    ex = @inferred build_excursion(arity, 2, base, Returns(false))
    n = size(ex.matrix, 2)
    @test n == 1 + 14 * 4 + 91 * 16
    # It allocates each row, the list of them and the matrix, and per change
    # set a few small vectors: about 27 bytes a row beyond rows and matrix.
    # Iterating a product of a tuple of runtime length took 263.
    rows = allocated(k -> [ones(Int, 14) for _ in 1:k], n)
    matrix = allocated(k -> zeros(Int, 14, k), n)
    @test allocated(build_excursion, arity, 2, base, Returns(false)) <= rows + matrix + 64 * n
end


@testitem "stability: the targets interface answers in place, and a profile lists no target" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, RequiredTargets, Profile, TargetList, classify_targets, supports,
                          ncombinations, isrequired, nrequired, engine_record, fit, _engine_for, Fit, EngineRecord,
                          _Classified, _required_bits
    # The engine protocol (plan §4.2): an engine reads its targets through
    # `supports`, `ncombinations`, `isrequired` and `nrequired` in its inner
    # loops, so each infers its type and a pass over every combination of
    # every support allocates nothing, for a constrained request's list and
    # for an unconstrained one's TargetList.
    "The required combinations, counted through the interface."
    function count_required(t)
        c = 0
        for s in eachindex(supports(t)), code in 0:(ncombinations(t, s) - 1)
            c += isrequired(t, s, code)
        end
        return c
    end
    # One argument and no varargs: Julia 1.10 doesn't specialize `allocated`'s
    # varargs here and boxes the Int that `count_required` returns.
    measured(f, x) = (f(x); @allocated f(x))
    constrained = Request(stability_space(); strength = 2, stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3])
    free = Request(TestSpace((a = 1:3, b = 1:2, c = 1:4, d = 1:5)); strength = 3)
    for request in (constrained, free)
        required, _ = classify_targets(request)
        t = @inferred RequiredTargets(request, required)
        @test count_required(t) == length(required) == nrequired(t)
        @test measured(count_required, t) == 0
        @test (@inferred isrequired(t, 1, 0)) isa Bool
        @test (@inferred nrequired(t, 1)) isa Int
        @test (@inferred ncombinations(t, 2)) isa Int
        @test (@inferred supports(t)) isa Vector{Vector{Int}}
    end
    @test RequiredTargets(free, first(classify_targets(free))) isa RequiredTargets{TargetList}
    # Classification's targets (`_Classified`, the maintainer's follow-up 3)
    # build their bits the first time `isrequired` asks; from then on it
    # infers and a pass over every combination allocates nothing, as above.
    for request in (constrained, free)
        classified = @inferred Union{_Classified{TargetList}, _Classified{Nothing}} _Classified(request)
        t = classified.targets
        @test t.bits === nothing
        @test (@inferred isrequired(t, 1, 0)) isa Bool
        @test (@inferred _required_bits(t)) isa BitVector
        @test count_required(t) == nrequired(t) && measured(count_required, t) == 0
    end
    # They are counted from the ids of what classification excluded, on the
    # layout it walked, so nothing is rebuilt and no bit is marked: on 40
    # binary parameters at strength 3 with one rule, 78,964 targets required
    # and 76 excluded on 9,880 supports, the targets ask for their counts
    # alone, 8 bytes a support and 120 more (79,160 bytes on Julia 1.13),
    # where from the list alone they ask for 1.9 MB (2.2 MB on 1.10), the
    # layout and a bit for every combination.
    forty = Request(TestSpace([Symbol(:p, i) for i in 1:40], [1:2 for _ in 1:40],
                              [forbid((a, b) -> a == 1 && b == 1, :p1, :p2)], 10^5); strength = 3)
    list = TargetList(forty)
    ids = _Classified(forty).targets.excluded
    @test length(list.supports) == 9_880 && length(ids) == 76
    @test requested(x -> RequiredTargets(x...), (list, ids)) <= 8 * 9_880 + 1024
    # A profile is computed from the parameters, groups and rules, never the
    # targets: about 4.8 KB on Julia 1.13 and 5.5 KB on 1.10 for 250 binary
    # parameters, at strength 2 or 4, where TargetList would list C(250, 4)
    # supports. Two overlapping groups at one strength add about 1 KB.
    wide = TestSpace([Symbol(:x, i) for i in 1:250], [1:2 for _ in 1:250], Constraint[], 10^5)
    for strength in (2, 4)
        request = Request(wide; strength)
        @test (@inferred Profile(request)) isa Profile
        @test measured(Profile, request) <= 8 * 1024
    end
    @test (@inferred Profile(constrained)).targets == length(TargetList(constrained))
    @test measured(Profile, constrained) <= 8 * 1024
    # Twenty `stronger` groups of one strength, each every parameter but one:
    # the count of their shared supports keeps a state per set of groups that
    # holds at most `s` parameters chosen, 1,351 of them, where every
    # intersection of groups was once a state and the profile allocated 620
    # MiB (`_union_count`). About 1 MiB now; a doubling per group would pass
    # 4 MiB by the third extra group.
    names = [Symbol(:p, i) for i in 1:21]
    overlapping = Request(TestSpace(names, [1:2 for _ in 1:21], Constraint[], 10^5); strength = 2,
                          stronger = [Tuple(names[setdiff(1:21, [g])]) => 3 for g in 1:20])
    @test Profile(overlapping).targets == length(TargetList(overlapping)) == 11_480
    @test measured(Profile, overlapping) <= 4 * 2^20
    # The protocol's other answers infer too; `_engine_for` is the engine or IPOG.
    profile = Profile(constrained)
    @test (@inferred engine_record(GND())) isa EngineRecord
    @test (@inferred fit(IPOG(), profile)) isa Fit
    @test (@inferred fit(GND(), profile)) isa Fit
    @test (@inferred Union{GND, IPOG} _engine_for(GND(), constrained)) isa GND
end


@testitem "stability: classification keeps nothing per required target, and the recount allocates nothing per row or support" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, RequiredTargets, TargetList, Excluded, _Classified, _classify_targets,
                          _classify_target, _space_indices, _recount, _required_matrix, cover_ordinary,
                          full_strength_rows, gnd_cover
    # Phase 5 (plan §5.6): classification walks the layout with two reused
    # rows and keeps the excluded targets' ids and a count per support. So it
    # asks for what its feasibility questions ask for, one question per target
    # (`_classify_target`, which copies the key and keeps the excluded
    # records), and a count per support beyond them, never a row per target.
    # On 20 binary parameters at strength 3 with one rule (9,120 targets, 36
    # excluded, 1,140 supports, each question's answer already cached) the
    # walk asked for 18,584 bytes more than the questions alone, of which
    # 9,120 are the counts, on Julia 1.13; a row of 20 kept or made per target
    # would add 1.6 MB, and even 8 bytes per target 73 KB. The questions are
    # p5-memo's, and measured beside the walk, so the bound holds whatever
    # they cost.
    binary(k) = TestSpace([Symbol(:p, i) for i in 1:k], [1:2 for _ in 1:k],
                          [forbid((a, b) -> a == 1 && b == 1, :p1, :p2)], 10^5)
    twenty = Request(binary(20); strength = 3)
    layout = TargetList(twenty)
    walk(x) = _classify_targets(x[1], x[2])
    function questions(x)
        request, active, idxs = x
        f = request.feasibility
        for idx in idxs
            _classify_target(request, f, active, idx, idx, "classifying target")
        end
        return nothing
    end
    walked = requested(walk, (twenty, layout))
    asked = requested(questions, (twenty, collect(eachindex(twenty.feasibility.tables)),
                                  [_space_indices(twenty, t) for t in layout]))
    @test length(layout) == 9_120 && length(layout.supports) == 1_140
    @test walked - asked <= 8 * 1_140 + 16 * 1024
    free = Request(TestSpace((a = 1:3, b = 1:2, c = 1:4)); strength = 2)
    for request in (twenty, free)
        @test (@inferred Union{Tuple{RequiredTargets{Nothing}, Vector{Excluded}},
                               Tuple{RequiredTargets{TargetList}, Vector{Excluded}}} _classify_targets(request,
                                                                                          TargetList(request))) isa Tuple
    end
    # The recount (`_recount`, contract §1.21) marks each row's code on each
    # support in one buffer, a bit per combination of the largest support, so
    # it asks for that buffer and nothing per row or per support: 96 bytes on
    # Julia 1.13 for 12 binary parameters at strength 2 (66 supports), the
    # same for three copies of the rows and for 24 parameters (276 supports).
    measured(f, x) = (f(x); @allocated f(x))   # one argument: see the targets-interface item
    recount(x) = _recount(x[1], x[2], x[3])
    readings = map((12, 24)) do k
        request = Request(binary(k); strength = 2)
        targets = _Classified(request).targets
        rows = cover_ordinary(IPOG(), request, targets)
        @test (@inferred _recount(request, rows, targets)) == length(TargetList(request)) - 1   # (p1 = 1, p2 = 1) excluded
        (measured(recount, (request, rows, targets)), measured(recount, (request, hcat(rows, rows, rows), targets)))
    end
    @test readings[1][1] == readings[1][2] == readings[2][1] == readings[2][2] <= 256
    # Readers that decode the required targets from their codes infer:
    # `full_strength_rows`, GND's coverage matrix and GND's design.
    full = Request(TestSpace((a = 1:2, b = 1:3, c = 1:2); constraints = [forbid((a = 1, b = 1))]); strength = 3)
    targets = _Classified(full).targets
    @test (@inferred full_strength_rows(full, targets)) == [1 1 1 1 2 2 2 2 2 2; 2 2 3 3 1 1 2 2 3 3; 1 2 1 2 1 2 1 2 1 2]
    @test (@inferred _required_matrix(targets)) isa Matrix{Int}
    @test (@inferred gnd_cover(GND(), full, targets)) isa Tuple{Matrix{Int}, Int}
    ruled = Request(binary(10); strength = 2)
    @test (@inferred gnd_cover(GND(), ruled, _Classified(ruled).targets)) isa Tuple{Matrix{Int}, Int}
end


@testitem "stability: every engine's plan infers, its execution infers behind `_run`, and a plan builds nothing" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, RequiredTargets, Profile, Fit, Design, NegativeProjection, classify_targets, fit,
        generate, _prepare, _execute, _run, _prepare_for, _negative_request, _catalog_entry, _DefaultPlan,
        _IPOGPlan, _ConstructionPlan, _CompactPlan, _AutoPlan
    # The engine protocol's plans (plan §4.2): `_prepare` is concrete for each
    # engine, `fit` is a `Fit`, and executing a concrete plan gives concrete
    # rows and notes; `Auto` runs its candidates' plans, of different types,
    # behind `_run`'s asserted result, and `generate` is a `Design` whatever
    # the engine.
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    request = Request(uniform(8, 7))
    profile = Profile(request)
    targets = RequiredTargets(request, first(classify_targets(request)))
    @test (@inferred _prepare(IPOG(), profile)) isa _IPOGPlan{IPOG}
    @test (@inferred _prepare(GND(), profile)) isa _DefaultPlan{GND}
    @test (@inferred _prepare(Construction(), profile)) isa _ConstructionPlan
    @test (@inferred _prepare(Compact(IPOG()), profile)) isa _CompactPlan{IPOG, _IPOGPlan{IPOG}}
    @test (@inferred _prepare(Compact(Construction()), profile)) isa _CompactPlan{Construction, _ConstructionPlan}
    @test (@inferred _prepare(Auto(), profile)) isa _AutoPlan
    for engine in (IPOG(), GND(), Construction(), Compact(Construction()), Auto(), Auto(goal = :compact))
        @test (@inferred fit(engine, profile)) isa Fit
        @test (@inferred generate(engine, request)) isa Design
    end
    for engine in (IPOG(), Construction(), Compact(IPOG()), Compact(Construction()))
        rows, notes = @inferred _execute(_prepare(engine, profile), request, targets)
        @test rows isa Matrix{Int} && isconcretetype(typeof(notes))
        rows, stage = @inferred _run(_prepare(engine, profile), request, targets)
        @test rows isa Matrix{Int} && isconcretetype(typeof(stage))
    end
    @test first(@inferred Tuple{Matrix{Int}, NamedTuple} _run(_prepare(Auto(), profile), request, targets)) isa Matrix{Int}
    # A negative sub-request the catalog refuses (strength 1) takes IPOG's plan: a union of two.
    space = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
    sub = _negative_request(Request(space), NegativeProjection(space, 1), zeros(Int, 3, 0))
    @test (@inferred Union{_ConstructionPlan, _IPOGPlan{IPOG}} _prepare_for(Construction(), Profile(sub))) isa
          _IPOGPlan{IPOG}
    # A plan lists no target and builds nothing: `Auto`'s, which prepares the
    # catalog's once, asks for the catalog's lookup and a few KB, at strength 3
    # on 250 parameters of 7 values, where a second lookup would double it:
    # the lookup asks for 474,865 bytes on Julia 1.13 and 754,361 on 1.10,
    # Auto's plan 6,054 and 5,959 bytes more, Compact(Construction())'s 711 and
    # 872 more. Counted as the bytes asked for (`requested`), since the
    # lookup's arrays are large enough for `@allocated` to count a larger block
    # than they ask for.
    wide = Profile(Request(uniform(250, 7); strength = 3))
    lookup = requested(k -> _catalog_entry(3, 7, k), 250)
    @test requested(p -> _prepare(Auto(), p), wide) <= lookup + 64 * 1024
    @test requested(p -> _prepare(Compact(Construction()), p), wide) <= lookup + 64 * 1024
end


@testitem "stability: the coverage index and the reducer's moves answer in place" setup=[StabilitySetup] begin
    using Random: Xoshiro
    using UnitTestDesign: Request, RequiredTargets, CoverageIndex, classify_targets, cover_ordinary, _Classified,
                          combination, add_row!, remove_row!, move_entry!, entry_score, singly_covered,
                          random_uncovered, decode!, nuncovered, nrows, max_support, members_of, _allows,
                          _allows_write, _holder, _replace_row!, _compact, _space_indices
    # The coverage index (plan §4.3) and the reducer's inner loop (§5.3): a
    # row's combination on a support, a move's score, a row's singly covered
    # combinations, an entry move, a row added and removed, a draw of an
    # uncovered combination and its decoding each infer their type and
    # allocate nothing once the uncovered list has room, and a move's rule
    # check allocates nothing once a lazy rule's verdict is in the memo
    # (tabulated, lazy and whole-case rules, as in `stability_space`). The
    # reducer's steps allocate nothing: a run of 100,000 steps allocates what
    # a run of 20,000 does (about 37 KB on Julia 1.13, all of it set-up and
    # the buffers' first growth).
    measured(f, x) = (f(x); @allocated f(x))   # one argument: see the targets-interface item
    request = Request(stability_space(); strength = 2, stronger = [(:a, :b, :c) => 3])
    # Classification's targets, whose bits the index builds and then holds.
    targets = _Classified(request).targets
    @test targets.bits === nothing
    index = @inferred CoverageIndex(request, targets)
    @test index.required === targets.bits
    start = cover_ordinary(IPOG(), request, targets)
    rows = [start[:, j] for j in axes(start, 2)]
    foreach(row -> add_row!(index, row), rows)
    @test nuncovered(index) == 0
    row = rows[2]
    @test (@inferred combination(index, 1, row)) isa Int
    @test (@inferred entry_score(index, row, 1, 3 - min(row[1], 2))) isa Int
    @test (@inferred singly_covered(index, row)) isa Int
    @test measured(x -> combination(x[1], length(x[1].supports), x[2]), (index, row)) == 0
    @test measured(x -> entry_score(x[1], x[2], 1, 3 - min(x[2][1], 2)), (index, row)) == 0
    @test measured(x -> singly_covered(x[1], x[2]), (index, row)) == 0
    there_and_back(x) = (move_entry!(x[1], x[2], 4, x[3]); move_entry!(x[1], x[2], 4, x[4]))
    @test measured(there_and_back, (index, row, row[4] == 1 ? 2 : 1, row[4])) == 0
    out_and_in(x) = (remove_row!(x[1], x[2]); add_row!(x[1], x[2]))
    @test measured(out_and_in, (index, row)) == 0
    @test (@inferred remove_row!(index, row)) === index
    @test nuncovered(index) > 0
    rng = Xoshiro(1)
    @test (@inferred random_uncovered(index, rng)) isa Int
    @test measured(x -> random_uncovered(x[1], x[2]), (index, rng)) == 0
    values = zeros(Int, 3)
    @test (@inferred decode!(values, index, random_uncovered(index, rng))) isa Int
    @test measured(x -> decode!(x[1], x[2], 1), (values, index)) == 0
    add_row!(index, row)
    # A move's rule check: every rule reads `a`; the second call finds each verdict.
    f = request.feasibility
    value_row = _space_indices(request, row)
    @test length(f.param_tables[1]) == 3
    @test (@inferred _allows(f, value_row, 1, 3)) isa Bool
    @test measured(x -> _allows(x[1], x[2], 1, 3), (f, value_row)) == 0
    @test value_row == _space_indices(request, row)   # restored
    # The reducer: a concrete result, and steps that allocate nothing. Ten
    # four-valued parameters never reach the bound of 16, so every run spends
    # its whole budget.
    @test (@inferred _compact(request, targets, start)) isa Tuple{Matrix{Int}, NamedTuple}
    flat = Request(TestSpace([Symbol(:x, i) for i in 1:10], [1:4 for _ in 1:10], Constraint[], 10^5))
    flat_targets = RequiredTargets(flat, first(classify_targets(flat)))
    flat_start = cover_ordinary(IPOG(), flat, flat_targets)
    run(budget) = (_compact(flat, flat_targets, flat_start; budget); @allocated _compact(flat, flat_targets, flat_start; budget))
    short, long = run(20_000), run(100_000)
    @test last(_compact(flat, flat_targets, flat_start; budget = 20_000)).reducer_stop === :budget
    @test long <= short + 1024
    # The same with rules, two scoped and tabulated, one lazy, one whole-case:
    # there a step may find no allowed entry move and write the combination
    # into a row (`_allows_write`) or replace the row by a starting row that
    # holds it (`_holder`, `_replace_row!`). Counted once by instrumenting the
    # reducer, a run replaced a row 2 times in 20,000 steps and 19 in 100,000,
    # and still allocated the same (Julia 1.13).
    rules = [forbid((a, b) -> a == 1 && b == 2, :x1, :x2), forbid((a, b, c) -> a == b == c, :x3, :x4, :x5),
             forbid((a, b) -> a + b == 5, :x6, :x7), forbid(row -> row.x1 == 3 && row.x10 == 3)]
    ruled = Request(with_logger(NullLogger()) do   # tabulation_limit = 30: the rule on three parameters is lazy
        TestSpace([Symbol(:x, i) for i in 1:10], [1:4 for _ in 1:10], rules, 30)
    end)
    ruled_targets = RequiredTargets(ruled, first(classify_targets(ruled)))
    ruled_start = cover_ordinary(IPOG(), ruled, ruled_targets)
    run_ruled(budget) = (_compact(ruled, ruled_targets, ruled_start; budget);
                         @allocated _compact(ruled, ruled_targets, ruled_start; budget))
    short, long = run_ruled(20_000), run_ruled(100_000)
    @test last(_compact(ruled, ruled_targets, ruled_start; budget = 20_000)).reducer_stop === :budget
    @test long <= short + 1024
    # Those paths on their own: a write's rule check, the draw of a starting row
    # that holds a combination, and a row's replacement allocate nothing.
    index = CoverageIndex(ruled, ruled_targets)
    starts = [ruled_start[:, j] for j in axes(ruled_start, 2)]
    design = [copy(row) for row in starts]
    foreach(row -> add_row!(index, row), design)
    combination_values = zeros(Int, max_support(index))
    s = decode!(combination_values, index, combination(index, 7, starts[1]))   # a combination row 1 holds
    span = members_of(index, s)
    f, candidates = ruled.feasibility, ruled.candidates
    values, saved = _space_indices(ruled, design[2]), zeros(Int, max_support(index))
    @test (@inferred _allows_write(f, values, saved, index, span, combination_values, candidates)) isa Bool
    @test measured(x -> _allows_write(x...), (f, values, saved, index, span, combination_values, candidates)) == 0
    @test values == _space_indices(ruled, design[2])   # restored
    rng = Xoshiro(3)
    @test (@inferred _holder(starts, index, span, combination_values, rng)) isa Vector{Int}
    @test measured(x -> _holder(x...), (starts, index, span, combination_values, rng)) == 0
    source = _holder(starts, index, span, combination_values, rng)
    @test (@inferred _replace_row!(index, design[2], values, source, candidates)) == source
    @test measured(x -> _replace_row!(x...), (index, design[2], values, source, candidates)) == 0
    @test values == _space_indices(ruled, source) && nrows(index) == length(design)
end


@testitem "stability: the catalog's lookup and builders infer, and a builder allocates its result" setup=[StabilitySetup] begin
    using UnitTestDesign: GaloisField, CatalogEntry, Construction, Fit, Profile, Request, RequiredTargets,
        classify_targets, cover_ordinary, fit, _catalog_entry, _catalog_rows, _build, _describe, _engine_rows,
        _bush, _bush_even, _kleitman_spencer, _zero_sum, _fuse, _lfsr_array, _lemma35, _lfsr_copies, _sca_base,
        _sca_product, _partitioned, _od_triple, _projection, _group_ca88, _ck_ca185, _od_strength3, _CCL_TABLE3,
        _cmtw_multiply, _primitive_cubic, _plus, _times
    # The catalog (plan §5.4): a lookup returns an entry or `nothing`, a size
    # an Int or `nothing`, and every builder a Matrix{Int}; `_build` recurses
    # through the ingredients and keeps its declared type.
    F = @inferred GaloisField(7)
    @test (@inferred _plus(F, 3, 5)) isa Int && (@inferred _times(F, 3, 5)) isa Int
    @test (@inferred _primitive_cubic(F)) isa NTuple{3, Int}
    @test (@inferred Union{Nothing, CatalogEntry} _catalog_entry(2, 7, 8)) isa CatalogEntry
    @test (@inferred Union{Nothing, CatalogEntry} _catalog_entry(3, [5, 4, 3, 2])) isa CatalogEntry
    @test (@inferred Union{Nothing, Int} _catalog_rows(3, 5, 155)) == 485
    @test (@inferred _describe(_catalog_entry(2, 7, 8))).orthogonal
    for (t, v, k) in ((2, 2, 20), (2, 3, 40), (2, 10, 20), (2, 6, 20), (3, 3, 20), (3, 6, 6), (3, 2, 30), (3, 5, 155))
        @test (@inferred _build(_catalog_entry(t, v, k))) isa Matrix{Int}
    end
    G = GaloisField(3)
    for A in (@inferred(_bush(F, 3)), @inferred(_bush_even(GaloisField(4))), @inferred(_kleitman_spencer(20)),
              @inferred(_zero_sum([3, 3, 3])), @inferred(_fuse(_bush(F, 2), 7)), @inferred(_lfsr_array(F)),
              @inferred(_lemma35(F, 1)), @inferred(_lfsr_copies(G, 3)), @inferred(_od_triple(_bush(F, 2), 7)),
              @inferred(_projection(F, 2)), @inferred(_group_ca88()), @inferred(_ck_ca185()),
              @inferred(_od_strength3(GaloisField(5), _CCL_TABLE3)), @inferred(_cmtw_multiply(_bush(G, 3), _bush(G, 2), G)))
        @test A isa Matrix{Int}
    end
    @test (@inferred _sca_product(_sca_base(F), (7, 1), _sca_base(F), (7, 1), 7)) isa Tuple{Matrix{Int}, Tuple{Int, Int}}
    @test (@inferred _partitioned(_sca_base(F), 43:49, 7)) isa Tuple{Matrix{Int}, Tuple{Int, Int}, Bool}
    # The engine's protocol answers infer too.
    request = Request(TestSpace((a = 1:3, b = 1:3, c = 1:3, d = 1:3, e = 1:3)))
    @test (@inferred fit(Construction(), Profile(request))) isa Fit
    targets = RequiredTargets(request, first(classify_targets(request)))
    @test (@inferred cover_ordinary(Construction(), request, targets)) isa Matrix{Int}
    # A builder asks for its result and a few small buffers, counted as the
    # bytes it asks for (`requested`): its result and 40 to 3,360 bytes more
    # on Julia 1.10 and 1.13 (the LFSR array, 312,360 bytes, asks for 315,680
    # on 1.13 and 315,720 on 1.10), so the bound, the result plus 8 KiB,
    # leaves at least 4.7 KiB; a value boxed per entry, or a second copy of a
    # result above 8 KiB, fails. `@allocated` read the LFSR array at 331,408
    # bytes on 1.13 under macOS, against a bound of 359,597 that allowed an
    # eighth for the allocator's rounding, which a larger free block (see
    # `requested`) could take.
    for (f, x) in ((F -> _bush(F, 3), F), (F -> _bush(F, 2), F), (_lfsr_array, F), (_kleitman_spencer, 200),
                   (_zero_sum, [6, 6, 6, 6]), (A -> _fuse(A, 7), _bush(F, 3)))
        @test requested(f, x) <= sizeof(f(x)) + 8192
    end
    # A field is its tables: 1 MiB for 256 symbols, and little beside, its
    # digits (16 KiB) and its smaller tables: it asks for 1,075,656 bytes on
    # Julia 1.13 and 1,075,920 on 1.10. The bound, the two tables plus 32 KiB,
    # leaves 5.3 KiB; another table of digits fails. (`@allocated` read
    # 1,075,712 against a bound of the tables plus 64 KiB.)
    @test requested(GaloisField, 256) <= 2 * 256^2 * 8 + 32 * 1024
    # A lookup builds nothing: 37 KB at strength 2 on 10 parameters of 5 values
    # and 0.57 MB at strength 3 on 250 of 7 on Julia 1.13; 76 KB and 0.97 MB on 1.10.
    # These bounds leave more than twice the reading, so `@allocated` serves.
    measured(f, x) = (f(x); @allocated f(x))   # one argument: see the targets-interface item
    @test measured(k -> _catalog_entry(2, 5, k), 10) <= 128 * 1024
    @test measured(k -> _catalog_entry(3, 7, k), 250) <= 2 * 2^20
end


@testitem "stability: Auto's choice, the lower bound and recommend infer, and the bound reads supports in place" setup=[StabilitySetup] begin
    using UnitTestDesign: Profile, Request, RequiredTargets, Design, classify_targets, supports, generate, _auto_plan,
        _AutoPlan, _ordinary_bound, _SupportBound, _bound_record, _request_bound, _recommendation, _prepare, _execute
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    # Auto's choice (plan §4.1) is a function of the profile, with one concrete type,
    # whichever rule it takes: the catalog alone, both starts, or IPOG alone.
    for space in (uniform(8, 7), uniform(15, 6), TestSpace((a = 1:2, b = 1:3, c = 1:4, d = 1:2)))
        for goal in (:fast, :balanced, :compact)
            @test (@inferred _auto_plan(Auto(; goal), Profile(Request(space)))) isa _AutoPlan
            @test (@inferred _prepare(Auto(; goal), Profile(Request(space)))) isa _AutoPlan
        end
    end
    # The bound (plan §4.1): one concrete type, and its record a NamedTuple of concrete fields.
    ruled = Request(TestSpace((a = 1:3, b = 1:3, c = 1:2); constraints = [forbid((a = 1, b = 1))]);
                    must_include = [(a = 2, b = 2, c = 1), (a = 3,)])
    targets = RequiredTargets(ruled, first(classify_targets(ruled)))
    b = @inferred _ordinary_bound(ruled, targets)
    @test b isa _SupportBound && b.rows == 8
    @test (@inferred _bound_record(9, b, 0, ruled.space.names, ruled.arity, supports(targets))) isa
          @NamedTuple{lower_bound::Int, minimal::Bool, proof::String}
    request = Request(uniform(8, 7))
    @test (@inferred Union{Tuple{Int, String}, Tuple{Nothing, String}} _request_bound(request)) == (49, _request_bound(request)[2])
    @test (@inferred _recommendation(Auto(), request)) isa Recommendation
    @test (@inferred recommend(uniform(8, 7))) isa Recommendation
    # A start's rows are a Matrix{Int} with concrete notes; Auto's notes are one
    # of a few NamedTuples, as the winner decides, behind `_run`'s barrier.
    all_targets = RequiredTargets(request, first(classify_targets(request)))
    @test first(@inferred _execute(_prepare(Construction(), Profile(request)), request, all_targets)) isa Matrix{Int}
    @test first(@inferred Tuple{Matrix{Int}, NamedTuple} _execute(_prepare(Auto(), Profile(request)), request,
                                                                  all_targets)) isa Matrix{Int}
    # The default engine's paths (`covering`'s `engine = Auto()`): IPOG alone on
    # mixed counts; both starts on the front page's space (IPOG's design and the
    # zero-sum array seeded under its rules) and on 15 × 6 (IPOG's and an exact
    # array); the catalog alone at the bound, with an Invalid value's negative
    # rows. Each start's plan executes with concrete notes, Auto's plan runs
    # them behind `_run`'s asserted barrier, and `generate` is a `Design`.
    front = TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
                      constraints = [@require(mode == :exact || solver == :none), forbid((mode = :exact, tol = 1e-3))])
    flagged = TestSpace((a = [1, 2, 3, Invalid(0)], b = 1:3, c = 1:3, d = 1:3))
    for (space, runs) in ((TestSpace((a = 1:2, b = 1:3, c = 1:4, d = 1:2)), [true, false]), (front, [true, true]),
                          (uniform(15, 6), [true, true]), (flagged, [false, true]))
        r = Request(space)
        p = Profile(r)
        t = RequiredTargets(r, first(classify_targets(r)))
        plan = @inferred _prepare(Auto(), p)
        @test [c.runs for c in plan.candidates] == runs
        for engine in (IPOG(), Construction())
            q = _prepare(engine, p)
            q.fit.kind === :unsupported && continue
            @test isconcretetype(typeof(last(@inferred _execute(q, r, t))))
        end
        @test first(@inferred Tuple{Matrix{Int}, NamedTuple} _execute(plan, r, t)) isa Matrix{Int}
        @test (@inferred generate(Auto(), r)) isa Design
    end
    # The bound reads every support in place, 45 or 7,140 of them: without
    # must-include rows it allocates nothing, and with them its two buffers,
    # whatever the supports (192 bytes for 3 rows on Julia 1.13, 320 on 1.10).
    # One argument, as the targets-interface item advises.
    bound_bytes(r) = (t = RequiredTargets(r, first(classify_targets(r))); _ordinary_bound(r, t); @allocated _ordinary_bound(r, t))
    @test bound_bytes(Request(uniform(10, 3))) == bound_bytes(Request(uniform(120, 3))) == 0
    with_rows(k) = Request(uniform(k, 3); must_include = [(p1 = 1, p2 = 2), (p3 = 3,), Tuple(fill(1, k))])
    @test bound_bytes(with_rows(10)) == bound_bytes(with_rows(40)) <= 512
    # Many must-include rows, as when topping up a previous design: each
    # support's held codes are marked in a reused bit buffer, not sorted, so
    # the bound allocates its two buffers whether it reads 435 supports
    # (strength 2) or 4,060 (strength 3): for 200 rows 1,776 bytes on Julia
    # 1.13 and 1,872 on 1.10. A sort per support took scratch space past
    # about 40 codes, 980 KB for 200 rows at strength 3.
    previous = collect(all_pairs(uniform(30, 3); engine = IPOG()))
    topping(t, m) = Request(uniform(30, 3); strength = t, must_include = [previous[mod1(i, length(previous))] for i in 1:m])
    for m in (60, 200)
        @test bound_bytes(topping(2, m)) == bound_bytes(topping(3, m)) <= 8 * m + 512
    end
end


@testitem "stability: a wide product builds only its kept columns, and the builders under `_build` infer" setup=[StabilitySetup] begin
    using UnitTestDesign: GaloisField, Request, RequiredTargets, Profile, classify_targets, ipog_order, _catalog_entry,
        _build, _sca_base, _sca_pair, _sca_product_columns, _product_columns, _wide_product_columns,
        _partitioned_columns, _lemma35_entry, _two_constant_rows, _paley12, _zero_sum, _engine_rows,
        _new_coverage_rows, _hold!, _lookup_steps, _lookup_complete, _ipog_members, _prepare, _execute
    # `_build` and `_build_full` declare `::Matrix{Int}`, which `@inferred
    # _build(…)` then only restates (review of Phase 2, finding 5); the
    # functions under them are checked here. `_two_constant_rows` was `Any`
    # (a captured variable assigned again), on both of its paths: a pair of
    # rows made constant (zero-sum) and a complement added (Hadamard 12).
    @test (@inferred _two_constant_rows(_zero_sum([2, 2, 2, 2]))) isa Matrix{Int}
    @test (@inferred _two_constant_rows(_paley12())) isa Matrix{Int}
    B = _sca_base(GaloisField(7))
    @test (@inferred _sca_pair(50, (7, 1), (7, 1))) isa Tuple{Int, Int}
    @test (@inferred _sca_product_columns(B, axes(B, 2), (7, 1), B, (7, 1), 7, [1, 9, 60])) isa Matrix{Int}
    wide = _catalog_entry(2, 64, 80)          # partitioned product: orthogonal array x orthogonal array
    x, y = wide.parts[1].parts
    @test (@inferred _product_columns(x, _build(y), y, 64, 1:80)) isa Matrix{Int}
    chain = @inferred _lemma35_entry(7, 2)
    @test (@inferred _wide_product_columns(chain, 1:100)) isa Matrix{Int}
    @test (@inferred _partitioned_columns(chain, [3, 70, 497])) isa Matrix{Int}
    # A wide product cut to its parameters allocates a small multiple of what
    # it keeps (review of Phase 2, finding 4). At 80 parameters of 64 values
    # the whole product has 4,224 columns, and `_build` allocated 533 MiB,
    # 107 times its 5 MiB result. Now it asks for 11,706,328 bytes on Julia
    # 1.13 and 11,706,467 on 1.10, 2.25 times: the result, its two factors,
    # and the first factor cut to the 64 columns it needs. Lemma 3.5 at 41
    # symbols for 130 parameters has 1,763 columns: 149 MiB before, 45 times
    # its 3.3 MiB result; now 16,416,452 and 16,566,736 bytes, 4.76 and 4.80
    # times (`_partitioned` copies what it keeps twice, and fusion once). The
    # bounds, 2.5 and 5 times, are those readings plus at least a fifth of the
    # result (1.3 and 0.7 MB): less than one more copy of the result, or, for
    # the wide product, of a factor. `@allocated` read the same builds at 2.25
    # to 3.05 and 4.79 to 6.53 times on Julia 1.13 under macOS, by what had
    # run before (see `requested`), past the 3 and 6 times these guards first
    # had; the first had since been widened to 4.
    @test requested(_build, wide) <= 5 * sizeof(_build(wide)) ÷ 2
    lemma = _catalog_entry(2, 40, 130)
    @test lemma.kind === :lemma35 && requested(_build, lemma) <= 5 * sizeof(_build(lemma))
    measured(f, x) = (f(x); @allocated f(x))   # one argument: see the targets-interface item
    # With must-include rows the catalog's rows are filtered by what they hold
    # (finding 1): a concrete result, and a row read without allocating.
    names = [Symbol(:p, i) for i in 1:8]
    request = Request(TestSpace(names, [1:7 for _ in 1:8], Constraint[], 10^5);
                      must_include = [(1, 2, 3, 4, 5, 6, 7, 1)])
    targets = RequiredTargets(request, first(classify_targets(request)))
    rows = _engine_rows(_catalog_entry(2, 7, 8), request.arity)
    @test (@inferred _new_coverage_rows(request.must_include, rows, targets)) isa Matrix{Int}
    held = falses(last(targets.layout.offsets))
    @test (@inferred _hold!(held, view(rows, :, 1), targets)) === true
    @test measured(x -> _hold!(x[1], view(x[2], :, 2), x[3]), (held, rows, targets)) == 0
    # It allocates its bits, one per combination, and the rows it keeps.
    filtered(r) = _new_coverage_rows(r.must_include, rows, targets)
    @test measured(filtered, request) <= sizeof(rows) + cld(last(targets.layout.offsets), 8) + 8192
    # Partial must-include rows are completed first by IPOG's steps on them
    # alone (the maintainer's follow-up 2): the targets by step, the completed
    # rows and the design have concrete types.
    partial = Request(TestSpace(names, [1:7 for _ in 1:8], Constraint[], 10^5);
                      must_include = [(p1 = 1, p2 = 2), (p3 = 3, p8 = 4)])
    required = first(classify_targets(partial))
    pt = RequiredTargets(partial, required)
    steps = @inferred _lookup_steps(pt, partial.arity, ipog_order(partial.arity, partial.groups))
    @test (@inferred _ipog_members()) isa Vector{Tuple{Symbol, Symbol}}
    @test (@inferred _lookup_complete(steps, pt, Returns(false), partial.must_include; tiebreak = :rotate)) isa
          Matrix{Int}
    plan = _prepare(Construction(), Profile(partial))
    @test first(@inferred _execute(plan, partial, RequiredTargets(partial, required))) isa Matrix{Int}
end


@testitem "stability: IPOG's lookup core scores and places in place" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, Profile, Design, RequiredTargets, _Classified, _IPOGLookup, _IPOGPlan, _prepare,
        _execute, _run, _lookup_steps, _LookupSteps, _lookup_cover, _lookup_complete, _LookupRun, _lookup_grow!,
        _begin_step!, _mark_required!, _horizontal!, _vertical!, _base, _cover_on!, _choose, _find_row,
        _decode_combo!, _agrees, _tiekey, _fill!, generate, dead, supports, ncombinations, nrequired
    # The core of plan §5.5 (Phase 4): its plan and its operations infer, a
    # lookup and a placement allocate nothing, horizontal growth over a whole
    # step allocates nothing, nor does vertical growth that starts no row, and
    # a whole run asks for its rows, its largest step's map and small
    # buffers, never something per row or per lookup.
    measured(f, x) = (f(x); @allocated f(x))   # one argument: see the targets-interface item
    "Bytes `g(x)` allocates on a fresh `x = make()`, after a first call on another compiled it."
    allocated_fresh(g, make) = (g(make()); x = make(); @allocated g(x))
    uniform(k, v) = TestSpace([Symbol(:p, i) for i in 1:k], [1:v for _ in 1:k], Constraint[], 10^5)
    request = Request(uniform(10, 3); strength = 3)
    targets = _Classified(request).targets
    plan = @inferred _prepare(IPOG(), Profile(request))
    @test plan isa _IPOGPlan{IPOG}
    # Every plan's notes name the member that made the rows, one type for
    # one member, several, and full strength, so the stage infers concretely.
    rows, notes = @inferred _execute(plan, request, targets)
    @test rows isa Matrix{Int} && notes.member isa NamedTuple{(:tiebreak, :vertical), Tuple{Symbol, Symbol}}
    @test first(@inferred _run(plan, request, targets)) == rows
    one = @inferred _prepare(_IPOGLookup(), Profile(request))
    @test one isa _IPOGPlan{_IPOGLookup} && typeof(@inferred _execute(one, request, targets)) === typeof((rows, notes))
    full = Request(uniform(4, 3); strength = 4)
    @test typeof(last(@inferred _execute(_prepare(IPOG(), Profile(full)), full, _Classified(full).targets))) ===
          typeof(notes)
    @test (@inferred generate(IPOG(), request)) isa Design
    steps = @inferred _lookup_steps(targets, request.arity, plan.order)
    @test (@inferred _lookup_cover(steps, targets, Returns(false), request.must_include; notes.member...)) == rows
    @test (@inferred _lookup_complete(steps, targets, Returns(false), request.must_include)) isa Matrix{Int}
    ruled = Request(stability_space(); strength = 2, must_include = [(a = 2,)])
    rt = _Classified(ruled).targets
    rsteps = _lookup_steps(rt, ruled.arity, _prepare(IPOG(), Profile(ruled)).order)
    @test (@inferred _lookup_cover(rsteps, rt, row -> dead(ruled, row), ruled.must_include)) isa Matrix{Int}
    # A run at the eighth parameter's step, after the seven before it, every
    # buffer sized: one step's growth, on a fresh copy each time.
    function at_step(k; tiebreak = :lowest, vertical = :support)
        run = _LookupRun(steps, Returns(false), zeros(Int, 10, 0), tiebreak, vertical)
        for p in steps.order[1:(k - 1)]
            steps.first[p] == steps.first[p + 1] && continue
            _begin_step!(run, steps, targets, p)
            _horizontal!(run)
            _vertical!(run, true)
        end
        _begin_step!(run, steps, targets, steps.order[k])
        return run
    end
    for tiebreak in (:lowest, :rotate, :leastused, :mostleft)
        template = at_step(8; tiebreak)
        @test allocated_fresh(_horizontal!, () -> deepcopy(template)) == 0
    end
    # Vertical growth, in either order, allocates only its candidate lists,
    # when they outgrow what the steps before left them, a few words a row;
    # and where it starts rows (`add`), the rows' storage as it grows, a few
    # rows' worth. Each placement allocates nothing (below).
    for vertical in (:support, :value), add in (false, true)
        local start = at_step(8; vertical)
        local started() = (run = deepcopy(start); _horizontal!(run); run)
        @test sum(started().left) > 0   # vertical growth has combinations to place
        local after = (run = started(); _vertical!(run, add); run.nrows)
        @test allocated_fresh(run -> _vertical!(run, add), started) <=
              32 * (after + 16) + (add ? 32 * (start.n + 1) * after : 0)
    end
    template = at_step(8)
    grown() = (run = deepcopy(template); _horizontal!(run); run)
    # One lookup, one choice, one row search, one coverage mark.
    run = grown()
    @test (@inferred _base(run, 0, 1)) isa Int
    @test measured(r -> _base(r, 0, 1), run) == 0
    @test measured(r -> _cover_on!(r, 0, 1), run) == 0
    @test (@inferred _choose(run, 1, 0)) isa Int
    @test measured(r -> _choose(r, 1, 0), run) == 0
    @test (@inferred _tiekey(run, 3, 2)) isa Int
    @test measured(r -> _find_row(r, 1, _decode_combo!(r, 1, 0)), run) == 0
    @test measured(r -> _agrees(r, 0, 1), run) == 0
    # The final fill allocates nothing either.
    filled() = (run = _LookupRun(steps, Returns(false), zeros(Int, 10, 0), :lowest, :support); _lookup_grow!(run, steps, targets, true))
    @test allocated_fresh(_fill!, filled) == 0
    # A step's map where rules partly exclude some of its supports: each
    # combination of those is asked by its code (`_mark_required!`'s
    # odometer), and making the map again, its buffers sized, allocates
    # nothing, with `dead` a closure. 12 × 4 at strength 3, three rules.
    parted = Request(TestSpace([Symbol(:p, i) for i in 1:12], [1:4 for _ in 1:12],
                               [forbid((p1 = 1, p12 = 2)), forbid((p3 = 2, p11 = 3)), forbid((p5 = 1, p6 = 1, p10 = 1))],
                               10^5); strength = 3)
    pt = _Classified(parted).targets
    psteps = _lookup_steps(pt, parted.arity, _prepare(IPOG(), Profile(parted)).order)
    prun = _LookupRun(psteps, row -> dead(parted, row), zeros(Int, 12, 0), :lowest, :support)
    odometer = Ref(0)   # partly excluded supports met
    for p in psteps.order
        psteps.first[p] == psteps.first[p + 1] && continue
        _begin_step!(prun, psteps, pt, p)
        @test measured(x -> _begin_step!(x[1], x[2], x[3], x[4]), (prun, psteps, pt, p)) == 0
        partial = [j for j in 1:prun.m if 0 < nrequired(pt, prun.sidx[j]) < ncombinations(pt, prun.sidx[j])]
        if !isempty(partial)
            odometer[] += length(partial)
            @test measured(x -> _mark_required!(x[1], x[2], x[3]), (prun, pt, first(partial))) == 0
            _begin_step!(prun, psteps, pt, p)   # the map again, as the step needs it
        end
        _horizontal!(prun)
        _vertical!(prun, true)
    end
    @test odometer[] > 0
    # A whole run asks for its rows (grown as they are added, then copied
    # once), its largest step's map (grown as the steps grow), and its
    # per-step buffers: at most 8 times the rows' bytes, 4 times the map's,
    # and 64 KiB, here on 8 × 64 at
    # strength 2 (7,168 rows; 2.75 MB on Julia 1.13), 20 × 3 at strength 4,
    # and 128 binary parameters at strength 2, a wide space of many small
    # steps (77 KB). At 0ce33a4 IPOG asked for 9.7 MB on 8 × 64 and the scan
    # for every tuple of a step at each row.
    for (k, v, t) in ((8, 64, 2), (20, 3, 4), (128, 2, 2))
        big = Request(uniform(k, v); strength = t)
        bt = _Classified(big).targets
        bsteps = _lookup_steps(bt, big.arity, _prepare(IPOG(), Profile(big)).order)
        cover(s) = _lookup_cover(s, bt, Returns(false), big.must_include)
        largest = maximum(p -> sum(s -> ncombinations(bt, s), view(bsteps.supports, bsteps.first[p]:(bsteps.first[p + 1] - 1));
                                   init = 0), 1:k)
        @test requested(cover, bsteps) <= 8 * sizeof(cover(bsteps)) + 4 * largest + 64 * 1024
    end
end
