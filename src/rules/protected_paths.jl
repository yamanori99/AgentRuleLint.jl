# Built-in `protected-paths` (diff-scoped integrity; no inline expects).

const CEILINGS_REL_PATH = CEILINGS_REL

const AUTO_PROTECTED_EXACT = Set(
    [
        ".AgentRuleLintConfig.toml",
        ".JETLSConfig.toml",
        "JuliaManifest.toml",
        "LocalPreferences.toml",
    ],
)

function _is_manifest_lock(path::AbstractString)
    base = basename(String(path))
    return startswith(base, "Manifest") && endswith(base, ".toml")
end

function _is_workspace_project_toml(path::AbstractString)
    p = normalize_path(path)
    return endswith(p, "/Project.toml") || p == "Project.toml"
end

function _under_agentrulelint(path::AbstractString)
    p = normalize_path(path)
    return p == ".agentrulelint" || startswith(p, ".agentrulelint/")
end

function auto_protected_reason(path::AbstractString)
    p = normalize_path(path)
    p == ".AgentRuleLintConfig.toml" &&
        return "AgentRuleLint policy must not be weakened by agents."
    _under_agentrulelint(p) && return "`.agentrulelint/` integrity files require explicit human review."
    p == ".JETLSConfig.toml" &&
        return "JETLS diagnostic settings require explicit human review."
    _is_manifest_lock(p) && return "Manifest lockfiles must not be edited without review."
    p == "JuliaManifest.toml" && return "JuliaManifest.toml must not be edited without review."
    p == "LocalPreferences.toml" &&
        return "LocalPreferences.toml must not be edited without review."
    _is_workspace_project_toml(p) &&
        return "Project.toml changes are limited to semantic deps/compat additions."
    return "protected path changed"
end

function classify_protected_path(path::AbstractString, policy::PolicyBundle)
    p = normalize_path(path)
    for entry in policy.protected_path_globs
        occursin(entry.regex, p) && return true, entry.reason
    end
    p in AUTO_PROTECTED_EXACT && return true, auto_protected_reason(p)
    _under_agentrulelint(p) && return true, auto_protected_reason(p)
    _is_manifest_lock(p) && return true, auto_protected_reason(p)
    _is_workspace_project_toml(p) && return true, auto_protected_reason(p)
    return false, ""
end

function _protected_paths_spec(policy::PolicyBundle)
    spec = get(policy.rules, PROTECTED_PATHS_RULE, nothing)
    spec === nothing &&
        throw(InternalError("built-in rule $PROTECTED_PATHS_RULE missing from policy"))
    return spec
end

