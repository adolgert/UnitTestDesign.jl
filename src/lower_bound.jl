# The lower bound a covering result records (plan §4.1, "State the bound";
# §6.1; decision D5): a number of rows that no design for the request can go
# below, with its proof, and whether the result's rows meet it, which is the one
# case this release calls a count minimal (contract §8.4). It is counted from
# what classification and generation already know: the required targets on
# each support, the must-include rows, and the negative targets of each
# invalid value. Nothing here searches.
#
# The argument, which `_ordinary_bound`'s docstring gives in full: a row holds
# exactly one combination on each support, so the required combinations of
# one support need as many rows as there are of them; must-include rows are
# rows of the design, kept with their duplicates (contract §10.5), and hold at
# most one combination each on a support; and ordinary and negative rows are
# counted apart, because each covers only targets of its own kind (§5.9) and
# a row holds one invalid value at most (§5.7).

"""
    _SupportBound

The bound that one support gives (`_ordinary_bound`): `rows`, the bound;
`support`, its parameters (0 when no support has a required combination);
`need`, its required combinations; `total`, all its combinations, the
product of its value counts; `held`, the distinct required combinations on
it that the must-include rows set on all of it hold; `unset`, the
must-include rows with a parameter of it unset; and `m`, the must-include
rows.
"""
struct _SupportBound
    rows::Int
    support::Int
    need::Int
    total::Int
    held::Int
    unset::Int
    m::Int
end

"""
    _ordinary_bound(request, targets::RequiredTargets) -> _SupportBound

A number of rows that no covering design for `request` can have fewer of
(plan §4.1); the fewest a design can have may be more. The design's
must-include rows `M`, `m` of them, are its first rows, and the rest cover
what they leave. For each support `s` with `need(s)` required combinations,
let `held(s)` count the distinct required combinations on `s` that the rows
of `M` set on every parameter of `s` hold, and `unset(s)` the rows of `M`
that leave some parameter of `s` unset. The bound is the largest over the
supports of

    m + max(0, need(s) - held(s) - unset(s)),

and at least `m`. It holds for every design that keeps `M`:

- every row holds exactly one combination on `s`, so covering the `need(s)`
  required combinations takes as many distinct rows that hold them;
- a row of `M` set on all of `s` holds a known combination, and one that
  leaves part of `s` unset holds at most one, whatever its completion; so the
  rows of `M` hold at most `held(s) + unset(s)` of them, and each of the
  others needs a row outside `M`;
- the design has all `m` rows of `M`, duplicates kept (contract §10.5).

Excluded targets are not required (§1.2), so they count nowhere; supports of
`stronger` groups count as any other. Without must-include rows the bound is
the most required combinations on one support, which plan §4.1 names; with
no rules that is the product of the `t` largest value counts. Ties go to the
first support in target order, which the proof names.

The negative rows are bounded apart (`cover_negative`): `targets` are the
ordinary targets of the ordinary request, whose must-include rows are the
ordinary ones.
"""
function _ordinary_bound(request::Request, targets::RequiredTargets)
    must = request.must_include
    m = size(must, 2)
    # Without must-include rows nothing is held, and no buffer is made. With
    # them, buffers for every support: the distinct codes held, at most one
    # per must-include row, and a bit per combination of the largest support.
    m == 0 && return _bound_over_supports(must, targets, nothing)
    return _bound_over_supports(must, targets, (sizehint!(Int[], m), falses(0)))
end

"`_ordinary_bound`'s pass over the supports, with `_held_by`'s buffers, or `nothing` without must-include rows."
function _bound_over_supports(must::Matrix{Int}, targets::RequiredTargets,
                              buffers::Union{Nothing, Tuple{Vector{Int}, BitVector}})
    m = size(must, 2)
    best = _SupportBound(m, 0, 0, 0, 0, 0, m)
    for s in eachindex(supports(targets))
        need = nrequired(targets, s)
        need > 0 || continue
        held, unset = buffers === nothing ? (0, 0) : _held_by(buffers..., must, targets, s, supports(targets)[s])
        rows = m + max(0, need - held - unset)
        rows > best.rows || continue
        best = _SupportBound(rows, s, need, ncombinations(targets, s), held, unset, m)
    end
    return best
end

