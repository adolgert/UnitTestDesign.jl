#####################################################
# Set-based coverage.
#
# This is an example of another data structure to
# support generation of test cases. It's a set of sets
# of the remaining covers.
#####################################################

mutable struct SetCoverage{T <: Integer}
    cover::Dict{Tuple{Vararg{T}},Set{Tuple{Vararg{T}}}}
    arity::Array{T, 1}
end


function SetCoverage(arity::Array{T}, n_way::Integer) where {T <: Integer}
    param_cnt = length(arity)
    param_combo = [Tuple(x) for x in combinations(1:param_cnt, n_way)]
    # The dictionary with keys = parameter indices and dictionary
    # value is set of tuples of parameter values.
    cover = Dict(x => Set{NTuple{n_way,T}}() for x in param_combo)
    SetCoverage{T}(cover, arity)
end


eltype(sc::SetCoverage{T}) where T = T
remaining(sc::SetCoverage) = sum([length(aset) for aset in values(sc.cover)])


function build_all_combinations!(sc::SetCoverage, n_way)
    allc = all_combinations(sc.arity, n_way)
    param_cnt = size(allc, 1)
    for cover_idx in 1:size(allc, 2)
        acover = allc[:, cover_idx]
        nonzero = acover .!= 0
        indices = tuple((1:param_cnt)[nonzero]...)
        values = tuple(acover[nonzero]...)
        if indices ∉ keys(sc.cover)
            sc.cover[indices] = Set{NTuple{n_way, Int}}()
        end
        push!(sc.cover[indices], values)
    end
end


function add_coverage!(sc::SetCoverage, entry::Array{T, 1}) where T
    add_cnt = 0  # Record the number removed for visibility.
    for indices in keys(sc.cover)
        value = tuple([entry[x] for x in indices]...)
        if value ∈ sc.cover[indices]
            pop!(sc.cover[indices], value)
            add_cnt += 1
        end
    end
    add_cnt
end


function add_coverage!(sc::SetCoverage, entries::Array{T, 2}) where T
    add_cnt = 0  # Record the number removed for visibility.
    for entry_idx in 1:size(entries, 2)
        add_cnt += add_coverage!(sc, entries[:, entry_idx])
    end
    add_cnt
end


function test_coverage(test_cases, arity, n_way)
    sc = SetCoverage(arity, n_way)
    build_all_combinations!(sc, 2)
    start = remaining(sc)
    add_coverage!(sc, test_cases)
    finish = remaining(sc)
    (start = start, finish = finish)
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
            values = entry[[x for x in params]]
            # values can be missing, in which case this isn't a tuple.
            if !any(values .== 0)
                push!(seen[params], Tuple(values))
            end
        end
    end
    seen
end


function coverage_by_tuple(trials, n_way)
    accumulated = tuples_in_trials(trials, n_way)
    sum([length(aset) for aset in values(accumulated)])
end
