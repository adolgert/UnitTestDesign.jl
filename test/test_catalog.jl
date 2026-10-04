using Test
using TestItemRunner

# The catalog of covering-array constructions (plan §5.4, Phase 2): field
# arithmetic, the cover-starter tables, every construction, and the lookup
# from sizes alone. Every array is checked by brute force with the checkers
# below, which share no code with the package; some also go through the
# package's `coverage`. The reference implementation the package was ported
# from is in design/20261003_solver_plan_constructions/ (verify.jl,
# catalog_table.jl); test/construction_catalog_table.txt is its table of 974
# shapes. The engine built on the catalog is tested in test_construction.jl,
# and the inference and allocation guards are in test_stability.jl.

@testsnippet CatalogSetup begin
    using Random: Xoshiro
    using UnitTestDesign: CatalogEntry, GaloisField, _catalog_entry, _catalog_rows, _build, _describe,
        _is_prime_power, _STAR, _fill_stars, _zero_sum, _fuse, _fused, _derive, _symbol_product, _kleitman_spencer,
        _bush, _bush_even, _sca_base, _sca_product, _lemma44, _lemma35, _lemma35_columns, _partitioned, _product,
        _idempotent_square, _od_triple, _is_fixed_starter, _is_distinct_starter, _fixed_starter_array,
        _distinct_starter_array, _projection, _printed, _CMMSSY_FIGURE5, _CMMSSY_FIGURE6, _CMMSSY_FIGURE7,
        _primitive_cubic, _lfsr_array, _lfsr_blocks, _difference_covering, _lfsr_copies, _roux_double,
        _ck_double, _cmtw_multiply, _paley12, _group_ca33, _group_ca88, _ck_ca10, _ck_ca45, _ck_ca51,
        _ck_ca185, _ordered_design, _CCL_TABLE3, _CCL_TABLE4, _two_constant_rows, _od_strength3,
        _affine_maps, _projective_maps, _parse_starter, _from_meagher_stevens, _symbol_group, _cyclic_group,
        _SURVEY_DISTINCT_STARTERS, _MEAGHER_STEVENS_STARTERS, _SEARCHED_COVER_STARTERS,
        _SEARCHED_DISTINCT_STARTERS, _LOBB_STARTERS, _plus, _times, _minus

    "Whether every `t` columns of `A` show every combination of the symbols `0:v-1`. Brute force."
    function is_covering(A::AbstractMatrix{<:Integer}, t::Int, v::Int)
        N, k = size(A)
        (k >= t && all(x -> 0 <= x < v, A)) || return false
        seen = falses(v^t)
        cols = collect(1:t)
        while true
            fill!(seen, false)
            count = 0
            for r in 1:N
                code = 0
                for c in cols
                    code = code * v + A[r, c]
                end
                seen[code + 1] || (seen[code + 1] = true; count += 1)
            end
            count == v^t || return false
            i = t                                   # the next t-subset, in lexicographic order
            while i >= 1 && cols[i] == k - t + i
                i -= 1
            end
            i == 0 && return true
            cols[i] += 1
            for j in (i + 1):t
                cols[j] = cols[j - 1] + 1
            end
        end
    end

    """
    Whether every `t` columns of `A` show every combination when column `c` has
    the symbols `0:sizes[c]-1`, and an entry -1 (a free entry) covers nothing.
    Brute force, with a set of tuples per set of columns.
    """
    function is_mixed_covering(A::AbstractMatrix{<:Integer}, t::Int, sizes::AbstractVector{Int})
        N, k = size(A)
        (k == length(sizes) && k >= t) || return false
        all(A[r, c] == -1 || 0 <= A[r, c] < sizes[c] for r in 1:N, c in 1:k) || return false
        for cols in Iterators.filter(s -> length(s) == t && issorted(s) && allunique(s),
                                     Iterators.product(ntuple(_ -> 1:k, t)...))
            seen = Set{Vector{Int}}()
            for r in 1:N
                row = [A[r, c] for c in cols]
                any(==(-1), row) || push!(seen, row)
            end
            length(seen) == prod(sizes[c] for c in cols) || return false
        end
        return true
    end
    is_pairwise(A, sizes) = is_mixed_covering(A, 2, sizes)

    "The same check through the package's `coverage`, which shares no code with the catalog."
    function through_coverage(A::AbstractMatrix{<:Integer}, t::Int, sizes::AbstractVector{Int})
        rows = [Tuple(A[r, :] .+ 1) for r in axes(A, 1)]
        return iscomplete(coverage(rows, (collect(1:s) for s in sizes)...; strength = t))
    end
    through_coverage(A, t, v::Int) = through_coverage(A, t, fill(v, size(A, 2)))
