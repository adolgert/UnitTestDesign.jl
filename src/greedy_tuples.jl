using Combinatorics: combinations
using Random

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
    allc = all_combinations_matrix(arity, n_way)
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remaining_uncovered(allc) > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        for trial_idx in 1:M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(
                        allc, entry, params[p_idx]
                        )
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            score = match_score(allc, entry)
            trial_scores[trial_idx] = score
            trials[trial_idx, :] = entry
        end
        chosen_idx = argmin_rand(rng, -trial_scores)
        maximum_score = trial_scores[chosen_idx]
        if maximum_score > 0
            chosen_trial = trials[chosen_idx, :]
            remain = add_coverage!(allc, chosen_trial)
            push!(coverage, chosen_trial)
        end  # nothing was covered, but this can happen
        loop_idx += 1
    end
    coverage
end



function n_way_coverage_init(arity, n_way, seed, M, rng)
    param_cnt = length(arity)
    allc = all_combinations_matrix(arity, n_way)
    # Every combination is nonzero.
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        remain = add_coverage!(allc, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    exhausted_by_filter = false
    loop_idx = 1
    while remaining_uncovered(allc) > 0 || exhausted_by_filter
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        for trial_idx in 1:M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            score = match_score(allc, entry)
            trial_scores[trial_idx] = score
            trials[trial_idx, :] = entry
        end
        chosen_idx = argmin_rand(rng, -trial_scores)
        maximum_score = trial_scores[chosen_idx]
        if maximum_score > 0
            chosen_trial = trials[chosen_idx, :]
            remain = add_coverage!(allc, chosen_trial)
            push!(coverage, chosen_trial)
        else
            exhausted_by_filter = true
        end
        loop_idx += 1
    end
    coverage
end


function arguments_to_arity(arguments)
    [length(x) for x in arguments]
end


function indices_to_arguments(arguments, indices)
    Tuple(arguments[i[1]][i[2]] for i in zip(1:length(indices), indices))
end


function n_way_coverage_filter(arity, n_way, disallow, seed, M, rng)
    param_cnt = length(arity)
    allc = all_combinations_matrix(arity, n_way)
    # Every combination is nonzero.
    @assert sum(sum(allc.allc, dims = 2) == 0) == 0
    before_disallow = size(allc.allc, 1)
    remove_combinations!(allc, disallow)
    maximum_match_score = combination_number(param_cnt, n_way)
    param_cnt = length(arity)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        remain = add_coverage!(allc, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remaining_uncovered(allc) > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        trial_cnt = 0
        while trial_cnt < M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            if !disallow(entry)
                trial_cnt += 1
                score = match_score(allc, entry)
                trial_scores[trial_cnt] = score
                trials[trial_cnt, :] = entry
            end
        end
        chosen_idx = argmin_rand(rng, -trial_scores[1:trial_cnt])
        chosen_trial = trials[chosen_idx, :]
        maximum_score = trial_scores[chosen_idx]
        if 0 < maximum_score
            remain = add_coverage!(allc, chosen_trial)
            push!(coverage, chosen_trial)
        # else Failure to cover can happen for a bad draw in the shuffle.
        end
        loop_idx += 1
    end
    coverage
end



function n_way_coverage_multi(allc, disallow, seed, M, rng)
    param_cnt = parameter_cnt(allc)
    remove_combinations!(allc, disallow)

    # Array of arrays.
    coverage = Array{Array{Int64,1},1}()

    # Don't save the seeds to the coverage array because the user knows
    # what they are.
    for seed_idx in 1:size(seed, 1)
        add_coverage!(allc, seed[seed_idx, :])
    end

    trials = zeros(Int, M, param_cnt)
    trial_scores = zeros(Int, M)
    params = zeros(Int, param_cnt)
    entry = zeros(Int, param_cnt)
    
    loop_idx = 1
    while remaining_uncovered(allc) > 0
        params[:] = 1:param_cnt
        param_coverage = coverage_by_parameter(allc)
        params[1] = argmin_rand(rng, -param_coverage)
        params[params[1]] = 1
        trial_cnt = 0
        while trial_cnt < M
            params[2:end] = shuffle(rng, params[2:end])
            entry[:] .= 0
            candidate_params = coverage_by_value(allc, params[1])
            entry[params[1]] = argmin_rand(rng, -candidate_params)
            for p_idx in 2:param_cnt
                candidate_values = most_matches_existing(allc, entry, params[p_idx])
                entry[params[p_idx]] = argmin_rand(rng, -candidate_values)
            end
            if !disallow(entry)
                trial_cnt += 1
                score = match_score(allc, entry)
                trial_scores[trial_cnt] = score
                trials[trial_cnt, :] = entry
            end
        end
        chosen_idx = argmin_rand(rng, -trial_scores[1:trial_cnt])
        chosen_trial = trials[chosen_idx, :]
        maximum_score = trial_scores[chosen_idx]
        if 0 < maximum_score
            add_coverage!(allc, chosen_trial)
            push!(coverage, chosen_trial)
        # else Failure to cover can happen for a bad draw in the shuffle.
        end
        loop_idx += 1
    end
    coverage
end
