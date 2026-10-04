# In-parameter-order generation, IPOG (Lei et al. 2008).
#
# The first half of this file is the classic, unconstrained algorithm, `ipog`.
# It sorts parameters by arity and works on "taller" matrices whose last row
# is the parameter being added. The second half is the constrained,
# mixed-strength form that `generate(::IPOG, request)` uses otherwise.

"""
    choose_last_parameter!(taller, allc)

Given a test set where the first k-1 parameters are chosen and the last parameter
has not been chosen, this fills in the last parameters for each test case.
"""
function choose_last_parameter!(taller, allc)
    param_idx  = size(taller, 1)
    # Each test case is read in place, and one histogram serves them all (plan §5.2).
    match_hist = zeros(eltype(allc), allc.arity[param_idx])
    for set_col_idx in axes(taller, 2)
        test_case = view(taller, :, set_col_idx)
        if any(==(0), test_case)
            matches_from_missing!(match_hist, allc, test_case, param_idx)
            if any(>(0), match_hist)
                # The argmax tie-breaks in a consistent manner.
                taller[param_idx, set_col_idx] = argmax(match_hist)
                add_coverage!(allc, test_case)
            end  # else don't set this entry by leaving it zero.
        end
    end
end


function put_tuple_in_case(tuple, case)
    for i in eachindex(tuple)
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
function insert_tuple_into_tests(test_set, allc)
    add_tests = Array{eltype(allc), 1}[]
    # Tuples, on the test set's parameters, and test cases are read and filled
    # in place; only a tuple that starts a new test case is copied (plan §5.2).
    for find_cover_idx in allc.remain:-1:1
        tuple = view(allc.allc, axes(test_set, 1), find_cover_idx)
        unmatched = true
        for test_idx in axes(test_set, 2)
            test_case = view(test_set, :, test_idx)
            if case_compatible_with_tuple(test_case, tuple)
                put_tuple_in_case(tuple, test_case)
                unmatched = false
                break
            end
        end
        if unmatched
            for tc_idx in eachindex(add_tests)
                test_case = add_tests[tc_idx]
                if case_compatible_with_tuple(test_case, tuple)
                    put_tuple_in_case(tuple, test_case)
                    unmatched = false
                    break
                end
            end
        end
        if unmatched
            push!(add_tests, collect(tuple))
        end
    end
    allc.remain = 0
    isempty(add_tests) ? test_set : hcat(test_set, stack(add_tests))
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
    for hist_entry in axes(test_set, 2)
        for hist_param in axes(test_set, 1)
            if test_set[hist_param, hist_entry] > 0
                hist[hist_param, test_set[hist_param, hist_entry]] += 1
            end
        end
    end
    for fill_col in axes(test_set, 2)
        for fill_param in axes(test_set, 1)
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
    # One coverage matrix serves every step, with a row for each parameter;
    # a step writes and reads the rows of the parameters added so far
    # (plan §5.2).
    allc = MatrixCoverage(zeros(eltype(arity), param_cnt, 0), 0, arity)

    for param_idx in (n_way + 1):param_cnt
        taller = zeros(eltype(arity), param_idx, size(test_set, 2))
        taller[1:(param_idx - 1), :] .= test_set

        # Seed test cases by adding them once params are covered and not double-covering.
        # Make mixed strength here, once all params at a strength are covered.
        one_parameter_combinations!(allc, param_idx, n_way)

        choose_last_parameter!(taller, allc)

        test_set = insert_tuple_into_tests(taller, allc)
    end

    fill_remaining_missing_values!(test_set, arity)

    # reorder test columns with `original_order`.
    test_set[original_order, :]
end


## Constrained, mixed-strength IPOG
#
# `generate(::IPOG, request)` uses `ipog` above only for an unconstrained
# request with one strength and no must-include rows. Everything else goes
# through `ipog_multi_way`, which differs from `ipog` in three ways:
#
# - Rows are full width, in the space's parameter order, with 0 for unset.
#   Parameters are added in `ipog_order`, but no row is ever permuted, so the
#   `dead` predicate always sees every value a row holds. (The 0.4 code
#   rotated each group's parameters to the front and hid the others from its
#   predicate, which let overlapping groups commit a value that clashed with
#   one set by an earlier group.)
# - The targets are the request's required list (contract §1.2), bucketed by
#   the parameter of each target that comes last in the order. Adding
#   parameter `p` covers the bucket of `p`, so targets of different strengths
#   (`stronger`, §1.8) are covered in one pass, and no infeasible target is
#   ever waited on.
# - A value is committed only when the row stays completable: `dead(row)` is
#   false (plan Phase 3 step 2). Must-include rows are completable when the
#   request accepts them (§10.4), and every required target is completable
#   (§1.2), so every row starts completable, and each of the three sites below
#   keeps it so. By induction every row is completable after every step, and
#   the final fill ends each at a complete completable row, which is a valid
#   row (§1.3).


