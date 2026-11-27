@testset "CLI exit codes" begin
    cd(ROOT) do
        @test AgentRuleLint.cli_main(["explain", "expect-audit"]) == 0
        @test AgentRuleLint.cli_main(["explain", "not-a-real-rule"]) == 2
        @test AgentRuleLint.cli_main(["check", "LICENSE"]) == 0
        @test AgentRuleLint.cli_main(["check", "test/corpus/split_string.jl"]) == 1
        @test AgentRuleLint.cli_main(["nope"]) == 2
    end
end
