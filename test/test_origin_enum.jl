module OriginMisspellProbe
    using AgentRuleLint
    probe() = getproperty(AgentRuleLint.Origin, :PROJCT)
end

@testset "Origin enum" begin
    @testset "misspelled member raises UndefVarError in a test module" begin
        err = @test_throws UndefVarError OriginMisspellProbe.probe()
        @test err.value isa UndefVarError
    end

    @testset "wire_name spellings match JSON origin field" begin
        @test collect(AgentRuleLint.wire_name.(instances(AgentRuleLint.Origin.T))) ==
            ["agentrulelint", "preset", "project"]
        for x in instances(AgentRuleLint.Origin.T)
            @test AgentRuleLint.wire_name(x) == lowercase(String(Symbol(x)))
        end
    end

    @testset "origin_label is distinct per member" begin
        labels = AgentRuleLint.origin_label.(instances(AgentRuleLint.Origin.T))
        @test length(unique(labels)) == length(labels)
        @test AgentRuleLint.origin_label(AgentRuleLint.Origin.AGENTRULELINT) == "[AgentRuleLint]"
        @test AgentRuleLint.origin_label(AgentRuleLint.Origin.PRESET) == "[Preset]"
        @test AgentRuleLint.origin_label(AgentRuleLint.Origin.PROJECT) == "[Project]"
    end
end
