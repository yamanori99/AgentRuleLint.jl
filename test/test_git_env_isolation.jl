@testset "git child env isolation" begin
    @testset "inherited GIT_CONFIG_COUNT does not change check" begin
        dir = abspath(mktempdir())
        hostile = mktempdir()
        try
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
            rm(hostile, recursive = true, force = true)
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "default HOME/.config/git/attributes ignored (XDG unset)" begin
        dir = abspath(mktempdir())
        home = abspath(mktempdir())
        try
            rename_diff_literal_isolation_fixture(dir)
            hostile_default_xdg_attributes_under_home!(home)
            base = GIT_ISOLATION_DIFF_BASE
            res_clean = AgentRuleLint.check(dir; diff_base = base)
            res_home = withenv("HOME" => home, "XDG_CONFIG_HOME" => nothing) do
                AgentRuleLint.check(dir; diff_base = base)
            end
            @test res_clean.complete && res_home.complete
            @test active_violation_paths(res_clean) == active_violation_paths(res_home)
            @test res_clean.exit_code == res_home.exit_code
        finally
            rm(home, recursive = true, force = true)
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "default XDG_CONFIG_HOME/git/attributes ignored" begin
        dir = abspath(mktempdir())
        xdg = abspath(mktempdir())
        home = abspath(mktempdir())
        try
            rename_diff_literal_isolation_fixture(dir)
            hostile_default_xdg_attributes_under_xdg!(xdg)
            base = GIT_ISOLATION_DIFF_BASE
            res_clean = AgentRuleLint.check(dir; diff_base = base)
            res_xdg = withenv("XDG_CONFIG_HOME" => xdg, "HOME" => home) do
                AgentRuleLint.check(dir; diff_base = base)
            end
            @test res_clean.complete && res_xdg.complete
            @test active_violation_paths(res_clean) == active_violation_paths(res_xdg)
            @test res_clean.exit_code == res_xdg.exit_code
        finally
            rm(xdg, recursive = true, force = true)
            rm(home, recursive = true, force = true)
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
