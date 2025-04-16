using TestItemRunner

@testitem "aqua checks" begin
    using Aqua
    Aqua.test_all(UnitTestDesign)
end
