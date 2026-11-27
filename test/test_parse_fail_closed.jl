@testset "parse fail-closed" begin
    @test_throws AgentRuleLint.ParseError AgentRuleLint.parse_source("x = (\n")
end