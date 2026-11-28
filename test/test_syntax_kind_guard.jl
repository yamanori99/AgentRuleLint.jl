@testset "syntax kind guard (Part A)" begin
    REPO = abspath(@__DIR__, "..")
    SRC = joinpath(REPO, "src")
    RULES = joinpath(SRC, "rules")

    function walk_jl_files(root::AbstractString)
        out = String[]
        for (dir, _, files) in walkdir(root)
            for f in files
                endswith(f, ".jl") || continue
                push!(out, joinpath(dir, f))
            end
        end
        return sort!(out)
    end

    function line_is_summary_comparison(line::AbstractString)
        occursin(r"summary\s*\(", line) || return false
        return occursin(r"==|!=|\sin\s+", line)
    end

    @testset "rules do not import JuliaSyntax" begin
        for path in walk_jl_files(RULES)
            for (i, line) in enumerate(eachline(path))
                occursin(r"\busing\s+JuliaSyntax\b", line) && error("JuliaSyntax import forbidden: $path:$i: $line")
                occursin(r"\bimport\s+JuliaSyntax\b", line) && error("JuliaSyntax import forbidden: $path:$i: $line")
            end
        end
    end

    @testset "src does not compare summary() output" begin
        for path in walk_jl_files(SRC)
            path == joinpath(SRC, "format", "report.jl") && continue
            path == joinpath(SRC, "syntax", "adapter_core.jl") && continue
            for (i, line) in enumerate(eachline(path))
                line_is_summary_comparison(line) && error("summary comparison forbidden: $path:$i: $line")
            end
        end
    end
end
