# The coverage index (plan §4.3 of design/20261003_solver_plan.md): for each
# support that carries targets, each combination's mixed-radix code, and per
# combination a required bit and a count of the design's rows that hold it.
# It is introduced with the row reducer (`Compact`, compact.jl), its only
# consumer. GND and `coverage` may adopt it later, in place of the arithmetic
# they keep (GND's `MatrixCoverage`, measure.jl's marks). The certifier's
# recount (`_recount`, request.jl) counts on the same layout, the request's
# `TargetList`, but with marks of its own and the excluded targets' ids, never
# an index an engine builds or the bits it holds (contract §1.21, Phase 5).
# IPOG's lookup core (Phase 4, ipog_core.jl) keeps a map of one step's
# supports of its own, laid out for its lookups.
#
# Everything here is index space: a row is a complete vector of engine
# positions, `1:arity[i]` for parameter `i` (request.jl). The codes are the
# package's one mixed-radix code (`_code`, space.jl) with the ordinary arity as
# radix, so combination `code` on support `s` is the target that `TargetList`
# lists at `offsets[s] + code + 1`, and that number is the combination's id
# here.

"""
    CoverageIndex(request, targets::RequiredTargets)

The coverage index of plan §4.3, empty: for each support `s` of `targets`
(`supports`, in target order), each of its `ncombinations(targets, s)`
combinations has an id, `offsets[s] + code + 1`, where `code` is `_code` of
the combination's entries with `request.arity` as radix. Per id the index
keeps whether the combination is a required target (`isrequired`) and how
many of the rows it holds contain it. Rows are added and removed whole
(`add_row!`, `remove_row!`) or changed one entry at a time (`move_entry!`),
and the index answers, without allocating: a row's combination on a support
(`combination`), the score of an entry move (`entry_score`), the required
combinations only one row holds (`singly_covered`), and the uncovered
required combinations (`nuncovered`, `random_uncovered`, `decode!`).

**Memory.** Two bytes of count and two bits per combination (the required
bit, which is the targets' and not copied, and a bit that marks an id on the
uncovered list), plus, per support, its
members and their strides, and, per parameter, the supports that hold it.
The uncovered list holds ids, and only of combinations that became
uncovered: it is built when it is first needed (a fresh index has every
required combination uncovered, and a design added to it leaves few), and
an id stays on it until a draw finds it covered or the design is complete
(`random_uncovered`, `_forget_covered!`).

**Counts.** A count is a `UInt16`, which is the plan's two bytes a
combination (§2.8). Each row adds one to exactly one combination of each
support, and an entry move takes it from one combination to another, so a
count is at most the number of rows the index holds. `add_row!` refuses a row
past `typemax(UInt16)` = 65,535 rows with an internal error, so a count never
wraps. The supported scale holds designs of more rows (three parameters of
64 values at strength 3 need 262,144), which `Compact` leaves unreduced
(`:rows_cap`); the designs it reduces have thousands (IPOG's 7,168 for
8 × 64). A consumer that counts more rows needs a wider count, which can
become a type parameter.

The structure is read-only for its consumers; its fields are internal. The
arity, supports, offsets and required bits are `targets`' own (its layout and
its bits, `RequiredTargets`), not copies, and must not be changed; an index
made for each run keeps its own counts and uncovered list, so runs that share
targets share no search state.
"""
mutable struct CoverageIndex
    arity::Vector{Int}
    supports::_Supports          # the targets' supports, computed (`_Supports`); the index reads its own members
    offsets::Vector{Int}         # offsets[s] combinations come before support s; the last entry is the total
    member_first::Vector{Int}    # support s's members are members[member_first[s]:member_first[s + 1] - 1]
    members::Vector{Int}
    strides::Vector{Int}         # each member's stride in its support's code
    holder_first::Vector{Int}    # parameter p is held by holder_support[holder_first[p]:holder_first[p + 1] - 1]
    holder_support::Vector{Int}
    holder_stride::Vector{Int}   # p's stride in that support
    count::Vector{UInt16}        # rows that hold each combination, by id
    required::BitVector          # whether each combination is a required target, by id
    uncovered::Vector{Int}       # ids of required combinations that were uncovered; some may be covered again
    listed::BitVector            # whether an id is on `uncovered`
    listing::Bool                # whether every uncovered required combination is on `uncovered`
    n_uncovered::Int             # required combinations that no row holds
    rows::Int                    # rows the index holds
