# These functions represent combinations that are covered and uncovered.
# It is a data structure to facilitate greedy approaches to combination coverage.
using Combinatorics: combinations

###############################################################
# MatrixCoverage
###############################################################

"""
Represents covered tuples using a two-dimensional matrix.
Each row is another tuple to cover. Each column is a parameter.
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
mutable struct MatrixCoverage
    allc
    remain
    arity
end


"""
all_combinations_matrix(arity, n_way)
"""
function all_combinations_matrix(arity, n_way)
    allc = all_combinations(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc, dims = 2) == 0) == 0
    remain = size(allc, 1)
    MatrixCoverage(allc, remain, arity)
end


function remaining_uncovered(mc::MatrixCoverage)
    mc.remain
end


function parameter_cnt(mc::MatrixCoverage)
    length(mc.arity)
end


function combination_histogram(allc, arity)
    width = maximum(arity)
    hist = zeros(Int, length(arity), width)
    for row_idx in 1:size(allc, 1)
        for col_idx in 1:width
            if allc[row_idx, col_idx] > 0
                hist[col_idx, allc[row_idx, col_idx]] += 1
            end
        end
    end
    hist
end


function most_to_cover(allc, row_cnt)
   argmax(vec(sum(allc[1:row_cnt, :] .!= 0, dims = 1)))
end


"""
    coverage_by_parameter(allc::MatrixCoverage)

Given a coverage array and a the number of rows to search,
find how many times a nonzero appears in each column.
"""
function coverage_by_parameter(mc::MatrixCoverage)
    vec(sum(mc.allc[1:mc.remain, :] .!= 0, dims = 1))
end


"""
    coverage_by_value(allc, param_idx)

Given a particular parameter, look at that column of the coverage matrix
and return a histogram of how many times each value appears in
that column.
"""
function coverage_by_value(mc, param_idx)
    hist = zeros(Int, mc.arity[param_idx] + 1)
    for row_idx in 1:mc.remain
        hist[mc.allc[row_idx, param_idx] + 1] += 1
    end
    hist[2:end]
end


function most_common_value(allc, row_cnt, arity, param_idx)
    hist = zeros(Int, arity[param_idx] + 1)
    for row_idx in 1:row_cnt
        hist[allc[row_idx, param_idx] + 1] += 1
    end
    argmax(hist[2:end])
end


"""
    most_matches_existing(mc::MatrixCoverage, existing, param_idx)

There is a coverage array, and there is a list of existing choices for the
values of parameters. This asks, given another parameter, how many matches
would each of its values produce, were it chosen. The return value is a
vector where the first entry is the number of matches for value = 1, the second
entry is number of matches for value = 2, and so on.
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
    for row_idx in 1:mc.remain
        # The given parameter column is part of this match.
        if mc.allc[row_idx, param_idx] != 0
            match_cnt = 0
            n_way = 0
            for match_idx in 1:param_cnt
                if mc.allc[row_idx, match_idx] != 0
                    n_way += 1
                end
                if existing[match_idx] != 0 && mc.allc[row_idx, match_idx] == existing[match_idx]
                    match_cnt += 1
                end
            end
            if match_cnt == min(max_known, n_way)
                hist[mc.allc[row_idx, param_idx]] += 1
            end
        end
    end
    hist
end

function coverage_by_tuple(trials, n_way)
    accumulated = tuples_in_trials(trials, n_way)
    sum([length(aset) for aset in values(accumulated)])
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
    for row_idx in 1:mc.remain
        match_cnt = 0
        n_way = 0
        for match_idx in 1:param_cnt
            if mc.allc[row_idx, match_idx] != 0
                n_way += 1
            end
            if mc.allc[row_idx, match_idx] == entry[match_idx]
                match_cnt += 1
            end
        end
        if match_cnt == n_way
            cover_cnt += 1
            covers[cover_cnt] = row_idx
        end
    end
    # Given the matches, we can swap them to the end of the matrix.
    # Work from the end in case a match is near row_cnt.
    for cover_idx in cover_cnt:-1:1
        if mc.remain > 1
            save = mc.allc[mc.remain, :]
            mc.allc[mc.remain, :] = mc.allc[covers[cover_idx], :]
            mc.allc[covers[cover_idx], :] = save
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
paramter values. Returns an integer number of newly-covered tuples.

This is a place to look into alternative algorithms. We could weight
the match score by increasing the score for greater wayness.
"""
function match_score(mc::MatrixCoverage, entry)
    param_cnt = length(entry)
    cover_cnt = 0
    for row_idx in 1:mc.remain
        param_match_cnt = 0
        n_way = 0
        for match_idx in 1:param_cnt
            if mc.allc[row_idx, match_idx] == entry[match_idx]
                param_match_cnt += 1
            end
            if mc.allc[row_idx, match_idx] != 0
                n_way += 1
            end
        end
        if param_match_cnt == n_way
            cover_cnt += 1
        end
    end
    cover_cnt
end


function remove_combinations!(mc::MatrixCoverage, disallow)
    allow_cnt = 0
    allowed = zeros(Int, size(mc.allc, 1))
    for i in 1:size(mc.allc, 1)
        if !disallow(mc.allc[i, :])
            allow_cnt += 1
            allowed[allow_cnt] = i
        # else disallowed
        end
    end
    mc.allc = mc.allc[allowed[1:allow_cnt], :]
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
    order_combos = Any[]
    for order in orders
        # The parameter set is a list of parameter indices.
        for param_set in wayness[order]
            high_combos = all_combinations(arity[param_set], order)
            widened = zeros(Int, size(high_combos, 1), param_cnt)
            widened[:, param_set] = high_combos
            push!(order_combos, widened)
        end
        # We could remove duplicates of higher orders.
    end
    push!(order_combos, all_combinations(arity, base_wayness))
    vcat(order_combos...)
end



#####################################################
# Set-based coverage.
#####################################################


"""
    tuples_in_trials(trials, n_way)

Find the number of distinct tuples in a set of trials. This uses a different method
to count and store those tuples, as a check on other methods. It returns a dictionary
where each key is the index of non-zero parameters and the value is the set of all
ways those values appear.
"""
function tuples_in_trials(trials, n_way)
    param_cnt = length(trials[1])
    param_combo = [Tuple(x) for x in combinations(1:param_cnt, n_way)]
    # The dictionary with keys = parameter indices and dictionary
    # value is set of tuples of parameter values.
    seen = Dict(x => Set{NTuple{n_way,Int}}() for x in param_combo)
    for trial_idx in 1:length(trials)
        entry = trials[trial_idx]
        for params in param_combo
            push!(seen[params], Tuple(entry[[x for x in params]]))
        end
    end
    seen
end
