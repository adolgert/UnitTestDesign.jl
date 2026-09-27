# The public result type (plan Phase 4 step 1, contract §1.18–§1.24).
#
# A TestCases is a vector of rows plus the bookkeeping generation already
# knows. It never performs a search (§1.22): everything here is copied from
# the Request and the Design.

"""
    Exclusion

One target a design did not need to cover, in the user's vocabulary
(contract §1.4): `target` (a partial `NamedTuple`), `status` (`:forbidden`
or `:implied`), `rules` (constraint positions in the space), `labels` (their
display labels), `minimal` (`:verified`, `:unresolved`, `:not_applicable`),
and `limit` (`keyword => value` when a limit cut the explanation short,
else `nothing`).

It prints as one line naming the target and its rules:

```
(mode = :exact, tol = 0.001): forbidden by rule 2 (exact mode needs a tight tolerance)
(solver = :lu, tol = 0.001): impossible because rules 1 and 2 combine (rule 1: …; rule 2: …)
```

An unresolved explanation adds the limit that left it unresolved, such as
"(explanation unresolved: explanation_limit = 1 reached)"; its rules are
still sufficient to exclude the target (§3.15).
"""
struct Exclusion
    target::NamedTuple
    status::Symbol
    rules::Vector{Int}
    labels::Vector{String}
    minimal::Symbol
    limit::Union{Nothing, Pair{Symbol, Int}}
end

"""
    TestCases{T} <: AbstractVector{T}

The cases a generation call returns. `T` is a `NamedTuple` type for named
spaces and a `Tuple` type for positional calls (§1.18); each field's type is
the element type of the stored domain, so a `Vector{Int}` domain gives an
`Int` field, `[nothing, :x]` a `Union{Nothing, Symbol}` field, and an
`Any[1, 1.0]` domain an `Any` field whose values stay `1` and `1.0` (§2.4).
Rows are immutable.

# A vector of rows

A `TestCases` is a read-only `AbstractVector{T}`: `length`, `cases[i]`,
`first`, `last`, `eachindex` and iteration work as for any vector, and
`for (mode, solver, tol) in cases` destructures each row. `collect(cases)`
and `copy(cases)` are plain, mutable `Vector{T}`s, and so is a slice such as
`cases[1:2]` or `cases[[1, 3]]`; the bookkeeping stays with the original.
`==` compares rows, as for any vector, so `cases == collect(cases)`.

# Fields

All recorded at generation and never recomputed (§1.19, §1.22):
`cases`, `space`, `strategy` (`:covering`, `:excursion`, `:full_factorial`),
`strength` (the covering strength; 0 when the strategy has no strength),
`stronger` (as `names => strength` pairs, base group excluded),
`engine::Symbol`, `seed`, `n_must_include`, `required` and `covered`
(ordinary target counts; zero for non-covering strategies), `excluded`
([`Exclusion`](@ref)s, in target order, §9.7), `positional::Bool`, and
`notes`, which is strategy specific (§7.3, §7.7):

- an excursion's `base`, the base row, of the result's row type `T`;
  `distance`, after clamping to the parameter count; `dropped`, the number
  of rows within the distance that broke a rule; and `never_appear`, the
  values that appear in no returned row, as a `Vector{Pair{Symbol, Any}}`
  of `name => value` in parameter and domain order (`:p2 => 3` for a
  positional result);
- a full factorial's `candidates` (the product) and `accepted` (the valid
  rows);
- nothing for a covering design.

Negative bookkeeping arrives in Phase 6 and is kept separate.

# Display

`show` prints a summary line, the excluded targets' counts, and the rows as
a table (§1.22):

```
5 cases · strength 2 · IPOG · 3 parameters · 12 combinations
excluded: 3 pairs forbidden, 2 impossible because constraints combine; see report(cases)
    mode    solver  tol
 1  :exact  :qr     1.0e-6
 2  :exact  :lu     1.0e-6
 3  :exact  :none   1.0e-6
 4  :fast   :none   0.001
 5  :fast   :none   1.0e-6
```

The summary names the strategy (the strength, any `stronger` groups and the
engine, with GND's seed; an excursion's distance, base and dropped rows; a
full factorial), the parameter count and the size of the full product. It
adds the number of valid rows only when generation already knows it: for a
full factorial, and for a covering design at strength equal to the parameter
count, where the required targets are the valid rows. Values print with
`show`, so `:fast` and `"fast"` differ. In a REPL (an `IOContext` with
`:limit => true`), long results keep their first 10 and last 5 rows and wide
cells and columns are cut to the display size, as a `DataFrame` does;
otherwise every row prints in full. Inside a container, a `TestCases`
prints as its summary line. Display performs no search, rule evaluation or
coverage count; verification and bonus coverage belong to `report` and
`coverage` (§1.23).

# Tables

A `TestCases` of named rows is a vector of `NamedTuple`s, which Tables.jl
reads as a row table: `DataFrame(cases)` has one column per parameter, with
the field types above, and `CSV.write(path, cases)` writes a header of
parameter names and one line per case. CSV is text: a `Symbol` is written
as its name and reads back as a string (`:fast` becomes `"fast"`), and `1`
and `1.0` in an `Any` column are written as `1` and `1.0`. CSV.jl refuses a
`nothing` value; write `CSV.write(path, cases; transform = (column, value) ->
something(value, missing))` to write it as an empty field, which reads back
as `missing`.

A positional result is a vector of `Tuple`s, which Tables.jl does not
recognize as a table (`Tables.istable(cases)` is `false`): `DataFrame(cases)`
still builds, with columns named `1`, `2`, `3`, and `CSV.write` fails. Name
the columns yourself:

```julia
DataFrame(cases, parameters(cases.space))          # columns p1, p2, p3
CSV.write(path, NamedTuple{Tuple(parameters(cases.space))}.(cases))
```
"""
struct TestCases{T} <: AbstractVector{T}
    cases::Vector{T}
    space::TestSpace
    strategy::Symbol
    strength::Int
    stronger::Vector{Pair{Tuple{Vararg{Symbol}}, Int}}
    engine::Symbol
    seed::Union{Nothing, Int}
    n_must_include::Int
    required::Int
    covered::Int
    excluded::Vector{Exclusion}
    positional::Bool
    notes::NamedTuple
