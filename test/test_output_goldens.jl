# Output goldens under test/goldens/output/ are pinned from main (see #77 / #25).
# They change only for intended output changes, which the PR that updates them
# must state. Never regenerate goldens to clear a failing neutrality check on a
# structure-only refactor.
#
# Three configurations:
# 1. Repo dogfood config (ROOT) — goldens in test/goldens/output/{check_*,explain/}
# 2. No config file — goldens in test/goldens/output/no_config/
# 3. Minimal config (rules without intent/do_not) — goldens in
#    test/goldens/output/minimal_config/ (fixture TOML:
#    minimal_config/AgentRuleLintConfig.toml)
#
# #82 / #83: inactive built-in `explain` succeeds with
# `level: <level> (default when enabled)` and `status: not enabled in this
# config` (no_config inactive ids; repo `shell-safety/process-pattern`).
# Fold-budget / analysis-incomplete diagnostics (#66 / review on #78) are an
# intentional output change for the repo-config check goldens and any
# no_config / minimal_config files they affect.

const OUTPUT_GOLDEN_DIR = joinpath(ROOT, "test", "goldens", "output")
const OUTPUT_GOLDEN_WIDTH = 80
# Text normalization helpers live in test/golden_test_helpers.jl (init_code).
const OUTPUT_GOLDEN_EXPLAIN_IDS = (
    "analysis-incomplete",
    "expect-audit",
    "ceiling-ratchet",
    "manifest-sync",
    "protected-paths",
    "scope-paths",
    "shell-safety/process-pattern",
    "silent-catch",
    "test-integrity",
    "unsafe-boundary",
)

# Under `default_policy` (no config file), explain covers every built-in id.
# Ids not registered / not activated include `status: not enabled in this config`
# (#82); check is unchanged. `analysis-incomplete` is always injected as an
# integrity rule, so it is active under `default_policy`.
const OUTPUT_GOLDEN_NO_CONFIG_EXPLAIN_IDS = (
    "analysis-incomplete",
    "expect-audit",
    "ceiling-ratchet",
    "manifest-sync",
    "protected-paths",
    "scope-paths",
    "shell-safety/process-pattern",
    "silent-catch",
    "test-integrity",
    "unsafe-boundary",
)

# Built-ins inactive under `default_policy` (explain succeeds with status line).
const OUTPUT_GOLDEN_NO_CONFIG_INACTIVE_EXPLAIN_IDS = (
    "shell-safety/process-pattern",
    "test-integrity",
    "unsafe-boundary",
)

const _CHECK_GOLDEN_REL_PATHS = (
    "check_human.txt",
    "check_agent.txt",
    "check_json.txt",
)

function _check_golden_dirs()
    out = AbstractString[joinpath(OUTPUT_GOLDEN_DIR)]
    for sub in ("no_config", "minimal_config")
        push!(out, joinpath(OUTPUT_GOLDEN_DIR, sub))
    end
    return out
end

function _explain_golden_filename(id::AbstractString)
    return replace(id, "/" => "__") * ".txt"
end

function _assert_check_goldens(golden_dir::AbstractString, root::AbstractString; config_path = nothing)
    kwargs = Dict{Symbol, Any}(:paths => [joinpath("test", "corpus")])
    config_path !== nothing && (kwargs[:config_path] = config_path)
    res = AgentRuleLint.check(root; kwargs...)
    plain_io = IOContext(IOBuffer(), :color => false)
    human = _golden_normalize_text(
        AgentRuleLint.format_human(
            res;
            root = root,
            io = plain_io,
            output_width = OUTPUT_GOLDEN_WIDTH,
        ),
    )
    agent = _golden_normalize_text(
        AgentRuleLint.format_agent(
            res;
            root = root,
            io = plain_io,
            output_width = OUTPUT_GOLDEN_WIDTH,
        ),
    )
    json = _golden_json_without_header(AgentRuleLint.format_json(res))
    @test human ==
        _golden_normalize_text(read(joinpath(golden_dir, "check_human.txt"), String))
    @test agent ==
        _golden_normalize_text(read(joinpath(golden_dir, "check_agent.txt"), String))
    @test json ==
        _golden_json_without_header(read(joinpath(golden_dir, "check_json.txt"), String))
    return nothing
