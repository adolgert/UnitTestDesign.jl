# The deterministic fixture inventory.
#
# Phase 1, step 4 of design/20260926_implementation_plan.md. Each fixture is
# plain data for the independent checker (checker.jl), with the 0.4 positional
# inputs where the 0.4 API can express the problem. Each names the contract
# clauses it exercises (docs/src/dev/contract.md) and lists the engine or
# production tests that are pending, with the phase that activates them.
# test_fixtures.jl asserts the hand-known facts with the checker now.
#
# This file expects the names from checker.jl and random_problems.jl in scope;
# the `Checker` test module in test_checker.jl includes all three.

export Fixture, FIXTURES, fixture_space,
    astra_chain, fable_solver, opus_gpu,
    disconnected_unsat, disconnected_witness, whole_case_connects,
    limit_exhaustion, heterogeneous_values, partial_seeds, overlapping_groups,
    invalid_beside_ordinary, partition_names,
    invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
    partition_symbol_collision, duplicate_partition_name

"""
A named fixture.

- `input`: `(names, domains, rules)`, exactly as given to `CheckSpace`.
- `space`: the `CheckSpace`, or `nothing` for inputs that construction must
  reject.
- `legacy`: `(domains, disallow)` for the 0.4 positional API, plus `wayness`
  where it matters, or `nothing` when 0.4 cannot express the problem.
- `request`: the request details the fixture is about (strength, `stronger`,
  must-include rows, limits).
- `clauses`: contract clauses exercised.
- `pending`: `phase => description` for each engine or production test that
  waits for that phase.
"""
struct Fixture
    name::Symbol
    input::NamedTuple
    space::Union{CheckSpace,Nothing}
    legacy::Union{NamedTuple,Nothing}
    request::NamedTuple
    clauses::Vector{String}
    pending::Vector{Pair{Int,String}}
end

function Fixture(name, names, domains, rules = [];
                 request = (;), clauses, pending, legacy = true, rejected = false, wayness = nothing)
    input = (names = names, domains = domains, rules = rules)
    space = rejected ? nothing : CheckSpace(names, domains, rules)
    leg = if legacy && !rejected
        base = (domains = [collect(d) for d in domains], disallow = legacy_disallow(space))
        wayness === nothing ? base : merge(base, (wayness = wayness,))
    else
        nothing
    end
    return Fixture(name, input, space, leg, request, clauses, pending)
end

Base.show(io::IO, f::Fixture) = print(io, "Fixture(:", f.name, ")")

"The fixture's CheckSpace, built fresh from its input."
fixture_space(f::Fixture) = CheckSpace(f.input...)


## The three named examples

"""
Astra's example: `A == B` and `B == C` over `(1, 2)`. Only `(1, 1, 1)` and
`(2, 2, 2)` are valid; `(A = 1, C = 2)` is implied, `(A = 1, B = 2)` is
forbidden by rule 1. Contract §1.2, §1.4. Engine tests: Phase 2 (classify),
Phase 3 (generation).
"""
const astra_chain = Fixture(:astra_chain, [:A, :B, :C], [[1, 2], [1, 2], [1, 2]],
    [((:A, :B), (a, b) -> a != b),
     ((:B, :C), (b, c) -> b != c)];
    clauses = ["1.2", "1.4"],
    pending = [2 => "explain((A = 1, C = 2)) is infeasible, implied by rules 1 and 2",
               3 => "IPOG and GND return (1,1,1) and (2,2,2) and cover all 6 feasible pairs"])