"""
    choose_last_parameter_filter!(test_set, allc, param_idx, dead)

Horizontal growth: give parameter `param_idx` a value in each row that has
none, choosing the value that covers the most targets of `allc`, and skipping
values that would make the row dead. A row that no target favors keeps `0`.
"""
function choose_last_parameter_filter!(test_set, allc, param_idx, dead)
    putative = zeros(eltype(test_set), size(test_set, 1))
    for col in axes(test_set, 2)
        test_set[param_idx, col] == 0 || continue  # set by a must-include row
        putative .= view(test_set, :, col)
        match_hist = matches_from_missing(allc, putative, param_idx)
        # sortperm is stable, so ties go to the lower value, as argmax does.
        for value in sortperm(match_hist; rev = true)
            match_hist[value] > 0 || break
            putative[param_idx] = value
            # Invariant: the row is completable before this assignment, and
            # it is committed only if the row stays completable.
            if !dead(putative)
                test_set[param_idx, col] = value
                add_coverage!(allc, putative)
                break
            end
        end
    end
    return test_set
end


"""
    merge_if_alive!(buffer, case, tuple, dead) -> Bool

Write `case` with the values of `tuple` filled in to `buffer` and return
whether they agree and the merged row is not dead.
"""
function merge_if_alive!(buffer, case, tuple, dead)
    case_compatible_with_tuple(case, tuple) || return false
    buffer .= case
    for i in eachindex(tuple)
        tuple[i] != 0 && (buffer[i] = tuple[i])
    end
    return !dead(buffer)
end


"""
    insert_tuple_into_tests_filter(test_set, allc, dead)

Vertical growth: place each uncovered target of `allc` in the first row, old
or new, that agrees with it and stays completable with it; otherwise start a
new row with the target alone. Returns the rows, old rows first and unmoved.
"""
function insert_tuple_into_tests_filter(test_set, allc, dead)
    add_tests = Vector{eltype(test_set)}[]
    putative = zeros(eltype(test_set), size(test_set, 1))
    for find_cover_idx in allc.remain:-1:1
        tuple = allc.allc[:, find_cover_idx]
        placed = false
        for test_idx in axes(test_set, 2)
            # Invariant: a row changes only if the merged row is completable.
            if merge_if_alive!(putative, view(test_set, :, test_idx), tuple, dead)
                test_set[:, test_idx] .= putative
                placed = true
                break
            end
        end
        if !placed
            for added in add_tests
                if merge_if_alive!(putative, added, tuple, dead)
                    added .= putative
                    placed = true
                    break
                end
            end
        end
        # A new row holds one required target, which is completable (§1.2),
        # so the new row starts completable.
        placed || push!(add_tests, copy(tuple))
    end
    allc.remain = 0
    return isempty(add_tests) ? test_set : hcat(test_set, stack(add_tests))
end


"""
    fill_remaining_missing_values_filter!(test_set, arity, dead)

Give every unset entry a value, the least-used value of that parameter that
keeps the row completable, so that rows end complete and valid.
"""
function fill_remaining_missing_values_filter!(test_set, arity, dead)
    param_cnt = size(test_set, 1)
    # We could have zero values at the end, so fill them in with the
    # least-used values.
    hist = zeros(Int, param_cnt, maximum(arity))
    for hist_entry in axes(test_set, 2)
        for hist_param in axes(test_set, 1)
            if test_set[hist_param, hist_entry] > 0
                hist[hist_param, test_set[hist_param, hist_entry]] += 1
            end
        end
    end
    putative = zeros(eltype(test_set), param_cnt)
    for fill_col in axes(test_set, 2)
        for fill_param in axes(test_set, 1)
            test_set[fill_param, fill_col] == 0 || continue
            putative .= view(test_set, :, fill_col)
            chosen = 0
            for fill_val in sortperm(hist[fill_param, 1:arity[fill_param]])
                putative[fill_param] = fill_val
                # Invariant: the row is completable, so some value keeps it
                # completable (a witness's value), and only such a value is set.
                if !dead(putative)
                    chosen = fill_val
                    break
                end
            end
            chosen == 0 && error("internal error: no value of parameter $fill_param keeps case " *
                                 "$fill_col completable, though the case was completable")
            test_set[fill_param, fill_col] = chosen
            hist[fill_param, chosen] += 1
        end
    end
    return test_set
end


"""
    ipog_order(arity, groups) -> Vector{Int}

The order in which IPOG adds parameters: members of stronger groups first
(highest strength first), then larger domains first, then parameter index.
With one group this is the classic IPOG order, `sortperm(arity, rev = true)`.
"""
function ipog_order(arity::AbstractVector{<:Integer}, groups)
    n = length(arity)
    top = zeros(Int, n)
    for (members, s) in groups, i in members
        top[i] = max(top[i], s)
    end
    return sortperm(collect(1:n); by = i -> (-top[i], -arity[i], i))
