# The 0.5 public interface (plan Phase 4 steps 2–5 and 8; contract §1.18,
# §7, §10, §11, §12.11–§12.12, §13).
#
# Every generation call is one pipeline: accept or build the space, build
# the Request (which validates strength, `stronger` and `must_include` in the
# caller's vocabulary, §0.1), ask an engine or a strategy for a Design, and
# wrap it as a TestCases. The input is one of four forms: a `TestSpace`; a
# `NamedTuple` of domains; `name => domain` pairs; or one positional domain
# per parameter, which builds a space named `p1, p2, ...` and returns tuples
# (§1.18, §13.4).
#
# The 0.4 spellings are deprecated aliases that warn through `Base.depwarn`
# (§13.1, §13.2): `all_tuples`, `values_excursion`, `pairs_excursion`,
# `triples_excursion`, and the keywords `n_way`, `seeds`, `wayness`.
# `disallow`, `generate_tuples`, `Excursion` and `Counter` are gone (§13.3);
# `disallow` and `Counter` meet the ordinary unknown-keyword `MethodError`.


## Input forms

"""
    _positional_space(domains) -> TestSpace

A space whose parameters are named `p1`, `p2`, ... in argument order, with the
given domains. Values and their types are kept; `nothing` and `missing` are
values (contract §2.9). A domain error names the parameter, such as `p2`.
"""
function _positional_space(domains)
    return TestSpace((Symbol(:p, i) => domains[i] for i in eachindex(domains))...)
end

const _INPUT_FORMS = "a TestSpace, a NamedTuple of domains, name => values pairs, " *
                     "or one vector of values per parameter"

"""
    _space(fname, input, constraints) -> (space, positional)

The space for one of the four input forms, and whether the call is
positional. `constraints` builds the space from named domains; it is an
error on a `TestSpace` and on positional input (contract §12.12).
"""
function _space(fname::Symbol, input::Tuple, constraints)
    isempty(input) && throw(ArgumentError(
        "$fname needs the parameters: $_INPUT_FORMS, for example $fname([1, 2], [:a, :b])"))
    rules = constraints === nothing ? Constraint[] : constraints
    if length(input) == 1 && input[1] isa TestSpace
        constraints === nothing || throw(ArgumentError(
            "constraints belong to the space: build TestSpace(...; constraints) instead (contract §12.12)"))
        return input[1], false
    elseif length(input) == 1 && input[1] isa NamedTuple
        return TestSpace(input[1]; constraints = rules), false
    elseif all(x -> x isa Pair, input)
        return TestSpace(input...; constraints = rules), false
    end
    k = findfirst(x -> x isa Union{TestSpace, NamedTuple, Pair}, input)
    k === nothing || throw(ArgumentError(
        "argument $k of $fname is a $(nameof(typeof(input[k]))) among other arguments; pass " *
        "one TestSpace, one NamedTuple of domains, only name => values pairs, or only " *
        "positional domains (vectors, ranges, or tuples)"))
    constraints === nothing || throw(ArgumentError(
        "positional calls take no constraints; use a named space, such as " *
        "$fname((a = [1, 2], b = [:x, :y]); constraints = [...]) (contract §12.12)"))
    return _positional_space(input), true
end


## Keywords

