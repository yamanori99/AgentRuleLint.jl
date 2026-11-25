@testset "fail-closed guards (no src mutation)" begin
    @testset "diff: unknown name-status raises GitError" begin
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("X\0x\0")
    end

    @testset "explain: invalid config exits 2" begin
        dir = mktempdir()
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), "agentrulelint_version = \"=99.99.99\"\n")
            code = cd(dir) do
                AgentRuleLint.cli_main(["explain", "test-integrity"])
            end
            @test code == 2
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
