@testset "bundled git ignores hostile global config" begin
    hostile_home = mktempdir()
    try
        hooks = joinpath(hostile_home, ".gitconfig")
        write(
            hooks,
            """
            [diff]
            \trenames = false
            """,
        )
        dir = mktempdir()
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "a.jl"), "1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "b.jl"), "2\n")
            git_commit_all!(dir, "head")
            env_clean = copy(ENV)
            env_hostile = copy(ENV)
            env_hostile["HOME"] = hostile_home
            out_clean = withenv(env_clean) do
                sprint() do io
                    redirect_stdout(io) do
                        AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    end
                end
            end
            out_hostile = withenv(env_hostile) do
                sprint() do io
                    redirect_stdout(io) do
                        AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    end
                end
            end
            @test out_clean == out_hostile
            out_clean_plain = withenv(env_clean) do
                sprint() do io
                    redirect_stdout(io) do
                        AgentRuleLint.check(dir)
                    end
                end
            end
            out_hostile_plain = withenv(env_hostile) do
                sprint() do io
                    redirect_stdout(io) do
                        AgentRuleLint.check(dir)
                    end
                end
            end
            @test out_clean_plain == out_hostile_plain
        finally
            rm(dir, recursive = true, force = true)
        end
    finally
        rm(hostile_home, recursive = true, force = true)
    end
end

@testset "plain check on non-repository fails closed for manifest-sync" begin
    dir = mktempdir()
    try
        write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
        err = try
            AgentRuleLint.check(dir)
            nothing
        catch e
            e
        end
        @test err isa AgentRuleLint.GitError
        @test occursin("manifest-sync", AgentRuleLint.sprint(showerror, err))
    finally
        rm(dir, recursive = true, force = true)
    end
end
