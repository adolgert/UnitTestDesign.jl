# These functions compute the sizes of combinations of parameters.

using Combinatorics: combinations

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
    # This returns a list of lists, so it has length, not size.
    indices = collect(combinations(1:v_cnt, n_way))
    combinations_cnt = total_combinations(arity, n_way)

    coverage = zeros(eltype(arity), v_cnt, combinations_cnt)
    idx = 1
    for indices_idx in 1:length(indices)
        offset = indices[indices_idx]
        sub_arity = arity[offset]
        sub_cnt = prod(sub_arity)
        values = copy(sub_arity)
        for sub_idx in 1:sub_cnt
            next_multiplicative!(values, sub_arity)
            coverage[offset, idx] = values
            idx += 1
        end
    end
    coverage
end


"""
    one_parameter_combinations(arity, n_way)

Generates all combinations that are nonzero for the last parameter.
This is for in-parameter-order generation, where we need
only those tuples that end with this column being nonzero.

The construction method is to leave out the given parameter
and construct all `n_way` - 1 tuples. Then copy and paste that
once for each possible value of the given parameter.
"""
function one_parameter_combinations(arity, n_way)
    param_cnt = length(arity)
    if n_way > 1
        partial = all_combinations(arity[1:(param_cnt-1)], n_way - 1)
        one_set = size(partial, 2)
        comb = zeros(eltype(arity), param_cnt, one_set * arity[param_cnt])
        for vidx in 1:(arity[param_cnt])
            col_begin = (vidx - 1) * one_set + 1
            col_end = vidx * one_set
            comb[1:size(partial, 1), col_begin:col_end] .= partial
            comb[param_cnt, col_begin:col_end] .= vidx
        end
    else  # n_way == 1
        comb = zeros(eltype(arity), param_cnt, arity[param_cnt])
        comb[param_cnt, :] .= 1:(arity[param_cnt])
    end
    comb
end


combination_number(n, m) = prod(n:-1:(n-m+1)) ÷ factorial(m)


function pairs_in_entry(entry, n_way)
    n = length(entry)
    ans = zeros(Int, combination_number(n, n_way), n)
    col_set_idx = 1
    for param_idx in combinations(1:length(entry), n_way)
        for row_idx in 1:n_way
            ans[param_idx[row_idx], col_set_idx] = entry[param_idx[row_idx]]
        end
        col_set_idx += 1
    end
    ans
end