"""
    _must_include_rows(must_include, space, positional) -> Vector

The rows to hand the `Request`, which validates them (contract §10.1–§10.4),
as a `Vector`. This is the one place the caller's `must_include` is read: it
is materialized once by `_row_list`, so an iterator that can be read only
once, such as an `Iterators.Stateful`, gives all its rows, and every check
here and in the `Request` reads that collection. A `TestCases` gives its
rows; its parameter names must all belong to the space, and a subset gives
partial rows (§10.1). A positional call takes each row as a tuple or vector
with one value per parameter. The caller's collection is never mutated
(§10.7). `nothing`, the omitted keyword, gives no rows.
"""
function _must_include_rows(must_include, space::TestSpace, positional::Bool)
    must_include === nothing && return Any[]
    if must_include isa TestCases
        given = parameters(must_include.space)
        unknown = [name for name in given if !(name in space.names)]
        isempty(unknown) || throw(ArgumentError(
            "must_include is a TestCases over $(join(given, ", ")), but " *
            "$(join(("`$u`" for u in unknown), ", ", " and ")) " *
            "$(length(unknown) == 1 ? "is not a parameter" : "are not parameters") of this space; " *
            "the parameters are $(join(space.names, ", ")) (contract §10.1)"))
        if positional
            given == space.names || throw(ArgumentError(
                "must_include is a TestCases over $(join(given, ", ")); a positional call takes " *
                "complete rows, one value for each of $(join(space.names, ", ")) (contract §10.1)"))
            return [Tuple(values(row)) for row in must_include]
        end
        return must_include.positional ?
            [NamedTuple{Tuple(given)}(row) for row in must_include] : collect(must_include)
    end
    rows = _row_list(must_include; what = "must_include is a list of rows", section = "§10.1",
                     fix = row -> "must_include = [$(repr(row))]")
    if positional
        for (r, row) in enumerate(rows)
            row isa NamedTuple && throw(ArgumentError(
                "must_include row $r is a NamedTuple; a positional call takes each row as a " *
                "tuple or vector with one value per parameter (contract §10.1)"))
        end
    end
    return rows
end

const _WAYNESS_FORM = "a Dict{Int, Vector{Vector{Int}}} from a strength to parameter index groups, " *
                      "such as Dict(3 => [[3, 4, 5, 6]])"

"""
    _stronger_from_wayness(wayness) -> Vector{Pair}

The 0.4 `wayness`, a `Dict` from a strength to a list of parameter index
groups, as `stronger` pairs: `Dict(3 => [[3, 4, 5, 6]])` becomes
`[[3, 4, 5, 6] => 3]` (contract §11.10). The caller's `Dict` and its groups
are copied, never mutated (§11.9). Every key is checked to be an integer
before the keys are sorted, since `sort` cannot order `3` and `:a`.
"""
function _stronger_from_wayness(wayness)
    wayness === nothing && return Pair{Vector{Int}, Int}[]
    wayness isa AbstractDict || throw(ArgumentError(
        "`wayness` is $_WAYNESS_FORM; got $(repr(wayness)) (contract §11.10)"))
    for s in keys(wayness)
        s isa Integer && !(s isa Bool) && typemin(Int) <= s <= typemax(Int) || throw(ArgumentError(
            "`wayness` is $_WAYNESS_FORM; got the key $(repr(s)), which is not an integer strength " *
            "(contract §11.10)"))
    end
    stronger = Pair{Vector{Int}, Int}[]
    for s in sort!(collect(keys(wayness)))
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

"`stronger` pairs as the caller would write them: `[(3, 4, 5, 6) => 3]`."
_stronger_text(stronger) = "[" * join(("$(repr(Tuple(g))) => $s" for (g, s) in stronger), ", ") * "]"

"""
    _deprecated_keywords(fname; must_include, seeds, stronger, wayness)
        -> (must_include, stronger)

Resolve the 0.4 keywords `seeds` and `wayness`, warning once per call site
through `Base.depwarn` (contract §10.8, §11.10, §13.2). `must_include` and
`stronger` arrive as `nothing` when the caller omitted them, so that a
keyword and its deprecated alias given together is an error whatever their
values, even an empty `must_include = []` beside `seeds` (§13.2). Returns
`must_include` as given (`nothing` when omitted, read later by
`_must_include_rows`) and `stronger` as a vector.
"""
function _deprecated_keywords(fname::Symbol; must_include, seeds, stronger, wayness)
    if seeds !== nothing
        must_include === nothing || throw(ArgumentError(
            "pass must_include only; seeds is its deprecated alias (contract §10.8)"))
        Base.depwarn("the keyword `seeds` is deprecated; use `must_include`, which takes the same rows", fname)
        must_include = seeds
    end
    if wayness !== nothing
        stronger === nothing || throw(ArgumentError(
            "pass stronger only; wayness is its deprecated form (contract §11.10)"))
        stronger = _stronger_from_wayness(wayness)
        Base.depwarn("the keyword `wayness` is deprecated; use `stronger = $(_stronger_text(stronger))`", fname)
    end
    return must_include, something(stronger, Pair{Vector{Int}, Int}[])
end

