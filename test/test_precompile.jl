using TestItemRunner

# The precompile workload (src/precompile.jl, plan §5.1) runs while the
# package precompiles, in every installation: a printed or logged line would
# show there, a file would be left behind, and an exception would stop the
# installation. Called here, it must do none of these.

@testitem "the precompile workload prints, logs, writes and throws nothing" begin
    using UnitTestDesign: _precompile_workload
    @test ccall(:jl_generating_output, Cint, ()) == 0  # so loading the package skipped it
    printed = mktempdir() do dir
        cd(dir) do
            mktemp(dir) do path, io
                redirect_stdout(io) do
                    redirect_stderr(io) do
                        @test_logs _precompile_workload()
                    end
                end
                close(io)
                @test readdir(dir) == [basename(path)]
                read(path, String)
            end
        end
    end
    @test isempty(printed)
end
