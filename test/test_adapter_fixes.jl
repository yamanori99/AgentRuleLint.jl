@testset "adapter correctness (JETLS fixes)" begin
    @testset "byte_to_col past line end" begin
        line = "aαb"
        @test AgentRuleLint.byte_to_col(line, ncodeunits(line) + 10) == length(line) + 1
        @test AgentRuleLint.byte_to_col(line, 1) == 1
    end

    @testset "git_diff_name_status" begin
        dir = abspath(mktempdir())
        try
            run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "agentrulelint@test"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "agentrulelint"]); dir = dir))
            write(joinpath(dir, "tracked.jl"), "1\n")
            run(setenv(Cmd(["git", "-C", dir, "add", "tracked.jl"]); dir = dir))
            run(
                setenv(
                    Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "initial"]);
                    dir = dir,
                ),
            )
            write(joinpath(dir, "new.jl"), "2\n")
            run(setenv(Cmd(["git", "-C", dir, "add", "new.jl"]); dir = dir))
            paths = AgentRuleLint.git_diff_name_status(dir, "HEAD")
            @test "new.jl" in paths
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "glob single-star segment" begin
        root = abspath(mktempdir())
        try
            mkpath(joinpath(root, "lib", "sub"))
            write(joinpath(root, "lib", "sub", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "miss.jl"), "x = \"INTERNAL_CODENAME\"\n")
            ver = string(pkgversion(AgentRuleLint))
            cfg = """
            agentrulelint_version = \"=$(ver)\"

            [[project_rules]]
            id = \"glob-star\"
            level = \"deny\"
            paths = [\"lib/*/hit.jl\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """
            write(joinpath(root, ".AgentRuleLintConfig.toml"), cfg)
            res = AgentRuleLint.check(root)
            hits = filter(d -> d.rule_id == "project/glob-star" && !d.suppressed, res.violations)
            paths = unique(d.path for d in hits)
            @test "lib/sub/hit.jl" in paths
            @test "lib/miss.jl" ∉ paths
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "expect block comment with expect text" begin
        src = "#= agentrulelint-expect: x reason=\"y\" =#\n"
        errs = AgentRuleLint.scan_block_comments(src)
        @test length(errs) == 1
        @test errs[1] == (1, "block comment expect forbidden")
    end

    @testset "String(UInt8[...]) fold" begin
        src = "s = String(UInt8[72, 73])\n"
        tree = AgentRuleLint.parse_source(src)
        folds = AgentRuleLint.collect_folded_string_exprs(tree, src)
        vals = [f.value for f in folds]
        @test "HI" in vals
    end
end
