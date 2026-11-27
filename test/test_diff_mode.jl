@testset "diff mode (--diff)" begin
    function minimal_project_cfg()
        ver = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(ver)\"

        [[project_rules]]
        id = \"diff-literal\"
        level = \"deny\"
        paths = [\"**\"]
        forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
        intent = \"\"
        do_not = \"\"
        """
    end

    @testset "changed-line selection" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "target.jl"), "x = 1\ny = 2\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "target.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\ny = 2\n")
            git_commit_all!(dir, "change line 1 only")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(
                    d -> d.rule_id == "project/diff-literal" && !d.suppressed,
                    res.violations,
                )
                @test length(hits) == 1
                @test first(hits).span.start_line == 1
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "new and renamed files" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "oldname.jl"), "1\n")
            git_commit_all!(dir, "base")
            mv(joinpath(dir, "oldname.jl"), joinpath(dir, "renamed.jl"))
            write(joinpath(dir, "renamed.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            write(joinpath(dir, "brand_new.jl"), "y = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "rename and add")
            cd(dir) do
                entries = AgentRuleLint.git_diff_name_status(dir, "HEAD^1")
                paths = Set(p for (_, p) in entries)
                @test "renamed.jl" in paths
                @test "brand_new.jl" in paths
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                vpaths = Set(d.path for d in res.violations if d.rule_id == "project/diff-literal")
                @test "brand_new.jl" in vpaths
                @test "renamed.jl" in vpaths
                @test "oldname.jl" ∉ vpaths
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "deleted files excluded from lint" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "gone.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "base")
            rm(joinpath(dir, "gone.jl"))
            git_commit_all!(dir, "delete")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                @test !any(d -> d.path == "gone.jl", res.violations)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "merge commit uses first parent (HEAD^1)" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "merge_me.jl"), "ok = 1\n")
            git_commit_all!(dir, "main base")
            run_git_cmd(dir, "checkout", "-q", "-b", "side"; cwd = dir)
            write(joinpath(dir, "side_only.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "side commit")
            run_git_cmd(dir, "checkout", "-q", "main"; cwd = dir)
            run(
                setenv(
                    Cmd(
                        [
                            "git",
                            "-C",
                            dir,
                            "-c",
                            "commit.gpgsign=false",
                            "merge",
                            "--no-edit",
                            "side",
                        ]
                    );
                    dir = dir,
                ),
            )
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                scope_paths = Set(f.path for f in scope.files)
                @test "side_only.jl" in scope_paths
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "empty diff does not fall back to full repo" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "quiet.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "base")
            run_git_cmd(
                dir,
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--allow-empty",
                "-q",
                "-m",
                "empty";
                cwd = dir,
            )
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                @test res.violation_count == 0
                @test isempty(res.violations)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "fail-closed git errors (exact messages)" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            err = try
                AgentRuleLint.check(dir; diff_base = "HEAD^1")
                nothing
            catch e
                e
            end
            @test err isa AgentRuleLint.GitError
            @test occursin("not a git repository", err.msg)

            init_git_repo!(dir)
            write(joinpath(dir, "a.jl"), "1\n")
            git_commit_all!(dir, "one")
            err2 = try
                AgentRuleLint.check(dir; diff_base = "HEAD^1")
                nothing
            catch e
                e
            end
            @test err2 isa AgentRuleLint.GitError
            @test occursin(
                "diff base ref not available: HEAD^1 (shallow clone or single-parent HEAD)",
                AgentRuleLint.sprint(showerror, err2),
            )

            err3 = try
                AgentRuleLint.check(dir; diff_base = "not-a-real-ref")
                nothing
            catch e
                e
            end
            @test err3 isa AgentRuleLint.GitError
            @test occursin("diff base ref not available: not-a-real-ref", AgentRuleLint.sprint(showerror, err3))
        finally
            rm(dir, recursive = true, force = true)
        end

    end

    @testset "CLI --diff default HEAD^1" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
            write(joinpath(dir, "t.jl"), "1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "t.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "hit")
            cd(dir) do
                @test AgentRuleLint.cli_main(["check", "--diff"]) == 1
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
