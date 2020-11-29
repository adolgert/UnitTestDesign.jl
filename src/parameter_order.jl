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
        # Exclude unwanted by stripping them from the allc combinations.
        for set_col_idx in 1:size(taller, 2)
            # This needs to account for previous entries that aren't set.
            match_hist = matches_from_missing(allc, taller[:, set_col_idx], param_idx)
            if (any(match_hist .> 0))
                # The argmax tie-breaks in a consistent manner.
                taller[param_idx, set_col_idx] = argmax(match_hist)
                add_coverage!(allc, taller[:, set_col_idx])
            end  # else don't set this entry by leaving it zero.
        end

        for missing_col_idx in 1:size(taller, 2)
            nonzero = sum(taller[1:(param_idx - 1), missing_col_idx] .> 0)
            if nonzero < param_idx - 1
                # The found_values has what format?
                found_entry = fill_consistent_matches(allc, taller[:, missing_col_idx])
                remain_zero = sum(found_entry .> 0)
                if remain_zero < nonzero
                    taller[:, missing_col_idx] .= found_entry
                    add_coverage!(allc, found_entry)
                end  # else nothing found for this row.
            end
        end

        add_entries = Array{Array{eltype(allc),1},1}()
        while remaining_uncovered(allc) > 0
            # add a new row. Fill with necessary tuples.
            entry = first_match_for_parameter(allc, param_idx)
            filled = fill_consistent_matches(allc, entry)
            add_coverage!(allc, filled)
            push!(add_entries, filled)
        end

        test_set = zeros(eltype(arity), param_idx, size(taller, 2) + length(add_entries))
        test_set[:, 1:size(taller, 2)] .= taller
        for long_idx in 1:length(add_entries)
            test_set[:, size(taller, 2) + long_idx] .= add_entries[long_idx]
        end
    end

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
    # reorder test columns with `original_order`.
    test_set[original_order, :]
end
