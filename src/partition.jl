# Realization of partitions (plan Phase 6 step 2; contract §4.6–§4.13).
#
# Generation, rules and coverage see a `Partition` by its name (§4.5), and
# returned rows hold the wrapper (§4.6). `realize` is the one place a draw
# runs: it replaces each wrapper by `draw(rng)`, in parameter order, and
# passes every other value through. Coverage is measured on the labeled
# rows, so a caller keeps those beside the realized ones (§4.11).

using Random: AbstractRNG

"""
    realize(case; rng) -> case
    realize(cases; rng) -> Vector

Replace each [`Partition`](@ref) in a row by a value drawn from it:
`draw(rng)`, one call per partition, in parameter order (contract §4.7).
Every other value, [`Invalid`](@ref) markers included, passes through
unchanged, and the row keeps its shape: a `Tuple` stays a `Tuple` of the same
length, and a `NamedTuple` keeps its names and their order (§4.8).

`realize(cases; rng)` realizes each row of a vector of rows, such as a
[`TestCases`](@ref), in order with the same `rng`, and returns a plain
`Vector` of the realized rows, not a `TestCases` (§4.9).

`rng` is required: no draw uses the global random number generator. For a
given row and `rng` state the result is the same, so a seeded generator
repeats it (§4.10):

```jldoctest; setup = :(using UnitTestDesign, Random)
julia> space = TestSpace((tol = [Partition(:tiny, rng -> 1e-9 * rand(rng)), 1e-3], method = [:lu, :qr]));

julia> cases = all_pairs(space)
4 cases · strength 2 · IPOG · 2 parameters · 4 combinations, 4 valid
    tol               method
 1  Partition(:tiny)  :lu
 2  Partition(:tiny)  :qr
 3  0.001             :lu
 4  0.001             :qr

julia> realize(cases; rng = Xoshiro(1)) == realize(cases; rng = Xoshiro(1))
true

julia> realize((tol = Partition(:big, Returns(1e6)), method = :qr); rng = Xoshiro(1))
(tol = 1.0e6, method = :qr)
```

Realized values carry no coverage claim (§4.11): measure coverage on the
labeled rows, and keep them beside the realized inputs. A `draw` that returns
a `Partition` or an `Invalid` is an `ArgumentError` naming the partition
(§4.12).
"""
function realize end

function realize(case::NamedTuple; rng = nothing)
    rng = _realize_rng(rng)
    return NamedTuple{keys(case)}(_realized(Tuple(case), rng))
end

realize(case::Tuple; rng = nothing) = _realized(case, _realize_rng(rng))

function realize(cases::AbstractVector; rng = nothing)
    rng = _realize_rng(rng)
    for (k, row) in enumerate(cases)
        row isa Union{Tuple, NamedTuple} || throw(ArgumentError(
            "realize(cases; rng) takes a vector of rows, each a NamedTuple or a Tuple; row $k is " *
            "a $(typeof(row)) (contract §4.9)"))
    end
    return [realize(row; rng) for row in cases]
end

realize(case; rng = nothing) = throw(ArgumentError(
    "realize takes a row, a NamedTuple or a Tuple, or a vector of rows, such as a TestCases; " *
    "got a $(typeof(case)) (contract §4.7, §4.9)"))

function _realize_rng(rng)
    rng === nothing && throw(ArgumentError(
        "realize needs the keyword rng, a random number generator such as " *
        "realize(cases; rng = Xoshiro(1)); no draw uses the global generator (contract §4.7)"))
    rng isa AbstractRNG || throw(ArgumentError(
        "rng must be a random number generator, an AbstractRNG such as Xoshiro(1), " *
        "got $(repr(rng)) (contract §4.7)"))
    return rng
end

# The values of a row, each partition replaced by one draw, strictly in
# parameter order, so that a seeded `rng` gives the same draws every time.
function _realized(values::Tuple, rng::AbstractRNG)
    out = Vector{Any}(undef, length(values))
    for (k, x) in enumerate(values)
        out[k] = x isa Partition ? _draw(x, rng) : x
    end
    return Tuple(out)
end

function _draw(p::Partition, rng::AbstractRNG)
    value = p.draw(rng)
    value isa Union{Partition, Invalid} && throw(ArgumentError(
        "the draw of Partition($(repr(p.name))) returned $(repr(value)); a draw returns a " *
        "concrete value, and nested wrappers are unsupported (contract §4.12)"))
    return value
end
