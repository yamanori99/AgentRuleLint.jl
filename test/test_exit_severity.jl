@testset "exit_severity" begin
    function _pin_config(extra::AbstractString = "")
        v = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(v)\"
        default_format = \"human\"
        $extra
        [rules.expect-audit]
        level = \"forbid\"
        on_allow_rule = \"warn\"
        """
    end

    @testset "default warn matches any-hit exit (repo corpus)" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
        res_default = AgentRuleLint.check(
            ROOT;
            paths = [joinpath("test", "corpus")],
            exit_severity = :warn,
        )
        @test res.exit_code == res_default.exit_code
        @test res.violation_count == res_default.violation_count
    end

    @testset "forbid threshold skips warn-only hits" begin
        relp = joinpath("test", "corpus", "unsafe_allow_module.jl")
        res = AgentRuleLint.check(ROOT; paths = [relp], exit_severity = :forbid)
        hits = filter(
            d -> d.rule_id == "unsafe-boundary" && !d.suppressed,
            res.violations,
        )
        @test !isempty(hits)
        @test all(d -> d.level == :warn, hits)
        @test res.exit_code == 0
    end

    @testset "forbid-level findings fail every threshold" begin
        relp = joinpath("test", "corpus", "expect_empty_reason.jl")
        for th in (:warn, :deny, :forbid)
            res = AgentRuleLint.check(ROOT; paths = [relp], exit_severity = th)
            forbid_hits = filter(d -> d.level == :forbid && !d.suppressed, res.violations)
            @test !isempty(forbid_hits)
            @test res.exit_code == 1
        end
    end

    @testset "deny-only hits respect forbid threshold" begin
        relp = joinpath("test", "corpus", "silent_catch_empty.jl")
        res = AgentRuleLint.check(ROOT; paths = [relp], exit_severity = :forbid)
        deny_hits = filter(d -> d.level == :deny && !d.suppressed, res.violations)
        forbid_hits = filter(d -> d.level == :forbid && !d.suppressed, res.violations)
        @test !isempty(deny_hits)
        @test isempty(forbid_hits)
        @test res.exit_code == 0
    end

    @testset "config exit_severity" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _pin_config("exit_severity = \"forbid\"\n"))
            pol = AgentRuleLint.resolve_policy(root)
            @test pol.exit_severity == :forbid
            relp = joinpath("test", "corpus", "unsafe_allow_module.jl")
            res = AgentRuleLint.check(
                ROOT;
                paths = [relp],
                config_path = joinpath(root, ".AgentRuleLintConfig.toml"),
            )
            @test res.exit_code == 0
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                _pin_config("exit_severity = \"nope\"\n"),
            )
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.resolve_policy(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "CLI unknown exit_severity" begin
        @test AgentRuleLint.cli_main(["check", "--exit-severity", "hint", "test/corpus"]) == 2
        @test AgentRuleLint.cli_main(["check", "--exit-severity=error", "test/corpus"]) == 2
    end

    @testset "CLI overrides config" begin
        root = mktempdir()
        try
            cfg = joinpath(root, ".AgentRuleLintConfig.toml")
            write(
                cfg,
                string(
                    _pin_config("exit_severity = \"forbid\"\n"),
                    "[rules.unsafe-boundary]\n",
                    "level = \"warn\"\n",
                    "allow_modules = []\n",
                    "allow_globs = []\n",
                ),
            )
            old = pwd()
            try
                cd(ROOT)
                @test AgentRuleLint.cli_main(
                    [
                        "check",
                        "--config",
                        cfg,
                        "--exit-severity",
                        "warn",
                        "test/corpus/unsafe_allow_module.jl",
                    ],
                ) == 1
            finally
                cd(old)
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end
end