using AgentRuleLint
using Test

# ROOT comes from ParallelTestRunner init_code in test/runtests.jl.

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

@testset "config filename single source of truth" begin
    new_lit = AgentRuleLint.CONFIG_FILENAME
    legacy_lit = AgentRuleLint.LEGACY_CONFIG_FILENAME

    @testset "src/ has no config filename literals outside constants" begin
        for path in _src_jl_files()
            rel = replace(relpath(path, ROOT), '\\' => '/')
            text = read(path, String)
            if rel == "src/config.jl"
                @test occursin(new_lit, text)
                @test occursin(legacy_lit, text)
                continue
            end
            occursin(new_lit, text) &&
                error("config filename literal in $rel; use CONFIG_FILENAME")
            occursin(legacy_lit, text) &&
                error("legacy config filename literal in $rel; use LEGACY_CONFIG_FILENAME")
            @test true
        end
    end

    @testset "init header written once" begin
        body = AgentRuleLint.render_init_config()
        @test startswith(body, AgentRuleLint.CONFIG_FILE_HEADER)
        hdr_count = count(AgentRuleLint.CONFIG_FILE_HEADER, body)
        @test hdr_count == 1
    end
end