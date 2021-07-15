using UnitTestDesign

entries = [
    (args = 5, vals = 4),
    (args = 5, vals = 8),
    (args = 10, vals = 4),
    (args = 10, vals = 8),
    (args = 40, vals = 4),
    (args = 40, vals = 8),
]
for e in entries
    vals = fill(1:e[:vals], e[:args])
    c = e[:vals]^e[:args]
    p = size(all_pairs(vals...))[1]
    t = size(all_triples(vals...))[1]
    ve = size(values_excursion(vals...))[1]
    pe = size(pairs_excursion(vals...))[1]
    # This is the power of 10 for the arguments.
    # val^arg = 10^(log10(val^arg)) = 10^(arg * log10(val))
    pow10 = e[:args] * log10(e[:vals])
    println("$(e[:vals]) $(e[:args]) $c $(pow10) $p $t $ve $pe")
end

params = fill(1:4, 40)
ts = all_pairs(params...;
    wayness = Dict(3 => [collect(3:6)])
    )
