# In-parameter-order General

## Overview

There is a published in-parameter-order general (IPOG) algorithm, and this
package extends it to handle what real tests need: rules, must-include
cases, and stronger coverage for some parameters. This page describes the
algorithm, the way the package finds the best value for a case quickly, and
the extensions. [Engines](engines.md) compares IPOG with the package's other
engines.

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
them appear together in some case. A set of ``t`` parameters is a
*support*; each support has one combination for each choice of its values.

## IPOG

Earlier algorithms built one complete case at a time. IPOG instead starts
with a few parameters, covers them completely, and then adds one parameter
at a time, extending the cases it already has.

There are a few sources for this work, annotated here.

 * Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing.” Software Testing, Verification & Reliability 18 (3): 125–48. - This is the most direct description.

 * Forbes, Michael, Jim Lawrence, Yu Lei, Raghu N. Kacker, and D. Richard Kuhn. 2008. “Refining the In-Parameter-Order Strategy for Constructing Covering Arrays.” Journal of Research of the National Institute of Standards and Technology 113 (5): 287–97. - This updates the algorithm to be more efficient and includes details not explained elsewhere, such as what to do with the blanks a case still has.

 * Kleine, Kristoffer, and Dimitris E. Simos. 2018. “An Efficient Design and Implementation of the In-Parameter-Order Algorithm.” Mathematics in Computer Science 12 (1): 51–67. - FIPOG, the layout of the coverage map that lets each case's best value be found by lookup, which this package follows.

 * Wagner, Michael, Kristoffer Kleine, Dimitris E. Simos, Rick Kuhn, and Raghu Kacker. 2020. “CAGEN: A Fast Combinatorial Test Generation Tool with Support for Constraints and Higher-Index Arrays.” IEEE International Conference on Software Testing, Verification and Validation Workshops (ICSTW), 191–200. - The tool built on FIPOG, which keeps the map only for the parameter being added.

 * Tai, Kuo-Chung, and Yu Lei. 2002. “A Test Generation Strategy for Pairwise Testing.” IEEE Transactions on Software Engineering 28 (1). - The original paper is interesting because it thinks more theoretically about the problem.

 * Kuhn, D. Richard, Raghu N. Kacker, and Yu Lei. 2013. Introduction to Combinatorial Testing. CRC Press. This book includes an algorithm description, but it may mix up one of the loops.

A sketch of the algorithm:

1. Given:

   * the number of values of each parameter, which the algorithm calls its
     arity;
   * the strength ``t`` (2, 3, ...).

2. Choose the order in which to add the parameters: by decreasing number of
   values. The cases keep the parameters in their own order; only the order
   of adding them changes.

3. Start with no cases. The first parameters only make combinations to
   place, which is how the full factorial of the first ``t`` parameters
   arises.

4. Add the next parameter to each case found so far. This is called
   *horizontal growth*, or widening, and is described below.

5. Every combination whose last parameter, in the order of step 2, is the
   one being added and which no case holds yet goes into the first case
   where it fits. If there is none, a new case holds just that combination,
   with the other parameters marked missing. This is *vertical growth*.

6. Repeat for each remaining parameter.

7. Fill the missing values.

Horizontal growth loops over the existing cases, which have no value yet for
the new parameter, and gives each the value that covers the most new
combinations. If no value would add coverage, the entry stays blank, because
a later step might use that spot. Blanks are written as 0.

Vertical growth, which adds cases, does not loop over cases. It loops over
the uncovered combinations, which is much more efficient. For each
combination it looks for a case where the combination fits, and otherwise
appends a new case, using 0 for missing values. The final fill gives each
blank the value of its parameter that the design has used least.

## Finding the best value by lookup

The step that costs the most is horizontal growth: for each case and each
value of the new parameter, how many uncovered combinations would the case
then hold? A direct implementation scans every uncovered combination of the
step for every case. Kleine and Simos's FIPOG replaces the scan with a
lookup, and the package does the same.

While parameter ``p`` is added, the engine keeps a map of the step's
combinations only: those of the supports whose last parameter is ``p``. Each
support's combinations form a block, numbered with ``p`` as the least
significant digit, so the combinations that one case would make with each
value of ``p`` are adjacent entries. For a case, the engine computes the
start of that run once per support, from the case's other values, and adds
up the uncovered entries of each run, one per value of ``p``. A support whose
combinations are all covered is skipped. When the step ends, its map is
discarded, as CAgen does, so the engine holds one step's combinations at a
time.

