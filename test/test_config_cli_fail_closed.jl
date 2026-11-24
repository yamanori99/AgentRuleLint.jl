@testset "config and CLI fail-closed" begin
    ver = string(pkgversion(JAILint))

    function minimal_config(extra::AbstractString = "")
        """
        jailint_version = \"=$(ver)\"
        $extra
        """
    end

    @testset "config unknown top-level key" begin
        root = mktempdir()
        try
            write(joinpath(root, ".JAILintConfig.toml"), minimal_config("oops = true\n"))
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config unknown rules table key" begin
        root = mktempdir()
        try
            cfg = minimal_config(
                """
                [rules.expect-audit]
                level = \"forbid\"
                typo = true
                """,
            )
            write(joinpath(root, ".JAILintConfig.toml"), cfg)
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config unknown project_rules key" begin
        root = mktempdir()
        try
            cfg = minimal_config(
                """
                [[project_rules]]
                id = \"x\"
                level = \"deny\"
                paths = []
                forbid_literals = []
                extra = 1
                """,
            )
            write(joinpath(root, ".JAILintConfig.toml"), cfg)
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config unknown rule level" begin
        root = mktempdir()
        try
            cfg = minimal_config(
                """
                [rules.expect-audit]
                level = \"mystery\"
                """,
            )
            write(joinpath(root, ".JAILintConfig.toml"), cfg)
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config unknown preset" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".JAILintConfig.toml"),
                minimal_config("presets = [\"not-a-real-preset\"]\n"),
            )
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config invalid default_format" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".JAILintConfig.toml"),
                minimal_config("default_format = \"xml\"\n"),
            )
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config invalid on_allow_rule" begin
        root = mktempdir()
        try
            cfg = minimal_config(
                """
                [rules.expect-audit]
                level = \"forbid\"
                on_allow_rule = \"nope\"
                """,
            )
            write(joinpath(root, ".JAILintConfig.toml"), cfg)
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "CLI unknown flag" begin
        cd(ROOT) do
            @test JAILint.cli_main(["check", "--bogus"]) == 2
        end
    end

    @testset "CLI invalid format" begin
        cd(ROOT) do
            @test JAILint.cli_main(["check", "--format", "xml"]) == 2
            @test JAILint.cli_main(["check", "--format=yaml"]) == 2
        end
    end

    @testset "CLI check rejects --write" begin
        cd(ROOT) do
            @test JAILint.cli_main(["check", "--write"]) == 2
        end
    end

    @testset "CLI ratchet requires --write" begin
        cd(ROOT) do
            @test JAILint.cli_main(["ratchet"]) == 2
            @test JAILint.cli_main(["ratchet", "--help"]) == 0
        end
    end

    @testset "emit format uses check policy not disk reload" begin
        dir = abspath(mktempdir())
        try
            ver = string(pkgversion(JAILint))
            cfg_head = """
            jailint_version = \"=$(ver)\"
            default_format = \"json\"
            """
            write(joinpath(dir, ".JAILintConfig.toml"), cfg_head)
            write(joinpath(dir, "ok.jl"), "1\n")
            run(setenv(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "j@test"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "t"]); dir = dir))
            run(setenv(Cmd(["git", "-C", dir, "add", "."]); dir = dir))
            run(
                setenv(
                    Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c"]);
                    dir = dir,
                ),
            )
            write(
                joinpath(dir, ".JAILintConfig.toml"),
                "jailint_version = \"=$(ver)\"\ndefault_format = \"human\"\n",
            )
            res = JAILint.check(dir; config_from = "HEAD", paths = ["ok.jl"])
            @test res.default_format == :json
            out = joinpath(dir, "emit.txt")
            cd(dir) do
                @test JAILint.cli_main(["check", "--config-from", "HEAD", "ok.jl", "--output", out]) == 0
            end
            body = read(out, String)
            @test occursin("\"type\":\"header\"", replace(body, " " => ""))
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "CLI default_format from config" begin
        root = mktempdir()
        try
            write(joinpath(root, "sample.jl"), "x = 1\n")
            write(
                joinpath(root, ".JAILintConfig.toml"),
                minimal_config("default_format = \"json\"\n"),
            )
            out = joinpath(root, "out.txt")
            cd(root) do
                @test JAILint.cli_main(["check", "sample.jl", "--output", out]) == 0
                body = read(out, String)
                @test occursin("\"type\":\"header\"", replace(body, " " => ""))
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "CLI --format overrides config default_format" begin
        root = mktempdir()
        try
            write(joinpath(root, "sample.jl"), "x = 1\n")
            write(
                joinpath(root, ".JAILintConfig.toml"),
                minimal_config("default_format = \"json\"\n"),
            )
            out = joinpath(root, "out.txt")
            cd(root) do
                @test JAILint.cli_main(["check", "sample.jl", "--format", "human", "--output", out]) == 0
                body = read(out, String)
                @test !occursin("\"type\":\"header\"", replace(body, " " => ""))
                @test occursin("JAILint", body) || occursin("complete", body)
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config max_hits_per_rule type" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".JAILintConfig.toml"),
                minimal_config("max_hits_per_rule = \"twenty\"\n"),
            )
            @test_throws JAILint.ConfigError JAILint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "CLI unknown command" begin
        cd(ROOT) do
            @test JAILint.cli_main(["nope"]) == 2
        end
    end
end
