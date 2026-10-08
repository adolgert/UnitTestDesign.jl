# The catalog of covering-array constructions (plan §5.4): for a strength,
# a number of values and a number of parameters, the smallest array the
# constructions of construction_arrays.jl give, chosen from sizes alone.
# Choosing builds nothing; it returns a `CatalogEntry`, a recipe whose
# ingredients (inner arrays, factors, the halves of a recursion) are entries
# chosen from the catalog itself, so the entries chain. `_build` follows the
# recipe. This is `catalog.jl` of design/20261003_solver_plan_constructions/,
# ported: the same candidates in the same order, so the same choice and the
# same size for every shape (test/test_catalog.jl checks the 974 shapes
# of its catalog_table.out). Phase 3's `recommend` and `Auto` read entries
# (`_catalog_entry`, `_describe`) and the benchmark tables read sizes
# (`_catalog_rows`).

"""
    CatalogEntry

One choice of the catalog (plan §5.4) and how to build it, without building
it. `rows` is the size the array will have, for `k` columns of `v` symbols at
strength `t`; `name` says which construction, as the reference catalog
names it ("Bush at 11, fused", "partitioned product: orthogonal array x
CMMSSY Figure 5"). The rest is the recipe `_build` follows: `kind`, the
builder; `q`, the field or symbol count it is built on; `fused`, the
fusions from `q` symbols down to `v` (CKRS 2010, Lemma 3.1); `n`, a count the
kind needs (Lemma 3.5's r, the LFSR copies, a starter's index in its table,
a product's second symbol count); `parts`, the ingredients, entries chosen
from the catalog. A partitioned array, an ingredient of the products of
CMMSSY 2006, has `k = k1 + k2` columns, `k1` of them in its first group, and
`issca` when it is an SCA (CMMSSY 2006, p.128). `sizes` are the value counts
of a zero-sum array's columns when they differ, largest first; otherwise
empty.
"""
struct CatalogEntry
    kind::Symbol
    t::Int
    v::Int
    k::Int
    rows::Int
    name::String
    q::Int
    fused::Int
    n::Int
    k1::Int
    issca::Bool
    sizes::Vector{Int}
    parts::Vector{CatalogEntry}
end

_entry(kind::Symbol, t::Int, v::Int, k::Int, rows::Int, name::AbstractString; q::Int = 0, fused::Int = 0,
       n::Int = 0, k1::Int = 0, issca::Bool = false, sizes::Vector{Int} = Int[],
       parts::Vector{CatalogEntry} = CatalogEntry[]) =
    CatalogEntry(kind, t, v, k, rows, String(name), q, fused, n, k1, issca, sizes, parts)

"""
    _CatalogMemo()

The choices made during one lookup, so that an ingredient asked for twice is
chosen once: entries by `(t, v, k)`, the binary strength-3 arrays with two
constant rows by `k`, the partitioned products by `(k, v)` and the
partitioned arrays on `v` symbols. It lives for one call; nothing is cached
between calls, so lookups from different tasks share nothing.
"""
struct _CatalogMemo
    entries::Dict{Tuple{Int, Int, Int}, Union{Nothing, CatalogEntry}}
    binary::Dict{Int, CatalogEntry}
    wide::Dict{Tuple{Int, Int}, Union{Nothing, CatalogEntry}}
    atoms::Dict{Int, Vector{CatalogEntry}}
end

_CatalogMemo() = _CatalogMemo(Dict{Tuple{Int, Int, Int}, Union{Nothing, CatalogEntry}}(), Dict{Int, CatalogEntry}(),
                              Dict{Tuple{Int, Int}, Union{Nothing, CatalogEntry}}(), Dict{Int, Vector{CatalogEntry}}())

"""
    _catalog_entry(t, v, k) -> Union{Nothing, CatalogEntry}

The smallest array the catalog gives for `k` parameters of `v` values at
strength `t`, from sizes alone (plan §5.4), or `nothing` when no entry
applies. Strengths 2 and 3 have an entry for every shape with at most 256
values; strength 1, strengths above 3 and more than 256 values have the
zero-sum array on at most t + 1 columns, and the strengths above 3 the Bush
array, fused, on at most q + 1. One value is one row at any strength. Ties
go to the candidate offered first, as in the reference catalog.
"""
_catalog_entry(t::Integer, v::Integer, k::Integer) = _catalog_entry(_CatalogMemo(), Int(t), Int(v), Int(k))

function _catalog_entry(memo::_CatalogMemo, t::Int, v::Int, k::Int)
    (t >= 1 && v >= 1 && k >= t) || return nothing
    key = (t, v, k)
    haskey(memo.entries, key) && return memo.entries[key]
    # Past the largest field only the zero-sum array is left (`_strength_other`).
    entry = v == 1 ? _entry(:one_row, t, 1, k, 1, "one row") :
            v > _FIELD_LIMIT ? _strength_other(memo, t, k, v) :
            t == 2 ? _pairwise(memo, k, v) :
            t == 3 ? _strength3(memo, k, v) : _strength_other(memo, t, k, v)
    memo.entries[key] = entry
    return entry
end

"An ingredient the catalog always has: strengths 2 and 3, any v and k >= t."
_ingredient(memo::_CatalogMemo, t::Int, v::Int, k::Int) = _catalog_entry(memo, t, v, k)::CatalogEntry