end

function CoverageIndex(request::Request, targets::RequiredTargets)
    # The arity, supports, offsets and required bits are the targets' own,
    # shared and never changed (`RequiredTargets`); the counts and the
    # uncovered list are this index's.
    layout = targets.layout
    arity, sets, offsets = layout.arity, layout.supports, layout.offsets
    arity == request.arity || error("internal error: the coverage index's targets are not the request's")
    member_first = ones(Int, length(sets) + 1)
    members, strides = Int[], Int[]
    held = [Tuple{Int, Int}[] for _ in arity]   # (support, stride) for each parameter
    for (s, support) in _each_support(sets)
        stride = 1
        for p in support
            push!(members, p)
            push!(strides, stride)
            push!(held[p], (s, stride))
            stride *= arity[p]
        end
        stride == ncombinations(targets, s) ||
            error("internal error: support $support has $(ncombinations(targets, s)) combinations, not $stride")
        member_first[s + 1] = length(members) + 1
    end
    holder_first = ones(Int, length(arity) + 1)
    for p in eachindex(arity)
        holder_first[p + 1] = holder_first[p] + length(held[p])
    end
    holder_support = Int[s for h in held for (s, _) in h]
    holder_stride = Int[stride for h in held for (_, stride) in h]
    total = last(offsets)
    required = _required_bits(targets)   # built now if no one asked before, then shared
    uncovered = count(required)
    return CoverageIndex(arity, sets, offsets, member_first, members, strides, holder_first,
                         holder_support, holder_stride, zeros(UInt16, total), required, Int[],
                         falses(total), uncovered == 0, uncovered, 0)
end

"The number of combinations the index counts, over every support: its length in counts."
ncombinations(index::CoverageIndex) = last(index.offsets)

"The number of required combinations that no row of the index holds."
nuncovered(index::CoverageIndex) = index.n_uncovered

"The number of rows the index holds."
nrows(index::CoverageIndex) = index.rows

"How many of the index's rows hold the combination `id`."
cover_count(index::CoverageIndex, id::Integer) = Int(index.count[id])

"Whether the combination `id` is a required target."
isrequired(index::CoverageIndex, id::Integer) = index.required[id]

"""
    combination(index, s, row) -> Int

The id of `row`'s combination on support `s`: `offsets[s] + code + 1`, with
`code` the row's `_code` on the support. `row` is a complete row of engine
positions (`_check_row`).
"""
function combination(index::CoverageIndex, s::Int, row::AbstractVector{<:Integer})
    checkbounds(index.supports, s)
    _check_row(index, row)
    return _combination(index, s, row)
end

# The hot loops read rows the index holds, whose positions were checked when
# they were added (`add_row!`) or moved (`move_entry!`, which checks the new
# position only), on supports `s` of the index, so every id they compute is in
# bounds and they skip the checks. `_combination`, `_entry_score` and
# `_singly_covered` are those loops' unchecked forms; `combination`,
# `entry_score` and `singly_covered` check their arguments first, and
# `move_entry!` is unchecked but for the new position.
@inline function _combination(index::CoverageIndex, s::Int, row::AbstractVector{<:Integer})
    @inbounds begin
        id = index.offsets[s] + 1
        for m in index.member_first[s]:(index.member_first[s + 1] - 1)
            id += (row[index.members[m]] - 1) * index.strides[m]
        end
    end
    return id
end

# One more row holds `id`. Its count can't pass the rows the index holds.
@inline function _cover!(index::CoverageIndex, id::Int)
    @inbounds c = index.count[id]
    @inbounds index.count[id] = c + one(UInt16)
    c == 0 && @inbounds(index.required[id]) && (index.n_uncovered -= 1)
    return nothing
end