function _protected_paths_diag(path::String, message::String, policy::PolicyBundle)
    spec = _protected_paths_spec(policy)
    return Violation(
        PROTECTED_PATHS_RULE,
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

function _status_word(st::Char)
    st == 'A' && return "added"
    st == 'D' && return "deleted"
    st == 'R' && return "renamed"
    st == 'C' && return "copied"
    return "modified"
end

function _read_working_text(root::AbstractString, relpath::AbstractString)
    ap = joinpath(root, relpath)
    isfile(ap) || throw(ParseError("file not found: $relpath"))
    bytes = read(ap)
    isvalid(String, bytes) || throw(ParseError("file is not valid UTF-8: $relpath"))
    return String(bytes)
end

function _read_base_text(root::AbstractString, base::AbstractString, relpath::AbstractString)
    sha = git_resolve_commit_sha(root, base)
    git_tree_path_exists(root, sha, relpath) ||
        throw(ParseError("missing file at diff base: $relpath"))
    return git_show_blob_at_commit(root, sha, relpath)
end

function _parse_toml_policy!(text::AbstractString, label::AbstractString)
    return load_toml_string(String(text), label)
end

function _toml_equal(a, b)
    return a == b
end

"""
    project_toml_semantic_violations(base, head) -> Vector{String}

Semantic diff for protected `Project.toml` (0.1.0: compat compared by string equality only; no semver).
Allows new `[deps]` entries and new `[compat]` entries for those deps. Forbids `[sources]`, `[workspace]`,
compat removal/change, and any other top-level key change.
"""
function project_toml_semantic_violations(base::Dict, head::Dict)
    msgs = String[]
    base_deps = get(base, "deps", Dict{String, Any}())
    head_deps = get(head, "deps", Dict{String, Any}())
    base_compat = get(base, "compat", Dict{String, Any}())
    head_compat = get(head, "compat", Dict{String, Any}())

    new_dep_names = Set(String(k) for k in keys(head_deps) if !haskey(base_deps, k))
    for dep in keys(base_deps)
        String(dep) in keys(head_deps) || push!(msgs, "removed [deps] entry $(dep)")
        haskey(head_deps, dep) && !_toml_equal(base_deps[dep], head_deps[dep]) &&
            push!(msgs, "changed [deps] entry $(dep)")
    end

    for k in keys(head_compat)
        sk = String(k)
        if !haskey(base_compat, k)
            sk in new_dep_names || push!(msgs, "new [compat] for existing dep $(sk)")
            continue
        end
        b = string(base_compat[k])
        h = string(head_compat[k])
        b != h && push!(msgs, "[compat] loosening or change for $(sk) (strings differ)")
    end
    for k in keys(base_compat)
        haskey(head_compat, k) || push!(msgs, "removed [compat] for $(k)")
    end

    for section in ("sources", "workspace")
        b = get(base, section, nothing)
        h = get(head, section, nothing)
        !_toml_equal(b, h) && push!(msgs, "changed [$section]")
    end

    skip = Set(["deps", "compat", "sources", "workspace"])
    all_keys = union(Set(string(k) for k in keys(base)), Set(string(k) for k in keys(head)))
    for k in all_keys
        k in skip && continue
        bv = get(base, k, nothing)
        hv = get(head, k, nothing)
        !_toml_equal(bv, hv) && push!(msgs, "changed top-level key $k")
    end
    return msgs
end

function _ceilings_semantic_exempt!(root::AbstractString, base::AbstractString, policy::PolicyBundle)
    base_present, base_entry = load_ceilings_at_git_ref(root, base, policy)
    head_text = _read_working_text(root, CEILINGS_REL_PATH)
    head_entry = load_ceilings_string(head_text, policy, CEILINGS_REL_PATH)
    return !ceilings_increase_relative_to_base(head_entry, base_entry, base_present, policy)
end

function _project_toml_semantic_ok(
        root::AbstractString,
        base::AbstractString,
        relpath::AbstractString,
        st::Char,
        policy::PolicyBundle,
    )
    policy.project_toml_policy == "semantic" || return false
    if st == 'A'
        head = _parse_toml_policy!(_read_working_text(root, relpath), relpath)
        return isempty(project_toml_semantic_violations(Dict(), head))
    elseif st == 'D'
        return false
    end
    head = _parse_toml_policy!(_read_working_text(root, relpath), relpath)
    sha = git_resolve_commit_sha(root, base)
    if !git_tree_path_exists(root, sha, relpath)
        st == 'A' || throw(ParseError("missing Project.toml at diff base: $relpath"))
        return isempty(project_toml_semantic_violations(Dict(), head))
    end
    base_text = git_show_blob_at_commit(root, sha, relpath)
    base = _parse_toml_policy!(base_text, "$relpath@$base")
    return isempty(project_toml_semantic_violations(base, head))
end

function _protected_change_exempt(
        root::AbstractString,
        base::AbstractString,
        relpath::AbstractString,
        ev::DiffPathEvent,
        policy::PolicyBundle,
    )
    ev.status in ('R', 'C') && return false
    ev.status == 'D' && return false
    p = normalize_path(relpath)
    if p == CEILINGS_REL_PATH
        return _ceilings_semantic_exempt!(root, base, policy)
    end
    if _is_workspace_project_toml(p)
        return _project_toml_semantic_ok(root, base, p, ev.status, policy)
    end
    return false
end

function _handle_protected_event(
        root::AbstractString,
        base::AbstractString,
        ev::DiffPathEvent,
        policy::PolicyBundle,
    )
    out = Violation[]
    paths = ev.status in ('R', 'C') ? [ev.old_path, ev.path] : [ev.path]
    seen = Set{String}()
    for p in paths
        p in seen && continue
        push!(seen, p)
        matched, reason = classify_protected_path(p, policy)
        matched || continue
        if !_protected_change_exempt(root, base, p, ev, policy)
            word = _status_word(ev.status)
            msg = "$word (reason: $reason)"
            push!(out, _protected_paths_diag(p, msg, policy))
        end
    end
    return out
end

"""
    enforce_protected_paths(root, base, policy)

Diff-scoped enforcement only. Without a diff base the caller should not invoke this.
"""
function enforce_protected_paths(root::AbstractString, base::AbstractString, policy::PolicyBundle)
    get(policy.rules, PROTECTED_PATHS_RULE, nothing) === nothing && return Violation[]
    events = git_diff_path_events(root, base)
    out = Violation[]
    for ev in events
        append!(out, _handle_protected_event(root, base, ev, policy))
    end
    return out
end
