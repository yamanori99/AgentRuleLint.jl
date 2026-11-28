@testset "Level enum" begin
    @testset "misspelled member raises UndefVarError in a test module" begin
        m = Module(:LevelMisspellProbe)
        Core.eval(m, :(using AgentRuleLint))
        err = try
            Core.eval(m, :(AgentRuleLint.Level.FOBID))
            nothing
        catch e
            e
        end
        @test err isa UndefVarError
    end

    @testset "parse_enum and wire_name round-trip" begin
        for x in instances(AgentRuleLint.Level.T)
            @test AgentRuleLint.parse_enum(AgentRuleLint.Level.T, AgentRuleLint.wire_name(x)) === x
        end
        @test collect(AgentRuleLint.wire_name.(instances(AgentRuleLint.Level.T))) ==
            ["forbid", "deny", "warn", "allow"]
    end

    @testset "parse_enum unknown input is ConfigError listing wire names" begin
        err = try
            AgentRuleLint.parse_enum(AgentRuleLint.Level.T, "fobid")
            nothing
        catch e
            e
        end
        @test err isa AgentRuleLint.ConfigError
        msg = sprint(showerror, err)
        @test occursin("forbid|deny|warn|allow", msg)
        @test occursin("fobid", msg)
    end
end
