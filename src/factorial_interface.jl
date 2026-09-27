## all_values
## all_pairs
## all_triples
## all_tuples
## values_excursion
## pairs_excursion
## triples_excursion
## full_factorial
#
# The 0.4 positional entry points. Each builds a TestSpace whose parameters
# are named p1, p2, ... from the positional domains, builds a Request, asks an
# engine for a Design, and returns the rows in the 0.4 shape, a vector of
# `Vector{Any}`. Phase 4 changes the return type to `TestCases{Tuple}`
# (contract §13.4).


# Remove in Phase 6. The positional generators treat every value as an
# ordinary one, so they would return rows with several `Invalid` values and
# partitions that are never drawn. Until negative generation arrives, they
# refuse wrapper values instead of applying different semantics (contract
# §0.2; plan Phase 2 step 2). `Request` refuses them too; this message names
# the argument's position, which is the caller's vocabulary here.
function _reject_wrappers(parameters)
    for (position, domain) in enumerate(parameters)
        for value in domain
            (value isa Invalid || value isa Partition) || continue
            throw(ArgumentError(
                "parameter $position lists $(repr(value)), but generation with Invalid or " *
                "Partition values is not supported yet; it arrives in a later release phase " *
                "(contract §0.2). A TestSpace accepts these values for isallowed and explain."))
        end
    end
    return nothing
end


"""
    _positional_space(parameters) -> TestSpace

A space whose parameters are named `p1`, `p2`, ... in argument order, with the
given domains. Values and their types are kept; `nothing` and `missing` are
values (contract §2.9).
"""
function _positional_space(parameters)
    isempty(parameters) && throw(ArgumentError(
        "pass the values of at least one parameter, for example all_values([1, 2, 3])"))
    _reject_wrappers(parameters)
    return TestSpace((Symbol(:p, i) => parameters[i] for i in eachindex(parameters))...)
end


"""
    _stronger_from_wayness(wayness) -> Vector{Pair}

The 0.4 `wayness`, a `Dict` from a strength to a list of parameter index
groups, as `stronger` pairs: `Dict(3 => [[3, 4, 5, 6]])` becomes
`[[3, 4, 5, 6] => 3]` (contract §11.10). The caller's `Dict` and its groups
are copied, never mutated (§11.9).
"""
function _stronger_from_wayness(wayness)
    wayness === nothing && return Pair{Vector{Int}, Int}[]
    wayness isa AbstractDict || throw(ArgumentError(
        "`wayness` is a Dict from a strength to a list of parameter index groups, " *
        "for example Dict(3 => [[3, 4, 5, 6]]); got $(repr(wayness))"))
    stronger = Pair{Vector{Int}, Int}[]
    for s in sort!(collect(keys(wayness)))
        s isa Integer || throw(ArgumentError(
            "`wayness` keys are strengths, integers; got $(repr(s))"))
        groups = wayness[s]
        (groups isa AbstractVector || groups isa Tuple) && all(g -> g isa Union{AbstractVector, Tuple}, groups) ||
            throw(ArgumentError(
                "`wayness` maps a strength to a list of parameter index groups, such as " *
                "$s => [[1, 2, 3]]; got $s => $(repr(groups))"))
        for g in groups
            all(i -> i isa Integer, g) || throw(ArgumentError(
                "`wayness` groups list parameter positions, integers; got $(repr(g))"))
            push!(stronger, collect(Int, g) => Int(s))
        end
    end
    return stronger
end


_positional_design(engine::IPOG, request::Request, n_way) = generate(engine, request)
_positional_design(engine::GND, request::Request, n_way) = generate(engine, request)
_positional_design(::Excursion, request::Request, n_way) = generate_excursion(request; distance = n_way)
_positional_design(engine, request::Request, n_way) = throw(ArgumentError(
    "`engine` is IPOG(), GND(), or Excursion(); got $(repr(engine))"))

"The rows of a design in the 0.4 shape: one `Vector{Any}` per case."
_positional_rows(request::Request, design::Design) =
    Vector{Any}[collect(Any, values(case)) for case in to_cases(request, design.matrix)]


