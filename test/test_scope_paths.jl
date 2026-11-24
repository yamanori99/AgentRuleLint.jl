SCOPE_RULE = "scope-paths"
const SCOPE_ROOT = dirname(@__DIR__)

@testset "scope-paths and --allow-paths" begin
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
        """
    end

    function scope_hits(res)
        return filter(
            d ->
            d.rule_id == SCOPE_RULE && !d.suppressed &&
                d.expect_status != :fulfilled && d.level != :allow,
            res.violations,
        )
    end

    @testset "allow-paths without diff fails closed" begin
        cd(SCOPE_ROOT) do
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(
                pwd();
                allow_paths = AgentRuleLint.compile_allow_path_globs(["src/**"]),
            )
            @test AgentRuleLint.cli_main(["check", "--allow-paths", "src/**"]) == 2
        end
    end

    @testset "empty allow-paths usage error" begin
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.parse_allow_paths_cli("   ")
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.parse_allow_paths_cli(", ,")
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.compile_allow_path_globs(["/abs"])
    end

    @testset "duplicate --allow-paths is usage error" begin
        cd(SCOPE_ROOT) do
            @test AgentRuleLint.cli_main(
                [
                    "check",
                    "--allow-paths",
                    "src/**",
                    "--allow-paths",
                    "doc/**",
                ],
            ) == 2
            @test AgentRuleLint.cli_main(["check", "--allow-paths=src/**", "--allow-paths=doc/**"]) == 2
        end
    end

    @testset "stray ArgumentError in pipeline maps to internal error" begin
        root = SCOPE_ROOT
        src_runner = joinpath(root, "src", "runner.jl")
        @eval AgentRuleLint begin
            function run_check(r::AbstractString; kwargs...)
                throw(ArgumentError("synthetic in-pipeline bug"))
            end
        end
        try
            @test_throws AgentRuleLint.InternalError AgentRuleLint.check(root)
            cd(root) do
                @test AgentRuleLint.cli_main(["check"]) == 3
            end
        finally
            @eval AgentRuleLint begin
                include($src_runner)
            end
        end
    end

    @testset "invalid allow_paths keyword type is config fail-closed" begin
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(SCOPE_ROOT; allow_paths = 123)
    end

    @testset "in-scope diff passes" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            mkpath(joinpath(dir, "src"))
            write(joinpath(dir, "src", "ok.jl"), "1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "src", "ok.jl"), "2\n")
            git_commit_all!(dir, "change")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1", allow_paths = ["src/**"])
                @test isempty(scope_hits(res))
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "out-of-scope diff fails" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, "secret.txt"), "a\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, "secret.txt"), "b\n")
            git_commit_all!(dir, "change")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1", allow_paths = ["src/**"])
                hits = scope_hits(res)
                @test length(hits) == 1
                @test first(hits).path == "secret.txt"
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "rename outside allowlist" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), minimal_cfg())
            write(joinpath(dir, ".JETLSConfig.toml"), "1\n")
            git_commit_all!(dir, "base")
            mv(joinpath(dir, ".JETLSConfig.toml"), joinpath(dir, "moved.toml"))
            git_commit_all!(dir, "rename")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1", allow_paths = ["src/**"])
                paths = Set(h.path for h in scope_hits(res))
                @test ".JETLSConfig.toml" in paths || "moved.toml" in paths
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "corpus adversarial fixture present" begin
        @test isfile(joinpath(@__DIR__, "corpus", "scope_paths_outside_allow.jl"))
    end

end