"""
    _catalog_entry(t, arity::AbstractVector) -> Union{Nothing, CatalogEntry}

The catalog's array for parameters with these value counts: the uniform
lookup when every count is the same, and otherwise the zero-sum array when
there are at most `t + 1` parameters, which is exact for any value counts
(plan §5.4: "Mixed levels are left to IPOG and the reducer, except for t + 1
parameters"). Its `sizes` are the counts largest first; `cover_ordinary`
puts each column back on its parameter.
"""
function _catalog_entry(t::Integer, arity::AbstractVector{<:Integer})
    k = length(arity)
    isempty(arity) && return nothing
    allequal(arity) && return _catalog_entry(t, first(arity), k)
    (1 <= t && t <= k <= t + 1) || return nothing
    sizes = sort!(collect(Int, arity); rev = true)
    k == t && push!(sizes, 1)           # a column of one value: the zero-sum array is the full product
    rows = _checked_product(view(sizes, 1:t))
    rows === nothing && return nothing
    return _entry(:zero_sum, Int(t), sizes[1], k, rows, "zero-sum"; sizes)
end

"""
    _catalog_rows(t, v, k) -> Union{Nothing, Int}

The catalog's size for `k` parameters of `v` values at strength `t`, or
`nothing` when no entry applies (`_catalog_entry`). The benchmark's
reference table reads it (benchmark/best_known/BestKnown.jl, plan §7.1).
"""
function _catalog_rows(t::Integer, v::Integer, k::Integer)
    entry = _catalog_entry(t, v, k)
    return entry === nothing ? nothing : entry.rows
end

"`q^t`, or `nothing` past `typemax(Int)`."
function _checked_power(q::Int, t::Int)
    r = 1
    for _ in 1:t
        r, over = Base.Checked.mul_with_overflow(r, q)
        over && return nothing
    end
    return r
end

"The product of `sizes`, or `nothing` past `typemax(Int)`."
function _checked_product(sizes::AbstractVector{Int})
    r = 1
    for s in sizes
        r, over = Base.Checked.mul_with_overflow(r, s)
        over && return nothing
    end
    return r
end

"The first of the fewest rows, so that the order the candidates are offered in breaks ties."
_smallest(candidates::Vector{CatalogEntry}) = candidates[argmin([c.rows for c in candidates])]

"The first `count` prime powers from `v` that have a field here (`_FIELD_LIMIT`); fewer near the limit."
function _prime_powers_from(v::Int, count::Int)
    out = Int[]
    q = max(v, 2)
    while length(out) < count && q <= _FIELD_LIMIT
        _is_prime_power(q) && push!(out, q)
        q += 1
    end
    return out
end

"How the reference names an array built on `q` symbols and fused `d` times down to fewer."
_fused_name(name::AbstractString, q::Int, d::Int) =
    d == 0 ? String(name) : "$name at $q, fused" * (d == 1 ? "" : " $d times")


## Strength 2

function _pairwise(memo::_CatalogMemo, k::Int, v::Int)
    candidates = CatalogEntry[]
    if v == 2
        push!(candidates, _entry(:kleitman_spencer, 2, 2, k, _kleitman_spencer_rows(k), "Kleitman-Spencer"))
        return _smallest(candidates)
    end
    k <= 3 && push!(candidates, _entry(:zero_sum, 2, v, k, v^2, "zero-sum"))
    for q in _prime_powers_from(v, 2)
        d = q - v
        k <= q + 1 && push!(candidates, _entry(:bush, 2, v, k, q^2 - 2d, _fused_name("Bush", q, d); q, fused = d))
        d == 0 && continue                      # for a prime power v, `_wide` below has the products
        r = 1
        while _lemma35_columns(q, r) < k
            r += 1
        end
        push!(candidates, _entry(:lemma35, 2, v, k, (r + 1) * q^2 - r * q - 2d,
                                 _fused_name("Lemma 3.5 (r = $r)", q, d); q, fused = d, n = r))
    end
    # No array has fewer than v^2 rows, and a tie goes to the first candidate,
    # so an array at v^2 already offered is the choice: the rest need not be
    # weighed. Only the time changes (Auto looks up small shapes often).
    any(c -> c.rows == v^2, candidates) && return _smallest(candidates)
    wide = _wide(memo, k, v)
    if wide !== nothing
        name = occursin(" x ", wide.name) ? "partitioned product: " * wide.name : wide.name
        push!(candidates, _entry(:wide, 2, v, k, wide.rows, name; parts = [wide]))
    end
    _starters!(candidates, memo, k, v)
    _products!(candidates, memo, 2, k, v)
    if k >= 6
        third = cld(k, 3)
        inner = _ingredient(memo, 2, v, third)
        push!(candidates, _entry(:tripling, 2, v, k, inner.rows + v * (v - 1), "tripling from $third columns";
                                 parts = [inner]))
    end
    return _smallest(candidates)
end

