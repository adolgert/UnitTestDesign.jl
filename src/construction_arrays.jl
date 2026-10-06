# The covering-array constructions of the catalog (plan §5.4), one function
# each, ported from the reference implementation in
# design/20261003_solver_plan_constructions/ (constructions.jl, products.jl),
# which checks every one by brute force. Each function cites the paper it
# follows; the PDFs are in papers/. Pages are journal pages unless marked.
#
# Conventions, the reference's and not the engines': an array is a
# `Matrix{Int}` with one row per test case and one column per parameter, and
# symbols `0:v-1`. `CA(N; t, k, v)` means N rows, strength t, k columns, v
# symbols; an OA, an orthogonal array, shows every combination of every t
# columns exactly once. `Construction`'s `cover_ordinary` turns an array into
# engine positions (construction.jl). An array that is a product's
# ingredient may hold `_STAR`, an entry that covers nothing and that any
# symbol can fill (`_fill_stars`).
#
# Sources:
#   Colbourn 2004             2004_Colbourn_Combinatorial_Aspects_of_Covering_Arrays.pdf
#   Sherwood 2005             2005_Sherwood_Covering_Arrays_of_Higher_Strength_from_Permutation_Vectors.pdf
#   CMMSSY 2006               2005_Colbourn_Products_of_Mixed_Covering_Arrays_of_Strength_Two.pdf
#                             (Colbourn, Martirosyan, Mullen, Shasha, Sherwood & Yucas)
#   CMTW 2006                 2006_Colbourn.pdf (Colbourn, Martirosyan, Trung & Walker)
#   Colbourn 2008             2008_Colbourn_Strength_Two_Covering_Arrays_Existence_Tables_and_Projection.pdf
#   CKRS 2010                 2010_Colbourn.pdf (Colbourn, Kéri, Rivas Soriano & Schlage-Puchta)
#   Chateauneuf & Kreher 2002 2002_Chateauneuf_On_the_State_of_Strength-Three_Covering_Arrays.pdf
#   Meagher & Stevens 2005    2004_Meagher_Group_Construction_of_Covering_Arrays.pdf
#   Cohen, Colbourn & Ling 2008  2008_Cohen_Constructing_Strength_Three_Covering_Arrays_with_Augmented_Annealing.pdf
#   Lobb et al. 2012          2012_Lobb_Cover_Starters_for_Covering_Arrays_of_Strength_Two.pdf
#   RMS 2014                  2014_Raphorst.pdf (Raaphorst, Moura & Stevens)
#   Shokri & Moura 2025       2025_Shokri_New_Families_of_Strength-3_Covering_Arrays_Using_LFSR_Sequences.pdf

"A free entry of an array: it covers nothing, and any symbol may replace it (CMMSSY 2006, p.126)."
const _STAR = -1

"Replace every `_STAR` by the symbol 0."
_fill_stars(A::Matrix{Int}) = max.(A, 0)

"`_fill_stars`, in place, for an array just built."
_fill_stars!(A::Matrix{Int}) = (A .= max.(A, 0))


## Any strength: zero-sum, fusion, derivation, products of two arrays

"""
    _zero_sum(sizes) -> Matrix{Int}

Strength `t = length(sizes) - 1` on `t + 1` columns, with as many rows as the
first `t` columns have combinations, `prod(sizes[1:t])`; `sizes` must not
increase. The first `t` columns run through every combination, the first
fastest, and the last holds minus their sum modulo its own size. For equal
sizes this is the sum-zero orthogonal array OA(v^t; t, t + 1, v) of
Chateauneuf & Kreher 2002, Theorem 2.1, which exists for every v. For unequal
sizes the same rule works because each earlier column has at least as many
symbols as the last: leaving one of them out, the others and the sum still
fix it modulo the last size, and it takes every residue. The row count is
the product of the `t` largest sizes, which no array of strength `t` can
beat. A last size of 1 gives the full product of the others.
"""
function _zero_sum(sizes::AbstractVector{Int})
    # The ordering as a constant: `rev = true` picks it at run time, a call no session's image holds.
    issorted(sizes, Base.Order.Reverse) || throw(ArgumentError("_zero_sum needs sizes that do not increase"))
    t = length(sizes) - 1
    N = prod(view(sizes, 1:t); init = 1)
    A = zeros(Int, N, t + 1)
    for r in 0:(N - 1)
        rest, total = r, 0
        for c in 1:t
            A[r + 1, c] = rest % sizes[c]
            total += A[r + 1, c]
            rest ÷= sizes[c]
        end
        A[r + 1, t + 1] = mod(-total, sizes[t + 1])
    end
    return A
end

"""
    _fuse(A, v) -> Matrix{Int}

CKRS 2010, Lemma 3.1, p.1160: from an array on `v` symbols, one on `v - 1`
symbols with two rows fewer, of the same strength. Permute the symbols
within each column so that the first row holds the last symbol throughout,
and delete it; then wherever another row holds the last symbol, write the
second row's entry there (or 0 where that is the last symbol too), and delete
the second row. Each column is treated alone, so fusing the first `k`
columns gives the first `k` columns of the fused array.
"""
function _fuse(A::Matrix{Int}, v::Int)
    N, k = size(A)
    last = v - 1
    out = Matrix{Int}(undef, N - 2, k)
    for c in 1:k
        s = A[1, c]
        swap(x) = s == last ? x : (x == s ? last : (x == last ? s : x))
        R = swap(A[2, c])
        for r in 3:N
            x = swap(A[r, c])
            out[r - 2, c] = x == last ? (R == last ? 0 : R) : x
        end
    end
    return out
end

"`d` fusions, from an array on `q` symbols to one on `q - d` symbols, with `2d` rows fewer."
function _fused(A::Matrix{Int}, q::Int, d::Int)
    for i in 0:(d - 1)
        A = _fuse(A, q - i)
    end
    return A
end

"""
    _derive(A, v) -> Matrix{Int}

Colbourn 2004, p.128, inequality (4): a CA(≤ N/v; t - 1, k - 1, v) from a
CA(N; t, k, v), the rows that hold the least frequent symbol in the last
column, with that column removed. The catalog's lookup doesn't offer it, as
the reference catalog doesn't: from sizes alone its size is only a bound,
N/v, and offering it would change sizes of the reference's table, which the
lookup reproduces (plan §5.4's gate). The notes of Phase 2 list the shapes
where a derived array would be smaller.
"""
function _derive(A::Matrix{Int}, v::Int)
    counts = [count(==(x), view(A, :, size(A, 2))) for x in 0:(v - 1)]
    x = argmin(counts) - 1
    return A[view(A, :, size(A, 2)) .== x, 1:(end - 1)]
end

"""
    _symbol_product(A, B, w) -> CA(N_A N_B; t, k, v w)

Chateauneuf & Kreher 2002, p.219, the product of two arrays: `A` has v
symbols and `B` has `w`. Each row of the result pairs a row of `A` with a row
of `B`, and the symbol in a column is the pair of theirs, written `a w + b`.
With two orthogonal arrays it gives one for a `v w` that is not a prime
power, on as many columns as the narrower of the two.
"""
function _symbol_product(A::Matrix{Int}, B::Matrix{Int}, w::Int)
    k = min(size(A, 2), size(B, 2))
    NA, NB = size(A, 1), size(B, 1)
    C = Matrix{Int}(undef, NA * NB, k)
    for i in 1:NA, j in 1:NB, c in 1:k
        C[(i - 1) * NB + j, c] = A[i, c] * w + B[j, c]
    end
    return C