end

Base.size(tc::TestCases) = size(tc.cases)
Base.getindex(tc::TestCases, i::Int) = tc.cases[i]
Base.IndexStyle(::Type{<:TestCases}) = IndexLinear()
Base.collect(tc::TestCases) = copy(tc.cases)

"The element type for rows of `space`: a NamedTuple type, or a Tuple type when positional."
function row_type(space::TestSpace, positional::Bool)
    types = Tuple{(eltype(v) for v in space.values)...}
    return positional ? types : NamedTuple{Tuple(space.names), types}
end

"""
    TestCases(request, design; positional = false)

Build the public result from an engine's `Design`. Rows come from
`to_cases`; positional results drop the names (§1.18). Exclusions are
translated into names and labels, and an excursion's `base` and
`never_appear` from engine positions into values. `strength` is the
request's for a covering design and 0 for the strategies that have none.
"""
function TestCases(request::Request, design::Design; positional::Bool = false)
    space = request.space
    T = row_type(space, positional)
    named = to_cases(request, design.matrix)
    cases = positional ? T[Tuple(values(c)) for c in named] : T[c for c in named]
    stronger = Pair{Tuple{Vararg{Symbol}}, Int}[
        Tuple(space.names[g]) => s for (g, s) in request.groups[2:end]]
    excluded = Exclusion[
        Exclusion(from_indices(space, _space_indices(request, e.target)), e.status, e.rules,
                  [rule_label(space, k) for k in e.rules], e.minimal, e.limit)
        for e in design.excluded]
    strength = design.strategy === :covering ? request.strength : 0
    notes = design.strategy === :excursion ? _excursion_notes(request, design.notes, T, positional) :
                                             design.notes
    return TestCases{T}(cases, space, design.strategy, strength, stronger, design.engine,
                        design.seed, design.n_must_include, design.required, design.covered,
                        excluded, positional, notes)