# The cover starters (Colbourn 2004, p.130-131, p.139; Meagher & Stevens 2005;
# Lobb et al. 2012) that give at least k columns of v symbols, in the
# reference's order: the searched ones, the distinct ones (searched, then
# Colbourn 2004's), Meagher & Stevens's, and Lobb et al.'s in table order.
function _starters!(candidates::Vector{CatalogEntry}, memo::_CatalogMemo, k::Int, v::Int)
    for (i, (g, l, _)) in enumerate(_SEARCHED_COVER_STARTERS)
        (g == v && l >= k) || continue
        push!(candidates, _entry(:searched_cover, 2, v, k, l * (v - 1) + 1, "cover starter, $l columns"; n = i))
    end
    for (kind, table, name) in ((:searched_distinct, _SEARCHED_DISTINCT_STARTERS, "distinct starter"),
                                (:survey_distinct, _SURVEY_DISTINCT_STARTERS, "distinct starter (Colbourn 2004)"))
        for (i, (g, l, _)) in enumerate(table)
            (g == v && l + 1 >= k) || continue
            push!(candidates, _entry(kind, 2, v, k, l * (v - 1) + v, "$name, $(l + 1) columns"; n = i))
        end
    end
    for (i, (g, l, _)) in enumerate(_MEAGHER_STEVENS_STARTERS)
        (g == v && l >= k) || continue
        push!(candidates, _entry(:meagher_stevens, 2, v, k, l * (v - 1) + 1, "Meagher-Stevens starter, $l columns";
                                 n = i))
    end
    for (i, e) in enumerate(_LOBB_STARTERS)
        (e.v == v && e.k >= k) || continue
        if e.kind !== :cover
            push!(candidates, _entry(:lobb_distinct, 2, v, k, e.k * (v - 1) + 1, "Lobb distinct starter, $(e.k) columns";
                                     n = i))
        elseif e.f == 1
            push!(candidates, _entry(:lobb_cover, 2, v, k, e.k * (v - 1) + 1, "Lobb starter, $(e.k) columns"; n = i))
        else
            inner = _ingredient(memo, 2, e.f, e.k)            # the array on the fixed symbols
            push!(candidates, _entry(:lobb_cover, 2, v, k, e.k * (v - e.f) + inner.rows,
                                     "Lobb starter, $(e.k) columns, $(e.f) fixed"; n = i, parts = [inner]))
        end
    end
    return candidates
end

# For v = a b, the product of the arrays for a and for b symbols (Chateauneuf
# & Kreher 2002, p.219), at strength t.
function _products!(candidates::Vector{CatalogEntry}, memo::_CatalogMemo, t::Int, k::Int, v::Int)
    for a in 2:isqrt(v)
        v % a == 0 || continue
        b = v ÷ a
        ca, cb = _ingredient(memo, t, a, k), _ingredient(memo, t, b, k)
        push!(candidates, _entry(:symbol_product, t, v, k, ca.rows * cb.rows, "product of $a and $b symbols";
                                 n = b, parts = [ca, cb]))
    end
    return candidates
end


## Strength 2, many columns: products of partitioned arrays (CMMSSY 2006, Theorems 3.2 and 3.3)

"The partitioned arrays on v symbols that the catalog has, each from one construction (CMMSSY 2006, p.128)."
function _partitioned_atoms(memo::_CatalogMemo, v::Int)
    haskey(memo.atoms, v) && return memo.atoms[v]
    atoms = CatalogEntry[]
    _is_prime_power(v) && v <= _FIELD_LIMIT &&
        push!(atoms, _entry(:oa_sca, 2, v, v + 1, v^2, "orthogonal array"; q = v, k1 = v, issca = true))
    # A distinct starter of length l gives an SCA on l + 1 columns; a later
    # table's starter of the same length replaces an earlier one's, as in the
    # reference. Each has the same size.
    starters = Dict{Int, CatalogEntry}()
    for (kind, table) in ((:searched_distinct, _SEARCHED_DISTINCT_STARTERS),
                          (:survey_distinct, _SURVEY_DISTINCT_STARTERS))
        for (i, (g, l, _)) in enumerate(table)
            g == v && (starters[l] = _entry(kind, 2, v, l + 1, l * (v - 1) + v, "distinct starter"; n = i))
        end
    end
    for (i, e) in enumerate(_LOBB_STARTERS)
        (e.v == v && e.kind !== :cover) || continue
        starters[e.k - 1] = _entry(:lobb_distinct, 2, v, e.k, e.k * (v - 1) + 1, "Lobb distinct starter"; n = i)
    end
    for l in sort!(collect(keys(starters)))
        push!(atoms, _entry(:special_rows, 2, v, l + 1, l * (v - 1) + v, "distinct starter on $(l + 1) columns";
                            k1 = l, issca = true, parts = [starters[l]]))
    end
    # The arrays CMMSSY 2006 prints, Figures 5-7: (name, figure, k1, k2, issca).
    printed = v == 3 ? (("CMMSSY Figure 5", 1, 14, 6, true), ("CMMSSY Figure 6a", 2, 4, 1, true),
                        ("CMMSSY Figure 6b", 3, 4, 3, false), ("CMMSSY Figure 6c", 4, 6, 3, true)) :
              v == 4 ? (("CMMSSY Figure 7a", 5, 5, 1, true), ("CMMSSY Figure 7b", 6, 6, 1, true),
                        ("CMMSSY Figure 7c", 7, 6, 2, false)) : ()
    for (name, figure, k1, k2, issca) in printed
        rows = size(_printed(_CMMSSY_PRINTED[figure]), 1)
        push!(atoms, _entry(:printed, 2, v, k1 + k2, rows, name; n = figure, k1, issca))
    end
    # Projection (Colbourn 2008, Theorem 2.3): the rows (0, j) of the projected
    # array come first and are constant on every column.
    for q in _prime_powers_from(v + 1, 2)
        t = q - v
        push!(atoms, _entry(:projection_pca, 2, v, q + 1 + t, q^2 - t, "projection at $q";
                            q, k1 = q + 1 + t, issca = true))
    end
    memo.atoms[v] = atoms
    return atoms
end

