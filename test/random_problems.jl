# Random constrained problems for the engine gate.
#
# Phase 1, step 4 of design/20260926_implementation_plan.md. Each problem is
# drawn in Opus's shape: 3–8 parameters, 2–4 values each, 1–4 scoped rules over
# 2–3 parameters, about half of them written with `!=` or `<`. A problem carries
# both forms of its rules:
#
#   - `space`, a CheckSpace for the independent oracle in checker.jl, which
#     `test_space` (fixture_model.jl) turns into a production `TestSpace`, and
#   - `domains` and `disallow`, the positional inputs of the 0.4 engines,
#     `all_pairs(domains...; disallow, engine)`. Phase 3 removed `disallow`
#     from the package; this form is kept only as a record, to run a problem
#     against the prior revision (commit d46122d).
#
# The legacy `disallow` receives positional values, with `nothing` for an
# unassigned parameter. It applies a rule only when every parameter in the
# rule's scope is assigned, so it is a correct pruning oracle and never shows
# a rule a partial case (contract §1.6, §12.14). Domains hold small distinct
# integers and never `nothing`, so the legacy sentinel cannot collide with a
# value.
#
# Everything is drawn from the `rng` argument, so a seed reproduces a problem.
#
# This file expects the names from checker.jl in scope; the `Checker` test
# module in test_checker.jl includes both.

using Random

export RandomRule, RandomProblem, random_problem, legacy_disallow

"""
One scoped rule. `scope` holds parameter positions in the order the predicate
receives them. `predicate` returns `true` for a forbidden combination.
"""
struct RandomRule
    scope::Vector{Int}
    kind::Symbol  # :pattern, :not_equal, :less
    predicate::Function
    text::String
end

"""
A random problem at one strength. From the checker, with no design:
`feasible` required targets, `forbidden` directly forbidden targets, and
`implied` targets that are infeasible only because rules combine.
`planted` says whether a two-rule chain was planted to imply an exclusion.
"""
struct RandomProblem
    names::Vector{Symbol}
    domains::Vector{Vector{Int}}
    rules::Vector{RandomRule}
    strength::Int
    space::CheckSpace
    disallow::Function
    feasible::Int
    forbidden::Int
    implied::Int
    planted::Bool
end

function Base.show(io::IO, problem::RandomProblem)
    print(io, "RandomProblem(strength $(problem.strength); ")
    print(io, join(("$n = $(d)" for (n, d) in zip(problem.names, problem.domains)), ", "))
    print(io, "; forbid: ", join((r.text for r in problem.rules), "; "), ")")
end

"""
    legacy_disallow(space::CheckSpace)

The 0.4 `disallow(values...)` for a space's rules. Values arrive in parameter
order with `nothing` for an unassigned parameter. A rule fires only when every
parameter in its scope is assigned. Refuses spaces whose domains contain
`nothing` or wrappers, which the 0.4 API cannot express.
"""
function legacy_disallow(space::CheckSpace)
    for (name, domain) in zip(space.names, space.domains)
        any(x -> x === nothing || x isa CheckInvalid || x isa CheckPartition, domain) &&
            throw(ArgumentError("parameter `$name` has a value the 0.4 disallow cannot express"))
    end
    rules = [(space.scopes[i], space.rules[i][2]) for i in eachindex(space.rules)]
    return function (values...)
        for (scope, predicate) in rules
            any(p -> values[p] === nothing, scope) && continue
            predicate((values[p] for p in scope)...) && return true
        end
        return false
    end
end

"Distinct values from 0:9, so a value and its position differ."
random_domain(rng) = sort!(randperm(rng, 10)[1:rand(rng, 2:4)] .- 1)

function random_rule(rng, names, domains)
    k = rand(rng, 2:3)
    scope = randperm(rng, length(domains))[1:k]
    v = [rand(rng, domains[p]) for p in scope]
    nm = names[scope]
    kind = rand(rng) < 0.5 ? :pattern : rand(rng, (:not_equal, :less))
    if kind == :pattern
        predicate = (xs...) -> all(xs[i] == v[i] for i in 1:k)
        text = join(("$(nm[i]) == $(v[i])" for i in 1:k), " && ")
    elseif kind == :not_equal
        predicate = (xs...) -> all(xs[i] == v[i] for i in 1:(k - 1)) && xs[k] != v[k]
        text = join(vcat(["$(nm[i]) == $(v[i])" for i in 1:(k - 1)], "$(nm[k]) != $(v[k])"), " && ")
    elseif k == 2
        predicate = (x, y) -> x == v[1] && y < v[2]
        text = "$(nm[1]) == $(v[1]) && $(nm[2]) < $(v[2])"
    else
        predicate = (x, y, z) -> x == v[1] && y < z
        text = "$(nm[1]) == $(v[1]) && $(nm[2]) < $(nm[3])"
    end
    return RandomRule(scope, kind, predicate, text)
end

"""
Two rules that imply an exclusion neither states: `a == x` forces `b == y`,
and `b == y` forbids `c == z`, so `(a = x, c = z)` is infeasible.
"""
function planted_chain(rng, names, domains)
    a, b, c = randperm(rng, length(domains))[1:3]
    x, y, z = rand(rng, domains[a]), rand(rng, domains[b]), rand(rng, domains[c])
    return [
        RandomRule([a, b], :not_equal, (p, q) -> p == x && q != y,
                   "$(names[a]) == $x && $(names[b]) != $y"),
        RandomRule([b, c], :pattern, (q, r) -> q == y && r == z,
                   "$(names[b]) == $y && $(names[c]) == $z"),
    ]
end

"""
    random_problem(rng; strength = 2, plant = 0.1)

Draw one problem. With probability `plant` its first two rules are a chain
that implies an exclusion (see `planted_chain`), followed by up to two random
rules; otherwise it has 1–4 random rules. Whether the problem has implied
targets is decided by the checker, in `problem.implied`.
"""
function random_problem(rng::AbstractRNG; strength::Integer = 2, plant::Real = 0.1)
    n = rand(rng, 3:8)
    names = [Symbol(:p, i) for i in 1:n]
    domains = [random_domain(rng) for _ in 1:n]
    planted = rand(rng) < plant
    if planted
        rules = [planted_chain(rng, names, domains);
                 [random_rule(rng, names, domains) for _ in 1:rand(rng, 0:2)]]
    else
        rules = [random_rule(rng, names, domains) for _ in 1:rand(rng, 1:4)]
    end
    space = CheckSpace(names, domains, [(Tuple(names[r.scope]), r.predicate) for r in rules])
    baseline = check_design([], space; strength = strength).ordinary.counts
    return RandomProblem(names, domains, rules, Int(strength), space, legacy_disallow(space),
                         baseline.feasible, baseline.forbidden, baseline.implied, planted)
end
