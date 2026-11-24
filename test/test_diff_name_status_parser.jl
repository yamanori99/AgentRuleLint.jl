@testset "git diff name-status parser (fail-closed)" begin
    @testset "copy C status (two paths)" begin
        payload = "C100\0old.toml\0new.toml\0"
        singles = AgentRuleLint._parse_diff_name_status_payload(payload)
        @test singles == [('C', "new.toml")]
        events = AgentRuleLint._parse_diff_path_events_payload(payload)
        @test length(events) == 1
        ev = first(events)
        @test ev.status == 'C'
        @test ev.old_path == "old.toml"
        @test ev.path == "new.toml"
    end

    @testset "unknown status" begin
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("U\0weird\0")
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_name_status_payload("X\0x\0")
    end

    @testset "truncated rename" begin
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("R100\0only-old\0")
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_name_status_payload("R100\0only-old\0")
    end

    @testset "truncated single-path record" begin
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("M\0")
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("A\0")
    end

    @testset "rename R status" begin
        payload = "R090\0a.jl\0b.jl\0"
        events = AgentRuleLint._parse_diff_path_events_payload(payload)
        @test length(events) == 1
        @test events[1].old_path == "a.jl"
        @test events[1].path == "b.jl"
    end
end