"Both search budgets, before any work (contract §3.3, §3.13)."
function _check_limits(feasibility_limit, explanation_limit)
    _check_limit(:feasibility_limit, feasibility_limit)
    _check_limit(:explanation_limit, explanation_limit)
    return nothing
end

"""
    _check_distance(keyword, distance) -> Int

An excursion distance: an integer of at least 0 (contract §7.5). A distance
above the parameter count is the parameter count, however large, so an
integer beyond `Int` is read as `typemax(Int)` rather than refused.
"""
function _check_distance(keyword, distance)
    distance isa Integer && !(distance isa Bool) && distance > typemax(Int) && return typemax(Int)
    return _check_integer(keyword, distance, 0, "§7.5")
end

"""
    _from_row(from, space, positional)

The caller's `from`, for `excursion_base` to read with `_row_indices`
(contract §7.6), after the two rules that are the public call's own: a
positional call takes the base as a tuple or vector of values, never a
`NamedTuple`; and a vector is values, never the engine positions
`excursion_base` also accepts, so it is passed on as a `Tuple`.
"""
function _from_row(from, space::TestSpace, positional::Bool)
    positional && from isa NamedTuple && throw(ArgumentError(
        "`from` is a NamedTuple; a positional call takes the base as a tuple or vector of " *
        "values in argument order, one for each of $(join(space.names, ", ")) (contract §7.6)"))
    return from isa AbstractVector ? Tuple(from) : from
end

function _check_engine(engine)
    engine isa Union{IPOG, GND} || throw(ArgumentError(
        "`engine` is IPOG() or GND(); got $(repr(engine))"))
    return engine
end


## Covering

"""
    _covering(fname, input; strength, ...) -> TestCases

The covering pipeline behind `covering`, `all_values`, `all_pairs`,
`all_triples` and `all_tuples`. `fname` is the function the caller used,
for messages and for `Base.depwarn`'s call site. `strength`, `stronger` and
`must_include` default to `nothing`, meaning omitted: strength 2, no
`stronger` groups, no must-include rows.
"""
function _covering(fname::Symbol, input::Tuple; strength = nothing, stronger = nothing,
                   must_include = nothing, engine = IPOG(), constraints = nothing,
                   feasibility_limit = 1_000_000, explanation_limit = 1_000_000, n_way = nothing,
                   seeds = nothing, wayness = nothing)
    # `nothing` marks an omitted keyword, so an explicit `strength = 2` beside
    # `n_way` is seen and refused rather than overridden (§13.2).
    if n_way !== nothing
        strength === nothing || throw(ArgumentError(
            "pass strength only; n_way is its deprecated alias (contract §11.10)"))
        _check_integer(:n_way, n_way, 1, "§11.1")
        Base.depwarn("the keyword `n_way` is deprecated; use `strength = $n_way`", fname)
        strength = n_way
    end
    # Keyword values are checked before the space is built or anything searched.
    strength = _check_integer(:strength, something(strength, 2), 1, "§11.1")
    _check_limits(feasibility_limit, explanation_limit)
    must_include, stronger = _deprecated_keywords(fname; must_include, seeds, stronger, wayness)
    _check_engine(engine)
    space, positional = _space(fname, input, constraints)
    request = Request(space; strength, stronger, feasibility_limit, explanation_limit,
                      must_include = _must_include_rows(must_include, space, positional))
    return TestCases(request, generate(engine, request); positional)
end