"Figures 5, 6a-c and 7a-c of CMMSSY 2006, as `:printed` entries number them."
const _CMMSSY_PRINTED = (_CMMSSY_FIGURE5, _CMMSSY_FIGURE6..., _CMMSSY_FIGURE7...)

# Theorem 3.2: a PCA times an SCA.
_times(x::CatalogEntry, y::CatalogEntry, v::Int) =
    _entry(:sca_times, 2, v, x.k1 * y.k1 + x.k1 * (y.k - y.k1) + (x.k - x.k1) * y.k1, x.rows + y.rows - v,
           x.name * " x " * y.name; k1 = x.k1 * y.k1, issca = x.issca, parts = [x, y])

# Theorem 3.3 with the orthogonal array on the right: the rows from its lines
# of slope 1 become the special rows.
_times_wide(x::CatalogEntry, base::CatalogEntry, v::Int) =
    _entry(:sca_times_wide, 2, v, v * x.k + x.k1, x.rows + base.rows - v,
           x.name * " x orthogonal array (Theorem 3.3)"; k1 = v * x.k, issca = true, parts = [x, base])

# One step of `_wide`'s search: keep `z` unless it has as many rows as the
# best so far, or a kept array has no more rows, as many columns in its
# first group and in all, and is an SCA if `z` is. Returns the new best.
function _offer!(next::Vector{CatalogEntry}, kept::Vector{CatalogEntry}, best::Union{Nothing, CatalogEntry},
                 z::CatalogEntry, k::Int)
    best !== nothing && z.rows >= best.rows && return best
    for w in kept
        w.rows <= z.rows && w.k1 >= z.k1 && w.k >= z.k && (w.issca || !z.issca) && return best
    end
    push!(kept, z)
    z.k >= k && return z
    push!(next, z)
    return best
end

"""
    _wide(memo, k, v) -> Union{Nothing, CatalogEntry}

The fewest rows for at least `k` columns of `v` symbols over products of the
partitioned arrays (CMMSSY 2006, Theorems 3.2 and 3.3), or `nothing` when
there are none: a breadth-first search over products of the atoms
(`_partitioned_atoms`), each step multiplying by an SCA or, for a prime
power, widening by the orthogonal array, keeping only arrays no kept one
dominates.
"""
function _wide(memo::_CatalogMemo, k::Int, v::Int)
    haskey(memo.wide, (k, v)) && return memo.wide[(k, v)]
    atoms = _partitioned_atoms(memo, v)
    scas = filter(a -> a.issca, atoms)
    base = !isempty(atoms) && atoms[1].kind === :oa_sca ? atoms[1] : nothing
    best = nothing
    kept = CatalogEntry[]
    frontier = CatalogEntry[]
    for a in sort(atoms; by = a -> a.rows, alg = MergeSort)   # stable: ties keep the atoms' order
        best = _offer!(frontier, kept, best, a, k)
    end
    while !isempty(frontier)
        next = CatalogEntry[]
        for x in frontier
            for y in scas
                best = _offer!(next, kept, best, _times(x, y, v), k)
            end
            base === nothing || (best = _offer!(next, kept, best, _times_wide(x, base, v), k))
        end
        frontier = next
    end
    memo.wide[(k, v)] = best
    return best
end


## Strength 3

"""
    _binary_constant(memo, k) -> CatalogEntry

The smallest CA(N; 3, k, 2) on hand whose first two rows are constant, 0 and
1: the ingredient of the ordered design (Cohen, Colbourn & Ling 2008,
Construction 2).
"""
function _binary_constant(memo::_CatalogMemo, k::Int)
    haskey(memo.binary, k) && return memo.binary[k]
    candidates = CatalogEntry[]
    k <= 4 && push!(candidates, _entry(:constant_rows, 3, 2, k, 8, "zero-sum";
                                       parts = [_entry(:zero_sum, 3, 2, 4, 8, "zero-sum")]))
    k <= 5 && push!(candidates, _entry(:constant_rows, 3, 2, k, 10, "Chateauneuf-Kreher Figure 4";
                                       parts = [_entry(:ck_ca10, 3, 2, 5, 10, "Chateauneuf-Kreher Figure 4")]))
    k <= 6 && push!(candidates, _entry(:ccl_table3, 3, 2, k, 12, "Cohen-Colbourn-Ling Table 3"))
    k <= 10 && push!(candidates, _entry(:ccl_table4, 3, 2, k, 13, "Cohen-Colbourn-Ling Table 4"))
    k <= 11 && push!(candidates, _entry(:constant_rows, 3, 2, k, 13, "Hadamard 12 and a complement";
                                        parts = [_entry(:paley12, 3, 2, 11, 12, "Hadamard 12")]))
    if k >= 5
        half = cld(k, 2)
        c3, c2 = _binary_constant(memo, half), _ingredient(memo, 2, 2, half)
        # the doubled rows (c, c) keep the two constant rows first
        push!(candidates, _entry(:roux_double, 3, 2, k, c3.rows + c2.rows, "Roux doubling from $half columns";
                                 parts = [c3, c2]))
    end
    best = _smallest(candidates)
    memo.binary[k] = best
    return best
end