end


@testitem "catalog: Galois fields are fields, on the first irreducible polynomial" setup=[CatalogSetup] begin
    orders = [q for q in 2:256 if _is_prime_power(q)]
    @test length(orders) == 70
    rng = Xoshiro(0x2026_1004)
    for q in orders
        F = GaloisField(q)
        S = 0:(q - 1)
        @test F.q == q && size(F.add) == size(F.mul) == (q, q)
        @test F.add == permutedims(F.add) && F.mul == permutedims(F.mul)
        @test all(sort(F.add[a + 1, :]) == collect(S) for a in S)
        @test all(sort(F.mul[a + 1, 2:end]) == collect(1:(q - 1)) for a in 1:(q - 1))
        @test all(F.add[1, a + 1] == a && F.mul[2, a + 1] == a && F.mul[1, a + 1] == 0 for a in S)
        @test all(F.add[a + 1, F.neg[a + 1] + 1] == 0 for a in S)
        @test all(F.mul[a + 1, F.inv[a + 1] + 1] == 1 for a in 1:(q - 1))
        # Associativity and distributivity: every triple up to 32, a sample above.
        triples = q <= 32 ? vec(collect(Iterators.product(S, S, S))) :
                  [(rand(rng, S), rand(rng, S), rand(rng, S)) for _ in 1:5_000]
        @test all(triples) do (a, b, c)
            _plus(F, _plus(F, a, b), c) == _plus(F, a, _plus(F, b, c)) &&
                _times(F, _times(F, a, b), c) == _times(F, a, _times(F, b, c)) &&
                _times(F, a, _plus(F, b, c)) == _plus(F, _times(F, a, b), _times(F, a, c))
        end
    end
    # Prime fields are the integers modulo p.
    @test GaloisField(13).mul == [(a * b) % 13 for a in 0:12, b in 0:12]
    # The modulus is the first irreducible one, in the order of its lower
    # coefficients: x^2 + x + 1 for 4, x^3 + x + 1 for 8, x^2 + 1 for 9, and
    # x^8 + x^4 + x^3 + x + 1 for 256, the polynomial of AES, whose standard
    # gives {57} {83} = {c1} (FIPS 197, section 4.2).
    @test _times(GaloisField(4), 2, 2) == 3
    @test _times(GaloisField(8), 4, 2) == 3
    @test _times(GaloisField(9), 3, 3) == 2
    @test _times(GaloisField(256), 0x57, 0x83) == 0xc1
    for q in (1, 6, 12, 257, 512)
        @test_throws ArgumentError GaloisField(q)
    end
    # The primitive cubic's recurrence has period q^3 - 1.
    for q in (2, 3, 4, 5, 7, 8, 9)
        F = GaloisField(q)
        c0, c1, c2 = _primitive_cubic(F)
        state, period = (0, 0, 1), 0
        while true
            a, b, c = state
            state = (b, c, _minus(F, _plus(F, _plus(F, _times(F, c2, c), _times(F, c1, b)), _times(F, c0, a))))
            period += 1
            state == (0, 0, 1) && break
        end
        @test period == q^3 - 1
    end
    # The affine maps are sharply 2-transitive, the projective ones sharply 3-transitive.
    for q in (3, 4, 5, 7)
        F = GaloisField(q)
        maps = _affine_maps(F)
        @test length(maps) == q * (q - 1)
        @test all(count(g -> g[x + 1] == xx && g[y + 1] == yy, maps) == 1
                  for x in 0:(q - 1), y in 0:(q - 1), xx in 0:(q - 1), yy in 0:(q - 1) if x != y && xx != yy)
        @test length(_projective_maps(F)) == q^3 - q
    end