"""
Fable's solver example: fast mode has no solver; exact mode needs a tight
tolerance. 5 valid rows of 12; 11 feasible pairs; 3 direct exclusions
(fast+lu and fast+qr by rule 1, exact+1e-3 by rule 2) and 2 implied
(lu+1e-3, qr+1e-3). Contract §1.4, §1.5. Engine tests: Phase 2 (classify,
explain), Phase 3 (generation), Phase 5 (coverage and report).
"""
const fable_solver = Fixture(:fable_solver, [:mode, :solver, :tol],
    [[:fast, :exact], [:none, :lu, :qr], [1e-3, 1e-6]],
    [((:mode, :solver), (m, s) -> m == :fast && s != :none),
     ((:mode, :tol), (m, t) -> m == :exact && t == 1e-3)];
    clauses = ["1.4", "1.5", "1.8"],
    pending = [2 => "classify: 3 direct pairs naming their rules, 2 implied with rules [1, 2]",
               3 => "IPOG and GND cover all 11 feasible pairs; IPOG in 5 rows",
               5 => "coverage and report agree with the checker: 11 of 11, 3 forbidden, 2 implied"])

"""
Opus's example from issue #51: a GPU needs CUDA and Windows has no CUDA, so
`(os = :windows, gpu = true)` is implied. The 0.4 IPOG throws a BoundsError
and GND never returns. Contract §1.2, §1.3. Engine tests: Phase 2
(classify), Phase 3 (generation; closes issue #51).
"""
const opus_gpu = Fixture(:opus_gpu, [:os, :gpu, :driver],
    [[:linux, :mac, :windows], [false, true], [:cuda, :none]],
    [((:gpu, :driver), (g, d) -> g && d == :none),
     ((:os, :driver), (o, d) -> o == :windows && d == :cuda)];
    clauses = ["1.2", "1.3", "1.4"],
    pending = [2 => "explain((os = :windows, gpu = true)) is infeasible, implied by rules 1 and 2",
               3 => "IPOG and GND cover all 13 feasible pairs without crashing or hanging (issue #51)"])


## Disconnected components

"""
An unsatisfiable component beside an unconstrained parameter. `x` and `y`
are forbidden both to match and to differ, so no row is valid, although
`free` appears in no rule. `(free = 1,)` is infeasible (implied): its
completion must solve the `{x, y}` component too. Contract §3.4 (every
component, including those with no assigned parameter), §1.24 (a proven
empty space yields an empty design, not an error). Engine tests: Phase 2
(completable), Phase 3 (generation).
"""
const disconnected_unsat = Fixture(:disconnected_unsat, [:free, :x, :y],
    [[1, 2, 3], [1, 2], [1, 2]],
    [((:x, :y), (x, y) -> x == y),
     ((:x, :y), (x, y) -> x != y)];
    clauses = ["3.4", "1.24", "1.2"],
    pending = [2 => "completable((free = 1,)) is proven infeasible by the {x, y} component",
               3 => "all_pairs returns no rows and reports every target excluded, without error"])

"""
Two satisfiable components whose only witnesses use each domain's last
values: `a + b < 6` is forbidden over `1:3`, leaving `(3, 3)`, and `(c, d)`
must be `(:y, :y)`. `e` is free. A witness for `(e = 1,)` must combine both
components' non-default values. Contract §3.1 (witness), §3.4, §3.5 (cache
keys). Engine tests: Phase 2 (witness combination), Phase 3 (generation).
"""
const disconnected_witness = Fixture(:disconnected_witness, [:a, :b, :c, :d, :e],
    [[1, 2, 3], [1, 2, 3], [:x, :y], [:x, :y], [1, 2]],
    [((:a, :b), (a, b) -> a + b < 6),
     ((:c, :d), (c, d) -> !(c == :y && d == :y))];
    clauses = ["3.1", "3.4", "3.5"],
    pending = [2 => "completable((e = 1,)) returns the witness (3, 3, :y, :y, 1)",
               3 => "IPOG and GND return only rows with a = b = 3 and c = d = :y"])

