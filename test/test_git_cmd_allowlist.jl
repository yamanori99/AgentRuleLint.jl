# Guard: no raw git command construction outside src/git.jl and test/git_test_helpers.jl (#67, #93).

function _git_cmd_allowlist_paths(root::AbstractString)
    r = abspath(String(root))
    return (
        joinpath(r, "src", "git.jl"),
        joinpath(r, "test", "git_test_helpers.jl"),
        joinpath(r, "test", "test_git_cmd_allowlist.jl"),
        joinpath(r, "test", "mutation", "mutation_lib.jl"),
        joinpath(r, "test", "mutation", "run_all_lib.jl"),
    )
end

const _RE_CMD_GIT_DQ = Regex("Cmd\\(\\[\\s*\"git\"")
const _RE_CMD_GIT_SQ = Regex("Cmd\\(\\[\\s*'git'")
const _RE_BACKTICK_GIT = Regex("`git\\s")
const _RE_DOLLAR_GIT = Regex(raw"\$\(git ")

function _line_in_docstring_or_comment(line::AbstractString, in_docstring::Bool)
    s = strip(String(line))
    startswith(s, '#') && return (in_docstring, true)
    in_docstring && return (in_docstring, true)
    return (in_docstring, false)
end

function _advance_docstring_state(line::AbstractString, in_docstring::Bool)
    for _ in 1:count("\"\"\"", line)
        in_docstring = !in_docstring
    end
    return in_docstring
end

function _line_violates_git_allowlist(line::AbstractString)
    s = String(line)
    occursin(_RE_CMD_GIT_DQ, s) && return "Cmd([\"git\""
    occursin(_RE_CMD_GIT_SQ, s) && return "Cmd(['git'"
    if occursin(_RE_BACKTICK_GIT, s)
        occursin("git mv", s) && return nothing
        return "backtick git"
    end
    occursin(_RE_DOLLAR_GIT, s) && return "\$(git "
    return nothing
end

function _scan_git_cmd_allowlist(root::AbstractString)
    allow = Set(map(abspath, _git_cmd_allowlist_paths(root)))
    violations = Tuple{String, Int, String}[]
    for dir in ("src", "test")
        base = joinpath(root, dir)
        for (dp, _, files) in walkdir(base)
            for f in files
                endswith(f, ".jl") || continue
                path = abspath(joinpath(dp, f))
                path in allow && continue
                rel_path = replace(relpath(path, root), '\\' => '/')
                text = read(path, String)
                in_docstring = false
                for (i, line) in enumerate(split(text, '\n'; keepempty = true))
                    if in_docstring
                        in_docstring = _advance_docstring_state(line, in_docstring)
                        continue
                    end
                    if startswith(strip(String(line)), "\"\"\"")
                        in_docstring = _advance_docstring_state(line, in_docstring)
                        continue
                    end
                    _, skip = _line_in_docstring_or_comment(line, false)
                    skip && continue
                    kind = _line_violates_git_allowlist(line)
                    kind === nothing && continue
                    push!(violations, (rel_path, i, kind))
                end
            end
        end
    end
    return violations
end

@testset "git command construction allowlist" begin
    violations = _scan_git_cmd_allowlist(ROOT)
    for (file, line, kind) in violations
        @error "raw git command construction" file line kind
    end
    @test isempty(violations)
end
