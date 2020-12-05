"""
    choose_last_parameter!(taller, arity, n_way)

Given a test set where the first k-1 parameters are chosen and the last parameter
has not been chosen, this fills in the last parameters for each test case.
"""
function choose_last_parameter!(taller, allc, matcher = case_partial_cover)
    param_idx  = size(taller, 1)
    for set_col_idx in 1:size(taller, 2)
        if any(taller[:, set_col_idx] .== 0)
            match_hist = matches_from_missing(allc, taller[:, set_col_idx], param_idx, matcher)
            if (any(match_hist .> 0))
                # The argmax tie-breaks in a consistent manner.
                taller[param_idx, set_col_idx] = argmax(match_hist)
                add_coverage!(allc, taller[:, set_col_idx])
            end  # else don't set this entry by leaving it zero.
        end
    end
end


"""
The given test cases have missing values, which are zeros.
This fills in missing values anywhere they cover tuples.
"""
function fill_missing_test_set_values!(taller, allc, matcher = case_compatible_with_tuple)
    param_idx  = size(taller, 1)
    for missing_col_idx in 1:size(taller, 2)
        nonzero = sum(taller[1:(param_idx - 1), missing_col_idx] .> 0)
        if nonzero < param_idx - 1
            # The found_values has what format?
            found_entry = fill_consistent_matches(allc, taller[:, missing_col_idx], matcher)
            remain_zero = sum(found_entry .> 0)
            if remain_zero < nonzero
                taller[:, missing_col_idx] .= found_entry
                add_coverage!(allc, found_entry)
            end  # else nothing found for this row.
        end
    end
end


"""
If not all tuples are covered by a test set, this creates new test cases
to cover all remaining tuples.
"""
function cover_remaining_by_creating_cases(allc, matcher = case_compatible_with_tuple)
    param_idx = parameter_cnt(allc)
    add_entries = Array{Array{eltype(allc),1},1}()
    while remaining_uncovered(allc) > 0
        # add a new row. Fill with necessary tuples.
        entry = first_match_for_parameter(allc, param_idx)
        filled = fill_consistent_matches(allc, entry, matcher)
        add_coverage!(allc, filled)
        push!(add_entries, filled)
    end
    add_entries
end


function put_tuple_in_case(tuple, case)
    for i in 1:length(tuple)
        if tuple[i] != 0
            if case[i] == 0
                case[i] = tuple[i]
            elseif case[i] != tuple[i]
                error("tuple doesn't match case $(tuple), $(case)")
            end  # else the values match.
        end
    end
    case
end


"""
Loop over remaining tuples instead of looping over each test.
For each tuple, loop over tests where that tuple could go. If that fails,
add the tuple at the end as its own test.
"""
function insert_tuple_into_tests(test_set, allc, matcher = case_compatible_with_tuple)
    add_tests = Array{eltype(allc), 1}[]
    for find_cover_idx in allc.remain:-1:1
        tuple = allc.allc[:, find_cover_idx]
        unmatched = true
        for test_idx in 1:size(test_set, 2)
            test_case = test_set[:, test_idx]
            matches = matcher(test_case, tuple)
            if matches
                test_set[:, test_idx] = put_tuple_in_case(tuple, test_case)
                unmatched = false
                break
            end
        end
        if unmatched
            for tc_idx in 1:length(add_tests)
                test_case = add_tests[tc_idx]
                if matcher(test_case, tuple)
                    add_tests[tc_idx] = put_tuple_in_case(tuple, test_case)
                    unmatched = false
                    break
                end
            end
        end
        if unmatched
            push!(add_tests, tuple)
        end
    end
    allc.remain = 0
    hcat(test_set, add_tests...)
end


"""
As a finishing step on a set of test cases, this fills in missing values
which aren't needed to cover the tuples but can increase coverage
of higher tuples.
"""
function fill_remaining_missing_values!(test_set, arity)
    param_cnt = size(test_set, 1)
    # We could have zero values at the end, so fill them in with the
    # least-used values.
    hist = zeros(Int, param_cnt, maximum(arity))
    for hist_entry in 1:size(test_set, 2)
        for hist_param in 1:size(test_set, 1)
            if test_set[hist_param, hist_entry] > 0
                hist[hist_param, test_set[hist_param, hist_entry]] += 1
            end
        end
    end
    for fill_col in 1:size(test_set, 2)
        for fill_param in 1:size(test_set, 1)
            if test_set[fill_param, fill_col] == 0
                fill_val = argmin(hist[fill_param, 1:arity[fill_param]])
                test_set[fill_param, fill_col] = fill_val
                hist[fill_param, fill_val] += 1
            end
        end
    end
end