"""
    all_tuples(parameters...; n_way = 2, engine = IPOG(), seeds = [], wayness = nothing)

Given the values of each parameter, generate test cases that include every
combination of values of every `n_way` parameters at least once. Each
argument is the list of values of one parameter, a vector, range, or tuple;
a parameter may have a single value. Values are kept as given, so `nothing`
and `missing` are ordinary values. Returns one vector of values per case.

# Arguments

- `n_way = 2`: the strength, from 1 to the number of parameters. At the number
  of parameters, the result is every combination.
- `engine = IPOG()`: `IPOG()`, `GND()`, or `Excursion()`.
- `seeds = []`: test cases that must be included, each a vector or tuple with
  one value per parameter. They come first in the result, in order.
- `wayness`: a dictionary that raises the strength for groups of parameters,
  by position. If the combinations are two-way, and you want the third to
  sixth parameters to be three-way covered, use
  `wayness = Dict(3 => [[3, 4, 5, 6]])`.

Positional calls do not take rules. To exclude combinations, build a
[`TestSpace`](@ref) with constraints.

# Examples
```julia
all_tuples([1, 2, 3], ["a", "b", "c"], [true, false]; n_way = 2)
parameters = fill(collect(1:3), 10)
all_tuples(parameters...; n_way = 4, engine = Excursion())
```
"""
function all_tuples(parameters...; n_way::Integer = 2, engine = IPOG(), seeds = [], wayness = nothing)
    space = _positional_space(parameters)
    must_include = seeds === nothing ? Tuple[] : [Tuple(s) for s in seeds]
    request = Request(space; strength = n_way, stronger = _stronger_from_wayness(wayness),
                      must_include = must_include)
    return _positional_rows(request, _positional_design(engine, request, n_way))
end


"""
    all_values(parameters...; kwargs...)

Ensure that the test cases include every value of every parameter
at least once.

See also: [`all_tuples`](@ref)
"""
function all_values(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 1, kwargs...)
end


"""
    all_pairs(parameters...; kwargs...)

Ensure that the returned test cases include every pair of
parameters at least once.

# Examples
```julia
all_pairs([1, 2, 3], ["a", "b", "c"], [true, false])
```

See also: [`all_tuples`](@ref)
"""
function all_pairs(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 2, kwargs...)
end


"""
    all_triples(parameters...; kwargs...)

Ensure that the returned test cases include every combination
of three parameters at least once.

See also: [`all_tuples`](@ref)
"""
function all_triples(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 3, kwargs...)
end


"""
    values_excursion(parameters...; kwargs...)

This starts with the first choice for each of the parameters.
It creates test cases by varying each parameter, one at a time,
through its possible values.

# Examples
```julia
values_excursion([:a, :b, :c], [1, 2, 3])
```

See also: [`all_tuples`](@ref)
"""
function values_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 1, engine = Excursion(), kwargs...)
end


"""
    pairs_excursion(parameters...; kwargs...)

This starts with the first choice for each of the parameters.
It creates test cases by varying each parameter, one at a time,
through its possible values. Then it walks pairs of parameters
away from the base case.

# Examples
```julia
pairs_excursion([:a, :b], [1, 2], [1, 2], ["a", "b"])
```

See also: [`all_tuples`](@ref)
"""
function pairs_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 2, engine = Excursion(), kwargs...)
end


"""
    triples_excursion(parameters...; kwargs...)

This starts with the first choice for each of the parameters.
It creates test cases by varying each parameter, one at a time,
through its possible values. Then it walks pairs of parameters
away from the base case, and finally triples.

See also: [`all_tuples`](@ref)
"""
function triples_excursion(parameters...; kwargs...)
    all_tuples(parameters...; n_way = 3, engine = Excursion(), kwargs...)
end


"""
    full_factorial(parameters...)

Generates a test case for every combination of the parameters' values.

# Examples
```julia
full_factorial([0.1, 0.2, 0.3], ["low", "high"], [false, true])
```

To leave out combinations, build a [`TestSpace`](@ref) with constraints.
"""
function full_factorial(parameters...)
    space = _positional_space(parameters)
    request = Request(space; strength = 1)
    return _positional_rows(request, generate_full_factorial(request; limit = 10^6))
end
