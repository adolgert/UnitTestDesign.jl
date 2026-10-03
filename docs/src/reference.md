```@meta
CurrentModule = UnitTestDesign
```

# API reference

Every exported name, grouped by the job it does. Each docstring opens with
the situation it serves. The 0.4 spellings that still work, with a warning,
are listed last; [Migration from 0.4](reference/migration.md) shows how to
rewrite them and what was removed.

```@docs
UnitTestDesign
```

## Spaces and values

A [`TestSpace`](@ref) names the parameters of a test and lists their values.
Values are kept as given; [`Invalid`](@ref) marks a value for negative tests
and [`Partition`](@ref) stands for a class of values drawn at run time.

```@docs
TestSpace
parameters
Invalid
Partition
hasinvalid
realize
```

## Rules

Rules exclude combinations of values. All four surface forms build the same
[`Constraint`](@ref), which a space takes in its `constraints` vector.

```@docs
forbid
require
@forbid
@require
Constraint
ConstraintError
```

## Generation

[`covering`](@ref) is the general entry point; [`all_values`](@ref),
[`all_pairs`](@ref) and [`all_triples`](@ref) are `covering` at strength 1,
2 and 3. [`excursions`](@ref) and [`full_factorial`](@ref) are the other two
strategies. Every generator returns a [`TestCases`](@ref).

```@docs
covering
all_values
all_pairs
all_triples
excursions
full_factorial
IPOG
GND
TestCases
Exclusion
ResourceLimitError
```

## Analysis

Questions about a space, and measurement of any set of rows against one.

```@docs
explain
isallowed
coverage
Coverage
iscomplete
missing_interactions
report
Report
design_sizes
DesignSizes
```

### Types returned by `explain` and `coverage`

These types are not exported; their fields are part of the results above.

```@docs
Explanation
CoveragePart
```

## After the run

[`diagnose`](@ref) and [`followups`](@ref) are experimental: their results
are hypotheses to test, not proof. [`github_matrix`](@ref) writes cases for
a CI workflow.

```@docs
diagnose
followups
github_matrix
```

### Types returned by `diagnose` and `followups`

These types are not exported; their fields are part of the results above.

```@docs
Diagnosis
Suspect
Followup
```

## Deprecated

Each warns through `Base.depwarn` and will be removed in the next breaking
release. The deprecated keywords (`n_way`, `seeds`, `wayness`, and
`GND(M = ...)`) are described with the functions that accept them.

```@docs
all_tuples
values_excursion
pairs_excursion
triples_excursion
```
