# In-parameter-order General

## Overview

There is a published in-parameter-order general (IPOG) algorithm, and this
package extends it to handle what real tests need: rules, must-include
cases, and stronger coverage for some parameters. This page describes both.
[Engines](engines.md) compares IPOG with the package's other engine.

## The covering problem

A covering design is a way to select combinations of values for testing.
Suppose there are several parameters to choose. They could be the arguments
of a function, the options of a large simulation, or pieces of hardware to
test together. Inside the engine, a case is an array of integers such as
`[2, 1, 3, 2]`, which picks the second value of the first parameter, the
first value of the second parameter, and so on. A design is a list of cases.

A design has strength ``t`` when, for any ``t`` parameters and any values
of those parameters, some case in the design holds all of them. We can list
the ``t``-way combinations as their own data structure, using 0 for the
parameters a combination leaves out. For pairs over four parameters:

```julia
[[1, 1, 0, 0],
 [2, 1, 0, 0],
 [1, 2, 0, 0],
 [0, 1, 1, 0],
 ...
]
```

A design covers these combinations if the nonzero values of every one of
them appear together in some case.

## IPOG

Earlier algorithms built one complete case at a time. IPOG instead starts
with a few parameters, covers them completely, and then adds one parameter
at a time, extending the cases it already has.

There are a few sources for this work, annotated here.

 * Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing.” Software Testing, Verification & Reliability 18 (3): 125–48. - This is the most direct description.

 * Forbes, Michael, Jim Lawrence, Yu Lei, Raghu N. Kacker, and D. Richard Kuhn. 2008. “Refining the In-Parameter-Order Strategy for Constructing Covering Arrays.” Journal of Research of the National Institute of Standards and Technology 113 (5): 287–97. - This updates the algorithm to be more efficient and includes details not explained elsewhere.

 * Tai, Kuo-Chung, and Yu Lei. 2002. “A Test Generation Strategy for Pairwise Testing.” IEEE Transactions on Software Engineering 28 (1). - The original paper is interesting because it thinks more theoretically about the problem.

 * Kuhn, D. Richard, Raghu N. Kacker, and Yu Lei. 2013. Introduction to Combinatorial Testing. CRC Press. This book includes an algorithm description, but it may mix up one of the loops.

A sketch of the algorithm:

1. Given:

   * the number of values of each parameter, which the algorithm calls its
     arity;
   * the strength ``t`` (2, 3, ...).

2. Sort the parameters by decreasing number of values. Record this ordering
   so you can restore it at the end.

3. Construct the full factorial of the first ``t`` parameters. This covers
   them at strength ``t``.

4. Add parameter ``t + 1`` to each case found so far. This is called
   *horizontal growth*, or widening, and is described below.

5. For every combination that involves parameter ``t + 1`` and is not yet
   covered, look for a case where it fits. If there is none, add a new case
   holding just that combination, with the other parameters marked missing.
   This is *vertical growth*.

6. Repeat for each remaining parameter.

7. Fill the missing values and restore the parameter order.

Horizontal growth first lists every combination that includes the new
parameter. Then it loops over the existing cases, which have no value yet
for the new parameter, and gives each the value that covers the most new
combinations. If no value would add coverage, the entry stays blank, because
a later step might use that spot. Blanks are written as 0.

Vertical growth, which adds cases, does not loop over cases. It loops over
the uncovered combinations, which is much more efficient. For each
combination it looks for a case where the combination fits, and otherwise
appends a new case, using 0 for missing values.

The papers describe ways to make this faster. One detail I haven't seen
discussed is that there are several ways to decide whether a combination
matches a case.

Represent a case as a vector such as `[1, 0, 2, 0, 4]`, where 0 means a
value not yet decided, and a combination the same way, such as
`[0, 1, 0, 0, 4]`. At several steps the algorithm has to decide whether to
put a combination into a case. Comparing one parameter at a time, there are
five possibilities:

```julia
ignores(a, b) = a == 0 && b == 0
skips(a, b) = a != 0 && b == 0
misses(a, b) = a == 0 && b != 0
matches(a, b) = a != 0 && b != 0 && a == b
mismatch(a, b) = a != 0 && b != 0 && a != b
```

A combination could be said to match when there are no mismatches, which
includes the case where the nonzeros of the case and the combination don't
overlap at all. Or it could be said to match only when at least one nonzero
agrees. There are several versions of this.

I don't know the projective geometry that might settle the question. I wrote
several matching functions and ran the algorithm with each until one
suddenly made much smaller designs, and those designs agree in size with
published ones.

## Extending IPOG

A bare covering design is rarely what a test needs. Real tests add three
requirements.

* **Rules.** Some combinations of values are not valid inputs, and the
  design must not contain them.
* **Must-include cases.** Some cases are interesting in their own right, such
  as the happy paths or the cases a specification requires. They should come
  first and count toward coverage, since the thing under test is assumed to
  be slow.
* **Stronger coverage for some parameters.** A configuration file might have
  forty parameters, of which ten carry most of the risk. Four-way coverage
  of all forty would be a huge design, but four-way coverage of those ten,
  with pairs for the rest, may be affordable.

I haven't found papers on adding these to IPOG, so the package extends it
as follows. When there are no rules, no must-include cases, and one
strength, the engine runs the classic algorithm above.

**Rules.** Before generating, every combination is classified: a
combination is required only when some valid case contains it, and the
others are reported as excluded ([Constraints](../explain/constraints.md)).
Then, at each of the three steps that set values (horizontal growth,
placing a combination during vertical growth, and the final fill), the
engine sets a value only when the partial case can still be completed into
a valid case. A new case starts from one required combination, which is
completable by definition, and every later assignment keeps it completable.
So the algorithm never reaches a dead end, and the final fill always finds a
value. Deciding whether a partial case can be completed is a backtracking
search over the rules, bounded by `feasibility_limit`.

**Must-include cases.** The `must_include` cases become the first cases of
the design, in the order given. Their values are never changed; the missing
values of a partial must-include case are filled like any others. Before
each parameter is added, the combinations the must-include cases already
hold are marked covered, so the algorithm adds only what they leave out.

**Stronger groups.** A request with `stronger` groups, such as
`stronger = [(:a, :b, :c, :d) => 3]`, asks for the union of the base
combinations and each group's combinations. The engine adds the parameters
of the stronger groups first, highest strength first, then the rest by
decreasing number of values. Each required combination is assigned to the
step that adds its last parameter in that order, and one pass of horizontal
and vertical growth covers all of them. Because the combinations of every
group are covered in the same pass, the values chosen for one group are
visible to the next, and a rule that spans two groups is respected.
