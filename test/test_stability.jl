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


@testitem "stability: classic IPOG reads its targets in place" setup=[StabilitySetup] begin
    using UnitTestDesign: MatrixCoverage, ipog, one_parameter_combinations!, matches_from_missing!,
        add_coverage!, choose_last_parameter!, insert_tuple_into_tests
    # One step of classic IPOG (plan §5.2): the 8th of ten three-valued
    # parameters joins a design on the first seven, at strength 2. The
    # targets' matrix has a row for all ten, as `ipog` keeps it.
    arity, p = fill(3, 10), 8
    prior = ipog(arity[1:(p - 1)], 2)
    taller = vcat(prior, zeros(Int, 1, size(prior, 2)))
    step = @inferred one_parameter_combinations!(MatrixCoverage(zeros(Int, 10, 0), 0, arity), p, 2)
    @test step.remain == 7 * 3 * 3
    fresh() = (copy(taller), MatrixCoverage(copy(step.allc), step.remain, arity))
    "Bytes allocated by `g(make()...)`, on fresh arguments, after a first call compiled it."
    function allocated_fresh(g, make)
        g(make()...)
        args = make()
        return @allocated g(args...)
    end

    @test (@inferred ipog(arity, 2)) isa Matrix{Int}
    hist = zeros(Int, 3)
    @test (@inferred matches_from_missing!(hist, step, view(taller, :, 1), p)) === hist
    row = [prior[:, 1]; 1]  # a complete case, which covers seven targets
    covering() = (fresh()[2], row)
    @test (@inferred add_coverage!(covering()...)) == step.remain - 7
    # Scoring a case and covering with a row read every target in place and
    # allocate nothing; at 2798ecf each target read copied a column, and
    # add_coverage! also listed the covered ones.
    @test allocated(matches_from_missing!, hist, step, view(taller, :, 1), p) == 0
    @test allocated_fresh(add_coverage!, covering) == 0
    # Horizontal growth allocates one histogram for the step.
    @test allocated_fresh(choose_last_parameter!, fresh) <= allocated(k -> zeros(Int, k), 3)
    # Vertical growth allocates the cases it adds and the matrix it returns.
    grown() = ((t, mc) = fresh(); choose_last_parameter!(t, mc); (t, mc))
    added = size(insert_tuple_into_tests(grown()...), 2) - size(taller, 2)
    @test added > 0
    @test allocated_fresh(insert_tuple_into_tests, grown) <=
          2 * allocated((n, k) -> [zeros(Int, n) for _ in 1:k], p, added) +
          2 * allocated(zeros, Int, p, size(taller, 2) + added)
    # A later step with fewer targets writes over the same matrix.
    matrix = step.allc
    @test one_parameter_combinations!(step, p - 1, 2).allc === matrix
    # A whole run allocates about 5 MiB on 128 binary parameters, mostly
    # small vectors that enumerate each step's tuples; at 2798ecf it
    # allocated 255 MiB, a new matrix of targets per step and a copy per read.
    @test allocated(ipog, fill(2, 128), 2) <= 16 * 2^20
end


@testitem "stability: the targets interface answers in place, and a profile lists no target" setup=[StabilitySetup] begin
    using UnitTestDesign: Request, RequiredTargets, Profile, TargetList, classify_targets, supports,
                          ncombinations, isrequired, nrequired, engine_record, fit, _engine_for, Fit, EngineRecord
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
    # The protocol's other answers infer too; `_engine_for` is the engine or IPOG.
    profile = Profile(constrained)
    @test (@inferred engine_record(GND())) isa EngineRecord
    @test (@inferred fit(IPOG(), profile)) isa Fit
    @test (@inferred fit(GND(), profile)) isa Fit
    @test (@inferred Union{GND, IPOG} _engine_for(GND(), constrained)) isa GND
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
    # A builder allocates its result and a few small buffers: the bound is the
    # result, rounded up as the allocator rounds a large array, plus 8 KiB; a
    # value boxed per entry would cost several times the result. One argument
    # and no varargs (see the targets-interface item).
    measured(f, x) = (f(x); @allocated f(x))
    budget(A) = sizeof(A) + sizeof(A) ÷ 8 + 8192
    for (f, x) in ((F -> _bush(F, 3), F), (F -> _bush(F, 2), F), (_lfsr_array, F), (_kleitman_spencer, 200),
                   (_zero_sum, [6, 6, 6, 6]), (A -> _fuse(A, 7), _bush(F, 3)))
        @test measured(f, x) <= budget(f(x))
    end
    # A field is its tables: 1 MiB for 256 symbols, and little beside.
    @test measured(GaloisField, 256) <= 2 * 256^2 * 8 + 64 * 1024
    # A lookup builds nothing: 37 KB at strength 2 on 10 parameters of 5 values
    # and 0.57 MB at strength 3 on 250 of 7 on Julia 1.13; 76 KB and 0.97 MB on 1.10.
    @test measured(k -> _catalog_entry(2, 5, k), 10) <= 128 * 1024
    @test measured(k -> _catalog_entry(3, 7, k), 250) <= 2 * 2^20
end
