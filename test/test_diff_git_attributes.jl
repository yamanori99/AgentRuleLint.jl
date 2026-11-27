@testset "diff gitattributes hardening" begin
    function init_git_repo!(dir)
        run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "agentrulelint@test"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "agentrulelint"]); dir = dir))
        return nothing
    end

    function git_commit_all!(dir, msg)
        run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
        run(
            setenv(
                Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", msg]);
                dir = dir,
            ),
        )
        return nothing
    end

    function hardening_cfg()
        ver = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(ver)\"

        [rules.protected-paths]
        level = \"forbid\"

        [[project_rules]]
        id = \"diff-literal\"
        level = \"deny\"
        paths = [\"**\"]
        forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
        intent = \"\"
        do_not = \"\"
        """
    end

    function assert_attrs_literal_and_protected!(dir, attr_line::String)
        init_git_repo!(dir)
        write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
        write(joinpath(dir, "target.jl"), "x = 1\n")
        git_commit_all!(dir, "base")
        write(joinpath(dir, ".gitattributes"), attr_line)
        write(joinpath(dir, "target.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
        git_commit_all!(dir, "attrs")
        cd(dir) do
            res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
            lit = filter(d -> d.rule_id == "project/diff-literal", res.violations)
            prot = filter(d -> d.rule_id == "protected-paths", res.violations)
            @test res.exit_code == 1
            @test length(lit) == 1
            @test first(lit).path == "target.jl"
            @test any(d -> d.path == ".gitattributes", prot)
        end
        return nothing
    end

    @testset "gitattributes -diff still reports literal" begin
        dir = abspath(mktempdir())
        try
            assert_attrs_literal_and_protected!(dir, "*.jl -diff\n")
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "gitattributes binary still reports literal" begin
        dir = abspath(mktempdir())
        try
            assert_attrs_literal_and_protected!(dir, "*.jl binary\n")
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "protected-paths on gitattributes and gitmodules alone" begin
        for (rel, content, label) in (
            (".gitattributes", "*.jl -diff\n", "gitattributes"),
            (".gitmodules", "[submodule \"x\"]\n\tpath = vendor\n\turl = https://example.invalid/x.git\n", "gitmodules"),
        )
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                write(joinpath(dir, "keep.jl"), "1\n")
                git_commit_all!(dir, "base")
                write(joinpath(dir, rel), content)
                git_commit_all!(dir, label)
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    hits = filter(
                        d -> d.rule_id == "protected-paths" && d.path == rel,
                        res.violations,
                    )
                    @test res.exit_code == 1
                    @test length(hits) == 1
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end
    end

    @testset "binary-only diff body fails closed" begin
        body = """
        diff --git a/target.jl b/target.jl
        index 7d4290a..46368f1 100644
        Binary files a/target.jl and b/target.jl differ
        """
        err = try
            AgentRuleLint._changed_lines_from_diff_body(body, "target.jl")
            nothing
        catch e
            e
        end
        @test err isa AgentRuleLint.GitError
        @test occursin("binary-only", AgentRuleLint.sprint(showerror, err))
    end

    @testset "mode-only diff allows empty changed lines" begin
        body = """
        diff --git a/target.jl b/target.jl
        old mode 100644
        new mode 100755
        """
        lines = AgentRuleLint._changed_lines_from_diff_body(body, "target.jl")
        @test isempty(lines)
    end
end