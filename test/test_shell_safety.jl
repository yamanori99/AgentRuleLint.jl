include("mutation_subprocess_helpers.jl")

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
    function _shell_mutation_script(root::AbstractString, needle::AbstractString)
        return join(
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
    end

    function _shell_active_hits(root::AbstractString, corpus::AbstractString, needle::AbstractString)
        write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, corpus), String))
        write(
            joinpath(root, ".AgentRuleLintConfig.toml"),
            _shell_config("presets = [\"shell-safety\"]\n\n"),
        )
        hits = _shell_hits(root, "bad.jl")
        return any(d -> occursin(needle, d.message), hits)
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
        shared_tmp = mktempdir()
        cp(repo_root, shared_tmp; force = true)
        scratch = mktempdir()
        cases = [
            ("pkill", r"\\bpkill\\b" => "pkill_OFF", "shell_pkill_backtick.jl", "pkill"),
            ("killall", r"\\bkillall\\b" => "killall_OFF", "shell_killall.jl", "killall"),
            ("sudo", r"\\bsudo\\b" => "sudo_OFF", "shell_sudo_cmd.jl", "sudo"),
            ("ssh", r"\\bssh\\b.*\\s--\\s" => "ssh_OFF", "shell_ssh_remote.jl", "ssh"),
            ("sh -c", "_shell_dash_c_label(cmd)" => "nothing", "shell_sh_dash_c.jl", "sh -c"),
        ]
        try
            for (label, pair, corpus, needle) in cases
                @testset "$label" begin
                    @test _shell_active_hits(scratch, corpus, needle)
                    write(joinpath(shared_tmp, "bad.jl"), read(joinpath(CORPUS, corpus), String))
                    patched = replace(orig, pair)
                    write(joinpath(shared_tmp, "src", "rules", "shell_safety.jl"), orig)
                    write(joinpath(shared_tmp, "src", "rules", "shell_safety.jl"), patched)
                    script = _shell_mutation_script(shared_tmp, needle)
                    @test _mutation_child_ok(shared_tmp, script; dir = repo_root)
                end
            end
        finally
            rm(shared_tmp, recursive = true, force = true)
            rm(scratch, recursive = true, force = true)
        end
    end
end