end


## Strength 2, two symbols: Kleitman-Spencer and Katona

"The least N with `binomial(N - 1, ceil(N / 2)) >= k`: the rows of `_kleitman_spencer(k)`."
function _kleitman_spencer_rows(k::Int)
    N = 2
    while binomial(N - 1, cld(N, 2)) < k
        N += 1
    end
    return N
end

"""
    _kleitman_spencer(k) -> CA(N; 2, k, 2)

Colbourn 2004, p.127: N is least with `binomial(N - 1, ceil(N / 2)) >= k`,
which is optimal. The columns are distinct binary N-tuples of weight
`ceil(N / 2)` with a 0 in the first position, in lexicographic order of
their supports.
"""
function _kleitman_spencer(k::Int)
    N = _kleitman_spencer_rows(k)
    w = cld(N, 2)
    A = zeros(Int, N, k)
    subset = collect(2:(w + 1))             # w-subsets of rows 2:N, in lexicographic order
    for c in 1:k
        for r in subset
            A[r, c] = 1
        end
        i = w
        while i >= 1 && subset[i] == N - w + i
            i -= 1
        end
        i == 0 && break
        subset[i] += 1
        for j in (i + 1):w
            subset[j] = subset[j - 1] + 1
        end
    end
    return A
end


## Orthogonal arrays: Bush

"""
    _bush(F, t, k = q + 1) -> OA(q^t; t, k, q), for 2 <= t <= q and k <= q + 1

Sherwood 2005, PDF p.3; CMTW 2006, proof of Theorem 3.4. The rows are the
polynomials of degree below `t` over `F`, the `i`-th coefficient the `i`-th
base-q digit of the row number. The first `q` columns are their values at
each field element, and the last is the leading coefficient. Every `t`
columns show every combination exactly once. Only the first `k` columns are
built.
"""
function _bush(F::GaloisField, t::Int, k::Int = F.q + 1)
    q = F.q
    (2 <= t <= q && 1 <= k <= q + 1) || throw(ArgumentError("_bush needs 2 <= t <= q and k <= q + 1"))
    A = Matrix{Int}(undef, q^t, k)
    coef = zeros(Int, t)
    for r in 0:(q^t - 1)
        rest = r
        for i in 1:t
            coef[i] = rest % q
            rest ÷= q
        end
        for x in 0:(min(k, q) - 1)
            value = 0
            for i in t:-1:1                # Horner
                value = _plus(F, _times(F, value, x), coef[i])
            end
            A[r + 1, x + 1] = value
        end
        k == q + 1 && (A[r + 1, q + 1] = coef[t])
    end
    return A
end

"""
    _bush_even(F, k = q + 2) -> OA(q^3; 3, k, q), for q a power of 2, q >= 4

Sherwood 2005, PDF p.3: one more column than `_bush(F, 3)`, the coefficient
of x. It fails in odd characteristic.
"""
function _bush_even(F::GaloisField, k::Int = F.q + 2)
    q = F.q
    (iseven(q) && q >= 4 && k <= q + 2) || throw(ArgumentError("_bush_even needs q = 2^m >= 4"))
    k <= q + 1 && return _bush(F, 3, k)
    return hcat(_bush(F, 3), [(r ÷ q) % q for r in 0:(q^3 - 1)])
end


## Strength 2 products: Colbourn 2004, Theorem 4.2 and Lemma 4.4; CMMSSY 2006, Theorems 3.2 and 3.3

# An SCA(N; 2, (k1, k2), v) is a CA(N; 2, k1 + k2, v) whose last v rows are
# (i, ..., i, 0, ..., 0) for each symbol i: constant on the first k1 columns
# and the special symbol, here 0, on the last k2 (Colbourn 2004, p.136-137,
# where the special symbol is written 1). A PCA(N; 2, (k1, k2), v) asks less
# of the last k2 columns: its last v rows may hold anything there (CMMSSY
# 2006, p.128).

"The SCA(q^2; 2, (q, 1), q) from the orthogonal array of `F`: slope a ≠ 0 rows first, then the q constant rows."
function _sca_base(F::GaloisField)
    q = F.q
    A = Matrix{Int}(undef, q^2, q + 1)
    row = 0
    for a in 1:(q - 1), b in 0:(q - 1)        # slope a != 0: not constant
        row += 1
        for x in 0:(q - 1)
            A[row, x + 1] = _plus(F, _times(F, a, x), b)
        end
        A[row, q + 1] = a
    end
    for b in 0:(q - 1)                        # slope 0: the q constant rows, last
        row += 1
        A[row, 1:q] .= b
        A[row, q + 1] = 0
    end
    return A
end

"""
    _sca_product(A, (k1, k2), B, (l1, l2), v) -> (C, (k1 l1, k1 l2 + k2 l1))

Colbourn 2004, Theorem 4.2; CMMSSY 2006, Theorem 3.2, p.129: from a
PCA(N; 2, (k1, k2), v) `A` and an SCA(M; 2, (l1, l2), v) `B`, a
PCA(N + M - v; 2, (k1 l1, k1 l2 + k2 l1), v). A product column is (f, g):
column f of B and column g of A; the columns from the last l2 of B and the
last k2 of A together are dropped. When `A` is an SCA, so is the result.
"""
function _sca_product(A::Matrix{Int}, K::Tuple{Int, Int}, B::Matrix{Int}, L::Tuple{Int, Int}, v::Int)
    nfirst, n = K[1] * L[1], _sca_width(K, L)
    return _sca_product_columns(A, axes(A, 2), K, B, L, v, 1:n), (nfirst, n - nfirst)
end

"The number of columns of `_sca_product` for the partitions `K` of A and `L` of B: k1 l1 + k1 l2 + k2 l1."
_sca_width(K::Tuple{Int, Int}, L::Tuple{Int, Int}) = K[1] * L[1] + K[1] * L[2] + K[2] * L[1]

"""
    _sca_pair(c, K, L) -> (f, g)

The columns that column `c` of `_sca_product` pairs: column f of B and column
g of A. In the product's order, f slowest throughout: the first group, f in
1:l1 with g in 1:k1; then the pairs of a first group and a second, f in 1:l1
with g in the last k2 of A, and f in the last l2 of B with g in 1:k1.
"""
function _sca_pair(c::Int, K::Tuple{Int, Int}, L::Tuple{Int, Int})
    (k1, k2), (l1, l2) = K, L
    1 <= c <= _sca_width(K, L) || throw(BoundsError(1:_sca_width(K, L), c))
    c <= l1 * k1 && return (div(c - 1, k1) + 1, rem(c - 1, k1) + 1)
    c -= l1 * k1
    c <= l1 * k2 && return (div(c - 1, k2) + 1, k1 + rem(c - 1, k2) + 1)
    c -= l1 * k2
    return (l1 + div(c - 1, k1) + 1, rem(c - 1, k1) + 1)
end

