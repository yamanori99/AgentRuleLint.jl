using TOML

const CONFIG_FILENAME = ".AgentRuleLintConfig.toml"
const CEILINGS_REL = ".agentrulelint/ceilings.toml"

const TOP_LEVEL_CONFIG_KEYS = Set(
    [
        "agentrulelint_version",
        "default_format",
        "max_hits_per_rule",
        "presets",
        "project_rules",
    ]
)
const RULE_TABLE_KEYS = Set(["level", "intent", "do_not"])
const EXPECT_AUDIT_RULE_KEYS = Set(["level", "intent", "do_not", "on_allow_rule"])
const PROTECTED_PATHS_RULE_KEYS =
    Set(["level", "intent", "do_not", "project_toml_policy", "paths"])
const PROTECTED_PATHS_RULE = "protected-paths"
const CEILING_RATCHET_RULE = "ceiling-ratchet"
const SCOPE_PATHS_RULE = "scope-paths"
const INTEGRITY_FORBID_RULES =
    Set([PROTECTED_PATHS_RULE, CEILING_RATCHET_RULE, SCOPE_PATHS_RULE])
const DEFAULT_PROJECT_TOML_POLICY = "semantic"
const PROJECT_RULE_KEYS = Set(
    [
        "id",
        "level",
        "paths",
        "forbid_literals",
        "intent",
        "do_not",
    ]
)
const VALID_RULE_LEVELS = Set([:forbid, :deny, :allow, :warn])
const VALID_ON_ALLOW_RULE = Set([:error, :warn, :allow])
const VALID_OUTPUT_FORMATS = Set([:human, :json, :agent])
const KNOWN_PRESET_NAMES = Set(["shell-safety/process-pattern"])

function _reject_unknown_keys!(dict::Dict, allowed::Set{String}, label::String)
    for k in keys(dict)
        String(k) in allowed || throw(ConfigError("unknown key '$k' in $label"))
    end
    return nothing
end

function _parse_rule_level(raw, label::String)
    s = raw isa AbstractString ? lowercase(strip(raw)) : raw isa Symbol ? lowercase(string(raw)) : ""
    s == "" && throw(ConfigError("missing rule level in $label"))
    sym = Symbol(s)
    sym in VALID_RULE_LEVELS ||
        throw(ConfigError("unknown rule level '$raw' in $label (expected forbid|deny|allow|warn)"))
    return sym
end

function _parse_on_allow_rule(raw, label::String)
    s = raw isa AbstractString ? lowercase(strip(raw)) : ""
    sym = Symbol(s)
    sym in VALID_ON_ALLOW_RULE ||
        throw(
        ConfigError(
            "unknown on_allow_rule '$raw' in $label (expected error|warn|allow)",
        ),
    )
    return sym
end

function _parse_default_format(raw, label::String)
    s = raw isa AbstractString ? lowercase(strip(raw)) : ""
    sym = Symbol(s)
    sym in VALID_OUTPUT_FORMATS ||
        throw(ConfigError("unknown default_format '$raw' in $label (expected human|json|agent)"))
    return sym
end

function _parse_preset_list(raw, label::String)
    raw isa AbstractVector || throw(ConfigError("$label must be an array"))
    out = String[]
    for (i, p) in enumerate(raw)
        p isa AbstractString || throw(ConfigError("$label[$i] must be a string"))
        name = String(p)
        name in KNOWN_PRESET_NAMES ||
            throw(ConfigError("unknown preset '$name' in $label"))
        push!(out, name)
    end
    return out
end

_rule_level(s::AbstractString) = _parse_rule_level(s, "rule level")
_rule_level(s::Symbol) = s in VALID_RULE_LEVELS ? s : throw(ConfigError("unknown rule level '$s'"))

function _require_string(dict, key, path)
    haskey(dict, key) || throw(ConfigError("missing key '$key' in $path"))
    v = dict[key]
    v isa AbstractString || throw(ConfigError("expected string for '$key' in $path"))
    return String(v)
