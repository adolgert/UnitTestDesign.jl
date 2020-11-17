using Combinatorics: combinations
using Random


"""
    total_combinations(arity, n_way)

Given an array of the number of values for each parameter and the
level of coverage, return the number of n-tuples required for complete
coverage.
"""
function total_combinations(arity, n_way)
    param_cnt = length(arity)
    sum(prod(arity[key_set]) for key_set in combinations(1:param_cnt, n_way))
end


"""
    next_multiplicative!(values, arity)

Given a set of values for parameters, this returns the next possible
value. When it reaches the end, it cycles back to the start. The first
value is all ones. The last value equals the arity.
"""
function next_multiplicative!(values, arity)
    carry = 1
    for slot_idx in length(values):-1:1
        values[slot_idx] += carry
        if arity[slot_idx] < values[slot_idx]
            values[slot_idx] = 1
            carry = 1
        else
            carry = 0
        end
    end
end

"""
    all_combinations(arity, n_way)

This represents possible coverage as a matrix, one column per parameter,
zero if not used. `arity` is a list of the number of values for each parameter,
and `n_way` is the order of the combinations, most commonly 2-way.
"""
function all_combinations(arity, n_way)
    v_cnt = length(arity)
    indices = collect(combinations(1:v_cnt, n_way))
    combinations_cnt = total_combinations(arity, n_way)

    coverage = zeros(Int, combinations_cnt, v_cnt)
    idx = 1
    for indices_idx in 1:size(indices, 1)
        offset = indices[indices_idx]
        sub_arity = arity[offset]
        sub_cnt = prod(sub_arity)
        values = copy(sub_arity)
        for sub_idx in 1:sub_cnt
            next_multiplicative!(values, sub_arity)
            coverage[idx, offset] = values
            idx += 1
        end
    end
    coverage
end


"""
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
    coverage_by_parameter(allc, row_cnt)

Given a coverage array and a the number of rows to search,
find how many times a nonzero appears in each column.
"""
function coverage_by_parameter(allc, row_cnt)
    vec(sum(allc[1:row_cnt, :] .!= 0, dims = 1))
end


"""
    coverage_by_value(allc, row_cnt, arity, param_idx)

Given a particular parameter, look at that column of the coverage matrix
and return a histogram of how many times each value appears in
that column.
"""
function coverage_by_value(allc, row_cnt, arity, param_idx)
    hist = zeros(Int, arity[param_idx] + 1)
    for row_idx in 1:row_cnt
        hist[allc[row_idx, param_idx] + 1] += 1
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
    most_matches_existing(allc, row_cnt, arity, existing, param_idx)

There is a coverage array, and there is a list of existing choices for the
values of parameters. This asks, given another parameter, how many matches
would each of its values produce, were it chosen. The return value is a
vector where the first entry is the number of matches for value = 1, the second
entry is number of matches for value = 2, and so on.
"""
function most_matches_existing(allc, row_cnt, arity, existing, param_idx)
    @assert existing[param_idx] == 0
    param_cnt = length(arity)
    # The match count can only be as large as n_way - 1 because the
    # column with the parameter is non-zero and will be zero in existing.
    # If n-way is 3 and we only know one parameter so far, that's another limit
    # to the possible match size.
    max_known = sum(existing .!= 0)
    # params_known = min(sum(existing .!= 0), n_way - 1)
    hist = zeros(Int, arity[param_idx])
    for row_idx in 1:row_cnt
        # The given parameter column is part of this match.
        if allc[row_idx, param_idx] != 0
            match_cnt = 0
            n_way = 0
            for match_idx in 1:param_cnt
                if allc[row_idx, match_idx] != 0
                    n_way += 1
                end
                if existing[match_idx] != 0 && allc[row_idx, match_idx] == existing[match_idx]
                    match_cnt += 1
                end
            end
            if match_cnt == min(max_known, n_way)
                hist[allc[row_idx, param_idx]] += 1
            end
        end
    end
    hist
end


combination_number(n, m) = prod(n:-1:(n-m+1)) ÷ factorial(m)


function pairs_in_entry(entry, n_way)
    n = length(entry)
    ans = zeros(Int, combination_number(n, n_way), n)
    row_idx = 1
    for param_idx in combinations(1:length(entry), n_way)
        for col_idx in 1:n_way
            ans[row_idx, param_idx[col_idx]] = entry[param_idx[col_idx]]
        end
        row_idx += 1
    end
    ans
end


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


function coverage_by_tuple(trials, n_way)
    accumulated = tuples_in_trials(trials, n_way)
    sum([length(aset) for aset in values(accumulated)])
end


"""
    add_coverage!(allc, row_cnt, entry)

