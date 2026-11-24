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
            @test isempty(ms_violations(dir))
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "positive manifest_format 2.1 with registries" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive_format_21"))
        try
            @test isempty(ms_violations(dir))
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "positive workspace" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive_workspace"))
        try
            @test isempty(ms_violations(dir))
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: manifest_format unsupported" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_manifest_format"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("manifest_format", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: project deps missing from manifest" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_missing_dep"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("missing from manifest", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: project deps UUID mismatch" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_uuid_mismatch"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("UUID mismatch", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: manifest internal deps closure" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_internal_closure"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("references missing dependency", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: manifest UUID uniqueness" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_duplicate_uuid"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("duplicate manifest UUID", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: Manifest-v filename vs julia_version" begin
        dir = init_git_fixture(joinpath(FIXTURES, "adversarial_versioned_name"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("disagrees with julia_version", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: diff mode stale project_hash" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive"))
        try
            proj = joinpath(dir, "Project.toml")
            proj_text = replace(read(proj, String), "julia = \"1.13\"" => "julia = \"1.12\"")
            write(proj, proj_text)
            viols = ms_violations(dir; diff_base = "HEAD")
            @test any(v -> occursin("project_hash is unchanged", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: undeclared extension trigger" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_extension_trigger"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("extension trigger", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: sources path disagree (warn)" begin
        dir = init_git_fixture(joinpath(FIXTURES, "warn_sources_mismatch"))
        try
            viols = ms_violations(dir)
            @test any(v -> v.level == :warn && occursin("sources path", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: workspace subproject manifest (warn)" begin
        dir = init_git_fixture(joinpath(FIXTURES, "warn_subproject_manifest"))
        try
            viols = ms_violations(dir)
            @test any(v -> v.level == :warn && occursin("workspace subproject", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "fixture prefix exempts corpus only" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_missing_dep"))
        try
            res = AgentRuleLint.check(ROOT; paths = String[])
            skipped = any(
                d -> startswith(d.path, "test/corpus/manifest_sync/"),
                filter(
                    d -> d.rule_id == "manifest-sync" && !d.suppressed,
                    res.violations,
                ),
            )
            @test !skipped
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "manifests outside fixture prefix are still checked" begin
        dir = abspath(mktempdir())
        try
            vendor = joinpath(dir, "vendor", "pkg")
            mkpath(vendor)
            cp(joinpath(FIXTURES, "negative_missing_dep"), vendor; force = true)
            run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "t@test"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "t"]); dir = dir))
            copy_config!(dir)
            run(Cmd(["git", "-C", dir, "add", "-A"]))
            run(setenv(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init"]); dir = dir))
            viols = ms_violations(dir)
            @test any(v -> v.path == "vendor/pkg/Project.toml" && occursin("missing from manifest", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "dogfood full-tree tracked root Manifest" begin
        res = AgentRuleLint.check(ROOT; paths = String[])
        ms = filter(d -> d.rule_id == "manifest-sync" && !d.suppressed, res.violations)
        @test isempty(ms)
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

    @testset "explain CLI" begin
        cd(ROOT) do
            @test AgentRuleLint.cli_main(["explain", "manifest-sync"]) == 0
        end
    end
end