end

function _opt_string(dict, key, default = "")
    !haskey(dict, key) && return default
    v = dict[key]
    v isa AbstractString || throw(ConfigError("expected string for '$key'"))
    return String(v)
end

function _parse_version_pin(raw::AbstractString)
    s = strip(raw)
    startswith(s, "=") && return VersionNumber(s[2:end])
    return VersionNumber(s)
end

function validate_agentrulelint_version!(toml_version::VersionNumber, pkg::VersionNumber)
    pkg_major, pkg_minor = pkg.major, pkg.minor
    return if toml_version.major != pkg_major || toml_version.minor != pkg_minor
        throw(
            ConfigError(
                "agentrulelint_version pin $(toml_version) does not match AgentRuleLint $(pkg)",
            ),
        )
    end
end

function load_toml_string(toml_string::String, path_label::String)
    try
        return TOML.parse(toml_string)
    catch err
        throw(ParseError("TOML parse error in $path_label: $(err)"))
    end
end

function load_toml_file(path::String)
    isfile(path) || throw(ConfigError("config not found: $path"))
    try
        return TOML.parsefile(path)
    catch err
        throw(ParseError("TOML parse error in $path: $(err)"))
    end
end

function _collect_rule_tables(raw::Dict)
    out = Tuple{String, Dict}[]
    seen = Set{String}()
    if haskey(raw, "rules")
        box = raw["rules"]
        box isa Dict || throw(ConfigError("rules must be a table"))
        for (id, content) in box
            sid = String(id)
            sid in seen && throw(ConfigError("duplicate rules.$sid"))
            push!(seen, sid)
            content isa Dict || throw(ConfigError("rules.$sid must be a table"))
            push!(out, (sid, content))
        end
    end
    for (section, content) in raw
        startswith(section, "rules.") || continue
        id = section[7:end]
        id in seen && throw(ConfigError("duplicate rules.$id"))
        push!(seen, id)
        content isa Dict || throw(ConfigError("$section must be a table"))
        push!(out, (id, content))
    end
    return out
end

function _parse_protected_paths_globs(content::Dict, label::String)
    raw = get(content, "paths", [])
    raw isa AbstractVector || throw(ConfigError("$label.paths must be an array"))
    out = ProtectedGlobEntry[]
    for (j, entry) in enumerate(raw)
        sub = "rules.$label.paths[$j]"
        entry isa Dict || throw(ConfigError("$sub must be a table"))
        _reject_unknown_keys!(entry, Set(["glob", "reason"]), sub)
        glob = _require_string(entry, "glob", sub)
        reason = _require_string(entry, "reason", sub)
        rx = compile_path_glob(glob, sub)
        push!(out, ProtectedGlobEntry(rx, reason))
    end
    return out
end

function _parse_project_toml_policy(raw, label::String)
    s = strip(raw isa AbstractString ? String(raw) : "")
    s == DEFAULT_PROJECT_TOML_POLICY && return DEFAULT_PROJECT_TOML_POLICY
    throw(ConfigError("unknown project_toml_policy '$raw' in $label (expected semantic)"))
end

function _load_rules_table(raw::Dict)
    rules = Dict{String, RuleSpec}()
    for (id, content) in _collect_rule_tables(raw)
        validate_kebab_rule_id(id, "rules.$id")
        allowed = if id == "expect-audit"
            EXPECT_AUDIT_RULE_KEYS
        elseif id == PROTECTED_PATHS_RULE
            PROTECTED_PATHS_RULE_KEYS
        else
            RULE_TABLE_KEYS
        end
        _reject_unknown_keys!(content, allowed, "rules.$id")
        level = haskey(content, "level") ?
            _parse_rule_level(content["level"], "rules.$id.level") : :deny
        if id in INTEGRITY_FORBID_RULES && level != :forbid
            throw(
                ConfigError(
                    "rules.$id.level must be forbid (integrity rules cannot be weakened)",
                ),
            )
        end
        intent = _opt_string(content, "intent")
        do_not = _opt_string(content, "do_not")
        eff_level = id in INTEGRITY_FORBID_RULES ? :forbid : level
        rules[id] = RuleSpec(id, :agentrulelint, eff_level, intent, do_not, Dict{Symbol, String}())
    end
    return rules
