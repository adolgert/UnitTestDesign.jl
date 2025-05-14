using ArgParse
using TOML
using CSV


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
        println("Error parsing input config file at line $(err.line) column $(err.column)")
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
    kwargs[:seeds] = nothing
    if "seeds" ∈ keys(parsed)
        seed_dict = parsed["seeds"]
        if length(seed_dict) == 1
            kwargs[:seeds] = first(values(seed_dict))
        elseif length(seed_dict) > 1
            println("expected 0 or 1 entry in the seeds section" *
                    "but found $(length(seed_dict)) entries")
            return nothing
        end
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


function julia_main()
    args = parse_commandline(ARGS)
    all_config = config_from_io(args["arg1"])
    if isnothing(all_config)
        return 1
    end
    config, parameters = all_config
    if args["n-way"] != 0
        config["n_way"] = args["n-way"]
    end
    println(stderr, "Generating test cases")
    testcases = all_tuples(parameters...;
        n_way = config["n_way"],
        engine = config["engine"],
        wayness = config["wayness"],
        Counter = config["Counter"],
    )
    if length(testcases) == 0
        println("No test cases generated.")
        return 2
    end
    outfile = args["output"]
    println(stderr, "Writing $(length(testcases)) test cases to $(outfile)")
    if outfile ∉ ["stdout", "stderr"]
        open(outfile, "w") do io
            write_testcases(io, testcases)
        end
    else
        if outfile == "stdout"
            outio = stdout
        elseif outfile == "stderr"
            outio = stderr
        else
            @error "Invalid output file name: $(outfile)"
        end
        write_testcases(outio, testcases)
    end
    return 0
end
