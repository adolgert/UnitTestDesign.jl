# Metrics recorded beside the timings (plan §7.3), included by worker.jl.
# Everything here runs outside the timed calls.

# Engine-reported extras, `name => value`, recorded with each measurement as
# `result.engine_extras`. A covering result's `record` holds them (the
# `Design`'s, which `TestCases` keeps): the lower bound and whether it is met;
# and the ordinary design's stage, its own `engine` and `rows` as
# `ordinary_engine` and `ordinary_rows`, and what the engine found, what Auto
# chose, the catalog's array and the reducer's run, each nested NamedTuple
# flattened with its name as a prefix, so the reducer's `steps` is
# `reducer_steps`, as before Phase 3. A covering design's `notes`, empty
# for every engine since Phase 3, are kept too, for an adapter that returns
# its own `Design`, e.g. `Design(matrix, :covering, :Mine, seed, required,
# covered, excluded, n_must_include, (steps = 1200,))`. A trial adapter may
# also call `record_extra(name, value)` during its call. The worker clears
# the dictionary before each timed call, so the extras belong to the call
# they are recorded with.
const EXTRAS = Dict{String, Any}()
record_extra(name, value) = (EXTRAS[string(name)] = value; nothing)
reset_extras!() = empty!(EXTRAS)

json_value(x::Union{Real, AbstractString, Nothing}) = x
json_value(x::Symbol) = string(x)
json_value(x::Union{AbstractVector, Tuple}) = Any[json_value(y) for y in x]
json_value(x::Union{NamedTuple, AbstractDict}) = Dict{String, Any}(string(k) => json_value(v) for (k, v) in pairs(x))
json_value(x) = string(x)

function engine_extras(x)
    out = Dict{String, Any}(k => json_value(v) for (k, v) in EXTRAS)
    if x isa Union{U.Design, TestCases} && x.strategy == :covering
        for (k, v) in pairs(x.notes)
            out[string(k)] = json_value(v)
        end
        for (k, v) in pairs(x.record)
            if k === :ordinary && v isa NamedTuple
                for (j, w) in pairs(v)
                    if j in (:engine, :rows)
                        out[string("ordinary_", j)] = json_value(w)
                    elseif w isa NamedTuple
                        for (i, y) in pairs(w)
                            out[string(j, "_", i)] = json_value(y)
                        end
                    else
                        out[string(j)] = json_value(w)
                    end
                end
            elseif k === :engine && v isa NamedTuple
                out["engine"] = json_value(v)
                out["engine_call"] = v.call
            elseif v isa NamedTuple
                for (j, w) in pairs(v)
                    out[string(k, "_", j)] = json_value(w)
                end
            else
                out[string(k)] = json_value(v)
            end
        end
    end
    return out
end

"""
Lower bounds on a covering result's rows (plan §4.1, "State the bound"):

- `elementary`: for each strength group, the product of its `t` largest
  ordinary value counts; the largest over the groups. Holds without rules.
- `required`: the most required combinations on any one support, which is
  the product of its value counts less its excluded targets. Holds with rules
  too, and equals `elementary` without them. `nothing` when there are
  exclusions and some group has more than 2,000,000 supports.

`cases` counts every row; `ordinary_cases` leaves out rows holding an
`Invalid` value, which the bounds don't count (`nothing` for an index-space
`Design` of a space with `Invalid` values).
"""
function bounds(x, m)
    x isa Union{U.Design, TestCases} && x.strategy == :covering || return Dict{String, Any}()
    names = m.names
    n = length(names)
    arity = [length(ordinary_values(d)) for d in m.domains]
    groups = Tuple{Vector{Int}, Int}[(collect(1:n), m.kw.strength)]
    for (g, t) in m.kw.stronger
        push!(groups, (sort!([findfirst(==(Symbol(nm)), names) for nm in g]), t))
    end
    elementary = maximum(prod(sort(arity[g]; rev = true)[1:min(t, length(g))]; init = 1) for (g, t) in groups)
    excluded = Dict{Vector{Int}, Int}()
    for e in x.excluded
        support = e.target isa NamedTuple ? sort!([findfirst(==(k), names) for k in keys(e.target)]) :
                                            findall(!iszero, e.target)
        excluded[support] = get(excluded, support, 0) + 1
    end
    required = if isempty(excluded)
        elementary
    elseif all(binomial(big(length(g)), t) <= 2_000_000 for (g, t) in groups)
        maximum(maximum(prod(arity[s]; init = 1) - get(excluded, s, 0) for s in combinations(g, t)) for (g, t) in groups)
    else
        nothing
    end
    has_invalid = any(d -> any(x -> x isa Invalid, d), m.domains)
    cases = x isa U.Design ? size(x.matrix, 2) : length(x)
    ordinary_cases = !has_invalid ? cases :
                     x isa TestCases ? count(row -> !any(v -> v isa Invalid, values(row)), x) : nothing
    return Dict{String, Any}("elementary" => elementary, "required" => required, "cases" => cases,
                             "ordinary_cases" => ordinary_cases, "strength" => m.kw.strength,
                             "arity" => arity, "excluded_supports" => length(excluded))
end