end


"""
    ipog_multi_way(arity, required, dead, seeds; order) -> Matrix{Int}

In-parameter-order generation for any set of targets, in index space.

- `arity`: values per parameter; value positions are `1:arity[i]`.
- `required`: the targets to cover, each a full-width partial row with `0`
  for unset parameters. Each must be feasible; the engine never checks.
- `dead(row)`: `true` when the partial row has no valid completion. It may
  throw (a `ResourceLimitError`); the engine does not catch it.
- `seeds`: must-include rows, parameters × rows, `0` for unset. Each must be
  completable. They come first, in order, their values unchanged; their unset
  entries are filled like any other (§10.5, §7.10).
- `order`: the order in which parameters are added (`ipog_order`).

Returns a parameters × cases matrix of complete rows, none dead, that covers
every target in `required`. Deterministic: no randomness, no hashing order
(contract §9.3, §9.4).
"""
function ipog_multi_way(arity::AbstractVector{<:Integer}, required, dead,
                        seeds::AbstractMatrix{<:Integer} = zeros(Int, length(arity), 0);
                        order = ipog_order(arity, [collect(1:length(arity)) => 1]))
    n = length(arity)
    arity = collect(Int, arity)
    size(seeds, 1) == n || throw(ArgumentError("seeds have $(size(seeds, 1)) rows for $n parameters"))
    rank = invperm(order)
    buckets = [Vector{Int}[] for _ in 1:n]
    for t in required
        last = 0
        for i in 1:n
            t[i] != 0 && (last == 0 || rank[i] > rank[last]) && (last = i)
        end
        last == 0 && throw(ArgumentError("a target assigns no parameter"))
        push!(buckets[last], collect(Int, t))
    end
    test_set = Matrix{Int}(seeds)
    for p in order
        isempty(buckets[p]) && continue
        allc = MatrixCoverage(stack(buckets[p]), length(buckets[p]), arity)
        # Must-include rows that already hold `p` cover what they cover.
        for col in axes(test_set, 2)
            test_set[p, col] != 0 && add_coverage!(allc, test_set[:, col])
        end
        choose_last_parameter_filter!(test_set, allc, p, dead)
        test_set = insert_tuple_into_tests_filter(test_set, allc, dead)
    end
    return fill_remaining_missing_values_filter!(test_set, arity, dead)
end


"""
    full_strength_rows(request, required) -> Matrix{Int}

Strength equal to the parameter count: every required target is a complete
valid row, so the design is the must-include rows (partial ones completed)
followed by every valid row they do not already hold, in lexicographic order.
Without must-include rows this is the set `full_factorial` returns (contract
§7.8, §11.2).
"""
function full_strength_rows(request::Request, required)
    n = length(request.arity)
    rows = Vector{Int}[]
    for j in axes(request.must_include, 2)
        row = request.must_include[:, j]
        push!(rows, any(==(0), row) ? witness(request, row) : row)
    end
    held = Set(rows)
    for t in sort(required)
        t in held || push!(rows, t)
    end
    return isempty(rows) ? zeros(Int, n, 0) : stack(rows)
end


"""
    cover_ordinary(::IPOG, request::Request, required) -> Matrix{Int}

IPOG's rows for `request` (contract §1.3): the must-include rows first, then
rows until every target in `required` (the classified required targets,
engine positions) is in some row, each row valid under the request's rules.
`generate` classifies the targets, calls this, and validates the result
(§1.21). The request's must-include rows are ordinary. Cases:

1. No required target and no must-include row gives no rows: a proven
   empty space (§1.24).
2. Strength equal to the parameter count gives every valid row
   (`full_strength_rows`, §7.8).
3. An unconstrained request with one strength and no must-include rows uses
   the classic `ipog`.
4. Everything else uses `ipog_multi_way` over the required targets, with
   `dead(request, row)` deciding each placement.

IPOG uses no randomness (§9.4).
"""
function cover_ordinary(::IPOG, request::Request, required)
    n = length(request.arity)
    seeds = request.must_include
    if isempty(required) && isempty(seeds)
        return zeros(Int, n, 0)
    elseif request.strength == n
        return full_strength_rows(request, required)
    elseif !isconstrained(request) && isempty(seeds) && length(request.groups) == 1
        return ipog(request.arity, request.strength)
    end
    isdead = isconstrained(request) ? (row -> dead(request, row)) : Returns(false)
    return ipog_multi_way(request.arity, required, isdead, seeds;
                          order = ipog_order(request.arity, request.groups))
end

_engine_name(::IPOG) = :IPOG
_engine_seed(::IPOG) = nothing