"""
    _sca_product_columns(A, acols, K, B, L, v, cols) -> Matrix{Int}

Columns `cols` of `first(_sca_product(A, K, B, L, v))`, in that order, for
an `A` that holds only the columns `acols` (increasing) of the PCA and the
whole SCA `B`: a column of the product is made of one column of each, so
the rest of `A` is never needed (`_sca_pair`). `_sca_product` is this with
every column; the catalog's wide products build only the columns they keep
(`_partitioned_columns`).
"""
function _sca_product_columns(A::Matrix{Int}, acols::AbstractVector{Int}, K::Tuple{Int, Int}, B::Matrix{Int},
                              L::Tuple{Int, Int}, v::Int, cols::AbstractVector{Int})
    k1 = K[1]
    nfirst = k1 * L[1]
    NA, NB = size(A, 1) - v, size(B, 1) - v      # the rows above the special rows
    C = zeros(Int, NA + NB + v, length(cols))
    for (j, c) in enumerate(cols)
        f, g = _sca_pair(c, K, L)
        a = searchsortedfirst(acols, g)
        (a <= length(acols) && acols[a] == g) || error("internal error: column $g of the PCA was not built")
        C[1:NA, j] .= view(A, 1:NA, a)
        C[(NA + 1):(NA + NB), j] .= view(B, 1:NB, f)
        for i in 0:(v - 1)
            # Under the first group, the constant rows. Under a column from the last k2 of A,
            # the last rows of A, which for an SCA hold 0. Under a column from the last l2 of B, 0.
            C[NA + NB + i + 1, j] = c <= nfirst ? i : (g > k1 ? A[NA + i + 1, a] : 0)
        end
    end
    return C
end

"""
    _lemma44(F, r) -> CA((r + 1) q^2 - r q; 2, q^(r + 1) + (r + 1) q^r, q)

Colbourn 2004, Lemma 4.4, p.137-139: `_sca_product` applied `r` times to the
base SCA. The lemma's formula gives the column count. Three of the examples
printed under it do not match the formula: 128 and 576 columns for q = 4,
where it and the arrays built from it give 112 and 512, and 3,673 for q = 7,
where they give 3,773 (misprints found by building, plan §5.4).
"""
function _lemma44(F::GaloisField, r::Int)
    base = _sca_base(F)
    K = (F.q, 1)
    C, KC = base, K
    for _ in 1:r
        C, KC = _sca_product(C, KC, base, K, F.q)
    end
    return C
end

"""
    _partitioned(C, rows, v) -> (P, (k1, k2), issca)

Rearrange a covering array as a PCA whose last v rows are `rows` of `C`
(CMMSSY 2006, p.128). A column on which those rows hold every symbol once
goes into the first group, with its symbols renamed so that the rows read
0, 1, ..., v-1; a `_STAR` there takes the symbol that is missing. Every
other column goes into the second group, and if the rows hold a single
symbol there it is renamed 0. `issca` says whether that happened in every
column of the second group, so that `P` is an SCA.
"""
function _partitioned(C::Matrix{Int}, rows::AbstractVector{Int}, v::Int)
    length(rows) == v || throw(ArgumentError("_partitioned needs v rows"))
    P = copy(C)
    first, second = Int[], Int[]
    issca = true
    for c in axes(C, 2)
        held = C[rows, c]
        symbols = filter(!=(_STAR), held)
        relabel = collect(0:(v - 1))
        if _first_group(held)
            missing_symbols = setdiff(0:(v - 1), symbols)
            for (i, x) in enumerate(held)
                x == _STAR && (held[i] = popfirst!(missing_symbols); P[rows[i], c] = held[i])
            end
            relabel[held .+ 1] .= 0:(v - 1)
            push!(first, c)
        else
            if allequal(symbols)
                a = symbols[1]
                relabel[a + 1], relabel[1] = 0, a
                for r in rows
                    P[r, c] == _STAR && (P[r, c] = a)
                end
            else
                issca = false
            end
            push!(second, c)
        end
        for r in axes(P, 1)
            P[r, c] == _STAR || (P[r, c] = relabel[P[r, c] + 1])
        end
    end
    others = setdiff(axes(C, 1), rows)
    return P[[others; rows], [first; second]], (length(first), length(second)), issca
end

"Whether `_partitioned` puts a column whose special rows hold `held` in its first group: no symbol twice, stars aside."
_first_group(held::AbstractVector{Int}) = allunique(filter(!=(_STAR), held))

"The number of columns of `_lemma35(F, r)`: T_0 = q + 1, T_1 = q^2 + 2q, T_(r+1) = q (T_r + T_(r-1))."
function _lemma35_columns(q::Int, r::Int)
    before, now = 0, q + 1
    r == 0 && return now
    before, now = now, q^2 + 2q
    for _ in 2:r
        before, now = now, q * (now + before)
    end
    return now
end

"""
    _lemma35(F, r) -> CA((r + 1) q^2 - r q; 2, T_r, q)

CMMSSY 2006, Lemma 3.5 with Theorem 3.3, p.130: the product of `_lemma44`,
with Theorem 3.3 applied after each step. The q rows that came from the
lines of slope 1 of the orthogonal array hold every symbol once on more
columns than the q constant rows do, so they become the special rows for the
next step. The same rows as `_lemma44`, for more columns (`_lemma35_columns`):
57, 216 and 819 columns of 3 symbols on 21, 27 and 33 rows.
"""
function _lemma35(F::GaloisField, r::Int)
    q = F.q
    base = _sca_base(F)
    K = (q, 1)
    C, KC = base, K
    for _ in 1:r
        C, KC = _sca_product(C, KC, base, K, q)
        slope1 = (size(C, 1) - q^2 + 1):(size(C, 1) - q^2 + q)     # the first q rows that came from `base`
        C, KC, issca = _partitioned(C, slope1, q)
        issca || error("internal error: Theorem 3.3 did not leave an SCA")
    end
    return C
end

"""
    _product(A, B) -> CA(N + M; 2, k l, v)

CMMSSY 2006, Figure 2, p.127: l copies of `A` side by side, above `B` with
each of its columns repeated k times. Two columns of the result differ in
their column of `A` or in their column of `B`.
"""
_product(A::Matrix{Int}, B::Matrix{Int}) = vcat(repeat(A, 1, size(B, 2)), repeat(B; inner = (1, size(A, 2))))


## Three times the columns: Chateauneuf & Kreher 2002, Theorem 4.2

"""
    _idempotent_square(v) -> Matrix{Int}

A Latin square L on `0:v-1` with `L[i, i] = i`, for v >= 3. For odd v,
`L[i, j] = (i + j) / 2` modulo v. For even v, that square of order v - 1,
prolonged: the cells (i, i + 1) hold different symbols, so each of them gets
the new symbol, and its old symbol moves to the new row and the new column.
"""
function _idempotent_square(v::Int)
    v >= 3 || throw(ArgumentError("_idempotent_square needs v >= 3"))
    n = isodd(v) ? v : v - 1
    half = (n + 1) ÷ 2                                   # 1 / 2 modulo n
    L = fill(v - 1, v, v)
    for i in 0:(n - 1), j in 0:(n - 1)
        L[i + 1, j + 1] = mod((i + j) * half, n)
    end
    if iseven(v)
        for i in 0:(n - 1)
            j = mod(i + 1, n)
            L[i + 1, v] = L[v, j + 1] = L[i + 1, j + 1]
            L[i + 1, j + 1] = v - 1
        end
    end
    return L
