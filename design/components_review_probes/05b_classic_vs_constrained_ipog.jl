# Does the constrained core, run without rules, reproduce the classic `ipog`?
# Compares size, exact matrix, and row set; times both. Read-only.
using UnitTestDesign
const U = UnitTestDesign

function both(arity, t)
    names = [Symbol(:p, i) for i in eachindex(arity)]
    space = TestSpace((names[i] => 1:arity[i] for i in eachindex(arity))...)
    request = U.Request(space; strength = t)
    required, _ = U.classify_targets(request)
    classic = U.ipog(arity, t)
    multi = U.ipog_multi_way(arity, required, Returns(false); order = U.ipog_order(arity, request.groups))
    via_generate = U.generate(IPOG(), request).matrix
    return classic, multi, via_generate
end

cases = [([2, 3, 2], 2), ([2, 3, 2, 4, 7, 2], 2), (fill(3, 6), 2), (fill(4, 10), 2), ([5, 4, 3, 3, 2, 2, 2], 2),
         (fill(3, 8), 3), ([4, 4, 3, 3, 2, 2, 2, 2], 3), (fill(4, 10), 3), (fill(2, 12), 4), (fill(3, 10), 4)]
println(rpad("arity", 28), rpad("t", 3), rpad("classic", 9), rpad("multi", 9), rpad("same matrix", 13), rpad("same row set", 14), "generate==classic")
for (arity, t) in cases
    c, m, g = both(arity, t)
    println(rpad(string(arity), 28), rpad(string(t), 3), rpad(string(size(c, 2)), 9), rpad(string(size(m, 2)), 9),
            rpad(string(c == m), 13), rpad(string(Set(eachcol(c)) == Set(eachcol(m))), 14), g == c)
end

# Timing on one mid-size case, after warm-up
arity, t = fill(4, 12), 3
names = [Symbol(:p, i) for i in eachindex(arity)]
space = TestSpace((names[i] => 1:arity[i] for i in eachindex(arity))...)
request = U.Request(space; strength = t)
required, _ = U.classify_targets(request)
order = U.ipog_order(arity, request.groups)
U.ipog(arity, t); U.ipog_multi_way(arity, required, Returns(false); order)
tc = @timed U.ipog(arity, t)
tm = @timed U.ipog_multi_way(arity, required, Returns(false); order)
println("\n12 x 4 values, strength 3: classic ", size(tc.value, 2), " rows in ", round(tc.time, digits = 3), " s, ",
        round(tc.bytes / 2^20, digits = 1), " MiB; multi ", size(tm.value, 2), " rows in ", round(tm.time, digits = 3), " s, ",
        round(tm.bytes / 2^20, digits = 1), " MiB")
