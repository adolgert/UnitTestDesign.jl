# In-parameter-order General

## Overview

There is an in-parameter-order general (IPOG) algorithm that is published,
and I've extended it to be more user-friendly. I'll describe both
here.

## The covering problem

A combinatorial covering set is a way to select combinations of values for
testing. We assume that there are `param_cnt` items to select. These could
be parameter values to send to a function. They could be configuration values
for a large simulation. They could be combinations of hardware to test together.
We can represent a selected test case as an array of integers,
`[2, 4, 3, 2]`, which represents the second selection of the first item,
the first selection of the second item, and so on. A test set is a list of
test cases.

We say that a test set has n-way covering when we can choose any `n` parameters
and choose any possible combination of values of those parameters, and find them in some
test case of the test set. We can think of the n-way combinations as their
own data structure, a covering set, where we might represent it as an array
that uses 0 to indicate paramters that aren't in the cover.
```@julia
[[1, 1, 0, 0],
 [2, 1, 0, 0],
 [1, 2, 0, 0],
 [0, 1, 1, 0]
 ...
]
```
A test set covers these tuples if every set of non-zero values in the covering
set can be found in some test case of the test set.

## IPOG

Previous algorithms constructed a single, complete set of parameter values,
called a test case, one at a time. This algorithm starts with a few
parameters, finds a covering set for them, and then uses this as the
basis to add a parameter at a time.

There are a few sources for this work, which I annotate here.

 * Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing.” Software Testing, Verification & Reliability 18 (3): 125–48. - This is the most direct description.

 * Forbes, Michael, Jim Lawrence, Yu Lei, Raghu N. Kacker, and D. Richard Kuhn. 2008. “Refining the In-Parameter-Order Strategy for Constructing Covering Arrays.” Journal of Research of the National Institute of Standards and Technology 113 (5): 287–97. - This updates the algorithm to be more efficient and includes details not explained elsewhere.

 * Tai, Kuo-Chung, and Yu Lei. 2002. “A Test Generation Strategy for Pairwise Testing.” IEEE Transactions on Software Engineering 28 (1). - The original paper is interesting because it thinks more theoretically about the problem.

 * Kuhn, D. Richard, Raghu N. Kacker, and Yu Lei. 2013. Introduction to Combinatorial Testing. CRC Press. This book includes an algorithm description, but it may mix up one of the loops.

A sketch of the algorithm.

1. Given:
   
   * `arity` - which is the number of values for each parameter.
   * `n_way` - which is the coverage level (2, 3,...)

2. Sort the parameters by non-increasing arity. Record this ordering so you can reorder it at the end.

3. Construct an `n_way` full-factorial combination of the first `n_way`
   parameters. This is a correct covering for `n_way` parameters.

4. Add an `n_way+1` value to each test case of those already found. This is called "widening," and we will describe it in more detail below.

5. For all coverage tuples that include the `n_way+1` parameter, loop over the tuples and, first, search for a place to put them in the existing test cases. If there is no spot to put them, then add them as a last test case. They will have missing values, which you mark as missing.

6. Repeat for each parameter until done.

7. Fill missing values and reorder parameters before returning test cases.

The widening step first constructs a list of all covers that include the last parameter. Then it loops over the existing test cases, which have missing values for this new parameter, and it looks for any place it can insert values in order to increase coverage. If an insertion won't increase coverage, it is left blank because a later parameter might use this spot. We denote blanks with 0.

The lengthening step, to add test cases, doesn't loop over test cases to add. It loops over the coverage. It's much more efficient this way. For each cover, it looks to see if there was a place to insert that cover in existing test cases, and then it adds it to the end, using 0 to denote missing values.

The papers go into ways to make this all faster. I'd like to point out a detail I haven't seen discussed, which is that there are several ways to match cases to covers.

Let's assume that a test case is represented as a vector `[1, 0, 2, 0, 4]`, where 0 means it has a missing value, not yet decided. Vectors aren't likely the best data structure, but we can use it to discuss the algorithm anyway. Then a cover might be `[0, 1, 0, 0, 0, 4]`. We need to decide, at different steps, whether to insert a cover into a test case. If we look at any single parameter, there are five different comparisons possible.
```julia
ignores(a, b) = a == 0 && b == 0
skips(a, b) = a != 0 && b == 0
misses(a, b) = a == 0 && b != 0
matches(a, b) = a != 0 && b != 0 && a == b
mismatch(a, b) = a != 0 && b != 0 && a != b
```
We could call a cover a match when there are no mismatches. This includes cases where the cover's nonzeros and the case's nonzeros don't overlap. We could call a cover a match when at least one nonzero matches. There are a few versions of this.

According to projective geometry principles, I have no clue about projective geometry principles. I made a bunch of matching functions and ran the algorithm with different versions until it suddenly made much smaller test sets. Those test sets agree with ones that are published.

## Expanding IPOG

We almost never want a set of test cases from the IPO algorithm. We want test cases that we can use for a particular function or to generate test data for a program, and those have limitations.

* The test generator has to exclude parameter combinations. Some combinations of parameter values are uninteresting. It could be that we don't think there is risk associated with those values or that we aren't testing exception cases at the moment.
* The test generator has to include certain test cases. If I know a few test cases are interesting, I want to start with these, and they should count against the overall coverage. We're assuming the thing we're testing is relatively slow.
* The test generator has to let me increase coverage on certain parameters. If I'm generating a configuration file with these test cases, it could have forty parameters, of which I think ten are the most risky. I don't want 4-way coverage on the whole thing because that's a huge test set, but I do want 4-way coverage of those ten parameter values.

I haven't found papers on how to add these features to IPOG, so I added some algorithms.

For excluding parameter combinations, you pass in a function that tests whethere the given arguments are allowed. The algorithm internally runs this function on every covering tuple and every test case to see whether the given value should be chosen. That's kind of it.

For adding seed cases, we have to add them, in this algorithm, parameter by parameter. The algorithm makes the seeds the first test cases and fills them in as it goes. For the first step, to create all n-way combinations of parameters, the algorithm only adds combinations that don't already exist in the test cases.

It's tricky with IPOG to increase coverage only for certain sets of parameters. I haven't tested this against different methods, but I made a method that runs. I run IPOG multiple times, once for each coverage set. Every time I run IPOG, I treat the existing test cases as seeds for the next run. Those seeds might have lots of zero values, but they get filled in as it goes.