end

function _inject_builtin_rules!(rules::Dict{String, RuleSpec})
    if get(rules, PROTECTED_PATHS_RULE, nothing) === nothing
        rules[PROTECTED_PATHS_RULE] = RuleSpec(
            PROTECTED_PATHS_RULE,
            :agentrulelint,
            :forbid,
            "Protect designated policy, lockfiles, and workflow paths from silent edits.",
            "Edit protected files, weaken compat, or rename paths to evade review.",
            Dict{Symbol, String}(),
        )
    end
    if get(rules, "ceiling-ratchet", nothing) === nothing
        rules["ceiling-ratchet"] = RuleSpec(
            "ceiling-ratchet",
            :agentrulelint,
            :forbid,
            "Keep violation and expect ceilings monotonic (down only).",
            "Raise ceilings or leave stale slack after counts decrease.",
            Dict{Symbol, String}(),
        )
    end
    if get(rules, "scope-paths", nothing) === nothing
        rules["scope-paths"] = RuleSpec(
            "scope-paths",
            :agentrulelint,
            :forbid,
            "Reject diff changes outside a trusted path allowlist.",
            "Edit files outside --allow-paths scope passed from CI or a human wrapper.",
            Dict{Symbol, String}(),
        )
    end
    return nothing
end

function _protected_paths_config(raw::Dict, rules::Dict{String, RuleSpec})
    spec = get(rules, PROTECTED_PATHS_RULE, nothing)
    spec === nothing &&
        return DEFAULT_PROJECT_TOML_POLICY, ProtectedGlobEntry[]
    content = nothing
    for (id, c) in _collect_rule_tables(raw)
        id == PROTECTED_PATHS_RULE && (content = c; break)
    end
    content === nothing && return DEFAULT_PROJECT_TOML_POLICY, ProtectedGlobEntry[]
    pol = if haskey(content, "project_toml_policy")
        _parse_project_toml_policy(content["project_toml_policy"], "rules.$PROTECTED_PATHS_RULE")
    else
        DEFAULT_PROJECT_TOML_POLICY
    end
    globs = _parse_protected_paths_globs(content, PROTECTED_PATHS_RULE)
    return pol, globs
end

function _expect_audit_table(raw::Dict)
    for (id, content) in _collect_rule_tables(raw)
        id == "expect-audit" && return content
    end
    return nothing
end

# `paths` globs are compiled at load (see `path_glob.jl`); they select every file
# type for `forbid_literals`, not only `.jl`.
function _load_project_rules(raw::Vector)
    out = ProjectRule[]
    for (i, entry) in enumerate(raw)
        entry isa Dict || throw(ConfigError("project_rules[$i] must be a table"))
        label = "project_rules[$i]"
        _reject_unknown_keys!(entry, PROJECT_RULE_KEYS, label)
        id = validate_kebab_rule_id(_require_string(entry, "id", label), label)
        level = haskey(entry, "level") ? _parse_rule_level(entry["level"], "$label.level") : :deny
        paths_raw = get(entry, "paths", String[])
        paths_raw isa AbstractVector || throw(ConfigError("$label.paths must be an array"))
        paths = String[]
        for (j, p) in enumerate(paths_raw)
            p isa AbstractString || throw(ConfigError("$label.paths[$j] must be a string"))
            push!(paths, String(p))
        end
        literals_raw = get(entry, "forbid_literals", String[])
        literals_raw isa AbstractVector || throw(ConfigError("$label.forbid_literals must be an array"))
        literals = String[]
        for (j, l) in enumerate(literals_raw)
            l isa AbstractString || throw(ConfigError("$label.forbid_literals[$j] must be a string"))
            push!(literals, String(l))
        end
        intent = _opt_string(entry, "intent")
        do_not = _opt_string(entry, "do_not")
        path_regexes = Regex[]
        for (j, p) in enumerate(paths)
            push!(path_regexes, compile_path_glob(p, "$label.paths[$j]"))
        end
        push!(out, ProjectRule(id, level, paths, path_regexes, literals, intent, do_not))
    end
    return out