# One fewer row holds `id`; a required combination left uncovered goes on the
# list. A count already at zero means the row was never added.
@inline function _uncover!(index::CoverageIndex, id::Int)
    @inbounds c = index.count[id]
    c == 0 && error("internal error: removing a combination that no row of the coverage index holds")
    c -= one(UInt16)
    @inbounds index.count[id] = c
    if c == 0 && @inbounds(index.required[id])
        index.n_uncovered += 1
        if !index.listed[id]
            push!(index.uncovered, id)
            index.listed[id] = true
        end
    end
    return nothing
end

"Throw an internal error unless `row` is a complete row of engine positions for this index."
function _check_row(index::CoverageIndex, row::AbstractVector{<:Integer})
    length(row) == length(index.arity) ||
        error("internal error: a row of $(length(row)) entries for $(length(index.arity)) parameters")
    for p in eachindex(row)
        1 <= row[p] <= index.arity[p] ||
            error("internal error: row $row has position $(row[p]) for parameter $p, outside 1:$(index.arity[p])")
    end
    return nothing
end

"""
    add_row!(index, row)

Count a complete row of engine positions: each of its combinations, one per
support, gains one. An internal error for an incomplete row, a position out
of range, or a row past `typemax(UInt16)` rows (`CoverageIndex`).
"""
function add_row!(index::CoverageIndex, row::AbstractVector{<:Integer})
    _check_row(index, row)
    index.rows < typemax(UInt16) ||
        error("internal error: a coverage index holds at most $(typemax(UInt16)) rows")
    index.rows += 1
    for s in eachindex(index.supports)
        _cover!(index, _combination(index, s, row))
    end
    return index
end

"""
    remove_row!(index, row)

Stop counting a row the index holds: each of its combinations loses one, and
a required combination that no row holds any more becomes uncovered.
"""
function remove_row!(index::CoverageIndex, row::AbstractVector{<:Integer})
    _check_row(index, row)
    index.rows > 0 || error("internal error: removing a row from an empty coverage index")
    index.rows -= 1
    for s in eachindex(index.supports)
        _uncover!(index, _combination(index, s, row))
    end
    return index
end

"""
    move_entry!(index, row, p, w)

Change entry `p` of `row`, a row the index holds, to position `w`, and move
the row's count on every support that holds `p` from its old combination to
its new one. Supports without `p` don't change.

Unchecked but for `w`: the reducer's inner loop calls it on every move, and
checking the whole row (`_check_row`) would read every entry for a move that
reads only the supports holding `p`. So `row` must be a row the index holds,
whose positions `add_row!` checked; a row of another length, or not held,
reads or counts out of bounds without an error.
"""
function move_entry!(index::CoverageIndex, row::AbstractVector{<:Integer}, p::Int, w::Int)
    1 <= w <= index.arity[p] || error("internal error: position $w for parameter $p, outside 1:$(index.arity[p])")
    shift = w - row[p]
    shift == 0 && return index
    @inbounds for h in index.holder_first[p]:(index.holder_first[p + 1] - 1)
        id = _combination(index, index.holder_support[h], row)
        _uncover!(index, id)
        _cover!(index, id + shift * index.holder_stride[h])
    end
    row[p] = w
    return index
end

"""
    entry_score(index, row, p, w) -> Int

What changing entry `p` of `row`, a row the index holds, to position `w`
would do to coverage, as FastCA scores a move (Lin et al. 2019, p.4): the
required combinations it would cover that no row covers, less the required
combinations that only this row covers and would lose. Combinations covered
twice or more can't change either way, so only those covered at most once
count. Supports without `p` don't change, so only the supports that hold `p`
are read. Nothing is changed.
"""
function entry_score(index::CoverageIndex, row::AbstractVector{<:Integer}, p::Int, w::Int)
    _check_row(index, row)
    1 <= w <= index.arity[p] || error("internal error: position $w for parameter $p, outside 1:$(index.arity[p])")
    return _entry_score(index, row, p, w)
end