end

"""
    _od_triple(A, v) -> CA(N + v (v - 1); 2, 3k, v), for v >= 3

Chateauneuf & Kreher 2002, Theorem 4.2 (tripling). Three copies of a
CA(N; 2, k, v) side by side cover every pair of columns except a column and
its own copy, where they show only equal symbols. Then, for every two
different symbols i and j, one row that is constant on each copy: i, j, and
`L[i, j]` from an idempotent Latin square. Those rows show every pair of
different symbols between any two copies.
"""
function _od_triple(A::Matrix{Int}, v::Int)
    N, k = size(A)
    L = _idempotent_square(v)
    C = Matrix{Int}(undef, N + v * (v - 1), 3k)
    for c in 1:3k
        C[1:N, c] .= view(A, :, mod1(c, k))
    end
    row = N
    for i in 0:(v - 1), j in 0:(v - 1)
        i == j && continue
        row += 1
        C[row, 1:k] .= i
        C[row, (k + 1):2k] .= j
        C[row, (2k + 1):3k] .= L[i + 1, j + 1]
    end
    return C
end


## Strength 2 just past the orthogonal array: cover starters
## Colbourn 2004, p.130-131 and p.139; Meagher & Stevens 2005; Lobb et al. 2012

"""
    _is_fixed_starter(starter, v, f; relative = false, group = nothing) -> Bool

Lobb et al. 2012, Section 2, with Z_k on the columns: whether `starter` (as
`_parse_starter` reads it) is a (k, v, f)-cover starter. At every separation
s = 1:k-1, (a) each fixed symbol stands s places before some group element,
and (b) the quotients `inv(x) y` of the group elements x, y that stand s
apart give every group element. With `relative`, (b) need not give the
identity: a (k, v, 1, f)-relative cover starter. `group = nothing` means
Z_(v-f).
"""
function _is_fixed_starter(starter::Vector{Int}, v::Int, f::Int;
                           relative::Bool = false, group::Union{Nothing, SymbolGroup} = nothing)
    k = length(starter)
    m = v - f
    1 <= m <= 63 || throw(ArgumentError("_is_fixed_starter needs 1 <= v - f <= 63"))
    all(e -> e == _FREE || -f <= e < m, starter) || return false
    wanted = (UInt64(1) << m) - 1 - relative      # bit d: the quotient d was seen
    fixed = (UInt64(1) << f) - 1                  # bit i: inf_i stands before a group element
    for s in 1:(k - 1)
        seen = zero(UInt64)
        reached = zero(UInt64)
        for a in 1:k
            b = a + s
            b > k && (b -= k)
            x, y = starter[a], starter[b]
            (x == _FREE || y == _FREE || y < 0) && continue
            if x < 0
                reached |= UInt64(1) << (-x - 1)
            elseif group === nothing
                seen |= UInt64(1) << mod(y - x, m)
            else
                seen |= UInt64(1) << group.op[group.inv[x + 1] + 1, y + 1]
            end
        end
        (reached == fixed && seen & wanted == wanted) || return false
    end
    return true
end

"""
    _is_distinct_starter(starter, v; group = nothing) -> Bool

One fixed symbol, every quotient but the identity at every separation, and
every group element among the entries (Colbourn 2004, p.131). In Lobb et al.
2012 this is a distinct (k, v, 1, 1)-relative cover starter.
"""
_is_distinct_starter(starter::Vector{Int}, v::Int; group::Union{Nothing, SymbolGroup} = nothing) =
    _is_fixed_starter(starter, v, 1; relative = true, group) &&
    sort!(unique!([e for e in starter if e >= 0])) == collect(0:(v - 2))

# Lobb et al. 2012, Lemma 2.1: k (v - f) rows. Row (a, x) holds, in column
# a + c, the fixed symbol at position c of the starter, or x times the group
# element there. The fixed symbol inf_i is written v - f + i, and a free
# position is filled with 0.
function _developed(starter::Vector{Int}, v::Int, f::Int, group::Union{Nothing, SymbolGroup})
    k = length(starter)
    m = v - f
    A = zeros(Int, k * m, k)
    row = 0
    for a in 0:(k - 1), x in 0:(m - 1)
        row += 1
        for c in 0:(k - 1)
            e = starter[c + 1]
            A[row, mod(a + c, k) + 1] =
                e == _FREE ? 0 : e < 0 ? m - e - 1 : group === nothing ? mod(x + e, m) : group.op[x + 1, e + 1]
        end
    end
    return A
end

"""
    _fixed_starter_array(starter, v, f, inner = nothing; group = nothing) -> CA(k (v - f) + N; 2, k, v)

Lobb et al. 2012, Lemma 2.1 and Theorem 2.2(1). The developed rows cover
every pair except those of two fixed symbols. Beneath them goes `inner`, a
CA(N; 2, k, f) on the symbols `0:f-1`, written on the fixed symbols. With one
fixed symbol the inner array is a single row and may be left out; then this
is the array of a (v, k)-cover starter, CA(k (v - 1) + 1; 2, k, v), of
Colbourn 2004, p.130, and Meagher & Stevens 2005, Lemma 2.1, with inf
written `v - 1`.
"""
function _fixed_starter_array(starter::Vector{Int}, v::Int, f::Int, inner::Union{Nothing, Matrix{Int}} = nothing;
                              group::Union{Nothing, SymbolGroup} = nothing)
    k = length(starter)
    _is_fixed_starter(starter, v, f; group) || throw(ArgumentError("not a ($k, $v, $f)-cover starter"))
    A = _developed(starter, v, f, group)
    f == 0 && return A
    inner === nothing && f == 1 && (inner = zeros(Int, 1, k))
    (inner !== nothing && size(inner, 2) >= k) ||
        throw(ArgumentError("needs a CA(N; 2, $k, $f) for the fixed symbols"))
    return vcat(A, view(inner, :, 1:k) .+ (v - f))
end

"""
    _distinct_starter_array(starter, v; group = nothing) -> CA(l (v - 1) + v; 2, l + 1, v)

Colbourn 2004, p.139; Lobb et al. 2012, Theorem 2.2(2b): from a distinct
starter of length l, one more column than the starter's own array, which
holds the developing element. Then v - 1 rows that are constant on the old
columns with inf in the new one, and a row of inf. The last v rows are
constant on the first l columns, so the array is an SCA(…; 2, (l, 1), v)
once they are relabelled (`_partitioned`).
"""
function _distinct_starter_array(starter::Vector{Int}, v::Int; group::Union{Nothing, SymbolGroup} = nothing)
    l = length(starter)
    _is_distinct_starter(starter, v; group) || throw(ArgumentError("not a ($v, $l)-distinct cover starter"))
    developed = hcat(_developed(starter, v, 1, group), repeat(0:(v - 2), l))
    constant = [c <= l ? i : v - 1 for i in 0:(v - 1), c in 1:(l + 1)]
    return vcat(developed, constant)
end


## Projection: Colbourn 2008, Theorem 2.3