"""
Use when you want every combination of values of every `strength` parameters
(pairs at strength 2, triples at 3) to appear in at least one case, with as few
cases as the engine finds.

    covering(space; strength = 2, stronger = [], must_include = [], engine = IPOG(),
             feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    covering(domains::NamedTuple; constraints = [], kwargs...)
    covering(name => domain, ...; constraints = [], kwargs...)
    covering(domain, domain, ...; kwargs...)

Test cases in which every combination of values of every `strength`
parameters appears at least once, among the combinations some valid row
contains; combinations the rules exclude need no case (contract §1.2, §1.3).
Returns a [`TestCases`](@ref), a vector of rows that also records the
request and what it excluded (§1.18, §1.19).

The parameters come in one of four forms:

- a [`TestSpace`](@ref), which holds the parameters, their values and the
  rules. `constraints =` is an error here: rules belong to the space (§12.12).
- a `NamedTuple` of domains, `(mode = [:fast, :exact], tol = [1e-3, 1e-6])`,
  or `name => domain` pairs, `:mode => [:fast, :exact], :tol => [1e-3, 1e-6]`.
  `constraints =` builds the space, as `TestSpace(domains; constraints)` would.
  Rows are `NamedTuple`s.
- one domain per parameter, a vector, range or tuple each:
  `covering([1, 2, 3], ["a", "b"], [true, false])`. The parameters are named
  `p1`, `p2`, ... in messages, and rows are tuples. Positional calls take no
  `constraints`; to exclude combinations, name the parameters.

Values are kept as given, with their types: `Any[1, 1.0]` is two values, and
`nothing` and `missing` are ordinary values (§2.1, §2.9).

A [`Partition`](@ref) is an ordinary value that rules and targets see by its
name; returned rows hold the wrapper, and [`realize`](@ref) draws the
concrete values (§4). An [`Invalid`](@ref) value is for negative tests
(§5, §6). The covering design is built over ordinary values; then, for each
invalid value `v` of a parameter `p`, negative rows hold `p = v` beside
ordinary values of the other parameters, and cover every feasible
combination of `v` with `strength - 1` other parameters' values, and within
each `stronger` group that contains `p`, with its strength less one. At
strength 2, each invalid value appears beside every value of every other
parameter that some valid negative row holds (§6.6). A negative row
satisfies the rules that do not read `p`; rules that read `p` do not apply
to it (§5.5). The rows are the must-include rows, then the ordinary rows,
then the negative rows (§5.12), and a row never holds two `Invalid` values
(§5.7). `hasinvalid(case)` tells a test body which kind it has, and the
result counts the two kinds of targets separately (§5.10).

# Keywords

- `strength = 2`: from 1 to the number of parameters (§11.1, §11.2). At the
  number of parameters the result is, as a set, every valid row (§7.8).
- `stronger = []`: groups of parameters that need a higher strength, as
  `group => strength` pairs. A named group is a tuple of names,
  `[(:a, :b, :c) => 3]`; a positional group lists argument positions,
  `[(1, 3, 4) => 3]`. Overlapping groups combine; a group at the base strength
  adds nothing. The caller's vector is not changed (§11.3–§11.9).
- `must_include = []`: rows that must appear. They come first, in the order
  given, duplicates kept (§10.5). A named call takes `NamedTuple`s, which may
  be partial and are then completed with valid values, or an existing
  `TestCases`, whose rows are kept and topped up with the rows needed to cover
  what they miss (§9.10). A positional call takes tuples or vectors with one
  value per parameter. A row that breaks a rule, or a partial row with no valid
  completion, is an error naming the row and the rules (§10.2–§10.4). A row
  with one `Invalid` value is a negative row, judged and completed under the
  negative policy, with ordinary values elsewhere; a partial row without one
  is completed as an ordinary row; a row with two is an error (§5.7, §7.9).
- `engine = IPOG()`: [`IPOG`](@ref) or [`GND`](@ref). Both are deterministic
  for the same inputs (§9.1). Neither guarantees a particular number of
  cases, and neither is always smaller than the other (§8.1).
- `feasibility_limit = 1_000_000`: the node budget of each search that
  decides whether a combination, a partial must-include row or a placement
  has a valid completion (§3.3, §3.4). Generation resolves every one of them
  or fails: a search that runs out throws a
  [`ResourceLimitError`](@ref) naming `feasibility_limit`, and no design is
  returned with an undecided combination (§1.20, §3.6, §3.7). Raise it when
  generation cannot finish, as in `all_pairs(space; feasibility_limit =
  10_000_000)`; a larger value never changes the rows of a result that
  already succeeded, though an implied exclusion's explanation may differ
  (§3.8).
- `explanation_limit = 1_000_000`: the node budget of the search that finds
  which rules cause each implied exclusion, starting from a set of rules
  already proven to exclude it (§3.13, §3.14). Each trial of that search is
  also bounded by `feasibility_limit`. Running out never throws and never
  changes the cases: the design is complete and certified as usual, and the
  exclusion keeps its proven set of rules with `minimal = :unresolved`,
  which `show` counts as "with an unresolved explanation" (§3.15, §3.16).
  Its `limit` is `:explanation_limit => N` when this budget stopped a trial
  or left one untried, and `:feasibility_limit => N` when a trial reached
  the feasibility limit instead (§3.14). Raise it only when you want each
  implied exclusion's rules verified inclusion-minimal, so that none of them
  can be dropped; only the attribution becomes more precise. It also bounds
  the explanation in the error for a partial must-include row with no valid
  completion.

The 0.4 keywords `n_way` (now `strength`), `seeds` (now `must_include`) and
`wayness` (now `stronger`, translated from its `Dict` of positions) are
accepted with a deprecation warning (§13.1). Passing one together with its
new keyword is an `ArgumentError`, even when the new keyword is at its
default value, as in `strength = 2, n_way = 1` (§13.2).

# Examples

```julia
space = TestSpace(
    (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
    constraints = [@require(mode == :exact || solver == :none)])
covering(space; strength = 2)
covering((a = 1:3, b = [:x, :y], c = [true, false]); strength = 3)
covering(fill(1:4, 10)...; stronger = [(1, 2, 3) => 3], engine = GND())
all_pairs(space; must_include = previous_cases)   # keep them; add what they miss
```

See also [`all_values`](@ref), [`all_pairs`](@ref), [`all_triples`](@ref),
[`excursions`](@ref), [`full_factorial`](@ref).
"""
function covering(input...; strength = nothing, stronger = nothing, must_include = nothing,
                  engine = IPOG(), constraints = nothing, feasibility_limit = 1_000_000,
                  explanation_limit = 1_000_000, n_way = nothing, seeds = nothing, wayness = nothing)
    return _covering(:covering, input; strength, stronger, must_include, engine, constraints,
                     feasibility_limit, explanation_limit, n_way, seeds, wayness)
