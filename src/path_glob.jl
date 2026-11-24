# Path glob → anchored regex (`*`/`?` do not cross `/`; `**` matches path segments).

const _GLOB_REGEX_SPECIALS = ('\\', '^', '$', '.', '|', '?', '+', '(', ')', '[', ']', '{', '}')

function _write_glob_literal!(out::IO, c::Char)
    if c in _GLOB_REGEX_SPECIALS
        write(out, '\\', c)
    else
        write(out, c)
    end
    return nothing
end

"""
    compile_path_glob(pattern, label) -> Regex

Compile a repo-relative path glob. Invalid patterns throw `ConfigError` (fail-closed).
"""
function compile_path_glob(pattern::AbstractString, label::AbstractString)
    pat = replace(String(pattern), '\\' => '/')
    isempty(pat) && throw(ConfigError("empty glob pattern in $label"))
    if pat == "**"
        return Regex("^.*\$")
    end
    suffix_extra = ""
    if endswith(pat, "/**")
        pat = pat[1:(end - 3)]
        suffix_extra = "(?:/.*)?"
        isempty(pat) && return Regex("^.*\$")
    end
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
    write(out, suffix_extra)
    write(out, '$')
    body = String(take!(out))
    try
        return Regex(body)
    catch err
        throw(ConfigError("invalid glob '$pattern' in $label: $(err)"))
    end
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