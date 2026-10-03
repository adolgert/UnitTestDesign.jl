# Registration examples, not new algorithms. Useful for checking integration.
# Function route includes additional harness certification in measured time.
register_solver("example_function", (space, kw) ->
    covering(space; kw..., engine=GND(seed=0,candidates=20)))

struct ExampleEngine end
function UnitTestDesign.generate(::ExampleEngine, request::UnitTestDesign.Request)
    return UnitTestDesign.generate(IPOG(), request)
end
register_solver("example_engine", ExampleEngine())
