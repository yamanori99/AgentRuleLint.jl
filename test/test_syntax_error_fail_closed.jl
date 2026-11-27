@testset "syntax error file fail-closed" begin
    dir = mktempdir()
    bad = joinpath(dir, "syntax_error_tmp.jl")
    try
        write(bad, "x = (\n")
        @test_throws AgentRuleLint.ParseError AgentRuleLint.check(dir; paths = ["syntax_error_tmp.jl"])
    finally
        rm(dir, recursive = true, force = true)
    end
end
