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
        write(joinpath(root, ".AgentRuleLint.jl.toml"), cfg)
    end

    function materialize_toml_fixtures!(root::AbstractString)
        for (dir, _, files) in walkdir(root)
            for f in files
                endswith(f, ".toml.fixture") || continue
                src = joinpath(dir, f)
                dest = joinpath(dir, replace(f, ".fixture" => ""))
                cp(src, dest; force = true)
            end
        end
        return nothing
    end

    function init_git_fixture(src::AbstractString)
        dir = abspath(mktempdir())
        cp(src, dir; force = true)
        materialize_toml_fixtures!(dir)
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

    @testset "positive manifest_format 2.2 with environment metadata" begin
        dir = init_git_fixture(joinpath(FIXTURES, "positive_format_22"))
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

    @testset "detector: unexpected manifest top-level key" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_unknown_top_level"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("unexpected manifest top-level key", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: format 2.1 with format-2.2-only top-level key" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_format_21_with_22_key"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("unexpected manifest top-level key", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: tracked manifest without tracked Project.toml" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_orphan_manifest"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("tracked manifest has no tracked Project.toml", v.message), viols)
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

    @testset "detector: invalid julia_version in versioned manifest" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_invalid_julia_version"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("invalid julia_version in manifest", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "detector: multiple Project.toml claim same manifest" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_duplicate_manifest_claim"))
        try
            viols = ms_violations(dir)
            @test any(v -> occursin("claimed by multiple Project.toml", v.message), viols)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "parse error: sources entry not a table" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_sources_not_table"))
        try
            @test_throws AgentRuleLint.ParseError ms_violations(dir)
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

    @testset "manifest_sync corpus fixtures are not tracked as Project/Manifest" begin
        for p in split(strip(read(Cmd(`git -C $ROOT ls-files`), String)), '\n'; keepempty = false)
            startswith(p, "test/corpus/manifest_sync/") || continue
            @test endswith(p, ".toml.fixture")
        end
        res = AgentRuleLint.check(ROOT; paths = String[])
        ms = filter(d -> d.rule_id == "manifest-sync" && !d.suppressed, res.violations)
        @test all(v -> !startswith(v.path, "test/corpus/manifest_sync/"), ms)
    end

    @testset "manifests outside fixture prefix are still checked" begin
        OTHER = joinpath(ROOT, "test", "corpus", "other")
        dir = abspath(mktempdir())
        try
            cp(OTHER, joinpath(dir, "other"); force = true)
            proj = joinpath(dir, "other", "Project.toml")
            proj_text = read(proj, String)
            write(proj, replace(proj_text, "Foo" => "Bar", "22222222" => "33333333"))
            run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "t@test"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "t"]); dir = dir))
            copy_config!(dir)
            run(Cmd(["git", "-C", dir, "add", "-A"]))
            run(setenv(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init"]); dir = dir))
            viols = ms_violations(dir)
            @test any(
                v -> startswith(v.path, "other/") && occursin("missing from manifest", v.message),
                viols,
            )
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "parse error: malformed manifest dep entry" begin
        dir = init_git_fixture(joinpath(FIXTURES, "negative_malformed_dep"))
        try
            @test_throws AgentRuleLint.ParseError ms_violations(dir)
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
