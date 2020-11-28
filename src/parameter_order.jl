
function ipog(arity, n_way, M, rng)
    nonincreasing = sortperm(arity, rev = true)
    original_arity = arity
    arity = arity[nonincreasing]
    original_order = sortperm(nonincreasing)

    param_cnt = length(arity)
    # Setup by taking first n_way parameters.
    # This is a 2D array.
    test_set = all_combinations(arity[1:n_way], n_way)

    for param_idx in (n_way + 1):param_cnt
        wider = zeros(Int, size(test_set, 1), param_idx)
        wider[:, 1:(param_idx - 1)] .= test_set

        allc = one_parameter_combinations(arity[1:param_idx], param_idx)
        for set_row_idx in 1:size(wider, 2)
            # This needs to account for previous entries that aren't set.
            match_hist = most_matches_existing(
                    allc, wider[set_row_idx, :], param_idx
                    )
            if (any(match_hist > 0))
                wider[set_row_idx, param_idx] = argmax(match_hist)
                add_coverage!(allc, wider[set_row_idx, :])
            end  # else don't set this entry by leaving it zero.
        end

        for missing_row_idx in 1:size(wider, 2)
            no_param = wider[missing_row_idx, param_idx] == 0
            any_missing = any(wider[missing_row_idx, 1:(param_idx - 1)]) == 0
            if no_param && any_missing
                # The found_values has what format?
                found_values = matches_to_missing(allc, wider[missing_row_idx, :], param_idx)
                if any(found_values > 0)
                    wider[missing_row_idx, :] = argmax(found_values)
                    add_coverage!(allc, wider[missing_row_idx, :])
                end  # else nothing found for this row.
            end
        end

        add_entries = Array{Array{eltype(allc),1},1}()
        while remaining_uncovered(allc) > 0
            # add a new row. Fill with necessary tuples.
            entry = first_match_for_parameter(mc, param_idx)
            filled = fill_consistent_matches(mc, entry)
            add_coverage!(mc, filled)
            push!(add_entries, filled)
        end

        test_set = zeros(Int, size(wider, 1) + length(add_entries), param_idx)
        test_set[1:size(wider, 1), :] .= wider
        for long_idx in 1:length(add_entries)
            test_set[1:size(wider, 1) + long_idx] .= add_entries[long_idx]
        end
    end
    # reorder test columns with `original_order`.
    test_set[:, original_order]
end
