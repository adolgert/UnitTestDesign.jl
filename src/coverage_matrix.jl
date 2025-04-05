# These functions represent combinations that are covered and uncovered.
# It is a data structure to facilitate greedy approaches to combination coverage.
using Combinatorics: combinations
import Base: eltype

###############################################################
# MatrixCoverage
###############################################################

"""
Represents covered tuples using a two-dimensional matrix.
Each column is another tuple to cover. Each row is a parameter.
A zero means this parameter is not part of the tuple.
The initial matrix represents all tuples to cover.
The `remain` integer is the number of tuples left to cover.
As tuples are covered, they are swapped to the end of the
uncovered tuples, and the `remain` value is decremented.

The arity is an integer array, the same length as the number of
parameters. Each member of the array is the number of possible
values each parameter can take.

This representation should be slow for lookup of tuples and
take lots of memory, but it is a clear representation with which
to understand the interface to the data structure.
"""
mutable struct MatrixCoverage{T <: Integer}
    allc::Array{T, 2}
    remain::T
    arity::Array{T, 1}
end


"""
The element type of the MatrixCoverage class is determined
by the element type of the arity because an element large
enough to hold the arity is what defines the minimum possible
element type.
"""
eltype(mc::MatrixCoverage) = eltype(mc.arity)


"""
all_combinations_matrix(arity, n_way)

Create matrix coverage that includes all n-way combinations
of parameters which can take `arity` values, where `arity`
is a vector of integers to represent the number of possible
values for each parameter, in order.
"""
function all_combinations_matrix(arity, n_way)
    allc = all_combinations(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc, dims = 1) == 0) == 0
    remain = size(allc, 2)
    MatrixCoverage(allc, convert(eltype(arity), remain), arity)
end


"""
    one_parameter_combinations(arity, n_way)

Generates all combinations that are nonzero for the last parameter.
This is for in-parameter-order generation, where we need
only those tuples that end with this column being nonzero.

The construction method is to leave out the given parameter
and construct all `n_way` - 1 tuples. Then copy and paste that
once for each possible value of the given parameter.
"""
function one_parameter_combinations_matrix(arity, n_way)
    comb = one_parameter_combinations(arity, n_way)
    MatrixCoverage(comb, convert(eltype(arity), size(comb, 2)), arity)
end


"""
How many tuples have not been covered yet.
"""
function remaining_uncovered(mc::MatrixCoverage)
    mc.remain
end


"""
The number of parameters for this design.
"""
function parameter_cnt(mc::MatrixCoverage)
    length(mc.arity)
end


function combination_histogram(allc, arity)
    height = maximum(arity)
    hist = zeros(Int, height, length(arity))
    for colh_idx in axes(allc, 2)
        for rowh_idx in 1:height
            if allc[rowh_idx, colh_idx] > 0
                hist[allc[rowh_idx, colh_idx], rowh_idx] += 1
            end
        end
    end
    hist
end


function most_to_cover(allc, col_cnt)
   argmax(vec(sum(allc[:, 1:col_cnt] .!= 0, dims = 2)))
end


"""
    coverage_by_parameter(allc::MatrixCoverage)

Given a coverage matrix, return how many times each parameter
participates in an uncovered tuple. The return value is a vector
of integers, where each value is the number of times that parameter
appears in any uncovered tuple.
"""
function coverage_by_parameter(mc::MatrixCoverage)
    vec(sum(mc.allc[:, 1:mc.remain] .!= 0, dims = 2))
end


"""
    coverage_by_value(allc, param_idx)

Given a particular parameter, look at that column of the coverage matrix
and return a histogram of how many times each value appears in
that column. We want to know which parameter has the most tuples
to cover so that we can address it first.
"""
function coverage_by_value(mc, param_idx)
    hist = zeros(Int, mc.arity[param_idx] + 1)
    for col_idx in 1:mc.remain
        hist[mc.allc[param_idx, col_idx] + 1] += 1
    end
    hist[2:end]
end


function most_common_value(allc, col_cnt, arity, param_idx)
    hist = zeros(Int, arity[param_idx] + 1)
    for col_idx in 1:col_cnt
        hist[allc[param_idx, col_idx] + 1] += 1
    end
    argmax(hist[2:end])
end


