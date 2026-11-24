@testset "manifest-sync" begin
    FIXTURES = joinpath(ROOT, "test", "corpus", "manifest_sync")

    function copy_config!(root::AbstractString)
        ver = string(pkgversion(AgentRuleLint))
        cfg = """
        agentrulelint_version = \"=$(ver)\"

        [rules.manifest-sync]
        level = \"deny\"
        intent = \"test\"
        do_not = \"test\"
        """
        write(joinpath(root, ".AgentRuleLintConfig.toml"), cfg)
    end

    function init_git_fixture(src::AbstractString)
        dir = abspath(mktempdir())
        cp(src, dir; force = true)
        run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "t@test"]); dir = dir))
        run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "t"]); dir = dir))
        copy_config!(dir)
        run(Cmd(["git", "-C", dir, "add", "-A"]))
        run(setenv(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init"]); dir = dir))
        return dir
    end

    function ms_violations(root::AbstractString; kwargs...)
        res = AgentRuleLint.check(root; paths = String[], kwargs...)
        return filter(d -> d.rule_id == "manifest-sync" && !d.suppressed, res.violations)
    end

    @testset "positive minimal pair" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive"))
        try
            viols = ms_violations(dir)
            @test isempty(viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "positive workspace" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive_workspace"))
        try
            viols = ms_violations(dir)
            @test isempty(viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "negative missing dep" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_missing_dep"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("missing from manifest", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "negative manifest_format" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_manifest_format"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("manifest_format", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "adversarial Manifest-v filename mismatch" begin
        dir = init_git_fixture(joinpath(FIXTURES, "adversarial_versioned_name"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("disagrees with julia_version", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "unparseable manifest fail-closed" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive"))
        bad = joinpath(dir, "Manifest.toml")
        try
            write(bad, "manifest_format = \"2.0\"\n[[deps.Foo\n")
            @test_throws AgentRuleLint.ParseError ms_violations(dir)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "diff project_hash stale" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive"))
        try
            proj = joinpath(dir, "Project.toml")
            proj_text = read(proj, String)
            proj_text = replace(proj_text, "julia = \"1.13\"" => "julia = \"1.12\"")
            write(proj, proj_text)
            run(Cmd(["git", "-C", dir, "add", "Project.toml"]))
            viols = ms_violations(dir; diff_base = "HEAD")
            @test any(v -> occursin("project_hash is unchanged", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "explain CLI" begin
        cd(ROOT) do
            @test AgentRuleLint.cli_main(["explain", "manifest-sync"]) == 0
        end
    end
end
