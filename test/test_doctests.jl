using TestItemRunner

# Every jldoctest block, in the docstrings of src/ and in the manual pages
# under docs/src, runs here as it runs in `docs/make.jl`, so a stale example
# fails the suite and not only the documentation build (plan Phase 7 step 8).
# `manual = true` finds the pages at docs/src beside the package's src/.
@testitem "doctests" begin
    using Documenter
    # Documenter evaluates a page's `@meta` block (`CurrentModule =
    # UnitTestDesign`) in `Main`, as `docs/make.jl` runs it; a test item runs
    # in a module of its own, so load the package into `Main` too.
    Core.eval(Main, :(using UnitTestDesign))
    DocMeta.setdocmeta!(UnitTestDesign, :DocTestSetup, :(using UnitTestDesign); recursive = true)
    doctest(UnitTestDesign; manual = true, testset = "doctests")
end

# Every exported name has a docstring that opens with the situation it
# serves (plan Phase 7 step 5), and no docstring describes a case count as
# minimal, optimal or fewest (contract §8.4): only a result may call its own
# count minimal, when the count equals its proven lower bound (§8.7).
@testitem "exported docstrings" begin
    meta = Base.Docs.meta(UnitTestDesign)
    undocumented, no_situation, size_claims = Symbol[], Symbol[], Symbol[]
    for name in names(UnitTestDesign)
        name === :UnitTestDesign && continue
        binding = Base.Docs.Binding(UnitTestDesign, name)
        if !haskey(meta, binding)
            push!(undocumented, name)
            continue
        end
        for doc in values(meta[binding].docs)
            text = join(doc.text)
            startswith(text, "Use when") || startswith(text, "Deprecated alias of") ||
                push!(no_situation, name)
            occursin(r"\b(minimal|optimal|fewest|minimum)\s+(number\s+of\s+)?(cases|rows|designs?)\b"i, text) &&
                push!(size_claims, name)
        end
    end
    @test isempty(undocumented)
    @test isempty(no_situation)
    @test isempty(size_claims)
end