end


@testitem "catalog: every construction builds and covers at small sizes" setup=[CatalogSetup] begin
    let
        # Each construction of plan §5.4's table, at several small sizes, checked by
        # brute force, as verify.jl in the constructions directory does.
        # Kleitman-Spencer (Colbourn 2004, p.127), optimal.
        for (k, N) in ((3, 4), (4, 5), (8, 6), (32, 8), (64, 10), (128, 11), (256, 12))
            A = _kleitman_spencer(k)
            @test size(A) == (N, k) && is_covering(A, 2, 2)
        end
        # Bush (Sherwood 2005, PDF p.3): an orthogonal array, each combination once.
        for (q, t) in ((2, 2), (3, 2), (4, 2), (5, 2), (7, 2), (8, 2), (9, 2), (11, 2), (13, 2), (16, 2),
                       (3, 3), (4, 3), (5, 3), (7, 3), (8, 3), (9, 3), (4, 4), (5, 4))
            A = _bush(GaloisField(q), t)
            @test size(A) == (q^t, q + 1) && is_covering(A, t, q)
            @test _bush(GaloisField(q), t, 3) == A[:, 1:3]     # the first columns alone
        end
        for q in (4, 8)
            A = _bush_even(GaloisField(q))
            @test size(A) == (q^3, q + 2) && is_covering(A, 3, q)
        end
        @test !is_covering(hcat(_bush(GaloisField(5), 3), [(r ÷ 5) % 5 for r in 0:124]), 3, 5)  # odd characteristic
        # Colbourn 2004, Lemma 4.4, and its printed misprints: 112, 512 and 3,773 columns, not 128, 576 and 3,673.
        for (q, r) in ((3, 1), (3, 2), (4, 1), (4, 2), (5, 1), (7, 1))
            A = _lemma44(GaloisField(q), r)
            @test size(A) == ((r + 1) * q^2 - r * q, q^(r + 1) + (r + 1) * q^r) && is_covering(A, 2, q)
        end
        @test size(_lemma44(GaloisField(4), 2), 2) == 112 && size(_lemma44(GaloisField(4), 3), 2) == 512
        @test 7^4 + 4 * 7^3 == 3773
        # CMMSSY 2006, Lemma 3.5: the same rows, more columns.
        @test [_lemma35_columns(3, r) for r in 0:3] == [4, 15, 57, 216]
        for (q, r) in ((3, 1), (3, 2), (4, 1), (5, 1))
            A = _lemma35(GaloisField(q), r)
            @test size(A) == ((r + 1) * q^2 - r * q, _lemma35_columns(q, r)) && is_covering(A, 2, q)
        end
        # The plain product (CMMSSY 2006, Figure 2) and Theorem 3.2's.
        @test size(_product(_bush(GaloisField(3), 2), _bush(GaloisField(3), 2))) == (18, 16)
        @test is_covering(_product(_bush(GaloisField(3), 2), _bush(GaloisField(3), 2)), 2, 3)
        P, KP, _ = _partitioned(_printed(_CMMSSY_FIGURE5), 13:15, 3)
        C, KC = _sca_product(P, KP, _sca_base(GaloisField(3)), (3, 1), 3)
        @test size(C) == (21, 74) && KC == (42, 32) && is_covering(_fill_stars(C), 2, 3)
        # Tripling (Chateauneuf & Kreher 2002, Theorem 4.2) and its idempotent squares.
        for v in 3:13
            L = _idempotent_square(v)
            @test all(L[i, i] == i - 1 for i in 1:v) && all(sort(L[i, :]) == sort(L[:, i]) == collect(0:(v - 1)) for i in 1:v)
        end
        for v in (3, 4, 5, 7)
            A = _od_triple(_bush(GaloisField(v), 2), v)
            @test size(A) == (2v^2 - v, 3 * (v + 1)) && is_covering(A, 2, v)
        end
        A = _od_triple(_fuse(_bush(GaloisField(7), 2), 7), 6)
        @test size(A) == (77, 24) && is_covering(A, 2, 6)
        # Fusion (CKRS 2010, Lemma 3.1), at strengths 2 and 3, column by column.
        for q in (3, 4, 5, 7, 8, 9)
            A = _fuse(_bush(GaloisField(q), 2), q)
            @test size(A) == (q^2 - 2, q + 1) && is_covering(A, 2, q - 1)
            @test _fuse(_bush(GaloisField(q), 2)[:, 1:3], q) == A[:, 1:3]
        end
        @test size(_fused(_bush(GaloisField(7), 2), 7, 2)) == (45, 8) && is_covering(_fused(_bush(GaloisField(7), 2), 7, 2), 2, 5)
        @test size(_fuse(_bush(GaloisField(5), 3), 5)) == (123, 6) && is_covering(_fuse(_bush(GaloisField(5), 3), 5), 3, 4)
        # Derivation (Colbourn 2004, p.128): one strength and one column fewer, at most N / v rows.
        @test size(_derive(_group_ca88(), 4)) == (22, 7) && is_covering(_derive(_group_ca88(), 4), 2, 4)
        @test size(_derive(_group_ca33(), 3)) == (11, 5) && is_covering(_derive(_group_ca33(), 3), 2, 3)
        # The LFSR array (RMS 2014, Theorem 6), its halves and its copies (Shokri & Moura 2025).
        for q in (2, 3, 4, 5, 7)
            F = GaloisField(q)
            A = _lfsr_array(F)
            @test size(A) == (2q^3 - 1, q^2 + q + 1) && is_covering(A, 3, q)
            @test _lfsr_array(F, 4) == A[:, 1:4]
            half, reversed = _lfsr_blocks(F)
            @test size(half) == (q^3, q^2 + q + 1) && is_covering(half, 2, q) && is_covering(reversed, 2, q)
        end
        for q in (3, 4, 5, 7), n in (1, 2)
            F = GaloisField(q)
            D = _difference_covering(F, n)
            @test size(D) == (n * (q - 1) + 1, q^n)
            @test all(length(Set(_plus(F, D[r, a], _minus(F, D[r, b])) for r in axes(D, 1))) == q
                      for a in 1:q^n for b in (a + 1):q^n)
        end
        for (q, x) in ((2, 2), (3, 2), (3, 3), (4, 2), (4, 3), (4, 4), (5, 2), (5, 5))
            A = _lfsr_copies(GaloisField(q), x)
            @test size(A) == (x == 2 ? 4q^3 - 5q^2 + 2q : 5q^3 - 6q^2 + 2q, x * (q^2 + q + 1)) && is_covering(A, 3, q)
        end
        # 485 rows for 155 five-valued parameters (plan §5.4), against 529 in the November 2024 tables.
        @test size(_lfsr_copies(GaloisField(5), 5)) == (485, 155)
        # The small strength-3 arrays.
        for (A, t, v, shape) in ((_paley12(), 3, 2, (12, 11)), (_group_ca33(), 3, 3, (33, 6)), (_group_ca88(), 3, 4, (88, 8)),
                                 (_ck_ca10(), 3, 2, (10, 5)), (_ck_ca45(), 3, 3, (45, 8)), (_ck_ca45()[:, 1:7], 3, 3, (45, 7)),
                                 (_ck_ca51(), 3, 3, (51, 9)), (_ck_ca185(), 3, 5, (185, 10)),
                                 (_CCL_TABLE3, 3, 2, (12, 6)), (_CCL_TABLE4, 3, 2, (13, 10)))
            @test size(A) == shape && is_covering(A, t, v)
        end
        # Colbourn 2004, Figure 2's last row as printed: a misprint, which does not cover.
        @test !is_covering(_group_ca88(; as_printed = true), 3, 4)
        # The Hadamard array needs its row of ones.
        @test !is_covering(vcat(zeros(Int, 1, 11), _paley12()[2:end, :]), 3, 2)
        # The CMTW 2006 recursions: Theorems 3.1, 3.2 and 3.4.
        r22 = _roux_double(_paley12(), _kleitman_spencer(11))
        @test size(r22) == (19, 22) && is_covering(r22, 3, 2)
        @test size(_roux_double(r22, _kleitman_spencer(22))) == (27, 44) && is_covering(_roux_double(r22, _kleitman_spencer(22)), 3, 2)
        A = _ck_double(_group_ca33(), _lemma44(GaloisField(3), 1)[:, 1:6], 3)
        @test size(A) == (63, 12) && is_covering(A, 3, 3)
        A = _ck_double(_lfsr_array(GaloisField(3)), _lemma44(GaloisField(3), 1)[:, 1:13], 3)
        @test size(A) == (83, 26) && is_covering(A, 3, 3)
        A = _cmtw_multiply(_bush(GaloisField(3), 3), _bush(GaloisField(3), 2), GaloisField(3))
        @test size(A) == (63, 12) && is_covering(A, 3, 3)
        A = _cmtw_multiply(_bush(GaloisField(5), 3), _bush(GaloisField(5), 2), GaloisField(5))
        @test size(A) == (325, 30) && is_covering(A, 3, 5)
        # Zero-sum (Chateauneuf & Kreher 2002, Theorem 2.1), for equal and unequal counts.
        for (v, t) in ((2, 2), (3, 2), (6, 2), (10, 2), (2, 3), (3, 3), (6, 3), (3, 4), (6, 4))
            A = _zero_sum(fill(v, t + 1))
            @test size(A) == (v^t, t + 1) && is_covering(A, t, v)
        end
        for sizes in ([5, 4, 3], [6, 4, 2], [8, 5, 5], [7, 7, 2], [5, 4, 3, 2], [6, 5, 4, 3], [4, 4, 3, 3],
                      [8, 4, 4, 2], [5, 4, 3, 3, 2], [3, 3, 3, 1])
            t = length(sizes) - 1
            A = _zero_sum(sizes)
            @test size(A, 1) == prod(sizes[1:t]) && is_mixed_covering(A, t, sizes)
        end
        @test through_coverage(_zero_sum([5, 4, 3, 2]), 3, [5, 4, 3, 2])
        @test_throws ArgumentError _zero_sum([2, 3, 4])
        # The product of two arrays (Chateauneuf & Kreher 2002, p.219).
        A = _symbol_product(_bush(GaloisField(3), 2), _bush(GaloisField(4), 2), 4)
        @test size(A) == (144, 4) && is_covering(A, 2, 12)
        A = _symbol_product(_group_ca33(), _bush_even(GaloisField(4)), 4)
        @test size(A) == (2112, 6) && is_covering(A, 3, 12)
        # Ordered designs: each triple of three different symbols exactly once.
        for q in (2, 3, 4, 5, 7, 8)
            D = _ordered_design(GaloisField(q))
            @test size(D) == (q^3 - q, q + 1)
            @test all(Iterators.product(1:(q + 1), 1:(q + 1), 1:(q + 1))) do (a, b, c)
                (a < b < c) || return true
                tuples = [(D[r, a], D[r, b], D[r, c]) for r in axes(D, 1)]
                allunique(tuples) && all(x -> allunique(x), tuples)
            end
        end
        # Cohen, Colbourn & Ling 2008, Construction 2.
        @test size(_two_constant_rows(_paley12())) == (13, 11) && is_covering(_two_constant_rows(_paley12()), 3, 2)
        for (F, T, k, shape) in ((GaloisField(5), _two_constant_rows(_ck_ca10()), 5, (246, 5)),
                                 (GaloisField(5), _CCL_TABLE3, 6, (276, 6)), (GaloisField(9), _CCL_TABLE4, 10, (1225, 10)))
            A = _od_strength3(F, T, k)
            @test size(A) == shape && is_covering(A, 3, F.q + 1)
        end
        # The arrays CMMSSY 2006 prints, with their free entries, and their partitions (p.128).
        for (text, v, shape, K, sca) in ((_CMMSSY_FIGURE5, 3, (15, 20), (14, 6), true),
                                         (_CMMSSY_FIGURE6[1], 3, (11, 5), (4, 1), true), (_CMMSSY_FIGURE6[2], 3, (12, 7), (4, 3), false),
                                         (_CMMSSY_FIGURE6[3], 3, (13, 9), (6, 3), true), (_CMMSSY_FIGURE7[1], 4, (19, 6), (5, 1), true),
                                         (_CMMSSY_FIGURE7[2], 4, (21, 7), (6, 1), true), (_CMMSSY_FIGURE7[3], 4, (23, 8), (6, 2), false))
            A = _printed(text)
            @test size(A) == shape && is_pairwise(A, fill(v, shape[2]))
            P, KP, issca = _partitioned(A, (shape[1] - v + 1):shape[1], v)
            @test KP == K && issca == sca && is_pairwise(P, fill(v, shape[2]))
            @test all(P[end - v + i, c] == i - 1 for i in 1:v, c in 1:K[1])
        end
        # Projection (Colbourn 2008, Theorem 2.3).
        for (q, t) in ((4, 1), (5, 1), (7, 1), (8, 2), (9, 2), (11, 1), (13, 3))
            A = _projection(GaloisField(q), t; stars = true)
            @test size(A) == (q^2 - t, q + 1 + t) && is_pairwise(A, fill(q - t, q + 1 + t))
            @test is_covering(_projection(GaloisField(q), t), 2, q - t)
        end
    end
