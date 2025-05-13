using ArgParse
using TOML
using CSV


function config_from_io(io)
    parsed = TOML.tryparse(io)
    if isa(parsed, TOML.ParserError)
        println("Error parsing input config file at line $(err.line) column $(err.column)")
        return nothing
    end

    config = Dict{String, Any}()
    parameters = Any[]
    if "parameters" ∈ keys(parsed)
        argnames = collect(keys(parsed["parameters"]))
        sort!(argnames)
        for argname in argnames
            push!(parameters, parsed["parameters"][argname])
        end
    else
        println("""
            The config file must contain a parameters section but the sections
            are $(keys(parsed)).
            """)
        return nothing
    end
    seeds = nothing
    if "seeds" ∈ keys(parsed)
        seeds = Any[]
        for (seedidx, seedlist) in parsed["seeds"]
            push!(seeds, seedlist)
        end
        config["seeds"] = seeds
    end
    int_types = Dict("Int8" => Int8, "Int16" => Int16, "Int32" => Int32, "Int64" => Int64)
    if "config" ∈ keys(parsed)
        for (kwarg, value) in parsed["config"]
            if kwarg == "n_way"
                config[kwarg] = value
            elseif kwarg == "engine"
                if value == "IPOG"
                    config[kwarg] = IPOG()
                elseif value == "GND"
                    config[kwarg] = GND()
                else
                    println("Engine must be either IPOG or GND")
                    return nothing
                end
            elseif kwarg == "disallow"
                config[kwarg] = value
            elseif kwarg == "wayness"
                config[kwarg] = Dict{Int, Vector{Vector{Int}}}()
                for (k, v) in value
                    config[kwarg][parse(Int, k)] = v
                end
            elseif kwarg == "Counter"
                if value in keys(int_types)
                    config[kwarg] = int_types[value]
                else
                    println("Counter must be one of $(keys(int_types))")
                    return nothing
                end
            else
                config[kwarg] = value
            end
        end
    else
        println("""
            The config file must contain a config section but the sections
            are $(keys(parsed)).
            """)
        return nothing
    end
    return config, parameters
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
    letters = [x * y for x in 'a':'z' for y in 'a':'z'][1:colcnt]
    cols = [letters[col] => [tc[row] for row in 1:length(testcases)] for col in 1:colcnt]
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
    if outfile ∉ ["stdout" || "stderr"]
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
