@testset "fail-closed guards (no src mutation)" begin
    @testset "diff: unknown name-status raises GitError" begin
        @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload("X\0x\0")
    end

    @testset "explain: invalid config exits 2" begin
        dir = mktempdir()
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), "agentrulelint_version = \"=99.99.99\"\n")
            err_path = tempname()
            code = cd(dir) do
                open(err_path, "w") do err_io
                    redirect_stderr(err_io) do
                        AgentRuleLint.cli_main(["explain", "test-integrity"])
                    end
                end
            end
            err = read(err_path, String)
            rm(err_path; force = true)
            @test code == 2
            @test occursin("99.99.99", err)
            @test occursin("agentrulelint_version", err)
            @test !occursin("unknown rule id", err)
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