# Without branches on the counts, which a move's supports make unpredictable.
@inline function _entry_score(index::CoverageIndex, row::AbstractVector{<:Integer}, p::Int, w::Int)
    shift = w - row[p]
    shift == 0 && return 0
    gain = 0
    loss = 0
    count, required = index.count, index.required
    @inbounds for h in index.holder_first[p]:(index.holder_first[p + 1] - 1)
        id = _combination(index, index.holder_support[h], row)
        moved = id + shift * index.holder_stride[h]
        gain += (count[moved] == 0) & required[moved]
        loss += (count[id] == 1) & required[id]
    end
    return gain - loss
end

"""
    singly_covered(index, row) -> Int

The required combinations that `row`, a row the index holds, is the only row
to hold: those that removing it would leave uncovered.
"""
singly_covered(index::CoverageIndex, row::AbstractVector{<:Integer}) =
    (_check_row(index, row); first(_singly_covered(index, row, typemax(Int))))

"""
    _singly_covered(index, row, limit) -> (alone, read)

`singly_covered`, counted only until it reaches `limit`: `alone` is the
count, or `limit` if it gets there, and `read` the supports read, at most
all of them. A reducer choosing the row with the fewest needs no more.
"""
function _singly_covered(index::CoverageIndex, row::AbstractVector{<:Integer}, limit::Int)
    alone = 0
    for s in eachindex(index.supports)
        id = _combination(index, s, row)
        if @inbounds(index.count[id] == 1 && index.required[id])
            alone += 1
            alone >= limit && return alone, s
        end
    end
    return alone, length(index.supports)
end

"""
    random_uncovered(index, rng) -> Int

The id of a required combination that no row holds, chosen uniformly at
random among them with `rng`. There must be one (`nuncovered(index) > 0`).
The uncovered list is lazy: an id drawn that some row covers again is dropped
from it, and the draw is repeated, which keeps the choice uniform.
"""
function random_uncovered(index::CoverageIndex, rng::AbstractRNG)
    index.n_uncovered > 0 || error("internal error: no uncovered combination to choose")
    index.listing || _list_uncovered!(index)
    list = index.uncovered
    while true
        k = rand(rng, eachindex(list))
        id = list[k]
        index.count[id] == 0 && return id
        list[k] = list[end]
        pop!(list)
        index.listed[id] = false
    end
end

"Put every uncovered required combination on the uncovered list, once: one pass over the ids."
function _list_uncovered!(index::CoverageIndex)
    for id in eachindex(index.count)
        if index.count[id] == 0 && index.required[id] && !index.listed[id]
            push!(index.uncovered, id)
            index.listed[id] = true
        end
    end
    index.listing = true
    return index
end

"Empty the uncovered list when nothing is uncovered, so that it doesn't keep ids covered long ago."
function _forget_covered!(index::CoverageIndex)
    index.n_uncovered == 0 || return index
    for id in index.uncovered
        index.listed[id] = false
    end
    empty!(index.uncovered)
    index.listing = true
    return index
end

"The support that combination `id` lies on."
support_of(index::CoverageIndex, id::Integer) = searchsortedlast(index.offsets, id - 1)

"""
    decode!(values, index, id) -> s

Write the positions of combination `id` into `values[1:t]`, in the order of
its support's members, and return the support `s`; `t` is the support's size.
"""
function decode!(values::Vector{Int}, index::CoverageIndex, id::Integer)
    s = support_of(index, id)
    code = id - 1 - index.offsets[s]
    for (k, m) in enumerate(index.member_first[s]:(index.member_first[s + 1] - 1))
        a = index.arity[index.members[m]]
        values[k] = code % a + 1
        code ÷= a
    end
    return s
end

"The parameters of support `s`, as a range into `index.members`."
members_of(index::CoverageIndex, s::Int) = index.member_first[s]:(index.member_first[s + 1] - 1)

"The number of supports that hold parameter `p`: the supports an entry move at `p` reads."
_holders(index::CoverageIndex, p::Int) = index.holder_first[p + 1] - index.holder_first[p]

"The size of the largest support."
function max_support(index::CoverageIndex)
    largest = 0
    for s in eachindex(index.supports)
        largest = max(largest, index.member_first[s + 1] - index.member_first[s])
    end
    return largest
end
