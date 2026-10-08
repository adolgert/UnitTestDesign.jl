# Where does report()'s bonus measurement spend its time? (30 params x 5 values, all_pairs)
#   julia --project=/Users/adolgert/dev/UnitTestDesign.jl probe_bonus_profile.jl
using UnitTestDesign, Profile
const U = UnitTestDesign
space = TestSpace(NamedTuple{Tuple(Symbol("x$i") for i in 1:30)}(Tuple(1:5 for _ in 1:30)))
cases = all_pairs(space); rows = collect(cases)
bonus() = U._coverage(rows, space; strength = 3, stronger = Pair[], feasibility_limit = 1_000_000, explanation_limit = 1_000_000)
bonus()
Profile.clear(); Profile.init(n = 10^7, delay = 0.0005)
@profile for _ in 1:4; bonus(); end
data = Profile.fetch()
lidict = Profile.getdict(data)
# Count samples (backtraces) that contain a frame of each function.
function share(names)
    total = 0; hit = Dict(n => 0 for n in names)
    bt = UInt64[]
    for x in data
        if x == 0
            if !isempty(bt)
                total += 1
                frames = Set(sf.func for ip in bt for sf in get(lidict, ip, Base.StackTraces.StackFrame[]))
                for n in names; n in frames && (hit[n] += 1); end
            end
            empty!(bt)
        else
            push!(bt, x)
        end
    end
    return total, hit
end
total, hit = share([:_coverage, :_read_rows, :_projections, :_classify!, :from_indices, :explain_partial, :_completable, :feasibility_for])
println("samples with any frame: $total")
for (k, v) in sort(collect(hit); by = last, rev = true)
    println(rpad(k, 18), v, "  (", round(100v / max(hit[:_coverage], 1); digits = 1), "% of samples inside _coverage)")
end
