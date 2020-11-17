```@meta
CurrentModule = UnitTestDesign
```

# UnitTestDesign

```@index
```

This package generates sets of parameters for unit testing. Given all the possible
parameters to test, this package provides functions which help you select
a subset of parameters with which to call the unit test.

There are a set of generators called [greedy generators.](man/greedy.md)

- All pairs
- All values
- All n-tuples

They also support:

- Seeding the parameter generation with manual choices.
- Specifying subsets of parameters that have higher coverage.
- Generating parameter sets that obey calling rules, as specified by a filter function.


```@autodocs
Modules = [UnitTestDesign]
```