end


@testitem "catalog: an array from every stored starter" setup=[CatalogSetup] begin
    let
        # Plan §5.4, "Cover starters are data": 19 + 33 + 141 printed vectors and
        # the searched ones, each developed into an array and checked.
        @test length(_SURVEY_DISTINCT_STARTERS) == 19
        @test length(_MEAGHER_STEVENS_STARTERS) == 33
        @test length(_LOBB_STARTERS) == 144 && length(unique(e.starter for e in _LOBB_STARTERS)) == 141
        @test length(_SEARCHED_COVER_STARTERS) == 14 && length(_SEARCHED_DISTINCT_STARTERS) == 24
        for (v, l, text) in _SURVEY_DISTINCT_STARTERS               # Colbourn 2004, p.131
            A = _distinct_starter_array(_parse_starter(text), v)
            @test size(A) == (l * (v - 1) + v, l + 1) && is_covering(A, 2, v)
        end
        for (v, l, text) in _SEARCHED_DISTINCT_STARTERS
            A = _distinct_starter_array(_parse_starter(text), v)
            @test size(A) == (l * (v - 1) + v, l + 1) && is_covering(A, 2, v)
        end
        for (v, l, text) in _SEARCHED_COVER_STARTERS
            A = _fixed_starter_array(_parse_starter(text), v, 1)
            @test size(A) == (l * (v - 1) + 1, l) && is_covering(A, 2, v)
        end
        for (v, k, text) in _MEAGHER_STEVENS_STARTERS              # Meagher & Stevens 2005, Table II
            A = _fixed_starter_array(_from_meagher_stevens(text), v, 1)
            @test size(A) == (k * (v - 1) + 1, k) && is_covering(A, 2, v)
        end
        # Lobb et al. 2012, Tables 4 to 12. The array on the fixed symbols is the
        # catalog's, so a size is the printed bound with one or two fixed symbols,
        # and at least it with more; 97 of the 144 have the printed size.
        exact = 0
        for e in _LOBB_STARTERS
            s, group = _parse_starter(e.starter, e.group), _symbol_group(e.group)
            @test length(s) == (e.kind === :cover ? e.k : e.k - 1)
            if e.kind === :cover
                inner = e.f >= 2 ? _build(_catalog_entry(2, e.f, e.k)) : nothing
                A = _fixed_starter_array(s, e.v, e.f, inner; group)
                @test size(A, 1) == e.k * (e.v - e.f) + (inner === nothing ? 1 : size(inner, 1))
            else
                @test _is_distinct_starter(s, e.v; group)
                A = _distinct_starter_array(s, e.v; group)
                @test size(A, 1) == e.k * (e.v - 1) + 1
            end
            @test size(A, 2) == e.k && is_covering(A, 2, e.v)
            @test e.f > 2 ? size(A, 1) >= e.rows : size(A, 1) == e.rows
            exact += size(A, 1) == e.rows
        end
        @test exact == 97
        # The misprint in Table 11: printed with 52 entries; read "1 1" as "11".
        misprint = only(e for e in _LOBB_STARTERS if (e.v, e.k) == (20, 51))
        @test length(_parse_starter(misprint.starter)) == 51
        # The two groups that are not cyclic, and the cyclic group as a table.
        for (G, order) in ((_symbol_group(:Z3xZ3), 9), (_symbol_group(:S3), 6))
            m = size(G.op, 1)
            @test m == order && all(G.op[1, a] == a - 1 == G.op[a, 1] for a in 1:m)
            @test all(sort(G.op[a, :]) == collect(0:(m - 1)) for a in 1:m)
            @test all(G.op[G.op[a, b] + 1, c] == G.op[a, G.op[b, c] + 1] for a in 1:m, b in 1:m, c in 1:m)
        end
        S3 = _symbol_group(:S3)
        times(a, b) = S3.op[a + 1, b + 1]
        @test times(times(1, 1), 1) == 0 && times(3, 3) == 0 && times(times(3, 1), 3) == times(1, 1)  # x^3 = y^2 = 1, y x y = x^2
        @test !(S3.op == permutedims(S3.op))                                                           # not abelian
        cyclic = [e for e in _LOBB_STARTERS if e.group === :Zm && e.kind === :cover]
        @test all(_is_fixed_starter(_parse_starter(e.starter), e.v, e.f; group = _cyclic_group(e.v - e.f)) for e in cyclic)
        # A few through the package's coverage, too.
        e = only(x for x in _LOBB_STARTERS if (x.v, x.k) == (8, 13))
        @test through_coverage(_fixed_starter_array(_parse_starter(e.starter, :S3), 8, 2, _kleitman_spencer(13);
                                                    group = _symbol_group(:S3)), 2, 8)
        @test through_coverage(_fixed_starter_array(_from_meagher_stevens(_MEAGHER_STEVENS_STARTERS[1][3]), 6, 1), 2, 6)
        @test !_is_fixed_starter([-1, 0, 0, 0, 0], 3, 1)          # not every quotient at every separation
    end