function _strength3(memo::_CatalogMemo, k::Int, v::Int)
    candidates = CatalogEntry[]
    k <= 4 && push!(candidates, _entry(:zero_sum, 3, v, k, v^3, "zero-sum"))
    if v == 2
        k <= 5 && push!(candidates, _entry(:ck_ca10, 3, 2, k, 10, "Chateauneuf-Kreher Figure 4"))
        k <= 11 && push!(candidates, _entry(:paley12, 3, 2, k, 12, "Hadamard 12"))
    else
        for q in _prime_powers_from(v, 2)
            d = q - v
            q >= 3 && k <= q + 1 &&
                push!(candidates, _entry(:bush, 3, v, k, q^3 - 2d, _fused_name("Bush", q, d); q, fused = d))
            iseven(q) && q >= 4 && k <= q + 2 &&
                push!(candidates, _entry(:bush_even, 3, v, k, q^3 - 2d, _fused_name("Bush, even q", q, d);
                                         q, fused = d))
            k <= q^2 + q + 1 &&
                push!(candidates, _entry(:lfsr, 3, v, k, 2q^3 - 1 - 2d, _fused_name("LFSR", q, d); q, fused = d))
        end
        # As in `_pairwise`: an array at v^3 already offered is the choice.
        any(c -> c.rows == v^3, candidates) && return _smallest(candidates)
        v == 3 && k <= 6 && push!(candidates, _entry(:group_ca33, 3, 3, k, 33, "group array"))
        v == 3 && k <= 8 && push!(candidates, _entry(:ck_ca45, 3, 3, k, 45, "Chateauneuf-Kreher Figure 7"))
        v == 3 && k <= 9 && push!(candidates, _entry(:ck_ca51, 3, 3, k, 51, "Chateauneuf-Kreher Figure 8"))
        v == 4 && k <= 8 && push!(candidates, _entry(:group_ca88, 3, 4, k, 88, "group array"))
        v == 5 && k <= 10 && push!(candidates, _entry(:ck_ca185, 3, 5, k, 185, "Chateauneuf-Kreher Figure 5"))
        if _is_prime_power(v - 1) && v - 1 <= _FIELD_LIMIT && k <= v
            q = v - 1
            T = _binary_constant(memo, k)
            push!(candidates, _entry(:ordered_design, 3, v, k, q^3 - q + binomial(v, 2) * (T.rows - 2) + v,
                                     "ordered design"; q, parts = [T]))
        end
    end
    v >= 4 && _products!(candidates, memo, 3, k, v)
    _lfsr_copies!(candidates, memo, k, v)
    if k >= 5
        half = cld(k, 2)
        c3, c2 = _ingredient(memo, 3, v, half), _ingredient(memo, 2, v, half)
        if v == 2
            push!(candidates, _entry(:roux_double, 3, 2, k, c3.rows + c2.rows, "Roux doubling from $half columns";
                                     parts = [c3, c2]))
        else
            push!(candidates, _entry(:ck_double, 3, v, k, c3.rows + (v - 1) * c2.rows, "doubling from $half columns";
                                     parts = [c3, c2]))
        end
        part = cld(k, v)
        if v >= 3 && _is_prime_power(v) && v <= _FIELD_LIMIT && part >= 3
            m3, m2 = _ingredient(memo, 3, v, part), _ingredient(memo, 2, v, part)
            push!(candidates, _entry(:cmtw_multiply, 3, v, k, m3.rows + (v - 1) * m2.rows + v^3 - v^2,
                                     "multiplying by $v from $part columns"; q = v, parts = [m3, m2]))
        end
    end
    return _smallest(candidates)
end

# Copies of the LFSR array side by side (Shokri & Moura 2025, Theorems 4.6 to
# 4.8), on q symbols for the first prime power q >= v, fused down to v. More
# than q copies take a difference covering array on q^n columns and, below,
# a strength-3 array on the copies, from the catalog.
function _lfsr_copies!(candidates::Vector{CatalogEntry}, memo::_CatalogMemo, k::Int, v::Int)
    qs = _prime_powers_from(v, 1)
    isempty(qs) && return candidates
    q = only(qs)
    d = q - v
    width = q^2 + q + 1
    x = cld(k, width)
    x >= 2 || return candidates
    name = _fused_name("LFSR array, $x copies", q, d)
    if x <= q
        rows = 2q^3 + (q - 2) * (2q^2 - q) + (x == 2 ? 0 : q^3 - q^2)
        push!(candidates, _entry(:lfsr_copies, 3, v, k, rows - 2d, name; q, fused = d, n = x))
    else
        n = _difference_power(q, x)
        inner = _ingredient(memo, 3, q, x)
        rows = 2q^3 + (n * (q - 1) - 1) * (2q^2 - q) + inner.rows
        push!(candidates, _entry(:lfsr_copies_general, 3, v, k, rows - 2d, name;
                                 q, fused = d, n = x, parts = [inner]))
    end
    return candidates
end

"The least n >= 2 with q^n >= x: the difference covering array that gives x copies."
function _difference_power(q::Int, x::Int)
    n = 2
    while q^n < x
        n += 1
    end
    return n
end


## Strength 1 and strengths above 3

# The zero-sum array, and the Bush array on the first three prime powers
# from max(v, t), fused down to v. Phase 2 leaves out the strength-4 arrays
# from Möbius planes (Shokri, Moura & Stevens 2025), which the reference's
# `strength4` offers (plan §5.7, later).
function _strength_other(memo::_CatalogMemo, t::Int, k::Int, v::Int)
    candidates = CatalogEntry[]
    if k <= t + 1
        rows = _checked_power(v, t)
        rows === nothing || push!(candidates, _entry(:zero_sum, t, v, k, rows, "zero-sum"))
    end
    if t >= 2
        for q in _prime_powers_from(max(v, t), 3)
            d = q - v
            rows = _checked_power(q, t)
            (k <= q + 1 && rows !== nothing) || continue
            push!(candidates, _entry(:bush, t, v, k, rows - 2d, _fused_name("Bush", q, d); q, fused = d))
        end
    end
    return isempty(candidates) ? nothing : _smallest(candidates)