end

# The fixed-strength functions take every keyword of `covering` but the strength.
function _fixed_strength(fname::Symbol, s::Int, keyword::Symbol, value)
    value === nothing && return nothing
    throw(ArgumentError(
        "$fname has strength $s and takes no `$keyword`; for another strength use " *
        "covering(...; strength = $(repr(value)))"))
end

"""
Use when you want every value of every parameter to appear in at least one case,
with as few cases as the engine finds: a quick check that each value works at
all.

    all_values(input...; stronger, must_include, engine, constraints,
               feasibility_limit, explanation_limit)

Test cases in which every value of every parameter appears at least once:
[`covering`](@ref) at strength 1. It takes the same inputs and every keyword
of `covering` except `strength`.

```julia
all_values([1, 2, 3], ["a", "b"], [true, false])   # 3 tuples
```
"""
function all_values(input...; stronger = nothing, must_include = nothing, engine = IPOG(),
                    constraints = nothing, feasibility_limit = 1_000_000,
                    explanation_limit = 1_000_000, strength = nothing, n_way = nothing,
                    seeds = nothing, wayness = nothing)
    _fixed_strength(:all_values, 1, :strength, strength)
    _fixed_strength(:all_values, 1, :n_way, n_way)
    return _covering(:all_values, input; strength = 1, stronger, must_include, engine, constraints,
                     feasibility_limit, explanation_limit, seeds, wayness)
end

"""
Use when you want every pair of parameter values to appear in at least one case,
with as few cases as the engine finds.

    all_pairs(input...; stronger, must_include, engine, constraints,
              feasibility_limit, explanation_limit)

Test cases in which every pair of values of every two parameters appears at
least once, among the pairs some valid row contains: [`covering`](@ref) at
strength 2. It takes the same inputs and every keyword of `covering` except
`strength`.

```julia
all_pairs([1, 2, 3], ["a", "b", "c"], [true, false])
all_pairs((mode = [:fast, :exact], solver = [:none, :lu, :qr]);
          constraints = [@forbid(mode == :fast && solver != :none)])
all_pairs(space; must_include = existing_cases)
```
"""
function all_pairs(input...; stronger = nothing, must_include = nothing, engine = IPOG(),
                   constraints = nothing, feasibility_limit = 1_000_000,
                   explanation_limit = 1_000_000, strength = nothing, n_way = nothing,
                   seeds = nothing, wayness = nothing)
    _fixed_strength(:all_pairs, 2, :strength, strength)
    _fixed_strength(:all_pairs, 2, :n_way, n_way)
    return _covering(:all_pairs, input; strength = 2, stronger, must_include, engine, constraints,
                     feasibility_limit, explanation_limit, seeds, wayness)
