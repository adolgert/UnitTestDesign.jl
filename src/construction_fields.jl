# Finite fields for the catalog of covering-array constructions (plan §5.4,
# "Field arithmetic lives in the package"; decision D6, no new dependency).
# The Bush arrays, the products of orthogonal arrays, the LFSR arrays, the
# group arrays and the ordered designs all compute over the field of order q,
# a prime power. Each field is a pair of tables over the symbols `0:q-1`, so
# a construction reads `F.add[a + 1, b + 1]` and never does polynomial
# arithmetic itself. The reference implementation the catalog was ported
# from, and checked against, is `constructions.jl` in
# design/20261003_solver_plan_constructions/.

"The largest field the catalog builds: tables of 256 × 256 entries (plan §5.4)."
const _FIELD_LIMIT = 256

"""
    GaloisField(q)

The field of order `q`, a prime power from 2 to 256, as tables over the
symbols `0:q-1`: `add`, `mul`, `neg` (additive inverse) and `inv`
(multiplicative inverse; `inv[1]`, for 0, is 0). For `q = p^m` a symbol's
base-`p` digits are the coefficients of a polynomial over the integers
modulo `p`, constant term first, and multiplication is taken modulo the
first monic polynomial `x^m + c(x)` of degree `m`, in the order of the
symbol `c` that holds its lower coefficients, for which every nonzero symbol
has an inverse: the first irreducible one, found by trying them in order.
`0` and `1` are the field's zero and one. The tables are those of the
reference's `GF(q)`, entry for entry.
"""
struct GaloisField
    q::Int
    p::Int
    add::Matrix{Int}
    mul::Matrix{Int}
    neg::Vector{Int}
    inv::Vector{Int}
end

function GaloisField(q::Integer)
    q = Int(q)
    (2 <= q <= _FIELD_LIMIT && _is_prime_power(q)) || throw(ArgumentError(
        "a Galois field here has a prime power order from 2 to $_FIELD_LIMIT; got $q (plan §5.4)"))
    p, m = _prime_and_degree(q)
    digit = [(a ÷ p^i) % p for i in 0:(m - 1), a in 0:(q - 1)]   # digit[i + 1, a + 1]: coefficient of x^i
    add = [_digitwise((x, y) -> (x + y) % p, digit, a, b, p) for a in 0:(q - 1), b in 0:(q - 1)]
    neg = [_digitwise((x, _) -> (p - x) % p, digit, a, a, p) for a in 0:(q - 1)]
    if m == 1
        mul = [(a * b) % p for a in 0:(q - 1), b in 0:(q - 1)]
        return GaloisField(q, p, add, mul, neg, _inverses(mul))
    end
    # s * a for a scalar s of the prime field; x * a, for a modulus x^m + c(x);
    # and then a * b by Horner's rule on b's digits: r <- x r + b_i a, from the
    # top digit down.
    scaled = [_digitwise((x, _) -> (s * x) % p, digit, a, a, p) for s in 0:(p - 1), a in 0:(q - 1)]
    xtimes = zeros(Int, q)
    mul = zeros(Int, q, q)
    for c in 0:(q - 1)
        for a in 0:(q - 1)
            top = digit[m, a + 1]
            shifted = (a - top * p^(m - 1)) * p           # a without its x^(m-1) term, times x
            # x^m = -c(x), so the top digit contributes -top * c.
            xtimes[a + 1] = add[shifted + 1, neg[scaled[top + 1, c + 1] + 1] + 1]
        end
        if _fill_products!(mul, xtimes, add, scaled, digit, q, m)
            return GaloisField(q, p, add, mul, neg, _inverses(mul))
        end
    end
    error("internal error: no irreducible polynomial of degree $m over the integers modulo $p")
end

"`(p, m)` with `q = p^m`, for a prime power `q`."
function _prime_and_degree(q::Int)
    p = 2
    while q % p != 0
        p += 1
    end
    m = 0
    while p^m < q
        m += 1
    end
    return p, m
end

"The symbol whose `i`-th base-`p` digit is `f` of the `i`-th digits of `a` and `b`."
function _digitwise(f::F, digit::Matrix{Int}, a::Int, b::Int, p::Int) where {F}
    s = 0
    for i in size(digit, 1):-1:1
        s = s * p + f(digit[i, a + 1], digit[i, b + 1])
    end
    return s
end