end


## Building

"""
    _build(entry) -> Matrix{Int}

The array `entry` describes: rows × columns, symbols `0:v-1`, exactly
`entry.k` columns (a partitioned array has its `k1 + k2`, in partitioned
form: first group first, special rows last). Its ingredients are built from
their own entries. Deterministic: the same entry gives the same array. A
product of partitioned arrays, and Lemma 3.5's, is built only on the columns
it keeps (`_partitioned_columns`): cut from the whole product, 80 columns of
64 values cost 533 MiB for a 5 MiB array (review of Phase 2, finding 4).
"""
function _build(e::CatalogEntry)::Matrix{Int}
    A = _build_full(e)
    return size(A, 2) == e.k ? A : A[:, 1:e.k]
end

function _build_full(e::CatalogEntry)::Matrix{Int}
    kind, v, k = e.kind, e.v, e.k
    kind === :one_row && return zeros(Int, 1, k)
    kind === :kleitman_spencer && return _kleitman_spencer(k)
    if kind === :zero_sum
        isempty(e.sizes) && return _zero_sum(fill(v, e.t + 1))
        return _zero_sum(e.sizes)
    end
    kind === :bush && return _fused(_bush(GaloisField(e.q), e.t, k), e.q, e.fused)
    kind === :bush_even && return _fused(_bush_even(GaloisField(e.q), k), e.q, e.fused)
    kind === :lemma35 && return _fused(_partitioned_columns(_lemma35_entry(e.q, e.n), 1:k), e.q, e.fused)
    kind === :lfsr && return _fused(_lfsr_array(GaloisField(e.q), k), e.q, e.fused)
    kind === :wide && return _fill_stars!(_partitioned_columns(e.parts[1], 1:k))
    kind === :tripling && return _od_triple(_build(e.parts[1]), v)
    kind === :symbol_product && return _symbol_product(_build(e.parts[1]), _build(e.parts[2]), e.n)
    kind === :searched_cover && return _fixed_starter_array(_parse_starter(_SEARCHED_COVER_STARTERS[e.n][3]), v, 1)
    kind === :searched_distinct &&
        return _distinct_starter_array(_parse_starter(_SEARCHED_DISTINCT_STARTERS[e.n][3]), v)
    kind === :survey_distinct && return _distinct_starter_array(_parse_starter(_SURVEY_DISTINCT_STARTERS[e.n][3]), v)
    kind === :meagher_stevens &&
        return _fixed_starter_array(_from_meagher_stevens(_MEAGHER_STEVENS_STARTERS[e.n][3]), v, 1)
    if kind === :lobb_distinct || kind === :lobb_cover
        s = _LOBB_STARTERS[e.n]
        starter, group = _parse_starter(s.starter, s.group), _symbol_group(s.group)
        kind === :lobb_distinct && return _distinct_starter_array(starter, v; group)
        inner = s.f == 1 ? nothing : _build(e.parts[1])
        return _fixed_starter_array(starter, v, s.f, inner; group)
    end
    # Strength 3
    kind === :ck_ca10 && return _ck_ca10()
    kind === :paley12 && return _paley12()
    kind === :group_ca33 && return _group_ca33()
    kind === :ck_ca45 && return _ck_ca45()
    kind === :ck_ca51 && return _ck_ca51()
    kind === :group_ca88 && return _group_ca88()
    kind === :ck_ca185 && return _ck_ca185()
    kind === :ccl_table3 && return copy(_CCL_TABLE3)
    kind === :ccl_table4 && return copy(_CCL_TABLE4)
    kind === :constant_rows && return _two_constant_rows(_build(e.parts[1]))
    kind === :ordered_design && return _od_strength3(GaloisField(e.q), _build(e.parts[1]), k)
    kind === :lfsr_copies && return _fused(_lfsr_copies(GaloisField(e.q), e.n)[:, 1:k], e.q, e.fused)
    if kind === :lfsr_copies_general
        F = GaloisField(e.q)
        A, Ar = _lfsr_blocks(F)
        width = e.q^2 + e.q + 1
        D = _difference_covering(F, _difference_power(e.q, e.n))[:, 1:e.n]
        C = _shokri_general([A, Ar], _lemma44(F, 1)[:, 1:width], D, _build(e.parts[1]), F)
        return _fused(C[:, 1:k], e.q, e.fused)
    end
    kind === :roux_double && return _roux_double(_build(e.parts[1]), _build(e.parts[2]))
    kind === :ck_double && return _ck_double(_build(e.parts[1]), _build(e.parts[2]), v)
    kind === :cmtw_multiply && return _cmtw_multiply(_build(e.parts[1]), _build(e.parts[2]), GaloisField(e.q))
    # Partitioned arrays, the products' ingredients (CMMSSY 2006, p.128)
    kind === :oa_sca && return _sca_base(GaloisField(e.q))
    kind === :special_rows && return _special_rows_last(_build(e.parts[1]), v, (e.k1, k - e.k1))
    kind === :printed && return _special_rows_last(_printed(_CMMSSY_PRINTED[e.n]), v, (e.k1, k - e.k1))
    kind === :projection_pca &&
        return first(_partitioned(_projection(GaloisField(e.q), e.q - v; stars = true), 1:v, v))
    (kind === :sca_times || kind === :sca_times_wide) && return _partitioned_columns(e, 1:k)
    error("internal error: no builder for a catalog entry of kind $(repr(kind))")