A case may still have blanks on the other parameters of a support. Such a
support scores nothing for that case: the blank's potential is ignored in
horizontal growth and used in vertical growth, as Forbes et al. recommend.
The engines this one replaced instead counted a combination when the case
agreed with it on at least one value, one of several ways to say that a
combination matches a partial case. Here are the five possibilities for one
parameter of a case `a` and a combination `b`:

```julia
ignores(a, b) = a == 0 && b == 0
skips(a, b) = a != 0 && b == 0
misses(a, b) = a == 0 && b != 0
matches(a, b) = a != 0 && b != 0 && a == b
mismatch(a, b) = a != 0 && b != 0 && a != b
```

Ignoring the blanks, so that only supports the case sets in full score, is
both FIPOG's choice and the one that made smaller designs over the
package's benchmark spaces.

Vertical growth splits the candidate cases by their value of ``p``: a
combination with value ``v`` can go only to a case that has ``v`` or a blank
there, which FIPOG reports gave a sixfold speed-up with 60 values. Only
cases with a blank among the parameters added so far are candidates. Before
the combinations of a support are placed, the cases that vertical growth has
changed so far mark what they now hold on that support, so that no
combination is placed twice (Forbes et al.: "it is important to capture the
unintended coverage").

## A family of designs, and keeping the smallest

Wherever two values cover the same number of new combinations, horizontal
growth has to choose one, and vertical growth has to place the uncovered
combinations in some order. Each choice of these rules gives another member
of the IPOG family, and their designs differ by a few percent either way,
sometimes much more, with no member best everywhere. The package's engine
has two tie-break rules, the lowest value and a value that rotates with the
case, and two orders of vertical growth, support by support and value by
value. `IPOG()` runs all four combinations on the same steps and keeps the
design with the fewest cases, the first of equals. It stops at a design no
design can beat: as many cases as its must-include rows, or as one set of
parameters has combinations to cover. The result's record says which
member made the cases, in `record.ordinary.member`:

```jldoctest; setup = :(using UnitTestDesign)
julia> all_pairs((a = 1:3, b = 1:3, c = 1:2, d = 1:2)).record.ordinary
(engine = "IPOG()", rows = 9, member = (tiebreak = :rotate, vertical = :support))
```

Over the package's benchmark spaces, the four together have no more cases
than the engines this one replaced on 96.7% of them, and 2% fewer cases in
total, but more on about 3%, by up to about 9%; any one member alone has
more than they did on a fifth to nearly a third of them.

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
as follows. The same engine handles every request, with or without them.

**Rules.** Before generating, every combination is classified: a
combination is required only when some valid case contains it, and the
others are reported as excluded ([Constraints](../explain/constraints.md)).
The map of each step marks only the required combinations. Then, at each of
the three steps that set values (horizontal growth, placing a combination
during vertical growth, and the final fill), the engine sets a value only
when the partial case can still be completed into a valid case. A new case
starts from one required combination, which is completable by definition,
and every later assignment keeps it completable. So the algorithm never
reaches a dead end, and the final fill always finds a value. Deciding
whether a partial case can be completed is a backtracking search over the
rules, bounded by `feasibility_limit`. The engine depends on the rules only
through those answers, so a rule that excludes nothing leaves the design as
it was without it.

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

## Determinism

IPOG uses no randomness. Its rules break every tie by a fixed order, it
reads the combinations in order, and it keeps the first of the members with
the fewest cases, so the same request gives the same cases in every run and
every process, for the same package version and the same Julia version
(contract §9.1). A larger `feasibility_limit` never changes the cases of a
call that succeeded, since the engine decides only from the searches'
answers. Each design `IPOG()` builds asks its own searches, and the call
succeeds only when the limit is enough for every one of them, so a call can
need a larger limit than a single design would: of 150 random problems with
rules, tried at limits that are powers of two, one needed 16 where the
engines before needed 4. The cases may change between package versions
(§9.8), as they did when this engine replaced the two before it, the
classic algorithm and a general one for rules, must-include cases and
stronger groups.
