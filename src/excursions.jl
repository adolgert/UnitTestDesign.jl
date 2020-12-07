function build_excursion(arity, n_way, disallow, seed = missing)
    test_list = []
    for way_idx in 1:n_way
        push!(test_list, all_combinations(arity .- 1, way_idx))
    end
    test_cases = hcat(test_list...)
    test_cases .+= 1

    if seed !== missing
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
