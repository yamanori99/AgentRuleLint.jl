module LevelMisspellProbe
    using AgentRuleLint
    probe() = getproperty(AgentRuleLint.Level, :FOBID)
end

@testset "Level enum" begin
    @testset "misspelled member raises UndefVarError in a test module" begin
        err = @test_throws UndefVarError LevelMisspellProbe.probe()
        @test err.value isa UndefVarError
    end

    @testset "parse_enum and wire_name round-trip" begin
        for x in instances(AgentRuleLint.Level.T)
            @test AgentRuleLint.parse_enum(AgentRuleLint.Level.T, AgentRuleLint.wire_name(x)) === x
        end
        @test collect(AgentRuleLint.wire_name.(instances(AgentRuleLint.Level.T))) ==
            ["forbid", "deny", "warn", "allow"]
    end

    @testset "parse_enum unknown input is ConfigError listing wire names" begin
        err = @test_throws AgentRuleLint.ConfigError AgentRuleLint.parse_enum(
            AgentRuleLint.Level.T,
            "fobid",
        )
        msg = sprint(showerror, err.value)
        @test occursin("forbid|deny|warn|allow", msg)
        @test occursin("fobid", msg)
    end
end