"""
    _projection(F, t; stars = false) -> CA(q^2 - t; 2, q + 1 + t, q - t), for 1 <= t <= q - 2

Colbourn 2008, Theorem 2.3, p.774, with s = q - t. Start from the orthogonal
array whose row (i, j) holds i l + j in column l and i in the last column;
the row (0, j) holds j throughout, then 0. Give up t symbols J, and delete
their t rows. For each j0 in J add a column: a row that held j0 in column l,
one of the first q - t columns, gets the number of that column there, and
its entry j0 in column l is replaced, so that the q - t symbols that are kept
each appear once among the rows with that number. The q - t rows (0, j) that
remain take j in every new column. With `stars`, the entries that are not
needed stay `_STAR`; otherwise they are filled with 0.
"""
function _projection(F::GaloisField, t::Int; stars::Bool = false)
    q = F.q
    s = q - t                                   # symbols kept: 0:s-1. Given up: s:q-1.
    (t >= 1 && s >= 2) || throw(ArgumentError("_projection needs 1 <= t <= q - 2"))
    index = [(i, j) for i in 0:(q - 1) for j in 0:(q - 1)]
    original = [l == q ? i : _plus(F, _times(F, i, l), j) for (i, j) in index, l in 0:q]
    A = hcat(original, fill(_STAR, q^2, t))
    for (n, j0) in enumerate(s:(q - 1)), l in 0:(s - 1)
        class = [r for (r, (i, j)) in enumerate(index) if i != 0 && original[r, l + 1] == j0]
        for (place, r) in enumerate(class)
            A[r, q + 1 + n] = l
            A[r, l + 1] = place <= s ? place - 1 : _STAR
        end
    end
    for (r, (i, j)) in enumerate(index)
        i == 0 && j < s && (A[r, (q + 2):end] .= j)
    end
    A = A[[r for (r, (i, j)) in enumerate(index) if !(i == 0 && j >= s)], :]
    for r in axes(A, 1)
        for l in 1:q
            A[r, l] >= s && (A[r, l] = _STAR)
        end
        slope = A[r, q + 1]                    # keep the slopes 1:s, as the symbols 0:s-1
        A[r, q + 1] = 1 <= slope <= s ? slope - 1 : _STAR
    end
    return stars ? A : _fill_stars(A)
end


## Arrays printed in CMMSSY 2006, with the symbols and free entries as printed

"An array printed one row per line, `*` for a free entry (`_STAR`)."
_printed(text::AbstractString) =
    permutedims(reduce(hcat, [[x == "*" ? _STAR : parse(Int, x) for x in split(line)]
                              for line in split(strip(text), "\n")]))

"""
CMMSSY 2006, Figure 5, p.131: a PCA(15; 2, (14, 6), 3), which is Nurmela's
CA(15; 2, 20, 3) with its rows and columns arranged. The last three rows hold
every symbol once in each of the first 14 columns and one symbol in each of
the last 6. Correct as printed.
"""
const _CMMSSY_FIGURE5 = """
    0 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 1 1 1
    0 0 1 1 0 1 2 2 2 2 2 2 2 2 0 0 0 2 2 2
    0 2 2 2 0 1 0 0 0 1 2 0 1 1 2 2 2 0 2 1
    1 1 1 0 1 0 1 1 0 0 2 2 2 1 2 2 2 2 1 0
    1 2 0 2 1 0 0 2 2 1 0 1 0 2 0 1 2 2 2 1
    1 2 2 1 2 0 2 1 1 0 1 0 2 0 1 0 2 1 2 1
    2 0 0 1 2 2 2 2 0 2 2 1 0 1 2 2 2 1 0 2
    2 1 2 0 2 2 1 2 2 0 1 0 1 2 0 2 1 2 2 0
    2 1 1 2 0 2 0 1 1 2 1 2 0 2 2 0 1 1 0 1
    2 1 1 2 2 1 2 0 2 1 0 1 2 0 2 1 0 1 0 0
    1 2 2 1 1 2 1 0 1 2 0 2 1 0 1 2 0 2 0 0
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    2 2 1 0 1 0 2 2 1 2 2 0 1 0 1 1 1 0 1 2
    1 0 2 2 0 1 1 1 2 0 0 1 0 1 1 1 1 0 1 2
    0 1 0 1 2 2 0 0 0 1 1 2 2 2 1 1 1 0 1 2
    """

"""
CMMSSY 2006, Figure 6, p.132: a PCA(11; 2, (4, 1), 3), a PCA(12; 2, (4, 3), 3)
and a PCA(13; 2, (6, 3), 3). Correct as printed.
"""
const _CMMSSY_FIGURE6 = (
    """
    1 2 1 0 0
    0 1 2 0 2
    1 1 0 1 2
    2 1 1 1 0
    1 0 2 2 0
    0 2 0 2 0
    0 0 1 1 2
    2 2 2 2 2
    0 1 1 2 1
    2 0 0 0 1
    1 2 2 1 1
    """,
    """
    0 2 1 0 1 1 1
    0 1 2 1 1 2 2
    1 1 1 2 0 1 2
    1 0 0 1 1 1 0
    0 2 0 2 2 0 2
    2 0 1 2 1 0 1
    1 2 2 1 0 0 1
    2 0 2 0 2 1 2
    2 1 0 0 0 0 0
    1 1 0 0 2 2 1
    0 0 2 2 0 2 0
    2 2 1 1 2 2 0
    """,
    """
    1 0 2 2 1 0 1 1 1
    1 2 0 0 0 1 1 2 0
    2 2 0 1 1 1 2 1 2
    2 2 2 0 2 2 1 0 2
    0 1 1 1 0 2 1 1 1
    2 0 1 0 2 1 2 2 1
    0 0 2 1 0 0 2 0 0
    1 1 1 2 1 2 2 0 0
    2 1 0 0 2 0 0 1 0
    0 2 0 2 2 1 0 0 1
    1 0 0 1 2 2 0 2 2
    0 1 2 0 1 1 0 2 2
    2 2 1 2 0 0 0 2 2
    """)

"""
CMMSSY 2006, Figure 7, p.133: a PCA(19; 2, (5, 1), 4), a PCA(21; 2, (6, 1), 4)
and a PCA(23; 2, (6, 2), 4), with the printed free entries. Correct as printed.
"""
const _CMMSSY_FIGURE7 = (
    """
    0 2 2 2 3 2
    0 0 0 3 1 1
    3 0 2 1 2 2
    0 3 1 1 0 3
    1 1 2 3 0 3
    2 0 3 2 3 3
    2 1 1 2 1 2
    1 3 0 0 3 2
    3 1 0 1 3 1
    2 0 2 0 0 1
    1 3 1 2 2 1
    1 2 3 1 1 1
    3 3 3 3 0 2
    3 2 1 0 1 3
    2 2 0 3 2 3
    3 2 0 2 0 0
    0 1 3 0 2 0
    2 3 2 1 1 0
    1 0 1 3 3 0
    """,
    """
    2 3 2 3 3 0 3
    3 0 0 3 0 0 2
    1 2 1 0 3 2 2
    0 3 0 1 1 2 0
    1 3 3 0 2 0 0
    3 3 3 1 3 3 2
    3 2 3 3 1 1 0
    2 1 3 1 0 2 3
    3 1 2 0 1 1 2
    0 2 0 0 0 3 3
    2 1 1 2 1 0 0
    3 0 2 2 2 2 3
    0 0 3 2 3 1 0
    1 0 1 1 1 1 3
    0 1 1 3 2 3 2
    1 * 2 2 0 3 0
    2 2 0 2 2 1 2
    1 1 0 3 3 2 1
    0 2 2 1 2 0 1
    2 0 3 0 1 3 1
    3 3 1 2 0 1 1
    """,
    """
    2 0 1 1 0 0 1 1
    1 2 2 1 3 3 0 1
    2 3 0 0 2 1 2 1
    2 1 1 2 1 3 3 2
    3 2 1 0 1 1 0 3
    3 0 2 2 0 1 2 2
    0 3 0 1 1 2 0 2
    2 1 3 3 0 2 0 1
    1 1 2 0 2 2 1 3
    3 3 3 2 1 3 1 1
    0 0 3 2 2 0 0 0
    0 1 3 1 3 1 2 3
    1 3 1 3 3 1 1 0
    2 3 2 3 1 0 2 3
    0 2 1 3 2 3 1 2
    3 0 0 3 3 2 3 3
    1 2 0 2 0 3 1 3
    0 3 2 0 0 1 3 1
    1 2 3 0 3 0 3 2
    2 2 1 2 3 2 2 0
    1 0 2 0 1 3 2 0
    3 1 0 1 2 0 3 0
    * * * * 0 * * 0
    """)


