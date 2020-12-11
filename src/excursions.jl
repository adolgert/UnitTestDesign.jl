using Combinatorics: combinations


function build_excursion(arity, n_way, disallow, seed = nothing)
    test_list = [zeros(eltype(arity), length(arity), 1)]
    for way_idx in 1:n_way
        push!(test_list, all_combinations(arity .- 1, way_idx))
    end
    test_cases = hcat(test_list...)
    test_cases .+= 1

    if seed !== nothing
        seeded = unique(hcat(seed, test_cases), dims = 2)
    else
        seeded = test_cases
    end

    allowed = zeros(Int, length(seeded))
    allow_cnt = 0
    for case_idx in 1:size(seeded, 2)
        if !disallow(seeded[:, case_idx])
            allow_cnt += 1
            allowed[allow_cnt] = case_idx
        end
    end
    seeded[:, allowed[1:allow_cnt]]
end


function build_excursion_multi(arity, n_way, levels, disallow, seed = nothing)
    param_cnt = length(arity)
    levels[n_way] = [collect(1:length(arity))]
    # excursion_set = Set{Tuple{Vararg{Int64, N} where N}}()
    excursion_set = Set{Array{Int, 1}}()
    for level in keys(levels)
        for indices in levels[level]
            # combos = Set(collect(tuple(x...) for x in combinations(indices, level)))
            for subset_idx in 1:level
                combos = Set(collect(combinations(indices, subset_idx)))
                union!(excursion_set, combos)
            end
        end
    end
    essity = arity .- 1  # 1 is the origin of the excursion
    excursions = sort(collect(excursion_set), by = x -> (length(x), x))
    include_origin = 1
    test_cnt = sum(prod(essity[inds]) for inds in excursions) + include_origin

    test_cases = ones(Int, param_cnt, test_cnt)
    test_cases[:, 1] .= 1
    test_idx = include_origin
    for exc_indices in excursions
        walks = ones(Int, length(exc_indices))
        for sub_idx in 1:prod(essity[exc_indices])
            test_idx += 1
            test_cases[exc_indices, test_idx] = walks .+ 1
            next_multiplicative!(walks, essity[exc_indices])
        end
        @assert walks == ones(Int, length(exc_indices))
    end
    @assert test_idx == test_cnt

    if seed !== nothing
        seeded = unique(hcat(seed, test_cases), dims = 2)
    else
        seeded = test_cases
    end

    allowed = zeros(Int, length(seeded))
    allow_cnt = 0
    for case_idx in 1:size(seeded, 2)
        if !disallow(seeded[:, case_idx])
            allow_cnt += 1
            allowed[allow_cnt] = case_idx
        end
    end
    seeded[:, allowed[1:allow_cnt]]
end