end

"""
Use when you want every combination of three parameters' values to appear in at
least one case, with as few cases as the engine finds; it reaches faults that
need three values together, at the cost of more cases than pairs.

    all_triples(input...; stronger, must_include, engine, constraints,
                feasibility_limit, explanation_limit)

Test cases in which every combination of values of every three parameters
appears at least once, among those some valid row contains:
[`covering`](@ref) at strength 3. It takes the same inputs and every keyword
of `covering` except `strength`.

```julia
all_triples([1, 2], [3, 4], [5, 6], [7, 8])
```
"""
function all_triples(input...; stronger = nothing, must_include = nothing, engine = IPOG(),
                     constraints = nothing, feasibility_limit = 1_000_000,
                     explanation_limit = 1_000_000, strength = nothing, n_way = nothing,
                     seeds = nothing, wayness = nothing)
    _fixed_strength(:all_triples, 3, :strength, strength)
    _fixed_strength(:all_triples, 3, :n_way, n_way)
    return _covering(:all_triples, input; strength = 3, stronger, must_include, engine, constraints,
                     feasibility_limit, explanation_limit, seeds, wayness)
end


## Excursions

"""
    _excursions(fname, input, default_distance; from, distance, ...) -> TestCases

The excursion pipeline behind `excursions` and its deprecated aliases. The
aliases forward the 0.4 `n_way`, which for an excursion was its distance
(contract §7.5), and give their own `default_distance` for when neither
`distance` nor `n_way` is passed. `distance = nothing` marks it omitted, so
that `distance` and `n_way` together is an error whatever their values
(§13.2).
"""
function _excursions(fname::Symbol, input::Tuple, default_distance::Integer; from = nothing,
                     distance = nothing, must_include = nothing, constraints = nothing,
                     feasibility_limit = 1_000_000, explanation_limit = 1_000_000, seeds = nothing,
                     stronger = nothing, wayness = nothing, n_way = nothing)
    (stronger === nothing || isempty(stronger)) && wayness === nothing || throw(ArgumentError(
        "excursions take a single distance; stronger groups apply to covering designs"))
    if n_way !== nothing
        distance === nothing || throw(ArgumentError(
            "pass distance only; n_way is its deprecated alias for an excursion (contract §7.5)"))
        _check_distance("n_way, an excursion's distance,", n_way)
        Base.depwarn("the keyword `n_way` is deprecated; an excursion's `n_way` is its distance: " *
                     "use excursions(...; distance = $n_way)", fname)
        distance = n_way
    end
    # Keyword values are checked before the space is built or anything searched.
    distance = _check_distance(:distance, something(distance, default_distance))
    _check_limits(feasibility_limit, explanation_limit)
    must_include, _ = _deprecated_keywords(fname; must_include, seeds, stronger = nothing, wayness = nothing)
    space, positional = _space(fname, input, constraints)
    base = _from_row(from, space, positional)
    # Strength 1 is accepted by every space and is not read (§7.5).
    request = Request(space; strength = 1, feasibility_limit, explanation_limit,
                      must_include = _must_include_rows(must_include, space, positional))
    return TestCases(request, generate_excursion(request; distance, from = base); positional)
end

