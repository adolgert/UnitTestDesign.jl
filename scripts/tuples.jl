using TestItemRunner

module CLITuples

using Pkg
using TOML

using ArgParse
using CSV
using UnitTestDesign

# This function has the same signature as the all_tuples function but encodes
# the parameters in a dictionary for a TOML file.
function convert_to_dict_all_tuples(
    parameters...;
    n_way::Integer = 2, engine = IPOG(), disallow = nothing, seeds = nothing, wayness = nothing, Counter = Int
    )
    toml_contents = Dict{String,Any}()
    toml_contents["parameters"] = Dict("params" => [collect(p) for p in parameters])
    toml_contents["config"] = Dict(
        "n_way" => n_way,
        "engine" => string(typeof(engine)),
        "Counter" => string(Counter),
    )
    if disallow !== nothing
        toml_contents["config"]["disallow"] = disallow
    end
    if wayness !== nothing
        # TOML can represent a dictionary if the key is a string.
        toml_contents["config"]["wayness"] = Dict(string(k) => v for (k, v) in wayness)
    end
    if seeds !== nothing
        toml_contents["seeds"] = Dict("seeds" => [collect(s) for s in seeds])
    end
    return toml_contents
end


function config_from_io(io)
    parsed = TOML.tryparse(io)
    if isa(parsed, TOML.ParserError)
        println("Error parsing input config file at line $(parsed.line) column $(parsed.column)")
        return nothing
    end

    kwargs = Dict{Symbol, Any}()
    parameters = Any[]
    if "parameters" ∈ keys(parsed)
        param_dict = parsed["parameters"]
        if length(param_dict) == 1
            parameters = first(values(param_dict))
        else
            println("expected 1 entry in the parameters section" *
                    "but found $(length(param_dict)) entries")
            return nothing
        end
    else
        println("""
            The config file must contain a parameters section but the sections
            are $(keys(parsed)).
            """)
        return nothing
    end
    int_types = Dict("Int8" => Int8, "Int16" => Int16, "Int32" => Int32, "Int64" => Int64)
    if "config" ∈ keys(parsed)
        for (kwarg, value) in parsed["config"]
            if kwarg == "n_way"
                kwargs[:n_way] = value
            elseif kwarg == "engine"
                if value == "IPOG"
                    kwargs[:engine] = IPOG()
                elseif value == "GND"
                    kwargs[:engine] = GND()
                else
                    println("Engine must be either IPOG or GND")
                    return nothing
                end
            elseif kwarg == "disallow"
                kwargs[:disallow] = value
            elseif kwarg == "wayness"
                kwargs[:wayness] = Dict{Int, Vector{Vector{Int}}}()
                for (k, v) in value
                    kwargs[:wayness][parse(Int, k)] = v
                end
            elseif kwarg == "Counter"
                if value in keys(int_types)
                    kwargs[:Counter] = int_types[value]
                else
                    println("Counter must be one of $(keys(int_types))")
                    return nothing
                end
            elseif kwarg == "seeds"
                kwargs[:seeds] = value
            else
                @error "Unknown config key: $(kwarg)"
            end
        end
    else
        println("""
            The config file must contain a config section but the sections
            are $(keys(parsed)).
            """)
        return nothing
    end
    return parameters, kwargs
end


function parse_commandline(env_args)
    settings = ArgParseSettings()
    add_arg_table!(settings,
        "--n-way",
        Dict(
            :help => "Wayness of the combinations.",
            :arg_type => Int64,
            :default => 0,
        ),
        "input",
        Dict(
            :help => "Name of a TOML file with configuration.",
            :arg_type => String,
            :required => true,
          ),
        "output",
        Dict(
            :help => "Name of a TOML file to write with testcases.",
            :arg_type => String,
            :required => false,
          ),
    )
    parsed = try
        parse_args(env_args, settings)
    catch err
        if isa(err, ArgParseError)
            println("Error parsing command line arguments: $(err)")
            return nothing
        else
            rethrow(err)
        end
    end
    return parsed
end


function write_testcases(io, testcases)
    colcnt = length(testcases[1])
    letters = [Symbol(x * y) for x in 'a':'z' for y in 'a':'z'][1:colcnt]
    cols = [letters[col] => [tc[col] for tc in testcases] for col in 1:colcnt]
    table = NamedTuple(cols)
    CSV.write(io, table; header = false)
end


function julia_main()::Cint
    args = parse_commandline(ARGS)
    parameters, config = open(args["input"], "r") do io
        all_config = config_from_io(io)
        all_config === nothing && return 1
        all_config
    end
    if args["n-way"] != 0
        config[:n_way] = args["n-way"]
    end
    println(stderr, "Generating test cases")
    testcases = all_tuples(parameters...; config...)
    if length(testcases) == 0
        println("No test cases generated.")
        return 2
    end
    if isnothing(args["output"])
        write_testcases(stdout, testcases)
    else
        open(args["output"], "w") do io
            write_testcases(io, testcases)
        end
    end
    return 0
end
export write_testcases, julia_main, parse_commandline, config_from_io, convert_to_dict_all_tuples
end

using .CLITuples
julia_main()


@testitem "Write and read TOML" begin
    using TOML
    using CLITuples
    toml_contents = convert_to_dict_all_tuples(
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
    parameters, config = config_from_io(io_rewound)
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
    using .CLITuples
    parsed = parse_commandline(split("""
        --n-way 2 input.toml
        """))
    @test parsed["n-way"] == 2
    @test parsed["input"] == "input.toml"
    @test parsed["output"] === nothing

    parsed = parse_commandline(split("""
        festoon.toml calibrate.csv
        """))
    @test parsed["n-way"] == 0
    @test parsed["input"] == "festoon.toml"
    @test parsed["output"] == "calibrate.csv"
end


@testitem "end-to-end parsing" begin
    using TOML
    using .CLITuples

    toml_contents = convert_to_dict_all_tuples(
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
    parameters, kwargs = config_from_io(io_rewound)
    compare_contents = convert_to_dict_all_tuples(parameters...; kwargs...)

    @test Set(keys(toml_contents)) == Set(keys(compare_contents))
end


@testitem "write_testcases writes and reads correctly" begin
    using CSV
    using .CLITuples
    testcases = [[i, i+1, string(Char('a'+i-1))] for i in 1:10]
    io = IOBuffer()
    write_testcases(io, testcases)
    seek(io, 0)
    tbl = CSV.File(io; header=false)
    # Convert CSV.File rows to lists for comparison
    read_cases = [collect(row) for row in tbl]
    # Convert all elements to string for comparison, since CSV.File may infer types
    input_cases_str = [[string(x) for x in row] for row in testcases]
    read_cases_str = [[string(x) for x in row] for row in read_cases]
    @test input_cases_str == read_cases_str
end
