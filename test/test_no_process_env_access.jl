# Guard: `src/` must not read process environment / host probes except allowlisted (issue #155 Part 1).

const _SRC_ROOT = joinpath(ROOT, "src")

const _ENV_ACCESS_ALLOWLIST = [
    # (relpath under repo, construct id, reason)
    ("src/git.jl", :Sys_which, "Resolve PATH git executable for isolated git child"),
    ("src/git.jl", :addenv, "Apply isolated git environment overrides on git child"),
    ("src/git.jl", :setenv, "Run isolated git with explicit working directory"),
]

const _ENV_SCAN_PATTERNS = (
    (; id = :ENV_index, rx = Regex("""\\bENV\\s*\\[""")),
    (; id = :ENV_get, rx = Regex("""\\bget\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_haskey, rx = Regex("""\\bhaskey\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_keys, rx = Regex("""\\bkeys\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_values, rx = Regex("""\\bvalues\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_pairs, rx = Regex("""\\bpairs\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_copy, rx = Regex("""\\bcopy\\s*\\(\\s*ENV\\b""")),
    (; id = :ENV_iterate, rx = Regex("""\\bin\\s+ENV\\b""")),
    (; id = :getenv, rx = Regex("""\\bgetenv\\s*\\(""")),
    (; id = :hasenv, rx = Regex("""\\bhasenv\\s*\\(""")),
    (; id = :withenv, rx = Regex("""\\bwithenv\\s*\\(""")),
    (; id = :addenv, rx = Regex("""\\baddenv\\b""")),
    (; id = :setenv, rx = Regex("""\\bsetenv\\b""")),
    (; id = :Sys_which, rx = Regex("""\\bSys\\.which\\s*\\(""")),
    (; id = :homedir, rx = Regex("""\\bhomedir\\s*\\(""")),
    (; id = :time, rx = Regex("""\\btime\\s*\\(\\s*\\)""")),
    (; id = :now, rx = Regex("""\\bnow\\s*\\(\\s*\\)""")),
    (; id = :Dates_now, rx = Regex("""\\bDates\\.now\\b""")),
    (; id = :randstring, rx = Regex("""\\brandstring\\s*\\(""")),
    (; id = :rand, rx = Regex("""\\brand\\s*\\(""")),
)

function _src_julia_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    return sort(out)
end

function _skip_src_line_for_env_scan(line::AbstractString, in_docstring::Bool)
    if in_docstring
        return _advance_docstring_state(line, in_docstring), true
    end
    startswith(strip(String(line)), '#') && return in_docstring, true
    occursin("\"\"\"", line) && return _advance_docstring_state(line, in_docstring), true
    return in_docstring, false
end

function _advance_docstring_state(line::AbstractString, in_docstring::Bool)
    for _ in 1:count("\"\"\"", line)
        in_docstring = !in_docstring
    end
    return in_docstring
end

function _allowlisted(rel_path::AbstractString, construct::Symbol)
    for (file, id, _) in _ENV_ACCESS_ALLOWLIST
        file == rel_path && id == construct && return true
    end
    return false
end

function collect_src_process_env_violations(repo_root::AbstractString)
    src = joinpath(repo_root, "src")
    violations = Tuple{String, Int, Symbol, SubString{String}}[]
    for path in _src_julia_files(src)
        rel = replace(relpath(path, repo_root), '\\' => '/')
        text = read(path, String)
        in_docstring = false
        for (i, line) in enumerate(split(text, '\n'; keepempty = true))
            in_docstring, skip = _skip_src_line_for_env_scan(line, in_docstring)
            skip && continue
            for pat in _ENV_SCAN_PATTERNS
                m = match(pat.rx, line)
                m === nothing && continue
                _allowlisted(rel, pat.id) && continue
                push!(violations, (rel, i, pat.id, m.match))
            end
        end
    end
    return violations
end

function _run_env_guard_tests()
    @testset "src/ process-environment access guard" begin
        @testset "docstrings and comments are not matches (width.jl ENV mention)" begin
            doc = read(joinpath(ROOT, "src", "format", "width.jl"), String)
            @test occursin("ENV[\"COLUMNS\"]", doc)
            v = collect_src_process_env_violations(ROOT)
            @test isempty(filter(x -> x[1] == "src/format/width.jl", v))
        end

        violations = collect_src_process_env_violations(ROOT)
        for (file, line, construct, snippet) in violations
            @error "process-environment access outside allowlist" file line construct snippet
        end
        @test isempty(violations)

        used = Set{Tuple{String, Symbol}}()
        for path in _src_julia_files(_SRC_ROOT)
            rel = replace(relpath(path, ROOT), '\\' => '/')
            text = read(path, String)
            in_docstring = false
            for line in split(text, '\n'; keepempty = true)
                in_docstring, skip = _skip_src_line_for_env_scan(line, in_docstring)
                skip && continue
                for pat in _ENV_SCAN_PATTERNS
                    match(pat.rx, line) === nothing && continue
                    push!(used, (rel, pat.id))
                end
            end
        end
        stale = [(f, id) for (f, id, _) in _ENV_ACCESS_ALLOWLIST if (f, id) ∉ used]
        @test isempty(stale) || error(
            "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
        )
    end
    return nothing
end

get(ENV, "AGENTRULELINT_ENV_GUARD_PROBE", "") == "1" || _run_env_guard_tests()
