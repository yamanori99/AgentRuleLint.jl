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
        @test_throws AgentRuleLint.GitError r"missing path=missing\.jl" begin
            AgentRuleLint._numstat_lines_for_path(
                Dict("other.jl" => "1\t0\tother.jl"),
                Dict("other.jl" => "1\t0\tother.jl"),
                "missing.jl",
                true,
            )
        end
    end

    @testset "malformed numstat -z record throws GitError" begin
        @test_throws AgentRuleLint.GitError r"malformed git diff --numstat -z" begin
            AgentRuleLint._parse_numstat_z_by_path("only-one-field\0path.jl")
        end
    end

    @testset "malformed numstat line throws GitError" begin
        @test_throws AgentRuleLint.GitError r"malformed git diff --numstat" begin
            AgentRuleLint._numstat_totals("not-a-number\talso-bad\tpath.jl\n")
        end
    end

    @testset "numstat binary probe fails closed without hunks" begin
        @test_throws AgentRuleLint.GitError r"numstat probe binary" begin
            AgentRuleLint._changed_lines_from_diff_output("", "", "-\t-\ttarget.jl", "target.jl")
        end
    end

    @testset "numstat text change without hunks fails closed" begin
        @test_throws AgentRuleLint.GitError r"without hunks" begin
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
            write(joinpath(dir, "src.jl"), "v=1\n")
            git_commit_all!(dir, "base")
            run(setenv(Cmd(["git", "-C", dir, "mv", "src.jl", "dst.jl"]); dir = dir))
            git_commit_all!(dir, "rename only")
            write(joinpath(dir, "dst.jl"), "v=1\nx=\"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "add literal on line two")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, "dst.jl")
                @test AgentRuleLint.diff_path_status(scope, "dst.jl") == 'M'
                @test lines == Set([2])
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                lit = filter(d -> d.rule_id == "project/diff-literal", res.violations)
                @test any(d -> d.path == "dst.jl", lit)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "rename and copy destination whole-file scope (real git)" begin
        function wc_physical_line_set(abspath_file::AbstractString)
            wc_line = strip(read(Cmd(["wc", "-l", abspath_file]), String))
            n = parse(Int, first(split(wc_line)))
            return Set(1:max(n, 1))
        end

        function path_scoped_literal_cfg()
            ver = string(pkgversion(AgentRuleLint))
            return """
            agentrulelint_version = \"=$(ver)\"

            [rules.protected-paths]
            level = \"forbid\"

            [[project_rules]]
            id = \"src-only-literal\"
            level = \"deny\"
            paths = [\"src/**\"]
            forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
            intent = \"\"
            do_not = \"\"

            [[project_rules]]
            id = \"diff-literal\"
            level = \"deny\"
            paths = [\"**\"]
            forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
            intent = \"\"
            do_not = \"\"
            """
        end

        @testset "pure rename without content change" begin
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                write(joinpath(dir, "old.jl"), "alpha\nbeta\n")
                git_commit_all!(dir, "base")
                run(setenv(Cmd(["git", "-C", dir, "mv", "old.jl", "new.jl"]); dir = dir))
                git_commit_all!(dir, "rename only")
                dest = joinpath(dir, "new.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "new.jl") == 'R'
                    @test AgentRuleLint.diff_changed_lines(scope, "new.jl") == wc_physical_line_set(dest)
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    @test res.exit_code == 0
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end

        @testset "rename with small similarity-preserving edit" begin
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                write(joinpath(dir, "src.jl"), "v=1\n")
                git_commit_all!(dir, "base")
                run(setenv(Cmd(["git", "-C", dir, "mv", "src.jl", "dst.jl"]); dir = dir))
                write(joinpath(dir, "dst.jl"), "v=1\nx=2\n")
                git_commit_all!(dir, "rename and add one line")
                dest = joinpath(dir, "dst.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "dst.jl") == 'R'
                    @test AgentRuleLint.diff_changed_lines(scope, "dst.jl") == wc_physical_line_set(dest)
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end

        @testset "copy-like add is status A with whole file" begin
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                body = join(["line" * string(i) for i in 1:20], "\n") * "\n"
                write(joinpath(dir, "src.jl"), body)
                git_commit_all!(dir, "base")
                write(joinpath(dir, "cp.jl"), body * "tail\n")
                git_commit_all!(dir, "copy-like add")
                dest = joinpath(dir, "cp.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "cp.jl") == 'A'
                    @test AgentRuleLint.diff_changed_lines(scope, "cp.jl") == wc_physical_line_set(dest)
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    @test res.exit_code == 0
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end

        @testset "rename into path-scoped rule reports unedited lines" begin
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), path_scoped_literal_cfg())
                mkpath(joinpath(dir, "test"))
                write(
                    joinpath(dir, "test", "moved.jl"),
                    "x = \"FORBIDDEN_DIFF_TOKEN\"\nallowed\n",
                )
                git_commit_all!(dir, "base")
                mkpath(joinpath(dir, "src"))
                run(
                    setenv(
                        Cmd(["git", "-C", dir, "mv", "test/moved.jl", "src/moved.jl"]);
                        dir = dir,
                    ),
                )
                write(joinpath(dir, "src", "moved.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\nallowed\nedit\n")
                git_commit_all!(dir, "rename and edit line three")
                dest = joinpath(dir, "src", "moved.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "src/moved.jl") == 'R'
                    @test AgentRuleLint.diff_changed_lines(scope, "src/moved.jl") ==
                        wc_physical_line_set(dest)
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    src_hits = filter(
                        d -> d.rule_id == "project/src-only-literal" && d.path == "src/moved.jl",
                        res.violations,
                    )
                    @test res.exit_code == 1
                    @test length(src_hits) == 1
                    @test first(src_hits).span.start_line == 1
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end

        @testset "rename with deletion-only edit" begin
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                write(joinpath(dir, "src.jl"), "keep\nbad\ntail\n")
                git_commit_all!(dir, "base")
                run(setenv(Cmd(["git", "-C", dir, "mv", "src.jl", "dst.jl"]); dir = dir))
                write(joinpath(dir, "dst.jl"), "keep\ntail\n")
                git_commit_all!(dir, "rename and delete middle")
                dest = joinpath(dir, "dst.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "dst.jl") == 'R'
                    @test AgentRuleLint.diff_changed_lines(scope, "dst.jl") ==
                        wc_physical_line_set(dest)
                end
            finally
                rm(dir, recursive = true, force = true)
            end
        end

        @testset "added file line count matches wc -l" begin
            @test AgentRuleLint._newline_delimited_line_count("a\nb\n") == 2
            @test AgentRuleLint._newline_delimited_line_count("a\nb") == 2
            dir = abspath(mktempdir())
            try
                init_git_repo!(dir)
                write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
                write(joinpath(dir, "keep.jl"), "1\n")
                git_commit_all!(dir, "base")
                write(joinpath(dir, "new.jl"), "safe\nx = \"FORBIDDEN_DIFF_TOKEN\"\n")
                git_commit_all!(dir, "add file")
                dest = joinpath(dir, "new.jl")
                cd(dir) do
                    scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                    @test AgentRuleLint.diff_path_status(scope, "new.jl") == 'A'
                    lines = AgentRuleLint.diff_changed_lines(scope, "new.jl")
                    @test lines == wc_physical_line_set(dest)
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    lit = filter(
                        d -> d.rule_id == "project/diff-literal" && d.path == "new.jl",
                        res.violations,
                    )
                    @test length(lit) == 1
                    @test first(lit).span.start_line == 2
                end
            finally
                rm(dir, recursive = true, force = true)
            end
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

    @testset "hunk line counts disagree with numstat throws GitError" begin
        body = "@@ -10,3 +10,1 @@\n"
        @test_throws AgentRuleLint.GitError r"path=target\.jl" begin
            AgentRuleLint._changed_lines_from_diff_output(
                body,
                "2\t3\ttarget.jl",
                "2\t3\ttarget.jl",
                "target.jl",
            )
        end
    end

    @testset "deletion-only hunk in temp repo" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(
                joinpath(dir, "target.jl"),
                "keep = 1\nx = \"FORBIDDEN_DIFF_TOKEN\"\ntail = 3\n",
            )
            git_commit_all!(dir, "base")
            write(joinpath(dir, "target.jl"), "keep = 1\ntail = 3\n")
            git_commit_all!(dir, "delete middle line")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, "target.jl")
                @test isempty(lines)
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                lit = filter(d -> d.rule_id == "project/diff-literal", res.violations)
                @test isempty(lit)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "deletion and addition hunks report only new lines" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(joinpath(dir, "target.jl"), "a = 1\nb = 2\nc = 3\n")
            git_commit_all!(dir, "base")
            write(
                joinpath(dir, "target.jl"),
                "a = \"FORBIDDEN_DIFF_TOKEN\"\nb = 2\n",
            )
            git_commit_all!(dir, "delete tail and edit head")
            cd(dir) do
                scope = AgentRuleLint.build_diff_scope(dir, "HEAD^1")
                lines = AgentRuleLint.diff_changed_lines(scope, "target.jl")
                @test lines == Set([1])
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                lit = filter(
                    d -> d.rule_id == "project/diff-literal" && !d.suppressed,
                    res.violations,
                )
                @test length(lit) == 1
                @test first(lit).span.start_line == 1
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "whole file deletion in temp repo" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), hardening_cfg())
            write(joinpath(dir, "gone.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "base")
            rm(joinpath(dir, "gone.jl"))
            git_commit_all!(dir, "delete file")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                lit = filter(d -> d.rule_id == "project/diff-literal", res.violations)
                @test isempty(lit)
                @test res.exit_code == 0
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
