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

This represents possible coverage as a matrix, one row per parameter,
zero if not used. `arity` is a list of the number of values for each parameter,
and `n_way` is the order of the combinations, most commonly 2-way.
"""
function all_combinations(arity, n_way)
    combinations_cnt = total_combinations(arity, n_way)
    coverage = zeros(eltype(arity), length(arity), combinations_cnt)
    all_combinations!(coverage, arity, n_way)
end


"""
    all_combinations!(coverage, arity, n_way)

`all_combinations(arity, n_way)` written into `coverage`, which must be zero
and of that size.
"""
function all_combinations!(coverage, arity, n_way)
    v_cnt = length(arity)
    # This returns a list of lists, so it has length, not size.
    indices = collect(combinations(1:v_cnt, n_way))
    idx = 1
    for indices_idx in eachindex(indices)
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
    comb = zeros(eltype(arity), length(arity), one_parameter_combinations_count(arity, n_way))
    one_parameter_combinations!(comb, arity, n_way)
end


"The number of columns of `one_parameter_combinations(arity, n_way)`."
function one_parameter_combinations_count(arity, n_way)
    param_cnt = length(arity)
    one_set = n_way > 1 ? total_combinations(view(arity, 1:(param_cnt - 1)), n_way - 1) : 1
    one_set * arity[param_cnt]
end


"""
    one_parameter_combinations!(comb, arity, n_way)

`one_parameter_combinations(arity, n_way)` written into `comb`, which must be
zero and of that size.
"""
function one_parameter_combinations!(comb, arity, n_way)
    param_cnt = length(arity)
    if n_way > 1
        one_set = size(comb, 2) ÷ arity[param_cnt]
        # The first copy is built in place and the others copied from it.
        all_combinations!(view(comb, 1:(param_cnt - 1), 1:one_set), view(arity, 1:(param_cnt - 1)), n_way - 1)
        for vidx in 1:(arity[param_cnt])
            col_begin = (vidx - 1) * one_set + 1
            col_end = vidx * one_set
            if vidx > 1
                for col in 1:one_set, row in 1:(param_cnt - 1)
                    comb[row, col_begin + col - 1] = comb[row, col]
                end
            end
            comb[param_cnt, col_begin:col_end] .= vidx
        end
    else  # n_way == 1
        comb[param_cnt, :] .= 1:(arity[param_cnt])
    end
    comb
end