end

function _reject_unknown_top_level!(raw::Dict)
    for (k, v) in raw
        sk = String(k)
        if sk in TOP_LEVEL_CONFIG_KEYS
            continue
        elseif sk == "rules"
            v isa Dict || throw(ConfigError("rules must be a table"))
            continue
        elseif startswith(sk, "rules.")
            v isa Dict || throw(ConfigError("$sk must be a table"))
            continue
        end
        throw(ConfigError("unknown config key '$sk' in $CONFIG_FILENAME"))
    end
    return nothing
end

function build_policy(raw::Dict, config_path::String, config_source::ConfigSource)
    _reject_unknown_top_level!(raw)
    ver_raw = _require_string(raw, "agentrulelint_version", CONFIG_FILENAME)
    ver = _parse_version_pin(ver_raw)
    validate_agentrulelint_version!(ver, AGENTRULELINT_VERSION)
    fmt = if haskey(raw, "default_format")
        _parse_default_format(raw["default_format"], CONFIG_FILENAME)
    else
        :human
    end
    max_hits = if haskey(raw, "max_hits_per_rule")
        v = raw["max_hits_per_rule"]
        v isa Integer || throw(ConfigError("max_hits_per_rule must be an integer"))
        Int(v)
    else
        20
    end
    presets = if haskey(raw, "presets")
        _parse_preset_list(raw["presets"], "presets")
    else
        String[]
    end
    rules = _load_rules_table(raw)
    _inject_builtin_rules!(rules)
    pr_raw = get(raw, "project_rules", [])
    pr_raw isa AbstractVector || throw(ConfigError("project_rules must be an array"))
    project = _load_project_rules(pr_raw)
    on_allow = :warn
    es = _expect_audit_table(raw)
    if es !== nothing && haskey(es, "on_allow_rule")
        on_allow = _parse_on_allow_rule(es["on_allow_rule"], "rules.expect-audit.on_allow_rule")
    end
    ptp, pglobs = _protected_paths_config(raw, rules)
    return PolicyBundle(
        ver,
        fmt,
        max_hits,
        presets,
        rules,
        project,
        on_allow,
        config_path,
        config_source,
        ptp,
        pglobs,
    )
end

function policy_from_dict(raw::Dict, config_path::String; config_source = ConfigSource())
    return build_policy(raw, config_path, config_source)
end

function load_policy(root::AbstractString; config_path = nothing)
    root = abspath(String(root))
    cfg = something(config_path, joinpath(root, CONFIG_FILENAME))
    raw = load_toml_file(cfg)
    rel = relpath(cfg, root)
    cs = ConfigSource(:path, rel, "", "")
    return policy_from_dict(raw, cfg; config_source = cs)
end

function git_resolve_commit_sha(root::AbstractString, ref::AbstractString)
    root = abspath(String(root))
    spec = string(ref, "^{commit}")
    cmd = Cmd(["git", "-C", root, "rev-parse", "--verify", "--end-of-options", spec])
    try
        return strip(String(read(cmd)))
    catch err
        err isa InterruptException && rethrow()
        ref_s = String(ref)
        if ref_s == "HEAD^1"
            throw(GitError("diff base ref not available: HEAD^1 (shallow clone or single-parent HEAD)"))
        end
        throw(GitError("diff base ref not available: $ref_s"))
    end
end