end


@testitem "catalog: it makes the reference's choice for its 974 shapes" setup=[CatalogSetup] begin
    let
        # test/construction_catalog_table.txt is catalog_table.out of the reference
        # catalog: runs of column counts with one choice. Each choice and size is
        # reproduced from sizes alone, and each array is built and checked.
        t, v = 0, 0
        shapes = 0
        built = 0
        for line in eachline(joinpath(@__DIR__, "construction_catalog_table.txt"))
            m = match(r"^== strength (\d+), (\d+) symbols$", line)
            if m !== nothing
                t, v = parse(Int, m[1]), parse(Int, m[2])
                continue
            end
            m = match(r"^  (\d+)(?:-(\d+))?\s+(\d+)\s+\S+\s+\S+\s+(.+)$", line)
            m === nothing && continue
            first_k = parse(Int, m[1])
            last_k = m[2] === nothing ? first_k : parse(Int, m[2])
            rows, name = parse(Int, m[3]), m[4]
            for k in first_k:last_k
                e = _catalog_entry(t, v, k)
                same = e !== nothing && e.rows == rows && e.name == name
                same || @error "the catalog's choice differs from the reference's" t v k rows name entry = e
                @test same
                @test _catalog_rows(t, v, k) == rows
                A = _build(e)
                ok = size(A) == (rows, k) && is_covering(A, t, v)
                ok || @error "the catalog's array does not cover" t v k name
                @test ok
                shapes += 1
                built += ok
            end
        end
        @test shapes == 974 && built == 974
    end
