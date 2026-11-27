@testset "agent format corpus" begin
    cd(ROOT) do
        dir = mktempdir()
        out1 = joinpath(dir, "agent1.txt")
        out2 = joinpath(dir, "agent2.txt")
        try
            @test AgentRuleLint.cli_main(
                ["check", "--format=agent", "--output", out1, "test/corpus"],
            ) == 1
            @test AgentRuleLint.cli_main(
                ["check", "--format=agent", "--output", out2, "test/corpus"],
            ) == 1
            text1 = read(out1, String)
            text2 = read(out2, String)
            @test !isempty(text1)
            @test text1 == text2
            @test startswith(text1, "AGENTRULELINT FAIL")
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
