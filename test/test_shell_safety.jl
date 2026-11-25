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

const _SHELL_POSITIVE = String[
    "shell_pkill_backtick.jl",
    "shell_sh_dash_c.jl",
    "shell_sudo_cmd.jl",
    "shell_open_sh_c.jl",
    "shell_pipeline_sudo.jl",
    "shell_cmd_pkill.jl",
    "shell_cmd_folded_c.jl",
    "shell_bash_lc.jl",
    "shell_bash_norc_c.jl",
    "shell_killall.jl",
    "shell_ssh_remote.jl",
    "shell_base_cmd_pkill.jl",
]

function _shell_hits(root::AbstractString, relpath::AbstractString)
    res = AgentRuleLint.check(root; config_path = joinpath(root, ".AgentRuleLintConfig.toml"), paths = [relpath])
    return filter(d -> d.rule_id == "shell-safety/process-pattern" && !d.suppressed, res.violations)
end

@testset "shell-safety process-pattern preset" begin
    function _shell_mutation_subprocess(
            repo_root::AbstractString,
            _orig::AbstractString,
            patched::AbstractString,
            corpus::AbstractString,
            needle::AbstractString,
        )
        script = root -> join(
            [
                "using AgentRuleLint",
                "v = string(pkgversion(AgentRuleLint))",
                "write(joinpath($(repr(root)), \".AgentRuleLintConfig.toml\"), \"agentrulelint_version=\\\"\" * v * \"\\\"\\npresets=[\\\"shell-safety\\\"]\\n[rules.expect-audit]\\nlevel=\\\"forbid\\\"\\n\")",
                "r = AgentRuleLint.check($(repr(root)); paths=[\"bad.jl\"])",
                "h = filter(d -> d.rule_id==\"shell-safety/process-pattern\" && occursin($(repr(needle)), d.message), r.violations)",
                "exit(isempty(h) ? 0 : 1)",
            ],
            '\n',
        )
        tmp = mktempdir()
        try
            cp(repo_root, tmp; force = true)
            write(joinpath(tmp, "bad.jl"), read(joinpath(CORPUS, corpus), String))
            base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            before_ok = success(run(ignorestatus(setenv(base_cmd; dir = repo_root))))
            write(joinpath(tmp, "src", "rules", "shell_safety.jl"), patched)
            patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            after_ok = success(run(ignorestatus(setenv(patch_cmd; dir = repo_root))))
            return (!before_ok, after_ok)
        finally
            rm(tmp, recursive = true, force = true)
        end
    end

    repo_root = dirname(@__DIR__)

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

    @testset "inactive preset table without presets is ConfigError" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                _shell_config("""[rules."shell-safety/process-pattern"]\nlevel = "deny"\n"""),
            )
            write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, "shell_pkill_backtick.jl"), String))
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(root; paths = ["bad.jl"])
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
            for file in _SHELL_POSITIVE
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

    @testset "long options with c are not -c" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _shell_config("presets = [\"shell-safety\"]\n\n"))
            write(joinpath(root, "ok.jl"), read(joinpath(CORPUS, "shell_bash_rcfile.jl"), String))
            @test isempty(_shell_hits(root, "ok.jl"))
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "mutation: detector patches (subprocess)" begin
        src = joinpath(repo_root, "src", "rules", "shell_safety.jl")
        orig = read(src, String)
        cases = [
            ("pkill", r"\\bpkill\\b" => "pkill_OFF", "shell_pkill_backtick.jl", "pkill"),
            ("killall", r"\\bkillall\\b" => "killall_OFF", "shell_killall.jl", "killall"),
            ("sudo", r"\\bsudo\\b" => "sudo_OFF", "shell_sudo_cmd.jl", "sudo"),
            ("ssh", r"\\bssh\\b.*\\s--\\s" => "ssh_OFF", "shell_ssh_remote.jl", "ssh"),
            ("sh -c", "_shell_dash_c_label(cmd)" => "nothing", "shell_sh_dash_c.jl", "sh -c"),
        ]
        for (label, pair, corpus, needle) in cases
            @testset "$label" begin
                patched = replace(orig, pair)
                found, missed = _shell_mutation_subprocess(repo_root, orig, patched, corpus, needle)
                @test found
                @test missed
            end
        end
    end
end
