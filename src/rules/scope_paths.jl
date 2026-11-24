# Built-in `scope-paths`: trusted `--allow-paths` gate (diff only).

function compile_allow_path_globs(raw::Vector{String})
    isempty(raw) &&
        throw(ConfigError("--allow-paths requires at least one non-empty glob"))
    out = Regex[]
    for (j, g) in enumerate(raw)
        label = "allow-paths[$j]"
        pat = strip(String(g))
        isempty(pat) && throw(ConfigError("--allow-paths: empty glob at index $j"))
        validate_path_glob_pattern!(pat, label)
        push!(out, compile_path_glob(pat, label))
    end
    return out
end

function parse_allow_paths_cli(raw::AbstractString)
    s = strip(String(raw))
    isempty(s) && throw(ConfigError("--allow-paths requires a non-empty glob list"))
    raw_parts = String[strip(p) for p in split(s, ',')]
    isempty(raw_parts) && throw(ConfigError("--allow-paths requires a non-empty glob list"))
    all(isempty, raw_parts) && throw(ConfigError("--allow-paths requires a non-empty glob list"))
    filter!(!isempty, raw_parts)
    return compile_allow_path_globs(raw_parts)
end

function _scope_paths_spec(policy::PolicyBundle)
    spec = get(policy.rules, SCOPE_PATHS_RULE, nothing)
    spec === nothing &&
        throw(InternalError("built-in rule $SCOPE_PATHS_RULE missing from policy"))
    return spec
end

function _scope_paths_diag(path::String, message::String, policy::PolicyBundle)
    spec = _scope_paths_spec(policy)
    return Violation(
        SCOPE_PATHS_RULE,
        :agentrulelint,
        spec.level,
        path,
        Span(1, 1, 1, 1),
        1,
        "",
        :none,
        false,
        message,
        spec.intent,
        spec.do_not,
    )
end

function _path_matches_allowlist(path::AbstractString, allow_regexes::Vector{Regex})
    p = normalize_path(path)
    return any(r -> occursin(r, p), allow_regexes)
end

function _event_paths(ev::DiffPathEvent)
    return ev.status in ('R', 'C') ? (ev.old_path, ev.path) : (ev.path,)
end

"""
    enforce_scope_paths(events, allow_regexes, policy)

Every changed path (including deletes and both sides of renames) must match an allow glob.
"""
function enforce_scope_paths(events::Vector{DiffPathEvent}, allow_regexes::Vector{Regex}, policy::PolicyBundle)
    _scope_paths_spec(policy)
    out = Violation[]
    seen = Set{String}()
    for ev in events
        for p in _event_paths(ev)
            p in seen && continue
            push!(seen, p)
            _path_matches_allowlist(p, allow_regexes) && continue
            msg = "change outside --allow-paths scope"
            push!(out, _scope_paths_diag(p, msg, policy))
        end
    end
    return out
end

function validate_allow_paths_kw(allow_paths, diff_base)
    allow_paths === nothing && return nothing
    diff_base === nothing &&
        throw(ConfigError("--allow-paths requires --diff (trusted scope mode)"))
    return allow_paths
end
