# Test generic code across types

Julia compiles a generic method separately for each combination of argument
types, so code that works for a `Vector{Float64}` can fail for `Float32`,
for `BigFloat`, or for a view. Put the element types and the array kinds in
the space as ordinary values, and cover every pair of element type,
container, and size.

## 1. Put types in the space

A type is a value like any other. `Float32` and `Float64` are different
choices because they are different values; the package compares them, and
never calls or instantiates them.

```@example generic
using UnitTestDesign, Test

space = TestSpace((
        T         = [Float32, Float64, BigFloat],
        container = [:vector, :strided_view, :column_matrix],
        n         = [0, 1, 10_000],
    );
    constraints = [forbid((T = BigFloat, n = 10_000); reason = "BigFloat is slow at this size")])

cases = all_pairs(space)
```

The container is a label, a `Symbol`, rather than a function that builds
one. A function would also be an ordinary value, but a label reads better
in the table and in a test's name, and the test body builds the real input
from it.

## 2. Pass the case to the generic function

The function under test is a compensated sum that should work for any
element type and any `AbstractArray`:

```@example generic
function compensated_sum(x::AbstractArray{T}) where {T}
    s = zero(T); c = zero(T)
    for xi in x
        y = xi - c
        t = s + y
        c = (t - s) - y
        s = t
    end
    return s
end

function build(kind, v)
    kind == :vector       && return v
    kind == :strided_view && return view(repeat(v; inner = 2), 1:2:2length(v))
    return reshape(v, :, 1)                                  # :column_matrix
end

@testset "compensated_sum" begin
    for (; T, container, n) in cases
        x = build(container, [one(T) / k for k in 1:n])
        s = @inferred compensated_sum(x)                     # type-stable for every T
        @test s isa T
        @test s ≈ T(sum(big.(x))) rtol = 2eps(T)
    end
end
nothing # hide
```

Every pair of element type and container, element type and size, and
container and size appears in at least one case, except `BigFloat` at the
large size, which the rule excludes. `@inferred` checks that the compiler
infers the result's type from the argument types, a property only a test
across types can check.

## What the result tells you

The summary counts 10 cases of the 27 in the full product, and the
`excluded:` line names the one pair the rule forbids. If a fault needs an
element type, a container, and a size together, pairs do not guarantee to
find it; `all_triples(space)` is the full product less the forbidden rows
here, and in a larger space it is the next step.

Types and functions in a domain are ordinary values. Nothing is inferred
from them: the package does not treat a function-valued domain as a
generator, and it does not treat a type as a set of values. Only the
[`Partition`](@ref) wrapper stands for a class of values to draw from (see
[Combine with property-based testing](property_based.md)).

## Pitfall: a type's name inside `@forbid`

Inside [`@forbid`](@ref) and [`@require`](@ref), every bare name that is
not called as a function is read as a parameter, and that includes type
names. The rule below fails when the space is built:

```@example generic
try
    TestSpace((T = [Float32, BigFloat], n = [1, 10_000]);
              constraints = [@forbid(T == BigFloat && n == 10_000)])
catch err
    showerror(stdout, err)
end
```

Write `$BigFloat` to use the type's value, or use the pattern form,
`forbid((T = BigFloat, n = 10_000))`, as above. A subtype test such as
`T <: AbstractFloat` is not supported inside the macro, because `<:` is
syntax rather than a function call. Write it as the call,
`@forbid((<:)(T, $AbstractFloat) && n > 1000)`, or with the function form,
`forbid(:T, :n) do T, n; T <: AbstractFloat && n > 1000 end`.
