module OutputFormatMisspellProbe
    using AgentRuleLint
    probe() = getproperty(AgentRuleLint.OutputFormat, :JSNO)
end

@testset "OutputFormat enum" begin
    @testset "misspelled member raises UndefVarError in a test module" begin
        err = @test_throws UndefVarError OutputFormatMisspellProbe.probe()
        @test err.value isa UndefVarError
    end

    @testset "parse_enum and wire_name round-trip" begin
        for x in instances(AgentRuleLint.OutputFormat.T)
            @test AgentRuleLint.parse_enum(AgentRuleLint.OutputFormat.T, AgentRuleLint.wire_name(x)) === x
        end
        @test collect(AgentRuleLint.wire_name.(instances(AgentRuleLint.OutputFormat.T))) ==
            ["human", "json", "agent"]
    end

    @testset "parse_enum unknown input is ConfigError listing wire names" begin
        err = @test_throws AgentRuleLint.ConfigError AgentRuleLint.parse_enum(
            AgentRuleLint.OutputFormat.T,
            "xml",
        )
        msg = sprint(showerror, err.value)
        @test occursin("human|json|agent", msg)
        @test occursin("xml", msg)
    end

    @testset "parse_enum spelling matches origin/main lowercase+strip" begin
        @test AgentRuleLint.parse_enum(AgentRuleLint.OutputFormat.T, " JSON ") ===
            AgentRuleLint.OutputFormat.JSON
        @test AgentRuleLint.parse_enum(AgentRuleLint.OutputFormat.T, "Human") ===
            AgentRuleLint.OutputFormat.HUMAN
        err = @test_throws AgentRuleLint.ConfigError AgentRuleLint.parse_enum(
            AgentRuleLint.OutputFormat.T,
            "yaml",
        )
        @test err.value isa AgentRuleLint.ConfigError
    end
end