## Strength 3: the LFSR array (RMS 2014) and its copies (Shokri & Moura 2025)

"""
    _lfsr_sequence(F, length) -> Vector{Int}

The first `length` terms of `a_i = -(c2 a_(i-1) + c1 a_(i-2) + c0 a_(i-3))`
for the first primitive cubic over `F` (`_primitive_cubic`), from
`(0, 0, 1)`. Its period is `q^3 - 1`.
"""
function _lfsr_sequence(F::GaloisField, n::Int)
    c0, c1, c2 = _primitive_cubic(F)
    seq = zeros(Int, n)
    n >= 3 && (seq[3] = 1)
    for i in 4:n
        seq[i] = _minus(F, _plus(F, _plus(F, _times(F, c2, seq[i - 1]), _times(F, c1, seq[i - 2])),
                                 _times(F, c0, seq[i - 3])))
    end
    return seq
end

"""
    _lfsr_array(F, k = q^2 + q + 1) -> CA(2 q^3 - 1; 3, k, q)

RMS 2014, Theorem 6. Take the sequence of a primitive cubic
(`_lfsr_sequence`), whose period is `q^3 - 1`. The rows are its `q^3 - 1`
windows of length `K = q^2 + q + 1`, the same windows reversed, and one row
of zeros. Only the first `k` columns are built: the window's first `k`
terms, and the reversed window's.
"""
function _lfsr_array(F::GaloisField, k::Int = F.q^2 + F.q + 1)
    q = F.q
    K = q^2 + q + 1
    1 <= k <= K || throw(ArgumentError("_lfsr_array has at most q^2 + q + 1 columns"))
    period = q^3 - 1
    seq = _lfsr_sequence(F, period + K)
    A = zeros(Int, 2 * period + 1, k)
    for i in 1:period, c in 1:k
        A[i, c] = seq[i + c - 1]
        A[period + i, c] = seq[i + K - c]
    end
    return A
end

"""
    _lfsr_blocks(F) -> (A, Ar)

The two halves of `_lfsr_array(F)`, each with the row of zeros: the windows
of the sequence, and the same windows reversed. Each is an orthogonal array
of strength 2 with q^3 rows, and every three columns are covered at strength
3 by at least one of the two (Shokri & Moura 2025, Theorems 3.13 and 3.15).
"""
function _lfsr_blocks(F::GaloisField)
    L = _lfsr_array(F)
    period = F.q^3 - 1
    return vcat(L[1:period, :], L[end:end, :]), vcat(L[(period + 1):(2 * period), :], L[end:end, :])
end

"""
    _difference_covering(F, n = 1) -> DCA(n (q - 1) + 1; 2, q^n, q)

In any two columns, the differences of the entries row by row give every
element of `F`. For n = 1 it is the multiplication table (Shokri & Moura
2025, Theorem 2.8). For larger n it is the product of n copies with all but
one row of zeros removed (Theorems 2.9 and 2.10).
"""
function _difference_covering(F::GaloisField, n::Int = 1)
    table = copy(F.mul)
    D = table
    for _ in 2:n
        D = _product(D, table[2:end, :])            # the row of zeros is the first row of the table
    end
    return D
end

"""
    _shokri_general(blocks, P, D, C, F) -> CA(n q^3 + max(m - n, 0) N1 + N2; 3, x k, q)

Shokri & Moura 2025, Theorem 4.6, p.163. `blocks` are n arrays of strength 2
on k columns such that every three columns are covered at strength 3 by one
of them. `P` is a CA(N1; 2, k, q), `D` a DCA(m; 2, x, q), and `C` a
CA(N2; 3, x, q), or `nothing` when x = 2. The result has x copies of the k
columns. In copy c, row block r is `blocks[r]` while they last and `P` after
that, with `D[r, c]` added to every entry. Below them, each column of `C` is
repeated k times.
"""
function _shokri_general(blocks::Vector{Matrix{Int}}, P::Matrix{Int}, D::Matrix{Int},
                         C::Union{Nothing, Matrix{Int}}, F::GaloisField)
    m, x = size(D)
    k = size(P, 2)
    parts = Matrix{Int}[]
    for r in 1:max(m, length(blocks))
        B = r <= length(blocks) ? blocks[r] : P
        push!(parts, reduce(hcat, [[_plus(F, a, r <= m ? D[r, c] : 0) for a in B] for c in 1:x]))
    end
    C === nothing || push!(parts, repeat(C; inner = (1, k)))
    return reduce(vcat, parts)
end

"""
    _lfsr_copies(F, x) -> a strength-3 array on x (q^2 + q + 1) columns, for 2 <= x <= q

Shokri & Moura 2025, Theorem 4.7 for x = 2, with 4q^3 - 5q^2 + 2q rows, and
Theorem 4.8 for 3 <= x <= q, with 5q^3 - 6q^2 + 2q rows, p.164. The
ingredients of `_shokri_general` are the two halves of the LFSR array, the
pairwise array of `_lemma44`, the multiplication table, and for x >= 3 the
Bush array on x columns without its q^2 polynomials of degree at most 1,
whose triples the row blocks above already show.
"""
function _lfsr_copies(F::GaloisField, x::Int)
    q = F.q
    2 <= x <= q || throw(ArgumentError("_lfsr_copies needs 2 <= x <= q"))
    A, Ar = _lfsr_blocks(F)
    P = _lemma44(F, 1)[:, 1:(q^2 + q + 1)]
    D = _difference_covering(F)[:, 1:x]
    C = x == 2 ? nothing : _bush(F, 3)[(q^2 + 1):end, 1:x]
    return _shokri_general([A, Ar], P, D, C, F)
end


## Strength 3 recursions: CMTW 2006, Section 3

"""
    _roux_double(C3, C2) -> CA(N3 + N2; 3, 2k, 2)

CMTW 2006, Theorem 3.1 (Roux): two copies of a CA(N3; 3, k, 2) side by side,
then a CA(N2; 2, k, 2) beside its complement.
"""
_roux_double(C3::Matrix{Int}, C2::Matrix{Int}) = vcat(hcat(C3, C3), hcat(C2, 1 .- C2))

