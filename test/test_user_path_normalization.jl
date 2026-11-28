@testset "user path normalization (input boundary)" begin
    corpus_rel = "test\\corpus\\silent_catch_empty.jl"
    corpus_slash = "test/corpus/silent_catch_empty.jl"

    @testset "library paths: backslash equals slash" begin
        res_bs = AgentRuleLint.check(ROOT; paths = [corpus_rel])
        res_sl = AgentRuleLint.check(ROOT; paths = [corpus_slash])
        @test res_bs.exit_code == res_sl.exit_code
        @test sort!([d.fingerprint for d in res_bs.violations]) ==
            sort!([d.fingerprint for d in res_sl.violations])
    end

    @testset "CLI positional paths: backslash equals slash" begin
        code_bs = cd(ROOT) do
            AgentRuleLint.cli_main(["check", corpus_rel, "--format", "json"])
        end
        code_sl = cd(ROOT) do
            AgentRuleLint.cli_main(["check", corpus_slash, "--format", "json"])
        end
        @test code_bs == code_sl
    end

    @testset "non-matching lint path fails closed (library)" begin
        bogus = "no\\such\\file.jl"
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(ROOT; paths = [bogus])
        try
            AgentRuleLint.check(ROOT; paths = [bogus])
        catch err
            err isa AgentRuleLint.ConfigError || rethrow(err)
            @test occursin("path matched no files", err.msg)
            @test occursin(repr(bogus), err.msg)
            @test occursin(repr(AgentRuleLint.normalize_path(bogus)), err.msg)
        end
    end

    @testset "non-matching lint path fails closed (CLI)" begin
        bogus = "ghost\\path.jl"
        code = cd(ROOT) do
            AgentRuleLint.cli_main(["check", bogus])
        end
        @test code == 2
    end

    @testset "--allow-paths: backslash glob matches files like slash form" begin
        root = mktempdir()
        try
            ver = string(pkgversion(AgentRuleLint))
            write(
                joinpath(root, ".AgentRuleLint.jl.toml"),
                "agentrulelint_version = \"=$(ver)\"\n",
            )
            mkpath(joinpath(root, "src"))
            write(joinpath(root, "src", "touch.jl"), "x = 1\n")
            run(`git -C $root init -q`)
            run(`git -C $root add -A`)
            run(`git -C $root -c user.email=mut@test -c user.name=mut commit -q -m init --allow-empty`)
            write(joinpath(root, "src", "touch.jl"), "x = 2\n")
            glob_bs = "src\\**"
            glob_sl = "src/**"
            res_bs = AgentRuleLint.check(
                root;
                diff_base = "HEAD",
                allow_paths = [glob_bs],
            )
            res_sl = AgentRuleLint.check(
                root;
                diff_base = "HEAD",
                allow_paths = [glob_sl],
            )
            scope_bs = filter(d -> d.rule_id == "scope-paths" && !d.suppressed, res_bs.violations)
            scope_sl = filter(d -> d.rule_id == "scope-paths" && !d.suppressed, res_sl.violations)
            @test isempty(scope_bs) == isempty(scope_sl)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "--config: backslash path finds file" begin
        root = mktempdir()
        try
            ver = string(pkgversion(AgentRuleLint))
            write(
                joinpath(root, ".AgentRuleLint.jl.toml"),
                "agentrulelint_version = \"=$(ver)\"\n",
            )
            cfg_bs = ".\\.AgentRuleLint.jl.toml"
            res = AgentRuleLint.check(root; config_path = cfg_bs)
            @test res.exit_code in (0, 1, 2)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "non-matching --config fails closed" begin
        root = mktempdir()
        try
            missing = "missing\\config.toml"
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(root; config_path = missing)
            code = cd(root) do
                AgentRuleLint.cli_main(["check", "--config", missing])
            end
            @test code == 2
        finally
            rm(root, recursive = true, force = true)
        end
    end
end