@testset "mutation run_all parallel pool" begin
    include(joinpath(@__DIR__, "mutation", "run_all_lib.jl"))

    tmp = mktempdir()
    try
        scripts = String[]
        for (fname, code) in (
                "aaa_pass.jl" => "exit(0)",
                "mmm_fail.jl" => "exit(1)",
                "zzz_crash.jl" => "exit(3)",
            )
            path = joinpath(tmp, fname)
            write(path, code * "\n")
            push!(scripts, path)
        end
        scripts = sort(scripts)

        results1 = run_mutation_harnesses(scripts; jobs = 1)
        results3 = run_mutation_harnesses(scripts; jobs = 3)

        labels(r) = (r.name, r.result, r.code)
        @test [labels(r) for r in results1] == [labels(r) for r in results3]

        @test length(results3) == 3
        @test [r.name for r in results3] == ["aaa_pass.jl", "mmm_fail.jl", "zzz_crash.jl"]
        @test count(r -> r.result === :pass, results3) == 1
        @test count(r -> r.result === :fail, results3) == 1
        @test count(r -> r.result === :crash, results3) == 1
    finally
        rm(tmp, recursive = true, force = true)
    end

    withenv("AGENTRULELINT_MUTATION_JOBS" => "0") do
        @test_throws ArgumentError parse_mutation_jobs()
    end
    withenv("AGENTRULELINT_MUTATION_JOBS" => "nope") do
        @test_throws ArgumentError parse_mutation_jobs()
    end

    @testset "signaled harness child is crash" begin
        mktempdir() do tmp
            src = joinpath(tmp, "kill_self.jl")
            write(src, "run(Cmd([\"kill\", \"-KILL\", string(getpid())]))\n")
            r = run_one_mutation_captured(src)
            @test r.result === :crash
            @test r.termsignal != 0
        end
    end
end
