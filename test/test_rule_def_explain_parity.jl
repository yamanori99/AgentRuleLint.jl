using AgentRuleLint
using Test

@testset "RuleDef intent/do_not matches explain" begin
    tmp = mktempdir()
    try
        for def in AgentRuleLint.RULE_DEFS
            text = AgentRuleLint.explain_rule(def.id; root = tmp)
            body = "intent:\n$(def.intent)\n\ndo_not:\n$(def.do_not)"
            @test occursin(body, text)
        end
    finally
        rm(tmp; recursive = true, force = true)
    end
end
