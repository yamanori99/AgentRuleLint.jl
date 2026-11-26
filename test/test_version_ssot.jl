using AgentRuleLint
using Test

const ROOT = dirname(@__DIR__)

# Docstrings / user-facing rule text that legitimately name a release series (not
# `Project.toml` version duplication).
const VERSION_LITERAL_SRC_ALLOWLIST = Set{String}([
    joinpath("src", "rules", "protected_paths.jl"),
])

function _project_version_string()
    path = joinpath(ROOT, "Project.toml")
    for line in eachline(path)
        m = match(r"^version\s*=\s*\"(.+)\"", line)
        m === nothing && continue
        return m.captures[1]
    end
    error("version missing in $path")
end

function _src_jl_files()
    out = String[]
    for (root, _, files) in walkdir(joinpath(ROOT, "src"))
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    sort!(out)
    return out
end

@testset "package version single source of truth" begin
    pkg_ver = _project_version_string()
    @test string(AgentRuleLint.AGENTRULELINT_VERSION) == pkg_ver

    @testset "src/ has no pkgversion except the module root" begin
        for path in _src_jl_files()
            rel = relpath(path, ROOT)
            text = read(path, String)
            if rel == "src/AgentRuleLint.jl"
                @test occursin("pkgversion", text)
                continue
            end
            occursin("pkgversion", text) &&
                error("unexpected pkgversion in $rel")
            @test true
        end
    end

    @testset "src/ has no literal Project.toml version string" begin
        for path in _src_jl_files()
            rel = relpath(path, ROOT)
            rel in VERSION_LITERAL_SRC_ALLOWLIST && continue
            text = read(path, String)
            occursin(pkg_ver, text) &&
                error("package version literal in $rel; use AGENTRULELINT_VERSION")
            @test true
        end
    end

    @testset "config version pin validation uses AGENTRULELINT_VERSION" begin
        # Smoke: mismatch against a different major.minor must fail closed.
        bad = VersionNumber(99, 0, 0)
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.validate_agentrulelint_version!(
            bad,
            AgentRuleLint.AGENTRULELINT_VERSION,
        )
        @test AgentRuleLint.validate_agentrulelint_version!(
            VersionNumber(0, 1, 0),
            AgentRuleLint.AGENTRULELINT_VERSION,
        ) === nothing
    end
end