"""
Use when you trust one base case and want every valid variation that changes at
most `distance` of its parameters. An excursion is not a covering design: it
does not guarantee that every pair, or even every value, appears.

    excursions(space; from = nothing, distance = 1, must_include = [],
               feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
    excursions(domains::NamedTuple; constraints = [], kwargs...)
    excursions(name => domain, ...; constraints = [], kwargs...)
    excursions(domain, domain, ...; kwargs...)

Variations around one base row: the must-include rows, in the order given
with duplicates kept (§10.5), then the base, then every other valid row that
differs from the base in at most `distance` parameters (contract §7.5). The
base and each of those rows appear once, and a row equal to a must-include
row is not repeated (§7.11). Returns a [`TestCases`](@ref) with strategy
`:excursion`. The inputs are the four forms [`covering`](@ref) takes.

The promise is only this: every returned row other than a must-include row is
within `distance` changed parameters of the base. An excursion is not a
covering design. It makes no claim that every pair, or even every value,
appears: a value whose rows within the distance all break a rule appears in no
row (§7.7).

- `from`: the base, a complete valid ordinary row, as a `NamedTuple` or, for
  a positional call, a tuple of values in argument order. Omitted, it is the
  first ordinary value of each parameter. A base that is partial, holds an
  [`Invalid`](@ref) value, or breaks a rule is an error naming the cause
  (§7.6). The base is never dropped.
- `distance = 1`: an integer of at least 0. 0 gives the must-include rows and
  the base alone; a distance above the number of parameters is the number of
  parameters. Excursion distance is not covering strength, and there are no
  `stronger` groups (§7.5).
- `must_include`: rows placed first, as for [`covering`](@ref) (§10), and
  kept as given, duplicates included. A partial row is completed toward the
  base. An excursion row equal to a must-include row is not repeated
  (§7.11).

Changing a parameter to one of its `Invalid` values gives a negative row,
which is kept when it satisfies the rules that do not read that parameter
(§5.5, §7.5). A row with two `Invalid` values is never returned (§5.7).

Rows within the distance that break a rule are left out. The result reports
how many in `cases.notes.dropped`, and `cases.notes.never_appear` lists the
values that appear in no returned row (§7.7).

`feasibility_limit` and `explanation_limit` bound only the searches for
must-include rows, as for [`full_factorial`](@ref).

```julia
excursions([1, 2, 3], [:x, :y], [true, false])            # 1 + 2 + 1 + 1 rows
excursions(space; from = (mode = :exact, solver = :lu, tol = 1e-6), distance = 2)
```
"""
function excursions(input...; from = nothing, distance = 1, must_include = nothing,
                    constraints = nothing, feasibility_limit = 1_000_000,
                    explanation_limit = 1_000_000, seeds = nothing, stronger = nothing,
                    wayness = nothing)
    return _excursions(:excursions, input, 1; from, distance, must_include, constraints,
                       feasibility_limit, explanation_limit, seeds, stronger, wayness)
end


## Full factorial

