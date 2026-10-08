# GND's coverage matrix (greedy_tuples.jl): the combinations that are covered
# and uncovered, as columns of a matrix, and the scores GND reads from it.

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
    remain::Int64
    arity::Array{T, 1}
end


"""
How many tuples have not been covered yet.
"""
function remaining_uncovered(mc::MatrixCoverage)
    mc.remain
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
            if match_cnt == min(max_known, n_way - 1)
                hist[mc.allc[param_idx, col_idx]] += 1
            end
        end
    end
    hist
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
    allc = mc.allc
    # This tests the first `length(entry)` rows, so the matrix may have rows
    # past the entry's, unread.
    n = length(entry)
    checkbounds(entry, 1:n)
    checkbounds(allc, 1:n, 1:mc.remain)
    # Swap each covered tuple with the last uncovered one, in place, working
    # from the end. A swap moves only columns at or after the current one, so
    # each column is tested as it was on entry, and the swaps are the ones the
    # two-pass form made (find every covered column, then swap from the last
    # one down; 2798ecf), which leaves the columns in the same order without
    # a list of the covered ones (plan §5.2).
    for col_idx in mc.remain:-1:1
        # Every value of the tuple is in the entry.
        covered = true
        @inbounds for i in 1:n
            b = allc[i, col_idx]
            if b != 0 && entry[i] != b
                covered = false
                break
            end
        end
        if covered
            last = mc.remain
            for i in axes(allc, 1)
                allc[i, col_idx], allc[i, last] = allc[i, last], allc[i, col_idx]
            end
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