"""
    most_matches_existing(mc::MatrixCoverage, existing, param_idx)

The `existing` vector is a partial test case. Each nonzero entry in this
test case is considered as decided. This function then determines, for
the next parameter, chosen by param_idx, which value of param_idx, between
1 and its arity, would cover the most tuples. It returns a histogram of
how many uncovered tuples could be covered, given the existing choices
and a particular value of this parameter.

This returns all tuples that the existing case could _exactly_ cover
if it didn't have missing values. That means the existing vector
either has the same number of entries as the tuple or it has
fewer entries than the tuple.

A value of the `param_idx` parameter matches with a tuple if its
existing choices match at least some part of the tuple and don't
disagree with any part of the tuple.
"""
function most_matches_existing(mc::MatrixCoverage, existing, param_idx)
    @assert existing[param_idx] == 0
    param_cnt = length(mc.arity)
    # The match count can only be as large as n_way - 1 because the
    # column with the parameter is non-zero and will be zero in existing.
    # If n-way is 3 and we only know one parameter so far, that's another limit
    # to the possible match size.
    max_known = sum(existing .!= 0)
    # params_known = min(sum(existing .!= 0), n_way - 1)
    hist = zeros(Int, mc.arity[param_idx])
    for col_idx in 1:mc.remain
        # The given parameter column is part of this match.
        if mc.allc[param_idx, col_idx] != 0
            match_cnt = 0
            n_way = 0
            for match_idx in 1:param_cnt
                if mc.allc[match_idx, col_idx] != 0
                    n_way += 1
                end
                if existing[match_idx] != 0 && mc.allc[match_idx, col_idx] == existing[match_idx]
                    match_cnt += 1
                end
            end
            if match_cnt == min(max_known, n_way)
                hist[mc.allc[param_idx, col_idx]] += 1
            end
        end
    end
    hist
end

"""
The logic of tuple comparison is oddly complicated.
We're going to write this out the first round in order to know
what our tools are.

If you take a case and a tuple to cover, then there are
five states for any pair of values:
               case tuple
    ignores    0    0
    skips      a    0
    misses     0    b
    matches    a == b
    mismatch   a != b

It's always one of those five. In this language,

covers = all(matches | irrelevant)
"""

ignores(a, b) = a == 0 && b == 0
skips(a, b) = a != 0 && b == 0
misses(a, b) = a == 0 && b != 0
matches(a, b) = a != 0 && b != 0 && a == b
mismatch(a, b) = a != 0 && b != 0 && a != b

"""
Example matches.
      crossed      incomplete cover
case  [0 1 0 2]    [1 0 0 3]  [1 1 0 2]
tuple [1 0 3 0]    [1 1 0 3]  [1 0 0 2]
"""
function case_compatible_with_tuple(case, tuple)
    !any(mismatch(a, b) for (a, b) in zip(case, tuple))
end


"""
Example matches.
      incomplete cover
case  [1 0 0 3]  [1 1 0 2]
tuple [1 1 0 3]  [1 0 0 2]
"""
function case_partial_cover(case, tuple)
    (sum(matches(a, b) for (a, b) in zip(case, tuple)) > 0 &&
     !any(mismatch(a, b) for (a, b) in zip(case, tuple)))
end


"""
Example matches.
case  [1 1 0 2]
tuple [1 0 0 2]
"""
function case_covers_tuple(case, tuple)
    all(matches(a, b) || skips(a, b) || ignores(a, b) for (a, b) in zip(case, tuple))
end


"""
Given an entry in the test set that has missing values, which are
zeros, find any matches that could be created by setting those
missing values. Return a new version of the entry.
"""
function matches_from_missing(mc::MatrixCoverage, entry, missing_param, matcher = case_compatible_with_tuple)
    param_cnt = parameter_cnt(mc)
    hist = zeros(eltype(mc), mc.arity[missing_param])
    for tuple_idx in 1:mc.remain
        if mc.allc[missing_param, tuple_idx] != 0
            # case_covers_tuple - variation.
            if matcher(entry, mc.allc[:, tuple_idx])
                hist[mc.allc[missing_param, tuple_idx]] += 1
            end
        end  # No matches unless the particular column is nonzero.
    end
    hist
end


"""
    first_match_for_parameter(mc::MatrixCoverage, param_idx)

Find the first uncovered tuple for a particular parameter value.
"""
function first_match_for_parameter(mc::MatrixCoverage, param_idx)
    for col_idx in 1:mc.remain
        if mc.allc[param_idx, col_idx] != 0
            return mc.allc[:, col_idx]
        end  # else keep looking
    end
    return zeros(eltype(mc), length(mc.arity))
end


"""
    fill_consistent_matches(mc::MatrixCoverage, entry)

Given an entry that's partially decided, fill in every covering tuple
that matches the existing values, in any order.
"""
function fill_consistent_matches(mc::MatrixCoverage, entry, matcher = case_compatible_with_tuple)
    param_cnt = parameter_cnt(mc)
    for col_idx in 1:mc.remain
        if matcher(entry, mc.allc[:, col_idx])
            for copy_idx in 1:param_cnt
                if mc.allc[copy_idx, col_idx] != 0
                    entry[copy_idx] = mc.allc[copy_idx, col_idx]
                end
            end
        end
    end
    entry