"""
    ipog(arity, n_way)

The `arity` is an integer array of the number of possible values each
parameter can take. The `n_way` is whether each parameter must appear
once in the test suite, or whether each pair of parameters must appear
together, or whether each triple must appear together. The wayness
can be set as high as the length of the arity.

This uses the in-parameter-order-general algorithm. It will always return
the same set of values. It takes less time and memory than most other
approaches.

This function represents a test set as a two-dimensional array of
the same integer type as the input arity. Each value of the array
is either an integer number, from 1 to the arity of that parameter,
or it is 0 for what the paper calls a don't-care value.

Lei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence.
2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial
Testing.” Software Testing, Verification & Reliability 18 (3): 125–48.
"""
function ipog(arity, n_way)
    nonincreasing = sortperm(arity, rev = true)
    original_arity = arity
    arity = arity[nonincreasing]
    original_order = sortperm(nonincreasing)

    param_cnt = length(arity)
    # Setup by taking first n_way parameters.
    # This is a 2D array.
    test_set = all_combinations(arity[1:n_way], n_way)

    for param_idx in (n_way + 1):param_cnt
        taller = zeros(eltype(arity), param_idx, size(test_set, 2))
        taller[1:(param_idx - 1), :] .= test_set

        # Seed test cases by adding them once params are covered and not double-covering.
        # Make mixed strength here, once all params at a strength are covered.
        allc = one_parameter_combinations_matrix(arity[1:param_idx], n_way)

        choose_last_parameter!(taller, allc)

        test_set = insert_tuple_into_tests(taller, allc)
    end

    fill_remaining_missing_values!(test_set, arity)

    # reorder test columns with `original_order`.
    test_set[original_order, :]
end


function keep_allowed(test_set, disallow)
    allow_cnt = 0
    allowed = zeros(Int, size(test_set, 2))
    for idx in 1:size(test_set, 2)
        if !disallow(test_set[:, idx])
            allow_cnt += 1
            allowed[allow_cnt] = idx
        end  # else not allowed so not put into the list.
    end
    test_set[:, allowed[1:allow_cnt]]
end


function ipog_multi(arity, n_way, disallow, seed)
    nonincreasing = sortperm(arity, rev = true)
    original_arity = arity
    arity = arity[nonincreasing]
    original_order = sortperm(nonincreasing)

    param_cnt = length(arity)
    if seed !== missing
        seed = seed[nonincreasing, :]
        seed_tests = seed[1:n_way, :]
    else
        seed = zeros(Int, n_way, 0)
        seed_tests = zeros(Int, n_way, 0)
    end
    # Setup by taking first n_way parameters.
    # This is a 2D array.
    combo_tests = keep_allowed(all_combinations(arity[1:n_way], n_way), disallow)
    test_set = unique(hcat(seed_tests, combo_tests), dims = 2)

    for param_idx in (n_way + 1):param_cnt
        taller = zeros(eltype(arity), param_idx, size(test_set, 2))
        taller[1:(param_idx - 1), :] .= test_set
        # Seed test cases by adding them once params are covered and not double-covering.
        # Make mixed strength here, once all params at a strength are covered.
        allc = one_parameter_combinations_matrix(arity[1:param_idx], n_way)
        remove_combinations!(allc, disallow)

        if size(seed, 2) > 0
            taller[param_idx, 1:size(seed, 2)] = seed[param_idx, :]
        end
        choose_last_parameter!(taller, allc)

        test_set = insert_tuple_into_tests(taller, allc)
    end

    fill_remaining_missing_values!(test_set, arity)

    # reorder test columns with `original_order`.
    test_set[original_order, :]
end


function ipog_bytuple_instrumented(arity, n_way, strategy)
    nonincreasing = sortperm(arity, rev = true)
    original_arity = arity
    arity = arity[nonincreasing]
    original_order = sortperm(nonincreasing)

    param_cnt = length(arity)
    widen = zeros(Int, param_cnt)
    fillz = zeros(Int, param_cnt)
    cover = zeros(Int, param_cnt)
    # Setup by taking first n_way parameters.
    # This is a 2D array.
    test_set = all_combinations(arity[1:n_way], n_way)

    for param_idx in (n_way + 1):param_cnt
        taller = zeros(eltype(arity), param_idx, size(test_set, 2))
        taller[1:(param_idx - 1), :] .= test_set

        allc = one_parameter_combinations_matrix(arity[1:param_idx], n_way)

        choose_last_parameter!(taller, allc, strategy[:lastparam])

        widen[param_idx] = size(allc.allc, 2) - allc.remain

        test_set = insert_tuple_into_tests(taller, allc, strategy[:expand])
    end

    # remove the part to fill missing values at the end.

    # reorder test columns with `original_order`.
    (test_set[original_order, :], widen, fillz, cover)
end