"""
    _ck_double(C3, C2, v) -> CA(N3 + (v - 1) N2; 3, 2k, v)

CMTW 2006, Theorem 3.2 (Chateauneuf & Kreher): two copies of a
CA(N3; 3, k, v), then, for each nonzero s, a CA(N2; 2, k, v) beside itself
shifted by s modulo v.
"""
function _ck_double(C3::Matrix{Int}, C2::Matrix{Int}, v::Int)
    blocks = [hcat(C3, C3)]
    for s in 1:(v - 1)
        push!(blocks, hcat(C2, mod.(C2 .+ s, v)))
    end
    return reduce(vcat, blocks)
end

"""
    _cmtw_multiply(C3, C2, F) -> CA(N3 + (v - 1) N2 + v^3 - v^2; 3, v k, v), for v = q >= 3

CMTW 2006, Theorem 3.4. Columns are pairs (f, h) of a column f of the
ingredients and a field element h, f-major. G1 is v copies of C3. G2 holds,
for each row of C2 and each nonzero s, the entry `c + s h`. G3 holds, for
each polynomial `b0 + b1 x + b2 x^2` with `b2 != 0`, its value at h.
"""
function _cmtw_multiply(C3::Matrix{Int}, C2::Matrix{Int}, F::GaloisField)
    v = F.q
    k = size(C3, 2)
    size(C2, 2) == k || throw(ArgumentError("C3 and C2 need the same number of columns"))
    column(f, h) = (f - 1) * v + h + 1
    G1 = zeros(Int, size(C3, 1), v * k)
    G2 = zeros(Int, (v - 1) * size(C2, 1), v * k)
    G3 = zeros(Int, v^3 - v^2, v * k)
    for f in 1:k, h in 0:(v - 1)
        G1[:, column(f, h)] .= view(C3, :, f)
        row = 0
        for r in axes(C2, 1), s in 1:(v - 1)
            row += 1
            G2[row, column(f, h)] = _plus(F, C2[r, f], _times(F, s, h))
        end
        row = 0
        for b2 in 1:(v - 1), b1 in 0:(v - 1), b0 in 0:(v - 1)
            row += 1
            G3[row, column(f, h)] = _plus(F, _plus(F, b0, _times(F, b1, h)), _times(F, b2, _times(F, h, h)))
        end
    end
    return vcat(G1, G2, G3)
end


## Small strength-3 arrays used as entries and ingredients

"""
    _paley12() -> CA(12; 3, 11, 2)

A row of ones and the eleven cyclic shifts of the quadratic residues modulo
11: the Paley Hadamard matrix of order 12 without its constant column. CMTW
2006, Table 1, lists 12 rows for 11 columns under "binary construction"; the
papers in papers/ do not give the array, and this form was found by trying
the Hadamard matrix and checking it. With a row of zeros in place of the row
of ones it does not cover.
"""
function _paley12()
    residues = Set(mod(x * x, 11) for x in 1:10)
    A = zeros(Int, 12, 11)
    A[1, :] .= 1
    for i in 0:10, j in 0:10
        A[i + 2, j + 1] = mod(j - i, 11) in residues
    end
    return A
end

# The one-factorization of the complete graph on n2 vertices by rotation:
# vertex n2 - 1 is fixed, the others turn modulo n2 - 1.
function _one_factorization(n2::Int)
    m = n2 - 1
    return [[(m, j); [(mod(j + i, m), mod(j - i, m)) for i in 1:((m - 1) ÷ 2)]] for j in 0:(m - 1)]
end

# The permutations of 0:n-1, each as its vector of images, in a fixed order.
function _permutations(n::Int)
    n == 1 && return [[0]]
    out = Vector{Int}[]
    for p in _permutations(n - 1), pos in 0:(n - 1)
        push!(out, [p[1:pos]; n - 1; p[(pos + 1):end]])
    end
    return out
end

_is_even_permutation(p::Vector{Int}) = iseven(count(p[i] > p[j] for i in eachindex(p) for j in (i + 1):length(p)))

"The rows of a vector of rows, as a matrix."
_rows_matrix(rows::Vector{Vector{Int}}) = permutedims(reduce(hcat, rows))

"""
    _group_ca33() -> CA(33; 3, 6, 3), which is optimal

Colbourn 2004, Theorems 3.2 (v = 3, q = 2) and 3.3. Label the edges of each
one-factor of K6 with the three symbols; a vertex takes the label of its
edge. Apply all six permutations of the symbols, and add the three constant
rows.
"""
function _group_ca33()
    rows = Vector{Int}[]
    for factor in _one_factorization(6), g in _permutations(3)
        row = zeros(Int, 6)
        for (label, (x, y)) in enumerate(factor)
            row[x + 1] = g[label]
            row[y + 1] = g[label]
        end
        push!(rows, row)
    end
    append!(rows, [fill(s, 6) for s in 0:2])
    return _rows_matrix(rows)
end

"""
    _group_ca88(; as_printed = false) -> CA(88; 3, 8, 4)

Colbourn 2004, Example 3.4 and Figure 2: the matrix of a labelled
one-factorization of K8, developed by the twelve even permutations of the
symbols, with the four constant rows. A misprint: Figure 2 prints the last
row as `2 2 2 1 2 1 0`. Rows 2 to 8 are cyclic shifts of one another, and the
last must be `2 3 3 1 2 1 0` for each column to be a one-factor; with the
printed row the array does not cover. `as_printed` builds it with the
printed row, for the test that shows so.
"""
function _group_ca88(; as_printed::Bool = false)
    M = [0 0 0 0 0 0 0
         0 2 3 3 1 2 1
         1 0 2 3 3 1 2
         2 1 0 2 3 3 1
         1 2 1 0 2 3 3
         3 1 2 1 0 2 3
         3 3 1 2 1 0 2
         2 3 3 1 2 1 0]      # Figure 2 prints 2 2 2 1 2 1 0 here (see above)
    as_printed && (M[8, :] .= [2, 2, 2, 1, 2, 1, 0])
    rows = Vector{Int}[]
    for j in 1:7, g in filter(_is_even_permutation, _permutations(4))
        push!(rows, [g[M[x, j] + 1] for x in 1:8])
    end
    append!(rows, [fill(s, 8) for s in 0:3])
    return _rows_matrix(rows)
end

# Chateauneuf & Kreher 2002, p.223: the columns of the starter array M, each
# moved by every map of the group, and then the constant rows. M has one row
# for each column of the covering array.
function _develop_columns(M::Matrix{Int}, maps::Vector{Vector{Int}}, v::Int)
    rows = [[g[M[x, j] + 1] for x in axes(M, 1)] for j in axes(M, 2) for g in maps]
    append!(rows, [fill(s, size(M, 1)) for s in 0:(v - 1)])
    return _rows_matrix(rows)
end

"""
    _ck_ca10() -> CA(10; 3, 5, 2), which is optimal

Chateauneuf & Kreher 2002, Figure 4 and Theorem 2.3. Five rows and their
complements; the first is all ones, so the array has two constant rows.
"""
function _ck_ca10()
    half = [1 1 1 1 1
            1 0 0 1 1
            0 1 0 1 1
            0 0 1 0 1
            1 1 0 0 1]
    return vcat(half, 1 .- half)