"""
The two components of `disconnected_witness` joined by a whole-case rule that
forbids `e == 1` whenever `c == :y`. Since `c` must be `:y`, `(e = 1,)` is
infeasible, though no scoped rule mentions `e`: implied through the
whole-case rule. Contract §12.9, §12.20, §12.21 (a whole-case rule connects
every parameter), §5.6. Engine tests: Phase 2, Phase 3.
"""
const whole_case_connects = Fixture(:whole_case_connects, [:a, :b, :c, :d, :e],
    [[1, 2, 3], [1, 2, 3], [:x, :y], [:x, :y], [1, 2]],
    [((:a, :b), (a, b) -> a + b < 6),
     ((:c, :d), (c, d) -> !(c == :y && d == :y)),
     ((:a, :b, :c, :d, :e), (a, b, c, d, e) -> e == 1 && c == :y)];
    clauses = ["12.9", "12.20", "12.21", "5.6"],
    pending = [2 => "explain((e = 1,)) is infeasible with rules [2, 3]; (e = 2,) completable",
               3 => "generation returns the single valid row (3, 3, :y, :y, 2)"])


## Resource limits

"""
A search that a small `feasibility_limit` cannot finish. Eight parameters over
`1:4` and one whole-case rule that allows only the row of all 4s, so every
feasibility question must reach the last value of every parameter. With
`feasibility_limit = 1` every target is unknown; the default limit resolves
them (at most 4^8 complete rows). The checker enumerates it: 1 valid row, 28
feasible pairs. Contract §3.1, §3.3, §3.6–§3.8, §3.10, §1.7. Nothing in Phase 1
consumes a limit. Engine tests: Phase 2 (explain), Phase 3 (generation
throws ResourceLimitError), Phase 5 (coverage reports unknown).
"""
const limit_exhaustion = Fixture(:limit_exhaustion, [Symbol(:x, i) for i in 1:8],
    [collect(1:4) for _ in 1:8],
    [(Tuple(Symbol(:x, i) for i in 1:8), (xs...) -> !all(==(4), xs))];
    request = (small_limit = 1, default_limit = 1_000_000),
    clauses = ["3.1", "3.3", "3.6", "3.7", "3.8", "3.10", "1.7"],
    pending = [2 => "explain(space, (x1 = 4,); feasibility_limit = 1) is unknown; the default limit finds the witness",
               3 => "all_pairs(space; feasibility_limit = 1) throws ResourceLimitError; retry with the default succeeds",
               5 => "coverage with feasibility_limit = 1 lists unknown targets and claims no percentage"])


## Values

"""
Heterogeneous values. `x` holds `1` and `1.0` (two choices), `y` holds
`nothing` as a value, and `z` holds `:s` and `"s"`. Rule 1 compares by `===`
and forbids only `(x = 1.0, y = nothing)`. Rule 2 uses `==`, which matches
both `1` and `1.0` (contract §12.23), and forbids `z == "s"` with either. So
`z = "s"` is infeasible and its pairs with `y` are implied. 3 valid rows of
8; 7 feasible pairs, 3 direct, 2 implied. No 0.4 form: `nothing` is the 0.4
unassigned sentinel. Contract §2.1–§2.4, §2.9, §12.23. Engine tests: Phase 2
(storage), Phase 4 (TestCases preserves types), Phase 5 (coverage keys).
"""
const heterogeneous_values = Fixture(:heterogeneous_values, [:x, :y, :z],
    [Any[1, 1.0], [nothing, :a], Any[:s, "s"]],
    [((:x, :y), (x, y) -> x === 1.0 && y === nothing),
     ((:x, :z), (x, z) -> x == 1 && z == "s")];
    legacy = false,
    clauses = ["2.1", "2.2", "2.3", "2.4", "2.9", "12.23"],
    pending = [2 => "TestSpace keeps 1 and 1.0 as two choices and nothing as a value",
               4 => "generated rows keep Int, Float64, Nothing, Symbol and String values unconverted",
               5 => "coverage of the 3 valid rows is 7 of 7 feasible, keyed by identity"])