end

"""
    _excursion_notes(request, notes, T, positional) -> NamedTuple

An excursion design's notes in the caller's vocabulary, through the same
`candidates` mapping as `to_cases`: `base` becomes a row of type `T`, and
`never_appear`, `(parameter, position)` pairs, becomes `name => value`
pairs. `dropped` and `distance` are counts and stay as they are.
"""
function _excursion_notes(request::Request, notes::NamedTuple, T::Type, positional::Bool)
    space = request.space
    row = from_indices(space, _space_indices(request, notes.base))
    base = convert(T, positional ? Tuple(row) : row)
    never_appear = Pair{Symbol, Any}[space.names[i] => space.values[i][request.candidates[i][k]]
                                     for (i, k) in notes.never_appear]
    return merge(notes, (base = base, never_appear = never_appear))
end


## Display (plan Phase 4 step 6; contract §1.22, §1.23)
#
# Everything printed below was recorded at generation: the counts come from
# the result's fields, the product from the domains' lengths, and the valid
# count only from a strategy that already has it. Nothing here calls
# `explain`, `classify`, `isallowed` or a feasibility search, and nothing
# reads `space.tables` (§1.22); test_testcases.jl checks that a lazy rule is
# never evaluated.

function Base.show(io::IO, e::Exclusion)
    show(IOContext(io, :typeinfo => Any), e.target)
    print(io, ": ")
    rules, labels = e.rules, e.labels
    if e.status === :forbidden
        print(io, "forbidden")
        if length(rules) == 1
            print(io, " by ", _rule_phrase(only(rules), only(labels)))
        elseif !isempty(rules)
            print(io, " by ", _rule_numbers(rules), " ", _rule_details(rules, labels))
        end
    elseif e.status === :implied
        if length(rules) == 1
            print(io, "impossible because of ", _rule_phrase(only(rules), only(labels)))
        else
            print(io, "impossible because ", _rule_numbers(rules), " combine ", _rule_details(rules, labels))
        end
    else
        print(io, e.status)
    end
    if e.minimal === :unresolved
        print(io, " (explanation unresolved")
        e.limit === nothing || print(io, ": ", e.limit.first, " = ", _grouped(e.limit.second), " reached")
        print(io, ")")
    end
    return nothing
end

"""
    _valid_count(cases::TestCases) -> Union{Nothing, Integer}

The number of valid rows in the full product when generation already knows
it (§1.22), else `nothing`. A full factorial counted them (`notes.accepted`).
A covering design at strength equal to the parameter count has the complete
rows as its targets, so its required targets are exactly the valid rows.
"""
function _valid_count(tc::TestCases)
    tc.strategy === :full_factorial && return tc.notes.accepted
    tc.strategy === :covering && tc.strength == length(tc.space.names) && return tc.required
    return nothing
end

function _engine_phrase(tc::TestCases)
    tc.engine === :GND || return string(tc.engine)
    return tc.seed === nothing ? "GND, caller's rng" : "GND seed $(tc.seed)"
end

_shown(io::IO, x) = sprint(show, x; context = IOContext(io, :typeinfo => Any))

# The first `k` entries of a row, then "…": "(mode = :fast, …)" or "(:fast, …)".
function _row_prefix(io::IO, row::Union{NamedTuple, Tuple}, k::Integer)
    k >= length(row) && return _shown(io, row)
    entries = row isa NamedTuple ?
        [string(name, " = ", _shown(io, row[name])) for name in keys(row)[1:k]] :
        [_shown(io, row[j]) for j in 1:k]
    return string("(", join(entries, ", "), ", …)")
