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



function coverage_by_tuple(trials, n_way)
    accumulated = tuples_in_trials(trials, n_way)
    sum([length(aset) for aset in values(accumulated)])
end
