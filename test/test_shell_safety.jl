function _shell_config(extra::AbstractString = "")
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

function _shell_hits(root::AbstractString, relpath::AbstractString)
    res = AgentRuleLint.check(root; config_path = joinpath(root, ".AgentRuleLintConfig.toml"), paths = [relpath])
    return filter(d -> d.rule_id == "shell-safety/process-pattern" && !d.suppressed, res.violations)
end

@testset "shell-safety process-pattern preset" begin
    @testset "inactive without presets" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config())
            write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, "shell_pkill_backtick.jl"), String))
            @test isempty(_shell_hits(root, "bad.jl"))
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "active with presets = [\"shell-safety\"]" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config("presets = [\"shell-safety\"]\n\n"))
            write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, "shell_pkill_backtick.jl"), String))
            @test !isempty(_shell_hits(root, "bad.jl"))
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "golden hits" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config("presets = [\"shell-safety\"]\n\n"))
            for file in ["shell_pkill_backtick.jl", "shell_sh_dash_c.jl", "shell_sudo_cmd.jl"]
                write(joinpath(root, file), read(joinpath(CORPUS, file), String))
                @test !isempty(_shell_hits(root, file))
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "adversarial split not folded" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config("presets = [\"shell-safety\"]\n\n"))
            write(joinpath(root, "evade.jl"), read(joinpath(CORPUS, "shell_adversarial_split.jl"), String))
            @test isempty(_shell_hits(root, "evade.jl"))
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "clean ls allowed" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config("presets = [\"shell-safety\"]\n\n"))
            write(joinpath(root, "ok.jl"), read(joinpath(CORPUS, "shell_clean_ls.jl"), String))
            @test isempty(_shell_hits(root, "ok.jl"))
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "mutation: pkill detector disabled (subprocess)" begin
        bak = joinpath(ROOT, "src", "rules", "shell_safety.jl")
        orig = read(bak, String)
        patched = replace(orig, r"\\bpkill\\b" => "pkill_OFF")
        script = root -> join(
            [
                "using AgentRuleLint",
                "cfg = joinpath($(repr(root)), \".AgentRuleLintConfig.toml\")",
                "write(cfg, \"agentrulelint_version = \\\"=$(string(pkgversion(AgentRuleLint)))\\\"\\npresets = [\\\"shell-safety\\\"]\\n[rules.expect-audit]\\nlevel = \\\"forbid\\\"\\n\")",
                "body = read(joinpath($(repr(root)), \"bad.jl\"), String)",
                "write(joinpath($(repr(root)), \"bad.jl\"), body)",
                "r = AgentRuleLint.check($(repr(root)); paths=[\"bad.jl\"])",
                "h = filter(d -> d.rule_id==\"shell-safety/process-pattern\" && occursin(\"pkill\", d.message), r.violations)",
                "exit(isempty(h) ? 0 : 1)",
            ],
            '\n',
        )
        tmp = mktempdir()
        try
            cp(ROOT, tmp; force = true)
            write(joinpath(tmp, "bad.jl"), read(joinpath(CORPUS, "shell_pkill_backtick.jl"), String))
            base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            @test !success(run(ignorestatus(setenv(base_cmd; dir = ROOT))))
            write(bak, patched)
            write(joinpath(tmp, "src", "rules", "shell_safety.jl"), patched)
            patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            @test success(run(ignorestatus(setenv(patch_cmd; dir = ROOT))))
        finally
            write(bak, orig)
            rm(tmp, recursive = true, force = true)
        end
    end
end
