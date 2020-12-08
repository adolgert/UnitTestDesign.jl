
function full_factorial(arity, disallow)
    param_cnt = length(arity)
    test_cnt = prod(arity)
    test_set = zeros(Int, param_cnt, test_cnt)
    state = ones(Int, param_cnt)
    idx = 0
    for gen_idx in 1:test_cnt
        if !disallow(state)
            test_set[:, gen_idx] = state
            idx += 1
        end
        next_multiplicative!(state, arity)
    end
    # Test the invariant that the state rolls over to all ones.
    @assert state == ones(Int, param_cnt)
    test_set[:, 1:idx]
end