end


"""
    add_coverage!(allc, entry)

The coverage matrix, `allc`, has `row_cnt` entries that are considered
uncovered, and the rest have been covered already. This adds a new entry,
which is a complete set of parameter choices. For every parameter that's
covered, this moves those to the end. It returns a new `row_cnt` which is
the number of initial uncovered rows.
"""
function add_coverage!(mc::MatrixCoverage, entry)
    param_cnt = length(entry)

    covers = zeros(Int, mc.remain)
    cover_cnt = 0
    # Find matches before reordering them to the end.
    for col_idx in 1:mc.remain
        if case_covers_tuple(entry, mc.allc[:, col_idx])
            cover_cnt += 1
            covers[cover_cnt] = col_idx
        end
    end
    # Given the matches, we can swap them to the end of the matrix.
    # Work from the end in case a match is near row_cnt.
    for cover_idx in cover_cnt:-1:1
        if mc.remain > 1
            save = mc.allc[:, mc.remain]
            mc.allc[:, mc.remain] = mc.allc[:, covers[cover_idx]]
            mc.allc[:, covers[cover_idx]] = save
            mc.remain -= 1
        else
            mc.remain -= 1
        end
    end
    mc.remain
end


"""
    match_score(allc, entry)

If we were to add this entry to the trials, how many uncovered
n-tuples would it now cover? `allc` is the matrix of n-tuples.
`row_cnt` is the first set of rows, representing uncovered tuples.
`n_way` is the length of each tuple. Entry is a set of putative
parameter values. Returns an integer number of newly-covered tuples.

This is a place to look into alternative algorithms. We could weight
the match score by increasing the score for greater wayness.
"""
function match_score(mc::MatrixCoverage, entry)
    param_cnt = length(entry)
    cover_cnt = 0
    for col_idx in 1:mc.remain
        param_match_cnt = 0
        n_way = 0
        for match_idx in 1:param_cnt
            if mc.allc[match_idx, col_idx] == entry[match_idx]
                param_match_cnt += 1
            end
            if mc.allc[match_idx, col_idx] != 0
                n_way += 1
            end
        end
        if param_match_cnt == n_way
            cover_cnt += 1
        end
    end
    cover_cnt
end


"""
    remove_combinations!(mc::MatrixCoverage, disallow)

Remove all tuples that are disallowed by the `disallow` function.
Input to the function is a vector of parameter indexes.
The output to the function is whether they are disallowed,
as a boolean. This reduces the size of total tuples in the
coverage matrix. It doesn't move them to covered tuples. It
deletes them.
"""
function remove_combinations!(mc::MatrixCoverage, disallow)
    allow_cnt = 0
    allowed = zeros(Int, size(mc.allc, 2))
    for i in 1:size(mc.allc, 2)
        if !disallow(mc.allc[:, i])
            allow_cnt += 1
            allowed[allow_cnt] = i
        # else disallowed
        end
    end
    mc.allc = mc.allc[:, allowed[1:allow_cnt]]
    mc.remain = allow_cnt
end


"""
Builds a coverage set where subsets of variables have different wayness.

The all-pairs algorithm is 2-way. All-triples is 3-way. This function
takes a `base_wayness`, which would be 2 or 3 for those examples.
Then it takes a dictionary that specifies higher wayness for subsets
of parameters.

The wayness is a dictionary from an integer, the wayness, to a set
of lists of indices that should have that wayness together. The `base_wayness`
is the `n_way` for the rest of the variables. It should be less than
the other sets of waynesses.
"""
function multi_way_coverage(arity, wayness, base_wayness)
    orders = sort(collect(keys(wayness)), rev = true)
    @assert minimum(orders) > base_wayness
    @assert maximum(orders) <= length(arity)

    param_cnt = length(arity)
    order_combos = Vector{Matrix{eltype(arity)}}(undef, 0)
    for order in orders
        # The parameter set is a list of parameter indices.
        for param_set in wayness[order]
            high_combos = all_combinations(arity[param_set], order)
            widened = zeros(eltype(arity), param_cnt, size(high_combos, 2))
            widened[param_set, :] = high_combos
            push!(order_combos, widened)
        end
        # We could remove duplicates of higher orders.
    end
    push!(order_combos, all_combinations(arity, base_wayness))
    return reduce(hcat, order_combos)
end