end

"""
    _summary_parts(io, cases; base_entries) -> Vector{String}

The pieces of the summary line, joined by " · " when printed. An excursion's
base shows its first `base_entries` values.
"""
function _summary_parts(io::IO, tc::TestCases; base_entries::Integer = length(tc.space.names))
    size_text = _plural(length(tc), "case")
    tc.n_must_include > 0 && (size_text *= " ($(tc.n_must_include) must-include)")
    parts = [size_text]
    if tc.strategy === :covering
        strength = "strength $(tc.strength)"
        for (names, s) in tc.stronger
            strength *= ", $s within ($(join(names, ", ")))"
        end
        push!(parts, strength, _engine_phrase(tc))
    elseif tc.strategy === :excursion
        push!(parts, string("excursion, distance ", tc.notes.distance, " from ",
                            _row_prefix(io, tc.notes.base, base_entries)))
    elseif tc.strategy === :full_factorial
        push!(parts, "full factorial")
    else
        push!(parts, string(tc.strategy), _engine_phrase(tc))
    end
    push!(parts, _plural(length(tc.space.names), "parameter"))
    product = _plural(length(tc.space), "combination")
    valid = _valid_count(tc)
    valid === nothing || (product *= ", $valid valid")
    if tc.strategy === :excursion && tc.notes.dropped > 0
        product *= ", " * _plural(tc.notes.dropped, "row") * " dropped"
    end
    push!(parts, product)
    return parts
end

# The summary line. Under `:limit`, an excursion's base is shortened until the
# line fits the display width, keeping at least its first value.
function _print_summary(io::IO, tc::TestCases)
    line = join(_summary_parts(io, tc), " · ")
    if tc.strategy === :excursion && get(io, :limit, false)::Bool
        width = displaysize(io)[2]
        k = length(tc.space.names)
        while textwidth(line) > width && k > 1
            k -= 1
            line = join(_summary_parts(io, tc; base_entries = k), " · ")
        end
    end
    print(io, line)
    return nothing
end

# "excluded: 3 pairs forbidden, 2 impossible because constraints combine;
# see report(cases)". The noun follows the targets' size: pairs, triples, or
# combinations when the size is another or the sizes differ (stronger groups).
function _print_excluded(io::IO, tc::TestCases)
    forbidden = count(e -> e.status === :forbidden, tc.excluded)
    implied = count(e -> e.status === :implied, tc.excluded)
    unresolved = count(e -> e.minimal === :unresolved, tc.excluded)
    sizes = unique(length(e.target) for e in tc.excluded)
    noun = sizes == [2] ? "pair" : sizes == [3] ? "triple" : "combination"
    clauses = Pair{String, Int}[]
    forbidden > 0 && push!(clauses, "forbidden" => forbidden)
    implied > 0 && push!(clauses, "impossible because constraints combine" => implied)
    parts = String[]
    for (k, (what, n)) in enumerate(clauses)
        push!(parts, k == 1 ? string(_plural(n, noun), " ", what) : string(n, " ", what))
    end
    unresolved > 0 && push!(parts, "$unresolved with an unresolved explanation")
    print(io, "excluded: ", join(parts, ", "), "; see report(cases)")
    return nothing
end

# `s` cut to textwidth `w`, ending in "…" when cut.
function _fit(s::AbstractString, w::Integer)
    textwidth(s) <= w && return String(s)
    w <= 1 && return "…"
    out = IOBuffer()
    used = 0
    for c in s
        used + textwidth(c) > w - 1 && break
        print(out, c)
        used += textwidth(c)
    end
    return String(take!(out)) * "…"
end

_pad(s::AbstractString, w::Integer) = s * " "^max(0, w - textwidth(s))

const _MAX_CELL = 32   # a DataFrame's default cell width under :limit
const _MIN_CELL = 6    # narrowest a column is cut to before columns are dropped

