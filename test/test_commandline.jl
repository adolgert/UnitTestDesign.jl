using TestItemRunner
using Random
using CSV

@testitem "Write and read TOML" begin
    using TOML
    toml_contents = UnitTestDesign.convert_to_dict_all_tuples(
        [1, 2, 3],
        ["a", "b", "c"],
        [1, 5, 7],
        [7, 9, 11],
        [1, 2, 3];
        n_way = 2,
        engine = IPOG(),
        disallow = nothing,
        seeds = [[3, "a", 5, 7, 1], [1, "a", 7, 11, 3]],
        wayness = Dict(3 => [[1, 3, 4, 5]]),
        Counter = Int8,
    )
    io = IOBuffer()
    TOML.print(io, toml_contents, sorted=true)
    io_rewound = seek(io, 0)
    parameters, config = UnitTestDesign.config_from_io(io_rewound)
    @test config[:n_way] == 2
    @test config[:engine] == IPOG()
    @test :disallow ∉ keys(config)
    @test config[:wayness] == Dict(3 => [[1, 3, 4, 5]])
    @test config[:Counter] == Int8
    @test parameters == Any[
        [1, 2, 3],
        ["a", "b", "c"],
        [1, 5, 7],
        [7, 9, 11],
        [1, 2, 3],
    ]
    @test config[:seeds] == Any[[3, "a", 5, 7, 1], [1, "a", 7, 11, 3]]
end


@testitem "commandline parser makes sense" begin
    parsed = UnitTestDesign.parse_commandline(split("""
        --n-way 2 input.toml
        """))
    @test parsed["n-way"] == 2
    @test parsed["input"] == "input.toml"
    @test parsed["output"] === nothing

    parsed = UnitTestDesign.parse_commandline(split("""
        festoon.toml calibrate.csv
        """))
    @test parsed["n-way"] == 0
    @test parsed["input"] == "festoon.toml"
    @test parsed["output"] == "calibrate.csv"
end


@testitem "end-to-end parsing" begin
    using TOML

    toml_contents = UnitTestDesign.convert_to_dict_all_tuples(
        [1, 2, 3],
        ["a", "b", "c"],
        [1, 5, 7],
        [7, 9, 11],
        [1, 2, 3];
        n_way = 2,
        engine = IPOG(),
        disallow = nothing,
        seeds = [[3, "a", 5, 7, 1], [1, "a", 7, 11, 3]],
        wayness = Dict(3 => [[1, 3, 4, 5]]),
        Counter = Int8,
    )
    io = IOBuffer()
    TOML.print(io, toml_contents, sorted=true)
    io_rewound = seek(io, 0)
    parameters, kwargs = UnitTestDesign.config_from_io(io_rewound)
    compare_contents = UnitTestDesign.convert_to_dict_all_tuples(parameters...; kwargs...)

    @test Set(keys(toml_contents)) == Set(keys(compare_contents))
end

@testitem "write_testcases writes and reads correctly" begin
    testcases = [[i, i+1, string(Char('a'+i-1))] for i in 1:10]
    io = IOBuffer()
    UnitTestDesign.write_testcases(io, testcases)
    seek(io, 0)
    tbl = CSV.read(io, DataFrame, header=false)
    # Convert DataFrame rows to lists for comparison
    read_cases = [collect(tbl[i, :]) for i in 1:nrow(tbl)]
    # Convert all elements to string for comparison, since CSV.read may infer types
    input_cases_str = [[string(x) for x in row] for row in testcases]
    read_cases_str = [[string(x) for x in row] for row in read_cases]
    @test input_cases_str == read_cases_str
end


