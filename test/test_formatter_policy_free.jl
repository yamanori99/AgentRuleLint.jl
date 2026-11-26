using AgentRuleLint
using Test

const ROOT = dirname(@__DIR__)
const FORMAT_DIR = joinpath(ROOT, "src", "format")
const FORMAT_POLICY_ALLOWLIST = ("report.jl",)

function _format_jl_sources()
    return filter(readdir(FORMAT_DIR)) do name
        endswith(name, ".jl")
    end
end

function _forbidden_policy_tokens(text::AbstractString)
    found = String[]
    for pat in ("resolve_policy", "load_policy", "build_builtin_registry")
        occursin(pat, text) && push!(found, pat)
    end
    return found
end

@testset "check formatters do not resolve policy" begin
    @testset "src/format policy token guard" begin
        for name in _format_jl_sources()
            name in FORMAT_POLICY_ALLOWLIST && continue
            text = read(joinpath(FORMAT_DIR, name), String)
            bad = _forbidden_policy_tokens(text)
            @test isempty(bad) #
        end
    end

    @testset "human agent json invariant to pwd and working-tree config" begin
        corpus = joinpath("test", "corpus", "split_string.jl")
        res = AgentRuleLint.check(ROOT; paths = [corpus])
        plain = IOContext(IOBuffer(), :color => false)

        remote = mktempdir()
        try
            mkpath(joinpath(remote, "deep"))
            conflict = """
            agentrulelint_version = \"=99.99.99\"
            default_format = \"json\"
            presets = [\"shell-safety\"]
            """
            write(joinpath(remote, ".AgentRuleLintConfig.toml"), conflict)
            human_here = AgentRuleLint.format_human(
                res;
                root = ROOT,
                io = plain,
                output_width = 80,
            )
            agent_here = AgentRuleLint.format_agent(
                res;
                root = ROOT,
                io = plain,
                output_width = 80,
            )
            json_here = AgentRuleLint.format_json(res)
            human_there = cd(joinpath(remote, "deep")) do
                AgentRuleLint.format_human(res; root = ROOT, io = plain, output_width = 80)
            end
            agent_there = cd(joinpath(remote, "deep")) do
                AgentRuleLint.format_agent(res; root = ROOT, io = plain, output_width = 80)
            end
            json_there = cd(joinpath(remote, "deep")) do
                AgentRuleLint.format_json(res)
            end
            @test human_here == human_there
            @test agent_here == agent_there
            @test json_here == json_there
        finally
            rm(remote; recursive = true, force = true)
        end
    end

    @testset "strict-only policy keeps unsafe-boundary/strict in all formats" begin
        ver = string(pkgversion(AgentRuleLint))
        cfg = """
        agentrulelint_version = \"=$(ver)\"
        presets = [\"unsafe-boundary/strict\"]

        [rules.\"unsafe-boundary/strict\"]
        level = \"warn\"
        """
        tmp = mktempdir()
        try
            mkpath(joinpath(tmp, "test"))
            cp(joinpath(ROOT, "test", "corpus"), joinpath(tmp, "test", "corpus"); force = true)
            cfg_path = joinpath(tmp, ".AgentRuleLintConfig.toml")
            write(cfg_path, cfg)
            path = joinpath("test", "corpus", "unsafe_inbounds.jl")
            run(`git -C $tmp init`)
            run(`git -C $tmp add .`)
            run(
                Cmd(
                    `git -C $tmp commit -m strict-only`;
                    env = Dict(
                        "GIT_AUTHOR_NAME" => "t",
                        "GIT_AUTHOR_EMAIL" => "t@t",
                        "GIT_COMMITTER_NAME" => "t",
                        "GIT_COMMITTER_EMAIL" => "t@t",
                    ),
                ),
            )
            res = AgentRuleLint.check(tmp; paths = [path], config_from = "HEAD")
            hits = filter(
                d -> d.rule_id == "unsafe-boundary/strict" && !d.suppressed,
                res.violations,
            )
            @test !isempty(hits)
            @test all(d -> !isempty(d.intent) && !isempty(d.do_not), hits)

            plain = IOContext(IOBuffer(), :color => false)
            human = AgentRuleLint.format_human(
                res;
                root = tmp,
                io = plain,
                output_width = 120,
            )
            agent = AgentRuleLint.format_agent(
                res;
                root = tmp,
                io = plain,
                output_width = 120,
            )
            json = AgentRuleLint.format_json(res)
            @test occursin("unsafe-boundary/strict", human)
            @test occursin("unsafe-boundary/strict", agent)
            @test occursin("\"rule_id\":\"unsafe-boundary/strict\"", replace(json, " " => ""))
            @test !occursin("RULE [AgentRuleLint] unsafe-boundary ", agent)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end
end