The coverage matrix, `allc`, has `row_cnt` entries that are considered
uncovered, and the rest have been covered already. This adds a new entry,
which is a complete set of parameter choices. For every parameter that's
covered, this moves those to the end. It returns a new `row_cnt` which is
the number of initial uncovered rows.
"""
function add_coverage!(allc, row_cnt, entry)
    param_cnt = length(entry)

    covers = zeros(Int, row_cnt)
    cover_cnt = 0
    # Find matches before reordering them to the end.
    for row_idx in 1:row_cnt
        match_cnt = 0
        n_way = 0
        for match_idx in 1:param_cnt
            if allc[row_idx, match_idx] != 0
                n_way += 1
            end
            if allc[row_idx, match_idx] == entry[match_idx]
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
        if row_cnt > 1
            save = allc[row_cnt, :]
            allc[row_cnt, :] = allc[covers[cover_idx], :]
            allc[covers[cover_idx], :] = save
            row_cnt -= 1
        else
            row_cnt -= 1
        end
    end
    row_cnt
end


"""
    match_score(allc, row_cnt, entry)

If we were to add this entry to the trials, how many uncovered
n-tuples would it now cover? `allc` is the matrix of n-tuples.
`row_cnt` is the first set of rows, representing uncovered tuples.
`n_way` is the length of each tuple. Entry is a set of putative
paramter values. Returns an integer number of newly-covered tuples.

This is a place to look into alternative algorithms. We could weight
the match score by increasing the score for greater wayness.
"""
function match_score(allc, row_cnt, entry)
    param_cnt = length(entry)
    cover_cnt = 0
    for row_idx in 1:row_cnt
        param_match_cnt = 0
        n_way = 0
        for match_idx in 1:param_cnt
            if allc[row_idx, match_idx] == entry[match_idx]
                param_match_cnt += 1
            end
            if allc[row_idx, match_idx] != 0
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
    argmin_rand(rng, v)

Given a vector, find the index of the smallest value. If more than
one value is the smallest, then randomly choose among the smallest
values.
"""
function argmin_rand(rng, v)
    small = typemax(v[1])
    small_extra_cnt = 0
    small_idx = -1
    for i in 1:length(v)
        if v[i] < small
            small = v[i]
            small_extra_cnt = 0
            small_idx = i
        elseif v[i] == small
            small_extra_cnt += 1
        # else not the smallest.
        end
    end
    if small_extra_cnt == 0
        return small_idx
    else
        which = rand(rng, 1:(small_extra_cnt + 1))
        which_cnt = 1
        for s_idx in small_idx:length(v)
            if v[s_idx] == small
                if which_cnt == which
                    return s_idx
                end
                which_cnt += 1
            end
        end
    end
    return 0
end


function n_way_coverage(arity, n_way, M, rng)
    param_cnt = length(arity)
    allc = all_combinations(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc, dims = 2) == 0) == 0
    remain = size(allc, 1)
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remain > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc, remain)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        for trial_idx in 1:M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, remain, arity, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, remain, arity, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            score = match_score(allc, remain, entry)
            trial_scores[trial_idx] = score
            trials[trial_idx, :] = entry
        end
        chosen_idx = argmin_rand(rng, -trial_scores)
        maximum_score = trial_scores[chosen_idx]
        if maximum_score > 0
            chosen_trial = trials[chosen_idx, :]
            remain = add_coverage!(allc, remain, chosen_trial)
            push!(coverage, chosen_trial)
        else
            println("error because nothing was covered")
        end
        loop_idx += 1
    end
    coverage
