@testset "CLI subprocess -m AgentRuleLint" begin
    cmd = `julia --startup-file=no --project=$(ROOT) -m AgentRuleLint explain expect-audit`
    @test success(run(cmd))
end