end


@testitem "catalog: sizes from sizes alone, and what an entry says of itself" setup=[CatalogSetup] begin
    let
        # The catalog's column of plan §2.1's table, and some of §5.4's.
        for (t, v, k, rows) in ((2, 2, 8, 6), (2, 2, 32, 8), (2, 2, 64, 10), (2, 2, 128, 11), (2, 2, 256, 12),
                                (2, 2, 512, 13), (2, 2, 1024, 14), (2, 4, 8, 23), (2, 8, 8, 64), (2, 16, 8, 256),
                                (2, 32, 8, 1024), (2, 64, 8, 4096), (2, 8, 10, 78), (2, 3, 12, 15), (2, 4, 16, 28),
                                (2, 4, 32, 33), (2, 4, 64, 40), (2, 4, 128, 43), (3, 3, 12, 53),
                                (2, 6, 3, 36), (2, 5, 30, 45), (2, 6, 20, 76), (2, 10, 20, 155), (2, 12, 20, 221),
                                (3, 6, 4, 216), (3, 2, 20, 18), (3, 3, 6, 33), (3, 4, 20, 127), (3, 5, 12, 225),
                                (3, 6, 6, 276), (3, 7, 8, 343), (3, 10, 10, 1225), (3, 5, 155, 485))
            @test (@inferred Union{Nothing, Int} _catalog_rows(t, v, k)) == rows
        end
        # Where no entry applies: strength 4 past the Bush array, a strength above
        # the parameters, and strength 1 past t + 1 parameters.
        @test _catalog_rows(4, 3, 20) === nothing
        @test _catalog_rows(3, 5, 2) === nothing
        @test _catalog_rows(1, 4, 5) === nothing && _catalog_rows(1, 4, 2) == 4
        @test _catalog_rows(4, 3, 5) == 81 && _catalog_rows(4, 5, 6) == 625 && _catalog_rows(5, 2, 6) == 32
        @test _catalog_rows(3, 1, 9) == 1 && _catalog_rows(2, 300, 3) == 90_000 && _catalog_rows(2, 300, 4) === nothing
        # Unequal value counts: the zero-sum array on t + 1 or t parameters, any counts.
        e = _catalog_entry(2, [3, 5, 4])
        @test e.rows == 20 && e.sizes == [5, 4, 3] && e.name == "zero-sum"
        @test _catalog_entry(3, [6, 5, 4, 3]).rows == 120 && _catalog_entry(3, [2, 3, 4]).rows == 24
        @test _catalog_entry(2, [3, 3, 2, 2]) === nothing && _catalog_entry(2, [4, 4, 4, 4]).rows == 16
            # What `recommend` can say (plan §5.4, "Balance"; §6.1).
        d = _describe(_catalog_entry(2, 7, 8))
        @test d.family == "Bush orthogonal array" && d.orthogonal && d.rows == d.lower_bound == 49
        @test occursin("Sherwood 2005", d.source)
        d = _describe(_catalog_entry(2, 2, 8))
        @test d.family == "Kleitman-Spencer" && !d.orthogonal && d.rows == 6 && d.lower_bound == 4
        d = _describe(_catalog_entry(2, 10, 12))
        @test d.name == "Bush at 11, fused" && occursin("Lemma 3.1", d.source) && !d.orthogonal
        @test _describe(_catalog_entry(2, [5, 4, 3])).orthogonal == false
        @test _describe(_catalog_entry(2, [5, 4])).orthogonal                   # the full product
        @test _describe(_catalog_entry(3, 3, 20)).family == "Copies of the LFSR array"
        @test _describe(_catalog_entry(2, 3, 40)).family == "Product of partitioned arrays"
        families = Set(_describe(_catalog_entry(t, v, k)).family for t in 2:3 for v in 2:12 for k in t:60)
        @test length(families) >= 15
    end
end
