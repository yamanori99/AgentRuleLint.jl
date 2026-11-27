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

    @testset "numstat map missing path throws GitError" begin
        @test_throws AgentRuleLint.GitError begin
            AgentRuleLint._numstat_lines_for_path(
                Dict("other.jl" => "1\t0\tother.jl"),
                Dict("other.jl" => "1\t0\tother.jl"),
                "missing.jl",
                true,
            )
        end
    end

    @testset "malformed numstat -z record throws GitError" begin
        @test_throws AgentRuleLint.GitError begin
            AgentRuleLint._parse_numstat_z_by_path("only-one-field\0path.jl")
        end
    end

    @testset "malformed numstat line throws GitError" begin
        @test_throws AgentRuleLint.GitError begin
            AgentRuleLint._numstat_totals("not-a-number\talso-bad\tpath.jl\n")
        end
    end

    @testset "numstat binary probe fails closed without hunks" begin
        @test_throws AgentRuleLint.GitError begin
            AgentRuleLint._changed_lines_from_diff_output("", "", "-\t-\ttarget.jl", "target.jl")
        end
    end

    @testset "numstat text change without hunks fails closed" begin
        @test_throws AgentRuleLint.GitError begin
            AgentRuleLint._changed_lines_from_diff_output(
                "",
                "2\t1\ttarget.jl",
                "2\t1\ttarget.jl",
                "target.jl",
            )
        end
    end

    @testset "mode-only diff allows empty changed lines" begin
        body = """
        diff --git a/target.jl b/target.jl
        old mode 100644
        new mode 100755
        """
        lines = AgentRuleLint._changed_lines_from_diff_output(body, "", "", "target.jl")
        @test isempty(lines)
    end

    @testset "pure rename metadata allows empty changed lines" begin
        body = """
        diff --git a/old.jl b/new.jl
        similarity index 100%
        rename from old.jl
        rename to new.jl
        """
        lines = AgentRuleLint._changed_lines_from_diff_output(body, "0\t0\tnew.jl", "", "new.jl")
        @test isempty(lines)
    end

    @testset "unicode path with space uses batched numstat keys" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            rel = "café x.jl"
            write(joinpath(dir, rel), "1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, rel), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "change")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, rel)
                @test 1 in lines
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                @test any(d -> d.rule_id == "project/diff-literal" && d.path == rel, res.violations)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "rename with edit reports changed lines" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(joinpath(dir, "src.jl"), "v = 1\n")
            git_commit_all!(dir, "base")
            run(setenv(Cmd(["git", "-C", dir, "mv", "src.jl", "dst.jl"]); dir = dir))
            write(joinpath(dir, "dst.jl"), "v = 1\nx = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "rename-edit")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, "dst.jl")
                @test !isempty(lines)
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                lit = filter(d -> d.rule_id == "project/diff-literal", res.violations)
                @test any(d -> d.path == "dst.jl", lit)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "batched numstat with gitattributes -diff on modified file" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(joinpath(dir, "target.jl"), "x = 1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, ".gitattributes"), "*.jl -diff\n")
            write(joinpath(dir, "target.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "attrs")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, "target.jl")
                @test 1 in lines
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "mode-only change in temp repo" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(joinpath(dir, "target.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "base")
            chmod(joinpath(dir, "target.jl"), 0o755)
            git_commit_all!(dir, "mode")
            cd(dir) do
                lines = AgentRuleLint.git_diff_changed_lines(dir, "HEAD^1", "target.jl")
                @test isempty(lines)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
