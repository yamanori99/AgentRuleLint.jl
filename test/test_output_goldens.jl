# Output goldens under test/goldens/output/ are pinned from merge-base main
# (see PR #77 / issue #25). They change only for intended output changes, which
# the PR that updates them must state. Never regenerate goldens to clear a
# failing neutrality check on a structure-only refactor.

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

@testset "output goldens (main neutrality)" begin
    @testset "check human/json/agent over test/corpus" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
        plain_io = IOContext(IOBuffer(), :color => false)
        human = _golden_normalize_text(
            AgentRuleLint.format_human(
                res;
                root = ROOT,
                io = plain_io,
                output_width = OUTPUT_GOLDEN_WIDTH,
            ),
        )
        agent = _golden_normalize_text(
            AgentRuleLint.format_agent(
                res;
                root = ROOT,
                io = plain_io,
                output_width = OUTPUT_GOLDEN_WIDTH,
            ),
        )
        json = _golden_json_without_header(AgentRuleLint.format_json(res))
        @test human ==
            _golden_normalize_text(read(joinpath(OUTPUT_GOLDEN_DIR, "check_human.txt"), String))
        @test agent ==
            _golden_normalize_text(read(joinpath(OUTPUT_GOLDEN_DIR, "check_agent.txt"), String))
        @test json ==
            _golden_json_without_header(read(joinpath(OUTPUT_GOLDEN_DIR, "check_json.txt"), String))
    end

    @testset "explain goldens" begin
        for id in OUTPUT_GOLDEN_EXPLAIN_IDS
            root, cleanup = _explain_root_for(id, ROOT)
            try
                got = AgentRuleLint.explain_rule(id; root = root)
                want = read(
                    joinpath(OUTPUT_GOLDEN_DIR, "explain", _explain_golden_filename(id)),
                    String,
                )
                # Trailing newline is file hygiene on the golden; explain_rule
                # itself does not end with `\n`.
                @test rstrip(got) == rstrip(want)
            finally
                cleanup !== nothing && rm(cleanup; recursive = true, force = true)
            end
        end
    end
end