"""
    _held_by(codes, seen, must, targets, s, members) -> (held, unset)

For the must-include rows `must` (parameters × rows, engine positions, 0 for
unset): the distinct required combinations on support `s` that the rows set
on all of `members` hold, and the rows that leave a member unset
(`_ordinary_bound`). `codes` and `seen` are buffers, reused: `seen` marks a
code once it is counted, so each row costs a constant and nothing is sorted,
which would allocate a sort's scratch space on every support with more than
about 40 codes (Julia 1.10 and 1.13). It grows to the largest support's
combinations, and is clear again on return.
"""
function _held_by(codes::Vector{Int}, seen::BitVector, must::Matrix{Int}, targets::RequiredTargets, s::Int,
                  members::Vector{Int})
    empty!(codes)
    n = ncombinations(targets, s)
    length(seen) < n && fill!(resize!(seen, n), false)
    unset = 0
    for j in axes(must, 2)
        row = view(must, :, j)
        if any(p -> row[p] == 0, members)
            unset += 1
            continue
        end
        code = _code(row, members, targets.arity)
        if isrequired(targets, s, code) && !seen[code + 1]
            seen[code + 1] = true
            push!(codes, code)
        end
    end
    for code in codes
        seen[code + 1] = false
    end
    return length(codes), unset
end

"""
    _bound_record(design_rows, ordinary, negative, names, arity) -> NamedTuple

A covering result's record of its lower bound (plan §4.1, §6.1; D5):
`lower_bound`, the ordinary bound (`_ordinary_bound`) plus the negative one
(`negative`, the sum over invalid values that `cover_negative` returns, 0
without [`Invalid`](@ref) values); `minimal`, whether the design's
`design_rows` equal it, the one case in which this release calls a count
minimal (contract §8.4); and `proof`, why no design has fewer rows, in the
caller's vocabulary, as `report` prints it. Fewer rows than the bound is an
internal error: the bound is proven, so a design below it is a bug.
"""
function _bound_record(design_rows::Int, ordinary::_SupportBound, negative::Int, names::Vector{Symbol},
                       arity::Vector{Int}, supports_list::Vector{Vector{Int}})
    bound = ordinary.rows + negative
    design_rows >= bound || error("internal error: the design has $design_rows rows, below its proven lower " *
                                  "bound of $bound")
    proof = _bound_proof(ordinary, names, arity, supports_list)
    if negative > 0
        proof *= (isempty(proof) ? "" : "; and ") * _plural(negative, "negative case") *
                 ", bounded in the same way for each Invalid value"
    end
    isempty(proof) && (proof = "no combination is feasible, and there is no must-include row")
    return (lower_bound = bound, minimal = design_rows == bound, proof = proof)
end

"""
    _bound_proof(b, names, arity, supports) -> String

The ordinary bound's proof in words (`_bound_record`): "the 6 × 6 = 36
combinations of a and b need a case each", "the 33 feasible combinations of
a and b need a case each" when rules exclude some, "the 3 must-include rows"
when they alone set the bound, or "the 3 must-include rows hold at most 7 of
the 9 combinations of a and b, and the other 2 need a case each". Empty when
nothing sets it.
"""
function _bound_proof(b::_SupportBound, names::Vector{Symbol}, arity::Vector{Int}, supports_list::Vector{Vector{Int}})
    musts = _plural(b.m, "must-include row")
    b.support == 0 && return b.m == 0 ? "" : "the $musts"
    members = supports_list[b.support]
    which = _and_list(string.(names[members]))
    noun = length(members) == 1 ? "value" : "combination"
    combinations = b.need == 1 ? "1 $(b.need == b.total ? "" : "feasible ")$noun of $which" :
                   b.need == b.total && length(members) > 1 ?
                       "$(join(arity[members], " × ")) = $(b.need) $(noun)s of $which" :
                       "$(b.need) $(b.need == b.total ? "" : "feasible ")$(noun)s of $which"
    b.m == 0 && return "the $combinations " * (b.need == 1 ? "needs a case" : "need a case each")
    b.rows == b.m && return "the $musts"
    rest = b.rows - b.m == 1 ? "the other needs a case" : "the other $(b.rows - b.m) need a case each"
    return "the $musts $(b.m == 1 ? "holds" : "hold") at most $(b.held + b.unset) of the $combinations, and $rest"
end

"\"a\", \"a and b\", \"a, b and c\"."
_and_list(xs::Vector{String}) = length(xs) <= 1 ? join(xs) : join(xs[1:(end - 1)], ", ") * " and " * xs[end]
