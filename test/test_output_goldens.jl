# Output goldens under test/goldens/output/ are pinned from merge-base main
# (see PR #77 / issue #25). They change only for intended output changes, which
# the PR that updates them must state. Never regenerate goldens to clear a
# failing neutrality check on a structure-only refactor.
#
# Three configurations:
# 1. Repo dogfood config (ROOT) — goldens in test/goldens/output/{check_*,explain/}
# 2. No config file — goldens in test/goldens/output/no_config/
# 3. Minimal config (rules without intent/do_not) — goldens in
#    test/goldens/output/minimal_config/ (fixture TOML:
#    minimal_config/AgentRuleLintConfig.toml)

const OUTPUT_GOLDEN_DIR = joinpath(ROOT, "test", "goldens", "output")
const OUTPUT_GOLDEN_WIDTH = 80
const OUTPUT_GOLDEN_EXPLAIN_IDS = (
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

# Under `default_policy` (no config file), inactive presets / undeclared rules
# are not registered, so explain is only exercised for these ids (same as main).
const OUTPUT_GOLDEN_NO_CONFIG_EXPLAIN_IDS = (
    "expect-audit",
    "ceiling-ratchet",
    "manifest-sync",
    "protected-paths",
    "scope-paths",
    "silent-catch",
)

# Not registered under `default_policy` / inactive presets (pinned vs merge-base main).
const OUTPUT_GOLDEN_NO_CONFIG_INACTIVE_EXPLAIN_IDS = (
    "shell-safety/process-pattern",
    "test-integrity",
    "unsafe-boundary",
)

"""Drop the JSONL header object (`"type":"header"`).

The header embeds `julia_version` and `parser`, which differ across Julia 1.13
vs 1.14-pre even when diagnostics are identical.
"""
function _golden_json_without_header(text::AbstractString)
    lines = split(text, '\n'; keepempty = true)
    kept = String[]
    for line in lines
        isempty(line) && (push!(kept, line); continue)
        if occursin("\"type\":\"header\"", line) || occursin("\"type\": \"header\"", line)
            continue
        end
        push!(kept, line)
    end
    return join(kept, '\n')
end

"""Normalize human/agent text for cross-environment comparison.

Pinned with `output_width=$(OUTPUT_GOLDEN_WIDTH)` so wrapping does not depend on
TTY/`COLUMNS`. Strip ANSI in case a caller enables color. Paths in these formats
are repo-relative, so no absolute-path rewrite is needed. Package version in the
banner is the project pin (`0.1.0-DEV`) and is part of the golden.
"""
function _golden_normalize_text(text::AbstractString)
    return AgentRuleLint.strip_ansi(text)
end

function _explain_golden_filename(id::AbstractString)
    return replace(id, "/" => "__") * ".txt"
end

function _explain_root_for(id::AbstractString, repo_root::AbstractString)
    id != "shell-safety/process-pattern" && return repo_root, nothing
    # Preset is inactive in the dogfood config; enable it in a temp root so
    # `explain` matches the pinned golden (same approach used when capturing).
    tmp = mktempdir()
    cfg = read(joinpath(repo_root, ".AgentRuleLintConfig.toml"), String)
    if !occursin(r"(?m)^presets\s*=", cfg)
        cfg = replace(
            cfg,
            r"(?m)^(max_hits_per_rule\s*=\s*\d+\n)" =>
                s"\1presets = [\"shell-safety\"]\n";
            count = 1,
        )
    end
    write(joinpath(tmp, ".AgentRuleLintConfig.toml"), cfg)
    return tmp, tmp
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

function _assert_explain_goldens(
        golden_dir::AbstractString,
        ids;
        root::AbstractString,
        explain_root_for = nothing,
    )
    for id in ids
        explain_root = root
        cleanup = nothing
        if explain_root_for !== nothing
            explain_root, cleanup = explain_root_for(id, root)
        end
        try
            got = AgentRuleLint.explain_rule(id; root = explain_root)
            want = read(
                joinpath(golden_dir, "explain", _explain_golden_filename(id)),
                String,
            )
            # Golden file = explain body + one trailing newline (tracked-file rule).
            @test got * "\n" == want
        finally
            cleanup !== nothing && rm(cleanup; recursive = true, force = true)
        end
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
    @testset "repo config: check human/json/agent over test/corpus" begin
        _assert_check_goldens(OUTPUT_GOLDEN_DIR, ROOT)
    end

    @testset "repo config: explain goldens" begin
        _assert_explain_goldens(
            OUTPUT_GOLDEN_DIR,
            OUTPUT_GOLDEN_EXPLAIN_IDS;
            root = ROOT,
            explain_root_for = _explain_root_for,
        )
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

    @testset "no config: inactive rules stay unknown (library + CLI)" begin
        # Merge-base main (`3305407`): under a tree with no config file,
        # `explain_rule` throws `ArgumentError("unknown rule id: <id>")` and
        # `cli_main(["explain", id])` exits 2 with empty stdout and
        # `AgentRuleLint: unknown rule id: <id>\n` on stderr.
        tmp = _temp_corpus_root()
        try
            @assert !isfile(joinpath(tmp, ".AgentRuleLintConfig.toml"))
            for id in OUTPUT_GOLDEN_NO_CONFIG_INACTIVE_EXPLAIN_IDS
                err = try
                    AgentRuleLint.explain_rule(id; root = tmp)
                    nothing
                catch e
                    e
                end
                @test err isa ArgumentError
                @test err.msg == "unknown rule id: $id"

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
