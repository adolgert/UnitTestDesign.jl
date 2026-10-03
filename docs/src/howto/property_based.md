# Combine with property-based testing

Random and property-based tests draw many inputs but make no promise about
which kinds of input meet in one case, while a covering design picks which
kinds to combine but tries one value of each. Use both: each value in
the space stands for a class of inputs, the design decides which classes
meet, and a random draw picks a member of each class every time the test
runs.

## 1. Name the classes with `Partition`

A [`Partition`](@ref) is a named choice with a function that draws a
member. Rules, the design, and coverage see only its name:

```@example pbt
using UnitTestDesign, Random, Test

classes = [Partition(:tiny, rng -> 1e-300 * randn(rng)),
           Partition(:unit, rng -> randn(rng)),
           Partition(:huge, rng -> 1e300 * randn(rng)),
           Partition(:zero, Returns(0.0))]           # a fixed value
space = TestSpace((x = classes, y = classes, z = classes))

cases = all_pairs(space)
```

`Partition(:zero, Returns(0.0))` is the fixed-value form: a class with one
member, which still prints and counts by its name.

## 2. Draw inputs with `realize`

[`realize`](@ref) replaces each partition with one draw from the generator
you pass. There is no default: no draw uses the global random number
generator, so a seed repeats the inputs.

```@example pbt
inputs = realize(cases; rng = Xoshiro(1))
first(inputs, 3)
```

## 3. Test a property on every draw

The function under test computes `sqrt(x^2 + y^2 + z^2)` without overflow
or underflow; the property is that it agrees with `Base.hypot`. Each pass
over the cases draws new members of the same classes:

```@example pbt
function hypot3(x, y, z)
    a = max(abs(x), abs(y), abs(z))
    (iszero(a) || isinf(a)) && return a
    return a * sqrt((x / a)^2 + (y / a)^2 + (z / a)^2)
end

@testset "hypot3" begin
    rng = Xoshiro(20260927)
    for trial in 1:100, (; x, y, z) in realize(cases; rng)
        @test hypot3(x, y, z) ≈ hypot(x, y, z)
    end
end
nothing # hide
```

More trials explore more values under the same interaction coverage: every
pair of classes, such as a huge `x` beside a tiny `z`, meets in every trial.

## 4. Measure and diagnose the labeled rows

Keep the labeled cases beside the realized inputs. Coverage is a claim
about the classes, not about the drawn numbers, so measure the labeled rows:

```@example pbt
coverage(cases)
```

The same goes for [`diagnose`](@ref): give it the labeled rows, since a
drawn value is not in the domain.

## The same idea with no API

Nothing above requires `Partition`. Name the classes with plain `Symbol`s,
cover them with [`all_pairs`](@ref), and draw inside the test body with any
generator you like, including one from a property-based testing library:

```@example pbt
draw(rng, class) =
    class == :tiny ? 1e-300 * randn(rng) :
    class == :unit ? randn(rng) :
    class == :huge ? 1e300 * randn(rng) : 0.0

labels = all_pairs((x = [:tiny, :unit, :huge, :zero],
                    y = [:tiny, :unit, :huge, :zero],
                    z = [:tiny, :unit, :huge, :zero]))

@testset "hypot3, drawn in the body" begin
    rng = Xoshiro(20260927)
    for trial in 1:100, (; x, y, z) in labels
        a, b, c = draw(rng, x), draw(rng, y), draw(rng, z)
        @test hypot3(a, b, c) ≈ hypot(a, b, c)
    end
end
nothing # hide
```

This form fits when a draw depends on other values in the case, such as an
element type, because the body sees the whole case, while a `Partition`'s
draw sees only the generator. It also fits when a library should shrink a
failing input within its class, while the case still reports which classes
it was in.

## Pitfall: a partition's name is taken

Rules see a partition by its name, so a domain cannot hold both a
partition and the raw `Symbol` of its name:

```@example pbt
try
    TestSpace((x = [Partition(:tiny, Returns(1e-9)), :tiny], y = [1, 2]))
catch err
    showerror(stdout, err)
end
```

The same `Symbol` in a different parameter's domain is allowed. In a rule
or a must-include row, write a partition by its name, such as
`forbid((x = :tiny, z = :huge))`.