"""
    _shown_rows(n, room) -> (head, tail)

Which rows to print when `room` lines are free: all of them when they fit
and number at most 20, otherwise the first `head` and the last `tail` around
a "⋮" line, 10 and 5 when there is room.
"""
function _shown_rows(n::Integer, room::Integer)
    n <= min(20, room) && return n, 0
    budget = max(3, min(16, room))
    tail = min(5, max(1, (budget - 1) ÷ 3))
    head = min(10, budget - 1 - tail)
    head + tail + 1 >= n && return n, 0   # cutting would save no line
    return head, tail
end

"""
    _column_layout(widths, number, width) -> (widths, ncols)

Column widths and the number of columns to print so that a table line fits
`width`, for a table whose row numbers take `number` characters: every cell
cut to `_MAX_CELL`, then the widest columns narrowed one character at a time
down to `_MIN_CELL`, then columns dropped from the right, leaving room for a
final "…" column.
"""
function _column_layout(widths::Vector{Int}, number::Int, width::Int)
    cut = min.(widths, _MAX_CELL)
    narrowest = min.(cut, _MIN_CELL)
    m = length(cut)
    total(k) = 1 + number + sum(cut[j] + 2 for j in 1:k; init = 0) + (k < m ? 3 : 0)
    while total(m) > width
        shrinkable = [j for j in 1:m if cut[j] > narrowest[j]]
        isempty(shrinkable) && break
        cut[shrinkable[argmax(cut[shrinkable])]] -= 1
    end
    ncols = m
    while ncols > 1 && total(ncols) > width
        ncols -= 1
    end
    return cut, ncols
end

# One table line: the row label right-aligned in `number` characters, then
# the first `ncols` texts, each fit to its width, then "…" if columns were
# dropped. The last column is not padded, so no line has trailing spaces.
function _print_line(io::IO, label, texts, widths, ncols, number)
    print(io, "\n", " ", lpad(label, number))
    for j in 1:ncols
        text = _fit(texts[j], widths[j])
        print(io, "  ", j == length(texts) ? text : _pad(text, widths[j]))
    end
    ncols < length(texts) && print(io, "  …")
    return nothing
end

"""
    _print_table(io, cases, used)

The rows as an aligned table under a header of parameter names, with row
numbers. `used` counts the lines printed above the rows, the header
included. Under `:limit` the rows and columns are cut to `displaysize(io)`;
otherwise everything prints.
"""
function _print_table(io::IO, tc::TestCases, used::Integer)
    limit = get(io, :limit, false)::Bool
    height, width = displaysize(io)
    n = length(tc)
    head, tail = limit ? _shown_rows(n, height - used - 3) : (n, 0)
    rows = [1:head; (n - tail + 1):n]
    names = [string(name) for name in tc.space.names]
    cells = [[_shown(io, tc.cases[r][j]) for r in rows] for j in eachindex(names)]
    natural = [maximum(textwidth, cells[j]; init = textwidth(names[j])) for j in eachindex(names)]
    number = max(textwidth(string(n)), tail > 0 ? 1 : 0)
    widths, ncols = limit ? _column_layout(natural, number, width) : (natural, length(names))
    _print_line(io, "", names, widths, ncols, number)
    for (k, r) in enumerate(rows)
        _print_line(io, string(r), [cells[j][k] for j in eachindex(names)], widths, ncols, number)
        tail > 0 && k == head && _print_line(io, "⋮", fill("⋮", length(names)), widths, ncols, number)
    end
    return nothing
end

Base.show(io::IO, tc::TestCases) = _print_summary(io, tc)

function Base.show(io::IO, ::MIME"text/plain", tc::TestCases)
    _print_summary(io, tc)
    used = 1
    if !isempty(tc.excluded)
        print(io, "\n")
        _print_excluded(io, tc)
        used += 1
    end
    _print_table(io, tc, used + 1)
    return nothing
end
