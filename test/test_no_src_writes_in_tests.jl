# Fail closed if any test file writes to tracked repo `src/` in-process (#94).
using Test

const TEST_DIR = @__DIR__
const REPO_SRC_MARKERS = (
    r"joinpath\(\s*ROOT\s*,\s*\"src\"",
    r"joinpath\(\s*repo_root\s*,\s*\"src\"",
    r"joinpath\(\s*dirname\(@__DIR__\)\s*,\s*\"src\"",
    r"joinpath\(\s*normpath\(joinpath\(@__DIR__\s*,\s*\"\.\.\"\)\)\s*,\s*\"src\"",
)

const WRITE_OPS = (
    r"\bwrite\s*\(",
    r"\bopen\s*\(",
    r"\bcp\s*\(",
    r"\bmv\s*\(",
)

function _is_exempt(rel::AbstractString)
    # temp-copy harness may write patched sources inside an isolated tree.
    return basename(rel) == "mutation_lib.jl" && occursin("mutation", rel)
end

function _line_writes_tracked_src(line::AbstractString)
    startswith(strip(line), "#") && return false
    any(op -> occursin(op, line), WRITE_OPS) || return false
    occursin("\"src\"", line) || return false
    any(marker -> occursin(marker, line), REPO_SRC_MARKERS) && return true
    # write(path, …) after `path = joinpath(ROOT, "src", …)` (same file).
    return false
end

function _path_var_writes_to_src(lines::Vector{String})
    hits = Tuple{Int, String}[]
    for (i, line) in enumerate(lines)
        startswith(strip(line), "#") && continue
        m = match(r"^\s*(\w+)\s*=\s*joinpath\(", line)
        m === nothing && continue
        occursin("\"src\"", line) || continue
        occursin(r"\btmp\b|mktemp|staging", line) && continue
        any(marker -> occursin(marker, line), REPO_SRC_MARKERS) || continue
        var = m.captures[1]
        for j in (i + 1):min(i + 12, length(lines))
            nj = lines[j]
            occursin(Regex("\\bwrite\\s*\\(\\s*$var\\s*,"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bopen\\s*\\(\\s*$var\\s*,"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bcp\\s*\\([^,]+,\\s*$var"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bmv\\s*\\([^,]+,\\s*$var"), nj) && push!(hits, (j, nj))
        end
    end
    return hits
end

@testset "no in-process writes to tracked src/" begin
    offenders = String[]
    for (dir, _, files) in walkdir(TEST_DIR)
        for f in files
            endswith(f, ".jl") || continue
            abs = joinpath(dir, f)
            rel = relpath(abs, TEST_DIR)
            startswith(rel, "corpus") && continue
            _is_exempt(rel) && continue
            text = read(abs, String)
            lines = String[strip(String(l), '\r') for l in split(text, '\n')]
            for (i, line) in enumerate(lines)
                _line_writes_tracked_src(line) &&
                    push!(offenders, "test/$rel:$i: $line")
            end
            for (i, line) in _path_var_writes_to_src(lines)
                push!(offenders, "test/$(rel):$i: $line")
            end
        end
    end
    @test isempty(offenders)
    if !isempty(offenders)
        for o in offenders
            @error "test writes tracked src/" o
        end
    end
end