end

"""
    _partitioned_columns(entry, cols) -> Matrix{Int}

Columns `cols` (increasing) of the partitioned array `entry`, one of
`_wide`'s atoms or products, entry for entry those of the whole array. A
product (CMMSSY 2006, Theorems 3.2 and 3.3) builds only those columns, from
only the columns of its first factor they are made of (`_sca_pair`); its
second factor is an atom, built whole. So a product cut to `k` columns costs
about the `k` columns, where the whole product has up to `v` times as many
(4,224 columns for 80 parameters of 64 values).
"""
function _partitioned_columns(e::CatalogEntry, cols::AbstractVector{Int})::Matrix{Int}
    e.kind === :sca_times && return _product_columns(e.parts[1], _build(e.parts[2]), e.parts[2], e.v, cols)
    e.kind === :sca_times_wide && return _wide_product_columns(e, cols)
    A = _build(e)
    return cols == axes(A, 2) ? A : A[:, cols]
end

# Columns `cols` of the product (Theorem 3.2) of the PCA `x` and the SCA `B`
# that the atom `y` builds, built from the columns of `x` they need.
function _product_columns(x::CatalogEntry, B::Matrix{Int}, y::CatalogEntry, v::Int, cols::AbstractVector{Int})
    K, L = (x.k1, x.k - x.k1), (y.k1, y.k - y.k1)
    acols = sort!(unique!([last(_sca_pair(c, K, L)) for c in cols]))
    return _sca_product_columns(_partitioned_columns(x, acols), acols, K, B, L, v, cols)
end

"""
    _wide_product_columns(entry, cols) -> Matrix{Int}

Columns `cols` (increasing) of a `:sca_times_wide` entry (Theorem 3.3,
`_times_wide`): the product of `x` with the orthogonal array `base`, put in
partitioned form (`_partitioned`) with the product's rows from the base's
lines of slope 1 as its special rows. Those rows of a product column are
rows of its column f of the base, so which group the column goes into
depends on f alone, and the columns of the result, the first group's in
product order and then the second's, are listed without building the
product. Only the product columns kept are built and partitioned; the
partition of each column is its own, so they are the whole result's columns.
"""
function _wide_product_columns(e::CatalogEntry, cols::AbstractVector{Int})
    x, base, v = e.parts[1], e.parts[2], e.v
    K, L = (x.k1, x.k - x.k1), (base.k1, base.k - base.k1)
    B = _build(base)
    slope = (size(B, 1) - v^2 + 1):(size(B, 1) - v^2 + v)    # the special rows, as rows of B
    (first(slope) >= 1 && last(slope) <= size(B, 1) - v) ||
        error("internal error: Theorem 3.3 needs a base of v^2 rows")
    firsts = [_first_group(view(B, slope, f)) for f in axes(B, 2)]
    n1 = sum(f -> firsts[f] ? (f <= L[1] ? K[1] + K[2] : K[1]) : 0, axes(B, 2))    # product columns with each f
    (n1 == e.k1 && _sca_width(K, L) == e.k) ||
        error("internal error: Theorem 3.3 gives $n1 of $(_sca_width(K, L)) columns in the first group, " *
              "expected $(e.k1) of $(e.k)")
    source = zeros(Int, length(cols))        # the product column of each column kept
    found, ahead, behind = 0, 0, n1
    for c in 1:_sca_width(K, L)
        found == length(cols) && break
        p = firsts[first(_sca_pair(c, K, L))] ? (ahead += 1) : (behind += 1)
        i = searchsortedfirst(cols, p)
        if i <= length(cols) && cols[i] == p
            source[i] = c
            found += 1
        end
    end
    found == length(cols) || throw(BoundsError(1:e.k, cols))
    C = _product_columns(x, B, base, v, source)
    special = (size(C, 1) - v^2 + 1):(size(C, 1) - v^2 + v)
    m1 = count(<=(n1), cols)
    all(j -> _first_group(view(C, special, j)) == (j <= m1), axes(C, 2)) ||
        error("internal error: Theorem 3.3's columns are not in the groups their base columns put them in")
    P, KP, issca = _partitioned(C, special, v)
    (KP == (m1, length(cols) - m1) && issca) ||
        error("internal error: Theorem 3.3 gave the partition $KP, expected ($m1, $(length(cols) - m1))")
    return P
end

"""
    _lemma35_entry(q, r) -> CatalogEntry

`_lemma35(GaloisField(q), r)` as the entry of a product: Theorem 3.3 applied
`r` times to the orthogonal array (`_times_wide`), which `_lemma35` does step
by step, so `_partitioned_columns` builds only its columns that are kept.
"""
function _lemma35_entry(q::Int, r::Int)
    base = _entry(:oa_sca, 2, q, q + 1, q^2, "orthogonal array"; q, k1 = q, issca = true)
    x = base
    for _ in 1:r
        x = _times_wide(x, base, q)
    end
    return x
end

"A covering array whose last v rows are already its special rows, in partitioned form with the partition `K`."
function _special_rows_last(A::Matrix{Int}, v::Int, K::Tuple{Int, Int})
    P, KP, _ = _partitioned(A, (size(A, 1) - v + 1):size(A, 1), v)
    KP == K || error("internal error: expected the partition $K, found $KP")
    return P
