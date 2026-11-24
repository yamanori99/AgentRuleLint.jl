@testset "test-integrity rule" begin
    root = ROOT
    cfg = read(joinpath(root, ".AgentRuleLintConfig.toml"), String)

    function check_rel(rel)
        return AgentRuleLint.check(root; paths = [rel])
    end

    function ti_hits(rel)
        res = check_rel(rel)
        return filter(d -> d.rule_id == "test-integrity" && !d.suppressed, res.violations)
    end

    rel(p) = joinpath("test", "corpus", p)

    @testset "syntax mode detectors" begin
        trivial = ti_hits(rel("test_integrity_trivial_true.jl"))
        @test any(d -> occursin("trivially true", d.message), trivial)
        @test length(trivial) >= 2

        valid = ti_hits(rel("test_integrity_valid.jl"))
        @test isempty(valid)

        evasion = ti_hits(rel("test_integrity_const_fold.jl"))
        @test any(d -> occursin("trivially true", d.message), evasion)

        broad = ti_hits(rel("test_integrity_broad_throws.jl"))
        @test length(broad) >= 2
        @test all(d -> occursin("overly broad", d.message), broad)
    end

    @testset "explain" begin
        out = AgentRuleLint.explain_rule("test-integrity")
        @test occursin("constant folding", out)
        @test occursin("do_not:", out)
    end

    function init_git_repo!(dir)
        run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "ti@test"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "ti"]); dir = dir))
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

    @testset "diff: skip count and runtests removal" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
            mkpath(joinpath(dir, "test"))
            write(joinpath(dir, "test", "runtests.jl"), "include(\"case.jl\")\n")
            write(joinpath(dir, "test", "case.jl"), "@test 1 == 1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "test", "case.jl"), "@test 1 == 1\n@test_skip false\n")
            write(
                joinpath(dir, "test", "runtests.jl"),
                "# removed include\n",
            )
            git_commit_all!(dir, "weaken")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(d -> d.rule_id == "test-integrity" && !d.suppressed, res.violations)
                @test any(d -> occursin("test_skip count increased", d.message), hits)
                @test any(d -> occursin("removed from test/runtests.jl", d.message), hits)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff: atol loosening" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
            mkpath(joinpath(dir, "test"))
            write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1e-12)\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1e-3)\n")
            git_commit_all!(dir, "loose")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(d -> d.rule_id == "test-integrity" && !d.suppressed, res.violations)
                @test any(d -> occursin("tolerance loosened", d.message), hits)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "exit and Base.exit in driver" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
            mkpath(joinpath(dir, "test"))
            write(joinpath(dir, "test", "runtests.jl"), "include(\"early.jl\")\n")
            write(joinpath(dir, "test", "early.jl"), "Base.exit(0)\n@test true\n")
            res = AgentRuleLint.check(dir; paths = ["test"])
            hits = filter(d -> d.rule_id == "test-integrity" && occursin("exit", d.message), res.violations)
            @test !isempty(hits)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "mutation guard: trivial @test corpus" begin
        hits = ti_hits(rel("test_integrity_trivial_true.jl"))
        @test !isempty(hits)
    end

    @testset "named atol constant is a documented blind spot" begin
        @test isempty(ti_hits(rel("test_integrity_named_tol_limit.jl")))
    end
end
