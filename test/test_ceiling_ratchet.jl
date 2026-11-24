@testset "ceiling ratchet" begin
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

    @testset "expect count implicit ceiling zero" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(
                joinpath(dir, "hit.jl"),
                "# agentrulelint-expect: project/ratchet-lit reason=\"r\"\nx = 1\n",
            )
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            res = AgentRuleLint.check(dir)
            hits = filter(
                d -> d.rule_id == "ceiling-ratchet" && occursin("expect count increased", d.message),
                res.violations,
            )
            @test length(hits) == 1
            @test occursin(
                "expect count increased for project/ratchet-lit at hit.jl: actual=1 ceiling=0",
                first(hits).message,
            )
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "unresolvable diff base is fail-closed (not absent ceilings)" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            git_commit_all!(dir, "base")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 9
                """,
            )
            git_commit_all!(dir, "raised working tree irrelevant")
            cd(dir) do
                err = try
                    AgentRuleLint.check(dir; diff_base = "not-a-real-ref")
                    nothing
                catch e
                    e
                end
                @test err isa AgentRuleLint.GitError
                @test occursin("diff base ref not available: not-a-real-ref", AgentRuleLint.sprint(showerror, err))
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff mode rejects new ceilings when base had no file" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            git_commit_all!(dir, "base without ceilings file")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 3
                """,
            )
            git_commit_all!(dir, "add ceilings")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(
                    d -> d.rule_id == "ceiling-ratchet" && occursin("new violation ceiling", d.message),
                    res.violations,
                )
                @test length(hits) == 1
                @test occursin("working=3", first(hits).message)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff mode compares when base had ceilings file" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "base with ceilings")
            write(joinpath(dir, "hit.jl"), "x = 2\n")
            git_commit_all!(dir, "touch hit.jl ceilings unchanged")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                @test !any(d -> d.rule_id == "ceiling-ratchet", res.violations)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "git show fails closed when blob object is missing" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "commit with ceilings blob")
            blob_sha = strip(
                String(
                    read(Cmd(["git", "-C", dir, "rev-parse", "HEAD:.agentrulelint/ceilings.toml"])),
                ),
            )
            obj_path = joinpath(dir, ".git", "objects", blob_sha[1:2], blob_sha[3:end])
            rm(obj_path; force = true)
            cd(dir) do
                err = try
                    AgentRuleLint.check(dir; diff_base = "HEAD")
                    nothing
                catch e
                    e
                end
                @test err isa AgentRuleLint.GitError
                @test occursin("failed to read .agentrulelint/ceilings.toml", AgentRuleLint.sprint(showerror, err))
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff mode rejects raised ceilings file" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "base")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 5
                """,
            )
            git_commit_all!(dir, "raise ceilings")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(
                    d -> d.rule_id == "ceiling-ratchet" && occursin("ceiling raised", d.message),
                    res.violations,
                )
                @test length(hits) == 1
                @test occursin("base=0 working=5", first(hits).message)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff mode rejects removed ceilings file" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "base")
            rm(joinpath(dir, ".agentrulelint", "ceilings.toml"))
            git_commit_all!(dir, "delete ceilings")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                hits = filter(d -> d.rule_id == "ceiling-ratchet", res.violations)
                @test any(occursin("ceilings.toml removed relative to diff base", d.message) for d in hits)
            end
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

    @testset "TOML round-trip with special path keys" begin
        dir = abspath(mktempdir())
        try
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            policy = AgentRuleLint.resolve_policy(dir)
            weird = "src/\"weird\".jl"
            entry = AgentRuleLint.CeilingEntry(
                Dict("project/ratchet-lit" => Dict(weird => 2)),
                Dict{String, Dict{String, Int}}(),
            )
            path = joinpath(dir, ".agentrulelint", "ceilings.toml")
            mkpath(dirname(path))
            AgentRuleLint.write_ceilings_toml!(path, entry)
            loaded = AgentRuleLint.load_ceilings(dir, policy)
            @test loaded.violations["project/ratchet-lit"][weird] == 2
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "ratchet --write excludes ceiling-ratchet diagnostics" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = \"CEILING_TOKEN\"\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "c")
            cd(dir) do
                AgentRuleLint.cli_main(["ratchet", "--write"]) == 1
                loaded = AgentRuleLint.load_ceilings(dir, AgentRuleLint.resolve_policy(dir))
                @test !haskey(loaded.violations, "ceiling-ratchet")
                @test get(loaded.violations["project/ratchet-lit"], "hit.jl", 0) == 1
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "ratchet --write with path merges out-of-scope entries" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "hit.jl"), "x = \"CEILING_TOKEN\"\n")
            write(joinpath(dir, "other.jl"), "y = 1\n")
            write_ceilings!(
                dir,
                """
                [violations."project/ratchet-lit"]
                "other.jl" = 3
                "hit.jl" = 0
                """,
            )
            git_commit_all!(dir, "c")
            cd(dir) do
                @test AgentRuleLint.cli_main(["ratchet", "--write", "hit.jl"]) == 1
                loaded = AgentRuleLint.load_ceilings(dir, AgentRuleLint.resolve_policy(dir))
                @test loaded.violations["project/ratchet-lit"]["other.jl"] == 3
                @test loaded.violations["project/ratchet-lit"]["hit.jl"] == 1
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