end

"""
    _ck_ca45() -> CA(45; 3, 8, 3)

Chateauneuf & Kreher 2002, Theorems 3.5 and 3.6, Figures 6 and 7. Column j of
the starter array labels the points 0:6 and infinity by a parallel class of a
near-resolvable design: {j, inf} is 0, {1, 2, 4} + j is 1, {3, 5, 6} + j is 2.
The six permutations of the symbols move each column. The first seven columns
of the result are the CA(45; 3, 7, 3) of Theorem 3.5.
"""
function _ck_ca45()
    label = [0, 1, 1, 2, 1, 2, 2]             # of the residues 0:6 modulo 7
    M = [x == 7 ? 0 : label[mod(x - j, 7) + 1] for x in 0:7, j in 0:6]
    return _develop_columns(M, _permutations(3), 3)
end

"""
    _ck_ca51() -> CA(51; 3, 9, 3)

Chateauneuf & Kreher 2002, Theorem 3.7 and Figure 8. The eight columns of the
starter array are the parallel classes of two disjoint Steiner triple systems
on nine points; the three triples of a class are labelled 0, 1, 2.
"""
function _ck_ca51()
    classes = [
        [[0, 1, 2], [3, 4, 5], [6, 7, 8]], [[0, 3, 6], [1, 4, 7], [2, 5, 8]],
        [[0, 4, 8], [1, 5, 6], [2, 3, 7]], [[1, 3, 8], [2, 4, 6], [0, 5, 7]],
        [[0, 1, 8], [2, 3, 4], [5, 6, 7]], [[0, 2, 5], [1, 3, 6], [4, 7, 8]],
        [[0, 3, 7], [1, 4, 5], [2, 6, 8]], [[3, 5, 8], [0, 4, 6], [1, 2, 7]],
    ]
    M = zeros(Int, 9, 8)
    for (j, class) in enumerate(classes), (label, block) in enumerate(class), x in block
        M[x + 1, j] = label - 1
    end
    return _develop_columns(M, _permutations(3), 3)
end

"""
    _ck_ca185() -> CA(185; 3, 10, 5)

Chateauneuf & Kreher 2002, Theorem 3.4 and Figure 5. Each column of the
starter array labels the edges of a one-factor of K10 with the five symbols.
The twenty maps x -> a x + b modulo 5 move each column.
"""
function _ck_ca185()
    M = [0 0 0 0 0 0 0 0 0
         0 1 1 1 1 1 1 1 1
         1 1 0 2 4 2 3 3 4
         1 0 1 4 2 3 2 4 3
         2 4 3 1 0 2 4 2 3
         2 3 4 0 1 4 2 3 2
         4 3 2 4 3 1 0 2 4
         4 2 3 3 4 0 1 4 2
         3 4 2 3 2 4 3 1 0
         3 2 4 2 3 3 4 0 1]
    return _develop_columns(M, _affine_maps(GaloisField(5)), 5)
end


## Strength 3 on q + 1 symbols: Cohen, Colbourn & Ling 2008

"""
    _ordered_design(F) -> OD(3, q + 1, q + 1), with q^3 - q rows

The maps of PGL(2, q) as rows (`_projective_maps`). Every three columns show
every triple of three different symbols exactly once (Cohen, Colbourn & Ling
2008, Section 3.1).
"""
_ordered_design(F::GaloisField) = _rows_matrix(_projective_maps(F))

"Cohen, Colbourn & Ling 2008, Table 3: a CA(12; 3, 6, 2) whose first two rows are constant."
const _CCL_TABLE3 = [0 0 0 0 0 0
                     1 1 1 1 1 1
                     0 1 1 0 1 0
                     0 0 1 1 0 1
                     0 0 0 0 1 1
                     0 1 0 1 1 1
                     1 1 0 1 0 0
                     1 1 0 0 0 1
                     1 0 0 1 1 0
                     1 0 1 0 0 1
                     1 0 1 0 1 0
                     0 1 1 1 0 0]

"Cohen, Colbourn & Ling 2008, Table 4: a CA(13; 3, 10, 2) whose first two rows are constant."
const _CCL_TABLE4 = [0 0 0 0 0 0 0 0 0 0
                     1 1 1 1 1 1 1 1 1 1
                     1 1 1 0 1 0 0 0 0 1
                     1 0 1 1 0 1 0 1 0 0
                     1 0 0 0 1 1 1 0 0 0
                     0 1 1 0 0 1 0 0 1 0
                     0 0 1 0 1 0 1 1 1 0
                     1 1 0 1 0 0 1 0 1 0
                     0 0 0 1 1 1 0 0 1 1
                     0 0 1 1 0 0 1 0 0 1
                     0 1 0 1 1 0 0 1 0 0
                     1 0 0 0 0 0 0 1 1 1
                     0 1 0 0 0 1 1 1 0 1]

"""
    _two_constant_rows(A) -> Matrix{Int}

The binary array `A` with its first two rows constant, 0 and 1. If two rows
differ in every column, the symbols of each column are swapped where needed
to make them constant, which does not change what a binary array covers.
Otherwise the complement of the first row is added first.
"""
function _two_constant_rows(A::Matrix{Int})
    N, k = size(A)
    pairs = [(i, j) for i in 1:N for j in (i + 1):N]
    found = findfirst(p -> all(A[p[1], c] != A[p[2], c] for c in 1:k), pairs)
    # One binding each: `A` is captured above, and a captured variable that is
    # assigned again is boxed, which makes the result `Any`.
    E = found === nothing ? vcat(A, 1 .- A[1:1, :]) : A
    i, j = found === nothing ? (1, N + 1) : pairs[found]
    B = [E[r, c] ⊻ E[i, c] for r in axes(E, 1), c in 1:k]
    return B[[i; j; setdiff(axes(B, 1), (i, j))], :]
end

"""
    _od_strength3(F, T, k = q + 1) -> CA(q^3 - q + binomial(q + 1, 2) (N - 2) + q + 1; 3, k, q + 1)

Cohen, Colbourn & Ling 2008, Construction 2, on the first `k` columns. The
ordered design covers every triple of three different symbols. `T` is a
CA(N; 3, k, 2) whose first two rows are constant, 0 and 1. For each pair of
symbols a < b, the other N - 2 rows of `T`, written with a for 0 and b for 1,
cover the triples that show both a and b. The q + 1 constant rows cover the
rest.
"""
function _od_strength3(F::GaloisField, T::Matrix{Int}, k::Int = F.q + 1)
    v = F.q + 1
    3 <= k <= v || throw(ArgumentError("_od_strength3 needs 3 <= k <= q + 1"))
    (size(T, 2) >= k && all(==(0), view(T, 1, 1:k)) && all(==(1), view(T, 2, 1:k))) ||
        throw(ArgumentError("T needs $k columns and first rows of 0 and of 1"))
    body = T[3:end, 1:k]
    blocks = [_ordered_design(F)[:, 1:k]]
    for a in 0:(v - 2), b in (a + 1):(v - 1)
        push!(blocks, [x == 0 ? a : b for x in body])
    end
    push!(blocks, [s for s in 0:(v - 1), _ in 1:k])
    return reduce(vcat, blocks)
end