"""
Use when the product of the domains is small enough to run every valid
combination, or when you need every one of them.

    full_factorial(space; limit = 10^6, must_include = [], feasibility_limit = 1_000_000)
    full_factorial(domains::NamedTuple; constraints = [], kwargs...)
    full_factorial(name => domain, ...; constraints = [], kwargs...)
    full_factorial(domain, domain, ...; kwargs...)

Every valid row: the full product of the domains, less the rows the rules
exclude (contract §7.2). The must-include rows come first, in the order
given with duplicates kept (§10.5); then each remaining valid row appears
once, and a valid row equal to a must-include row is not repeated. Returns a
[`TestCases`](@ref) with strategy `:full_factorial`; the inputs are the four
forms [`covering`](@ref) takes.

With [`Invalid`](@ref) values, the valid ordinary rows come first, then the
valid negative rows: for each parameter in order and each of its invalid
values in domain order, the rows holding that value beside ordinary values
of the other parameters, kept when they satisfy the rules that do not read
that parameter (§5.5). A row with two `Invalid` values is never returned
(§5.7).

`limit` guards against a product too large to enumerate. Before looking at
any row, must-include rows included, the call counts the candidate rows,
the product of the parameters' ordinary value counts plus, for each
parameter, its number of `Invalid` values times the product of the other
parameters' ordinary value counts, and if that exceeds `limit` it throws a
[`ResourceLimitError`](@ref) that gives the count and the keyword (§7.3), so
no search runs for a refused enumeration. Raise `limit` to go ahead, or use
[`covering`](@ref) for a smaller design. Candidates are then enumerated one
at a time and only valid rows are kept (§7.4). `cases.notes` reports
`candidates` and `accepted` separately.

The enumeration checks complete rows and does not search, so
`feasibility_limit` and `explanation_limit` matter only for a partial
must-include row. `feasibility_limit` bounds the search that completes it:
running out throws a [`ResourceLimitError`](@ref) naming the keyword, and
raising it is how to let the call finish. `explanation_limit` bounds the
search that explains a row with no valid completion: running out still
throws the `ArgumentError` for that row, naming rules proven to exclude it,
with the explanation marked unresolved; raising it only narrows that list of
rules.

```julia
full_factorial([0.1, 0.2, 0.3], ["low", "high"], [false, true])   # 12 tuples
full_factorial((a = 1:3, b = [7, 8], c = [true, false]);
               constraints = [forbid((b = 7, c = false))])        # 9 rows
```
"""
function full_factorial(input...; limit = 10^6, must_include = nothing, constraints = nothing,
                        feasibility_limit = 1_000_000, explanation_limit = 1_000_000,
                        seeds = nothing, stronger = nothing, wayness = nothing)
    (stronger === nothing || isempty(stronger)) && wayness === nothing || throw(ArgumentError(
        "full_factorial returns every valid row; stronger groups apply to covering designs"))
    must_include, _ = _deprecated_keywords(:full_factorial; must_include, seeds, stronger = nothing,
                                           wayness = nothing)
    limit = _check_integer(:limit, limit, 1, "§7.3")
    _check_limits(feasibility_limit, explanation_limit)
    space, positional = _space(:full_factorial, input, constraints)
    # The count comes before the Request, whose must-include checks may search
    # (§7.3): an enumeration that is refused never runs a feasibility search.
    check_full_factorial_limit(space, limit)
    request = Request(space; strength = 1, feasibility_limit, explanation_limit,
                      must_include = _must_include_rows(must_include, space, positional))
    return TestCases(request, generate_full_factorial(request; limit); positional)
end


## Deprecated aliases (contract §13.1, §13.2)

"""
Deprecated alias of [`covering`](@ref): call `covering` with the same inputs
and keywords, writing `strength` for `n_way`.

    all_tuples(input...; n_way = 2, kwargs...)

It warns through `Base.depwarn` and will be removed in the next breaking
release (contract §13.1, §13.2). See the migration table in the manual.
"""
function all_tuples(input...; kwargs...)
    Base.depwarn("all_tuples is deprecated; use covering, which takes the same inputs, " *
                 "with `strength` for `n_way`", :all_tuples)
    return _covering(:all_tuples, input; kwargs...)
end

"""
Deprecated alias of [`excursions`](@ref) at distance 1: call
`excursions(input...; distance = 1)`.

    values_excursion(input...; kwargs...)

It takes the keywords of `excursions`, and the 0.4 `n_way` as the distance.
It warns through `Base.depwarn` and will be removed in the next breaking
release (contract §13.1, §13.2).
"""
function values_excursion(input...; kwargs...)
    Base.depwarn("values_excursion is deprecated; use excursions(...; distance = 1)", :values_excursion)
    return _excursions(:values_excursion, input, 1; kwargs...)
end

"""
Deprecated alias of [`excursions`](@ref) at distance 2: call
`excursions(input...; distance = 2)`.

    pairs_excursion(input...; kwargs...)

It takes the keywords of `excursions`, and the 0.4 `n_way` as the distance.
It warns through `Base.depwarn` and will be removed in the next breaking
release (contract §13.1, §13.2).
"""
function pairs_excursion(input...; kwargs...)
    Base.depwarn("pairs_excursion is deprecated; use excursions(...; distance = 2)", :pairs_excursion)
    return _excursions(:pairs_excursion, input, 2; kwargs...)
end

"""
Deprecated alias of [`excursions`](@ref) at distance 3: call
`excursions(input...; distance = 3)`.

    triples_excursion(input...; kwargs...)

It takes the keywords of `excursions`, and the 0.4 `n_way` as the distance.
It warns through `Base.depwarn` and will be removed in the next breaking
release (contract §13.1, §13.2).
"""
function triples_excursion(input...; kwargs...)
    Base.depwarn("triples_excursion is deprecated; use excursions(...; distance = 3)", :triples_excursion)
    return _excursions(:triples_excursion, input, 3; kwargs...)
end