end



function n_way_coverage_init(arity, n_way, seed, M, rng)
    param_cnt = length(arity)
    allc = all_combinations(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc, dims = 2) == 0) == 0
    remain = size(allc, 1)
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        remain = add_coverage!(allc, remain, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    exhausted_by_filter = false
    loop_idx = 1
    while remain > 0 || exhausted_by_filter
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc, remain)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        for trial_idx in 1:M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, remain, arity, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, remain, arity, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            score = match_score(allc, remain, entry)
            trial_scores[trial_idx] = score
            trials[trial_idx, :] = entry
        end
        chosen_idx = argmin_rand(rng, -trial_scores)
        maximum_score = trial_scores[chosen_idx]
        if maximum_score > 0
            chosen_trial = trials[chosen_idx, :]
            remain = add_coverage!(allc, remain, chosen_trial)
            push!(coverage, chosen_trial)
        else
            exhausted_by_filter = true
        end
        loop_idx += 1
    end
    coverage
end


function remove_combinations(allc, disallow)
    allow_cnt = 0
    allowed = zeros(Int, size(allc, 1))
    for i in 1:size(allc, 1)
        if !disallow(allc[i, :])
            allow_cnt += 1
            allowed[allow_cnt] = i
        # else disallowed
        end
    end
    allc[allowed[1:allow_cnt], :]
end


function arguments_to_arity(arguments)
    [length(x) for x in arguments]
end


function indices_to_arguments(arguments, indices)
    Tuple(arguments[i[1]][i[2]] for i in zip(1:length(indices), indices))
end


function n_way_coverage_filter(arity, n_way, disallow, seed, M, rng)
    param_cnt = length(arity)
    allc = all_combinations(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc, dims = 2) == 0) == 0
    before_disallow = size(allc, 1)
    allc = remove_combinations(allc, disallow)
    remain = size(allc, 1)
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        remain = add_coverage!(allc, remain, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remain > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc, remain)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        trial_cnt = 0
        while trial_cnt < M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, remain, arity, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, remain, arity, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            if !disallow(entry)
                trial_cnt += 1
                score = match_score(allc, remain, entry)
                trial_scores[trial_cnt] = score
                trials[trial_cnt, :] = entry
            end
        end
        chosen_idx = argmin_rand(rng, -trial_scores[1:trial_cnt])
        chosen_trial = trials[chosen_idx, :]
        maximum_score = trial_scores[chosen_idx]
        if 0 < maximum_score
            remain = add_coverage!(allc, remain, chosen_trial)
            push!(coverage, chosen_trial)
        # else Failure to cover can happen for a bad draw in the shuffle.
        end
        loop_idx += 1
    end
    coverage
end



function n_way_coverage_multi(arity, allc, disallow, seed, M, rng)
    param_cnt = length(arity)
    remain = size(allc, 1)
    before_disallow = size(allc, 1)
    allc = remove_combinations(allc, disallow)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        remain = add_coverage!(allc, remain, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remain > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc, remain)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        trial_cnt = 0
        while trial_cnt < M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, remain, arity, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, remain, arity, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            if !disallow(entry)
                trial_cnt += 1
                score = match_score(allc, remain, entry)
                trial_scores[trial_cnt] = score
                trials[trial_cnt, :] = entry
            end
        end
        chosen_idx = argmin_rand(rng, -trial_scores[1:trial_cnt])
        chosen_trial = trials[chosen_idx, :]
        maximum_score = trial_scores[chosen_idx]
        if 0 < maximum_score
            remain = add_coverage!(allc, remain, chosen_trial)
            push!(coverage, chosen_trial)
        # else Failure to cover can happen for a bad draw in the shuffle.
        end
        loop_idx += 1
    end
    coverage
end
