# Heuristic tripwire: flag likely in-process writes to tracked `src/` in tests (#94).
# This is not a formal guarantee—accidental bypasses are possible. The real guard is
# the temp-copy mutation harness (`test/mutation/mutation_lib.jl`), which never patches
# the working tree's `src/`.
using Test

const TEST_DIR = @__DIR__

const REPO_SRC_MARKERS = (
    r"joinpath\(\s*ROOT\s*,\s*\"src\"",
    r"joinpath\(\s*repo_root\s*,\s*\"src\"",
    r"joinpath\(\s*dirname\(@__DIR__\)\s*,\s*\"src\"",
    r"joinpath\(\s*normpath\(joinpath\(@__DIR__\s*,\s*\"\.\.\"\)\)\s*,\s*\"src\"",
)

const PACKAGE_SRC_MARKERS = (
    r"pkgdir\(\s*AgentRuleLint\s*\)",
    r"pathof\(\s*AgentRuleLint\s*\)",
    r"dirname\(\s*pathof\(\s*AgentRuleLint\s*\)\s*\)",
)

const WRITE_OPS = (
    r"\bwrite\s*\(",
    r"\bopen\s*\(",
    r"\bcp\s*\(",
    r"\bmv\s*\(",
)

const SRC_ROOT_ASSIGN_MARKERS = (REPO_SRC_MARKERS..., PACKAGE_SRC_MARKERS...)
const SRC_ROOT_ASSIGN_EXACT = r"joinpath\(\s*ROOT\s*,\s*\"src\"\s*\)"

function _is_exempt(rel::AbstractString)
    return basename(rel) == "mutation_lib.jl" && occursin("mutation", rel)
end

function _line_has_tracked_src_target(line::AbstractString)
    any(m -> occursin(m, line), PACKAGE_SRC_MARKERS) && return true
    occursin("\"src\"", line) || return false
    return any(marker -> occursin(marker, line), REPO_SRC_MARKERS)
end

function _line_writes_tracked_src(line::AbstractString)
    startswith(strip(line), "#") && return false
    any(op -> occursin(op, line), WRITE_OPS) || return false
    return _line_has_tracked_src_target(line)
end

function _rhs_defines_src_root(rhs::AbstractString)
    occursin(SRC_ROOT_ASSIGN_EXACT, rhs) && return true
    any(m -> occursin(m, rhs), PACKAGE_SRC_MARKERS) && return true
    occursin("\"src\"", rhs) || return false
    return any(marker -> occursin(marker, rhs), REPO_SRC_MARKERS)
end

function _collect_src_root_vars(lines::Vector{String})
    vars = Set{String}()
    for line in lines
        startswith(strip(line), "#") && continue
        m = match(r"^\s*(\w+)\s*=\s*(.+)$", line)
        m === nothing && continue
        var = m.captures[1]
        rhs = m.captures[2]
        (var === nothing || rhs === nothing) && continue
        occursin(r"\btmp\b|mktemp|staging", line) && continue
        _rhs_defines_src_root(strip(String(rhs))) && push!(vars, String(var))
    end
    return vars
end

function _joinpath_var_writes(var::AbstractString, line::AbstractString)
    occursin(Regex("\\bwrite\\s*\\(\\s*joinpath\\s*\\(\\s*$var\\b"), line) && return true
    occursin(Regex("\\bopen\\s*\\(\\s*joinpath\\s*\\(\\s*$var\\b"), line) && return true
    occursin(Regex("\\bcp\\s*\\([^,]+,\\s*joinpath\\s*\\(\\s*$var\\b"), line) && return true
    occursin(Regex("\\bmv\\s*\\([^,]+,\\s*joinpath\\s*\\(\\s*$var\\b"), line) && return true
    return false
end

function _path_var_writes_to_src(lines::Vector{String})
    hits = Tuple{Int, String}[]
    src_vars = _collect_src_root_vars(lines)
    for (i, line) in enumerate(lines)
        startswith(strip(line), "#") && continue
        m = match(r"^\s*(\w+)\s*=\s*joinpath\(", line)
        m === nothing && continue
        occursin("\"src\"", line) || continue
        occursin(r"\btmp\b|mktemp|staging", line) && continue
        any(marker -> occursin(marker, line), REPO_SRC_MARKERS) || continue
        var = m.captures[1]
        var === nothing && continue
        var = String(var)
        for j in (i + 1):min(i + 12, length(lines))
            nj = lines[j]
            occursin(Regex("\\bwrite\\s*\\(\\s*$var\\s*,"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bopen\\s*\\(\\s*$var\\s*,"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bcp\\s*\\([^,]+,\\s*$var"), nj) && push!(hits, (j, nj))
            occursin(Regex("\\bmv\\s*\\([^,]+,\\s*$var"), nj) && push!(hits, (j, nj))
        end
    end
    for var in src_vars
        for (i, line) in enumerate(lines)
            startswith(strip(line), "#") && continue
            _joinpath_var_writes(var, line) && push!(hits, (i, line))
        end
    end
    return hits
end

function _lines_from_text(text::AbstractString)
    return String[strip(String(l), '\r') for l in split(text, '\n')]
end

function offenders_in_text(rel::AbstractString, text::AbstractString)
    _is_exempt(rel) && return String[]
    lines = _lines_from_text(text)
    offenders = String[]
    for (i, line) in enumerate(lines)
        _line_writes_tracked_src(line) && push!(offenders, "test/$rel:$i: $line")
    end
    for (i, line) in _path_var_writes_to_src(lines)
        push!(offenders, "test/$rel:$i: $line")
    end
    return offenders
end

@testset "fixture strings for src-write tripwire" begin
    @testset "pkgdir(AgentRuleLint)" begin
        sample = "write(joinpath(pkgdir(AgentRuleLint), \"syntax\", \"x.jl\"), data)"
        @test !isempty(offenders_in_text("fixture_pkgdir.jl", sample))
    end
    @testset "pathof(AgentRuleLint)" begin
        sample = "cp(\"x\", joinpath(pathof(AgentRuleLint), \"syntax\", \"y.jl\"))"
        @test !isempty(offenders_in_text("fixture_pathof.jl", sample))
    end
    @testset "dirname(pathof(AgentRuleLint))" begin
        sample = "open(joinpath(dirname(pathof(AgentRuleLint)), \"rules\", \"x.jl\"), \"w\")"
        @test !isempty(offenders_in_text("fixture_dirname_pathof.jl", sample))
    end
    @testset "src root var then joinpath write" begin
        sample = """
        src_base = joinpath(ROOT, "src")
        write(joinpath(src_base, "syntax", "x.jl"), data)
        """
        @test !isempty(offenders_in_text("fixture_src_base.jl", sample))
    end
    @testset "temp tree src is not flagged" begin
        sample = "write(joinpath(tmp, \"src\", \"rules\", \"x.jl\"), data)"
        @test isempty(offenders_in_text("fixture_temp.jl", sample))
    end
end

@testset "no in-process writes to tracked src/" begin
    offenders = String[]
    for (dir, _, files) in walkdir(TEST_DIR)
        for f in files
            endswith(f, ".jl") || continue
            abs = joinpath(dir, f)
            rel = relpath(abs, TEST_DIR)
            startswith(rel, "corpus") && continue
            # Fixture strings for this scanner live in this file; see `fixture strings` testset.
            basename(rel) == "test_no_src_writes_in_tests.jl" && continue
            append!(offenders, offenders_in_text(rel, read(abs, String)))
        end
    end
    @test isempty(offenders)
    if !isempty(offenders)
        for o in offenders
            @error "test writes tracked src/" o
        end
    end
end
