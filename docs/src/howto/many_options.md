# Test a function with many options

A function with four or five options has more combinations than anyone
writes by hand, and most of the faults in such code need only one or two
options set a particular way. Name each option's values in a
[`TestSpace`](@ref), ask [`all_pairs`](@ref) for cases in which every pair of
values appears, and loop over the cases in a `@testset`.

The function under test here is `smooth(x; window, boundary, kernel)`, a
moving-window filter, defined in a hidden block. Any function with options
works the same way.

```@setup many
function smooth(x::AbstractVector; window = 3, boundary = :clamp, kernel = :box)
    h = window ÷ 2
    w = kernel == :box ? ones(window) :
        kernel == :triangle ? [h + 1.0 - abs(k) for k in -h:h] :
        [exp(-k^2 / 2) for k in -h:h]
    w ./= sum(w)
    n = length(x)
    at(i) = boundary == :clamp ? x[clamp(i, 1, n)] :
            boundary == :periodic ? x[mod1(i, n)] :
            x[i < 1 ? 2 - i : i > n ? 2n - i : i]        # :reflect
    return [sum(w[k + h + 1] * at(i + k) for k in -h:h) for i in 1:n]
end
```

## 1. Describe the options

Give each option a name and the values worth trying, in the order you want
them tried. Add a rule for each combination the function does not support.

```@example many
using UnitTestDesign, Test

space = TestSpace((
        window   = [1, 3, 5],
        boundary = [:clamp, :reflect, :periodic],
        kernel   = [:box, :triangle, :gaussian],
        n        = [1, 4, 100],        # the length of the input
    );
    constraints = [
        @forbid(window == 1 && kernel != :box),
        @forbid(boundary == :reflect && n <= window ÷ 2;
                reason = "reflect needs more points than half the window"),
    ])
```

## 2. Generate the cases

```@example many
cases = all_pairs(space)
```

The summary line says what you asked for: 12 cases at strength 2 over 4
parameters, whose full product has 81 combinations, from the default engine,
`Auto`, which here kept the catalog's array, seeded under the rules
(`Construction()`), over IPOG's 13 cases. Every pair of values of
every two options appears in at least one case, among the pairs some valid
case can hold.

The `excluded:` line counts the pairs that no case holds because the rules
exclude them: here, a window of 1 with a kernel other than `:box`. They are
not gaps in the design, since no valid case could contain them. When a
space also shows pairs "impossible under the constraints", no single rule
forbids those pairs, but the rules together leave no valid case that holds
them.

## 3. Loop over the cases

```@example many
@testset "smooth" begin
    for (; window, boundary, kernel, n) in cases
        y = smooth(fill(2.0, n); window, boundary, kernel)
        @test length(y) == n
        @test all(≈(2.0), y)       # a constant input stays constant
    end
end
nothing # hide
```

Each case is a `NamedTuple`, so `(; window, boundary, kernel, n)` picks the
values out by name, and reordering the space cannot swap two arguments. The
test needs an oracle that holds for every combination of options; a
property such as "a constant stays constant" is often easier to state than
an exact answer. See
[Choosing values and oracles](../explain/values_and_oracles.md).

## 4. Read the excluded line in full

[`report`](@ref) measures the cases again and lists each excluded
combination with the rule that excludes it:

```@example many
report(cases)
```

The `bonus:` line is the interaction coverage the pairs give at the next
strength: 50 of the 92 feasible triples already appear. The prefix curve
says how much the first cases cover, for a suite that runs only some of
them.

## 5. When to go to triples

Go to [`all_triples`](@ref) when a fault is likely to need three options set
together, or when cases are cheap enough that the extra rows do not matter.
To raise the strength only for the options that interact, name them in
`stronger`:

```@example many
(length(all_triples(space)),
 length(all_pairs(space; stronger = [(:window, :boundary, :n) => 3])),
 length(full_factorial(space)))
```

Every triple takes 31 cases, triples within the three named options 25,
and every valid case 57. These counts are the rows the engine produced for
this space, not lower bounds. [`design_sizes`](@ref) prints them side by side with the pairs and
triples each design covers, as in
[Run a simulation campaign](simulation_campaign.md).

## Pitfall: a rule means "never tested here"

A rule removes a combination from this test entirely. `smooth` with
`boundary = :reflect` and too few points throws an error instead of
returning a value. If throwing is the documented behavior, that is worth a
test of its own, with the rejected combinations as its cases: see
[Test invalid inputs](invalid_inputs.md).