## Must-include rows

"""
Partial must-include rows on Fable's solver space. `(solver = :lu,)` has one
completion, `(mode = :exact, solver = :lu, tol = 1e-6)`. `(solver = :lu, tol =
1e-3)` has none (implied). `(mode = :fast, solver = :lu, tol = 1e-6)` is
complete and violates rule 1. No 0.4 form: 0.4 seeds are complete rows.
Contract §10.1–§10.5, §7.9, §7.10. Engine tests: Phase 4 (must_include).
"""
const partial_seeds = Fixture(:partial_seeds, fable_solver.input.names,
    fable_solver.input.domains, fable_solver.input.rules;
    legacy = false,
    request = (completable = [(solver = :lu,)],
               infeasible = [(solver = :lu, tol = 1e-3)],
               violating = [(mode = :fast, solver = :lu, tol = 1e-6)]),
    clauses = ["10.1", "10.2", "10.3", "10.4", "10.5", "7.9", "7.10"],
    pending = [4 => "must_include = [(solver = :lu,)] is completed in place to (exact, lu, 1e-6) and comes first",
               4 => "must_include = [(solver = :lu, tol = 1e-3)] is an error carrying its explanation",
               4 => "must_include = [(mode = :fast, solver = :lu, tol = 1e-6)] is an error naming rule 1"])


## Strength groups

"""
Overlapping `stronger` groups `(a, b, c) => 3` and `(b, c, d) => 3` over
binary parameters, with `(b = 2, c = 2)` forbidden. Targets: 23 feasible
pairs, 6 feasible triples in each group, so 35 feasible and 5 forbidden
(the pair and two triples per group). Listing a group twice changes nothing
(§11.8). `legacy.wayness()` returns a fresh 0.4 `wayness` Dict, because 0.4
mutates the one it is given (§11.9). Contract §1.8, §11.3–§11.9. Engine
tests: Phase 3 (ipog_multi_way and GND), Phase 4 (stronger keyword).
"""
const overlapping_groups = Fixture(:overlapping_groups, [:a, :b, :c, :d],
    [[1, 2], [1, 2], [1, 2], [1, 2]],
    [((:b, :c), (b, c) -> b == 2 && c == 2)];
    request = (strength = 2,
               stronger = [(:a, :b, :c) => 3, (:b, :c, :d) => 3],
               stronger_twice = [(:a, :b, :c) => 3, (:b, :c, :d) => 3, (:c, :b, :a) => 3]),
    wayness = () -> Dict(3 => [[1, 2, 3], [2, 3, 4]]),
    clauses = ["1.8", "11.3", "11.4", "11.6", "11.7", "11.8", "11.9"],
    pending = [3 => "IPOG (ipog_multi_way) and GND cover all 35 feasible targets and leave wayness unmutated",
               4 => "covering(space; stronger) covers the union; the caller's stronger vector is unchanged"])


## Wrappers

"""
`Invalid(1)` beside the ordinary `1`: two choices. Ordinary rows: 4.
Negative rows (rule 1 mentions `n` and is skipped; rule 2 applies): 3.
Negative targets at strength 2: 4, all feasible; at strength 1: `(n =
Invalid(1),)`. The partial must-include row `(n = Invalid(1),)` is completed
as a negative row. Contract §2.12, §5.1–§5.9, §6.1–§6.6, §7.9. Engine tests:
Phase 2 (validation), Phase 6 (generation and measurement).
"""
const invalid_beside_ordinary = Fixture(:invalid_beside_ordinary, [:n, :m, :k],
    [[1, 2, CheckInvalid(1)], [:a, :b], [:x, :y]],
    [((:n, :m), (n, m) -> n == 2 && m == :b),
     ((:m, :k), (m, k) -> m == :a && k == :y)];
    legacy = false,
    request = (negative_seed = [(n = CheckInvalid(1),)],),
    clauses = ["2.12", "5.1", "5.5", "5.7", "5.9", "6.1", "6.4", "6.6", "7.9"],
    pending = [2 => "TestSpace accepts 1 and Invalid(1) in one domain",
               6 => "all_pairs covers 9 ordinary pairs and 4 negative targets, reported separately",
               6 => "must_include = [(n = Invalid(1),)] completes as a negative row"])

