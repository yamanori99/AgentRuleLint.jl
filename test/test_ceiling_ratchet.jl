@testset "ceiling ratchet" begin
    function init_git_repo!(dir)
        run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "agentrulelint@test"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "agentrulelint"]); dir = dir))
        return nothing
    end

    function minimal_cfg()
        ver = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(ver)\"

        [rules.ceiling-ratchet]
        level = \"forbid\"

        [[project_rules]]
        id = \"ratchet-lit\"
        level = \"deny\"
        paths = [\"hit.jl\"]
        forbid_literals = [\"CEILING_TOKEN\"]
        intent = \"\"
        do_not = \"\"
        """
    end

    function write_ceilings!(dir, body)
        mkpath(joinpath(dir, ".agentrulelint"))
        write(joinpath(dir, ".agentrulelint", "ceilings.toml"), body)
        return nothing
    end

    @testset "increase fails" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = \"CEILING_TOKEN\"\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            res = AgentRuleLint.check(dir)
            ratchet_hits = filter(
                d -> d.rule_id == "ceiling-ratchet" && d.path == "hit.jl",
                res.violations,
            )
            @test length(ratchet_hits) == 1
            @test occursin(
                "violation count increased for project/ratchet-lit at hit.jl: actual=1 ceiling=0",
                first(ratchet_hits).message,
            )
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "decrease requires lowering ceiling" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 1
                """,
            )
            res = AgentRuleLint.check(dir)
            ratchet_hits = filter(
                d -> d.rule_id == "ceiling-ratchet" && d.path == "hit.jl",
                res.violations,
            )
            @test length(ratchet_hits) == 1
            @test occursin(
                "violation count decreased for project/ratchet-lit at hit.jl: actual=0 ceiling=1 (run agentrulelint ratchet --write)",
                first(ratchet_hits).message,
            )
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "malformed and unknown rule id (exit 2 / ConfigError)" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "a.jl"), "1\n")
            write_ceilings!(dir, "bad_top = 1\n")
            err = try
                AgentRuleLint.check(dir)
                nothing
            catch e
                e
            end
            @test err isa AgentRuleLint.ConfigError
            @test err.msg == "malformed ceilings: unknown top-level key 'bad_top'"

            write_ceilings!(
                dir,
                """
                [violations."not-a-real-rule"]
                "a.jl" = 0
                """,
            )
            err2 = try
                AgentRuleLint.check(dir)
                nothing
            catch e
                e
            end
            @test err2 isa AgentRuleLint.ConfigError
            @test err2.msg == "unknown rule id in ceilings violations: not-a-real-rule"

            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "a.jl" = "x"
                """,
            )
            err3 = try
                AgentRuleLint.check(dir)
                nothing
            catch e
                e
            end
            @test err3 isa AgentRuleLint.ConfigError
            @test err3.msg ==
                "malformed ceilings: violations.project/ratchet-lit.\"a.jl\" must be an integer"
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "ratchet --write" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = \"CEILING_TOKEN\"\n")
            run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
            run(
                setenv(
                    Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c"]);
                    dir = dir,
                ),
            )
            cd(dir) do
                @test AgentRuleLint.cli_main(["ratchet", "--write"]) == 1
                @test isfile(joinpath(dir, ".agentrulelint", "ceilings.toml"))
                text = read(joinpath(dir, ".agentrulelint", "ceilings.toml"), String)
                @test occursin("[violations.\"project/ratchet-lit\"]", text)
                @test occursin("\"hit.jl\" = 1", text)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