# The products a * b for the modulus whose multiplication by x is `xtimes`,
# into `mul`. Stops and returns false at the first zero product of two
# nonzero symbols: the modulus is then reducible, and no row of the table is
# a permutation, which is the reference's test of the same polynomial.
function _fill_products!(mul::Matrix{Int}, xtimes::Vector{Int}, add::Matrix{Int}, scaled::Matrix{Int},
                         digit::Matrix{Int}, q::Int, m::Int)
    for a in 0:(q - 1), b in 0:(q - 1)
        r = 0
        for i in m:-1:1
            r = add[xtimes[r + 1] + 1, scaled[digit[i, b + 1] + 1, a + 1] + 1]
        end
        a != 0 && b != 0 && r == 0 && return false
        mul[a + 1, b + 1] = r
    end
    return true
end

function _inverses(mul::Matrix{Int})
    q = size(mul, 1)
    inv = zeros(Int, q)
    for a in 1:(q - 1)
        inv[a + 1] = findfirst(==(1), view(mul, a + 1, :)) - 1
    end
    return inv
end

@inline _plus(F::GaloisField, a::Integer, b::Integer) = @inbounds F.add[a + 1, b + 1]
@inline _times(F::GaloisField, a::Integer, b::Integer) = @inbounds F.mul[a + 1, b + 1]
@inline _minus(F::GaloisField, a::Integer) = @inbounds F.neg[a + 1]

"""
    _primitive_cubic(F) -> (c0, c1, c2)

The coefficients of the first primitive cubic `x^3 + c2 x^2 + c1 x + c0` over
`F`, in the order `c0` in `1:q-1`, then `c1`, then `c2`: the one whose linear
recurrence `a_i = -(c2 a_(i-1) + c1 a_(i-2) + c0 a_(i-3))` has period
`q^3 - 1` (the LFSR arrays, Raaphorst, Moura & Stevens 2014, Theorem 6).
"""
function _primitive_cubic(F::GaloisField)
    q = F.q
    for c0 in 1:(q - 1), c1 in 0:(q - 1), c2 in 0:(q - 1)
        a, b, c = 0, 0, 1                     # the state (a_(i-3), a_(i-2), a_(i-1))
        period = 0
        while true
            next = _minus(F, _plus(F, _plus(F, _times(F, c2, c), _times(F, c1, b)), _times(F, c0, a)))
            a, b, c = b, c, next
            period += 1
            ((a, b, c) == (0, 0, 1) || period > q^3) && break
        end
        period == q^3 - 1 && return (c0, c1, c2)
    end
    error("internal error: no primitive cubic over the field of order $q")
end

"""
    _affine_maps(F) -> Vector{Vector{Int}}

The `q (q - 1)` maps `x -> a x + b` with `a != 0` over `F`, `a` in the outer
order and `b` in the inner, each as its vector of images of `0:q-1`. They
form a sharply 2-transitive group (Chateauneuf & Kreher 2002, p.223), which
`_ck_ca185` develops its starter by.
"""
_affine_maps(F::GaloisField) =
    [[_plus(F, _times(F, a, x), b) for x in 0:(F.q - 1)] for a in 1:(F.q - 1) for b in 0:(F.q - 1)]

"""
    _projective_maps(F) -> Vector{Vector{Int}}

The `q^3 - q` maps `x -> (a x + b) / (c x + d)` of PGL(2, q) on the field and
infinity, each as its vector of images of `0:q`, where `q` stands for
infinity. One matrix is taken from each class of scalar multiples: `c = 0`
and `d = 1`, then `c = 1`. The group is sharply 3-transitive (Chateauneuf &
Kreher 2002, p.224), so its maps as rows are an ordered design
(`_ordered_design`).
"""
function _projective_maps(F::GaloisField)
    q = F.q
    maps = Vector{Int}[]
    for a in 1:(q - 1), b in 0:(q - 1)                    # x -> a x + b, which fixes infinity
        push!(maps, [[_plus(F, _times(F, a, x), b) for x in 0:(q - 1)]; q])
    end
    for a in 0:(q - 1), b in 0:(q - 1), d in 0:(q - 1)    # x -> (a x + b) / (x + d)
        b == _times(F, a, d) && continue                  # determinant a d - b = 0
        image = map(0:(q - 1)) do x
            below = _plus(F, x, d)
            below == 0 ? q : _times(F, _plus(F, _times(F, a, x), b), F.inv[below + 1])
        end
        push!(maps, [image; a])
    end
    return maps
end
