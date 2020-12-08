using Primes: nextprime


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


function driven_factorial(arity, indices, disallow)
    param_cnt = length(arity)
    test_main = full_factorial(arity[indices], x -> false)
    test_set = zeros(Int, param_cnt, size(test_main, 2))
    test_set[indices, :] .= test_main
    if length(indices) == length(arity)
        return test_set
    end
    remaining_indices = [ind for ind in 1:param_cnt if ind ∉ indices]
    drives = similar(arity)
    drives[1] = nextprime(23958)
    for drive_idx in 2:length(drives)
        drives[drive_idx] = nextprime(drives[drive_idx - 1] + 1)
    end
    println(remaining_indices)
    println(drives)
    keep = zeros(Int, size(test_set, 2))
    keep_idx = 0
    for col_idx in 1:size(test_set, 2)
        if !disallow(test_set[:, col_idx])
            for param_idx in remaining_indices
                param_val = sum(drives .* test_set[:, col_idx]) % arity[param_idx] + 1
                for param_check in 1:arity[param_idx]
                    test_set[param_idx, col_idx] = param_val
                    if !disallow(test_set[:, col_idx])
                        break
                    end
                    param_val += 1
                    param_val = (param_val % arity[param_idx]) + 1
                end
            end
            keep_idx += 1
            keep[keep_idx] = col_idx
        end
    end
    test_set[:, keep]
end