function git_tree_path_exists(root::AbstractString, commit_sha::AbstractString, relpath::AbstractString)
    root = abspath(String(root))
    cmd = Cmd(
        [
            "git",
            "-C",
            root,
            "ls-tree",
            "--name-only",
            "-z",
            "--end-of-options",
            String(commit_sha),
            "--",
            String(relpath),
        ]
    )
    try
        return !isempty(read(cmd))
    catch err
        err isa InterruptException && rethrow()
        throw(
            GitError(
                "failed to list $(relpath) at commit $(commit_sha): $(sprint(showerror, err))",
            ),
        )
    end
end

function git_show_blob_at_commit(root::AbstractString, commit_sha::AbstractString, relpath::AbstractString)
    root = abspath(String(root))
    showspec = string(commit_sha, ":", relpath)
    cmd = Cmd(["git", "-C", root, "show", "--end-of-options", showspec])
    try
        return String(strip(String(read(cmd))))
    catch err
        err isa InterruptException && rethrow()
        throw(
            GitError(
                "failed to read $(relpath) at commit $(commit_sha): $(sprint(showerror, err))",
            ),
        )
    end
end

function git_show_file(ref::AbstractString, relpath::AbstractString, root::AbstractString)
    root = abspath(String(root))
    sha = git_resolve_commit_sha(root, ref)
    text = git_show_blob_at_commit(root, sha, relpath)
    return text, sha
end

function load_policy_from_ref(root::AbstractString, ref::AbstractString)
    root = abspath(String(root))
    try
        cfg_text, sha = git_show_file(ref, CONFIG_FILENAME, root)
        raw = load_toml_string(cfg_text, "$CONFIG_FILENAME@$ref")
        cs = ConfigSource(:git_ref, CONFIG_FILENAME, String(ref), sha)
        cfg_path = joinpath(root, CONFIG_FILENAME)
        return build_policy(raw, cfg_path, cs)
    catch err
        if err isa InterruptException
            rethrow()
        elseif err isa ConfigError || err isa ParseError
            rethrow()
        elseif err isa ErrorException || err isa GitError
            rethrow()
        else
            throw(GitError("failed loading policy from ref $(ref): $(err)"))
        end
    end
end

function default_policy(root::AbstractString)
    ver = AGENTRULELINT_VERSION
    rules = Dict{String, RuleSpec}(
        "expect-audit" => RuleSpec(
            "expect-audit",
            :agentrulelint,
            :forbid,
            "Keep suppression comments auditable and fail-closed.",
            "Use inline or block comment expects to hide violations.",
            Dict{Symbol, String}(),
        ),
        "ceiling-ratchet" => RuleSpec(
            "ceiling-ratchet",
            :agentrulelint,
            :forbid,
            "Keep violation and expect ceilings monotonic (down only).",
            "Raise ceilings or leave stale slack after counts decrease.",
            Dict{Symbol, String}(),
        ),
        PROTECTED_PATHS_RULE => RuleSpec(
            PROTECTED_PATHS_RULE,
            :agentrulelint,
            :forbid,
            "Protect designated policy, lockfiles, and workflow paths from silent edits.",
            "Edit protected files, weaken compat, or rename paths to evade review.",
            Dict{Symbol, String}(),
        ),
    )
    cs = ConfigSource(:builtin, "", "", "")
    cfg = joinpath(abspath(root), CONFIG_FILENAME)
    return PolicyBundle(
        ver,
        :human,
        20,
        String[],
        rules,
        ProjectRule[],
        :warn,
        cfg,
        cs,
        DEFAULT_PROJECT_TOML_POLICY,
        ProtectedGlobEntry[],
    )
end

function resolve_policy(root::AbstractString; config_path = nothing, config_from = nothing)
    if config_from !== nothing
        return load_policy_from_ref(root, config_from)
    end
    cfg = something(config_path, joinpath(abspath(root), CONFIG_FILENAME))
    if isfile(cfg)
        return load_policy(root; config_path = cfg)
    end
    return default_policy(root)
end
