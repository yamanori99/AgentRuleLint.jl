@testset "git child env isolation" begin
    @testset "inherited GIT_CONFIG_COUNT does not change check" begin
        dir = abspath(mktempdir())
        try
            hostile = mktempdir()
            rename_diff_literal_isolation_fixture(dir)
            attr = joinpath(hostile, "attrs")
            write(attr, "*.jl -diff\n")
            base = GIT_ISOLATION_DIFF_BASE
            res_clean = AgentRuleLint.check(dir; diff_base = base)
            res_injected = withenv(
                "GIT_CONFIG_COUNT" => "1",
                "GIT_CONFIG_KEY_0" => "core.attributesfile",
                "GIT_CONFIG_VALUE_0" => attr,
            ) do
                AgentRuleLint.check(dir; diff_base = base)
            end
            @test active_violation_paths(res_clean) == active_violation_paths(res_injected)
            @test res_clean.exit_code == res_injected.exit_code
            @test res_clean.complete && res_injected.complete
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "inherited GIT_DIR / GIT_WORK_TREE does not change check" begin
        dir = abspath(mktempdir())
        decoy = abspath(mktempdir())
        try
            rename_diff_literal_isolation_fixture(dir)
            init_git_repo!(decoy)
            write(joinpath(decoy, "noise.jl"), "x = 1\n")
            git_commit_all!(decoy, "decoy")
            base = GIT_ISOLATION_DIFF_BASE
            res_clean = AgentRuleLint.check(dir; diff_base = base)
            res_poisoned = withenv(
                "GIT_DIR" => joinpath(decoy, ".git"),
                "GIT_WORK_TREE" => decoy,
            ) do
                AgentRuleLint.check(dir; diff_base = base)
            end
            @test active_violation_paths(res_clean) == active_violation_paths(res_poisoned)
            @test res_clean.exit_code == res_poisoned.exit_code
            @test res_clean.complete && res_poisoned.complete
        finally
            rm(dir, recursive = true, force = true)
            rm(decoy, recursive = true, force = true)
        end
    end
end
