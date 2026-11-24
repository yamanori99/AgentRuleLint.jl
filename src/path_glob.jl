# Project-rule path globs: compile at config load to anchored regexes.
# Executable spec: `test/test_project_rules_paths.jl`.
#
# Supported syntax (repo-relative; whole path anchored, not basename-only):
# - `*` and `?` match within one path segment (never cross `/`).
# - `**` only as a whole segment: `**`, `**/x`, `x/**`, `x/**/y` (plus `/**` suffix).
# Rejected with `ConfigError` (fail-closed): empty, leading `/`, `..` segments,
# `[` `]` `{` `}`, `***`, `a**b`, `**foo`, or any `**` inside a longer segment.

const _GLOB_REGEX_SPECIALS = ('\\', '^', '$', '.', '|', '?', '+', '(', ')', '[', ']', '{', '}')

function _write_glob_literal!(out::IO, c::Char)
    if c in _GLOB_REGEX_SPECIALS
        write(out, '\\', c)
    else
        write(out, c)
    end
    return nothing
end

function _validate_glob_segment!(seg::AbstractString, label::AbstractString, pattern::AbstractString)
    seg == "**" && return
    occursin("**", seg) &&
        throw(ConfigError("** must be a whole path segment in $label: '$pattern'"))
    return nothing
end

"""
    validate_path_glob_pattern!(pattern, label)

Fail-closed validation for supported path-glob syntax (`*`, `?`, `**` as whole segment only).
"""
function validate_path_glob_pattern!(pattern::AbstractString, label::AbstractString)
    pat = replace(String(pattern), '\\' => '/')
    isempty(pat) && throw(ConfigError("empty glob pattern in $label"))
    startswith(pat, "/") &&
        throw(ConfigError("glob must be repo-relative (no leading '/') in $label: '$pattern'"))
    for c in ('[', ']', '{', '}')
        occursin(c, pat) &&
            throw(ConfigError("unsupported glob syntax '$c' in $label: '$pattern'"))
    end
    occursin("***", pat) &&
        throw(ConfigError("invalid glob (adjacent stars) in $label: '$pattern'"))
    for seg in split(pat, '/'; keepempty = false)
        seg == ".." &&
            throw(ConfigError("path segment '..' not allowed in $label: '$pattern'"))
        _validate_glob_segment!(seg, label, pattern)
    end
    return nothing
end

function _compile_path_glob_body(pat::AbstractString)
    out = IOBuffer()
    write(out, '^')
    i = firstindex(pat)
    lasti = lastindex(pat)
    while i <= lasti
        c = pat[i]
        if c == '*'
            n1 = nextind(pat, i)
            if n1 <= lasti && pat[n1] == '*'
                n2 = nextind(pat, n1)
                if n2 <= lasti && pat[n2] == '/'
                    write(out, "(?:[^/]+/)*")
                    i = nextind(pat, n2)
                elseif n2 > lasti
                    write(out, "(?:/.*)?")
                    i = nextind(pat, n1)
                else
                    write(out, "(?:[^/]+/)*")
                    i = n2
                end
            else
                write(out, "[^/]*")
                i = nextind(pat, i)
            end
        elseif c == '?'
            write(out, "[^/]")
            i = nextind(pat, i)
        else
            _write_glob_literal!(out, c)
            i = nextind(pat, i)
        end
    end
    return String(take!(out))
end

"""
    compile_path_glob(pattern, label) -> Regex

Compile a repo-relative `[[project_rules]].paths` glob to an anchored regex.

**Syntax:** `*` / `?` per path segment; `**` only as a whole segment (`**`, `**/x`,
`x/**`, `x/**/y`, including `prefix/**` meaning `prefix` or anything under it).
Matches the full repo-relative path (no basename-only fallback).

**Rejected** (`ConfigError`, config load fail-closed): empty pattern, leading `/`,
`..` segments, bracket/brace groups, `***`, embedded `**` (e.g. `a**b`, `**foo`).

Non-`.jl` targets selected by these globs are linted without Julia parsing; see
`read_parsed_file` (UTF-8) and `expect_audit_text_diagnostics` in `expect.jl`.
Tests: `test/test_project_rules_paths.jl`.
"""
function compile_path_glob(pattern::AbstractString, label::AbstractString)
    pat = replace(String(pattern), '\\' => '/')
    validate_path_glob_pattern!(pat, label)
    if pat == "**"
        return Regex("^.*\$")
    end
    suffix_extra = ""
    core = pat
    if endswith(pat, "/**")
        core = pat[1:(end - 3)]
        suffix_extra = "(?:/.*)?"
        if isempty(core)
            return Regex("^.*\$")
        end
        validate_path_glob_pattern!(core, label)
    end
    body = _compile_path_glob_body(core)
    return Regex(body * suffix_extra * "\$")
end

function path_matches_glob(path::AbstractString, regexes::Vector{Regex})
    p = replace(String(path), '\\' => '/')
    return any(r -> occursin(r, p), regexes)
end

function project_rule_path_regexes(policy::PolicyBundle)
    out = Regex[]
    for pr in policy.project_rules
        append!(out, pr.path_regexes)
    end
    return out
end

function julia_source_path(path::AbstractString)
    return endswith(lowercase(replace(String(path), '\\' => '/')), ".jl")
end

function selected_for_lint(path::AbstractString, project_regexes::Vector{Regex})
    julia_source_path(path) && return true
    return path_matches_glob(path, project_regexes)
end
