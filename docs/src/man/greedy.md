# Greedy Fractional Factorial Parameter Generators

This creates a fractional factorial test design for the parameters.
Out of all possible combinations of parameters, this chooses a subset
that contains every possible pair of inputs, or every possible triple,
or even every possible value of each parameter.

The method constructs a list of every tuple that must be tested. Then
it uses weighted random number generation to construct a complete
set of parameters that includes as many of those tuples as possible.
