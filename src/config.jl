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

function _load_rules_table(raw::Dict)
    rules = Dict{String, RuleSpec}()
    for (id, content) in _collect_rule_tables(raw)
        validate_kebab_rule_id(id, "rules.$id")
        allowed = id == "expect-audit" ? EXPECT_AUDIT_RULE_KEYS : RULE_TABLE_KEYS
        _reject_unknown_keys!(content, allowed, "rules.$id")
        level = haskey(content, "level") ?
            _parse_rule_level(content["level"], "rules.$id.level") : :deny
        intent = _opt_string(content, "intent")
        do_not = _opt_string(content, "do_not")
        rules[id] = RuleSpec(id, :agentrulelint, level, intent, do_not, Dict{Symbol, String}())
    end
    return rules
end

function _expect_audit_table(raw::Dict)
    for (id, content) in _collect_rule_tables(raw)
        id == "expect-audit" && return content
    end
    return nothing
end

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
        push!(out, ProjectRule(id, level, paths, literals, intent, do_not))
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
    pr_raw = get(raw, "project_rules", [])
    pr_raw isa AbstractVector || throw(ConfigError("project_rules must be an array"))
    project = _load_project_rules(pr_raw)
    on_allow = :warn
    es = _expect_audit_table(raw)
    if es !== nothing && haskey(es, "on_allow_rule")
        on_allow = _parse_on_allow_rule(es["on_allow_rule"], "rules.expect-audit.on_allow_rule")
    end
    return PolicyBundle(ver, fmt, max_hits, presets, rules, project, on_allow, config_path, config_source)
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

"""Load `.agentrulelint/ceilings.toml`. Enforcement (`ceiling-ratchet`) is not wired in `run_check` yet."""
function load_ceilings(root::AbstractString)
    path = joinpath(abspath(root), CEILINGS_REL)
    !isfile(path) && return CeilingEntry(Dict(), Dict())
    raw = load_toml_file(path)
    viol = Dict{String, Dict{String, Int}}()
    for (k, v) in raw
        startswith(k, "violations.") || continue
        rid = k[12:end]
        viol[rid] = Dict{String, Int}(String(p) => Int(c) for (p, c) in v)
    end
    exp = Dict{String, Dict{String, Int}}()
    for (k, v) in raw
        startswith(k, "expects.") || continue
        rid = k[9:end]
        exp[rid] = Dict{String, Int}(String(p) => Int(c) for (p, c) in v)
    end
    return CeilingEntry(viol, exp)
end

function git_show_file(ref::AbstractString, relpath::AbstractString, root::AbstractString)
    root = abspath(String(root))
    reff = string(ref, "^{commit}")
    sha_cmd = Cmd(["git", "-C", root, "rev-parse", "--verify", "--end-of-options", reff])
    sha = strip(String(read(sha_cmd)))
    showspec = string(sha, ":", relpath)
    show_cmd = Cmd(["git", "-C", root, "show", "--end-of-options", showspec])
    return String(strip(String(read(show_cmd)))), sha
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

function _legacy_config_path(root::AbstractString)
    return joinpath(abspath(root), "." * "JAI" * "LintConfig.toml")
end

function _reject_legacy_config!(root::AbstractString)
    legacy = _legacy_config_path(root)
    new_cfg = joinpath(abspath(root), CONFIG_FILENAME)
    if isfile(legacy) && !isfile(new_cfg)
        throw(ConfigError("legacy config file present; rename it to $(CONFIG_FILENAME)"))
    end
    return nothing
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
    _reject_legacy_config!(root)
    return default_policy(root)
end
