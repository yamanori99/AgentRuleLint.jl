using Test

const ROOT = dirname(@__DIR__)

function tmp_repo(config_body::AbstractString)
    root = abspath(mktempdir())
    ver = string(pkgversion(AgentRuleLint))
    hdr = "agentrulelint_version = \"=$(ver)\"\n\n"
    write(joinpath(root, ".AgentRuleLintConfig.toml"), hdr * config_body)
    return root
end

function sole_hit_fp(root::AbstractString, rule_id::AbstractString, pred = nothing)
    res = AgentRuleLint.check(root)
    pred === nothing && (pred = d -> d.rule_id == rule_id && !d.suppressed)
    hits = filter(pred, res.violations)
    @test length(hits) == 1
    return only(hits).fingerprint
end

@testset "project rules: path globs and non-Julia sources" begin
    @testset "non-.jl hits (toml and md)" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"docs-secrets\"
            level = \"deny\"
            paths = [\"config/*.toml\", \"docs/**/*.md\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            mkpath(joinpath(root, "config"))
            mkpath(joinpath(root, "docs", "sub"))
            write(joinpath(root, "config", "app.toml"), "name = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "docs", "sub", "note.md"), "# INTERNAL_CODENAME\n")
            mkpath(joinpath(root, "other"))
            write(joinpath(root, "other", "skip.toml"), "INTERNAL_CODENAME\n")
            res = AgentRuleLint.check(root)
            paths = unique(d.path for d in res.violations if d.rule_id == "project/docs-secrets" && !d.suppressed)
            @test "config/app.toml" in paths
            @test "docs/sub/note.md" in paths
            @test "other/skip.toml" ∉ paths
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "non-.jl fingerprint stable when line shifts" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"note\"
            level = \"deny\"
            paths = [\"notes/*.md\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            mkpath(joinpath(root, "notes"))
            base = joinpath(root, "notes", "a.md")
            fp0 = begin
                write(base, "INTERNAL_CODENAME\n")
                sole_hit_fp(root, "project/note")
            end
            fp1 = begin
                write(base, "\n\nheader\n\nINTERNAL_CODENAME\n")
                sole_hit_fp(root, "project/note")
            end
            @test fp0 == fp1
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "glob star does not cross slash" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"glob-star\"
            level = \"deny\"
            paths = [\"lib/*/hit.jl\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            mkpath(joinpath(root, "lib", "sub"))
            mkpath(joinpath(root, "lib", "sub", "extra"))
            write(joinpath(root, "lib", "sub", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "sub", "extra", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "miss.jl"), "x = \"INTERNAL_CODENAME\"\n")
            res = AgentRuleLint.check(root)
            hits = filter(d -> d.rule_id == "project/glob-star" && !d.suppressed, res.violations)
            paths = unique(d.path for d in hits)
            @test paths == ["lib/sub/hit.jl"]
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "glob double-star across directories" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"glob-deep\"
            level = \"deny\"
            paths = [\"lib/**/hit.jl\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            mkpath(joinpath(root, "lib", "a", "b"))
            write(joinpath(root, "lib", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "a", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "a", "b", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            write(joinpath(root, "lib", "a", "miss.jl"), "x = \"INTERNAL_CODENAME\"\n")
            res = AgentRuleLint.check(root)
            paths = sort(
                unique(
                    d.path for d in res.violations if d.rule_id == "project/glob-deep" && !d.suppressed
                )
            )
            @test paths == ["lib/a/b/hit.jl", "lib/a/hit.jl", "lib/hit.jl"]
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "glob anchored to full relative path" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"anchored\"
            level = \"deny\"
            paths = [\"hit.jl\"]
            forbid_literals = [\"INTERNAL_CODENAME\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            write(joinpath(root, "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            mkpath(joinpath(root, "sub"))
            write(joinpath(root, "sub", "hit.jl"), "x = \"INTERNAL_CODENAME\"\n")
            res = AgentRuleLint.check(root)
            paths = unique(d.path for d in res.violations if d.rule_id == "project/anchored" && !d.suppressed)
            @test paths == ["hit.jl"]
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "invalid glob fails config load" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"bad-glob\"
            level = \"deny\"
            paths = [\"lib/***/hit.jl\"]
            forbid_literals = [\"x\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(root)
            cd(root) do
                @test AgentRuleLint.cli_main(["check"]) == 2
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "non-UTF-8 project target fails closed" begin
        root = tmp_repo(
            """
            [[project_rules]]
            id = \"bin\"
            level = \"deny\"
            paths = [\"data/*.bin\"]
            forbid_literals = [\"SECRET\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        try
            mkpath(joinpath(root, "data"))
            write(joinpath(root, "data", "payload.bin"), UInt8[0xff, 0xfe, 0xfd])
            @test_throws AgentRuleLint.ParseError AgentRuleLint.check(root)
            cd(root) do
                @test AgentRuleLint.cli_main(["check"]) == 2
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end
end