end


## Describing an entry (for Phase 3's `recommend` and the engine's fit)

"""
    _describe(entry) -> NamedTuple

What `recommend` can say about a catalog array without building it (plan
§5.4, §6.1): `name`, the construction as the catalog names it; `family`, its
row of §5.4's table; `source`, the papers with pages, the fusion's included
when it was fused; `rows`; `lower_bound`, the product of the `t` largest
value counts, which no array can beat; and `orthogonal`, whether every `t`
columns show every combination exactly once, the balance a designed
experiment wants (§5.4, "Balance"), which holds exactly when the rows are
the product of every `t` columns' value counts.
"""
function _describe(e::CatalogEntry)
    family = _family(e)
    source = _FAMILY_SOURCES[family]
    _fused_anywhere(e) && (source *= "; fusion: Colbourn et al. 2010, Lemma 3.1, p.1160")
    sizes = isempty(e.sizes) ? fill(e.v, e.k) : e.sizes[1:e.k]
    bound = prod(view(sizes, 1:min(e.t, length(sizes))); init = 1)
    orthogonal = e.rows == bound && (isempty(e.sizes) || allequal(sizes) || e.k == e.t)
    return (; name = e.name, family, source, rows = e.rows, lower_bound = bound, orthogonal)
end

_fused_anywhere(e::CatalogEntry) = e.fused > 0 || any(_fused_anywhere, e.parts)

"The row of plan §5.4's table that an entry's construction comes from."
function _family(e::CatalogEntry)
    kind = e.kind
    kind === :wide && return _family(e.parts[1])
    kind === :one_row && return "One row"
    kind === :kleitman_spencer && return "Kleitman-Spencer"
    kind === :zero_sum && return "Zero-sum array"
    kind in (:bush, :bush_even, :oa_sca) && return "Bush orthogonal array"
    kind === :lemma35 && return "Product of orthogonal arrays"
    kind in (:sca_times, :sca_times_wide) && return "Product of partitioned arrays"
    kind === :printed && return "Printed arrays"
    kind === :projection_pca && return "Projection"
    kind in (:special_rows, :searched_cover, :searched_distinct, :survey_distinct, :meagher_stevens, :lobb_distinct,
             :lobb_cover) && return "Cover starters"
    kind === :tripling && return "Tripling"
    kind === :symbol_product && return "Product of two arrays"
    kind === :lfsr && return "LFSR array"
    kind in (:lfsr_copies, :lfsr_copies_general) && return "Copies of the LFSR array"
    kind in (:ck_ca10, :paley12, :group_ca33, :ck_ca45, :ck_ca51, :group_ca88, :ck_ca185) && return "Small arrays"
    kind === :ordered_design && return "Ordered design"
    kind === :roux_double && return "Roux doubling"
    kind === :ck_double && return "Chateauneuf-Kreher doubling"
    kind === :cmtw_multiply && return "Multiply by v"
    kind in (:constant_rows, :ccl_table3, :ccl_table4) && return "Small arrays"
    error("internal error: no family for a catalog entry of kind $(repr(kind))")
end

"""
The sources of plan §5.4's table, by row, with pages (journal pages unless
marked), as the plan writes them; construction_arrays.jl's header names each
file in papers/. CMMSSY 2006 is Colbourn, Martirosyan, Mullen, Shasha,
Sherwood & Yucas; CMTW 2006 is Colbourn, Martirosyan, Trung & Walker.
"""
const _FAMILY_SOURCES = Dict{String, String}(
    "One row" => "a single row covers every combination of one value",
    "Zero-sum array" => "Chateauneuf & Kreher 2002, Theorem 2.1, for equal counts",
    "Kleitman-Spencer" => "Colbourn 2004, p.127",
    "Bush orthogonal array" => "Sherwood 2005, PDF p.3",
    "Cover starters" => "Colbourn 2004, p.130-131, p.139; Meagher & Stevens 2005; Lobb et al. 2012, Theorem 2.2",
    "Product of partitioned arrays" => "CMMSSY 2006, Theorem 3.2, p.129",
    "Product of orthogonal arrays" => "CMMSSY 2006, Theorem 3.3 and Lemma 3.5, p.130",
    "Printed arrays" => "CMMSSY 2006, Figures 5-7, p.131-133",
    "Projection" => "Colbourn 2008, Theorem 2.3, p.774",
    "Tripling" => "Chateauneuf & Kreher 2002, Theorem 4.2",
    "Product of two arrays" => "Chateauneuf & Kreher 2002, p.219",
    "LFSR array" => "Raaphorst, Moura & Stevens 2014, Theorem 6",
    "Copies of the LFSR array" => "Shokri & Moura 2025, Theorems 4.6-4.8, p.163-164",
    "Small arrays" => "Hadamard matrix of order 12; Colbourn 2004, Theorems 3.2-3.3, Example 3.4; " *
                      "Chateauneuf & Kreher 2002, Figures 4-8; Cohen, Colbourn & Ling 2008, Tables 3-4",
    "Ordered design" => "Cohen, Colbourn & Ling 2008, Construction 2",
    "Roux doubling" => "CMTW 2006, Theorem 3.1",
    "Chateauneuf-Kreher doubling" => "CMTW 2006, Theorem 3.2",
    "Multiply by v" => "CMTW 2006, Theorem 3.4",
)