end

function _assert_explain_goldens(golden_dir::AbstractString, ids; root::AbstractString)
    for id in ids
        got = AgentRuleLint.explain_rule(id; root = root)
        want = read(
            joinpath(golden_dir, "explain", _explain_golden_filename(id)),
            String,
        )
        # Golden file = explain body + one trailing newline (tracked-file rule).
        @test got * "\n" == want
    end
    return nothing
end

function _temp_corpus_root(; config_text::Union{Nothing, AbstractString} = nothing)
    tmp = mktempdir()
    mkpath(joinpath(tmp, "test"))
    cp(joinpath(ROOT, "test", "corpus"), joinpath(tmp, "test", "corpus"); force = true)
    if config_text !== nothing
        write(joinpath(tmp, ".AgentRuleLintConfig.toml"), config_text)
    end
    return tmp
end

@testset "output goldens (main neutrality)" begin
    @testset "golden check files pin version placeholder" begin
        for gdir in _check_golden_dirs()
            for rel in _CHECK_GOLDEN_REL_PATHS
                body = read(joinpath(gdir, rel), String)
                @test occursin(OUTPUT_GOLDEN_VERSION_PLACEHOLDER, body)
            end
        end
    end

    @testset "status headers invariant to version string length" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        plain_io = IOContext(IOBuffer(), :color => false)
        width = OUTPUT_GOLDEN_WIDTH
        short_v = "0.1.0"
        long_v = "0.1.0-DEV.1234"
        human_short = AgentRuleLint.format_human(
            res;
            root = ROOT,
            io = plain_io,
            output_width = width,
            _agentrulelint_version = short_v,
        )
        human_long = AgentRuleLint.format_human(
            res;
            root = ROOT,
            io = plain_io,
            output_width = width,
            _agentrulelint_version = long_v,
        )
        agent_short = AgentRuleLint.format_agent(
            res;
            root = ROOT,
            io = plain_io,
            output_width = width,
            _agentrulelint_version = short_v,
        )
        agent_long = AgentRuleLint.format_agent(
            res;
            root = ROOT,
            io = plain_io,
            output_width = width,
            _agentrulelint_version = long_v,
        )
        norm_short_h = replace(human_short, short_v => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
        norm_long_h = replace(human_long, long_v => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
        norm_short_a = replace(agent_short, short_v => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
        norm_long_a = replace(agent_long, long_v => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
        @test norm_short_h == norm_long_h
        @test norm_short_a == norm_long_a
    end

    @testset "live check output embeds package version" begin
        ver = string(AgentRuleLint.AGENTRULELINT_VERSION)
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
        plain_io = IOContext(IOBuffer(), :color => false)
        human = AgentRuleLint.format_human(
            res;
            root = ROOT,
            io = plain_io,
            output_width = OUTPUT_GOLDEN_WIDTH,
        )
        agent = AgentRuleLint.format_agent(
            res;
            root = ROOT,
            io = plain_io,
            output_width = OUTPUT_GOLDEN_WIDTH,
        )
        json = AgentRuleLint.format_json(res)
        @test occursin(ver, human)
        @test occursin(ver, agent)
        @test occursin(ver, json)
    end
    @testset "repo config: check human/json/agent over test/corpus" begin
        _assert_check_goldens(OUTPUT_GOLDEN_DIR, ROOT)
    end

    @testset "repo config: explain goldens" begin
        _assert_explain_goldens(OUTPUT_GOLDEN_DIR, OUTPUT_GOLDEN_EXPLAIN_IDS; root = ROOT)
    end

    @testset "no config: check and explain" begin
        tmp = _temp_corpus_root()
        try
            @assert !isfile(joinpath(tmp, ".AgentRuleLintConfig.toml"))
            gdir = joinpath(OUTPUT_GOLDEN_DIR, "no_config")
            _assert_check_goldens(gdir, tmp)
            _assert_explain_goldens(gdir, OUTPUT_GOLDEN_NO_CONFIG_EXPLAIN_IDS; root = tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "no config: inactive built-ins explain with status (library + CLI)" begin
        # #82: inactive built-ins are explainable; status marks them as not enabled.
        tmp = _temp_corpus_root()
        try
            @assert !isfile(joinpath(tmp, ".AgentRuleLintConfig.toml"))
            gdir = joinpath(OUTPUT_GOLDEN_DIR, "no_config")
            for id in OUTPUT_GOLDEN_NO_CONFIG_INACTIVE_EXPLAIN_IDS
                text = AgentRuleLint.explain_rule(id; root = tmp)
                @test occursin("status: not enabled in this config", text)
                want = read(
                    joinpath(gdir, "explain", _explain_golden_filename(id)),
                    String,
                )
                @test text * "\n" == want

                mktemp() do out_path, _
                    mktemp() do err_path, _
                        code = cd(tmp) do
                            open(out_path, "w") do out_io
                                open(err_path, "w") do err_io
                                    redirect_stdout(out_io) do
                                        redirect_stderr(err_io) do
                                            AgentRuleLint.cli_main(["explain", id])
                                        end
                                    end
                                end
                            end
                        end
                        @test code == 0
                        @test read(out_path, String) == text * "\n"
                        @test read(err_path, String) == ""
                    end
                end
            end
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "truly unknown rule id stays unknown (library + CLI)" begin
        id = "not-a-real-rule"
        tmp = _temp_corpus_root()
        try
            @test_throws ArgumentError "unknown rule id: not-a-real-rule" AgentRuleLint.explain_rule(
                id;
                root = tmp,
            )

            mktemp() do out_path, _
                mktemp() do err_path, _
                    code = cd(tmp) do
                        open(out_path, "w") do out_io
                            open(err_path, "w") do err_io
                                redirect_stdout(out_io) do
                                    redirect_stderr(err_io) do
                                        AgentRuleLint.cli_main(["explain", id])
                                    end
                                end
                            end
                        end
                    end
                    @test code == 2
                    @test read(out_path, String) == ""
                    @test read(err_path, String) ==
                        "AgentRuleLint: unknown rule id: $id\n"
                end
            end
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "preset name stays unknown with did-you-mean hint (library + CLI)" begin
        # Preset names are not rule ids; hint points at the canonical slug (#83 review).
        id = "shell-safety"
        hint_msg =
            "unknown rule id: shell-safety (did you mean shell-safety/process-pattern?)"
        tmp = _temp_corpus_root()
        try
            @test_throws ArgumentError hint_msg AgentRuleLint.explain_rule(
                id;
                root = tmp,
            )

            mktemp() do out_path, _
                mktemp() do err_path, _
                    code = cd(tmp) do
                        open(out_path, "w") do out_io
                            open(err_path, "w") do err_io
                                redirect_stdout(out_io) do
                                    redirect_stderr(err_io) do
                                        AgentRuleLint.cli_main(["explain", id])
                                    end
                                end
                            end
                        end
                    end
                    @test code == 2
                    @test read(out_path, String) == ""
                    @test read(err_path, String) == "AgentRuleLint: $hint_msg\n"
                end
            end
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "minimal config: check and explain" begin
        fixture = read(
            joinpath(OUTPUT_GOLDEN_DIR, "minimal_config", "AgentRuleLintConfig.toml"),
            String,
        )
        tmp = _temp_corpus_root(; config_text = fixture)
        try
            gdir = joinpath(OUTPUT_GOLDEN_DIR, "minimal_config")
            cfg = joinpath(tmp, ".AgentRuleLintConfig.toml")
            _assert_check_goldens(gdir, tmp; config_path = cfg)
            _assert_explain_goldens(gdir, OUTPUT_GOLDEN_EXPLAIN_IDS; root = tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end
end