"""
Partitions. `size` holds `Partition(:tiny)`, `Partition(:huge)` and `100`;
`mode` holds `:a`, `:b` and a raw `:tiny`, which is allowed in a different
parameter (§4.4). The rule sees the name and forbids `(size = :tiny, mode =
:b)`. 8 valid rows of 9. Contract §4.2–§4.6, §2.11, §2.13. Engine tests:
Phase 2 (validation, rules see names), Phase 6 (generation keeps wrappers;
`realize`).
"""
const partition_names = Fixture(:partition_names, [:size, :mode],
    [[CheckPartition(:tiny), CheckPartition(:huge), 100], [:a, :b, :tiny]],
    [((:size, :mode), (s, m) -> s == :tiny && m == :b)];
    legacy = false,
    clauses = ["4.2", "4.3", "4.4", "4.5", "4.6", "2.11", "2.13"],
    pending = [2 => "TestSpace accepts the space; the rule receives :tiny",
               6 => "all_pairs rows hold the Partition wrappers; realize draws each once"])


## Inputs that construction must reject

"A domain with only invalid values. Contract §5.2. Engine test: Phase 2."
const invalid_only_domain = Fixture(:invalid_only_domain, [:n, :m],
    [[CheckInvalid(0), CheckInvalid(-1)], [:a, :b]];
    rejected = true, clauses = ["5.2"],
    pending = [2 => "TestSpace rejects `n`: it has no ordinary value"])

"`Invalid(Partition(...))`. Contract §4.12. Engine test: Phase 2."
const nested_invalid_partition = Fixture(:nested_invalid_partition, [:n, :m],
    [[1, CheckInvalid(CheckPartition(:tiny))], [:a, :b]];
    rejected = true, clauses = ["4.12"],
    pending = [2 => "TestSpace rejects the nested wrapper"])

"`Invalid(Invalid(x))`. Contract §4.12. Engine test: Phase 2."
const nested_invalid_invalid = Fixture(:nested_invalid_invalid, [:n, :m],
    [[1, CheckInvalid(CheckInvalid(0))], [:a, :b]];
    rejected = true, clauses = ["4.12"],
    pending = [2 => "TestSpace rejects the nested wrapper"])

"A raw Symbol equal to a partition name in the same domain. Contract §4.4. Engine test: Phase 2."
const partition_symbol_collision = Fixture(:partition_symbol_collision, [:size, :mode],
    [[CheckPartition(:tiny), :tiny], [:a, :b]];
    rejected = true, clauses = ["4.4"],
    pending = [2 => "TestSpace rejects `size`: :tiny is both a Symbol and a partition name"])

"A partition name repeated in one domain. Contract §4.3. Engine test: Phase 2."
const duplicate_partition_name = Fixture(:duplicate_partition_name, [:size, :mode],
    [[CheckPartition(:tiny), CheckPartition(:tiny)], [:a, :b]];
    rejected = true, clauses = ["4.3", "2.5"],
    pending = [2 => "TestSpace rejects `size`: the partition name :tiny repeats"])


"Every fixture, in the order above."
const FIXTURES = Fixture[
    astra_chain, fable_solver, opus_gpu,
    disconnected_unsat, disconnected_witness, whole_case_connects,
    limit_exhaustion, heterogeneous_values, partial_seeds, overlapping_groups,
    invalid_beside_ordinary, partition_names,
    invalid_only_domain, nested_invalid_partition, nested_invalid_invalid,
    partition_symbol_collision, duplicate_partition_name,
]
