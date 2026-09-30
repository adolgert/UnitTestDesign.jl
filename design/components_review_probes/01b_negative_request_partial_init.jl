# Julia lets an inner constructor call `new` with fewer arguments than fields.
struct Toy
    names::Vector{Symbol}
    count::Int                  # a hypothetical new isbits field
    index::Dict{Symbol, Int}    # a hypothetical new reference field
    Toy(names) = new(names, length(names), Dict(n => i for (i, n) in enumerate(names)))
    Toy(::Val{:parts}, names) = new(names)   # the "parts" constructor not updated
end
t = Toy(Val(:parts), [:a, :b])
println("isdefined(t, :count) = ", isdefined(t, :count), ", t.count = ", t.count, " (arbitrary)")
println("isdefined(t, :index) = ", isdefined(t, :index))
try
    t.index
catch err
    println("t.index -> ", typeof(err))
end
